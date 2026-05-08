import Foundation

public enum StepStatus: String, Codable, CaseIterable, Equatable, Sendable {
    case pending
    case inProgress = "in_progress"
    case completed
}

public struct PlanItemArgument: Equatable, Codable, Sendable {
    public let step: String
    public let status: StepStatus

    public init(step: String, status: StepStatus) {
        self.step = step
        self.status = status
    }
}

public struct UpdatePlanArguments: Equatable, Codable, Sendable {
    public let explanation: String?
    public let plan: [PlanItemArgument]

    public init(explanation: String? = nil, plan: [PlanItemArgument]) {
        self.explanation = explanation
        self.plan = plan
    }
}
