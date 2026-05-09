import Foundation

public typealias CloudTaskResult<T> = Result<T, CloudTaskError>

public enum CloudTaskError: Error, Equatable, CustomStringConvertible, Sendable {
    case unimplemented(String)
    case http(String)
    case io(String)
    case message(String)

    public var description: String {
        switch self {
        case let .unimplemented(message):
            return "unimplemented: \(message)"
        case let .http(message):
            return "http error: \(message)"
        case let .io(message):
            return "io error: \(message)"
        case let .message(message):
            return message
        }
    }
}

public struct CloudTaskID: Equatable, Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public var description: String {
        rawValue
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(try container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public enum CloudTaskStatus: String, Codable, Sendable {
    case pending
    case ready
    case applied
    case error
}

public struct CloudTaskSummary: Equatable, Codable, Sendable {
    public let id: CloudTaskID
    public let title: String
    public let status: CloudTaskStatus
    public let updatedAt: Date
    public let environmentID: String?
    public let environmentLabel: String?
    public let summary: CloudDiffSummary
    public let isReview: Bool
    public let attemptTotal: Int?

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case status
        case updatedAt = "updated_at"
        case environmentID = "environment_id"
        case environmentLabel = "environment_label"
        case summary
        case isReview = "is_review"
        case attemptTotal = "attempt_total"
    }

    public init(
        id: CloudTaskID,
        title: String,
        status: CloudTaskStatus,
        updatedAt: Date,
        environmentID: String?,
        environmentLabel: String?,
        summary: CloudDiffSummary,
        isReview: Bool = false,
        attemptTotal: Int? = nil
    ) {
        self.id = id
        self.title = title
        self.status = status
        self.updatedAt = updatedAt
        self.environmentID = environmentID
        self.environmentLabel = environmentLabel
        self.summary = summary
        self.isReview = isReview
        self.attemptTotal = attemptTotal
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(CloudTaskID.self, forKey: .id)
        self.title = try container.decode(String.self, forKey: .title)
        self.status = try container.decode(CloudTaskStatus.self, forKey: .status)
        self.updatedAt = try CloudDateCoding.decodeDate(from: container, forKey: .updatedAt)
        self.environmentID = try container.decodeIfPresent(String.self, forKey: .environmentID)
        self.environmentLabel = try container.decodeIfPresent(String.self, forKey: .environmentLabel)
        self.summary = try container.decode(CloudDiffSummary.self, forKey: .summary)
        self.isReview = try container.decodeIfPresent(Bool.self, forKey: .isReview) ?? false
        self.attemptTotal = try container.decodeIfPresent(Int.self, forKey: .attemptTotal)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(status, forKey: .status)
        try CloudDateCoding.encode(updatedAt, into: &container, forKey: .updatedAt)
        try container.encodeIfPresentOrNull(environmentID, forKey: .environmentID)
        try container.encodeIfPresentOrNull(environmentLabel, forKey: .environmentLabel)
        try container.encode(summary, forKey: .summary)
        try container.encode(isReview, forKey: .isReview)
        try container.encodeIfPresentOrNull(attemptTotal, forKey: .attemptTotal)
    }
}

public enum CloudAttemptStatus: String, Codable, Sendable {
    case pending
    case inProgress = "in-progress"
    case completed
    case failed
    case cancelled
    case unknown
}

public struct CloudTurnAttempt: Equatable, Sendable {
    public let turnID: String
    public let attemptPlacement: Int64?
    public let createdAt: Date?
    public let status: CloudAttemptStatus
    public let diff: String?
    public let messages: [String]

    public init(
        turnID: String,
        attemptPlacement: Int64? = nil,
        createdAt: Date? = nil,
        status: CloudAttemptStatus = .unknown,
        diff: String? = nil,
        messages: [String] = []
    ) {
        self.turnID = turnID
        self.attemptPlacement = attemptPlacement
        self.createdAt = createdAt
        self.status = status
        self.diff = diff
        self.messages = messages
    }
}

public enum CloudApplyStatus: String, Codable, Sendable {
    case success
    case partial
    case error
}

public struct CloudApplyOutcome: Equatable, Codable, Sendable {
    public let applied: Bool
    public let status: CloudApplyStatus
    public let message: String
    public let skippedPaths: [String]
    public let conflictPaths: [String]

