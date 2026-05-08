import CryptoKit
import Foundation

public struct AcceptedLineFingerprint: Equatable, Codable, Sendable {
    public let pathHash: String
    public let lineHash: String

    public init(pathHash: String, lineHash: String) {
        self.pathHash = pathHash
        self.lineHash = lineHash
    }

    private enum CodingKeys: String, CodingKey {
        case pathHash = "path_hash"
        case lineHash = "line_hash"
    }
}

public struct AcceptedLineFingerprintSummary: Equatable, Sendable {
    public let acceptedAddedLines: UInt64
    public let acceptedDeletedLines: UInt64
    public let lineFingerprints: [AcceptedLineFingerprint]

    public init(
        acceptedAddedLines: UInt64,
        acceptedDeletedLines: UInt64,
        lineFingerprints: [AcceptedLineFingerprint]
    ) {
        self.acceptedAddedLines = acceptedAddedLines
        self.acceptedDeletedLines = acceptedDeletedLines
        self.lineFingerprints = lineFingerprints
    }
}

public struct AcceptedLineFingerprintEventInput: Equatable, Sendable {
    public let eventType: String
    public let turnID: String
    public let threadID: String
    public let productSurface: String?
    public let modelSlug: String?
    public let completedAt: UInt64
    public let repoHash: String?
    public let acceptedAddedLines: UInt64
    public let acceptedDeletedLines: UInt64
    public let lineFingerprints: [AcceptedLineFingerprint]

    public init(
        eventType: String,
        turnID: String,
        threadID: String,
        productSurface: String? = nil,
        modelSlug: String? = nil,
        completedAt: UInt64,
        repoHash: String? = nil,
        acceptedAddedLines: UInt64,
        acceptedDeletedLines: UInt64,
        lineFingerprints: [AcceptedLineFingerprint]
    ) {
        self.eventType = eventType
        self.turnID = turnID
        self.threadID = threadID
        self.productSurface = productSurface
        self.modelSlug = modelSlug
        self.completedAt = completedAt
        self.repoHash = repoHash
        self.acceptedAddedLines = acceptedAddedLines
        self.acceptedDeletedLines = acceptedDeletedLines
        self.lineFingerprints = lineFingerprints
    }
}

public struct AcceptedLineFingerprintsEventParams: Equatable, Codable, Sendable {
    public let eventType: String
    public let turnID: String
    public let threadID: String
    public let productSurface: String?
    public let modelSlug: String?
    public let completedAt: UInt64
    public let repoHash: String?
    public let acceptedAddedLines: UInt64
    public let acceptedDeletedLines: UInt64
    public let lineFingerprints: [AcceptedLineFingerprint]

    private enum CodingKeys: String, CodingKey {
        case eventType = "event_type"
        case turnID = "turn_id"
        case threadID = "thread_id"
        case productSurface = "product_surface"
        case modelSlug = "model_slug"
        case completedAt = "completed_at"
        case repoHash = "repo_hash"
        case acceptedAddedLines = "accepted_added_lines"
        case acceptedDeletedLines = "accepted_deleted_lines"
        case lineFingerprints = "line_fingerprints"
    }
}

public struct AcceptedLineFingerprintsEventRequest: Equatable, Codable, Sendable {
    public let eventType: String
    public let eventParams: AcceptedLineFingerprintsEventParams

    public var shouldSendInIsolatedRequest: Bool {
        true
    }

    public init(eventParams: AcceptedLineFingerprintsEventParams) {
        self.eventType = "codex_accepted_line_fingerprints"
        self.eventParams = eventParams
    }

    private enum CodingKeys: String, CodingKey {
        case eventType = "event_type"
        case eventParams = "event_params"
    }
}

public struct AcceptedLineFingerprintReducer {
    private struct TurnState {
        var threadID: String?
        var modelSlug: String?
        var cwd: URL?
        var latestDiff: String?
    }

    private var turns: [String: TurnState] = [:]
    private let repoHashResolver: (URL) -> String?

    public init(repoHashResolver: @escaping (URL) -> String? = { AcceptedLines.acceptedLineRepoHash(cwd: $0) }) {
        self.repoHashResolver = repoHashResolver
    }

    public mutating func ingestResolvedTurn(
        turnID: String,
        threadID: String,
        modelSlug: String,
        cwd: URL
    ) {
        updateTurn(turnID) { state in
            state.threadID = threadID
            state.modelSlug = modelSlug
            state.cwd = cwd
        }
    }

    public mutating func ingestTurnDiff(threadID: String, turnID: String, unifiedDiff: String) {
        updateTurn(turnID) { state in
            state.threadID = threadID
            state.latestDiff = unifiedDiff
        }
    }

    public mutating func completeTurn(
        turnID: String,
        completedAt: UInt64
    ) -> [AcceptedLineFingerprintsEventRequest] {
        defer { turns.removeValue(forKey: turnID) }

        guard let state = turns[turnID],
              let latestDiff = state.latestDiff,
              let threadID = state.threadID,
              let modelSlug = state.modelSlug,
              let cwd = state.cwd
        else {
            return []
        }

        let summary = AcceptedLines.acceptedLineFingerprints(fromUnifiedDiff: latestDiff)
        if summary.acceptedAddedLines == 0 && summary.acceptedDeletedLines == 0 {
            return []
        }

        return AcceptedLines.acceptedLineFingerprintEventRequests(input: AcceptedLineFingerprintEventInput(
            eventType: "codex.accepted_line_fingerprints",
            turnID: turnID,
            threadID: threadID,
            productSurface: "codex",
            modelSlug: modelSlug,
            completedAt: completedAt,
            repoHash: repoHashResolver(cwd),
            acceptedAddedLines: summary.acceptedAddedLines,
            acceptedDeletedLines: summary.acceptedDeletedLines,
            lineFingerprints: summary.lineFingerprints
        ))
    }

