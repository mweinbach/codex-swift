import Foundation

public struct ChatSSEParser: Sendable {
    private struct ToolCallState: Sendable {
        var id: String?
        var name: String?
        var arguments = ""
    }

    private var toolCalls: [Int: ToolCallState] = [:]
    private var toolCallOrder: [Int] = []
    private var toolCallOrderSeen: Set<Int> = []
    private var toolCallIndexByID: [String: Int] = [:]
    private var nextToolCallIndex = 0
    private var lastToolCallIndex: Int?
    private var assistantItem: ResponseItem?
    private var reasoningItem: ResponseItem?
    private var completedSent = false
    private var terminated = false

    public init() {}

    public mutating func receive(data: String) -> [Result<ResponseEvent, APIError>] {
        guard !terminated else {
            return []
        }

        let trimmed = data.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let value = try? JSONDecoder().decode(JSONValue.self, from: Data(data.utf8)),
              case let .object(root) = value,
              let choices = root["choices"]?.arrayValue
        else {
            return []
        }

        var output: [Result<ResponseEvent, APIError>] = []
        for choiceValue in choices {
            guard case let .object(choice) = choiceValue else {
                continue
            }

            if case let .object(delta)? = choice["delta"] {
                if let reasoning = delta["reasoning"] {
                    appendReasoningText(reasoning.chatReasoningText, to: &output)
                }

                if let content = delta["content"] {
                    appendContent(content, to: &output)
                }

                if let toolCallValues = delta["tool_calls"]?.arrayValue {
                    for toolCall in toolCallValues {
                        receiveToolCall(toolCall)
                    }
                }
            }

            if case let .object(message)? = choice["message"],
               let reasoning = message["reasoning"]
            {
                appendReasoningText(reasoning.chatReasoningText, to: &output)
            }

            switch choice["finish_reason"]?.stringValue {
            case "stop":
                flushReasoning(to: &output)
                flushAssistant(to: &output)
                if !completedSent {
                    output.append(.success(.completed(responseID: "", tokenUsage: nil)))
                    completedSent = true
                }

            case "length":
                output.append(.failure(.contextWindowExceeded))
                terminated = true
                return output

            case "tool_calls":
                flushReasoning(to: &output)
                flushToolCalls(to: &output)

            default:
                break
            }
        }

        return output
    }

    public mutating func finish() -> [Result<ResponseEvent, APIError>] {
        guard !terminated else {
            return []
        }

        var output: [Result<ResponseEvent, APIError>] = []
        flushReasoning(to: &output)
        flushAssistant(to: &output)
        if !completedSent {
            output.append(.success(.completed(responseID: "", tokenUsage: nil)))
            completedSent = true
        }
        return output
    }

    public static func collectEvents(fromSSEText text: String) -> [Result<ResponseEvent, APIError>] {
        var parser = ChatSSEParser()
        var results: [Result<ResponseEvent, APIError>] = []
        for frame in ResponsesSSEParser.dataFrames(fromSSEText: text) {
            results.append(contentsOf: parser.receive(data: frame))
        }
        results.append(contentsOf: parser.finish())
        return results
    }

    private mutating func appendContent(_ content: JSONValue, to output: inout [Result<ResponseEvent, APIError>]) {
        if let items = content.arrayValue {
            for item in items {
                guard case let .object(object) = item,
                      let text = object["text"]?.stringValue
                else {
                    continue
                }
                appendAssistantText(text, to: &output)
            }
            return
        }

        if let text = content.stringValue {
            appendAssistantText(text, to: &output)
        }
    }

    private mutating func appendAssistantText(_ text: String?, to output: inout [Result<ResponseEvent, APIError>]) {
        guard let text else {
            return
        }

        if assistantItem == nil {
            let item = ResponseItem.message(role: "assistant", content: [])
            assistantItem = item
            output.append(.success(.outputItemAdded(item)))
        }

        if case let .message(id, role, content)? = assistantItem {
            var updatedContent = content
            updatedContent.append(.outputText(text: text))
            assistantItem = .message(id: id, role: role, content: updatedContent)
            output.append(.success(.outputTextDelta(text)))
        }
    }

