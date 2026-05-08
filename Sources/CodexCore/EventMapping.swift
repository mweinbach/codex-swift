import Foundation

public enum EventMapping {
    public static func parseTurnItem(_ item: ResponseItem) -> TurnItem? {
        switch item {
        case let .message(id, role, content):
            switch role {
            case "user":
                return parseUserMessage(content).map(TurnItem.userMessage)
            case "assistant":
                return .agentMessage(parseAgentMessage(id: id, content: content))
            case "system":
                return nil
            default:
                return nil
            }

        case let .reasoning(id, summary, content, _):
            let summaryText = summary.map { entry in
                switch entry {
                case let .summaryText(text):
                    return text
                }
            }
            let rawContent = (content ?? []).map { entry in
                switch entry {
                case let .reasoningText(text), let .text(text):
                    return text
                }
            }
            return .reasoning(ReasoningItem(id: id, summaryText: summaryText, rawContent: rawContent))

        case let .webSearchCall(id, _, action):
            guard case let .some(.search(query)) = action else {
                return nil
            }
            return .webSearch(WebSearchItem(id: id ?? "", query: query ?? ""))

        case let .imageGenerationCall(id, status, revisedPrompt, result):
            return .imageGeneration(ImageGenerationItem(
                id: id,
                status: status,
                revisedPrompt: revisedPrompt,
                result: result
            ))

        case .compaction,
             .localShellCall,
             .functionCall,
             .toolSearchCall,
             .functionCallOutput,
             .customToolCall,
             .customToolCallOutput,
             .toolSearchOutput,
             .ghostSnapshot,
             .knownPersisted,
             .other:
            return nil
        }
    }

    private static func parseUserMessage(_ message: [ContentItem]) -> UserMessageItem? {
        if UserInstructions.isUserInstructions(message: message)
            || SkillInstructions.isSkillInstructions(message: message)
        {
            return nil
        }

        var content: [UserInput] = []
        for contentItem in message {
            switch contentItem {
            case let .inputText(text):
                if isSessionPrefix(text) || UserShellCommand.isUserShellCommandText(text) {
                    return nil
                }
                content.append(.text(text))

            case let .inputImage(imageURL):
                content.append(.image(imageURL: imageURL))

            case let .outputText(text):
                if isSessionPrefix(text) {
                    return nil
                }
            }
        }

        return UserMessageItem(content: content)
    }

    private static func parseAgentMessage(id: String?, content message: [ContentItem]) -> AgentMessageItem {
        let content = message.compactMap { contentItem -> AgentMessageContent? in
            guard case let .outputText(text) = contentItem else {
                return nil
            }
            return .text(text)
        }
        return AgentMessageItem(id: id ?? UUID().uuidString.lowercased(), content: content)
    }

    private static func isSessionPrefix(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .hasPrefix("<environment_context>")
    }
}
