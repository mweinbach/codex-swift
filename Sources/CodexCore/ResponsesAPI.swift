import Foundation

public struct ResponsesAPIReasoning: Equatable, Codable, Sendable {
    public var effort: ReasoningEffort?
    public var summary: ReasoningSummary?

    public init(effort: ReasoningEffort? = nil, summary: ReasoningSummary? = nil) {
        self.effort = effort
        self.summary = summary
    }
}

public enum ResponsesAPITextFormatType: String, Codable, Sendable {
    case jsonSchema = "json_schema"
}

public struct ResponsesAPITextFormat: Equatable, Codable, Sendable {
    public var type: ResponsesAPITextFormatType
    public var strict: Bool
    public var schema: JSONValue
    public var name: String

    public init(
        type: ResponsesAPITextFormatType = .jsonSchema,
        strict: Bool,
        schema: JSONValue,
        name: String
    ) {
        self.type = type
        self.strict = strict
        self.schema = schema
        self.name = name
    }
}

public enum OpenAIVerbosity: String, Codable, Sendable {
    case low
    case medium
    case high

    public init(_ verbosity: Verbosity) {
        switch verbosity {
        case .low:
            self = .low
        case .medium:
            self = .medium
        case .high:
            self = .high
        }
    }
}

public struct ResponsesAPITextControls: Equatable, Codable, Sendable {
    public var verbosity: OpenAIVerbosity?
    public var format: ResponsesAPITextFormat?

    public init(
        verbosity: OpenAIVerbosity? = nil,
        format: ResponsesAPITextFormat? = nil
    ) {
        self.verbosity = verbosity
        self.format = format
    }

    /// Port of codex-api create_text_param_for_request.
    public static func createForRequest(
        verbosity: Verbosity?,
        outputSchema: JSONValue?
    ) -> ResponsesAPITextControls? {
        if verbosity == nil, outputSchema == nil {
            return nil
        }

        return ResponsesAPITextControls(
            verbosity: verbosity.map(OpenAIVerbosity.init),
            format: outputSchema.map {
                ResponsesAPITextFormat(
                    strict: true,
                    schema: $0,
                    name: "codex_output_schema"
                )
            }
        )
    }
}

public struct ResponsesAPIRequest: Equatable, Codable, Sendable {
    public var model: String
    public var instructions: String
    public var input: [ResponseItem]
    public var tools: [JSONValue]
    public var toolChoice: String
    public var parallelToolCalls: Bool
    public var reasoning: ResponsesAPIReasoning?
    public var store: Bool
    public var stream: Bool
    public var include: [String]
    public var promptCacheKey: String?
    public var text: ResponsesAPITextControls?

    private enum CodingKeys: String, CodingKey {
        case model
        case instructions
        case input
        case tools
        case toolChoice = "tool_choice"
        case parallelToolCalls = "parallel_tool_calls"
        case reasoning
        case store
        case stream
        case include
        case promptCacheKey = "prompt_cache_key"
        case text
    }

    public init(
        model: String,
        instructions: String,
        input: [ResponseItem],
        tools: [JSONValue] = [],
        toolChoice: String = "auto",
        parallelToolCalls: Bool = false,
        reasoning: ResponsesAPIReasoning? = nil,
        store: Bool,
        stream: Bool = true,
        include: [String] = [],
        promptCacheKey: String? = nil,
        text: ResponsesAPITextControls? = nil
    ) {
        self.model = model
        self.instructions = instructions
        self.input = input
        self.tools = tools
        self.toolChoice = toolChoice
        self.parallelToolCalls = parallelToolCalls
        self.reasoning = reasoning
        self.store = store
        self.stream = stream
        self.include = include
        self.promptCacheKey = promptCacheKey
        self.text = text
    }
}

public struct ResponsesRequest: Equatable, Sendable {
    public var body: JSONValue
    public var headers: [String: String]

    public init(body: JSONValue, headers: [String: String] = [:]) {
        self.body = body
        self.headers = headers
    }
}

public enum ResponsesRequestBuildError: Error, Equatable, CustomStringConvertible, Sendable {
    case encodingFailed(String)

    public var description: String {
        switch self {
        case let .encodingFailed(message):
            return "failed to encode responses request: \(message)"
        }
    }
}

public struct ResponsesRequestBuilder: Equatable, Sendable {
    public var model: String
    public var instructions: String
    public var input: [ResponseItem]
    public var tools: [JSONValue]
    public var parallelToolCalls: Bool
    public var reasoning: ResponsesAPIReasoning?
    public var include: [String]
    public var promptCacheKey: String?
    public var text: ResponsesAPITextControls?
    public var conversationID: String?
    public var sessionSource: SessionSource?
    public var storeOverride: Bool?
    public var extraHeaders: [String: String]

