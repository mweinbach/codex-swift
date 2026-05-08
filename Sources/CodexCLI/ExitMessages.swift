import CodexCore
import Foundation

public struct AppExitInfo: Equatable, Sendable {
    public var tokenUsage: TokenUsage
    public var conversationID: ConversationId?
    public var updateAction: UpdateAction?

    public init(
        tokenUsage: TokenUsage,
        conversationID: ConversationId? = nil,
        updateAction: UpdateAction? = nil
    ) {
        self.tokenUsage = tokenUsage
        self.conversationID = conversationID
        self.updateAction = updateAction
    }
}

public enum ExitMessages {
    public static func formatExitMessages(_ exitInfo: AppExitInfo, colorEnabled: Bool) -> [String] {
        guard !exitInfo.tokenUsage.isZero else {
            return []
        }

        var lines = [FinalOutput(exitInfo.tokenUsage).description]
        if let conversationID = exitInfo.conversationID {
            let resumeCommand = "codex resume \(conversationID.description)"
            let command = colorEnabled ? cyan(resumeCommand) : resumeCommand
            lines.append("To continue this session, run \(command)")
        }
        return lines
    }

    private static func cyan(_ text: String) -> String {
        "\u{1B}[36m\(text)\u{1B}[0m"
    }
}
