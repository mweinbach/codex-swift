import Foundation

public protocol APITransport: Sendable {
    func execute(_ request: APIRequest) async -> Result<APIResponse, TransportError>
    func stream(_ request: APIRequest) async -> Result<APIStreamResponse, TransportError>
}

public typealias APIByteStream = AsyncStream<Result<Data, TransportError>>

public struct APIStreamResponse: Sendable, ResponseWithStatus {
    public let statusCode: Int
    public let headers: [String: String]
    public let sseText: String?
    public let byteStream: APIByteStream

    public init(statusCode: Int, headers: [String: String] = [:], sseText: String) {
        self.statusCode = statusCode
        self.headers = headers
        self.sseText = sseText
        self.byteStream = APIByteStream { continuation in
            continuation.yield(.success(Data(sseText.utf8)))
            continuation.finish()
        }
    }

    public init(statusCode: Int, headers: [String: String] = [:], byteStream: APIByteStream) {
        self.statusCode = statusCode
        self.headers = headers
        self.sseText = nil
        self.byteStream = byteStream
    }

    public func collectSSEText() async -> Result<String, TransportError> {
        var body = Data()
        for await chunk in byteStream {
            switch chunk {
            case let .success(data):
                body.append(data)
            case let .failure(error):
                return .failure(error)
            }
        }
        return .success(String(decoding: body, as: UTF8.self))
    }
}

extension APIStreamResponse: Equatable {
    public static func == (lhs: APIStreamResponse, rhs: APIStreamResponse) -> Bool {
        lhs.statusCode == rhs.statusCode
            && lhs.headers == rhs.headers
            && lhs.sseText == rhs.sseText
    }
}

public typealias ResponseEventResults = [Result<ResponseEvent, APIError>]

public struct StreamingAPIClient<Transport: APITransport, Auth: APIAuthProvider> {
    public let transport: Transport
    public let provider: APIProvider
    public let auth: Auth
    public var requestTelemetry: RequestTelemetry?

    public init(
        transport: Transport,
        provider: APIProvider,
        auth: Auth,
        requestTelemetry: RequestTelemetry? = nil
    ) {
        self.transport = transport
        self.provider = provider
        self.auth = auth
        self.requestTelemetry = requestTelemetry
    }

    public func withTelemetry(_ telemetry: RequestTelemetry?) -> StreamingAPIClient {
        var copy = self
        copy.requestTelemetry = telemetry
        return copy
    }

    public func stream(
        path: String,
        body: JSONValue,
        extraHeaders: [String: String] = [:],
        parse: (String) -> ResponseEventResults
    ) async -> Result<ResponseEventResults, APIError> {
        let result: Result<APIStreamResponse, TransportError> = await TransportRetry.runWithRequestTelemetry(
            policy: provider.retry.toPolicy(),
            telemetry: requestTelemetry,
            makeRequest: {
                makeStreamRequest(path: path, body: body, extraHeaders: extraHeaders)
            },
            send: { request in
                await transport.stream(request)
            }
        )

        switch result {
        case let .success(response):
            switch await response.collectSSEText() {
            case let .success(sseText):
                return .success(parse(sseText))
            case let .failure(error):
                return .failure(.transport(error))
            }
        case let .failure(error):
            return .failure(.transport(error))
        }
    }

    public func makeStreamRequest(
        path: String,
        body: JSONValue,
        extraHeaders: [String: String] = [:]
    ) -> APIRequest {
        var request = provider.buildRequest(method: .post, path: path).withJSON(body)
        for (name, value) in extraHeaders {
            request.headers[name] = value
        }
        request.headers["accept"] = "text/event-stream"
        return request.addingAuthHeaders(from: auth)
    }
}

public struct ModelsClient<Transport: APITransport, Auth: APIAuthProvider> {
    public let transport: Transport
    public let provider: APIProvider
    public let auth: Auth
    public var requestTelemetry: RequestTelemetry?

    public init(
        transport: Transport,
        provider: APIProvider,
        auth: Auth,
        requestTelemetry: RequestTelemetry? = nil
    ) {
        self.transport = transport
        self.provider = provider
        self.auth = auth
        self.requestTelemetry = requestTelemetry
    }

    public func withTelemetry(_ telemetry: RequestTelemetry?) -> ModelsClient {
        var copy = self
        copy.requestTelemetry = telemetry
        return copy
    }

