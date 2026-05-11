import Foundation

private let modelKey = "model"
private let reasoningEffortKey = "reasoning_effort"
private let turnStartedAtUnixMsKey = "turn_started_at_unix_ms"

public func buildTurnMetadataHeader(cwd: URL, sandbox: String? = nil) -> String? {
    let repoRoot = GitInfoCollector.gitRepoRoot(baseDir: cwd)?.path
    let workspaceGitMetadata = WorkspaceGitMetadata.collect(cwd: cwd)

    if workspaceGitMetadata.isEmpty,
       sandbox == nil
    {
        return nil
    }

    return TurnMetadataState.asciiJSONString(
        TurnMetadataState.buildTurnMetadataBag(
            sessionID: nil,
            threadID: nil,
            threadSource: nil,
            turnID: nil,
            sandbox: sandbox,
            repoRoot: repoRoot,
            workspaceGitMetadata: workspaceGitMetadata
        )
    )
}

public struct McpTurnMetadataContext: Equatable, Sendable {
    public let model: String
    public let reasoningEffort: ReasoningEffort?

    public init(model: String, reasoningEffort: ReasoningEffort? = nil) {
        self.model = model
        self.reasoningEffort = reasoningEffort
    }
}

/// Mutable per-turn metadata shared across request builders; all mutable fields are guarded by
/// `lock`, so callers can read or update the header state across concurrency domains.
public final class TurnMetadataState: @unchecked Sendable {
    private let cwd: URL?
    private let repoRoot: String?
    private let baseMetadata: [String: Any]
    private let baseHeader: String
    private let lock = NSLock()
    private var enrichedHeader: String?
    private var turnStartedAtUnixMs: Int64?
    private var responsesAPIClientMetadata: [String: String]?
    private var enrichmentTask: Task<Void, Never>?

    public init(
        sessionID: String,
        threadID: String,
        threadSource: ThreadSource?,
        turnID: String,
        cwd: URL? = nil,
        sandbox: String? = nil
    ) {
        self.cwd = cwd
        repoRoot = cwd.flatMap { GitInfoCollector.gitRepoRoot(baseDir: $0)?.path }
        let metadata = Self.buildTurnMetadataBag(
            sessionID: sessionID,
            threadID: threadID,
            threadSource: threadSource,
            turnID: turnID,
            sandbox: sandbox
        )
        baseMetadata = metadata
        baseHeader = Self.asciiJSONString(metadata) ?? "{}"
    }

    public func currentHeaderValue() -> String? {
        let header: String
        let startedAt: Int64?
        let clientMetadata: [String: String]?
        lock.lock()
        header = enrichedHeader ?? baseHeader
        startedAt = turnStartedAtUnixMs
        clientMetadata = responsesAPIClientMetadata
        lock.unlock()
        return Self.mergingTurnMetadata(
            header: header,
            turnStartedAtUnixMs: startedAt,
            responsesAPIClientMetadata: clientMetadata
        ) ?? header
    }

    public func currentMetaValueForMcpRequest(context: McpTurnMetadataContext) -> JSONValue? {
        guard let header = currentHeaderValue(),
              var metadata = Self.jsonObject(from: header)
        else {
            return nil
        }
        metadata[modelKey] = context.model
        if let reasoningEffort = context.reasoningEffort {
            metadata[reasoningEffortKey] = reasoningEffort.rawValue
        } else {
            metadata.removeValue(forKey: reasoningEffortKey)
        }
        guard let data = try? JSONSerialization.data(withJSONObject: metadata, options: [.sortedKeys]) else {
            return nil
        }
        return try? JSONDecoder().decode(JSONValue.self, from: data)
    }

    public func setResponsesAPIClientMetadata(_ metadata: [String: String]) {
        lock.lock()
        responsesAPIClientMetadata = metadata
        lock.unlock()
    }

    public func setTurnStartedAtUnixMs(_ value: Int64) {
        lock.lock()
        turnStartedAtUnixMs = value
        lock.unlock()
    }

    public func spawnGitEnrichmentTask() {
        guard let cwd, let repoRoot else {
            return
        }

        lock.lock()
        if enrichmentTask != nil {
            lock.unlock()
            return
        }
        let baseMetadata = self.baseMetadata
        enrichmentTask = Task { [weak self] in
            let workspaceGitMetadata = WorkspaceGitMetadata.collect(cwd: cwd)
            guard !Task.isCancelled,
                  !workspaceGitMetadata.isEmpty,
                  let headerValue = Self.asciiJSONString(Self.buildTurnMetadataBag(
                    baseMetadata: baseMetadata,
                    repoRoot: repoRoot,
                    workspaceGitMetadata: workspaceGitMetadata
                  ))
            else {
                return
            }

            guard let self else {
                return
            }
            self.setEnrichedHeaderIfNotCancelled(headerValue)
        }
        lock.unlock()
    }

