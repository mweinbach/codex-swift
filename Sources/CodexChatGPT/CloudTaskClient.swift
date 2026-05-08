import CodexCore
import Foundation

public struct CloudTaskClientConfiguration: Equatable, Sendable {
    public static let defaultBaseURL = CodexConfigDefaults.chatgptBaseURL

    public let chatgptBaseURL: String
    public let codexHome: URL
    public let authCredentialsStoreMode: AuthCredentialsStoreMode

    public init(
        chatgptBaseURL: String = Self.defaultBaseURL,
        codexHome: URL,
        authCredentialsStoreMode: AuthCredentialsStoreMode = .file
    ) {
        self.chatgptBaseURL = chatgptBaseURL
        self.codexHome = codexHome
        self.authCredentialsStoreMode = authCredentialsStoreMode
    }
}

public enum CloudTaskClientError: Error, Equatable, CustomStringConvertible, Sendable {
    case chatGPTTokenNotAvailable
    case chatGPTAccountIDNotAvailable
    case cloudTaskFailed(CloudTaskError)
    case applyDidNotSucceed(CloudApplyOutcome)
    case emptyTaskID
    case noAttemptsAvailable
    case noDiffAvailable(taskID: String)
    case attemptUnavailable(requested: Int, available: Int)

    public var description: String {
        switch self {
        case .chatGPTTokenNotAvailable:
            return "ChatGPT token not available"
        case .chatGPTAccountIDNotAvailable:
            return "ChatGPT account ID not available, please re-run `codex login`"
        case let .cloudTaskFailed(error):
            return error.description
        case let .applyDidNotSucceed(outcome):
            return outcome.message
        case .emptyTaskID:
            return "task id must not be empty"
        case .noAttemptsAvailable:
            return "No attempts available"
        case let .noDiffAvailable(taskID):
            return "No diff available for task \(taskID); it may still be running."
        case let .attemptUnavailable(requested, available):
            return "Attempt \(requested) not available; only \(available) attempt(s) found"
        }
    }
}

public struct CloudTaskClient<Transport: APITransport>: Sendable {
    public typealias TokenLoader = @Sendable () async throws -> AuthTokenData?

    public let configuration: CloudTaskClientConfiguration
    public let transport: Transport

    private let tokenLoader: TokenLoader
    private let currentDirectory: @Sendable () -> URL
    private let applyGitPatch: CloudGitApply
    private let errorLog: CloudTaskErrorLog

    public init(
        configuration: CloudTaskClientConfiguration,
        transport: Transport,
        tokenLoader: TokenLoader? = nil,
        currentDirectory: @escaping @Sendable () -> URL = {
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        },
        applyGitPatch: @escaping CloudGitApply = CloudTaskCodexGitApplier.apply,
        errorLog: @escaping CloudTaskErrorLog = CloudTaskErrorLogger.append
    ) {
        self.configuration = configuration
        self.transport = transport
        self.tokenLoader = tokenLoader ?? {
            try await CodexAuthStorage.loadFreshTokenData(
                codexHome: configuration.codexHome,
                mode: configuration.authCredentialsStoreMode
            )
        }
        self.currentDirectory = currentDirectory
        self.applyGitPatch = applyGitPatch
        self.errorLog = errorLog
    }

    public func applyTask(taskID: String) async throws -> CloudApplyOutcome {
        let outcome = try await applyTaskOutcome(taskID: taskID, diffOverride: nil)
        guard outcome.applied, outcome.status == .success else {
            throw CloudTaskClientError.applyDidNotSucceed(outcome)
        }
        return outcome
    }

    public func taskSummary(taskID: String) async throws -> CloudTaskSummary {
        let id = try Self.parseTaskID(taskID)
        let backend = try await makeBackend()
        switch await backend.getTaskSummary(id: id) {
        case let .success(summary):
            return summary
        case let .failure(error):
            throw CloudTaskClientError.cloudTaskFailed(error)
        }
    }

