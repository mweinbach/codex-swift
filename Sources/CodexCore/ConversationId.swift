import Foundation

public struct ConversationId: Equatable, Hashable, Codable, CustomStringConvertible, Sendable {
    public let uuid: UUID

    public init() {
        self.uuid = UUID.v7()
    }

    public init(uuid: UUID) {
        self.uuid = uuid
    }

    public init(string: String) throws {
        guard let uuid = UUID(uuidString: string) else {
            throw ConversationIdError.invalidUUID(string)
        }
        self.uuid = uuid
    }

    public var description: String {
        uuid.uuidString.lowercased()
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self = try ConversationId(string: container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}

public enum ConversationIdError: Error, Equatable, CustomStringConvertible, Sendable {
    case invalidUUID(String)

    public var description: String {
        switch self {
        case let .invalidUUID(value):
            return "Invalid conversation id: \(value)"
        }
    }
}

public struct ThreadId: Equatable, Hashable, Codable, CustomStringConvertible, Sendable {
    public let uuid: UUID

    public init() {
        self.uuid = UUID.v7()
    }

    public init(uuid: UUID) {
        self.uuid = uuid
    }

    public init(string: String) throws {
        guard let uuid = UUID(uuidString: string) else {
            throw ThreadIdError.invalidUUID(string)
        }
        self.uuid = uuid
    }

    public var description: String {
        uuid.uuidString.lowercased()
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self = try ThreadId(string: container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}

public enum ThreadIdError: Error, Equatable, CustomStringConvertible, Sendable {
    case invalidUUID(String)

    public var description: String {
        switch self {
        case let .invalidUUID(value):
            return "Invalid thread id: \(value)"
        }
    }
}

public struct SessionId: Equatable, Hashable, Codable, CustomStringConvertible, Sendable {
    public let uuid: UUID

    public init() {
        self.uuid = UUID.v7()
    }

    public init(uuid: UUID) {
        self.uuid = uuid
    }

    public init(threadID: ThreadId) {
        self.uuid = threadID.uuid
    }

    public init(string: String) throws {
        guard let uuid = UUID(uuidString: string) else {
            throw SessionIdError.invalidUUID(string)
        }
        self.uuid = uuid
    }

    public var threadID: ThreadId {
        ThreadId(uuid: uuid)
    }

    public var description: String {
        uuid.uuidString.lowercased()
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self = try SessionId(string: container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}

public enum SessionIdError: Error, Equatable, CustomStringConvertible, Sendable {
    case invalidUUID(String)

    public var description: String {
        switch self {
        case let .invalidUUID(value):
            return "Invalid session id: \(value)"
        }
    }
}

extension ThreadId {
    public init(sessionID: SessionId) {
        self.init(uuid: sessionID.uuid)
    }
}

extension UUID {
    static func v7(date: Date = Date()) -> UUID {
        let milliseconds = UInt64((date.timeIntervalSince1970 * 1_000.0).rounded(.down))
        var random = SystemRandomNumberGenerator()
        var bytes = (0..<16).map { _ in UInt8.random(in: UInt8.min...UInt8.max, using: &random) }

        bytes[0] = UInt8((milliseconds >> 40) & 0xff)
        bytes[1] = UInt8((milliseconds >> 32) & 0xff)
        bytes[2] = UInt8((milliseconds >> 24) & 0xff)
        bytes[3] = UInt8((milliseconds >> 16) & 0xff)
        bytes[4] = UInt8((milliseconds >> 8) & 0xff)
        bytes[5] = UInt8(milliseconds & 0xff)
        bytes[6] = (bytes[6] & 0x0f) | 0x70
        bytes[8] = (bytes[8] & 0x3f) | 0x80

        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}
