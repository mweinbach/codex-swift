import Foundation

public enum AppServerSortDirection: String, Codable, Equatable, Sendable {
    case asc
    case desc
}

public enum AppServerTurnItemsView: String, Codable, Equatable, Sendable {
    case notLoaded
    case summary
    case full
}

public enum AppServerTurnStatus: String, Codable, Equatable, Sendable {
    case completed
    case interrupted
    case failed
    case inProgress
}

public enum ThreadStartSource: String, Codable, Equatable, Sendable {
    case startup
    case clear
}

public enum AppServerSessionSource: Equatable, Sendable {
    case cli
    case vsCode
    case exec
    case appServer
    case custom(String)
    case subAgent(SubAgentSource)
    case unknown

    private enum UnitValue: String, Codable {
        case cli
        case vsCode = "vscode"
        case exec
        case appServer
        case unknown
    }

    private enum TaggedKey: String, CodingKey {
        case custom
        case subAgent
    }
}

extension AppServerSessionSource: Codable {
    public init(from decoder: Decoder) throws {
        let single = try decoder.singleValueContainer()
        if let unit = try? single.decode(UnitValue.self) {
            switch unit {
            case .cli:
                self = .cli
            case .vsCode:
                self = .vsCode
            case .exec:
                self = .exec
            case .appServer:
                self = .appServer
            case .unknown:
                self = .unknown
            }
            return
        }

        let container = try decoder.container(keyedBy: TaggedKey.self)
        if container.contains(.custom) {
            self = .custom(try container.decode(String.self, forKey: .custom))
        } else if container.contains(.subAgent) {
            self = .subAgent(try container.decode(SubAgentSource.self, forKey: .subAgent))
        } else {
            self = .unknown
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .cli:
            var container = encoder.singleValueContainer()
            try container.encode(UnitValue.cli)
        case .vsCode:
            var container = encoder.singleValueContainer()
            try container.encode(UnitValue.vsCode)
        case .exec:
            var container = encoder.singleValueContainer()
            try container.encode(UnitValue.exec)
        case .appServer:
            var container = encoder.singleValueContainer()
            try container.encode(UnitValue.appServer)
        case let .custom(source):
            var container = encoder.container(keyedBy: TaggedKey.self)
            try container.encode(source, forKey: .custom)
        case let .subAgent(source):
            var container = encoder.container(keyedBy: TaggedKey.self)
            try container.encode(source, forKey: .subAgent)
        case .unknown:
            var container = encoder.singleValueContainer()
            try container.encode(UnitValue.unknown)
        }
    }
}

public enum AppServerThreadSourceKind: String, Codable, Equatable, Sendable {
    case cli
    case vsCode = "vscode"
    case exec
    case appServer
    case subAgent
    case subAgentReview
    case subAgentCompact
    case subAgentThreadSpawn
    case subAgentOther
    case unknown
}

public enum AppServerThreadSortKey: String, Codable, Equatable, Sendable {
    case createdAt = "created_at"
    case updatedAt = "updated_at"
}

public enum AppServerThreadActiveFlag: String, Codable, Equatable, Sendable {
    case waitingOnApproval
    case waitingOnUserInput
}

public enum ThreadUnsubscribeStatus: String, Codable, Equatable, Sendable {
    case notLoaded
    case notSubscribed
    case unsubscribed
}

public enum AppServerThreadStatus: Equatable, Sendable {
    case notLoaded
    case idle
    case systemError
    case active(activeFlags: [AppServerThreadActiveFlag])

    private enum CodingKeys: String, CodingKey {
        case type
        case activeFlags
    }

    private enum StatusType: String, Codable {
        case notLoaded
        case idle
        case systemError
        case active
    }
}

extension AppServerThreadStatus: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(StatusType.self, forKey: .type) {
        case .notLoaded:
            self = .notLoaded
        case .idle:
            self = .idle
        case .systemError:
            self = .systemError
        case .active:
            self = .active(
                activeFlags: try container.decodeIfPresent(
                    [AppServerThreadActiveFlag].self,
                    forKey: .activeFlags
                ) ?? []
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .notLoaded:
            try container.encode(StatusType.notLoaded, forKey: .type)
        case .idle:
            try container.encode(StatusType.idle, forKey: .type)
        case .systemError:
            try container.encode(StatusType.systemError, forKey: .type)
        case let .active(activeFlags):
            try container.encode(StatusType.active, forKey: .type)
            try container.encode(activeFlags, forKey: .activeFlags)
        }
    }
}

public struct AppServerTurnError: Equatable, Codable, Sendable {
    public let message: String
    public let codexErrorInfo: CodexErrorInfo?
    public let additionalDetails: String?

    private enum CodingKeys: String, CodingKey {
        case message
        case codexErrorInfo
        case additionalDetails
    }

    public init(
        message: String,
        codexErrorInfo: CodexErrorInfo? = nil,
        additionalDetails: String? = nil
    ) {
        self.message = message
        self.codexErrorInfo = codexErrorInfo
        self.additionalDetails = additionalDetails
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(message, forKey: .message)
        try container.encodeNilOrValue(codexErrorInfo, forKey: .codexErrorInfo)
        try container.encodeNilOrValue(additionalDetails, forKey: .additionalDetails)
    }
}

public struct AppServerMemoryCitation: Equatable, Codable, Sendable {
    public let entries: [AppServerMemoryCitationEntry]
    public let threadIDs: [String]

    private enum CodingKeys: String, CodingKey {
        case entries
        case threadIDs = "threadIds"
    }

    public init(entries: [AppServerMemoryCitationEntry] = [], threadIDs: [String] = []) {
        self.entries = entries
        self.threadIDs = threadIDs
    }

    public init(_ citation: MemoryCitation) {
        self.init(
            entries: citation.entries.map(AppServerMemoryCitationEntry.init),
            threadIDs: citation.rolloutIDs
        )
    }
}

public struct AppServerMemoryCitationEntry: Equatable, Codable, Sendable {
    public let path: String
    public let lineStart: UInt32
    public let lineEnd: UInt32
    public let note: String

    public init(path: String, lineStart: UInt32, lineEnd: UInt32, note: String) {
        self.path = path
        self.lineStart = lineStart
        self.lineEnd = lineEnd
        self.note = note
    }

    public init(_ entry: MemoryCitationEntry) {
        self.init(
            path: entry.path,
            lineStart: entry.lineStart,
            lineEnd: entry.lineEnd,
            note: entry.note
        )
    }
}

