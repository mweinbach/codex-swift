import Foundation

public enum TaskKind: String, Codable, Equatable, Sendable {
    case regular
    case review
    case compact
}

public struct PendingApprovalSender: Equatable, Sendable {
    public let identifier: String

    public init(identifier: String) {
        self.identifier = identifier
    }
}

public struct PendingRequestPermissions: Equatable, Sendable {
    public let sender: PendingApprovalSender
    public let requestedPermissions: RequestPermissionProfile
    public let cwd: String

    public init(sender: PendingApprovalSender, requestedPermissions: RequestPermissionProfile, cwd: String) {
        self.sender = sender
        self.requestedPermissions = requestedPermissions
        self.cwd = cwd
    }
}

public struct ElicitationKey: Equatable, Hashable, Sendable {
    public let serverName: String
    public let requestID: String

    public init(serverName: String, requestID: String) {
        self.serverName = serverName
        self.requestID = requestID
    }
}

public enum MailboxDeliveryPhase: String, Codable, Equatable, Sendable {
    case currentTurn
    case nextTurn
}

public struct RunningTask: Equatable, Sendable {
    public let subID: String
    public let kind: TaskKind
    public let turnContext: TurnContext

    public init(subID: String, kind: TaskKind, turnContext: TurnContext) {
        self.subID = subID
        self.kind = kind
        self.turnContext = turnContext
    }
}

public struct TurnState: Equatable, Sendable {
    private var pendingApprovals: [String: PendingApprovalSender]
    private var pendingRequestPermissions: [String: PendingRequestPermissions]
    private var pendingUserInput: [String: PendingApprovalSender]
    private var pendingElicitations: [ElicitationKey: PendingApprovalSender]
    private var pendingDynamicTools: [String: PendingApprovalSender]
    private var pendingInput: [ResponseInputItem]
    private var mailboxDeliveryPhase: MailboxDeliveryPhase
    private var grantedPermissions: RequestPermissionProfile?
    public private(set) var toolCallCount: UInt64
    public var hasMemoryCitation: Bool
    public private(set) var tokenUsageAtTurnStart: TokenUsage
    private var strictAutoReviewEnabled: Bool

    public init(
        pendingApprovals: [String: PendingApprovalSender] = [:],
        pendingRequestPermissions: [String: PendingRequestPermissions] = [:],
        pendingUserInput: [String: PendingApprovalSender] = [:],
        pendingElicitations: [ElicitationKey: PendingApprovalSender] = [:],
        pendingDynamicTools: [String: PendingApprovalSender] = [:],
        pendingInput: [ResponseInputItem] = [],
        mailboxDeliveryPhase: MailboxDeliveryPhase = .currentTurn,
        grantedPermissions: RequestPermissionProfile? = nil,
        toolCallCount: UInt64 = 0,
        hasMemoryCitation: Bool = false,
        tokenUsageAtTurnStart: TokenUsage = TokenUsage(),
        strictAutoReviewEnabled: Bool = false
    ) {
        self.pendingApprovals = pendingApprovals
        self.pendingRequestPermissions = pendingRequestPermissions
        self.pendingUserInput = pendingUserInput
        self.pendingElicitations = pendingElicitations
        self.pendingDynamicTools = pendingDynamicTools
        self.pendingInput = pendingInput
        self.mailboxDeliveryPhase = mailboxDeliveryPhase
        self.grantedPermissions = grantedPermissions
        self.toolCallCount = toolCallCount
        self.hasMemoryCitation = hasMemoryCitation
        self.tokenUsageAtTurnStart = tokenUsageAtTurnStart
        self.strictAutoReviewEnabled = strictAutoReviewEnabled
    }

    public var pendingApprovalCount: Int {
        pendingApprovals.count
    }

    public var pendingRequestPermissionsCount: Int {
        pendingRequestPermissions.count
    }

    public var pendingUserInputCount: Int {
        pendingUserInput.count
    }

    public var pendingElicitationCount: Int {
        pendingElicitations.count
    }

    public var pendingDynamicToolCount: Int {
        pendingDynamicTools.count
    }

    public var pendingInputCount: Int {
        pendingInput.count
    }

    public var hasPendingInput: Bool {
        !pendingInput.isEmpty
    }

    public var acceptsMailboxDeliveryForCurrentTurn: Bool {
        mailboxDeliveryPhase == .currentTurn
    }

    public var isStrictAutoReviewEnabled: Bool {
        strictAutoReviewEnabled
    }

    public var grantedPermissionsForTurn: RequestPermissionProfile? {
        grantedPermissions
    }

    @discardableResult
    public mutating func insertPendingApproval(
        key: String,
        sender: PendingApprovalSender
    ) -> PendingApprovalSender? {
        let previous = pendingApprovals[key]
        pendingApprovals[key] = sender
        return previous
    }

    @discardableResult
    public mutating func removePendingApproval(key: String) -> PendingApprovalSender? {
        pendingApprovals.removeValue(forKey: key)
    }

