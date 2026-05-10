import CodexCore
import XCTest

final class ExecServerClientTests: XCTestCase {
    func testClientInitializeSendsRustHandshakeAndStoresSessionID() async throws {
        let transport = ScriptedExecServerClientTransport { message in
            switch message {
            case let .request(request):
                XCTAssertEqual(request.id, .integer(1))
                XCTAssertEqual(request.method, execServerInitializeMethod)
                XCTAssertEqual(request.params, .object([
                    "clientName": .string("swift-test"),
                    "resumeSessionId": .string("session-old")
                ]))
                return ExecServerRPC.response(
                    id: request.id,
                    result: try ExecServerRPC.jsonValue(from: ExecServerInitializeResponse(sessionId: "session-new"))
                )
            case let .notification(notification):
                XCTAssertEqual(notification, ExecServerJSONRPCNotification(
                    method: execServerInitializedMethod,
                    params: .object([:])
                ))
                return nil
            case .response, .error:
                XCTFail("Client should not send responses or errors")
                return nil
            }
        }
        let client = ExecServerClient(transport: transport)

        let response = try await client.initialize(options: ExecServerClientConnectOptions(
            clientName: "swift-test",
            initializeTimeoutSeconds: 0,
            resumeSessionID: "session-old"
        ))

        XCTAssertEqual(response, ExecServerInitializeResponse(sessionId: "session-new"))
        let sessionID = await client.sessionID
        XCTAssertEqual(sessionID, "session-new")
        let methods = await transport.snapshot().map { $0.method }
        XCTAssertEqual(methods, [
            execServerInitializeMethod,
            execServerInitializedMethod
        ])
    }

    func testClientUsesSequentialRequestIDsAndTypedExecServerMethods() async throws {
        let transport = ScriptedExecServerClientTransport { message in
            guard case let .request(request) = message else {
                return nil
            }
            switch request.method {
            case execServerProcessStartMethod:
                XCTAssertEqual(request.id, .integer(1))
                XCTAssertEqual(request.params?["processId"], .string("proc-1"))
                return ExecServerRPC.response(
                    id: request.id,
                    result: try ExecServerRPC.jsonValue(from: ExecServerExecResponse(processId: "proc-1"))
                )
            case execServerProcessReadMethod:
                XCTAssertEqual(request.id, .integer(2))
                XCTAssertEqual(request.params?["afterSeq"], .integer(7))
                return ExecServerRPC.response(
                    id: request.id,
                    result: try ExecServerRPC.jsonValue(from: ExecServerReadResponse(
                        chunks: [],
                        nextSeq: 8,
                        exited: false,
                        closed: false
                    ))
                )
            case execServerFsReadFileMethod:
                XCTAssertEqual(request.id, .integer(3))
                XCTAssertEqual(request.params?["path"], .string("/tmp/file.txt"))
                return ExecServerRPC.response(
                    id: request.id,
                    result: try ExecServerRPC.jsonValue(from: ExecServerFsReadFileResponse(dataBase64: "aGk="))
                )
            case execServerHttpRequestMethod:
                XCTAssertEqual(request.id, .integer(4))
                XCTAssertEqual(request.params?["bodyBase64"], .string("aGk="))
                return ExecServerRPC.response(
                    id: request.id,
                    result: try ExecServerRPC.jsonValue(from: ExecServerHttpRequestResponse(
                        status: 200,
                        headers: [ExecServerHttpHeader(name: "content-type", value: "text/plain")],
                        body: ExecServerByteChunk(Array("ok".utf8))
                    ))
                )
            default:
                XCTFail("Unexpected method \(request.method)")
                return nil
            }
        }
        let client = ExecServerClient(transport: transport)

        let started = try await client.startProcess(ExecServerExecParams(
            processId: "proc-1",
            argv: ["/bin/echo", "hi"],
            cwd: "/tmp",
            env: [:],
            tty: false
        ))
        let read = try await client.readProcess(ExecServerReadParams(processId: "proc-1", afterSeq: 7))
        let file = try await client.readFile(ExecServerFsReadFileParams(
            path: try AbsolutePath(absolutePath: "/tmp/file.txt")
        ))
        let http = try await client.httpRequest(ExecServerHttpRequestParams(
            method: "POST",
            url: "https://example.test",
            body: ExecServerByteChunk(Array("hi".utf8)),
            requestId: "http-1"
        ))

        XCTAssertEqual(started.processId, "proc-1")
        XCTAssertEqual(read.nextSeq, 8)
        XCTAssertEqual(file.dataBase64, "aGk=")
        XCTAssertEqual(http.status, 200)
        let methods = await transport.snapshot().map { $0.method }
        XCTAssertEqual(methods, [
            execServerProcessStartMethod,
            execServerProcessReadMethod,
            execServerFsReadFileMethod,
            execServerHttpRequestMethod
        ])
    }