public enum AppServerThreadItem: Equatable, Sendable {
    case userMessage(id: String, content: [AppServerUserInput])
    case hookPrompt(id: String, fragments: [HookPromptFragment])
    case agentMessage(id: String, text: String, phase: MessagePhase? = nil, memoryCitation: AppServerMemoryCitation? = nil)
    case plan(id: String, text: String)
    case reasoning(id: String, summary: [String] = [], content: [String] = [])
    case contextCompaction(id: String)

    private enum CodingKeys: String, CodingKey {
        case type
        case id
        case fragments
        case text
        case phase
        case memoryCitation
        case summary
        case content
    }

    private enum ItemType: String, Codable {
        case userMessage
        case hookPrompt
        case agentMessage
        case plan
        case reasoning
        case contextCompaction
    }

    public var id: String {
        switch self {
        case let .userMessage(id, _),
             let .hookPrompt(id, _),
             let .agentMessage(id, _, _, _),
             let .plan(id, _),
             let .reasoning(id, _, _),
             let .contextCompaction(id):
            id
        }
    }
}

extension AppServerThreadItem: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(ItemType.self, forKey: .type) {
        case .userMessage:
            self = .userMessage(
                id: try container.decode(String.self, forKey: .id),
                content: try container.decode([AppServerUserInput].self, forKey: .content)
            )
        case .hookPrompt:
            self = .hookPrompt(
                id: try container.decode(String.self, forKey: .id),
                fragments: try container.decode([HookPromptFragment].self, forKey: .fragments)
            )
        case .agentMessage:
            self = .agentMessage(
                id: try container.decode(String.self, forKey: .id),
                text: try container.decode(String.self, forKey: .text),
                phase: try container.decodeIfPresent(MessagePhase.self, forKey: .phase),
                memoryCitation: try container.decodeIfPresent(AppServerMemoryCitation.self, forKey: .memoryCitation)
            )
        case .plan:
            self = .plan(
                id: try container.decode(String.self, forKey: .id),
                text: try container.decode(String.self, forKey: .text)
            )
        case .reasoning:
            self = .reasoning(
                id: try container.decode(String.self, forKey: .id),
                summary: try container.decodeIfPresent([String].self, forKey: .summary) ?? [],
                content: try container.decodeIfPresent([String].self, forKey: .content) ?? []
            )
        case .contextCompaction:
            self = .contextCompaction(id: try container.decode(String.self, forKey: .id))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .userMessage(id, content):
            try container.encode(ItemType.userMessage, forKey: .type)
            try container.encode(id, forKey: .id)
            try container.encode(content, forKey: .content)
        case let .hookPrompt(id, fragments):
            try container.encode(ItemType.hookPrompt, forKey: .type)
            try container.encode(id, forKey: .id)
            try container.encode(fragments, forKey: .fragments)
        case let .agentMessage(id, text, phase, memoryCitation):
            try container.encode(ItemType.agentMessage, forKey: .type)
            try container.encode(id, forKey: .id)
            try container.encode(text, forKey: .text)
            try container.encodeIfPresent(phase, forKey: .phase)
            try container.encodeIfPresent(memoryCitation, forKey: .memoryCitation)
        case let .plan(id, text):
            try container.encode(ItemType.plan, forKey: .type)
            try container.encode(id, forKey: .id)
            try container.encode(text, forKey: .text)
        case let .reasoning(id, summary, content):
            try container.encode(ItemType.reasoning, forKey: .type)
            try container.encode(id, forKey: .id)
            try container.encode(summary, forKey: .summary)
            try container.encode(content, forKey: .content)
        case let .contextCompaction(id):
            try container.encode(ItemType.contextCompaction, forKey: .type)
            try container.encode(id, forKey: .id)
        }
    }
}

public struct AppServerTurn: Equatable, Codable, Sendable {
    public let id: String
    public var items: [AppServerThreadItem]
    public var itemsView: AppServerTurnItemsView
    public let status: AppServerTurnStatus
    public let error: AppServerTurnError?
    public let startedAt: Int64?
    public let completedAt: Int64?
    public let durationMs: Int64?

    private enum CodingKeys: String, CodingKey {
        case id
        case items
        case itemsView
        case status
        case error
        case startedAt
        case completedAt
        case durationMs
    }

    public init(
        id: String,
        items: [AppServerThreadItem],
        itemsView: AppServerTurnItemsView = .full,
        status: AppServerTurnStatus,
        error: AppServerTurnError? = nil,
        startedAt: Int64? = nil,
        completedAt: Int64? = nil,
        durationMs: Int64? = nil
    ) {
        self.id = id
        self.items = items
        self.itemsView = itemsView
        self.status = status
        self.error = error
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.durationMs = durationMs
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        items = try container.decode([AppServerThreadItem].self, forKey: .items)
        itemsView = try container.decodeIfPresent(AppServerTurnItemsView.self, forKey: .itemsView) ?? .full
        status = try container.decode(AppServerTurnStatus.self, forKey: .status)
        error = try container.decodeIfPresent(AppServerTurnError.self, forKey: .error)
        startedAt = try container.decodeIfPresent(Int64.self, forKey: .startedAt)
        completedAt = try container.decodeIfPresent(Int64.self, forKey: .completedAt)
        durationMs = try container.decodeIfPresent(Int64.self, forKey: .durationMs)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(items, forKey: .items)
        try container.encode(itemsView, forKey: .itemsView)
        try container.encode(status, forKey: .status)
        try container.encodeNilOrValue(error, forKey: .error)
        try container.encodeNilOrValue(startedAt, forKey: .startedAt)
        try container.encodeNilOrValue(completedAt, forKey: .completedAt)
        try container.encodeNilOrValue(durationMs, forKey: .durationMs)
    }
}

public struct AppServerThreadGitInfo: Equatable, Codable, Sendable {
    public let sha: String?
    public let branch: String?
    public let originURL: String?

    private enum CodingKeys: String, CodingKey {
        case sha
        case branch
        case originURL = "originUrl"
    }

    public init(sha: String? = nil, branch: String? = nil, originURL: String? = nil) {
        self.sha = sha
        self.branch = branch
        self.originURL = originURL
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeNilOrValue(sha, forKey: .sha)
        try container.encodeNilOrValue(branch, forKey: .branch)
        try container.encodeNilOrValue(originURL, forKey: .originURL)
    }
}