    public func taskDiff(taskID: String, attempt: Int? = nil) async throws -> String {
        let id = try Self.parseTaskID(taskID)
        let attempts = try await collectAttemptDiffs(id: id)
        return try selectAttempt(attempts, attempt: attempt).diff
    }

    public func applyTaskOutcome(taskID: String, attempt: Int?) async throws -> CloudApplyOutcome {
        let id = try Self.parseTaskID(taskID)
        let attempts = try await collectAttemptDiffs(id: id)
        let diff = try selectAttempt(attempts, attempt: attempt).diff
        return try await applyTaskOutcome(taskID: id.rawValue, diffOverride: diff)
    }

    public static func parseTaskID(_ raw: String) throws -> CloudTaskID {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw CloudTaskClientError.emptyTaskID
        }

        let withoutFragment = trimmed.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? trimmed
        let withoutQuery = withoutFragment.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? withoutFragment
        let id = withoutQuery.split(separator: "/", omittingEmptySubsequences: false).last.map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? withoutQuery
        guard !id.isEmpty else {
            throw CloudTaskClientError.emptyTaskID
        }
        return CloudTaskID(id)
    }

    private func makeBackend() async throws -> CloudHTTPClient<Transport, StaticAPIAuthProvider> {
        guard let token = try await tokenLoader() else {
            throw CloudTaskClientError.chatGPTTokenNotAvailable
        }
        guard let accountID = token.accountID else {
            throw CloudTaskClientError.chatGPTAccountIDNotAvailable
        }

        return CloudHTTPClient(
            baseURL: configuration.chatgptBaseURL,
            transport: transport,
            auth: StaticAPIAuthProvider(bearerToken: token.accessToken, accountID: accountID),
            currentDirectory: currentDirectory,
            applyGitPatch: applyGitPatch,
            errorLog: errorLog
        )
    }

    private func applyTaskOutcome(taskID: String, diffOverride: String?) async throws -> CloudApplyOutcome {
        let id = try Self.parseTaskID(taskID)
        let backend = try await makeBackend()
        switch await backend.applyTask(id: id, diffOverride: diffOverride) {
        case let .success(outcome):
            return outcome
        case let .failure(error):
            throw CloudTaskClientError.cloudTaskFailed(error)
        }
    }

    private func collectAttemptDiffs(id: CloudTaskID) async throws -> [AttemptDiffData] {
        let backend = try await makeBackend()
        let text: CloudTaskText
        switch await backend.getTaskText(id: id) {
        case let .success(value):
            text = value
        case let .failure(error):
            throw CloudTaskClientError.cloudTaskFailed(error)
        }

        var attempts: [AttemptDiffData] = []
        switch await backend.getTaskDiff(id: id) {
        case let .success(diff?):
            attempts.append(AttemptDiffData(
                placement: text.attemptPlacement,
                createdAt: nil,
                diff: diff
            ))
        case .success(nil):
            break
        case let .failure(error):
            throw CloudTaskClientError.cloudTaskFailed(error)
        }

        if let turnID = text.turnID {
            switch await backend.listSiblingAttempts(task: id, turnID: turnID) {
            case let .success(siblings):
                for sibling in siblings {
                    if let diff = sibling.diff {
                        attempts.append(AttemptDiffData(
                            placement: sibling.attemptPlacement,
                            createdAt: sibling.createdAt,
                            diff: diff
                        ))
                    }
                }
            case let .failure(error):
                throw CloudTaskClientError.cloudTaskFailed(error)
            }
        }

        attempts.sort(by: Self.compareAttempts)
        if attempts.isEmpty {
            throw CloudTaskClientError.noDiffAvailable(taskID: id.rawValue)
        }
        return attempts
    }

    private func selectAttempt(_ attempts: [AttemptDiffData], attempt: Int?) throws -> AttemptDiffData {
        guard !attempts.isEmpty else {
            throw CloudTaskClientError.noAttemptsAvailable
        }
        let desired = attempt ?? 1
        let index = desired - 1
        guard attempts.indices.contains(index) else {
            throw CloudTaskClientError.attemptUnavailable(requested: desired, available: attempts.count)
        }
        return attempts[index]
    }

    private static func compareAttempts(lhs: AttemptDiffData, rhs: AttemptDiffData) -> Bool {
        switch (lhs.placement, rhs.placement) {
        case let (lhs?, rhs?):
            return lhs < rhs
        case (.some, .none):
            return true
        case (.none, .some):
            return false
        case (.none, .none):
            switch (lhs.createdAt, rhs.createdAt) {
            case let (lhs?, rhs?):
                return lhs < rhs
            case (.some, .none):
                return true
            case (.none, .some), (.none, .none):
                return false
            }
        }
    }
}

