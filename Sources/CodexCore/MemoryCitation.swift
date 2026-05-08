import Foundation

public struct MemoryCitation: Equatable, Codable, Sendable {
    public let entries: [MemoryCitationEntry]
    public let rolloutIDs: [String]

    private enum CodingKeys: String, CodingKey {
        case entries
        case rolloutIDs = "rolloutIds"
    }

    public init(entries: [MemoryCitationEntry] = [], rolloutIDs: [String] = []) {
        self.entries = entries
        self.rolloutIDs = rolloutIDs
    }
}

public struct MemoryCitationEntry: Equatable, Codable, Sendable {
    public let path: String
    public let lineStart: UInt32
    public let lineEnd: UInt32
    public let note: String

    private enum CodingKeys: String, CodingKey {
        case path
        case lineStart
        case lineEnd
        case note
    }

    public init(path: String, lineStart: UInt32, lineEnd: UInt32, note: String) {
        self.path = path
        self.lineStart = lineStart
        self.lineEnd = lineEnd
        self.note = note
    }
}
