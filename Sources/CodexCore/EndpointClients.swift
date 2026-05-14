import Foundation

public protocol APITransport: Sendable {
    func execute(_ request: APIRequest) async -> Result<APIResponse, TransportError>
    func stream(_ request: APIRequest) async -> Result<APIStreamResponse, TransportError>
}

public typealias APIByteStream = AsyncStream<Result<Data, TransportError>>
public typealias ResponseEventStream = AsyncStream<Result<ResponseEvent, APIError>>

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

fileprivate func collectResponseEvents(_ stream: ResponseEventStream) async -> ResponseEventResults {
    var results: ResponseEventResults = []
    for await event in stream {
        results.append(event)
    }
    return results
}

public enum ResponsesSSEFixtureStream {
    public static func streamFromFixture(
        path: String,
        idleTimeoutMilliseconds: UInt64,
        telemetry: SseTelemetry? = nil
    ) -> Result<ResponseEventStream, APIError> {
        let content: String
        do {
            content = try String(contentsOfFile: path, encoding: .utf8)
        } catch {
            return .failure(.stream(String(describing: error)))
        }

        return .success(makeResponseEventStream(
            from: APIStreamResponse(statusCode: 200, sseText: fixtureSSEText(from: content)),
            makeParser: ResponsesEventFrameParser.init,
            includeRateLimits: false,
            idleTimeoutMilliseconds: idleTimeoutMilliseconds,
            telemetry: telemetry
        ))
    }

    private static func fixtureSSEText(from content: String) -> String {
        var text = ""
        content.enumerateLines { line, _ in
            text.append(line)
            text.append("\n\n")
        }
        return text
    }
}

public protocol ResponseEventFrameParsing: Sendable {
    mutating func receive(frame: String) -> ResponseEventResults
    mutating func finish() -> ResponseEventResults
}

public struct ResponsesEventFrameParser: ResponseEventFrameParsing {
    private var parser = ResponsesSSEParser()

    public init() {}

    public mutating func receive(frame: String) -> ResponseEventResults {
        parser.receive(data: frame).map(Result.success)
    }

    public mutating func finish() -> ResponseEventResults {
        [parser.finish()]
    }
}

public struct ChatEventFrameParser: ResponseEventFrameParsing {
    private var parser = ChatSSEParser()

    public init() {}

    public mutating func receive(frame: String) -> ResponseEventResults {
        parser.receive(data: frame)
    }

    public mutating func finish() -> ResponseEventResults {
        parser.finish()
    }
}

public struct StreamingAPIClient<Transport: APITransport, Auth: APIAuthProvider> {
    public let transport: Transport
    public let provider: APIProvider
    public let auth: Auth
    public var requestTelemetry: RequestTelemetry?
    public var sseTelemetry: SseTelemetry?

    public init(
        transport: Transport,
        provider: APIProvider,
        auth: Auth,
        requestTelemetry: RequestTelemetry? = nil,
        sseTelemetry: SseTelemetry? = nil
    ) {
        self.transport = transport
        self.provider = provider
        self.auth = auth
        self.requestTelemetry = requestTelemetry
        self.sseTelemetry = sseTelemetry
    }

    public func withTelemetry(_ telemetry: RequestTelemetry?) -> StreamingAPIClient {
        withTelemetry(request: telemetry, sse: sseTelemetry)
    }

    public func withTelemetry(request: RequestTelemetry?, sse: SseTelemetry?) -> StreamingAPIClient {
        var copy = self
        copy.requestTelemetry = request
        copy.sseTelemetry = sse
        return copy
    }

    public func stream(
        path: String,
        body: JSONValue,
        extraHeaders: [String: String] = [:],
        parse: @escaping @Sendable (String) -> ResponseEventResults
    ) async -> Result<ResponseEventResults, APIError> {
        await stream(
            path: path,
            body: body,
            extraHeaders: extraHeaders,
            makeParser: {
                BufferedEventFrameParser(parse: parse)
            }
        )
    }