    private mutating func appendReasoningText(_ text: String?, to output: inout [Result<ResponseEvent, APIError>]) {
        guard let text else {
            return
        }

        if reasoningItem == nil {
            let item = ResponseItem.reasoning(id: "", summary: [], content: [], encryptedContent: nil)
            reasoningItem = item
            output.append(.success(.outputItemAdded(item)))
        }

        if case let .reasoning(id, summary, content, encryptedContent)? = reasoningItem {
            var updatedContent = content ?? []
            let contentIndex = Int64(updatedContent.count)
            updatedContent.append(.reasoningText(text: text))
            reasoningItem = .reasoning(
                id: id,
                summary: summary,
                content: updatedContent,
                encryptedContent: encryptedContent
            )
            output.append(.success(.reasoningContentDelta(delta: text, contentIndex: contentIndex)))
        }
    }

    private mutating func receiveToolCall(_ value: JSONValue) {
        guard case let .object(toolCall) = value else {
            return
        }

        var index = toolCall["index"]?.intValue
        var callIDForLookup: String?
        if let callID = toolCall["id"]?.stringValue {
            callIDForLookup = callID
            if let existing = toolCallIndexByID[callID] {
                index = existing
            }
        }

        if index == nil, callIDForLookup == nil {
            index = lastToolCallIndex
        }

        let resolvedIndex = index ?? nextAvailableToolCallIndex()
        var state = toolCalls[resolvedIndex] ?? ToolCallState()
        if toolCallOrderSeen.insert(resolvedIndex).inserted {
            toolCallOrder.append(resolvedIndex)
        }

        if let id = toolCall["id"]?.stringValue {
            if state.id == nil {
                state.id = id
            }
            if toolCallIndexByID[id] == nil {
                toolCallIndexByID[id] = resolvedIndex
            }
        }

        if case let .object(function)? = toolCall["function"] {
            if let name = function["name"]?.stringValue, !name.isEmpty, state.name == nil {
                state.name = name
            }
            if let arguments = function["arguments"]?.stringValue {
                state.arguments.append(arguments)
            }
        }

        toolCalls[resolvedIndex] = state
        lastToolCallIndex = resolvedIndex
    }

    private mutating func nextAvailableToolCallIndex() -> Int {
        while toolCalls[nextToolCallIndex] != nil {
            nextToolCallIndex += 1
        }
        defer { nextToolCallIndex += 1 }
        return nextToolCallIndex
    }

    private mutating func flushReasoning(to output: inout [Result<ResponseEvent, APIError>]) {
        guard let reasoning = reasoningItem else {
            return
        }
        reasoningItem = nil
        output.append(.success(.outputItemDone(reasoning)))
    }

    private mutating func flushAssistant(to output: inout [Result<ResponseEvent, APIError>]) {
        guard let assistant = assistantItem else {
            return
        }
        assistantItem = nil
        output.append(.success(.outputItemDone(assistant)))
    }

    private mutating func flushToolCalls(to output: inout [Result<ResponseEvent, APIError>]) {
        for index in toolCallOrder {
            guard let state = toolCalls.removeValue(forKey: index) else {
                continue
            }
            toolCallOrderSeen.remove(index)
            guard let name = state.name else {
                continue
            }

            output.append(.success(.outputItemDone(.functionCall(
                name: name,
                arguments: state.arguments,
                callID: state.id ?? "tool-call-\(index)"
            ))))
        }
        toolCallOrder.removeAll(keepingCapacity: true)
    }
}

private extension JSONValue {
    var objectValue: [String: JSONValue]? {
        guard case let .object(value) = self else {
            return nil
        }
        return value
    }

    var arrayValue: [JSONValue]? {
        guard case let .array(value) = self else {
            return nil
        }
        return value
    }

    var stringValue: String? {
        guard case let .string(value) = self else {
            return nil
        }
        return value
    }

    var intValue: Int? {
        switch self {
        case let .integer(value):
            return Int(value)
        case let .double(value):
            return value.isFinite ? Int(value) : nil
        default:
            return nil
        }
    }

    var chatReasoningText: String? {
        if let stringValue {
            return stringValue
        }
        guard let object = objectValue else {
            return nil
        }
        return object["text"]?.stringValue ?? object["content"]?.stringValue
    }
}