public struct AppServerThread: Equatable, Codable, Sendable {
    public let id: String
    public let sessionID: String
    public let forkedFromID: String?
    public let preview: String
    public let ephemeral: Bool
    public let modelProvider: String
    public let createdAt: Int64
    public let updatedAt: Int64
    public let status: AppServerThreadStatus
    public let path: String?
    public let cwd: AbsolutePath
    public let cliVersion: String
    public let source: AppServerSessionSource
    public let threadSource: ThreadSource?
    public let agentNickname: String?
    public let agentRole: String?
    public let gitInfo: AppServerThreadGitInfo?
    public let name: String?
    public var turns: [AppServerTurn]

    private enum CodingKeys: String, CodingKey {
        case id
        case sessionID = "sessionId"
        case forkedFromID = "forkedFromId"
        case preview
        case ephemeral
        case modelProvider
        case createdAt
        case updatedAt
        case status
        case path
        case cwd
        case cliVersion
        case source
        case threadSource
        case agentNickname
        case agentRole
        case gitInfo
        case name
        case turns
    }

    public init(
        id: String,
        sessionID: String? = nil,
        forkedFromID: String? = nil,
        preview: String = "",
        ephemeral: Bool = false,
        modelProvider: String = "",
        createdAt: Int64 = 0,
        updatedAt: Int64 = 0,
        status: AppServerThreadStatus = .notLoaded,
        path: String? = nil,
        cwd: AbsolutePath = .root,
        cliVersion: String = "",
        source: AppServerSessionSource = .vsCode,
        threadSource: ThreadSource? = nil,
        agentNickname: String? = nil,
        agentRole: String? = nil,
        gitInfo: AppServerThreadGitInfo? = nil,
        name: String? = nil,
        turns: [AppServerTurn]
    ) {
        self.id = id
        self.sessionID = sessionID ?? id
        self.forkedFromID = forkedFromID
        self.preview = preview
        self.ephemeral = ephemeral
        self.modelProvider = modelProvider
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.status = status
        self.path = path
        self.cwd = cwd
        self.cliVersion = cliVersion
        self.source = source
        self.threadSource = threadSource
        self.agentNickname = agentNickname
        self.agentRole = agentRole
        self.gitInfo = gitInfo
        self.name = name
        self.turns = turns
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(sessionID, forKey: .sessionID)
        try container.encodeNilOrValue(forkedFromID, forKey: .forkedFromID)
        try container.encode(preview, forKey: .preview)
        try container.encode(ephemeral, forKey: .ephemeral)
        try container.encode(modelProvider, forKey: .modelProvider)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(status, forKey: .status)
        try container.encodeNilOrValue(path, forKey: .path)
        try container.encode(cwd, forKey: .cwd)
        try container.encode(cliVersion, forKey: .cliVersion)
        try container.encode(source, forKey: .source)
        try container.encodeNilOrValue(threadSource, forKey: .threadSource)
        try container.encodeNilOrValue(agentNickname, forKey: .agentNickname)
        try container.encodeNilOrValue(agentRole, forKey: .agentRole)
        try container.encodeNilOrValue(gitInfo, forKey: .gitInfo)
        try container.encodeNilOrValue(name, forKey: .name)
        try container.encode(turns, forKey: .turns)
    }

    public func items(forTurnID turnID: String) -> [AppServerThreadItem]? {
        turns.first { $0.id == turnID }?.items
    }
}

public struct TokenUsageBreakdown: Equatable, Codable, Sendable {
    public let totalTokens: Int64
    public let inputTokens: Int64
    public let cachedInputTokens: Int64
    public let outputTokens: Int64
    public let reasoningOutputTokens: Int64

    public init(
        totalTokens: Int64,
        inputTokens: Int64,
        cachedInputTokens: Int64,
        outputTokens: Int64,
        reasoningOutputTokens: Int64
    ) {
        self.totalTokens = totalTokens
        self.inputTokens = inputTokens
        self.cachedInputTokens = cachedInputTokens
        self.outputTokens = outputTokens
        self.reasoningOutputTokens = reasoningOutputTokens
    }
}

public struct ThreadTokenUsage: Equatable, Codable, Sendable {
    public let total: TokenUsageBreakdown
    public let last: TokenUsageBreakdown
    public let modelContextWindow: Int64?

    private enum CodingKeys: String, CodingKey {
        case total
        case last
        case modelContextWindow
    }

    public init(total: TokenUsageBreakdown, last: TokenUsageBreakdown, modelContextWindow: Int64?) {
        self.total = total
        self.last = last
        self.modelContextWindow = modelContextWindow
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(total, forKey: .total)
        try container.encode(last, forKey: .last)
        if let modelContextWindow {
            try container.encode(modelContextWindow, forKey: .modelContextWindow)
        } else {
            try container.encodeNil(forKey: .modelContextWindow)
        }
    }
}

public struct ThreadTokenUsageUpdatedNotification: Equatable, Codable, Sendable {
    public let threadID: String
    public let turnID: String
    public let tokenUsage: ThreadTokenUsage

    private enum CodingKeys: String, CodingKey {
        case threadID = "threadId"
        case turnID = "turnId"
        case tokenUsage
    }

    public init(threadID: String, turnID: String, tokenUsage: ThreadTokenUsage) {
        self.threadID = threadID
        self.turnID = turnID
        self.tokenUsage = tokenUsage
    }
}

public struct ThreadStartedNotification: Equatable, Codable, Sendable {
    public let thread: AppServerThread

    public init(thread: AppServerThread) {
        self.thread = thread
    }
}

public struct ThreadStartResponse: Equatable, Codable, Sendable {
    public let thread: AppServerThread
    public let model: String
    public let modelProvider: String
    public let serviceTier: String?
    public let cwd: AbsolutePath
    public let instructionSources: [AbsolutePath]
    public let approvalPolicy: AskForApproval
    public let approvalsReviewer: ApprovalsReviewer
    public let sandbox: SandboxPolicy
    public let permissionProfile: AppServerPermissionProfile?
    public let activePermissionProfile: AppServerActivePermissionProfile?
    public let reasoningEffort: ReasoningEffort?

    private enum CodingKeys: String, CodingKey {
        case thread
        case model
        case modelProvider
        case serviceTier
        case cwd
        case instructionSources
        case approvalPolicy
        case approvalsReviewer
        case sandbox
        case permissionProfile
        case activePermissionProfile
        case reasoningEffort
    }

