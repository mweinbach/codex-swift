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
    case emptyEnvironmentID
    case noCloudEnvironmentsAvailable
    case environmentNotFound(String)
    case ambiguousEnvironmentLabel(String)
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
        case .emptyEnvironmentID:
            return "environment id must not be empty"
        case .noCloudEnvironmentsAvailable:
            return "no cloud environments are available for this workspace"
        case let .environmentNotFound(environment):
            return "environment '\(environment)' not found; run `codex cloud` to list available environments"
        case let .ambiguousEnvironmentLabel(label):
            return "environment label '\(label)' is ambiguous; run `codex cloud` to pick the desired environment id"
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
    public typealias BranchNameResolver = @Sendable (URL) -> String?

    public let configuration: CloudTaskClientConfiguration
    public let transport: Transport

    private let tokenLoader: TokenLoader
    private let currentDirectory: @Sendable () -> URL
    private let currentBranchName: BranchNameResolver
    private let defaultBranchName: BranchNameResolver
    private let applyGitPatch: CloudGitApply
    private let errorLog: CloudTaskErrorLog

    public init(
        configuration: CloudTaskClientConfiguration,
        transport: Transport,
        tokenLoader: TokenLoader? = nil,
        currentDirectory: @escaping @Sendable () -> URL = {
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        },
        currentBranchName: @escaping BranchNameResolver = GitInfoCollector.currentBranchName,
        defaultBranchName: @escaping BranchNameResolver = GitInfoCollector.defaultBranchName,
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
        self.currentBranchName = currentBranchName
        self.defaultBranchName = defaultBranchName
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

    public func listTasks(environment: String?, limit: Int = 20, cursor: String? = nil) async throws -> CloudTaskPage {
        let backend = try await makeBackend()
        let environmentID: String?
        if let environment {
            environmentID = try await resolveEnvironmentID(environment, backend: backend)
        } else {
            environmentID = nil
        }
        switch await backend.listTasks(environment: environmentID, limit: limit, cursor: cursor) {
        case let .success(page):
            return page
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

    public func createTask(
        prompt: String,
        environment requestedEnvironment: String,
        branch branchOverride: String? = nil,
        attempts: Int = 1
    ) async throws -> String {
        let backend = try await makeBackend()
        let environmentID = try await resolveEnvironmentID(requestedEnvironment, backend: backend)
        let gitRef = resolveGitRef(branchOverride: branchOverride)
        let created: CloudCreatedTask
        switch await backend.createTask(
            environmentID: environmentID,
            prompt: prompt,
            gitRef: gitRef,
            qaMode: false,
            bestOfN: attempts
        ) {
        case let .success(value):
            created = value
        case let .failure(error):
            throw CloudTaskClientError.cloudTaskFailed(error)
        }
        return CloudTaskCommandFormatter.taskURL(
            baseURL: configuration.chatgptBaseURL,
            taskID: created.id.rawValue
        )
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

    private func resolveEnvironmentID(
        _ requested: String,
        backend: CloudHTTPClient<Transport, StaticAPIAuthProvider>
    ) async throws -> String {
        let trimmed = requested.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw CloudTaskClientError.emptyEnvironmentID
        }

        let environments: [CloudEnvironmentRow]
        switch await backend.listEnvironments() {
        case let .success(rows):
            environments = rows
        case let .failure(error):
            throw CloudTaskClientError.cloudTaskFailed(error)
        }
        guard !environments.isEmpty else {
            throw CloudTaskClientError.noCloudEnvironmentsAvailable
        }

        if let exact = environments.first(where: { $0.id == trimmed }) {
            return exact.id
        }

        let labelMatches = environments.filter { row in
            row.label?.caseInsensitiveCompare(trimmed) == .orderedSame
        }
        guard let first = labelMatches.first else {
            throw CloudTaskClientError.environmentNotFound(trimmed)
        }
        if labelMatches.dropFirst().allSatisfy({ $0.id == first.id }) {
            return first.id
        }
        throw CloudTaskClientError.ambiguousEnvironmentLabel(trimmed)
    }

    private func resolveGitRef(branchOverride: String?) -> String {
        if let branch = branchOverride?.trimmingCharacters(in: .whitespacesAndNewlines),
           !branch.isEmpty {
            return branch
        }

        let cwd = currentDirectory()
        if let branch = currentBranchName(cwd), !branch.isEmpty {
            return branch
        }
        if let branch = defaultBranchName(cwd), !branch.isEmpty {
            return branch
        }
        return "main"
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

    public static func listLines(tasks: [CloudTaskSummary], baseURL: String, now: Date = Date()) -> [String] {
        var lines: [String] = []
        for (index, task) in tasks.enumerated() {
            lines.append(taskURL(baseURL: baseURL, taskID: task.id.rawValue))
            lines.append(contentsOf: statusLines(task: task, now: now).map { "  \($0)" })
            if index + 1 < tasks.count {
                lines.append("")
            }
        }
        return lines
    }

    public static func listJSON(tasks: [CloudTaskSummary], cursor: String?, baseURL: String) throws -> String {
        var lines: [String] = []
        lines.append("{")
        lines.append("  \"cursor\": \(try jsonOptionalString(cursor)),")
        if tasks.isEmpty {
            lines.append("  \"tasks\": []")
        } else {
            lines.append("  \"tasks\": [")
            for (index, task) in tasks.enumerated() {
                lines.append("    {")
                lines.append("      \"attempt_total\": \(jsonOptionalInt(task.attemptTotal)),")
                lines.append("      \"environment_id\": \(try jsonOptionalString(task.environmentID)),")
                lines.append("      \"environment_label\": \(try jsonOptionalString(task.environmentLabel)),")
                lines.append("      \"id\": \(try jsonString(task.id.rawValue)),")
                lines.append("      \"is_review\": \(task.isReview),")
                lines.append("      \"status\": \(try jsonString(task.status.rawValue)),")
                lines.append("      \"summary\": {")
                lines.append("        \"files_changed\": \(task.summary.filesChanged),")
                lines.append("        \"lines_added\": \(task.summary.linesAdded),")
                lines.append("        \"lines_removed\": \(task.summary.linesRemoved)")
                lines.append("      },")
                lines.append("      \"title\": \(try jsonString(task.title)),")
                lines.append("      \"updated_at\": \(try jsonString(CloudDateCoding.encodeString(task.updatedAt))),")
                lines.append("      \"url\": \(try jsonString(taskURL(baseURL: baseURL, taskID: task.id.rawValue)))")
                lines.append(index + 1 == tasks.count ? "    }" : "    },")
            }
            lines.append("  ]")
        }
        lines.append("}")
        return lines.joined(separator: "\n")
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

    public static func taskURL(baseURL: String, taskID: String) -> String {
        let normalized = CloudHTTPClient<URLSessionAPITransport, StaticAPIAuthProvider>.normalizedBaseURL(baseURL)
        if normalized.hasSuffix("/backend-api") {
            return "\(String(normalized.dropLast("/backend-api".count)))/codex/tasks/\(taskID)"
        }
        if normalized.hasSuffix("/api/codex") {
            return "\(String(normalized.dropLast("/api/codex".count)))/codex/tasks/\(taskID)"
        }
        if normalized.hasSuffix("/codex") {
            return "\(normalized)/tasks/\(taskID)"
        }
        return "\(normalized)/codex/tasks/\(taskID)"
    }

    private static func jsonOptionalInt(_ value: Int?) -> String {
        value.map(String.init) ?? "null"
    }

    private static func jsonOptionalString(_ value: String?) throws -> String {
        guard let value else {
            return "null"
        }
        return try jsonString(value)
    }

    private static func jsonString(_ value: String) throws -> String {
        let encoded = try JSONEncoder().encode(value)
        return String(decoding: encoded, as: UTF8.self)
            .replacingOccurrences(of: "\\/", with: "/")
    }
}

public extension CloudTaskClient where Transport == URLSessionAPITransport {
    init(
        configuration: CloudTaskClientConfiguration,
        tokenLoader: TokenLoader? = nil,
        currentDirectory: @escaping @Sendable () -> URL = {
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        },
        currentBranchName: @escaping BranchNameResolver = GitInfoCollector.currentBranchName,
        defaultBranchName: @escaping BranchNameResolver = GitInfoCollector.defaultBranchName,
        applyGitPatch: @escaping CloudGitApply = CloudTaskCodexGitApplier.apply,
        errorLog: @escaping CloudTaskErrorLog = CloudTaskErrorLogger.append
    ) {
        self.init(
            configuration: configuration,
            transport: URLSessionAPITransport(),
            tokenLoader: tokenLoader,
            currentDirectory: currentDirectory,
            currentBranchName: currentBranchName,
            defaultBranchName: defaultBranchName,
            applyGitPatch: applyGitPatch,
            errorLog: errorLog
        )
    }
}
