import Foundation

public enum StepStatus: String, Codable, CaseIterable, Equatable, Sendable {
    case pending
    case inProgress = "in_progress"
    case completed
}

public struct PlanItemArgument: Equatable, Codable, Sendable {
    public let step: String
    public let status: StepStatus

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case step
        case status
    }

    public init(step: String, status: StepStatus) {
        self.step = step
        self.status = status
    }

    public init(from decoder: Decoder) throws {
        try rejectUnknownKeys(decoder, allowedBy: CodingKeys.self)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        step = try container.decode(String.self, forKey: .step)
        status = try container.decode(StepStatus.self, forKey: .status)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(step, forKey: .step)
        try container.encode(status, forKey: .status)
    }
}

public struct UpdatePlanArguments: Equatable, Codable, Sendable {
    public let explanation: String?
    public let plan: [PlanItemArgument]

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case explanation
        case plan
    }

    public init(explanation: String? = nil, plan: [PlanItemArgument]) {
        self.explanation = explanation
        self.plan = plan
    }

    public init(from decoder: Decoder) throws {
        try rejectUnknownKeys(decoder, allowedBy: CodingKeys.self)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        explanation = try container.decodeIfPresent(String.self, forKey: .explanation)
        plan = try container.decode([PlanItemArgument].self, forKey: .plan)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(explanation, forKey: .explanation)
        try container.encode(plan, forKey: .plan)
    }
}

private struct PlanToolAnyCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}

private func rejectUnknownKeys<K: CodingKey & CaseIterable>(
    _ decoder: Decoder,
    allowedBy _: K.Type
) throws {
    let container = try decoder.container(keyedBy: PlanToolAnyCodingKey.self)
    let allowedKeys = Set(K.allCases.map(\.stringValue))
    if let unknown = container.allKeys.first(where: { !allowedKeys.contains($0.stringValue) }) {
        throw DecodingError.dataCorrupted(DecodingError.Context(
            codingPath: decoder.codingPath + [unknown],
            debugDescription: "unknown field `\(unknown.stringValue)`"
        ))
    }
}
