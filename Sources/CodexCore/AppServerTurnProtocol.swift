import Foundation

public struct AppServerTurnEnvironmentParams: Codable, Equatable, Sendable {
    public let environmentID: String
    public let cwd: AbsolutePath

    private enum CodingKeys: String, CodingKey {
        case environmentID = "environmentId"
        case cwd
    }

    public init(environmentID: String, cwd: AbsolutePath) {
        self.environmentID = environmentID
        self.cwd = cwd
    }
}

public enum AppServerServiceTierOverride: Equatable, Sendable {
    case clear
    case set(String)
}

public struct AppServerTurnStartParams: Equatable, Sendable {
    public let threadID: String
    public let input: [AppServerUserInput]
    public let responsesapiClientMetadata: [String: String]?
    public let environments: [AppServerTurnEnvironmentParams]?
    public let cwd: String?
    public let approvalPolicy: AskForApproval?
    public let approvalsReviewer: ApprovalsReviewer?
    public let sandboxPolicy: AppServerSandboxPolicy?
    public let permissions: AppServerPermissionProfileSelectionParams?
    public let model: String?
    public let serviceTier: AppServerServiceTierOverride?
    public let effort: ReasoningEffort?
    public let summary: ReasoningSummary?
    public let personality: Personality?
    public let outputSchema: JSONValue?
    public let collaborationMode: CollaborationMode?

    private enum CodingKeys: String, CodingKey {
        case threadID = "threadId"
        case input
        case responsesapiClientMetadata
        case environments
        case cwd
        case approvalPolicy
        case approvalsReviewer
        case sandboxPolicy
        case permissions
        case model
        case serviceTier
        case effort
        case summary
        case personality
        case outputSchema
        case collaborationMode
    }

    public init(
        threadID: String,
        input: [AppServerUserInput],
        responsesapiClientMetadata: [String: String]? = nil,
        environments: [AppServerTurnEnvironmentParams]? = nil,
        cwd: String? = nil,
        approvalPolicy: AskForApproval? = nil,
        approvalsReviewer: ApprovalsReviewer? = nil,
        sandboxPolicy: AppServerSandboxPolicy? = nil,
        permissions: AppServerPermissionProfileSelectionParams? = nil,
        model: String? = nil,
        serviceTier: AppServerServiceTierOverride? = nil,
        effort: ReasoningEffort? = nil,
        summary: ReasoningSummary? = nil,
        personality: Personality? = nil,
        outputSchema: JSONValue? = nil,
        collaborationMode: CollaborationMode? = nil
    ) {
        self.threadID = threadID
        self.input = input
        self.responsesapiClientMetadata = responsesapiClientMetadata
        self.environments = environments
        self.cwd = cwd
        self.approvalPolicy = approvalPolicy
        self.approvalsReviewer = approvalsReviewer
        self.sandboxPolicy = sandboxPolicy
        self.permissions = permissions
        self.model = model
        self.serviceTier = serviceTier
        self.effort = effort
        self.summary = summary
        self.personality = personality
        self.outputSchema = outputSchema
        self.collaborationMode = collaborationMode
    }
}

