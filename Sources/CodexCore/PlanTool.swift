import Foundation

public enum StepStatus: String, Codable, Equatable, Sendable {
    case pending
    case inProgress = "in_progress"
    case completed
}

public struct PlanItemArgument: Codable, Equatable, Sendable {
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
        try PlanToolUnknownFields.reject(in: decoder, allowedKeys: CodingKeys.allCases)
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

public struct UpdatePlanArguments: Codable, Equatable, Sendable {
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
        try PlanToolUnknownFields.reject(in: decoder, allowedKeys: CodingKeys.allCases)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        explanation = try container.decodeIfPresent(String.self, forKey: .explanation)
        plan = try container.decode([PlanItemArgument].self, forKey: .plan)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let explanation {
            try container.encode(explanation, forKey: .explanation)
        } else {
            try container.encodeNil(forKey: .explanation)
        }
        try container.encode(plan, forKey: .plan)
    }
}

private enum PlanToolUnknownFields {
    static func reject<AllowedKey: CodingKey, AllowedKeys: Collection>(
        in decoder: Decoder,
        allowedKeys: AllowedKeys
    ) throws where AllowedKeys.Element == AllowedKey {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        let allowed = Set(allowedKeys.map(\.stringValue))
        if let unknownKey = container.allKeys.first(where: { !allowed.contains($0.stringValue) }) {
            throw DecodingError.keyNotFound(
                unknownKey,
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "unknown field `\(unknownKey.stringValue)`"
                )
            )
        }
    }
}

private struct DynamicCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}