    @discardableResult
    public mutating func insertPendingRequestPermissions(
        key: String,
        pending: PendingRequestPermissions
    ) -> PendingRequestPermissions? {
        let previous = pendingRequestPermissions[key]
        pendingRequestPermissions[key] = pending
        return previous
    }

    @discardableResult
    public mutating func removePendingRequestPermissions(key: String) -> PendingRequestPermissions? {
        pendingRequestPermissions.removeValue(forKey: key)
    }

    @discardableResult
    public mutating func insertPendingUserInput(
        key: String,
        sender: PendingApprovalSender
    ) -> PendingApprovalSender? {
        let previous = pendingUserInput[key]
        pendingUserInput[key] = sender
        return previous
    }

    @discardableResult
    public mutating func removePendingUserInput(key: String) -> PendingApprovalSender? {
        pendingUserInput.removeValue(forKey: key)
    }

    @discardableResult
    public mutating func insertPendingElicitation(
        key: ElicitationKey,
        sender: PendingApprovalSender
    ) -> PendingApprovalSender? {
        let previous = pendingElicitations[key]
        pendingElicitations[key] = sender
        return previous
    }

    @discardableResult
    public mutating func removePendingElicitation(key: ElicitationKey) -> PendingApprovalSender? {
        pendingElicitations.removeValue(forKey: key)
    }

    @discardableResult
    public mutating func insertPendingDynamicTool(
        key: String,
        sender: PendingApprovalSender
    ) -> PendingApprovalSender? {
        let previous = pendingDynamicTools[key]
        pendingDynamicTools[key] = sender
        return previous
    }

    @discardableResult
    public mutating func removePendingDynamicTool(key: String) -> PendingApprovalSender? {
        pendingDynamicTools.removeValue(forKey: key)
    }

    public mutating func clearPending() {
        pendingApprovals.removeAll()
        pendingRequestPermissions.removeAll()
        pendingUserInput.removeAll()
        pendingElicitations.removeAll()
        pendingDynamicTools.removeAll()
        pendingInput.removeAll()
    }

    public mutating func pushPendingInput(_ input: ResponseInputItem) {
        pendingInput.append(input)
    }

    public mutating func prependPendingInput(_ input: [ResponseInputItem]) {
        guard !input.isEmpty else {
            return
        }
        pendingInput = input + pendingInput
    }

    public mutating func takePendingInput() -> [ResponseInputItem] {
        guard !pendingInput.isEmpty else {
            return []
        }
        let input = pendingInput
        pendingInput.removeAll(keepingCapacity: false)
        return input
    }

    public mutating func setMailboxDeliveryPhase(_ phase: MailboxDeliveryPhase) {
        mailboxDeliveryPhase = phase
    }

    public mutating func acceptMailboxDeliveryForCurrentTurn() {
        setMailboxDeliveryPhase(.currentTurn)
    }

    public mutating func recordGrantedPermissions(_ permissions: RequestPermissionProfile) {
        grantedPermissions = RequestPermissionProfile.mergeAdditionalPermissionProfiles(
            base: grantedPermissions,
            permissions: permissions
        )
    }

    public mutating func incrementToolCallCount() {
        toolCallCount += 1
    }

    public mutating func recordMemoryCitationForTurn() {
        hasMemoryCitation = true
    }

    public mutating func setTokenUsageAtTurnStart(_ tokenUsage: TokenUsage) {
        tokenUsageAtTurnStart = tokenUsage
    }

    public mutating func enableStrictAutoReview() {
        strictAutoReviewEnabled = true
    }
}

public struct ActiveTurn: Equatable, Sendable {
    private var tasksBySubID: [String: RunningTask]
    private var taskOrder: [String]
    public private(set) var turnState: TurnState

    public init(tasks: [RunningTask] = [], turnState: TurnState = TurnState()) {
        self.tasksBySubID = [:]
        self.taskOrder = []
        self.turnState = turnState

        for task in tasks {
            addTask(task)
        }
    }

    public var taskCount: Int {
        tasksBySubID.count
    }

    public var taskSubIDs: [String] {
        taskOrder
    }

    public mutating func addTask(_ task: RunningTask) {
        if tasksBySubID[task.subID] == nil {
            taskOrder.append(task.subID)
        }
        tasksBySubID[task.subID] = task
    }

    @discardableResult
    public mutating func removeTask(subID: String) -> Bool {
        guard tasksBySubID.removeValue(forKey: subID) != nil,
              let index = taskOrder.firstIndex(of: subID)
        else {
            return tasksBySubID.isEmpty
        }

        let lastSubID = taskOrder.removeLast()
        if index < taskOrder.count {
            taskOrder[index] = lastSubID
        }
        return tasksBySubID.isEmpty
    }

    public mutating func drainTasks() -> [RunningTask] {
        let tasks = taskOrder.compactMap { tasksBySubID[$0] }
        taskOrder.removeAll(keepingCapacity: false)
        tasksBySubID.removeAll(keepingCapacity: false)
        return tasks
    }

    public mutating func clearPending() {
        turnState.clearPending()
    }
}