private struct AttemptDiffData: Equatable, Sendable {
    let placement: Int64?
    let createdAt: Date?
    let diff: String
}

public enum CloudTaskCommandFormatter {
    public static func statusLines(task: CloudTaskSummary, now: Date = Date()) -> [String] {
        var lines: [String] = []
        lines.append("[\(statusLabel(task.status))] \(task.title)")

        var metaParts: [String] = []
        if let label = task.environmentLabel, !label.isEmpty {
            metaParts.append(label)
        } else if let id = task.environmentID {
            metaParts.append(id)
        }
        metaParts.append(formatRelativeTime(reference: now, timestamp: task.updatedAt))
        lines.append(metaParts.joined(separator: "  •  "))
        lines.append(summaryLine(task.summary))
        return lines
    }

    public static func summaryLine(_ summary: CloudDiffSummary) -> String {
        if summary.filesChanged == 0, summary.linesAdded == 0, summary.linesRemoved == 0 {
            return "no diff"
        }
        return "+\(summary.linesAdded)/-\(summary.linesRemoved) • \(summary.filesChanged) file\(summary.filesChanged == 1 ? "" : "s")"
    }

    public static func statusLabel(_ status: CloudTaskStatus) -> String {
        switch status {
        case .pending:
            return "PENDING"
        case .ready:
            return "READY"
        case .applied:
            return "APPLIED"
        case .error:
            return "ERROR"
        }
    }

    public static func formatRelativeTime(reference: Date, timestamp: Date) -> String {
        let seconds = max(0, Int(reference.timeIntervalSince(timestamp)))
        if seconds < 60 {
            return "\(seconds)s ago"
        }
        let minutes = seconds / 60
        if minutes < 60 {
            return "\(minutes)m ago"
        }
        let hours = minutes / 60
        if hours < 24 {
            return "\(hours)h ago"
        }
        let monthFormatter = DateFormatter()
        monthFormatter.locale = Locale(identifier: "en_US_POSIX")
        monthFormatter.dateFormat = "MMM"
        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale(identifier: "en_US_POSIX")
        timeFormatter.dateFormat = "HH:mm"
        let day = Calendar.current.component(.day, from: timestamp)
        return "\(monthFormatter.string(from: timestamp)) \(String(format: "%2d", day)) \(timeFormatter.string(from: timestamp))"
    }
}

public extension CloudTaskClient where Transport == URLSessionAPITransport {
    init(
        configuration: CloudTaskClientConfiguration,
        tokenLoader: TokenLoader? = nil,
        currentDirectory: @escaping @Sendable () -> URL = {
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        },
        applyGitPatch: @escaping CloudGitApply = CloudTaskCodexGitApplier.apply,
        errorLog: @escaping CloudTaskErrorLog = CloudTaskErrorLogger.append
    ) {
        self.init(
            configuration: configuration,
            transport: URLSessionAPITransport(),
            tokenLoader: tokenLoader,
            currentDirectory: currentDirectory,
            applyGitPatch: applyGitPatch,
            errorLog: errorLog
        )
    }
}
