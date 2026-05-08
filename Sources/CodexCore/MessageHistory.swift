import Foundation

public struct HistoryEntry: Equatable, Codable, Sendable {
    public let conversationID: String
    public let ts: UInt64
    public let text: String

    private enum CodingKeys: String, CodingKey {
        case conversationID = "conversation_id"
        case ts
        case text
    }

    public init(conversationID: String, ts: UInt64, text: String) {
        self.conversationID = conversationID
        self.ts = ts
        self.text = text
    }
}
