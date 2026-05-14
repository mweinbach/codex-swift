public struct ReviewStartParams: Equatable, Sendable {
    public let threadID: String
    public let target: ReviewTarget
    public let delivery: ReviewDelivery?

    private enum CodingKeys: String, CodingKey {
        case threadID = "threadId"
        case target
        case delivery
    }

    public init(threadID: String, target: ReviewTarget, delivery: ReviewDelivery? = nil) {
        self.threadID = threadID
        self.target = target
        self.delivery = delivery
    }
}

extension ReviewStartParams: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        threadID = try container.decode(String.self, forKey: .threadID)
        target = try container.decode(ReviewTarget.self, forKey: .target)
        delivery = try container.decodeIfPresent(ReviewDelivery.self, forKey: .delivery)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(threadID, forKey: .threadID)
        try container.encode(target, forKey: .target)
        try container.encodeNilOrValue(delivery, forKey: .delivery)
    }
}

public struct ReviewStartResponse: Equatable, Codable, Sendable {
    public let turn: AppServerTurn
    public let reviewThreadID: String

    private enum CodingKeys: String, CodingKey {
        case turn
        case reviewThreadID = "reviewThreadId"
    }

    public init(turn: AppServerTurn, reviewThreadID: String) {
        self.turn = turn
        self.reviewThreadID = reviewThreadID
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