    public func cancelGitEnrichmentTask() {
        lock.lock()
        let task = enrichmentTask
        enrichmentTask = nil
        lock.unlock()
        task?.cancel()
    }

    private func setEnrichedHeaderIfNotCancelled(_ headerValue: String) {
        lock.lock()
        if !Task.isCancelled {
            enrichedHeader = headerValue
        }
        lock.unlock()
    }

    private static func mergingTurnMetadata(
        header: String,
        turnStartedAtUnixMs: Int64?,
        responsesAPIClientMetadata: [String: String]?
    ) -> String? {
        guard turnStartedAtUnixMs != nil || responsesAPIClientMetadata != nil,
              var metadata = jsonObject(from: header)
        else {
            return nil
        }
        if let turnStartedAtUnixMs {
            metadata[turnStartedAtUnixMsKey] = turnStartedAtUnixMs
        }
        if let responsesAPIClientMetadata {
            for (key, value) in responsesAPIClientMetadata where key != turnStartedAtUnixMsKey {
                if metadata[key] == nil {
                    metadata[key] = value
                }
            }
        }
        return asciiJSONString(metadata)
    }

    private static func jsonObject(from string: String) -> [String: Any]? {
        guard let data = string.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }
        return object
    }

    fileprivate static func buildTurnMetadataBag(
        sessionID: String?,
        threadID: String?,
        threadSource: ThreadSource?,
        turnID: String?,
        sandbox: String?,
        repoRoot: String? = nil,
        workspaceGitMetadata: WorkspaceGitMetadata? = nil
    ) -> [String: Any] {
        var metadata: [String: Any] = [:]
        if let sessionID {
            metadata["session_id"] = sessionID
        }
        if let threadID {
            metadata["thread_id"] = threadID
        }
        if let threadSource {
            metadata["thread_source"] = threadSource.rawValue
        }
        if let turnID {
            metadata["turn_id"] = turnID
        }
        if let sandbox {
            metadata["sandbox"] = sandbox
        }
        if let repoRoot,
           let workspace = workspaceGitMetadata?.jsonObject,
           !workspace.isEmpty
        {
            metadata["workspaces"] = [repoRoot: workspace]
        }
        return metadata
    }

    fileprivate static func buildTurnMetadataBag(
        baseMetadata: [String: Any],
        repoRoot: String,
        workspaceGitMetadata: WorkspaceGitMetadata
    ) -> [String: Any] {
        var metadata = baseMetadata
        if !workspaceGitMetadata.isEmpty {
            metadata["workspaces"] = [repoRoot: workspaceGitMetadata.jsonObject]
        }
        return metadata
    }

    fileprivate static func asciiJSONString(_ object: [String: Any]) -> String? {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8)
        else {
            return nil
        }
        return json.unicodeScalars.map(asciiEscaped).joined()
    }

    private static func asciiEscaped(_ scalar: UnicodeScalar) -> String {
        switch scalar.value {
        case 0x00...0x7F:
            return String(scalar)
        case 0x80...0xFFFF:
            return String(format: "\\u%04X", scalar.value)
        default:
            let value = scalar.value - 0x10000
            let high = 0xD800 + (value >> 10)
            let low = 0xDC00 + (value & 0x3FF)
            return String(format: "\\u%04X\\u%04X", high, low)
        }
    }
}

fileprivate struct WorkspaceGitMetadata {
    let associatedRemoteURLs: [String: String]?
    let latestGitCommitHash: String?
    let hasChanges: Bool?

    static func collect(cwd: URL) -> WorkspaceGitMetadata {
        WorkspaceGitMetadata(
            associatedRemoteURLs: GitInfoCollector.remoteURLsByNameAssumingGitRepo(cwd: cwd),
            latestGitCommitHash: GitInfoCollector.headCommitHash(cwd: cwd),
            hasChanges: GitInfoCollector.hasChanges(cwd: cwd)
        )
    }

    var isEmpty: Bool {
        associatedRemoteURLs == nil && latestGitCommitHash == nil && hasChanges == nil
    }

    var jsonObject: [String: Any] {
        var object: [String: Any] = [:]
        if let associatedRemoteURLs {
            object["associated_remote_urls"] = associatedRemoteURLs
        }
        if let latestGitCommitHash {
            object["latest_git_commit_hash"] = latestGitCommitHash
        }
        if let hasChanges {
            object["has_changes"] = hasChanges
        }
        return object
    }
}