    func testClientMapsServerErrorAndTransportCloseLikeRust() async throws {
        let serverErrorTransport = ScriptedExecServerClientTransport { message in
            guard case let .request(request) = message else {
                return nil
            }
            return ExecServerRPC.error(
                id: request.id,
                error: ExecServerRPC.invalidRequest("client must call initialize before using exec methods")
            )
        }
        let serverErrorClient = ExecServerClient(transport: serverErrorTransport)
        await XCTAssertThrowsExecServerClientError(
            try await serverErrorClient.terminateProcess(ExecServerTerminateParams(processId: "missing")),
            description: "exec-server rejected request (-32600): client must call initialize before using exec methods"
        )

        let closedClient = ExecServerClient(transport: ClosureExecServerClientTransport { _ in nil })
        await XCTAssertThrowsExecServerClientError(
            try await closedClient.terminateProcess(ExecServerTerminateParams(processId: "missing")),
            description: "exec-server transport disconnected"
        )
        await XCTAssertThrowsExecServerClientError(
            try await closedClient.terminateProcess(ExecServerTerminateParams(processId: "missing")),
            description: "exec-server transport disconnected"
        )
    }

    func testClientRejectsUnexpectedResponseShapesLikeRustProtocolErrors() async throws {
        let mismatchedTransport = ScriptedExecServerClientTransport { _ in
            ExecServerRPC.response(
                id: .integer(99),
                result: try ExecServerRPC.jsonValue(from: ExecServerTerminateResponse(running: false))
            )
        }
        let client = ExecServerClient(transport: mismatchedTransport)

        await XCTAssertThrowsExecServerClientError(
            try await client.terminateProcess(ExecServerTerminateParams(processId: "proc-1")),
            description: "exec-server protocol error: exec-server response id integer(99) did not match request id integer(1)"
        )
    }

    private func XCTAssertThrowsExecServerClientError<T>(
        _ expression: @autoclosure @escaping () async throws -> T,
        description: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await expression()
            XCTFail("Expected exec-server client error", file: file, line: line)
        } catch let error as ExecServerClientError {
            XCTAssertEqual(error.description, description, file: file, line: line)
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
    }
}

private actor ScriptedExecServerClientTransport: ExecServerClientTransport {
    typealias Handler = @Sendable (ExecServerJSONRPCMessage) async throws -> ExecServerJSONRPCMessage?

    private let handler: Handler
    private var messages: [ExecServerJSONRPCMessage] = []

    init(handler: @escaping Handler) {
        self.handler = handler
    }

    func send(_ message: ExecServerJSONRPCMessage) async throws -> ExecServerJSONRPCMessage? {
        messages.append(message)
        return try await handler(message)
    }

    func snapshot() -> [ExecServerJSONRPCMessage] {
        messages
    }
}

private extension ExecServerJSONRPCMessage {
    var method: String {
        switch self {
        case let .request(request):
            return request.method
        case let .notification(notification):
            return notification.method
        case .response:
            return "<response>"
        case .error:
            return "<error>"
        }
    }
}

private extension JSONValue {
    subscript(key: String) -> JSONValue? {
        guard case let .object(object) = self else {
            return nil
        }
        return object[key]
    }
}
