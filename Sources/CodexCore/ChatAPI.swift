import Foundation

public struct ChatRequest: Equatable, Sendable {
    public var body: JSONValue
    public var headers: [String: String]

    public init(body: JSONValue, headers: [String: String] = [:]) {
        self.body = body
        self.headers = headers
    }
}

public struct ChatRequestBuilder: Equatable, Sendable {
    public var model: String
    public var instructions: String
    public var input: [ResponseItem]
    public var tools: [JSONValue]
    public var conversationID: String?
    public var sessionSource: SessionSource?

    public init(
        model: String,
        instructions: String,
        input: [ResponseItem],
        tools: [JSONValue] = []
    ) {
        self.model = model
        self.instructions = instructions
        self.input = input
        self.tools = tools
        self.conversationID = nil
        self.sessionSource = nil
    }

    public func conversationID(_ id: String?) -> ChatRequestBuilder {
        var copy = self
        copy.conversationID = id
        return copy
    }

    public func sessionSource(_ source: SessionSource?) -> ChatRequestBuilder {
        var copy = self
        copy.sessionSource = source
        return copy
    }

    public func build(provider _: APIProvider) -> ChatRequest {
        var messages: [JSONValue] = [
            .object([
                "role": .string("system"),
                "content": .string(instructions)
            ])
        ]

        let reasoningByAnchorIndex = buildReasoningAnchors()
        var lastAssistantText: String?

        for (index, item) in input.enumerated() {
            switch item {
            case let .message(_, role, content):
                let mapped = Self.chatContent(from: content, role: role)
                if role == "assistant" {
                    if lastAssistantText == mapped.text {
                        continue
                    }
                    lastAssistantText = mapped.text
                }

                var message: [String: JSONValue] = [
                    "role": .string(role),
                    "content": mapped.value
                ]
                if role == "assistant",
                   let reasoning = reasoningByAnchorIndex[index]
                {
                    message["reasoning"] = .string(reasoning)
                }
                messages.append(.object(message))

            case let .functionCall(_, name, arguments, callID):
                var message: [String: JSONValue] = [
                    "role": .string("assistant"),
                    "content": .null,
                    "tool_calls": .array([
                        .object([
                            "id": .string(callID),
                            "type": .string("function"),
                            "function": .object([
                                "name": .string(name),
                                "arguments": .string(arguments)
                            ])
                        ])
                    ])
                ]
                if let reasoning = reasoningByAnchorIndex[index] {
                    message["reasoning"] = .string(reasoning)
                }
                messages.append(.object(message))

            case let .localShellCall(id, _, status, action):
                var message: [String: JSONValue] = [
                    "role": .string("assistant"),
                    "content": .null,
                    "tool_calls": .array([
                        .object([
                            "id": .string(id ?? ""),
                            "type": .string("local_shell_call"),
                            "status": .string(status.rawValue),
                            "action": Self.codableJSONValue(action)
                        ])
                    ])
                ]
                if let reasoning = reasoningByAnchorIndex[index] {
                    message["reasoning"] = .string(reasoning)
                }
                messages.append(.object(message))

            case let .functionCallOutput(callID, output):
                messages.append(.object([
                    "role": .string("tool"),
                    "tool_call_id": .string(callID),
                    "content": functionOutputContent(output)
                ]))

            case let .customToolCall(id, _, _, name, input):
                messages.append(.object([
                    "role": .string("assistant"),
                    "content": .null,
                    "tool_calls": .array([
                        .object([
                            "id": id.map(JSONValue.string) ?? .null,
                            "type": .string("custom"),
                            "custom": .object([
                                "name": .string(name),
                                "input": .string(input)
                            ])
                        ])
                    ])
                ]))

            case let .customToolCallOutput(callID, output):
                messages.append(.object([
                    "role": .string("tool"),
                    "tool_call_id": .string(callID),
                    "content": .string(output)
                ]))

            case .reasoning,
                 .toolSearchCall,
                 .toolSearchOutput,
                 .webSearchCall,
                 .imageGenerationCall,
                 .ghostSnapshot,
                 .compaction,
                 .knownPersisted,
                 .other:
                continue
            }
        }

        var headers = CodexRequestHeaders.conversationHeaders(conversationID: conversationID)
        if let subagent = CodexRequestHeaders.subagentHeader(for: sessionSource) {
            headers["x-openai-subagent"] = subagent
        }

        return ChatRequest(
            body: .object([
                "model": .string(model),
                "messages": .array(messages),
                "stream": .bool(true),
                "tools": .array(tools)
            ]),
            headers: headers
        )
    }

