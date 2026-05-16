public enum TuiStatusLineItem: String, CaseIterable, Equatable, Sendable {
    case model = "model"
    case modelWithReasoning = "model-with-reasoning"
    case currentDir = "current-dir"
    case projectName = "project-name"
    case gitBranch = "git-branch"
    case pullRequestNumber = "pull-request-number"
    case branchChanges = "branch-changes"
    case runState = "run-state"
    case permissions = "permissions"
    case approvalMode = "approval-mode"
    case contextRemaining = "context-remaining"
    case contextUsed = "context-used"
    case fiveHourLimit = "five-hour-limit"
    case weeklyLimit = "weekly-limit"
    case codexVersion = "codex-version"
    case contextWindowSize = "context-window-size"
    case usedTokens = "used-tokens"
    case totalInputTokens = "total-input-tokens"
    case totalOutputTokens = "total-output-tokens"
    case threadID = "thread-id"
    case fastMode = "fast-mode"
    case rawOutput = "raw-output"
    case threadTitle = "thread-title"
    case taskProgress = "task-progress"

    public init?(id: String) {
        switch id {
        case "model-name":
            self = .model
        case "project", "project-root":
            self = .projectName
        case "status":
            self = .runState
        case "approval":
            self = .approvalMode
        case "context-usage":
            self = .contextUsed
        case "session-id":
            self = .threadID
        default:
            guard let item = Self(rawValue: id) else {
                return nil
            }
            self = item
        }
    }

    public static func parseIDs<S: Sequence>(_ ids: S) -> [TuiStatusLineItem]? where S.Element == String {
        var items: [TuiStatusLineItem] = []
        for id in ids {
            guard let item = TuiStatusLineItem(id: id) else {
                return nil
            }
            items.append(item)
        }
        return items
    }
}

public enum TuiTerminalTitleItem: String, CaseIterable, Equatable, Sendable {
    case appName = "app-name"
    case projectName = "project-name"
    case currentDir = "current-dir"
    case activity = "activity"
    case runState = "run-state"
    case threadTitle = "thread-title"
    case gitBranch = "git-branch"
    case contextRemaining = "context-remaining"
    case contextUsed = "context-used"
    case fiveHourLimit = "five-hour-limit"
    case weeklyLimit = "weekly-limit"
    case codexVersion = "codex-version"
    case usedTokens = "used-tokens"
    case totalInputTokens = "total-input-tokens"
    case totalOutputTokens = "total-output-tokens"
    case threadID = "thread-id"
    case fastMode = "fast-mode"
    case model = "model"
    case modelWithReasoning = "model-with-reasoning"
    case taskProgress = "task-progress"

    public init?(id: String) {
        switch id {
        case "project":
            self = .projectName
        case "spinner":
            self = .activity
        case "status":
            self = .runState
        case "thread":
            self = .threadTitle
        case "context-usage":
            self = .contextUsed
        case "session-id":
            self = .threadID
        case "model-name":
            self = .model
        default:
            guard let item = Self(rawValue: id) else {
                return nil
            }
            self = item
        }
    }

    public static func parseIDs<S: Sequence>(_ ids: S) -> [TuiTerminalTitleItem]? where S.Element == String {
        var items: [TuiTerminalTitleItem] = []
        for id in ids {
            guard let item = TuiTerminalTitleItem(id: id) else {
                return nil
            }
            items.append(item)
        }
        return items
    }
}