    private enum CodingKeys: String, CodingKey {
        case applied
        case status
        case message
        case skippedPaths = "skipped_paths"
        case conflictPaths = "conflict_paths"
    }

    public init(
        applied: Bool,
        status: CloudApplyStatus,
        message: String,
        skippedPaths: [String] = [],
        conflictPaths: [String] = []
    ) {
        self.applied = applied
        self.status = status
        self.message = message
        self.skippedPaths = skippedPaths
        self.conflictPaths = conflictPaths
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.applied = try container.decode(Bool.self, forKey: .applied)
        self.status = try container.decode(CloudApplyStatus.self, forKey: .status)
        self.message = try container.decode(String.self, forKey: .message)
        self.skippedPaths = try container.decodeIfPresent([String].self, forKey: .skippedPaths) ?? []
        self.conflictPaths = try container.decodeIfPresent([String].self, forKey: .conflictPaths) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(applied, forKey: .applied)
        try container.encode(status, forKey: .status)
        try container.encode(message, forKey: .message)
        try container.encode(skippedPaths, forKey: .skippedPaths)
        try container.encode(conflictPaths, forKey: .conflictPaths)
    }
}

public struct CloudCreatedTask: Equatable, Codable, Sendable {
    public let id: CloudTaskID

    public init(id: CloudTaskID) {
        self.id = id
    }
}

public struct CloudEnvironmentRow: Equatable, Codable, Sendable {
    public let id: String
    public let label: String?
    public let isPinned: Bool
    public let repoHints: String?

    public init(id: String, label: String? = nil, isPinned: Bool = false, repoHints: String? = nil) {
        self.id = id
        self.label = label
        self.isPinned = isPinned
        self.repoHints = repoHints
    }
}

public struct CloudDiffSummary: Equatable, Codable, Sendable {
    public let filesChanged: Int
    public let linesAdded: Int
    public let linesRemoved: Int

    private enum CodingKeys: String, CodingKey {
        case filesChanged = "files_changed"
        case linesAdded = "lines_added"
        case linesRemoved = "lines_removed"
    }

    public init(filesChanged: Int = 0, linesAdded: Int = 0, linesRemoved: Int = 0) {
        self.filesChanged = filesChanged
        self.linesAdded = linesAdded
        self.linesRemoved = linesRemoved
    }
}

public struct CloudTaskText: Equatable, Sendable {
    public let prompt: String?
    public let messages: [String]
    public let turnID: String?
    public let siblingTurnIDs: [String]
    public let attemptPlacement: Int64?
    public let attemptStatus: CloudAttemptStatus

    public init(
        prompt: String? = nil,
        messages: [String] = [],
        turnID: String? = nil,
        siblingTurnIDs: [String] = [],
        attemptPlacement: Int64? = nil,
        attemptStatus: CloudAttemptStatus = .unknown
    ) {
        self.prompt = prompt
        self.messages = messages
        self.turnID = turnID
        self.siblingTurnIDs = siblingTurnIDs
        self.attemptPlacement = attemptPlacement
        self.attemptStatus = attemptStatus
    }
}

public struct CloudTaskPage: Equatable, Sendable {
    public let tasks: [CloudTaskSummary]
    public let cursor: String?