    public init(
        thread: AppServerThread,
        model: String,
        modelProvider: String,
        serviceTier: String?,
        cwd: AbsolutePath,
        instructionSources: [AbsolutePath] = [],
        approvalPolicy: AskForApproval,
        approvalsReviewer: ApprovalsReviewer,
        sandbox: SandboxPolicy,
        permissionProfile: AppServerPermissionProfile?,
        activePermissionProfile: AppServerActivePermissionProfile?,
        reasoningEffort: ReasoningEffort?
    ) {
        self.thread = thread
        self.model = model
        self.modelProvider = modelProvider
        self.serviceTier = serviceTier
        self.cwd = cwd
        self.instructionSources = instructionSources
        self.approvalPolicy = approvalPolicy
        self.approvalsReviewer = approvalsReviewer
        self.sandbox = sandbox
        self.permissionProfile = permissionProfile
        self.activePermissionProfile = activePermissionProfile
        self.reasoningEffort = reasoningEffort
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(thread, forKey: .thread)
        try container.encode(model, forKey: .model)
        try container.encode(modelProvider, forKey: .modelProvider)
        try container.encodeNilOrValue(serviceTier, forKey: .serviceTier)
        try container.encode(cwd, forKey: .cwd)
        try container.encode(instructionSources, forKey: .instructionSources)
        try container.encode(approvalPolicy, forKey: .approvalPolicy)
        try container.encode(approvalsReviewer, forKey: .approvalsReviewer)
        try container.encode(sandbox, forKey: .sandbox)
        try container.encodeNilOrValue(permissionProfile, forKey: .permissionProfile)
        try container.encodeNilOrValue(activePermissionProfile, forKey: .activePermissionProfile)
        try container.encodeNilOrValue(reasoningEffort, forKey: .reasoningEffort)
    }
}

public struct ThreadResumeResponse: Equatable, Codable, Sendable {
    public let thread: AppServerThread
    public let model: String
    public let modelProvider: String
    public let serviceTier: String?
    public let cwd: AbsolutePath
    public let instructionSources: [AbsolutePath]
    public let approvalPolicy: AskForApproval
    public let approvalsReviewer: ApprovalsReviewer
    public let sandbox: SandboxPolicy
    public let permissionProfile: AppServerPermissionProfile?
    public let activePermissionProfile: AppServerActivePermissionProfile?
    public let reasoningEffort: ReasoningEffort?

    private enum CodingKeys: String, CodingKey {
        case thread
        case model
        case modelProvider
        case serviceTier
        case cwd
        case instructionSources
        case approvalPolicy
        case approvalsReviewer
        case sandbox
        case permissionProfile
        case activePermissionProfile
        case reasoningEffort
    }

    public init(
        thread: AppServerThread,
        model: String,
        modelProvider: String,
        serviceTier: String?,
        cwd: AbsolutePath,
        instructionSources: [AbsolutePath] = [],
        approvalPolicy: AskForApproval,
        approvalsReviewer: ApprovalsReviewer,
        sandbox: SandboxPolicy,
        permissionProfile: AppServerPermissionProfile?,
        activePermissionProfile: AppServerActivePermissionProfile?,
        reasoningEffort: ReasoningEffort?
    ) {
        self.thread = thread
        self.model = model
        self.modelProvider = modelProvider
        self.serviceTier = serviceTier
        self.cwd = cwd
        self.instructionSources = instructionSources
        self.approvalPolicy = approvalPolicy
        self.approvalsReviewer = approvalsReviewer
        self.sandbox = sandbox
        self.permissionProfile = permissionProfile
        self.activePermissionProfile = activePermissionProfile
        self.reasoningEffort = reasoningEffort
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(thread, forKey: .thread)
        try container.encode(model, forKey: .model)
        try container.encode(modelProvider, forKey: .modelProvider)
        try container.encodeNilOrValue(serviceTier, forKey: .serviceTier)
        try container.encode(cwd, forKey: .cwd)
        try container.encode(instructionSources, forKey: .instructionSources)
        try container.encode(approvalPolicy, forKey: .approvalPolicy)
        try container.encode(approvalsReviewer, forKey: .approvalsReviewer)
        try container.encode(sandbox, forKey: .sandbox)
        try container.encodeNilOrValue(permissionProfile, forKey: .permissionProfile)
        try container.encodeNilOrValue(activePermissionProfile, forKey: .activePermissionProfile)
        try container.encodeNilOrValue(reasoningEffort, forKey: .reasoningEffort)
    }
}

public struct ThreadForkResponse: Equatable, Codable, Sendable {
    public let thread: AppServerThread
    public let model: String
    public let modelProvider: String
    public let serviceTier: String?
    public let cwd: AbsolutePath
    public let instructionSources: [AbsolutePath]
    public let approvalPolicy: AskForApproval
    public let approvalsReviewer: ApprovalsReviewer
    public let sandbox: SandboxPolicy
    public let permissionProfile: AppServerPermissionProfile?
    public let activePermissionProfile: AppServerActivePermissionProfile?
    public let reasoningEffort: ReasoningEffort?

    private enum CodingKeys: String, CodingKey {
        case thread
        case model
        case modelProvider
        case serviceTier
        case cwd
        case instructionSources
        case approvalPolicy
        case approvalsReviewer
        case sandbox
        case permissionProfile
        case activePermissionProfile
        case reasoningEffort
    }

    public init(
        thread: AppServerThread,
        model: String,
        modelProvider: String,
        serviceTier: String?,
        cwd: AbsolutePath,
        instructionSources: [AbsolutePath] = [],
        approvalPolicy: AskForApproval,
        approvalsReviewer: ApprovalsReviewer,
        sandbox: SandboxPolicy,
        permissionProfile: AppServerPermissionProfile?,
        activePermissionProfile: AppServerActivePermissionProfile?,
        reasoningEffort: ReasoningEffort?
    ) {
        self.thread = thread
        self.model = model
        self.modelProvider = modelProvider
        self.serviceTier = serviceTier
        self.cwd = cwd
        self.instructionSources = instructionSources
        self.approvalPolicy = approvalPolicy
        self.approvalsReviewer = approvalsReviewer
        self.sandbox = sandbox
        self.permissionProfile = permissionProfile
        self.activePermissionProfile = activePermissionProfile
        self.reasoningEffort = reasoningEffort
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(thread, forKey: .thread)
        try container.encode(model, forKey: .model)
        try container.encode(modelProvider, forKey: .modelProvider)
        try container.encodeNilOrValue(serviceTier, forKey: .serviceTier)
        try container.encode(cwd, forKey: .cwd)
        try container.encode(instructionSources, forKey: .instructionSources)
        try container.encode(approvalPolicy, forKey: .approvalPolicy)
        try container.encode(approvalsReviewer, forKey: .approvalsReviewer)
        try container.encode(sandbox, forKey: .sandbox)
        try container.encodeNilOrValue(permissionProfile, forKey: .permissionProfile)
        try container.encodeNilOrValue(activePermissionProfile, forKey: .activePermissionProfile)
        try container.encodeNilOrValue(reasoningEffort, forKey: .reasoningEffort)
    }
}

