import Foundation

public struct InterAgentCommunication: Codable, Equatable, Sendable {
    public let author: AgentPath
    public let recipient: AgentPath
    public let otherRecipients: [AgentPath]
    public let content: String
    public let triggerTurn: Bool

    public init(
        author: AgentPath,
        recipient: AgentPath,
        otherRecipients: [AgentPath] = [],
        content: String,
        triggerTurn: Bool
    ) {
        self.author = author
        self.recipient = recipient
        self.otherRecipients = otherRecipients
        self.content = content
        self.triggerTurn = triggerTurn
    }

    public static func fromMessageContent(_ content: [ContentItem]) -> InterAgentCommunication? {
        guard content.count == 1 else {
            return nil
        }

        let text: String
        switch content[0] {
        case let .inputText(value), let .outputText(value):
            text = value
        case .inputImage:
            return nil
        }
        return try? JSONDecoder().decode(InterAgentCommunication.self, from: Data(text.utf8))
    }

    public static func isMessageContent(_ content: [ContentItem]) -> Bool {
        fromMessageContent(content) != nil
    }

    private enum CodingKeys: String, CodingKey {
        case author
        case recipient
        case otherRecipients = "other_recipients"
        case content
        case triggerTurn = "trigger_turn"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.author = try container.decode(AgentPath.self, forKey: .author)
        self.recipient = try container.decode(AgentPath.self, forKey: .recipient)
        self.otherRecipients = try container.decodeIfPresent([AgentPath].self, forKey: .otherRecipients) ?? []
        self.content = try container.decode(String.self, forKey: .content)
        self.triggerTurn = try container.decode(Bool.self, forKey: .triggerTurn)
    }
}