extension AppServerTurnStartParams: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        threadID = try container.decode(String.self, forKey: .threadID)
        input = try container.decode([AppServerUserInput].self, forKey: .input)
        responsesapiClientMetadata = try container.decodeIfPresent(
            [String: String].self,
            forKey: .responsesapiClientMetadata
        )
        environments = try container.decodeIfPresent([AppServerTurnEnvironmentParams].self, forKey: .environments)
        cwd = try container.decodeIfPresent(String.self, forKey: .cwd)
        approvalPolicy = try container.decodeIfPresent(AskForApproval.self, forKey: .approvalPolicy)
        approvalsReviewer = try container.decodeIfPresent(ApprovalsReviewer.self, forKey: .approvalsReviewer)
        sandboxPolicy = try container.decodeIfPresent(AppServerSandboxPolicy.self, forKey: .sandboxPolicy)
        permissions = try container.decodeIfPresent(
            AppServerPermissionProfileSelectionParams.self,
            forKey: .permissions
        )
        model = try container.decodeIfPresent(String.self, forKey: .model)
        if container.contains(.serviceTier) {
            if try container.decodeNil(forKey: .serviceTier) {
                serviceTier = .clear
            } else {
                serviceTier = .set(try container.decode(String.self, forKey: .serviceTier))
            }
        } else {
            serviceTier = nil
        }
        effort = try container.decodeIfPresent(ReasoningEffort.self, forKey: .effort)
        summary = try container.decodeIfPresent(ReasoningSummary.self, forKey: .summary)
        personality = try container.decodeIfPresent(Personality.self, forKey: .personality)
        outputSchema = try container.decodeIfPresent(JSONValue.self, forKey: .outputSchema)
        collaborationMode = try container.decodeIfPresent(CollaborationMode.self, forKey: .collaborationMode)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(threadID, forKey: .threadID)
        try container.encode(input, forKey: .input)
        try container.encodeNilOrValue(responsesapiClientMetadata, forKey: .responsesapiClientMetadata)
        try container.encodeNilOrValue(environments, forKey: .environments)
        try container.encodeNilOrValue(cwd, forKey: .cwd)
        try container.encodeNilOrValue(approvalPolicy, forKey: .approvalPolicy)
        try container.encodeNilOrValue(approvalsReviewer, forKey: .approvalsReviewer)
        try container.encodeNilOrValue(sandboxPolicy, forKey: .sandboxPolicy)
        try container.encodeNilOrValue(permissions, forKey: .permissions)
        try container.encodeNilOrValue(model, forKey: .model)
        switch serviceTier {
        case .clear:
            try container.encodeNil(forKey: .serviceTier)
        case let .set(value):
            try container.encode(value, forKey: .serviceTier)
        case nil:
            break
        }
        try container.encodeNilOrValue(effort, forKey: .effort)
        try container.encodeNilOrValue(summary, forKey: .summary)
        try container.encodeNilOrValue(personality, forKey: .personality)
        try container.encodeNilOrValue(outputSchema, forKey: .outputSchema)
        try container.encodeNilOrValue(collaborationMode, forKey: .collaborationMode)
    }
}

public struct AppServerTurnStartResponse: Codable, Equatable, Sendable {
    public let turn: AppServerTurn

    public init(turn: AppServerTurn) {
        self.turn = turn
    }
}

public struct AppServerTurnSteerParams: Codable, Equatable, Sendable {
    public let threadID: String
    public let input: [AppServerUserInput]
    public let responsesapiClientMetadata: [String: String]?
    public let expectedTurnID: String

    private enum CodingKeys: String, CodingKey {
        case threadID = "threadId"
        case input
        case responsesapiClientMetadata
        case expectedTurnID = "expectedTurnId"
    }

    public init(
        threadID: String,
        input: [AppServerUserInput],
        responsesapiClientMetadata: [String: String]? = nil,
        expectedTurnID: String
    ) {
        self.threadID = threadID
        self.input = input
        self.responsesapiClientMetadata = responsesapiClientMetadata
        self.expectedTurnID = expectedTurnID
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(threadID, forKey: .threadID)
        try container.encode(input, forKey: .input)
        try container.encodeNilOrValue(responsesapiClientMetadata, forKey: .responsesapiClientMetadata)
        try container.encode(expectedTurnID, forKey: .expectedTurnID)
    }
}

public struct AppServerTurnSteerResponse: Codable, Equatable, Sendable {
    public let turnID: String

    private enum CodingKeys: String, CodingKey {
        case turnID = "turnId"
    }

    public init(turnID: String) {
        self.turnID = turnID
    }
}

public struct AppServerTurnInterruptParams: Codable, Equatable, Sendable {
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

public struct AppServerTurnInterruptResponse: Codable, Equatable, Sendable {
    public init() {}
}

public struct AppServerByteRange: Codable, Equatable, Sendable {
    public let start: Int
    public let end: Int

    public init(start: Int, end: Int) {
        self.start = start
        self.end = end
    }

    public init(core: ByteRange) {
        self.init(start: core.start, end: core.end)
    }