    public init(tasks: [CloudTaskSummary], cursor: String? = nil) {
        self.tasks = tasks
        self.cursor = cursor
    }
}

public protocol CloudBackend: Sendable {
    func listTasks(environment: String?, limit: Int?, cursor: String?) async -> CloudTaskResult<CloudTaskPage>
    func listEnvironments() async -> CloudTaskResult<[CloudEnvironmentRow]>
    func getTaskSummary(id: CloudTaskID) async -> CloudTaskResult<CloudTaskSummary>
    func getTaskDiff(id: CloudTaskID) async -> CloudTaskResult<String?>
    func getTaskMessages(id: CloudTaskID) async -> CloudTaskResult<[String]>
    func getTaskText(id: CloudTaskID) async -> CloudTaskResult<CloudTaskText>
    func listSiblingAttempts(task: CloudTaskID, turnID: String) async -> CloudTaskResult<[CloudTurnAttempt]>
    func applyTaskPreflight(id: CloudTaskID, diffOverride: String?) async -> CloudTaskResult<CloudApplyOutcome>
    func applyTask(id: CloudTaskID, diffOverride: String?) async -> CloudTaskResult<CloudApplyOutcome>
    func createTask(
        environmentID: String,
        prompt: String,
        gitRef: String,
        qaMode: Bool,
        bestOfN: Int
    ) async -> CloudTaskResult<CloudCreatedTask>
}

public extension CloudBackend {
    func listTasks(environment: String?) async -> CloudTaskResult<[CloudTaskSummary]> {
        switch await listTasks(environment: environment, limit: 20, cursor: nil) {
        case let .success(page):
            return .success(page.tasks)
        case let .failure(error):
            return .failure(error)
        }
    }
}

public struct CloudMockClient: CloudBackend {
    private let now: @Sendable () -> Date

    public init(now: @escaping @Sendable () -> Date = Date.init) {
        self.now = now
    }

    public func listTasks(environment: String?, limit: Int?, cursor: String?) async -> CloudTaskResult<CloudTaskPage> {
        _ = cursor
        let rows: [(String, String, CloudTaskStatus)]
        switch environment {
        case "env-A":
            rows = [("T-2000", "A: First", .ready)]
        case "env-B":
            rows = [
                ("T-3000", "B: One", .ready),
                ("T-3001", "B: Two", .pending)
            ]
        default:
            rows = [
                ("T-1000", "Update README formatting", .ready),
                ("T-1001", "Fix clippy warnings in core", .pending),
                ("T-1002", "Add contributing guide", .ready)
            ]
        }

        let environmentLabel: String?
        switch environment {
        case "env-A":
            environmentLabel = "Env A"
        case "env-B":
            environmentLabel = "Env B"
        case let value?:
            environmentLabel = value
        case nil:
            environmentLabel = "Global"
        }

        let limitedRows = rows.prefix(limit ?? rows.count)
        return .success(CloudTaskPage(tasks: limitedRows.map { id, title, status in
            let taskID = CloudTaskID(id)
            let diffCounts = Self.countFromUnified(Self.mockDiff(for: taskID))
            return CloudTaskSummary(
                id: taskID,
                title: title,
                status: status,
                updatedAt: now(),
                environmentID: environment,
                environmentLabel: environmentLabel,
                summary: CloudDiffSummary(
                    filesChanged: 1,
                    linesAdded: diffCounts.added,
                    linesRemoved: diffCounts.removed
                ),
                isReview: false,
                attemptTotal: id == "T-1000" ? 2 : 1
            )
        }))
    }

    public func listEnvironments() async -> CloudTaskResult<[CloudEnvironmentRow]> {
        .success([
            CloudEnvironmentRow(id: "env-A", label: "Env A", isPinned: true, repoHints: "mock/repo"),
            CloudEnvironmentRow(id: "env-B", label: "Env B")
        ])
    }

    public func getTaskSummary(id: CloudTaskID) async -> CloudTaskResult<CloudTaskSummary> {
        switch await listTasks(environment: nil) {
        case let .success(tasks):
            if let task = tasks.first(where: { $0.id == id }) {
                return .success(task)
            }
            return .failure(.message("Task \(id.rawValue) not found (mock)"))
        case let .failure(error):
            return .failure(error)
        }
    }

    public func getTaskDiff(id: CloudTaskID) async -> CloudTaskResult<String?> {
        .success(Self.mockDiff(for: id))
    }

    public func getTaskMessages(id: CloudTaskID) async -> CloudTaskResult<[String]> {
        _ = id
        return .success(["Mock assistant output: this task contains no diff."])
    }

    public func getTaskText(id: CloudTaskID) async -> CloudTaskResult<CloudTaskText> {
        _ = id
        return .success(CloudTaskText(
            prompt: "Why is there no diff?",
            messages: ["Mock assistant output: this task contains no diff."],
            turnID: "mock-turn",
            attemptPlacement: 0,
            attemptStatus: .completed
        ))
    }