    public func stream<Parser: ResponseEventFrameParsing>(
        path: String,
        body: JSONValue,
        extraHeaders: [String: String] = [:],
        makeParser: @escaping @Sendable () -> Parser
    ) async -> Result<ResponseEventResults, APIError> {
        switch await streamEvents(
            path: path,
            body: body,
            extraHeaders: extraHeaders,
            makeParser: makeParser,
            includeRateLimits: false
        ) {
        case let .success(stream):
            return .success(await collectResponseEvents(stream))
        case let .failure(error):
            return .failure(error)
        }
    }

    public func streamEvents<Parser: ResponseEventFrameParsing>(
        path: String,
        body: JSONValue,
        extraHeaders: [String: String] = [:],
        makeParser: @escaping @Sendable () -> Parser,
        includeRateLimits: Bool
    ) async -> Result<ResponseEventStream, APIError> {
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
            return .success(makeResponseEventStream(
                from: response,
                makeParser: makeParser,
                includeRateLimits: includeRateLimits,
                idleTimeoutMilliseconds: provider.streamIdleTimeoutMilliseconds,
                telemetry: sseTelemetry
            ))
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

private func makeResponseEventStream<Parser: ResponseEventFrameParsing>(
    from response: APIStreamResponse,
    makeParser: @escaping @Sendable () -> Parser,
    includeRateLimits: Bool,
    idleTimeoutMilliseconds: UInt64,
    telemetry: SseTelemetry?
) -> ResponseEventStream {
    ResponseEventStream { continuation in
        let taskBox = StreamTaskBox()
        let timeout = SseIdleTimeout(
            milliseconds: idleTimeoutMilliseconds,
            telemetry: telemetry,
            continuation: continuation,
            taskBox: taskBox
        )
        let task = Task {
            var lastServerModel: String?
            if let model = response.headers.caseInsensitiveValue(for: "openai-model") {
                continuation.yield(.success(.serverModel(model)))
                lastServerModel = model
            }
            if includeRateLimits {
                for snapshot in RateLimitSnapshot.parseAllRateLimits(headers: response.headers) {
                    continuation.yield(.success(.rateLimits(snapshot)))
                }
            }
            if let etag = response.headers.caseInsensitiveValue(for: "x-models-etag") {
                continuation.yield(.success(.modelsETag(etag)))
            }
            if response.headers.caseInsensitiveValue(for: "x-reasoning-included") != nil {
                continuation.yield(.success(.serverReasoningIncluded(true)))
            }

            var parser = makeParser()
            var textDecoder = UTF8StreamDecoder()
            var frameDecoder = SSEDataFrameDecoder()
            var pollStart = timeout.startPoll()

            for await chunk in response.byteStream {
                guard !Task.isCancelled else {
                    timeout.cancel()
                    return
                }

                switch chunk {
                case let .success(data):
                    guard timeout.finishPoll(.event, startedAt: pollStart) else {
                        return
                    }
                    appendResponseEvents(
                        from: frameDecoder.receive(textDecoder.receive(data)),
                        using: &parser,
                        to: continuation,
                        lastServerModel: &lastServerModel
                    )
                    pollStart = timeout.startPoll()
                case let .failure(error):
                    guard timeout.finishPoll(.streamError(error), startedAt: pollStart) else {
                        return
                    }
                    continuation.yield(.failure(.stream(String(describing: error))))
                    continuation.finish()
                    return
                }
            }

            guard timeout.finishPoll(.streamClosed, startedAt: pollStart) else {
                return
            }
            let pendingText: String
            do {
                pendingText = try textDecoder.finish()
            } catch {
                continuation.yield(.failure(.stream(String(describing: error))))
                continuation.finish()
                return
            }
            appendResponseEvents(
                from: frameDecoder.receive(pendingText) + frameDecoder.finish(),
                using: &parser,
                to: continuation,
                lastServerModel: &lastServerModel
            )
            for event in parser.finish() {
                continuation.yield(event)
            }
            continuation.finish()
        }
        taskBox.task = task

        continuation.onTermination = { _ in
            timeout.cancel()
            task.cancel()
        }
    }
}

private func appendResponseEvents<Parser: ResponseEventFrameParsing>(
    from frames: [String],
    using parser: inout Parser,
    to continuation: ResponseEventStream.Continuation,
    lastServerModel: inout String?
) {
    for frame in frames {
        if let model = frame.responseModelFromSSEDataFrame(),
           lastServerModel != model {
            continuation.yield(.success(.serverModel(model)))
            lastServerModel = model
        }
        for event in parser.receive(frame: frame) {
            continuation.yield(event)
        }
    }
}

private final class StreamTaskBox: @unchecked Sendable {
    var task: Task<Void, Never>?
}

private final class SseIdleTimeout: @unchecked Sendable {
    private let milliseconds: UInt64
    private let telemetry: SseTelemetry?
    private let continuation: ResponseEventStream.Continuation
    private let taskBox: StreamTaskBox
    private let lock = NSLock()
    private var task: Task<Void, Never>?
    private var timedOut = false

    init(
        milliseconds: UInt64,
        telemetry: SseTelemetry?,
        continuation: ResponseEventStream.Continuation,
        taskBox: StreamTaskBox
    ) {
        self.milliseconds = milliseconds
        self.telemetry = telemetry
        self.continuation = continuation
        self.taskBox = taskBox
    }

    func startPoll() -> ContinuousClock.Instant {
        let startedAt = ContinuousClock.now
        lock.withLock {
            task?.cancel()
            timedOut = false
            task = Task { [self, milliseconds, telemetry, continuation, taskBox] in
                await Self.sleep(milliseconds: milliseconds)
                guard !Task.isCancelled else {
                    return
                }
                guard markTimedOut() else {
                    return
                }
                telemetry?.onSSEPoll(result: .idleTimeout, duration: startedAt.duration(to: .now))
                continuation.yield(.failure(.stream("idle timeout waiting for SSE")))
                continuation.finish()
                taskBox.task?.cancel()
            }
        }
        return startedAt
    }

    func finishPoll(_ result: SsePollResult, startedAt: ContinuousClock.Instant) -> Bool {
        let shouldReport = lock.withLock {
            guard !timedOut else {
                return false
            }
            task?.cancel()
            task = nil
            return true
        }
        guard shouldReport else {
            return false
        }
        telemetry?.onSSEPoll(result: result, duration: startedAt.duration(to: .now))
        return true
    }

    func cancel() {
        lock.withLock {
            task?.cancel()
            task = nil
        }
    }

    private func markTimedOut() -> Bool {
        lock.withLock {
            guard !timedOut else {
                return false
            }
            task = nil
            timedOut = true
            return true
        }
    }

    private static func sleep(milliseconds: UInt64) async {
        let nanoseconds = milliseconds.multipliedReportingOverflow(by: 1_000_000)
        try? await Task.sleep(nanoseconds: nanoseconds.overflow ? UInt64.max : nanoseconds.partialValue)
    }
}

private struct BufferedEventFrameParser: ResponseEventFrameParsing {
    let parse: @Sendable (String) -> ResponseEventResults
    private var text = ""

    init(parse: @escaping @Sendable (String) -> ResponseEventResults) {
        self.parse = parse
    }

    mutating func receive(frame: String) -> ResponseEventResults {
        text.append("data: ")
        text.append(frame.replacingOccurrences(of: "\n", with: "\ndata: "))
        text.append("\n\n")
        return []
    }

    mutating func finish() -> ResponseEventResults {
        parse(text)
    }
}

private extension Dictionary where Key == String, Value == String {
    func caseInsensitiveValue(for name: String) -> String? {
        first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }
}

private extension String {
    func responseModelFromSSEDataFrame() -> String? {
        guard let value = try? JSONDecoder().decode(JSONValue.self, from: Data(utf8)),
              case let .object(object) = value
        else {
            return nil
        }
        if let responseHeaders = object["response"]?.objectValue?["headers"]?.objectValue,
           let model = Self.headerOpenAIModelValue(responseHeaders) {
            return model
        }
        if let headers = object["headers"]?.objectValue,
           let model = Self.headerOpenAIModelValue(headers) {
            return model
        }
        return nil
    }

    private static func headerOpenAIModelValue(_ headers: [String: JSONValue]) -> String? {
        for (name, value) in headers {
            guard name.caseInsensitiveCompare("openai-model") == .orderedSame
                || name.caseInsensitiveCompare("x-openai-model") == .orderedSame
            else {
                continue
            }
            if let string = value.stringValue {
                return string
            }
            return value.arrayValue?.first?.stringValue
        }
        return nil
    }
}

private extension JSONValue {
    var objectValue: [String: JSONValue]? {
        if case let .object(value) = self {
            return value
        }
        return nil
    }

    var arrayValue: [JSONValue]? {
        if case let .array(value) = self {
            return value
        }
        return nil
    }

    var stringValue: String? {
        if case let .string(value) = self {
            return value
        }
        return nil
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
    public let attestationProvider: (any AttestationProvider)?
    public var requestTelemetry: RequestTelemetry?

    public init(
        transport: Transport,
        provider: APIProvider,
        auth: Auth,
        attestationProvider: (any AttestationProvider)? = nil,
        requestTelemetry: RequestTelemetry? = nil
    ) {
        self.transport = transport
        self.provider = provider
        self.auth = auth
        self.attestationProvider = attestationProvider
        self.requestTelemetry = requestTelemetry
    }

    public func withTelemetry(_ telemetry: RequestTelemetry?) -> CompactClient {
        var copy = self
        copy.requestTelemetry = telemetry
        return copy
    }

    public func withAttestationProvider(_ attestationProvider: (any AttestationProvider)?) -> CompactClient {
        CompactClient(
            transport: transport,
            provider: provider,
            auth: auth,
            attestationProvider: attestationProvider,
            requestTelemetry: requestTelemetry
        )
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
        let attestedHeaders = await headersWithAttestation(extraHeaders)

        let result: Result<APIResponse, TransportError> = await TransportRetry.runWithRequestTelemetry(
            policy: provider.retry.toPolicy(),
            telemetry: requestTelemetry,
            makeRequest: {
                var request = provider.buildRequest(method: .post, path: path).withJSON(body)
                for (name, value) in attestedHeaders {
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

    private func headersWithAttestation(_ headers: [String: String]) async -> [String: String] {
        await AttestationRequestHeaders.addAttestationHeader(
            to: headers,
            auth: auth,
            provider: attestationProvider
        )
    }
}

public struct MemoriesClient<Transport: APITransport, Auth: APIAuthProvider> {
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

    public func withTelemetry(_ telemetry: RequestTelemetry?) -> MemoriesClient {
        var copy = self
        copy.requestTelemetry = telemetry
        return copy
    }

    public func summarizeInput(
        _ input: MemorySummarizeInput,
        extraHeaders: [String: String] = [:]
    ) async -> Result<[MemorySummarizeOutput], APIError> {
        do {
            return await summarize(body: try MemorySummarizeAPI.body(for: input), extraHeaders: extraHeaders)
        } catch {
            return .failure(.stream(String(describing: error)))
        }
    }

    public func summarize(
        body: JSONValue,
        extraHeaders: [String: String] = [:]
    ) async -> Result<[MemorySummarizeOutput], APIError> {
        let result: Result<APIResponse, TransportError> = await TransportRetry.runWithRequestTelemetry(
            policy: provider.retry.toPolicy(),
            telemetry: requestTelemetry,
            makeRequest: {
                var request = provider.buildRequest(method: .post, path: MemorySummarizeAPI.path).withJSON(body)
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
                return .success(try JSONDecoder().decode(MemorySummarizeResponse.self, from: response.body).output)
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
    public var serviceTier: String?
    public var supportedServiceTierIDs: [String]?
    public var promptCacheKey: String?
    public var text: ResponsesAPITextControls?
    public var inputModalities: [InputModality]
    public var storeOverride: Bool?
    public var conversationID: String?
    public var sessionSource: SessionSource?
    public var clientMetadata: [String: String]
    public var turnMetadataHeader: String?
    public var extraHeaders: [String: String]

    public init(
        reasoning: ResponsesAPIReasoning? = nil,
        include: [String] = [],
        serviceTier: String? = nil,
        supportedServiceTierIDs: [String]? = nil,
        promptCacheKey: String? = nil,
        text: ResponsesAPITextControls? = nil,
        inputModalities: [InputModality] = InputModality.defaultInputModalities,
        storeOverride: Bool? = nil,
        conversationID: String? = nil,
        sessionSource: SessionSource? = nil,
        clientMetadata: [String: String] = [:],
        turnMetadataHeader: String? = nil,
        extraHeaders: [String: String] = [:]
    ) {
        self.reasoning = reasoning
        self.include = include
        self.serviceTier = serviceTier
        self.supportedServiceTierIDs = supportedServiceTierIDs
        self.promptCacheKey = promptCacheKey
        self.text = text
        self.inputModalities = inputModalities
        self.storeOverride = storeOverride
        self.conversationID = conversationID
        self.sessionSource = sessionSource
        self.clientMetadata = clientMetadata
        self.turnMetadataHeader = turnMetadataHeader
        self.extraHeaders = extraHeaders
    }
}

private enum AttestationRequestHeaders {
    static func addAttestationHeader<Auth: APIAuthProvider>(
        to headers: [String: String],
        auth: Auth,
        provider: (any AttestationProvider)?
    ) async -> [String: String] {
        guard auth.accountID != nil,
              let provider,
              let threadID = headers["thread_id"]
                ?? headers["thread-id"]
                ?? headers["conversation_id"]
                ?? headers["session_id"]
                ?? headers["session-id"],
              let headerValue = await provider.header(for: Attestation.Context(threadID: threadID)),
              validHeaderValue(headerValue)
        else {
            return headers
        }

        var copy = headers
        copy[Attestation.headerName] = headerValue
        return copy
    }

    private static func validHeaderValue(_ value: String) -> Bool {
        value.unicodeScalars.allSatisfy { scalar in
            scalar.value == 0x09 || (0x20...0x7E).contains(scalar.value)
        }
    }
}

private enum ResponsesWebSocketHeaders {
    static let betaHeaderValue = "responses_websockets=2026-02-06"
    static let timingMetricsHeaderName = "x-responsesapi-include-timing-metrics"
}

public struct ResponsesClient<Transport: APITransport, Auth: APIAuthProvider> {
    public let streaming: StreamingAPIClient<Transport, Auth>
    public let attestationProvider: (any AttestationProvider)?

    public init(
        transport: Transport,
        provider: APIProvider,
        auth: Auth,
        attestationProvider: (any AttestationProvider)? = nil
    ) {
        self.streaming = StreamingAPIClient(transport: transport, provider: provider, auth: auth)
        self.attestationProvider = attestationProvider
    }

    private init(
        streaming: StreamingAPIClient<Transport, Auth>,
        attestationProvider: (any AttestationProvider)?
    ) {
        self.streaming = streaming
        self.attestationProvider = attestationProvider
    }

    public func withTelemetry(_ telemetry: RequestTelemetry?) -> ResponsesClient {
        ResponsesClient(streaming: streaming.withTelemetry(telemetry), attestationProvider: attestationProvider)
    }

    public func withTelemetry(request: RequestTelemetry?, sse: SseTelemetry?) -> ResponsesClient {
        ResponsesClient(
            streaming: streaming.withTelemetry(request: request, sse: sse),
            attestationProvider: attestationProvider
        )
    }

    public func withAttestationProvider(_ provider: (any AttestationProvider)?) -> ResponsesClient {
        ResponsesClient(streaming: streaming, attestationProvider: provider)
    }

    public func streamRequest(_ request: ResponsesRequest) async -> Result<ResponseEventResults, APIError> {
        await stream(body: request.body, extraHeaders: request.headers)
    }

    public func streamEventRequest(_ request: ResponsesRequest) async -> Result<ResponseEventStream, APIError> {
        await streamEvents(body: request.body, extraHeaders: request.headers)
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
            var input = prompt.input
            ContextNormalization.normalizeHistory(&input)
            ContextNormalization.stripImagesWhenUnsupported(inputModalities: options.inputModalities, items: &input)
            let serviceTier = options.supportedServiceTierIDs.map { supportedIDs in
                options.serviceTier.flatMap { supportedIDs.contains($0) ? $0 : nil }
            } ?? options.serviceTier

            let request = try ResponsesRequestBuilder(model: model, instructions: instructions, input: input)
                .tools(tools)
                .parallelToolCalls(prompt.parallelToolCalls)
                .reasoning(options.reasoning)
                .include(options.include)
                .serviceTier(serviceTier)
                .promptCacheKey(options.promptCacheKey)
                .text(options.text)
                .conversation(options.conversationID)
                .sessionSource(options.sessionSource)
                .storeOverride(options.storeOverride)
                .clientMetadata(options.clientMetadata)
                .turnMetadataHeader(options.turnMetadataHeader)
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
        switch await streamEvents(body: body, extraHeaders: extraHeaders) {
        case let .success(stream):
            return .success(await collectResponseEvents(stream))
        case let .failure(error):
            return .failure(error)
        }
    }

    public func streamEvents(
        body: JSONValue,
        extraHeaders: [String: String] = [:]
    ) async -> Result<ResponseEventStream, APIError> {
        let attestedHeaders = await headersWithAttestation(extraHeaders)
        return await streaming.streamEvents(
            path: Self.path(for: streaming.provider.wireAPI),
            body: body,
            extraHeaders: attestedHeaders,
            makeParser: ResponsesEventFrameParser.init,
            includeRateLimits: true
        )
    }

    public func websocketHandshakeHeaders(
        sessionID: String,
        threadID: String,
        turnMetadataHeader: String? = nil,
        turnStateHeader: String? = nil,
        betaFeaturesHeader: String? = nil,
        includeTimingMetrics: Bool = false
    ) async -> [String: String] {
        var headers: [String: String] = [:]
        if let betaFeaturesHeader,
           !betaFeaturesHeader.isEmpty,
           Self.validHeaderValue(betaFeaturesHeader) {
            headers["x-codex-beta-features"] = betaFeaturesHeader
        }
        if let turnStateHeader,
           Self.validHeaderValue(turnStateHeader) {
            headers["x-codex-turn-state"] = turnStateHeader
        }
        if let turnMetadataHeader,
           Self.validHeaderValue(turnMetadataHeader) {
            headers[CodexRequestHeaders.turnMetadataHeaderName] = turnMetadataHeader
        }
        if Self.validHeaderValue(threadID) {
            headers["x-client-request-id"] = threadID
        }
        for (name, value) in CodexRequestHeaders.sessionHeaders(sessionID: sessionID, threadID: threadID) {
            headers[name] = value
        }
        headers = await headersWithAttestation(headers)
        headers["OpenAI-Beta"] = ResponsesWebSocketHeaders.betaHeaderValue
        if includeTimingMetrics {
            headers[ResponsesWebSocketHeaders.timingMetricsHeaderName] = "true"
        }
        return headers
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

    private static func validHeaderValue(_ value: String) -> Bool {
        value.unicodeScalars.allSatisfy { scalar in
            scalar.value == 0x09 || (0x20...0x7E).contains(scalar.value)
        }
    }

    private func headersWithAttestation(_ headers: [String: String]) async -> [String: String] {
        await AttestationRequestHeaders.addAttestationHeader(
            to: headers,
            auth: streaming.auth,
            provider: attestationProvider
        )
    }
}

public extension ResponsesClient where Auth == StaticAPIAuthProvider {
    func streamRetryingProviderCommandAuth(
        body: JSONValue,
        extraHeaders: [String: String] = [:],
        providerInfo: ModelProviderInfo,
        commandRunner: ProviderAuthCommandRunner
    ) async -> Result<ResponseEventResults, APIError> {
        let result = await stream(body: body, extraHeaders: extraHeaders)
        guard result.isUnauthorized,
              let providerAuth = providerInfo.auth,
              let refreshedToken = try? await commandRunner.refreshToken(config: providerAuth)
        else {
            return result
        }

        return await ResponsesClient(
            transport: streaming.transport,
            provider: streaming.provider,
            auth: StaticAPIAuthProvider(bearerToken: refreshedToken),
            attestationProvider: attestationProvider
        )
        .stream(body: body, extraHeaders: extraHeaders)
    }

    func streamPromptRetryingProviderCommandAuth(
        model: String,
        instructions: String,
        prompt: Prompt,
        options: ResponsesOptions = ResponsesOptions(),
        providerInfo: ModelProviderInfo,
        commandRunner: ProviderAuthCommandRunner
    ) async -> Result<ResponseEventResults, APIError> {
        let result = await streamPrompt(
            model: model,
            instructions: instructions,
            prompt: prompt,
            options: options
        )
        guard result.isUnauthorized,
              let providerAuth = providerInfo.auth,
              let refreshedToken = try? await commandRunner.refreshToken(config: providerAuth)
        else {
            return result
        }

        return await ResponsesClient(
            transport: streaming.transport,
            provider: streaming.provider,
            auth: StaticAPIAuthProvider(bearerToken: refreshedToken),
            attestationProvider: attestationProvider
        )
        .streamPrompt(
            model: model,
            instructions: instructions,
            prompt: prompt,
            options: options
        )
    }
}

private extension Result where Success == ResponseEventResults, Failure == APIError {
    var isUnauthorized: Bool {
        guard case let .failure(.transport(.http(statusCode, _, _, _))) = self else {
            return false
        }
        return statusCode == 401
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

    public func withTelemetry(request: RequestTelemetry?, sse: SseTelemetry?) -> ChatClient {
        ChatClient(streaming: streaming.withTelemetry(request: request, sse: sse))
    }

    public func streamRequest(_ request: ChatRequest) async -> Result<ResponseEventResults, APIError> {
        await stream(body: request.body, extraHeaders: request.headers)
    }

    public func streamEventRequest(_ request: ChatRequest) async -> Result<ResponseEventStream, APIError> {
        await streamEvents(body: request.body, extraHeaders: request.headers)
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
        switch await streamEvents(body: body, extraHeaders: extraHeaders) {
        case let .success(stream):
            return .success(await collectResponseEvents(stream))
        case let .failure(error):
            return .failure(error)
        }
    }

    public func streamEvents(
        body: JSONValue,
        extraHeaders: [String: String] = [:]
    ) async -> Result<ResponseEventStream, APIError> {
        await streaming.streamEvents(
            path: Self.path(for: streaming.provider.wireAPI),
            body: body,
            extraHeaders: extraHeaders,
            makeParser: ChatEventFrameParser.init,
            includeRateLimits: false
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
