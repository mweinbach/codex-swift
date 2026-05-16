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
        for (index, contentItem) in message.enumerated() {
            switch contentItem {
            case let .inputText(text):
                if isImageWrapperText(text, at: index, in: message) {
                    continue
                }
                content.append(.text(text))

            case let .inputImage(imageURL, detail):
                content.append(.image(imageURL: imageURL, detail: detail))

            case .outputText:
                continue
            }
        }

        return UserMessageItem(content: content)
    }

    private static func isImageWrapperText(_ text: String, at index: Int, in message: [ContentItem]) -> Bool {
        if (isLocalImageOpenTagText(text) || isImageOpenTagText(text)),
           message.indices.contains(index + 1),
           case .inputImage = message[index + 1] {
            return true
        }

        if index > 0,
           isImageCloseTagText(text),
           case .inputImage = message[index - 1] {
            return true
        }

        return false
    }

    private static func isImageOpenTagText(_ text: String) -> Bool {
        text == "<image>"
    }

    private static func isImageCloseTagText(_ text: String) -> Bool {
        text == "</image>"
    }

    private static func isLocalImageOpenTagText(_ text: String) -> Bool {
        text.hasPrefix("<image name=") && text.hasSuffix(">")
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
