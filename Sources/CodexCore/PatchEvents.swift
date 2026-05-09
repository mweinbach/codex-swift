import Foundation

public enum FileChange: Equatable, Codable, Sendable {
    case add(content: String)
    case delete(content: String)
    case update(unifiedDiff: String, movePath: String?)

    private enum CodingKeys: String, CodingKey {
        case type
        case content
        case unifiedDiff = "unified_diff"
        case movePath = "move_path"
    }

    private enum ChangeType: String, Codable {
        case add
        case delete
        case update
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(ChangeType.self, forKey: .type) {
        case .add:
            self = .add(content: try container.decode(String.self, forKey: .content))
        case .delete:
            self = .delete(content: try container.decode(String.self, forKey: .content))
        case .update:
            self = .update(
                unifiedDiff: try container.decode(String.self, forKey: .unifiedDiff),
                movePath: try container.decodeIfPresent(String.self, forKey: .movePath)
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .add(content):
            try container.encode(ChangeType.add, forKey: .type)
            try container.encode(content, forKey: .content)
        case let .delete(content):
            try container.encode(ChangeType.delete, forKey: .type)
            try container.encode(content, forKey: .content)
        case let .update(unifiedDiff, movePath):
            try container.encode(ChangeType.update, forKey: .type)
            try container.encode(unifiedDiff, forKey: .unifiedDiff)
            try container.encodeIfPresentOrNull(movePath, forKey: .movePath)
        }
    }
}

public enum PatchApplyStatus: String, Codable, Equatable, Sendable {
    case completed
    case failed
    case declined
}

public struct PatchApplyBeginEvent: Equatable, Codable, Sendable {
    public let callID: String
    public let turnID: String
    public let autoApproved: Bool
    public let changes: [String: FileChange]

    private enum CodingKeys: String, CodingKey {
        case callID = "call_id"
        case turnID = "turn_id"
        case autoApproved = "auto_approved"
        case changes
    }

    public init(
        callID: String,
        turnID: String = "",
        autoApproved: Bool,
        changes: [String: FileChange]
    ) {
        self.callID = callID
        self.turnID = turnID
        self.autoApproved = autoApproved
        self.changes = changes
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.callID = try container.decode(String.self, forKey: .callID)
        self.turnID = try container.decodeIfPresent(String.self, forKey: .turnID) ?? ""
        self.autoApproved = try container.decode(Bool.self, forKey: .autoApproved)
        self.changes = try container.decode([String: FileChange].self, forKey: .changes)
    }
}

public struct PatchApplyUpdatedEvent: Equatable, Codable, Sendable {
    public let callID: String
    public let changes: [String: FileChange]

    private enum CodingKeys: String, CodingKey {
        case callID = "call_id"
        case changes
    }

    public init(callID: String, changes: [String: FileChange]) {
        self.callID = callID
        self.changes = changes
    }
}

public struct PatchApplyEndEvent: Equatable, Codable, Sendable {
    public let callID: String
    public let turnID: String
    public let stdout: String
    public let stderr: String
    public let success: Bool
    public let changes: [String: FileChange]
    public let status: PatchApplyStatus

    private enum CodingKeys: String, CodingKey {
        case callID = "call_id"
        case turnID = "turn_id"
        case stdout
        case stderr
        case success
        case changes
        case status
    }

    public init(
        callID: String,
        turnID: String = "",
        stdout: String,
        stderr: String,
        success: Bool,
        changes: [String: FileChange] = [:],
        status: PatchApplyStatus? = nil
    ) {
        self.callID = callID
        self.turnID = turnID
        self.stdout = stdout
        self.stderr = stderr
        self.success = success
        self.changes = changes
        self.status = status ?? (success ? .completed : .failed)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.callID = try container.decode(String.self, forKey: .callID)
        self.turnID = try container.decodeIfPresent(String.self, forKey: .turnID) ?? ""
        self.stdout = try container.decode(String.self, forKey: .stdout)
        self.stderr = try container.decode(String.self, forKey: .stderr)
        self.success = try container.decode(Bool.self, forKey: .success)
        self.changes = try container.decodeIfPresent([String: FileChange].self, forKey: .changes) ?? [:]
        self.status = try container.decodeIfPresent(PatchApplyStatus.self, forKey: .status)
            ?? (success ? .completed : .failed)
    }
}

public struct TurnDiffEvent: Equatable, Codable, Sendable {
    public let unifiedDiff: String

    private enum CodingKeys: String, CodingKey {
        case unifiedDiff = "unified_diff"
    }

    public init(unifiedDiff: String) {
        self.unifiedDiff = unifiedDiff
    }
}

private extension KeyedEncodingContainer {
    mutating func encodeIfPresentOrNull<T: Encodable>(_ value: T?, forKey key: Key) throws {
        if let value {
            try encode(value, forKey: key)
        } else {
            try encodeNil(forKey: key)
        }
    }
}
