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

    func testLineClientTransportWritesStdioLinesAndFansOutNotificationsLikeRust() async throws {
        let harness = LineClientHarness()
        let notification = ExecServerJSONRPCNotification(
            method: execServerProcessOutputDeltaMethod,
            params: try ExecServerRPC.jsonValue(from: ExecServerOutputDeltaNotification(
                processId: "proc-1",
                seq: 1,
                stream: .stdout,
                chunk: ExecServerByteChunk(Array("hi".utf8))
            ))
        )
        await harness.enqueueReadLine("   ")
        await harness.enqueueReadLine(try line(for: .notification(notification)))
        await harness.enqueueReadLine(try line(for: ExecServerRPC.response(
            id: .integer(1),
            result: try ExecServerRPC.jsonValue(from: ExecServerExecResponse(processId: "proc-1"))
        )))
        let transport = ExecServerLineClientTransport(
            readLine: { await harness.readLine() },
            writeLine: { await harness.writeLine($0) },
            notificationHandler: { await harness.recordNotification($0) }
        )
        let client = ExecServerClient(transport: transport)

        let response = try await client.startProcess(ExecServerExecParams(
            processId: "proc-1",
            argv: ["/bin/echo", "hi"],
            cwd: "/tmp",
            env: [:],
            tty: false
        ))

        XCTAssertEqual(response.processId, "proc-1")
        let writes = try await harness.writtenMessages()
        XCTAssertEqual(writes.count, 1)
        guard case let .request(request) = try XCTUnwrap(writes.first) else {
            return XCTFail("Expected request")
        }
        XCTAssertEqual(request.id, .integer(1))
        XCTAssertEqual(request.method, execServerProcessStartMethod)
        let notifications = await harness.notifications
        XCTAssertEqual(notifications, [notification])
    }

    func testLineClientTransportMapsMalformedAndClosedReadsLikeRust() async throws {
        let malformedHarness = LineClientHarness()
        await malformedHarness.enqueueReadLine("{")
        let malformedClient = ExecServerClient(transport: ExecServerLineClientTransport(
            readLine: { await malformedHarness.readLine() },
            writeLine: { await malformedHarness.writeLine($0) }
        ))
        await XCTAssertThrowsExecServerClientError(
            try await malformedClient.terminateProcess(ExecServerTerminateParams(processId: "proc-1")),
            descriptionPrefix: "exec-server protocol error: failed to parse JSON-RPC message from exec-server stdio command:"
        )

        let closedHarness = LineClientHarness()
        let closedClient = ExecServerClient(transport: ExecServerLineClientTransport(
            readLine: { await closedHarness.readLine() },
            writeLine: { await closedHarness.writeLine($0) }
        ))
        await XCTAssertThrowsExecServerClientError(
            try await closedClient.terminateProcess(ExecServerTerminateParams(processId: "proc-1")),
            description: "exec-server transport disconnected"
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

    private func XCTAssertThrowsExecServerClientError<T>(
        _ expression: @autoclosure @escaping () async throws -> T,
        descriptionPrefix: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await expression()
            XCTFail("Expected exec-server client error", file: file, line: line)
        } catch let error as ExecServerClientError {
            XCTAssertTrue(
                error.description.hasPrefix(descriptionPrefix),
                "Expected prefix \(descriptionPrefix), got \(error.description)",
                file: file,
                line: line
            )
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

private actor LineClientHarness {
    private var readLines: [String] = []
    private var written: [Data] = []
    private var observedNotifications: [ExecServerJSONRPCNotification] = []

    var notifications: [ExecServerJSONRPCNotification] {
        observedNotifications
    }

    func enqueueReadLine(_ line: String) {
        readLines.append(line)
    }

    func readLine() -> String? {
        guard !readLines.isEmpty else {
            return nil
        }
        return readLines.removeFirst()
    }

    func writeLine(_ data: Data) {
        written.append(data)
    }

    func recordNotification(_ notification: ExecServerJSONRPCNotification) {
        observedNotifications.append(notification)
    }

    func writtenMessages() throws -> [ExecServerJSONRPCMessage] {
        try written.map { data in
            var line = data
            if line.last == 0x0A {
                line.removeLast()
            }
            return try JSONDecoder().decode(ExecServerJSONRPCMessage.self, from: line)
        }
    }
}

private func line(for message: ExecServerJSONRPCMessage) throws -> String {
    let data = try ExecServerJSONRPCCodec.encodeLine(message)
    return String(decoding: data.dropLast(), as: UTF8.self)
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