    private mutating func updateTurn(_ turnID: String, _ body: (inout TurnState) -> Void) {
        var state = turns[turnID] ?? TurnState()
        body(&state)
        turns[turnID] = state
    }
}

public enum AcceptedLines {
    public static let eventTargetBytes = 2 * 1024 * 1024
    public static let eventFixedBytes = 1024

    public static func acceptedLineFingerprints(fromUnifiedDiff unifiedDiff: String) -> AcceptedLineFingerprintSummary {
        var currentPath: String?
        var inHunk = false
        var acceptedAddedLines: UInt64 = 0
        var acceptedDeletedLines: UInt64 = 0
        var lineFingerprints: [AcceptedLineFingerprint] = []

        for line in unifiedDiff.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            if line.hasPrefix("diff --git ") {
                currentPath = nil
                inHunk = false
                continue
            }

            if line.hasPrefix("@@ ") {
                inHunk = true
                continue
            }

            if !inHunk, let path = line.stripPrefix("+++ ") {
                currentPath = normalizeDiffPath(path)
                continue
            }

            if !inHunk, line.hasPrefix("--- ") {
                continue
            }

            if let addedLine = line.stripPrefix("+") {
                acceptedAddedLines += 1
                if let currentPath,
                   let normalizedLine = normalizeEffectiveLine(addedLine)
                {
                    lineFingerprints.append(AcceptedLineFingerprint(
                        pathHash: fingerprintHash(domain: "path", value: currentPath),
                        lineHash: fingerprintHash(domain: "line", value: normalizedLine)
                    ))
                }
                continue
            }

            if line.hasPrefix("-") {
                acceptedDeletedLines += 1
            }
        }

        return AcceptedLineFingerprintSummary(
            acceptedAddedLines: acceptedAddedLines,
            acceptedDeletedLines: acceptedDeletedLines,
            lineFingerprints: lineFingerprints
        )
    }

    public static func fingerprintHash(domain: String, value: String) -> String {
        var data = Data("file-line-v1\0".utf8)
        data.append(Data(domain.utf8))
        data.append(0)
        data.append(Data(value.utf8))
        return Insecure.SHA1.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    public static func acceptedLineFingerprintEventRequests(
        input: AcceptedLineFingerprintEventInput
    ) -> [AcceptedLineFingerprintsEventRequest] {
        acceptedLineFingerprintChunks(input.lineFingerprints).enumerated().map { index, lineFingerprints in
            let isFirstChunk = index == 0
            return AcceptedLineFingerprintsEventRequest(eventParams: AcceptedLineFingerprintsEventParams(
                eventType: input.eventType,
                turnID: input.turnID,
                threadID: input.threadID,
                productSurface: input.productSurface,
                modelSlug: input.modelSlug,
                completedAt: input.completedAt,
                repoHash: input.repoHash,
                acceptedAddedLines: isFirstChunk ? input.acceptedAddedLines : 0,
                acceptedDeletedLines: isFirstChunk ? input.acceptedDeletedLines : 0,
                lineFingerprints: lineFingerprints
            ))
        }
    }

    public static func acceptedLineRepoHash(cwd: URL) -> String? {
        guard let remotes = GitInfoCollector.remoteURLsByNameAssumingGitRepo(cwd: cwd) else {
            return nil
        }

        let remoteURL = remotes["origin"] ?? remotes.keys.sorted().first.flatMap { remotes[$0] }
        guard let remoteURL else {
            return nil
        }
        let canonical = GitInfoCollector.canonicalizeGitRemoteURL(remoteURL) ?? remoteURL
        return fingerprintHash(domain: "repo", value: canonical)
    }

    private static func normalizeDiffPath(_ path: String) -> String? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "/dev/null" {
            return nil
        }

        return trimmed
            .stripPrefix("b/")
            ?? trimmed.stripPrefix("a/")
            ?? trimmed
    }

    private static func normalizeEffectiveLine(_ line: String) -> String? {
        let normalized = line.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        if normalized.count <= 3 {
            return nil
        }
        if !normalized.contains(where: { character in
            character.isLetter || character.isNumber || character == "_"
        }) {
            return nil
        }
        return normalized
    }

    private static func acceptedLineFingerprintChunks(
        _ lineFingerprints: [AcceptedLineFingerprint]
    ) -> [[AcceptedLineFingerprint]] {
        if lineFingerprints.isEmpty {
            return [[]]
        }

        var chunks: [[AcceptedLineFingerprint]] = []
        var current: [AcceptedLineFingerprint] = []
        var currentBytes = eventFixedBytes

        for fingerprint in lineFingerprints {
            let itemBytes = acceptedLineFingerprintJSONBytes(fingerprint)
            let separatorBytes = current.isEmpty ? 0 : 1
            if !current.isEmpty,
               currentBytes + separatorBytes + itemBytes > eventTargetBytes
            {
                chunks.append(current)
                current = []
                currentBytes = eventFixedBytes
            }
            currentBytes += (current.isEmpty ? 0 : 1) + itemBytes
            current.append(fingerprint)
        }

        if !current.isEmpty {
            chunks.append(current)
        }
        return chunks
    }

    private static func acceptedLineFingerprintJSONBytes(_ fingerprint: AcceptedLineFingerprint) -> Int {
        32 + fingerprint.pathHash.count + fingerprint.lineHash.count
    }
}

private extension String {
    func stripPrefix(_ prefix: String) -> String? {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)) : nil
    }
}