public struct ThreadStatusChangedNotification: Equatable, Codable, Sendable {
    public let threadID: String
    public let status: AppServerThreadStatus

    private enum CodingKeys: String, CodingKey {
        case threadID = "threadId"
        case status
    }

    public init(threadID: String, status: AppServerThreadStatus) {
        self.threadID = threadID
        self.status = status
    }
}

public struct ThreadArchivedNotification: Equatable, Codable, Sendable {
    public let threadID: String

    private enum CodingKeys: String, CodingKey {
        case threadID = "threadId"
    }

    public init(threadID: String) {
        self.threadID = threadID
    }
}

public struct ThreadUnarchivedNotification: Equatable, Codable, Sendable {
    public let threadID: String

    private enum CodingKeys: String, CodingKey {
        case threadID = "threadId"
    }

    public init(threadID: String) {
        self.threadID = threadID
    }
}

public struct ThreadClosedNotification: Equatable, Codable, Sendable {
    public let threadID: String

    private enum CodingKeys: String, CodingKey {
        case threadID = "threadId"
    }

    public init(threadID: String) {
        self.threadID = threadID
    }
}

public struct ThreadNameUpdatedNotification: Equatable, Codable, Sendable {
    public let threadID: String
    public let threadName: String?

    private enum CodingKeys: String, CodingKey {
        case threadID = "threadId"
        case threadName
    }

    public init(threadID: String, threadName: String? = nil) {
        self.threadID = threadID
        self.threadName = threadName
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(threadID, forKey: .threadID)
        try container.encodeIfPresent(threadName, forKey: .threadName)
    }
}

public struct ThreadGoalUpdatedNotification: Equatable, Codable, Sendable {
    public let threadID: String
    public let turnID: String?
    public let goal: ThreadGoal

    private enum CodingKeys: String, CodingKey {
        case threadID = "threadId"
        case turnID = "turnId"
        case goal
    }

    public init(threadID: String, turnID: String? = nil, goal: ThreadGoal) {
        self.threadID = threadID
        self.turnID = turnID
        self.goal = goal
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(threadID, forKey: .threadID)
        if let turnID {
            try container.encode(turnID, forKey: .turnID)
        } else {
            try container.encodeNil(forKey: .turnID)
        }
        try container.encode(goal, forKey: .goal)
    }
}

public struct ThreadGoalClearedNotification: Equatable, Codable, Sendable {
    public let threadID: String

    private enum CodingKeys: String, CodingKey {
        case threadID = "threadId"
    }

    public init(threadID: String) {
        self.threadID = threadID
    }
}

public struct ContextCompactedNotification: Equatable, Codable, Sendable {
    public let threadID: String
    public let turnID: String

    private enum CodingKeys: String, CodingKey {
        case threadID = "threadId"
        case turnID = "turnId"
    }

    public init(threadID: String, turnID: String) {
        self.threadID = threadID
        self.turnID = turnID
    }
}

public enum AppServerTurnCompletionBackfill {
    public static func shouldBackfill(threadEphemeral: Bool, completedTurn: AppServerTurn) -> Bool {
        !threadEphemeral && completedTurn.items.isEmpty
    }

    public static func backfilledTurn(_ completedTurn: AppServerTurn, from thread: AppServerThread) -> AppServerTurn {
        guard let items = thread.items(forTurnID: completedTurn.id) else {
            return completedTurn
        }
        var turn = completedTurn
        turn.items = items
        return turn
    }
}

public enum ThreadListCwdFilter: Equatable, Sendable {
    case one(String)
    case many([String])
}

extension ThreadListCwdFilter: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let one = try? container.decode(String.self) {
            self = .one(one)
            return
        }
        self = .many(try container.decode([String].self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .one(value):
            try container.encode(value)
        case let .many(values):
            try container.encode(values)
        }
    }
}

public struct ThreadListParams: Equatable, Codable, Sendable {
    public let cursor: String?
    public let limit: UInt32?
    public let sortKey: AppServerThreadSortKey?
    public let sortDirection: AppServerSortDirection?
    public let modelProviders: [String]?
    public let sourceKinds: [AppServerThreadSourceKind]?
    public let archived: Bool?
    public let cwd: ThreadListCwdFilter?
    public let useStateDBOnly: Bool
    public let searchTerm: String?

    private enum CodingKeys: String, CodingKey {
        case cursor
        case limit
        case sortKey
        case sortDirection
        case modelProviders
        case sourceKinds
        case archived
        case cwd
        case useStateDBOnly = "useStateDbOnly"
        case searchTerm
    }