    public func listModels(
        clientVersion: String,
        extraHeaders: [String: String] = [:]
    ) async -> Result<ModelsResponse, APIError> {
        let result: Result<APIResponse, TransportError> = await TransportRetry.runWithRequestTelemetry(
            policy: provider.retry.toPolicy(),
            telemetry: requestTelemetry,
            makeRequest: {
                ModelsAPI.request(
                    provider: provider,
                    clientVersion: clientVersion,
                    extraHeaders: extraHeaders
                )
                .addingAuthHeaders(from: auth)
            },
            send: { request in
                await transport.execute(request)
            }
        )

        switch result {
        case let .success(response):
            do {
                return .success(try ModelsAPI.decodeResponse(body: response.body, headers: response.headers))
            } catch {
                return .failure(.stream(String(describing: error)))
            }
        case let .failure(error):
            return .failure(.transport(error))
        }
    }
}

public struct CompactClient<Transport: APITransport, Auth: APIAuthProvider> {
    public let transport: Transport
    public let provider: APIProvider
    public let auth: Auth
    public var requestTelemetry: RequestTelemetry?

    public init(
        transport: Transport,
        provider: APIProvider,
        auth: Auth,
        requestTelemetry: RequestTelemetry? = nil
    ) {
        self.transport = transport
        self.provider = provider
        self.auth = auth
        self.requestTelemetry = requestTelemetry
    }

    public func withTelemetry(_ telemetry: RequestTelemetry?) -> CompactClient {
        var copy = self
        copy.requestTelemetry = telemetry
        return copy
    }

    public func compactInput(
        _ input: CompactionInput,
        extraHeaders: [String: String] = [:]
    ) async -> Result<[ResponseItem], APIError> {
        do {
            return await compact(body: try CompactAPI.body(for: input), extraHeaders: extraHeaders)
        } catch {
            return .failure(.stream(String(describing: error)))
        }
    }

    public func compact(
        body: JSONValue,
        extraHeaders: [String: String] = [:]
    ) async -> Result<[ResponseItem], APIError> {
        let path: String
        do {
            path = try CompactAPI.path(for: provider)
        } catch {
            return .failure(.stream(String(describing: error)))
        }

        let result: Result<APIResponse, TransportError> = await TransportRetry.runWithRequestTelemetry(
            policy: provider.retry.toPolicy(),
            telemetry: requestTelemetry,
            makeRequest: {
                var request = provider.buildRequest(method: .post, path: path).withJSON(body)
                for (name, value) in extraHeaders {
                    request.headers[name] = value
                }
                return request.addingAuthHeaders(from: auth)
            },
            send: { request in
                await transport.execute(request)
            }
        )

        switch result {
        case let .success(response):
            do {
                return .success(try JSONDecoder().decode(CompactHistoryResponse.self, from: response.body).output)
            } catch {
                return .failure(.stream(String(describing: error)))
            }
        case let .failure(error):
            return .failure(.transport(error))
        }
    }
}

public struct ResponsesOptions: Equatable, Sendable {
    public var reasoning: ResponsesAPIReasoning?
    public var include: [String]
    public var promptCacheKey: String?
    public var text: ResponsesAPITextControls?
    public var storeOverride: Bool?
    public var conversationID: String?
    public var sessionSource: SessionSource?
    public var extraHeaders: [String: String]

    public init(
        reasoning: ResponsesAPIReasoning? = nil,
        include: [String] = [],
        promptCacheKey: String? = nil,
        text: ResponsesAPITextControls? = nil,
        storeOverride: Bool? = nil,
        conversationID: String? = nil,
        sessionSource: SessionSource? = nil,
        extraHeaders: [String: String] = [:]
    ) {
        self.reasoning = reasoning
        self.include = include
        self.promptCacheKey = promptCacheKey
        self.text = text
        self.storeOverride = storeOverride
        self.conversationID = conversationID
        self.sessionSource = sessionSource
        self.extraHeaders = extraHeaders
    }
}

public struct ResponsesClient<Transport: APITransport, Auth: APIAuthProvider> {
    public let streaming: StreamingAPIClient<Transport, Auth>

    public init(transport: Transport, provider: APIProvider, auth: Auth) {
        self.streaming = StreamingAPIClient(transport: transport, provider: provider, auth: auth)
    }

    private init(streaming: StreamingAPIClient<Transport, Auth>) {
        self.streaming = streaming
    }

    public func withTelemetry(_ telemetry: RequestTelemetry?) -> ResponsesClient {
        ResponsesClient(streaming: streaming.withTelemetry(telemetry))
    }