    public var coreValue: ByteRange {
        ByteRange(start: start, end: end)
    }
}

public struct AppServerTextElement: Equatable, Sendable {
    public let byteRange: AppServerByteRange
    public let placeholder: String?

    private enum CodingKeys: String, CodingKey {
        case byteRange
        case placeholder
    }

    public init(byteRange: AppServerByteRange, placeholder: String? = nil) {
        self.byteRange = byteRange
        self.placeholder = placeholder
    }

    public init(core: TextElement) {
        self.init(byteRange: AppServerByteRange(core: core.byteRange), placeholder: core.placeholder)
    }

    public var coreValue: TextElement {
        TextElement(byteRange: byteRange.coreValue, placeholder: placeholder)
    }
}

extension AppServerTextElement: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        byteRange = try container.decode(AppServerByteRange.self, forKey: .byteRange)
        placeholder = try container.decodeIfPresent(String.self, forKey: .placeholder)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(byteRange, forKey: .byteRange)
        try container.encodeNilOrValue(placeholder, forKey: .placeholder)
    }
}

public enum AppServerUserInput: Equatable, Sendable {
    case text(String, textElements: [AppServerTextElement] = [])
    case image(url: String, detail: ImageDetail? = nil)
    case localImage(path: String, detail: ImageDetail? = nil)
    case skill(name: String, path: String)
    case mention(name: String, path: String)

    private enum CodingKeys: String, CodingKey {
        case type
        case text
        case textElements
        case url
        case path
        case detail
        case name
    }

    private enum InputType: String, Codable {
        case text
        case image
        case localImage
        case skill
        case mention
    }

    public init(core: UserInput) {
        switch core {
        case let .text(text, textElements):
            self = .text(text, textElements: textElements.map(AppServerTextElement.init))
        case let .image(imageURL, detail):
            self = .image(url: imageURL, detail: detail)
        case let .localImage(path, detail):
            self = .localImage(path: path, detail: detail)
        case let .skill(name, path):
            self = .skill(name: name, path: path)
        case let .mention(name, path):
            self = .mention(name: name, path: path)
        }
    }

    public var coreValue: UserInput {
        switch self {
        case let .text(text, textElements):
            .text(text, textElements: textElements.map(\.coreValue))
        case let .image(url, detail):
            .image(imageURL: url, detail: detail)
        case let .localImage(path, detail):
            .localImage(path: path, detail: detail)
        case let .skill(name, path):
            .skill(name: name, path: path)
        case let .mention(name, path):
            .mention(name: name, path: path)
        }
    }

    public var textCharacterCount: Int {
        switch self {
        case let .text(text, _):
            text.count
        case .image, .localImage, .skill, .mention:
            0
        }
    }
}

extension AppServerUserInput: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(InputType.self, forKey: .type) {
        case .text:
            self = .text(
                try container.decode(String.self, forKey: .text),
                textElements: try container.decodeRustDefaulted(
                    [AppServerTextElement].self,
                    forKey: .textElements,
                    defaultValue: []
                )
            )
        case .image:
            self = .image(
                url: try container.decode(String.self, forKey: .url),
                detail: try container.decodeUserInputImageDetailIfPresent(forKey: .detail)
            )
        case .localImage:
            self = .localImage(
                path: try container.decode(String.self, forKey: .path),
                detail: try container.decodeUserInputImageDetailIfPresent(forKey: .detail)
            )
        case .skill:
            self = .skill(
                name: try container.decode(String.self, forKey: .name),
                path: try container.decode(String.self, forKey: .path)
            )
        case .mention:
            self = .mention(
                name: try container.decode(String.self, forKey: .name),
                path: try container.decode(String.self, forKey: .path)
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .text(text, textElements):
            try container.encode(InputType.text, forKey: .type)
            try container.encode(text, forKey: .text)
            try container.encode(textElements, forKey: .textElements)
        case let .image(url, detail):
            try container.encode(InputType.image, forKey: .type)
            try container.encode(url, forKey: .url)
            try container.encodeNilOrValue(detail, forKey: .detail)
        case let .localImage(path, detail):
            try container.encode(InputType.localImage, forKey: .type)
            try container.encode(path, forKey: .path)
            try container.encodeNilOrValue(detail, forKey: .detail)
        case let .skill(name, path):
            try container.encode(InputType.skill, forKey: .type)
            try container.encode(name, forKey: .name)
            try container.encode(path, forKey: .path)
        case let .mention(name, path):
            try container.encode(InputType.mention, forKey: .type)
            try container.encode(name, forKey: .name)
            try container.encode(path, forKey: .path)
        }
    }
}