    public init(
        cursor: String? = nil,
        limit: UInt32? = nil,
        sortKey: AppServerThreadSortKey? = nil,
        sortDirection: AppServerSortDirection? = nil,
        modelProviders: [String]? = nil,
        sourceKinds: [AppServerThreadSourceKind]? = nil,
        archived: Bool? = nil,
        cwd: ThreadListCwdFilter? = nil,
        useStateDBOnly: Bool = false,
        searchTerm: String? = nil
    ) {
        self.cursor = cursor
        self.limit = limit
        self.sortKey = sortKey
        self.sortDirection = sortDirection
        self.modelProviders = modelProviders
        self.sourceKinds = sourceKinds
        self.archived = archived
        self.cwd = cwd
        self.useStateDBOnly = useStateDBOnly
        self.searchTerm = searchTerm
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        cursor = try container.decodeIfPresent(String.self, forKey: .cursor)
        limit = try container.decodeIfPresent(UInt32.self, forKey: .limit)
        sortKey = try container.decodeIfPresent(AppServerThreadSortKey.self, forKey: .sortKey)
        sortDirection = try container.decodeIfPresent(AppServerSortDirection.self, forKey: .sortDirection)
        modelProviders = try container.decodeIfPresent([String].self, forKey: .modelProviders)
        sourceKinds = try container.decodeIfPresent([AppServerThreadSourceKind].self, forKey: .sourceKinds)
        archived = try container.decodeIfPresent(Bool.self, forKey: .archived)
        cwd = try container.decodeIfPresent(ThreadListCwdFilter.self, forKey: .cwd)
        useStateDBOnly = try container.decodeIfPresent(Bool.self, forKey: .useStateDBOnly) ?? false
        searchTerm = try container.decodeIfPresent(String.self, forKey: .searchTerm)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(cursor, forKey: .cursor)
        try container.encodeIfPresent(limit, forKey: .limit)
        try container.encodeIfPresent(sortKey, forKey: .sortKey)
        try container.encodeIfPresent(sortDirection, forKey: .sortDirection)
        try container.encodeIfPresent(modelProviders, forKey: .modelProviders)
        try container.encodeIfPresent(sourceKinds, forKey: .sourceKinds)
        try container.encodeIfPresent(archived, forKey: .archived)
        try container.encodeIfPresent(cwd, forKey: .cwd)
        if useStateDBOnly {
            try container.encode(useStateDBOnly, forKey: .useStateDBOnly)
        }
        try container.encodeIfPresent(searchTerm, forKey: .searchTerm)
    }
}

public struct ThreadListResponse: Equatable, Codable, Sendable {
    public let data: [AppServerThread]
    public let nextCursor: String?
    public let backwardsCursor: String?

    private enum CodingKeys: String, CodingKey {
        case data
        case nextCursor
        case backwardsCursor
    }

    public init(data: [AppServerThread], nextCursor: String?, backwardsCursor: String?) {
        self.data = data
        self.nextCursor = nextCursor
        self.backwardsCursor = backwardsCursor
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(data, forKey: .data)
        try container.encodeNilOrValue(nextCursor, forKey: .nextCursor)
        try container.encodeNilOrValue(backwardsCursor, forKey: .backwardsCursor)
    }
}

public struct MockExperimentalMethodParams: Equatable, Codable, Sendable {
    public let value: String?

    private enum CodingKeys: String, CodingKey {
        case value
    }

    public init(value: String? = nil) {
        self.value = value
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let value {
            try container.encode(value, forKey: .value)
        } else {
            try container.encodeNil(forKey: .value)
        }
    }
}

public struct MockExperimentalMethodResponse: Equatable, Codable, Sendable {
    public let echoed: String?

    private enum CodingKeys: String, CodingKey {
        case echoed
    }

    public init(echoed: String?) {
        self.echoed = echoed
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let echoed {
            try container.encode(echoed, forKey: .echoed)
        } else {
            try container.encodeNil(forKey: .echoed)
        }
    }
}

public struct ThreadLoadedListParams: Equatable, Codable, Sendable {
    public let cursor: String?
    public let limit: UInt32?

    private enum CodingKeys: String, CodingKey {
        case cursor
        case limit
    }

    public init(cursor: String? = nil, limit: UInt32? = nil) {
        self.cursor = cursor
        self.limit = limit
    }
}

public struct ThreadLoadedListResponse: Equatable, Codable, Sendable {
    public let data: [String]
    public let nextCursor: String?

    private enum CodingKeys: String, CodingKey {
        case data
        case nextCursor
    }

    public init(data: [String], nextCursor: String?) {
        self.data = data
        self.nextCursor = nextCursor
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(data, forKey: .data)
        if let nextCursor {
            try container.encode(nextCursor, forKey: .nextCursor)
        } else {
            try container.encodeNil(forKey: .nextCursor)
        }
    }
}

public struct ThreadInjectItemsParams: Equatable, Codable, Sendable {
    public let threadID: String
    public let items: [JSONValue]

    private enum CodingKeys: String, CodingKey {
        case threadID = "threadId"
        case items
    }

    public init(threadID: String, items: [JSONValue]) {
        self.threadID = threadID
        self.items = items
    }
}

public struct ThreadInjectItemsResponse: Equatable, Codable, Sendable {
    public init() {}
}

public struct ThreadArchiveParams: Equatable, Codable, Sendable {
    public let threadID: String

    private enum CodingKeys: String, CodingKey {
        case threadID = "threadId"
    }

    public init(threadID: String) {
        self.threadID = threadID
    }
}

public struct ThreadArchiveResponse: Equatable, Codable, Sendable {
    public init() {}
}

public struct ThreadUnarchiveParams: Equatable, Codable, Sendable {
    public let threadID: String

    private enum CodingKeys: String, CodingKey {
        case threadID = "threadId"
    }

    public init(threadID: String) {
        self.threadID = threadID
    }
}

public struct ThreadUnarchiveResponse: Equatable, Codable, Sendable {
    public let thread: AppServerThread

    public init(thread: AppServerThread) {
        self.thread = thread
    }
}

public struct ThreadUnsubscribeParams: Equatable, Codable, Sendable {
    public let threadID: String

    private enum CodingKeys: String, CodingKey {
        case threadID = "threadId"
    }

    public init(threadID: String) {
        self.threadID = threadID
    }
}

public struct ThreadUnsubscribeResponse: Equatable, Codable, Sendable {
    public let status: ThreadUnsubscribeStatus

    public init(status: ThreadUnsubscribeStatus) {
        self.status = status
    }
}

public struct ThreadIncrementElicitationParams: Equatable, Codable, Sendable {
    public let threadID: String

    private enum CodingKeys: String, CodingKey {
        case threadID = "threadId"
    }

    public init(threadID: String) {
        self.threadID = threadID
    }
}

public struct ThreadIncrementElicitationResponse: Equatable, Codable, Sendable {
    public let count: UInt64
    public let paused: Bool

    public init(count: UInt64, paused: Bool) {
        self.count = count
        self.paused = paused
    }
}

public struct ThreadDecrementElicitationParams: Equatable, Codable, Sendable {
    public let threadID: String

    private enum CodingKeys: String, CodingKey {
        case threadID = "threadId"
    }

    public init(threadID: String) {
        self.threadID = threadID
    }
}

public struct ThreadDecrementElicitationResponse: Equatable, Codable, Sendable {
    public let count: UInt64
    public let paused: Bool

    public init(count: UInt64, paused: Bool) {
        self.count = count
        self.paused = paused
    }
}

public struct ThreadSetNameParams: Equatable, Codable, Sendable {
    public let threadID: String
    public let name: String

