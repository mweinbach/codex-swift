import Foundation

public struct HistoryEntry: Equatable, Codable, Sendable {
    public let sessionID: String
    public let ts: UInt64
    public let text: String

    private enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case ts
        case text
    }

    public init(sessionID: String, ts: UInt64, text: String) {
        self.sessionID = sessionID
        self.ts = ts
        self.text = text
    }
}