    private func buildReasoningAnchors() -> [Int: String] {
        guard lastEmittedRole() != "user" else {
            return [:]
        }

        let lastUserIndex = input.lastIndex { item in
            if case let .message(_, role, _) = item {
                return role == "user"
            }
            return false
        }

        var reasoningByAnchorIndex: [Int: String] = [:]
        for (index, item) in input.enumerated() {
            if let lastUserIndex, index <= lastUserIndex {
                continue
            }
            guard case let .reasoning(_, _, content?, _) = item else {
                continue
            }

            let text = content.map(\.chatReasoningText).joined()
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                continue
            }

            var attached = false
            if index > 0,
               case let .message(_, role, _) = input[index - 1],
               role == "assistant"
            {
                reasoningByAnchorIndex[index - 1, default: ""].append(text)
                attached = true
            }

            if !attached, index + 1 < input.count {
                switch input[index + 1] {
                case .functionCall,
                     .localShellCall:
                    reasoningByAnchorIndex[index + 1, default: ""].append(text)
                case let .message(_, role, _) where role == "assistant":
                    reasoningByAnchorIndex[index + 1, default: ""].append(text)
                default:
                    break
                }
            }
        }

        return reasoningByAnchorIndex
    }

    private func lastEmittedRole() -> String? {
        var role: String?
        for item in input {
            switch item {
            case let .message(_, itemRole, _):
                role = itemRole
            case .functionCall,
                 .localShellCall:
                role = "assistant"
            case .functionCallOutput:
                role = "tool"
            case .reasoning,
                 .customToolCall,
                 .customToolCallOutput,
                 .toolSearchCall,
                 .toolSearchOutput,
                 .webSearchCall,
                 .imageGenerationCall,
                 .ghostSnapshot,
                 .compaction,
                 .knownPersisted,
                 .other:
                continue
            }
        }
        return role
    }

    private static func chatContent(
        from content: [ContentItem],
        role: String
    ) -> (text: String, value: JSONValue) {
        var text = ""
        var items: [JSONValue] = []
        var sawImage = false

        for item in content {
            switch item {
            case let .inputText(segment),
                 let .outputText(segment):
                text.append(segment)
                items.append(.object([
                    "type": .string("text"),
                    "text": .string(segment)
                ]))
            case let .inputImage(imageURL):
                sawImage = true
                items.append(.object([
                    "type": .string("image_url"),
                    "image_url": .object(["url": .string(imageURL)])
                ]))
            }
        }

        if role == "assistant" || !sawImage {
            return (text, .string(text))
        }
        return (text, .array(items))
    }

    private func functionOutputContent(_ output: FunctionCallOutputPayload) -> JSONValue {
        guard let contentItems = output.contentItems else {
            return .string(output.content)
        }

        return .array(contentItems.map { item in
            switch item {
            case let .inputText(text):
                return .object([
                    "type": .string("text"),
                    "text": .string(text)
                ])
            case let .inputImage(imageURL):
                return .object([
                    "type": .string("image_url"),
                    "image_url": .object(["url": .string(imageURL)])
                ])
            }
        })
    }

    private static func codableJSONValue<T: Encodable>(_ value: T) -> JSONValue {
        guard let data = try? JSONEncoder().encode(value),
              let json = try? JSONDecoder().decode(JSONValue.self, from: data)
        else {
            return .null
        }
        return json
    }
}

private extension ReasoningItemContent {
    var chatReasoningText: String {
        switch self {
        case let .reasoningText(text):
            return text
        case let .text(text):
            return text
        }
    }
}