    private enum CodingKeys: String, CodingKey {
        case threadID = "threadId"
        case name
    }

    public init(threadID: String, name: String) {
        self.threadID = threadID
        self.name = name
    }
}

public struct ThreadSetNameResponse: Equatable, Codable, Sendable {
    public init() {}
}

public struct ThreadCompactStartParams: Equatable, Codable, Sendable {
    public let threadID: String

    private enum CodingKeys: String, CodingKey {
        case threadID = "threadId"
    }

    public init(threadID: String) {
        self.threadID = threadID
    }
}

public struct ThreadCompactStartResponse: Equatable, Codable, Sendable {
    public init() {}
}

public struct ThreadShellCommandParams: Equatable, Codable, Sendable {
    public let threadID: String
    public let command: String

    private enum CodingKeys: String, CodingKey {
        case threadID = "threadId"
        case command
    }

    public init(threadID: String, command: String) {
        self.threadID = threadID
        self.command = command
    }
}

public struct ThreadShellCommandResponse: Equatable, Codable, Sendable {
    public init() {}
}

public struct ThreadApproveGuardianDeniedActionParams: Equatable, Codable, Sendable {
    public let threadID: String
    public let event: JSONValue

    private enum CodingKeys: String, CodingKey {
        case threadID = "threadId"
        case event
    }

    public init(threadID: String, event: JSONValue) {
        self.threadID = threadID
        self.event = event
    }
}

public struct ThreadApproveGuardianDeniedActionResponse: Equatable, Codable, Sendable {
    public init() {}
}

public struct ThreadBackgroundTerminalsCleanParams: Equatable, Codable, Sendable {
    public let threadID: String

    private enum CodingKeys: String, CodingKey {
        case threadID = "threadId"
    }

    public init(threadID: String) {
        self.threadID = threadID
    }
}

public struct ThreadBackgroundTerminalsCleanResponse: Equatable, Codable, Sendable {
    public init() {}
}

public enum ThreadMetadataStringPatch: Equatable, Sendable {
    case preserve
    case clear
    case set(String)
}

public struct ThreadMetadataGitInfoUpdateParams: Equatable, Codable, Sendable {
    public let sha: ThreadMetadataStringPatch
    public let branch: ThreadMetadataStringPatch
    public let originURL: ThreadMetadataStringPatch

    private enum CodingKeys: String, CodingKey {
        case sha
        case branch
        case originURL = "originUrl"
    }

    public init(
        sha: ThreadMetadataStringPatch = .preserve,
        branch: ThreadMetadataStringPatch = .preserve,
        originURL: ThreadMetadataStringPatch = .preserve
    ) {
        self.sha = sha
        self.branch = branch
        self.originURL = originURL
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sha = try Self.decodePatch(from: container, forKey: .sha)
        branch = try Self.decodePatch(from: container, forKey: .branch)
        originURL = try Self.decodePatch(from: container, forKey: .originURL)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try Self.encodePatch(sha, into: &container, forKey: .sha)
        try Self.encodePatch(branch, into: &container, forKey: .branch)
        try Self.encodePatch(originURL, into: &container, forKey: .originURL)
    }

    private static func decodePatch(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) throws -> ThreadMetadataStringPatch {
        if !container.contains(key) {
            return .preserve
        }
        if try container.decodeNil(forKey: key) {
            return .clear
        }
        return .set(try container.decode(String.self, forKey: key))
    }

    private static func encodePatch(
        _ patch: ThreadMetadataStringPatch,
        into container: inout KeyedEncodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) throws {
        switch patch {
        case .preserve:
            break
        case .clear:
            try container.encodeNil(forKey: key)
        case let .set(value):
            try container.encode(value, forKey: key)
        }
    }
}

public struct ThreadMetadataUpdateParams: Equatable, Codable, Sendable {
    public let threadID: String
    public let gitInfo: ThreadMetadataGitInfoUpdateParams?

    private enum CodingKeys: String, CodingKey {
        case threadID = "threadId"
        case gitInfo
    }

    public init(threadID: String, gitInfo: ThreadMetadataGitInfoUpdateParams?) {
        self.threadID = threadID
        self.gitInfo = gitInfo
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(threadID, forKey: .threadID)
        if let gitInfo {
            try container.encode(gitInfo, forKey: .gitInfo)
        } else {
            try container.encodeNil(forKey: .gitInfo)
        }
    }
}

public struct ThreadMetadataUpdateResponse: Equatable, Codable, Sendable {
    public let thread: AppServerThread

    public init(thread: AppServerThread) {
        self.thread = thread
    }
}

public enum ThreadGoalTokenBudgetPatch: Equatable, Sendable {
    case preserve
    case clear
    case set(Int64)
}

public struct ThreadGoalSetParams: Equatable, Codable, Sendable {
    public let threadID: String
    public let objective: String?
    public let status: ThreadGoalStatus?
    public let tokenBudget: ThreadGoalTokenBudgetPatch

    private enum CodingKeys: String, CodingKey {
        case threadID = "threadId"
        case objective
        case status
        case tokenBudget
    }

    public init(
        threadID: String,
        objective: String? = nil,
        status: ThreadGoalStatus? = nil,
        tokenBudget: ThreadGoalTokenBudgetPatch = .preserve
    ) {
        self.threadID = threadID
        self.objective = objective
        self.status = status
        self.tokenBudget = tokenBudget
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        threadID = try container.decode(String.self, forKey: .threadID)
        objective = try container.decodeIfPresent(String.self, forKey: .objective)
        status = try container.decodeIfPresent(ThreadGoalStatus.self, forKey: .status)
        if !container.contains(.tokenBudget) {
            tokenBudget = .preserve
        } else if try container.decodeNil(forKey: .tokenBudget) {
            tokenBudget = .clear
        } else {
            tokenBudget = .set(try container.decode(Int64.self, forKey: .tokenBudget))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(threadID, forKey: .threadID)
        try container.encodeIfPresent(objective, forKey: .objective)
        try container.encodeIfPresent(status, forKey: .status)
        switch tokenBudget {
        case .preserve:
            break
        case .clear:
            try container.encodeNil(forKey: .tokenBudget)
        case let .set(value):
            try container.encode(value, forKey: .tokenBudget)
        }
    }
}

public struct ThreadGoalSetResponse: Equatable, Codable, Sendable {
    public let goal: ThreadGoal