    public func listSiblingAttempts(task: CloudTaskID, turnID: String) async -> CloudTaskResult<[CloudTurnAttempt]> {
        _ = turnID
        if task.rawValue == "T-1000" {
            return .success([
                CloudTurnAttempt(
                    turnID: "T-1000-attempt-2",
                    attemptPlacement: 1,
                    createdAt: now(),
                    status: .completed,
                    diff: Self.mockDiff(for: task),
                    messages: ["Mock alternate attempt"]
                )
            ])
        }
        return .success([])
    }

    public func applyTaskPreflight(id: CloudTaskID, diffOverride: String?) async -> CloudTaskResult<CloudApplyOutcome> {
        _ = diffOverride
        return .success(CloudApplyOutcome(
            applied: false,
            status: .success,
            message: "Preflight passed for task \(id.rawValue) (mock)"
        ))
    }

    public func applyTask(id: CloudTaskID, diffOverride: String?) async -> CloudTaskResult<CloudApplyOutcome> {
        _ = diffOverride
        return .success(CloudApplyOutcome(
            applied: true,
            status: .success,
            message: "Applied task \(id.rawValue) locally (mock)"
        ))
    }

    public func createTask(
        environmentID: String,
        prompt: String,
        gitRef: String,
        qaMode: Bool,
        bestOfN: Int
    ) async -> CloudTaskResult<CloudCreatedTask> {
        _ = (environmentID, prompt, gitRef, qaMode, bestOfN)
        let milliseconds = Int64((now().timeIntervalSince1970 * 1_000).rounded(.down))
        return .success(CloudCreatedTask(id: CloudTaskID("task_local_\(milliseconds)")))
    }

    public static func mockDiff(for id: CloudTaskID) -> String {
        switch id.rawValue {
        case "T-1000":
            return """
            diff --git a/README.md b/README.md
            index 000000..111111 100644
            --- a/README.md
            +++ b/README.md
            @@ -1,2 +1,3 @@
             Intro
            -Hello
            +Hello, world!
            +Task: T-1000

            """
        case "T-1001":
            return """
            diff --git a/core/src/lib.rs b/core/src/lib.rs
            index 000000..111111 100644
            --- a/core/src/lib.rs
            +++ b/core/src/lib.rs
            @@ -1,2 +1,1 @@
            -use foo;
             use bar;

            """
        default:
            return """
            diff --git a/CONTRIBUTING.md b/CONTRIBUTING.md
            index 000000..111111 100644
            --- /dev/null
            +++ b/CONTRIBUTING.md
            @@ -0,0 +1,3 @@
            +## Contributing
            +Please open PRs.
            +Thanks!

            """
        }
    }

    public static func countFromUnified(_ diff: String) -> (added: Int, removed: Int) {
        var added = 0
        var removed = 0
        for line in diff.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("+++") || line.hasPrefix("---") || line.hasPrefix("@@") {
                continue
            }
            if line.hasPrefix("+") {
                added += 1
            } else if line.hasPrefix("-") {
                removed += 1
            }
        }
        return (added, removed)
    }
}

private enum CloudDateCoding {
    static func decodeDate<K: CodingKey>(
        from container: KeyedDecodingContainer<K>,
        forKey key: K
    ) throws -> Date {
        let raw = try container.decode(String.self, forKey: key)
        if let date = makeFormatter(fractionalSeconds: false).date(from: raw)
            ?? makeFormatter(fractionalSeconds: true).date(from: raw) {
            return date
        }
        throw DecodingError.dataCorruptedError(
            forKey: key,
            in: container,
            debugDescription: "expected RFC3339 timestamp"
        )
    }

    static func encode<K: CodingKey>(
        _ date: Date,
        into container: inout KeyedEncodingContainer<K>,
        forKey key: K
    ) throws {
        try container.encode(makeFormatter(fractionalSeconds: false).string(from: date), forKey: key)
    }

    private static func makeFormatter(fractionalSeconds: Bool) -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = fractionalSeconds ? [.withInternetDateTime, .withFractionalSeconds] : [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }
}

private extension KeyedEncodingContainer {
    mutating func encodeIfPresentOrNull<T: Encodable>(_ value: T?, forKey key: Key) throws {
        if let value {
            try encode(value, forKey: key)
        } else {
            try encodeNil(forKey: key)
        }
    }
}