public struct TurnStartedNotification: Codable, Equatable, Sendable {
    public let threadID: String
    public let turn: AppServerTurn

    private enum CodingKeys: String, CodingKey {
        case threadID = "threadId"
        case turn
    }

    public init(threadID: String, turn: AppServerTurn) {
        self.threadID = threadID
        self.turn = turn
    }
}

public struct TurnUsage: Codable, Equatable, Sendable {
    public let inputTokens: Int
    public let cachedInputTokens: Int
    public let outputTokens: Int

    public init(inputTokens: Int, cachedInputTokens: Int, outputTokens: Int) {
        self.inputTokens = inputTokens
        self.cachedInputTokens = cachedInputTokens
        self.outputTokens = outputTokens
    }
}

public struct TurnCompletedNotification: Codable, Equatable, Sendable {
    public let threadID: String
    public let turn: AppServerTurn

    private enum CodingKeys: String, CodingKey {
        case threadID = "threadId"
        case turn
    }

    public init(threadID: String, turn: AppServerTurn) {
        self.threadID = threadID
        self.turn = turn
    }
}

public struct TurnDiffUpdatedNotification: Codable, Equatable, Sendable {
    public let threadID: String
    public let turnID: String
    public let diff: String

    private enum CodingKeys: String, CodingKey {
        case threadID = "threadId"
        case turnID = "turnId"
        case diff
    }

    public init(threadID: String, turnID: String, diff: String) {
        self.threadID = threadID
        self.turnID = turnID
        self.diff = diff
    }
}

public struct TurnPlanUpdatedNotification: Equatable, Sendable {
    public let threadID: String
    public let turnID: String
    public let explanation: String?
    public let plan: [TurnPlanStep]

    private enum CodingKeys: String, CodingKey {
        case threadID = "threadId"
        case turnID = "turnId"
        case explanation
        case plan
    }

    public init(threadID: String, turnID: String, explanation: String? = nil, plan: [TurnPlanStep]) {
        self.threadID = threadID
        self.turnID = turnID
        self.explanation = explanation
        self.plan = plan
    }
}

extension TurnPlanUpdatedNotification: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        threadID = try container.decode(String.self, forKey: .threadID)
        turnID = try container.decode(String.self, forKey: .turnID)
        explanation = try container.decodeIfPresent(String.self, forKey: .explanation)
        plan = try container.decode([TurnPlanStep].self, forKey: .plan)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(threadID, forKey: .threadID)
        try container.encode(turnID, forKey: .turnID)
        try container.encodeNilOrValue(explanation, forKey: .explanation)
        try container.encode(plan, forKey: .plan)
    }
}

public struct TurnPlanStep: Codable, Equatable, Sendable {
    public let step: String
    public let status: TurnPlanStepStatus

    public init(step: String, status: TurnPlanStepStatus) {
        self.step = step
        self.status = status
    }

    public init(core: PlanItemArgument) {
        self.init(step: core.step, status: TurnPlanStepStatus(core: core.status))
    }
}

public enum TurnPlanStepStatus: String, Codable, Equatable, Sendable {
    case pending
    case inProgress
    case completed

    public init(core: StepStatus) {
        switch core {
        case .pending:
            self = .pending
        case .inProgress:
            self = .inProgress
        case .completed:
            self = .completed
        }
    }
}

private extension KeyedEncodingContainer {
    mutating func encodeNilOrValue<T: Encodable>(_ value: T?, forKey key: Key) throws {
        if let value {
            try encode(value, forKey: key)
        } else {
            try encodeNil(forKey: key)
        }
    }
}