    public init(goal: ThreadGoal) {
        self.goal = goal
    }
}

public struct ThreadGoalGetParams: Equatable, Codable, Sendable {
    public let threadID: String

    private enum CodingKeys: String, CodingKey {
        case threadID = "threadId"
    }

    public init(threadID: String) {
        self.threadID = threadID
    }
}

public struct ThreadGoalGetResponse: Equatable, Codable, Sendable {
    public let goal: ThreadGoal?

    public init(goal: ThreadGoal?) {
        self.goal = goal
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let goal {
            try container.encode(goal, forKey: .goal)
        } else {
            try container.encodeNil(forKey: .goal)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case goal
    }
}

public struct ThreadGoalClearParams: Equatable, Codable, Sendable {
    public let threadID: String

    private enum CodingKeys: String, CodingKey {
        case threadID = "threadId"
    }

    public init(threadID: String) {
        self.threadID = threadID
    }
}

public struct ThreadGoalClearResponse: Equatable, Codable, Sendable {
    public let cleared: Bool

    public init(cleared: Bool) {
        self.cleared = cleared
    }
}

public struct ThreadMemoryModeSetParams: Equatable, Codable, Sendable {
    public let threadID: String
    public let mode: ThreadMemoryMode

    private enum CodingKeys: String, CodingKey {
        case threadID = "threadId"
        case mode
    }

    public init(threadID: String, mode: ThreadMemoryMode) {
        self.threadID = threadID
        self.mode = mode
    }
}

public struct ThreadMemoryModeSetResponse: Equatable, Codable, Sendable {
    public init() {}
}

public struct MemoryResetResponse: Equatable, Codable, Sendable {
    public init() {}
}

public struct ThreadRollbackParams: Equatable, Codable, Sendable {
    public let threadID: String
    public let numTurns: UInt32

    private enum CodingKeys: String, CodingKey {
        case threadID = "threadId"
        case numTurns
    }

    public init(threadID: String, numTurns: UInt32) {
        self.threadID = threadID
        self.numTurns = numTurns
    }
}

public struct ThreadRollbackResponse: Equatable, Codable, Sendable {
    public let thread: AppServerThread

    public init(thread: AppServerThread) {
        self.thread = thread
    }
}

public struct ThreadReadParams: Equatable, Codable, Sendable {
    public let threadID: String
    public let includeTurns: Bool

    private enum CodingKeys: String, CodingKey {
        case threadID = "threadId"
        case includeTurns
    }

    public init(threadID: String, includeTurns: Bool = false) {
        self.threadID = threadID
        self.includeTurns = includeTurns
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        threadID = try container.decode(String.self, forKey: .threadID)
        includeTurns = try container.decodeIfPresent(Bool.self, forKey: .includeTurns) ?? false
    }
}

public struct ThreadReadResponse: Equatable, Codable, Sendable {
    public let thread: AppServerThread

    public init(thread: AppServerThread) {
        self.thread = thread
    }
}

private extension KeyedEncodingContainer {
    mutating func encodeNilOrValue<Value: Encodable>(_ value: Value?, forKey key: Key) throws {
        if let value {
            try encode(value, forKey: key)
        } else {
            try encodeNil(forKey: key)
        }
    }
}

public struct ThreadTurnsListParams: Equatable, Codable, Sendable {
    public let threadID: String
    public let cursor: String?
    public let limit: UInt32?
    public let sortDirection: AppServerSortDirection?
    public let itemsView: AppServerTurnItemsView?

    private enum CodingKeys: String, CodingKey {
        case threadID = "threadId"
        case cursor
        case limit
        case sortDirection
        case itemsView
    }

    public init(
        threadID: String,
        cursor: String? = nil,
        limit: UInt32? = nil,
        sortDirection: AppServerSortDirection? = nil,
        itemsView: AppServerTurnItemsView? = nil
    ) {
        self.threadID = threadID
        self.cursor = cursor
        self.limit = limit
        self.sortDirection = sortDirection
        self.itemsView = itemsView
    }
}

public struct ThreadTurnsListResponse: Equatable, Codable, Sendable {
    public let data: [AppServerTurn]
    public let nextCursor: String?
    public let backwardsCursor: String?

    private enum CodingKeys: String, CodingKey {
        case data
        case nextCursor
        case backwardsCursor
    }

    public init(data: [AppServerTurn], nextCursor: String?, backwardsCursor: String?) {
        self.data = data
        self.nextCursor = nextCursor
        self.backwardsCursor = backwardsCursor
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(data, forKey: .data)
        if let nextCursor {
            try container.encode(nextCursor, forKey: .nextCursor)
        } else {
            try container.encodeNil(forKey: .nextCursor)
        }
        if let backwardsCursor {
            try container.encode(backwardsCursor, forKey: .backwardsCursor)
        } else {
            try container.encodeNil(forKey: .backwardsCursor)
        }
    }
}

public struct ThreadTurnsItemsListParams: Equatable, Codable, Sendable {
    public let threadID: String
    public let turnID: String
    public let cursor: String?
    public let limit: UInt32?
    public let sortDirection: AppServerSortDirection?

    private enum CodingKeys: String, CodingKey {
        case threadID = "threadId"
        case turnID = "turnId"
        case cursor
        case limit
        case sortDirection
    }

    public init(
        threadID: String,
        turnID: String,
        cursor: String? = nil,
        limit: UInt32? = nil,
        sortDirection: AppServerSortDirection? = nil
    ) {
        self.threadID = threadID
        self.turnID = turnID
        self.cursor = cursor
        self.limit = limit
        self.sortDirection = sortDirection
    }
}

public struct ThreadTurnsItemsListResponse: Equatable, Codable, Sendable {
    public let data: [AppServerThreadItem]
    public let nextCursor: String?
    public let backwardsCursor: String?

    private enum CodingKeys: String, CodingKey {
        case data
        case nextCursor
        case backwardsCursor
    }

    public init(data: [AppServerThreadItem], nextCursor: String?, backwardsCursor: String?) {
        self.data = data
        self.nextCursor = nextCursor
        self.backwardsCursor = backwardsCursor
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(data, forKey: .data)
        if let nextCursor {
            try container.encode(nextCursor, forKey: .nextCursor)
        } else {
            try container.encodeNil(forKey: .nextCursor)
        }
        if let backwardsCursor {
            try container.encode(backwardsCursor, forKey: .backwardsCursor)
        } else {
            try container.encodeNil(forKey: .backwardsCursor)
        }
    }
}
