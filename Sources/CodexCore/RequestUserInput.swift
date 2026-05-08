import Foundation

public struct RequestUserInputQuestionOption: Codable, Equatable, Sendable {
    public let label: String
    public let description: String

    public init(label: String, description: String) {
        self.label = label
        self.description = description
    }
}

public struct RequestUserInputQuestion: Codable, Equatable, Sendable {
    public let id: String
    public let header: String
    public let question: String
    public let isOther: Bool
    public let isSecret: Bool
    public let options: [RequestUserInputQuestionOption]?

    private enum CodingKeys: String, CodingKey {
        case id
        case header
        case question
        case isOther
        case isSecret
        case options
    }

    public init(
        id: String,
        header: String,
        question: String,
        isOther: Bool = false,
        isSecret: Bool = false,
        options: [RequestUserInputQuestionOption]? = nil
    ) {
        self.id = id
        self.header = header
        self.question = question
        self.isOther = isOther
        self.isSecret = isSecret
        self.options = options
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        header = try container.decode(String.self, forKey: .header)
        question = try container.decode(String.self, forKey: .question)
        isOther = try container.decodeIfPresent(Bool.self, forKey: .isOther) ?? false
        isSecret = try container.decodeIfPresent(Bool.self, forKey: .isSecret) ?? false
        options = try container.decodeIfPresent([RequestUserInputQuestionOption].self, forKey: .options)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(header, forKey: .header)
        try container.encode(question, forKey: .question)
        try container.encode(isOther, forKey: .isOther)
        try container.encode(isSecret, forKey: .isSecret)
        try container.encodeIfPresent(options, forKey: .options)
    }
}

public struct RequestUserInputArgs: Codable, Equatable, Sendable {
    public let questions: [RequestUserInputQuestion]

    public init(questions: [RequestUserInputQuestion]) {
        self.questions = questions
    }
}

public struct RequestUserInputAnswer: Codable, Equatable, Sendable {
    public let answers: [String]

    public init(answers: [String]) {
        self.answers = answers
    }
}

public struct RequestUserInputResponse: Codable, Equatable, Sendable {
    public let answers: [String: RequestUserInputAnswer]

    public init(answers: [String: RequestUserInputAnswer]) {
        self.answers = answers
    }
}

public struct RequestUserInputEvent: Codable, Equatable, Sendable {
    public let callID: String
    public let turnID: String
    public let questions: [RequestUserInputQuestion]

    private enum CodingKeys: String, CodingKey {
        case callID = "call_id"
        case turnID = "turn_id"
        case questions
    }

    public init(callID: String, turnID: String = "", questions: [RequestUserInputQuestion]) {
        self.callID = callID
        self.turnID = turnID
        self.questions = questions
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        callID = try container.decode(String.self, forKey: .callID)
        turnID = try container.decodeIfPresent(String.self, forKey: .turnID) ?? ""
        questions = try container.decode([RequestUserInputQuestion].self, forKey: .questions)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(callID, forKey: .callID)
        try container.encode(turnID, forKey: .turnID)
        try container.encode(questions, forKey: .questions)
    }
}
