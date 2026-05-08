import Foundation

public enum StreamEventUtils {
    public static func handleNonToolResponseItem(_ item: ResponseItem) -> TurnItem? {
        switch item {
        case .message,
             .reasoning,
             .webSearchCall:
            return EventMapping.parseTurnItem(item)
        case .functionCallOutput,
             .customToolCallOutput,
             .localShellCall,
             .functionCall,
             .customToolCall,
             .compaction,
             .knownPersisted,
             .other:
            return nil
        }
    }

    public static func lastAssistantMessage(from item: ResponseItem) -> String? {
        guard case let .message(_, role, content) = item,
              role == "assistant"
        else {
            return nil
        }

        return content.reversed().compactMap { item -> String? in
            if case let .outputText(text) = item {
                return text
            }
            return nil
        }.first
    }

    public static func responseInputToResponseItem(_ input: ResponseInputItem) -> ResponseItem? {
        switch input {
        case let .functionCallOutput(callID, output):
            return .functionCallOutput(callID: callID, output: output)
        case let .customToolCallOutput(callID, output):
            return .customToolCallOutput(callID: callID, output: output)
        case let .mcpToolCallOutput(callID, result):
            let output: FunctionCallOutputPayload
            switch result {
            case let .ok(callToolResult):
                output = FunctionCallOutputPayload(callToolResult: callToolResult)
            case let .err(error):
                output = FunctionCallOutputPayload(content: error, success: false)
            }
            return .functionCallOutput(callID: callID, output: output)
        case .message:
            return nil
        }
    }
}

public extension ResponseInputItem {
    func responseItem() -> ResponseItem {
        switch self {
        case let .message(role, content):
            return .message(role: role, content: content)
        case let .functionCallOutput(callID, output):
            return .functionCallOutput(callID: callID, output: output)
        case let .customToolCallOutput(callID, output):
            return .customToolCallOutput(callID: callID, output: output)
        case let .mcpToolCallOutput(callID, result):
            let output: FunctionCallOutputPayload
            switch result {
            case let .ok(callToolResult):
                output = FunctionCallOutputPayload(callToolResult: callToolResult)
            case let .err(error):
                output = FunctionCallOutputPayload(content: "err: \(String(reflecting: error))", success: false)
            }
            return .functionCallOutput(callID: callID, output: output)
        }
    }
}
