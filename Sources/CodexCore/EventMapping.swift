import Foundation

public enum EventMapping {
    public static func parseTurnItem(_ item: ResponseItem) -> TurnItem? {
        switch item {
        case let .message(id, role, content, phase):
            switch role {
            case "user":
                if let hookPrompt = HookPromptItem.parseMessage(id: id, content: content) {
                    return .hookPrompt(hookPrompt)
                }
                return parseUserMessage(content).map(TurnItem.userMessage)
            case "assistant":
                return .agentMessage(parseAgentMessage(id: id, content: content, phase: phase))
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
            let action = action ?? .other
            return .webSearch(WebSearchItem(
                id: id ?? "",
                query: action.detail,
                action: action
            ))

        case let .imageGenerationCall(id, status, revisedPrompt, result):
            return .imageGeneration(ImageGenerationItem(
                id: id,
                status: status,
                revisedPrompt: revisedPrompt,
                result: result
            ))

        case .compaction,
             .contextCompaction,
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
        if message.contains(where: isContextualUserFragment) {
            return nil
        }

        var content: [UserInput] = []
        for contentItem in message {
            switch contentItem {
            case let .inputText(text):
                content.append(.text(text))

            case let .inputImage(imageURL, _):
                content.append(.image(imageURL: imageURL))

            case .outputText:
                continue
            }
        }

        return UserMessageItem(content: content)
    }

    private static func isContextualUserFragment(_ item: ContentItem) -> Bool {
        guard case let .inputText(text) = item else {
            return false
        }
        return HookPromptFragment.parseXML(text) != nil
            || ContextualUserFragments.isStandardText(text)
    }

    private static func parseAgentMessage(
        id: String?,
        content message: [ContentItem],
        phase: MessagePhase?
    ) -> AgentMessageItem {
        let content = message.compactMap { contentItem -> AgentMessageContent? in
            guard case let .outputText(text) = contentItem else {
                return nil
            }
            return .text(text)
        }
        return AgentMessageItem(id: id ?? UUID().uuidString.lowercased(), content: content, phase: phase)
    }

}