    public func streamRequest(_ request: ResponsesRequest) async -> Result<ResponseEventResults, APIError> {
        await stream(body: request.body, extraHeaders: request.headers)
    }

    public func streamPrompt(
        model: String,
        instructions: String,
        prompt: Prompt,
        options: ResponsesOptions = ResponsesOptions()
    ) async -> Result<ResponseEventResults, APIError> {
        let tools: [JSONValue]
        do {
            tools = try Self.toolsJSONValues(ToolSpecFactory.createToolsJSONForResponsesAPI(prompt.tools))
        } catch {
            return .failure(.stream(String(describing: error)))
        }

        do {
            let request = try ResponsesRequestBuilder(model: model, instructions: instructions, input: prompt.input)
                .tools(tools)
                .parallelToolCalls(prompt.parallelToolCalls)
                .reasoning(options.reasoning)
                .include(options.include)
                .promptCacheKey(options.promptCacheKey)
                .text(options.text)
                .conversation(options.conversationID)
                .sessionSource(options.sessionSource)
                .storeOverride(options.storeOverride)
                .extraHeaders(options.extraHeaders)
                .build(provider: streaming.provider)
            return await streamRequest(request)
        } catch {
            return .failure(.stream(String(describing: error)))
        }
    }

    public func stream(
        body: JSONValue,
        extraHeaders: [String: String] = [:]
    ) async -> Result<ResponseEventResults, APIError> {
        await streaming.stream(
            path: Self.path(for: streaming.provider.wireAPI),
            body: body,
            extraHeaders: extraHeaders,
            parse: ResponsesSSEParser.collectEvents(fromSSEText:)
        )
    }

    public static func path(for wireAPI: WireAPI) -> String {
        switch wireAPI {
        case .responses,
             .compact:
            return "responses"
        case .chat:
            return "chat/completions"
        }
    }

    private static func toolsJSONValues(_ tools: [Any]) throws -> [JSONValue] {
        let data = try JSONSerialization.data(withJSONObject: tools)
        return try JSONDecoder().decode([JSONValue].self, from: data)
    }
}

public struct ChatClient<Transport: APITransport, Auth: APIAuthProvider> {
    public let streaming: StreamingAPIClient<Transport, Auth>

    public init(transport: Transport, provider: APIProvider, auth: Auth) {
        self.streaming = StreamingAPIClient(transport: transport, provider: provider, auth: auth)
    }

    private init(streaming: StreamingAPIClient<Transport, Auth>) {
        self.streaming = streaming
    }

    public func withTelemetry(_ telemetry: RequestTelemetry?) -> ChatClient {
        ChatClient(streaming: streaming.withTelemetry(telemetry))
    }

    public func streamRequest(_ request: ChatRequest) async -> Result<ResponseEventResults, APIError> {
        await stream(body: request.body, extraHeaders: request.headers)
    }

    public func streamPrompt(
        model: String,
        instructions: String,
        prompt: Prompt,
        conversationID: String? = nil,
        sessionSource: SessionSource? = nil
    ) async -> Result<ResponseEventResults, APIError> {
        let tools: [JSONValue]
        do {
            tools = try Self.toolsJSONValues(ToolSpecFactory.createToolsJSONForChatCompletionsAPI(prompt.tools))
        } catch {
            return .failure(.stream(String(describing: error)))
        }

        let request = ChatRequestBuilder(
            model: model,
            instructions: instructions,
            input: prompt.input,
            tools: tools
        )
        .conversationID(conversationID)
        .sessionSource(sessionSource)
        .build(provider: streaming.provider)

        return await streamRequest(request)
    }

    public func stream(
        body: JSONValue,
        extraHeaders: [String: String] = [:]
    ) async -> Result<ResponseEventResults, APIError> {
        await streaming.stream(
            path: Self.path(for: streaming.provider.wireAPI),
            body: body,
            extraHeaders: extraHeaders,
            parse: ChatSSEParser.collectEvents(fromSSEText:)
        )
    }

    public static func path(for wireAPI: WireAPI) -> String {
        switch wireAPI {
        case .chat:
            return "chat/completions"
        case .responses,
             .compact:
            return "responses"
        }
    }

    private static func toolsJSONValues(_ tools: [Any]) throws -> [JSONValue] {
        let data = try JSONSerialization.data(withJSONObject: tools)
        return try JSONDecoder().decode([JSONValue].self, from: data)
    }
}
