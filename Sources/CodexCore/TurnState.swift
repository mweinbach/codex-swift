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
    private var pendingInput: [ResponseInputItem]

    public init(
        pendingApprovals: [String: PendingApprovalSender] = [:],
        pendingInput: [ResponseInputItem] = []
    ) {
        self.pendingApprovals = pendingApprovals
        self.pendingInput = pendingInput
    }

    public var pendingApprovalCount: Int {
        pendingApprovals.count
    }

    public var pendingInputCount: Int {
        pendingInput.count
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

    public mutating func clearPending() {
        pendingApprovals.removeAll()
        pendingInput.removeAll()
    }

    public mutating func pushPendingInput(_ input: ResponseInputItem) {
        pendingInput.append(input)
    }

    public mutating func takePendingInput() -> [ResponseInputItem] {
        guard !pendingInput.isEmpty else {
            return []
        }
        let input = pendingInput
        pendingInput.removeAll(keepingCapacity: false)
        return input
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