    public init(model: String, instructions: String, input: [ResponseItem]) {
        self.model = model
        self.instructions = instructions
        self.input = input
        self.tools = []
        self.parallelToolCalls = false
        self.reasoning = nil
        self.include = []
        self.promptCacheKey = nil
        self.text = nil
        self.conversationID = nil
        self.sessionSource = nil
        self.storeOverride = nil
        self.extraHeaders = [:]
    }

    public func tools(_ tools: [JSONValue]) -> ResponsesRequestBuilder {
        var copy = self
        copy.tools = tools
        return copy
    }

    public func parallelToolCalls(_ enabled: Bool) -> ResponsesRequestBuilder {
        var copy = self
        copy.parallelToolCalls = enabled
        return copy
    }

    public func reasoning(_ reasoning: ResponsesAPIReasoning?) -> ResponsesRequestBuilder {
        var copy = self
        copy.reasoning = reasoning
        return copy
    }

    public func include(_ include: [String]) -> ResponsesRequestBuilder {
        var copy = self
        copy.include = include
        return copy
    }

    public func promptCacheKey(_ key: String?) -> ResponsesRequestBuilder {
        var copy = self
        copy.promptCacheKey = key
        return copy
    }

    public func text(_ text: ResponsesAPITextControls?) -> ResponsesRequestBuilder {
        var copy = self
        copy.text = text
        return copy
    }

    public func conversation(_ conversationID: String?) -> ResponsesRequestBuilder {
        var copy = self
        copy.conversationID = conversationID
        return copy
    }

    public func sessionSource(_ source: SessionSource?) -> ResponsesRequestBuilder {
        var copy = self
        copy.sessionSource = source
        return copy
    }

    public func storeOverride(_ store: Bool?) -> ResponsesRequestBuilder {
        var copy = self
        copy.storeOverride = store
        return copy
    }

    public func extraHeaders(_ headers: [String: String]) -> ResponsesRequestBuilder {
        var copy = self
        copy.extraHeaders = headers
        return copy
    }

    public func build(provider: APIProvider) throws -> ResponsesRequest {
        let store = storeOverride ?? provider.isAzureResponsesEndpoint()
        let request = ResponsesAPIRequest(
            model: model,
            instructions: instructions,
            input: input,
            tools: tools,
            parallelToolCalls: parallelToolCalls,
            reasoning: reasoning,
            store: store,
            include: include,
            promptCacheKey: promptCacheKey,
            text: text
        )

        var body = try Self.jsonValue(request)
        if store, provider.isAzureResponsesEndpoint() {
            Self.attachItemIDs(to: &body, originalItems: input)
        }

        var headers = extraHeaders
        for (name, value) in CodexRequestHeaders.conversationHeaders(conversationID: conversationID) {
            headers[name] = value
        }
        if let subagent = CodexRequestHeaders.subagentHeader(for: sessionSource) {
            headers["x-openai-subagent"] = subagent
        }

        return ResponsesRequest(body: body, headers: headers)
    }

    private static func jsonValue<T: Encodable>(_ value: T) throws -> JSONValue {
        do {
            let data = try JSONEncoder().encode(value)
            return try JSONDecoder().decode(JSONValue.self, from: data)
        } catch {
            throw ResponsesRequestBuildError.encodingFailed(String(describing: error))
        }
    }

    private static func attachItemIDs(to payload: inout JSONValue, originalItems: [ResponseItem]) {
        guard case var .object(root) = payload,
              case var .array(items) = root["input"]
        else {
            return
        }

        for index in items.indices {
            guard index < originalItems.count,
                  let id = originalItems[index].responsesRequestID,
                  !id.isEmpty,
                  case var .object(item) = items[index]
            else {
                continue
            }

            item["id"] = .string(id)
            items[index] = .object(item)
        }

        root["input"] = .array(items)
        payload = .object(root)
    }
}

private extension ResponseItem {
    var responsesRequestID: String? {
        switch self {
        case let .message(id, _, _, _):
            return id
        case let .reasoning(id, _, _, _):
            return id
        case let .localShellCall(id, _, _, _):
            return id
        case let .functionCall(id, _, _, _):
            return id
        case let .customToolCall(id, _, _, _, _):
            return id
        case let .toolSearchCall(id, _, _, _, _):
            return id
        case let .webSearchCall(id, _, _):
            return id
        case let .imageGenerationCall(id, _, _, _):
            return id
        case .functionCallOutput,
             .customToolCallOutput,
             .toolSearchOutput,
             .ghostSnapshot,
             .compaction,
             .knownPersisted,
             .other:
            return nil
        }
    }
}
