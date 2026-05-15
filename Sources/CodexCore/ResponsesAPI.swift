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
        outputSchema: JSONValue?,
        outputSchemaStrict: Bool = true
    ) -> ResponsesAPITextControls? {
        if verbosity == nil, outputSchema == nil {
            return nil
        }

        return ResponsesAPITextControls(
            verbosity: verbosity.map(OpenAIVerbosity.init),
            format: outputSchema.map {
                ResponsesAPITextFormat(
                    strict: outputSchemaStrict,
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
    public var serviceTier: String?
    public var promptCacheKey: String?
    public var text: ResponsesAPITextControls?
    public var clientMetadata: [String: String]?

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
        case serviceTier = "service_tier"
        case promptCacheKey = "prompt_cache_key"
        case text
        case clientMetadata = "client_metadata"
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
        serviceTier: String? = nil,
        promptCacheKey: String? = nil,
        text: ResponsesAPITextControls? = nil,
        clientMetadata: [String: String]? = nil
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
        self.serviceTier = serviceTier
        self.promptCacheKey = promptCacheKey
        self.text = text
        self.clientMetadata = clientMetadata
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(model, forKey: .model)
        if !instructions.isEmpty {
            try container.encode(instructions, forKey: .instructions)
        }
        try container.encode(input, forKey: .input)
        try container.encode(tools, forKey: .tools)
        try container.encode(toolChoice, forKey: .toolChoice)
        try container.encode(parallelToolCalls, forKey: .parallelToolCalls)
        try container.encodeIfPresent(reasoning, forKey: .reasoning)
        try container.encode(store, forKey: .store)
        try container.encode(stream, forKey: .stream)
        try container.encode(include, forKey: .include)
        try container.encodeIfPresent(serviceTier, forKey: .serviceTier)
        try container.encodeIfPresent(promptCacheKey, forKey: .promptCacheKey)
        try container.encodeIfPresent(text, forKey: .text)
        try container.encodeIfPresent(clientMetadata, forKey: .clientMetadata)
    }
}

public struct ResponseProcessedWebSocketRequest: Equatable, Codable, Sendable {
    public var responseID: String

    private enum CodingKeys: String, CodingKey {
        case responseID = "response_id"
    }

    public init(responseID: String) {
        self.responseID = responseID
    }
}

public struct ResponseCreateWebSocketRequest: Equatable, Encodable, Sendable {
    public var model: String
    public var instructions: String
    public var previousResponseID: String?
    public var input: [ResponseItem]
    public var tools: [JSONValue]
    public var toolChoice: String
    public var parallelToolCalls: Bool
    public var reasoning: ResponsesAPIReasoning?
    public var store: Bool
    public var stream: Bool
    public var include: [String]
    public var serviceTier: String?
    public var promptCacheKey: String?
    public var text: ResponsesAPITextControls?
    public var generate: Bool?
    public var clientMetadata: [String: String]?

    private enum CodingKeys: String, CodingKey {
        case model
        case instructions
        case previousResponseID = "previous_response_id"
        case input
        case tools
        case toolChoice = "tool_choice"
        case parallelToolCalls = "parallel_tool_calls"
        case reasoning
        case store
        case stream
        case include
        case serviceTier = "service_tier"
        case promptCacheKey = "prompt_cache_key"
        case text
        case generate
        case clientMetadata = "client_metadata"
    }

    public init(
        model: String,
        instructions: String,
        previousResponseID: String? = nil,
        input: [ResponseItem],
        tools: [JSONValue] = [],
        toolChoice: String = "auto",
        parallelToolCalls: Bool = false,
        reasoning: ResponsesAPIReasoning? = nil,
        store: Bool,
        stream: Bool = true,
        include: [String] = [],
        serviceTier: String? = nil,
        promptCacheKey: String? = nil,
        text: ResponsesAPITextControls? = nil,
        generate: Bool? = nil,
        clientMetadata: [String: String]? = nil
    ) {
        self.model = model
        self.instructions = instructions
        self.previousResponseID = previousResponseID
        self.input = input
        self.tools = tools
        self.toolChoice = toolChoice
        self.parallelToolCalls = parallelToolCalls
        self.reasoning = reasoning
        self.store = store
        self.stream = stream
        self.include = include
        self.serviceTier = serviceTier
        self.promptCacheKey = promptCacheKey
        self.text = text
        self.generate = generate
        self.clientMetadata = clientMetadata
    }

    public init(_ request: ResponsesAPIRequest, previousResponseID: String? = nil, generate: Bool? = nil) {
        self.init(
            model: request.model,
            instructions: request.instructions,
            previousResponseID: previousResponseID,
            input: request.input,
            tools: request.tools,
            toolChoice: request.toolChoice,
            parallelToolCalls: request.parallelToolCalls,
            reasoning: request.reasoning,
            store: request.store,
            stream: request.stream,
            include: request.include,
            serviceTier: request.serviceTier,
            promptCacheKey: request.promptCacheKey,
            text: request.text,
            generate: generate,
            clientMetadata: request.clientMetadata
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(model, forKey: .model)
        if !instructions.isEmpty {
            try container.encode(instructions, forKey: .instructions)
        }
        try container.encodeIfPresent(previousResponseID, forKey: .previousResponseID)
        try container.encode(input, forKey: .input)
        try container.encode(tools, forKey: .tools)
        try container.encode(toolChoice, forKey: .toolChoice)
        try container.encode(parallelToolCalls, forKey: .parallelToolCalls)
        try container.encodeIfPresent(reasoning, forKey: .reasoning)
        try container.encode(store, forKey: .store)
        try container.encode(stream, forKey: .stream)
        try container.encode(include, forKey: .include)
        try container.encodeIfPresent(serviceTier, forKey: .serviceTier)
        try container.encodeIfPresent(promptCacheKey, forKey: .promptCacheKey)
        try container.encodeIfPresent(text, forKey: .text)
        try container.encodeIfPresent(generate, forKey: .generate)
        try container.encodeIfPresent(clientMetadata, forKey: .clientMetadata)
    }
}

public struct ResponsesWebSocketLastResponse: Equatable, Sendable {
    public var responseID: String
    public var itemsAdded: [ResponseItem]

    public init(responseID: String, itemsAdded: [ResponseItem]) {
        self.responseID = responseID
        self.itemsAdded = itemsAdded
    }
}

public enum ResponsesWebSocketContinuation {
    public static func incrementalInput(
        previousRequest: ResponsesAPIRequest?,
        currentRequest: ResponsesAPIRequest,
        lastResponse: ResponsesWebSocketLastResponse?,
        allowEmptyDelta: Bool = true
    ) -> [ResponseItem]? {
        guard let previousRequest else {
            return nil
        }

        var previousWithoutInput = previousRequest
        previousWithoutInput.input.removeAll()
        var currentWithoutInput = currentRequest
        currentWithoutInput.input.removeAll()
        guard previousWithoutInput == currentWithoutInput else {
            return nil
        }

        var baseline = previousRequest.input
        if let lastResponse {
            baseline.append(contentsOf: lastResponse.itemsAdded)
        }

        guard currentRequest.input.starts(with: baseline),
              allowEmptyDelta || baseline.count < currentRequest.input.count
        else {
            return nil
        }

        return Array(currentRequest.input.dropFirst(baseline.count))
    }

    public static func prepareResponseCreateRequest(
        payload: ResponseCreateWebSocketRequest,
        currentRequest: ResponsesAPIRequest,
        previousRequest: ResponsesAPIRequest?,
        lastResponse: ResponsesWebSocketLastResponse?
    ) -> ResponseCreateWebSocketRequest {
        guard let lastResponse,
              !lastResponse.responseID.isEmpty,
              let incrementalItems = incrementalInput(
                previousRequest: previousRequest,
                currentRequest: currentRequest,
                lastResponse: lastResponse,
                allowEmptyDelta: true
              )
        else {
            return payload
        }

        var copy = payload
        copy.previousResponseID = lastResponse.responseID
        copy.input = incrementalItems
        return copy
    }
}

public enum ResponsesWebSocketRequest: Equatable, Encodable, Sendable {
    case responseCreate(ResponseCreateWebSocketRequest)
    case responseProcessed(ResponseProcessedWebSocketRequest)

    private enum CodingKeys: String, CodingKey {
        case type
        case model
        case instructions
        case previousResponseID = "previous_response_id"
        case input
        case tools
        case toolChoice = "tool_choice"
        case parallelToolCalls = "parallel_tool_calls"
        case reasoning
        case store
        case stream
        case include
        case serviceTier = "service_tier"
        case promptCacheKey = "prompt_cache_key"
        case text
        case generate
        case clientMetadata = "client_metadata"
        case responseID = "response_id"
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .responseCreate(request):
            try container.encode("response.create", forKey: .type)
            try container.encode(request.model, forKey: .model)
            if !request.instructions.isEmpty {
                try container.encode(request.instructions, forKey: .instructions)
            }
            try container.encodeIfPresent(request.previousResponseID, forKey: .previousResponseID)
            try container.encode(request.input, forKey: .input)
            try container.encode(request.tools, forKey: .tools)
            try container.encode(request.toolChoice, forKey: .toolChoice)
            try container.encode(request.parallelToolCalls, forKey: .parallelToolCalls)
            try container.encodeIfPresent(request.reasoning, forKey: .reasoning)
            try container.encode(request.store, forKey: .store)
            try container.encode(request.stream, forKey: .stream)
            try container.encode(request.include, forKey: .include)
            try container.encodeIfPresent(request.serviceTier, forKey: .serviceTier)
            try container.encodeIfPresent(request.promptCacheKey, forKey: .promptCacheKey)
            try container.encodeIfPresent(request.text, forKey: .text)
            try container.encodeIfPresent(request.generate, forKey: .generate)
            try container.encodeIfPresent(request.clientMetadata, forKey: .clientMetadata)
        case let .responseProcessed(request):
            try container.encode("response.processed", forKey: .type)
            try container.encode(request.responseID, forKey: .responseID)
        }
    }
}

public enum ResponsesWebSocketErrorMapper {
    public static let connectionLimitReachedCode = "websocket_connection_limit_reached"
    public static let connectionLimitReachedMessage =
        "Responses websocket connection limit reached (60 minutes). Create a new websocket connection to continue."

    public static func mapErrorEvent(payload: String) -> APIError? {
        guard let data = payload.data(using: .utf8),
              let event = try? JSONDecoder().decode(WrappedResponsesWebSocketErrorEvent.self, from: data),
              event.kind == "error"
        else {
            return nil
        }

        if event.error?.code == connectionLimitReachedCode {
            return .retryable(
                message: event.error?.message ?? connectionLimitReachedMessage,
                delay: nil
            )
        }

        guard let status = event.status,
              (100..<1000).contains(status),
              !(200..<300).contains(status)
        else {
            return nil
        }

        return .transport(.http(
            statusCode: status,
            headers: event.headers.flatMap(headersFromJSON),
            body: payload
        ))
    }

    private static func headersFromJSON(_ headers: [String: JSONValue]) -> [String: String]? {
        var mapped: [String: String] = [:]
        for (name, value) in headers {
            guard isValidHeaderName(name),
                  let headerValue = headerValue(value),
                  isValidHeaderValue(headerValue)
            else {
                continue
            }
            mapped[name] = headerValue
        }
        return mapped.isEmpty ? nil : mapped
    }

    private static func headerValue(_ value: JSONValue) -> String? {
        switch value {
        case let .string(value):
            return value
        case let .integer(value):
            return String(value)
        case let .double(value):
            return String(value)
        case let .bool(value):
            return String(value)
        case .null, .array, .object:
            return nil
        }
    }

    private static func isValidHeaderName(_ name: String) -> Bool {
        guard !name.isEmpty else {
            return false
        }
        return name.utf8.allSatisfy { byte in
            byte == 33
                || (35...39).contains(byte)
                || byte == 42
                || byte == 43
                || byte == 45
                || byte == 46
                || (48...57).contains(byte)
                || (65...90).contains(byte)
                || (94...122).contains(byte)
                || byte == 124
                || byte == 126
        }
    }

    private static func isValidHeaderValue(_ value: String) -> Bool {
        value.utf8.allSatisfy { byte in
            byte == 9 || (32...126).contains(byte) || byte >= 128
        }
    }
}

private struct WrappedResponsesWebSocketErrorEvent: Decodable {
    let kind: String
    let status: Int?
    let error: WrappedResponsesWebSocketError?
    let headers: [String: JSONValue]?

    private enum CodingKeys: String, CodingKey {
        case kind = "type"
        case status
        case statusCode = "status_code"
        case error
        case headers
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(String.self, forKey: .kind)
        status = try container.decodeIfPresent(Int.self, forKey: .status)
            ?? container.decodeIfPresent(Int.self, forKey: .statusCode)
        error = try container.decodeIfPresent(WrappedResponsesWebSocketError.self, forKey: .error)
        headers = try container.decodeIfPresent([String: JSONValue].self, forKey: .headers)
    }
}

private struct WrappedResponsesWebSocketError: Decodable {
    let code: String?
    let message: String?
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
    public var serviceTier: String?
    public var promptCacheKey: String?
    public var text: ResponsesAPITextControls?
    public var conversationID: String?
    public var sessionSource: SessionSource?
    public var storeOverride: Bool?
    public var clientMetadata: [String: String]
    public var turnMetadataHeader: String?
    public var extraHeaders: [String: String]

    public init(model: String, instructions: String, input: [ResponseItem]) {
        self.model = model
        self.instructions = instructions
        self.input = input
        self.tools = []
        self.parallelToolCalls = false
        self.reasoning = nil
        self.include = []
        self.serviceTier = nil
        self.promptCacheKey = nil
        self.text = nil
        self.conversationID = nil
        self.sessionSource = nil
        self.storeOverride = nil
        self.clientMetadata = [:]
        self.turnMetadataHeader = nil
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

    public func serviceTier(_ serviceTier: String?) -> ResponsesRequestBuilder {
        var copy = self
        copy.serviceTier = serviceTier
        return copy
    }

    public func serviceTier(_ serviceTier: String?, modelInfo: ModelInfo) -> ResponsesRequestBuilder {
        self.serviceTier(serviceTier.flatMap { modelInfo.supportsServiceTier($0) ? $0 : nil })
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

    public func clientMetadata(_ metadata: [String: String]) -> ResponsesRequestBuilder {
        var copy = self
        copy.clientMetadata = metadata
        return copy
    }

    public func turnMetadataHeader(_ header: String?) -> ResponsesRequestBuilder {
        var copy = self
        copy.turnMetadataHeader = header
        return copy
    }

    public func extraHeaders(_ headers: [String: String]) -> ResponsesRequestBuilder {
        var copy = self
        copy.extraHeaders = headers
        return copy
    }

    public func build(provider: APIProvider) throws -> ResponsesRequest {
        let store = storeOverride ?? provider.isAzureResponsesEndpoint()
        let sanitizedTurnMetadataHeader = Self.validHeaderValue(turnMetadataHeader)
        var requestClientMetadata = clientMetadata
        if let sanitizedTurnMetadataHeader {
            requestClientMetadata[CodexRequestHeaders.turnMetadataHeaderName] = sanitizedTurnMetadataHeader
        }
        let request = ResponsesAPIRequest(
            model: model,
            instructions: instructions,
            input: input,
            tools: tools,
            parallelToolCalls: parallelToolCalls,
            reasoning: reasoning,
            store: store,
            include: include,
            serviceTier: serviceTier,
            promptCacheKey: promptCacheKey,
            text: text,
            clientMetadata: requestClientMetadata.isEmpty ? nil : requestClientMetadata
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
        if let sanitizedTurnMetadataHeader {
            headers[CodexRequestHeaders.turnMetadataHeaderName] = sanitizedTurnMetadataHeader
        }
        if provider.name == ModelProviderInfo.amazonBedrockProviderName {
            headers = headers.filter { name, _ in !name.contains("_") }
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

    private static func validHeaderValue(_ value: String?) -> String? {
        guard let value,
              value.unicodeScalars.allSatisfy({ scalar in
                scalar.value == 0x09 || (0x20...0x7E).contains(scalar.value)
              })
        else {
            return nil
        }
        return value
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
        case let .functionCall(id, _, _, _, _):
            return id
        case let .customToolCall(id, _, _, _, _):
            return id
        case let .toolSearchCall(id, _, _, _, _):
            return id
        case let .webSearchCall(id, _, _):
            return id
        case .functionCallOutput,
             .imageGenerationCall,
             .customToolCallOutput,
             .toolSearchOutput,
             .ghostSnapshot,
             .compaction,
             .contextCompaction,
             .knownPersisted,
             .other:
            return nil
        }
    }
}
