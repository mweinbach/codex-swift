import CodexCore
import XCTest

final class ExecServerTests: XCTestCase {
    func testJSONRPCCodecSkipsBlankStdioLinesLikeRust() {
        XCTAssertNil(ExecServerJSONRPCCodec.stdioEvent(fromLine: "", connectionLabel: "stdio"))
        XCTAssertNil(ExecServerJSONRPCCodec.stdioEvent(fromLine: " \t\n", connectionLabel: "stdio"))
    }

    func testJSONRPCCodecDecodesStdioLineToMessageEventLikeRust() throws {
        let line = #"{"id":1,"method":"initialize","params":{"clientName":"client"}}"#

        let event = ExecServerJSONRPCCodec.stdioEvent(fromLine: line, connectionLabel: "exec-server stdio")

        XCTAssertEqual(event, .message(.request(ExecServerJSONRPCRequest(
            id: .integer(1),
            method: execServerInitializeMethod,
            params: .object(["clientName": .string("client")])
        ))))
    }

    func testJSONRPCCodecReportsMalformedStdioLineWithRustLabel() {
        let event = ExecServerJSONRPCCodec.stdioEvent(fromLine: "{", connectionLabel: "exec-server stdio")

        guard case let .malformedMessage(reason)? = event else {
            return XCTFail("Expected malformed stdio message")
        }
        XCTAssertTrue(reason.hasPrefix("failed to parse JSON-RPC message from exec-server stdio:"))
    }

    func testJSONRPCCodecDecodesWebSocketTextAndBinaryLikeRust() throws {
        let text = #"{"method":"initialized","params":{}}"#
        let binary = Data(#"{"id":"a","result":{"ok":true}}"#.utf8)

        let textEvent = ExecServerJSONRPCCodec.webSocketTextEvent(text, connectionLabel: "exec-server websocket 127.0.0.1:9")
        let binaryEvent = ExecServerJSONRPCCodec.webSocketBinaryEvent(binary, connectionLabel: "exec-server websocket 127.0.0.1:9")

        XCTAssertEqual(textEvent, .message(.notification(ExecServerJSONRPCNotification(
            method: execServerInitializedMethod,
            params: .object([:])
        ))))
        XCTAssertEqual(binaryEvent, .message(.response(ExecServerJSONRPCResponse(
            id: .string("a"),
            result: .object(["ok": .bool(true)])
        ))))
    }

    func testJSONRPCCodecReportsMalformedWebSocketPayloadsWithRustLabel() {
        let textEvent = ExecServerJSONRPCCodec.webSocketTextEvent("{", connectionLabel: "exec-server websocket peer")
        let binaryEvent = ExecServerJSONRPCCodec.webSocketBinaryEvent(Data("{".utf8), connectionLabel: "exec-server websocket peer")

        guard case let .malformedMessage(textReason) = textEvent else {
            return XCTFail("Expected malformed websocket text")
        }
        guard case let .malformedMessage(binaryReason) = binaryEvent else {
            return XCTFail("Expected malformed websocket binary")
        }
        XCTAssertTrue(textReason.hasPrefix("failed to parse websocket JSON-RPC message from exec-server websocket peer:"))
        XCTAssertTrue(binaryReason.hasPrefix("failed to parse websocket JSON-RPC message from exec-server websocket peer:"))
    }

    func testJSONRPCCodecEncodesOutboundStdioLinesLikeRust() throws {
        let message = ExecServerRPC.response(
            id: .integer(1),
            result: .object(["sessionId": .string("session-1")])
        )

        let line = try ExecServerJSONRPCCodec.encodeLine(message)

        XCTAssertEqual(line.last, 0x0A)
        let decoded = try JSONDecoder().decode(ExecServerJSONRPCMessage.self, from: Data(line.dropLast()))
        XCTAssertEqual(decoded, message)
    }

    func testJSONRPCCodecEncodesOutboundWebSocketTextLikeRust() throws {
        let message = ExecServerRPC.error(
            id: .integer(-1),
            error: ExecServerRPC.invalidRequest("bad")
        )

        let text = try ExecServerJSONRPCCodec.encodeWebSocketText(message)
        let decoded = try JSONDecoder().decode(ExecServerJSONRPCMessage.self, from: Data(text.utf8))

        XCTAssertEqual(decoded, message)
        XCTAssertFalse(text.contains("\n"))
    }

    func testConnectionProcessorRoutesMessagesSequentiallyLikeRust() async throws {
        let processor = ExecServerConnectionProcessor(
            sessionRegistry: ExecServerSessionRegistry(makeID: sequenceIDs(["connection-1", "session-1"]))
        )
        let connection = await processor.makeConnection()
        let initialize = ExecServerJSONRPCRequest(
            id: .integer(1),
            method: execServerInitializeMethod,
            params: try ExecServerRPC.jsonValue(from: ExecServerInitializeParams(clientName: "client"))
        )
        let pendingExec = ExecServerJSONRPCRequest(
            id: .integer(2),
            method: execServerProcessTerminateMethod,
            params: try ExecServerRPC.jsonValue(from: ExecServerTerminateParams(processId: "p1"))
        )

        let initializeResponse = await connection.handle(.message(.request(initialize)))
        let initializedResponse = await connection.handle(.message(.notification(ExecServerJSONRPCNotification(
            method: execServerInitializedMethod,
            params: .object([:])
        ))))
        let pendingExecResponse = await connection.handle(.message(.request(pendingExec)))

        XCTAssertEqual(initializeResponse?.jsonRPCMessage, ExecServerRPC.response(
            id: .integer(1),
            result: .object(["sessionId": .string("session-1")])
        ))
        XCTAssertNil(initializedResponse)
        XCTAssertEqual(pendingExecResponse, .response(
            requestID: .integer(2),
            result: .object(["running": .bool(false)])
        ))
    }

    func testConnectionProcessorHandlesStdioCodecEventsLikeRust() async throws {
        let processor = ExecServerConnectionProcessor(
            sessionRegistry: ExecServerSessionRegistry(makeID: sequenceIDs(["connection-1", "session-1"]))
        )
        let connection = await processor.makeConnection()
        let blank = await connection.handleStdioLine("  ", connectionLabel: "exec-server stdio")
        let initialize = await connection.handleStdioLine(
            #"{"id":1,"method":"initialize","params":{"clientName":"client"}}"#,
            connectionLabel: "exec-server stdio"
        )
        let malformed = await connection.handleStdioLine("{", connectionLabel: "exec-server stdio")

        XCTAssertNil(blank)
        XCTAssertEqual(initialize?.jsonRPCMessage, ExecServerRPC.response(
            id: .integer(1),
            result: .object(["sessionId": .string("session-1")])
        ))
        guard case let .error(requestID, error) = malformed else {
            return XCTFail("Expected malformed stdio error")
        }
        XCTAssertEqual(requestID, .integer(-1))
        XCTAssertEqual(error.code, -32600)
        XCTAssertTrue(error.message.hasPrefix("failed to parse JSON-RPC message from exec-server stdio:"))
    }

    func testLineServerServesNewlineDelimitedStdioMessagesLikeRust() async throws {
        let server = ExecServerLineServer(
            sessionRegistry: ExecServerSessionRegistry(makeID: sequenceIDs(["connection-1", "session-1"]))
        )

        let blankLines = try await server.receiveLine(" \t")
        let initializeLines = try await server.receiveLine(
            #"{"id":1,"method":"initialize","params":{"clientName":"client"}}"#
        )
        let initializedLines = try await server.receiveLine(#"{"method":"initialized","params":{}}"#)
        let terminateLines = try await server.receiveLine(
            #"{"id":2,"method":"process/terminate","params":{"processId":"missing"}}"#
        )

        XCTAssertEqual(blankLines, [])
        XCTAssertEqual(initializeLines.count, 1)
        XCTAssertEqual(try decodeLine(initializeLines[0]), ExecServerRPC.response(
            id: .integer(1),
            result: .object(["sessionId": .string("session-1")])
        ))
        XCTAssertEqual(initializedLines, [])
        XCTAssertEqual(terminateLines.count, 1)
        XCTAssertEqual(try decodeLine(terminateLines[0]), ExecServerRPC.response(
            id: .integer(2),
            result: .object(["running": .bool(false)])
        ))
    }

    func testLineServerReportsMalformedStdioLinesAndContinuesLikeRust() async throws {
        let server = ExecServerLineServer(
            sessionRegistry: ExecServerSessionRegistry(makeID: sequenceIDs(["connection-1", "session-1"]))
        )

        let malformedLines = try await server.receiveLine("{")
        let initializeLines = try await server.receiveLine(
            #"{"id":1,"method":"initialize","params":{"clientName":"client"}}"#
        )

        XCTAssertEqual(malformedLines.count, 1)
        guard case let .error(errorEnvelope) = try decodeLine(malformedLines[0]) else {
            return XCTFail("Expected malformed line error")
        }
        XCTAssertEqual(errorEnvelope.id, .integer(-1))
        XCTAssertEqual(errorEnvelope.error.code, -32600)
        XCTAssertTrue(errorEnvelope.error.message.hasPrefix("failed to parse JSON-RPC message from exec-server stdio:"))
        XCTAssertEqual(initializeLines.count, 1)
        XCTAssertEqual(try decodeLine(initializeLines[0]), ExecServerRPC.response(
            id: .integer(1),
            result: .object(["sessionId": .string("session-1")])
        ))
    }

    func testLineServerDrainsQueuedNotificationsLikeRustOutboundTask() async throws {
        let server = ExecServerLineServer(httpClient: ExecServerHTTPClient(
            send: { _ in URLSessionTransportResponse(statusCode: 500) },
            stream: { _ in
                APIStreamResponse(
                    statusCode: 200,
                    byteStream: APIByteStream { continuation in
                        continuation.yield(.success(Data("hello".utf8)))
                        continuation.finish()
                    }
                )
            }
        ))
        _ = try await server.receiveLine(#"{"id":1,"method":"initialize","params":{"clientName":"client"}}"#)
        _ = try await server.receiveLine(#"{"method":"initialized","params":{}}"#)

        let responseLines = try await server.receiveLine(#"{"id":2,"method":"http/request","params":{"method":"GET","url":"https://example.test/mcp","requestId":"stream-stdio","streamResponse":true}}"#)

        XCTAssertEqual(responseLines.count, 1)
        XCTAssertEqual(try decodeLine(responseLines[0]), ExecServerRPC.response(
            id: .integer(2),
            result: .object([
                "bodyBase64": .string(""),
                "headers": .array([]),
                "status": .integer(200)
            ])
        ))
        let deltas = try await collectHTTPBodyDeltaLines(from: server, requestId: "stream-stdio")
        XCTAssertEqual(deltas.map(\.seq), [1, 2])
        XCTAssertEqual(deltas.flatMap { $0.delta.bytes }, Array("hello".utf8))
        XCTAssertEqual(deltas.last?.done, true)
    }

    func testStdioTransportWritesQueuedNotificationsWithoutAdditionalInputLikeRust() async throws {
        var inputContinuation: AsyncStream<String>.Continuation?
        let input = AsyncStream<String> { continuation in
            inputContinuation = continuation
        }
        let output = StdioTransportOutput()
        let transport = ExecServerStdioTransport(server: ExecServerLineServer(
            sessionRegistry: ExecServerSessionRegistry(makeID: sequenceIDs(["connection-1", "session-1"])),
            httpClient: ExecServerHTTPClient(
                send: { _ in URLSessionTransportResponse(statusCode: 500) },
                stream: { _ in
                    APIStreamResponse(
                        statusCode: 200,
                        byteStream: APIByteStream { continuation in
                            continuation.yield(.success(Data("hello".utf8)))
                            continuation.finish()
                        }
                    )
                }
            )
        ))

        let runTask = Task {
            try await transport.run(lines: input) { line in
                await output.append(line)
            }
        }
        let continuation = try XCTUnwrap(inputContinuation)
        continuation.yield(#"{"id":1,"method":"initialize","params":{"clientName":"client"}}"#)
        continuation.yield(#"{"method":"initialized","params":{}}"#)
        continuation.yield(#"{"id":2,"method":"http/request","params":{"method":"GET","url":"https://example.test/mcp","requestId":"transport-stream","streamResponse":true}}"#)

        let messages = try await output.waitForMessages(count: 3)
        XCTAssertEqual(messages[0], ExecServerRPC.response(
            id: .integer(1),
            result: .object(["sessionId": .string("session-1")])
        ))
        XCTAssertEqual(messages[1], ExecServerRPC.response(
            id: .integer(2),
            result: .object([
                "bodyBase64": .string(""),
                "headers": .array([]),
                "status": .integer(200)
            ])
        ))
        guard case let .notification(notification) = messages[2] else {
            return XCTFail("Expected queued http/request body delta notification")
        }
        XCTAssertEqual(notification.method, execServerHttpRequestBodyDeltaMethod)
        let delta = try decodeJSONValue(
            try XCTUnwrap(notification.params),
            as: ExecServerHttpRequestBodyDeltaNotification.self
        )
        XCTAssertEqual(delta.requestId, "transport-stream")
        XCTAssertEqual(delta.seq, 1)
        XCTAssertEqual(delta.delta.bytes, Array("hello".utf8))
        XCTAssertFalse(delta.done)

        let terminalMessages = try await output.waitForMessages(count: 4)
        guard case let .notification(terminalNotification) = terminalMessages[3] else {
            return XCTFail("Expected terminal http/request body delta notification")
        }
        let terminalDelta = try decodeJSONValue(
            try XCTUnwrap(terminalNotification.params),
            as: ExecServerHttpRequestBodyDeltaNotification.self
        )
        XCTAssertEqual(terminalDelta.requestId, "transport-stream")
        XCTAssertEqual(terminalDelta.seq, 2)
        XCTAssertTrue(terminalDelta.done)

        continuation.finish()
        try await runTask.value
    }

    func testStdioTransportWritesProcessLifecycleNotificationsWithoutAdditionalInputLikeRust() async throws {
        var inputContinuation: AsyncStream<String>.Continuation?
        let input = AsyncStream<String> { continuation in
            inputContinuation = continuation
        }
        let output = StdioTransportOutput()
        let transport = ExecServerStdioTransport(server: ExecServerLineServer(
            sessionRegistry: ExecServerSessionRegistry(makeID: sequenceIDs(["connection-1", "session-1"]))
        ))

        let runTask = Task {
            try await transport.run(lines: input) { line in
                await output.append(line)
            }
        }
        let continuation = try XCTUnwrap(inputContinuation)
        continuation.yield(#"{"id":1,"method":"initialize","params":{"clientName":"client"}}"#)
        continuation.yield(#"{"method":"initialized","params":{}}"#)
        continuation.yield(#"{"id":2,"method":"process/start","params":{"processId":"transport-proc","argv":["/bin/sh","-c","printf 'transport-push\n'; sleep 0.05"],"cwd":"/tmp","env":{},"tty":false}}"#)

        let messages = try await output.waitForMessages(count: 5)
        XCTAssertEqual(messages[0], ExecServerRPC.response(
            id: .integer(1),
            result: .object(["sessionId": .string("session-1")])
        ))
        XCTAssertEqual(messages[1], ExecServerRPC.response(
            id: .integer(2),
            result: .object(["processId": .string("transport-proc")])
        ))

        guard case let .notification(outputNotification) = messages[2],
              case let .notification(exitedNotification) = messages[3],
              case let .notification(closedNotification) = messages[4] else {
            return XCTFail("Expected process lifecycle notifications")
        }
        XCTAssertEqual(outputNotification.method, execServerProcessOutputDeltaMethod)
        XCTAssertEqual(exitedNotification.method, execServerProcessExitedMethod)
        XCTAssertEqual(closedNotification.method, execServerProcessClosedMethod)

        let outputDelta = try decodeJSONValue(
            try XCTUnwrap(outputNotification.params),
            as: ExecServerOutputDeltaNotification.self
        )
        let exited = try decodeJSONValue(
            try XCTUnwrap(exitedNotification.params),
            as: ExecServerExitedNotification.self
        )
        let closed = try decodeJSONValue(
            try XCTUnwrap(closedNotification.params),
            as: ExecServerClosedNotification.self
        )
        XCTAssertEqual(outputDelta.processId, "transport-proc")
        XCTAssertEqual(outputDelta.seq, 1)
        XCTAssertEqual(outputDelta.stream, .stdout)
        XCTAssertEqual(outputDelta.chunk.bytes, Array("transport-push\n".utf8))
        XCTAssertEqual(exited.processId, "transport-proc")
        XCTAssertEqual(exited.seq, 2)
        XCTAssertEqual(exited.exitCode, 0)
        XCTAssertEqual(closed.processId, "transport-proc")
        XCTAssertEqual(closed.seq, 3)

        continuation.finish()
        try await runTask.value
    }

    func testConnectionProcessorHandlesWebSocketCodecEventsLikeRust() async {
        let connection = ExecServerConnection()
        let malformed = await connection.handleWebSocketText("{", connectionLabel: "exec-server websocket peer")

        guard case let .error(requestID, error) = malformed else {
            return XCTFail("Expected malformed websocket error")
        }
        XCTAssertEqual(requestID, .integer(-1))
        XCTAssertEqual(error.code, -32600)
        XCTAssertTrue(error.message.hasPrefix("failed to parse websocket JSON-RPC message from exec-server websocket peer:"))
    }

    func testConnectionProcessorStartsAndReadsPipeProcessLikeRust() async throws {
        let connection = try await initializedConnection()
        let cwd = FileManager.default.currentDirectoryPath

        let start = await connection.handle(.message(.request(ExecServerJSONRPCRequest(
            id: .integer(2),
            method: execServerProcessStartMethod,
            params: try ExecServerRPC.jsonValue(from: ExecServerExecParams(
                processId: "proc-output",
                argv: ["/bin/sh", "-c", "printf 'session output\\n'"],
                cwd: cwd,
                env: [:],
                tty: false
            ))
        ))))
        let read = try await readProcessUntilClosed(connection, processId: "proc-output")

        XCTAssertEqual(start?.jsonRPCMessage, ExecServerRPC.response(
            id: .integer(2),
            result: .object(["processId": .string("proc-output")])
        ))
        XCTAssertEqual(read.output, "session output\n")
        XCTAssertEqual(read.exitCode, 0)
        XCTAssertTrue(read.closed)
    }

    func testConnectionProcessorPushesProcessLifecycleNotificationsLikeRust() async throws {
        let connection = try await initializedConnection()
        let cwd = FileManager.default.currentDirectoryPath

        let start = await connection.handle(.message(.request(ExecServerJSONRPCRequest(
            id: .integer(2),
            method: execServerProcessStartMethod,
            params: try ExecServerRPC.jsonValue(from: ExecServerExecParams(
                processId: "proc-notify",
                argv: ["/bin/sh", "-c", "printf 'push-notify\\n'; sleep 0.05"],
                cwd: cwd,
                env: [:],
                tty: false
            ))
        ))))

        XCTAssertEqual(start?.jsonRPCMessage, ExecServerRPC.response(
            id: .integer(2),
            result: .object(["processId": .string("proc-notify")])
        ))

        let notifications = try await collectProcessLifecycleNotifications(
            from: connection,
            processId: "proc-notify"
        )
        XCTAssertEqual(notifications.output?.seq, 1)
        XCTAssertEqual(notifications.output?.stream, .stdout)
        XCTAssertEqual(notifications.output?.chunk.bytes, Array("push-notify\n".utf8))
        XCTAssertEqual(notifications.exited?.exitCode, 0)
        XCTAssertEqual(notifications.exited?.seq, 2)
        XCTAssertEqual(notifications.closed?.seq, 3)

        let retained = try await readProcessUntilClosed(connection, processId: "proc-notify")
        XCTAssertEqual(retained.output, "push-notify\n")
        XCTAssertEqual(retained.exitCode, 0)
        XCTAssertTrue(retained.closed)
    }

    func testHandlerRetainsThenEvictsClosedProcessesLikeRust() async throws {
        let processStore = ExecServerProcessStore(retentionDelayNanoseconds: 25_000_000)
        let handler = ExecServerHandler(
            sessionRegistry: ExecServerSessionRegistry(makeID: sequenceIDs(["connection-1", "session-1"])),
            processStore: processStore
        )
        _ = try await handler.initialize(ExecServerInitializeParams(clientName: "client"))
        try await handler.markInitialized()

        let processId = "proc-retention"
        _ = try await handler.startProcess(ExecServerExecParams(
            processId: processId,
            argv: ["/bin/sh", "-c", "printf 'retained\\n'"],
            cwd: FileManager.default.currentDirectoryPath,
            env: [:],
            tty: false
        ))
        let retained = try await readHandlerProcessUntilClosed(handler, processId: processId)

        XCTAssertEqual(retained.output, "retained\n")
        XCTAssertEqual(retained.exitCode, 0)
        XCTAssertTrue(retained.closed)
        let finalRead = try await handler.readProcess(ExecServerReadParams(processId: processId))
        XCTAssertTrue(finalRead.closed)

        try await Task.sleep(nanoseconds: 75_000_000)
        await XCTAssertThrowsExecServerError(
            try await handler.readProcess(ExecServerReadParams(processId: processId)),
            code: -32600,
            message: "unknown process id \(processId)"
        )

        let restarted = try await handler.startProcess(ExecServerExecParams(
            processId: processId,
            argv: ["/bin/sh", "-c", "true"],
            cwd: FileManager.default.currentDirectoryPath,
            env: [:],
            tty: false
        ))
        XCTAssertEqual(restarted.processId, processId)
        await handler.shutdown()
    }

    func testConnectionProcessorWritesToPipeStdinLikeRust() async throws {
        let connection = try await initializedConnection()
        let cwd = FileManager.default.currentDirectoryPath
        _ = await connection.handle(.message(.request(ExecServerJSONRPCRequest(
            id: .integer(2),
            method: execServerProcessStartMethod,
            params: try ExecServerRPC.jsonValue(from: ExecServerExecParams(
                processId: "proc-stdin",
                argv: ["/bin/sh", "-c", "IFS= read line; printf 'from-stdin:%s\\n' \"$line\""],
                cwd: cwd,
                env: [:],
                tty: false,
                pipeStdin: true
            ))
        ))))

        let write = await connection.handle(.message(.request(ExecServerJSONRPCRequest(
            id: .integer(3),
            method: execServerProcessWriteMethod,
            params: try ExecServerRPC.jsonValue(from: ExecServerWriteParams(
                processId: "proc-stdin",
                chunk: ExecServerByteChunk(Array("hello\n".utf8))
            ))
        ))))
        let read = try await readProcessUntilClosed(connection, processId: "proc-stdin")

        XCTAssertEqual(write?.jsonRPCMessage, ExecServerRPC.response(
            id: .integer(3),
            result: .object(["status": .string("accepted")])
        ))
        XCTAssertEqual(read.output, "from-stdin:hello\n")
        XCTAssertEqual(read.exitCode, 0)
        XCTAssertTrue(read.closed)
    }

    func testConnectionProcessorReportsProcessWriteStatusesLikeRust() async throws {
        let connection = try await initializedConnection()
        let cwd = FileManager.default.currentDirectoryPath
        _ = await connection.handle(.message(.request(ExecServerJSONRPCRequest(
            id: .integer(2),
            method: execServerProcessStartMethod,
            params: try ExecServerRPC.jsonValue(from: ExecServerExecParams(
                processId: "proc-closed-stdin",
                argv: ["/bin/sh", "-c", "sleep 0.1; if IFS= read line; then printf 'read:%s\\n' \"$line\"; else printf 'eof\\n'; fi"],
                cwd: cwd,
                env: [:],
                tty: false
            ))
        ))))

        let closed = await connection.handle(.message(.request(ExecServerJSONRPCRequest(
            id: .integer(3),
            method: execServerProcessWriteMethod,
            params: try ExecServerRPC.jsonValue(from: ExecServerWriteParams(
                processId: "proc-closed-stdin",
                chunk: ExecServerByteChunk(Array("ignored\n".utf8))
            ))
        ))))
        let unknown = await connection.handle(.message(.request(ExecServerJSONRPCRequest(
            id: .integer(4),
            method: execServerProcessWriteMethod,
            params: try ExecServerRPC.jsonValue(from: ExecServerWriteParams(
                processId: "missing",
                chunk: ExecServerByteChunk(Array("ignored\n".utf8))
            ))
        ))))

        XCTAssertEqual(closed?.jsonRPCMessage, ExecServerRPC.response(
            id: .integer(3),
            result: .object(["status": .string("stdinClosed")])
        ))
        XCTAssertEqual(unknown?.jsonRPCMessage, ExecServerRPC.response(
            id: .integer(4),
            result: .object(["status": .string("unknownProcess")])
        ))
    }

    func testConnectionProcessorTerminatesProcessLikeRust() async throws {
        let connection = try await initializedConnection()
        let cwd = FileManager.default.currentDirectoryPath
        _ = await connection.handle(.message(.request(ExecServerJSONRPCRequest(
            id: .integer(2),
            method: execServerProcessStartMethod,
            params: try ExecServerRPC.jsonValue(from: ExecServerExecParams(
                processId: "proc-terminate",
                argv: ["/bin/sh", "-c", "sleep 5"],
                cwd: cwd,
                env: [:],
                tty: false
            ))
        ))))

        let terminated = await connection.handle(.message(.request(ExecServerJSONRPCRequest(
            id: .integer(3),
            method: execServerProcessTerminateMethod,
            params: try ExecServerRPC.jsonValue(from: ExecServerTerminateParams(processId: "proc-terminate"))
        ))))
        let secondTerminate = await connection.handle(.message(.request(ExecServerJSONRPCRequest(
            id: .integer(4),
            method: execServerProcessTerminateMethod,
            params: try ExecServerRPC.jsonValue(from: ExecServerTerminateParams(processId: "missing"))
        ))))

        XCTAssertEqual(terminated?.jsonRPCMessage, ExecServerRPC.response(
            id: .integer(3),
            result: .object(["running": .bool(true)])
        ))
        XCTAssertEqual(secondTerminate?.jsonRPCMessage, ExecServerRPC.response(
            id: .integer(4),
            result: .object(["running": .bool(false)])
        ))
    }

    func testConnectionProcessorReportsProcessValidationErrorsLikeRust() async throws {
        let connection = try await initializedConnection()
        let cwd = FileManager.default.currentDirectoryPath
        let emptyArgv = await connection.handle(.message(.request(ExecServerJSONRPCRequest(
            id: .integer(2),
            method: execServerProcessStartMethod,
            params: try ExecServerRPC.jsonValue(from: ExecServerExecParams(
                processId: "proc-empty",
                argv: [],
                cwd: cwd,
                env: [:],
                tty: false
            ))
        ))))
        _ = await connection.handle(.message(.request(ExecServerJSONRPCRequest(
            id: .integer(3),
            method: execServerProcessStartMethod,
            params: try ExecServerRPC.jsonValue(from: ExecServerExecParams(
                processId: "proc-duplicate",
                argv: ["/bin/sh", "-c", "sleep 0.2"],
                cwd: cwd,
                env: [:],
                tty: false
            ))
        ))))
        let duplicate = await connection.handle(.message(.request(ExecServerJSONRPCRequest(
            id: .integer(4),
            method: execServerProcessStartMethod,
            params: try ExecServerRPC.jsonValue(from: ExecServerExecParams(
                processId: "proc-duplicate",
                argv: ["/bin/sh", "-c", "true"],
                cwd: cwd,
                env: [:],
                tty: false
            ))
        ))))
        let unknownRead = await connection.handle(.message(.request(ExecServerJSONRPCRequest(
            id: .integer(5),
            method: execServerProcessReadMethod,
            params: try ExecServerRPC.jsonValue(from: ExecServerReadParams(processId: "missing"))
        ))))

        XCTAssertEqual(emptyArgv?.jsonRPCMessage, ExecServerRPC.error(
            id: .integer(2),
            error: ExecServerRPC.invalidParams("argv must not be empty")
        ))
        XCTAssertEqual(duplicate?.jsonRPCMessage, ExecServerRPC.error(
            id: .integer(4),
            error: ExecServerRPC.invalidRequest("process proc-duplicate already exists")
        ))
        XCTAssertEqual(unknownRead?.jsonRPCMessage, ExecServerRPC.error(
            id: .integer(5),
            error: ExecServerRPC.invalidRequest("unknown process id missing")
        ))
    }

    func testFilesystemDirectOperationsCoverRustSurfaceArea() throws {
        let fileSystem = ExecServerFileSystem()
        let tempDirectory = try makeTemporaryDirectory()
        let sourceDirectory = tempDirectory.appendingPathComponent("source")
        let nestedDirectory = sourceDirectory.appendingPathComponent("nested")
        let nestedFile = nestedDirectory.appendingPathComponent("note.txt")
        let rootFile = sourceDirectory.appendingPathComponent("root.txt")
        let copiedFile = tempDirectory.appendingPathComponent("copy.txt")
        let copiedDirectory = tempDirectory.appendingPathComponent("copied")

        _ = try fileSystem.createDirectory(ExecServerFsCreateDirectoryParams(
            path: absolutePath(nestedDirectory.path),
            recursive: true
        ))
        _ = try fileSystem.writeFile(ExecServerFsWriteFileParams(
            path: absolutePath(nestedFile.path),
            dataBase64: Data("hello from trait".utf8).base64EncodedString()
        ))
        _ = try fileSystem.writeFile(ExecServerFsWriteFileParams(
            path: absolutePath(rootFile.path),
            dataBase64: Data("hello from source root".utf8).base64EncodedString()
        ))

        let read = try fileSystem.readFile(ExecServerFsReadFileParams(path: absolutePath(nestedFile.path)))
        XCTAssertEqual(Data(base64Encoded: read.dataBase64), Data("hello from trait".utf8))

        _ = try fileSystem.copy(ExecServerFsCopyParams(
            sourcePath: absolutePath(nestedFile.path),
            destinationPath: absolutePath(copiedFile.path),
            recursive: false
        ))
        XCTAssertEqual(try String(contentsOf: copiedFile, encoding: .utf8), "hello from trait")

        _ = try fileSystem.copy(ExecServerFsCopyParams(
            sourcePath: absolutePath(sourceDirectory.path),
            destinationPath: absolutePath(copiedDirectory.path),
            recursive: true
        ))
        XCTAssertEqual(
            try String(contentsOf: copiedDirectory.appendingPathComponent("nested/note.txt"), encoding: .utf8),
            "hello from trait"
        )

        try FileManager.default.createSymbolicLink(
            at: sourceDirectory.appendingPathComponent("broken-link"),
            withDestinationURL: sourceDirectory.appendingPathComponent("missing-target")
        )
        let entries = try fileSystem.readDirectory(ExecServerFsReadDirectoryParams(path: absolutePath(sourceDirectory.path)))
            .entries
            .sorted { $0.fileName < $1.fileName }
        XCTAssertEqual(entries, [
            ExecServerFsReadDirectoryEntry(fileName: "nested", isDirectory: true, isFile: false),
            ExecServerFsReadDirectoryEntry(fileName: "root.txt", isDirectory: false, isFile: true)
        ])

        _ = try fileSystem.remove(ExecServerFsRemoveParams(
            path: absolutePath(copiedDirectory.path),
            recursive: true,
            force: true
        ))
        XCTAssertFalse(FileManager.default.fileExists(atPath: copiedDirectory.path))
    }

    func testFilesystemMetadataAndSymlinkCopyMatchRust() throws {
        let fileSystem = ExecServerFileSystem()
        let tempDirectory = try makeTemporaryDirectory()
        let fileURL = tempDirectory.appendingPathComponent("note.txt")
        let linkURL = tempDirectory.appendingPathComponent("note-link.txt")
        let copiedLinkURL = tempDirectory.appendingPathComponent("copied-link.txt")
        try Data("hello".utf8).write(to: fileURL)
        try FileManager.default.createSymbolicLink(at: linkURL, withDestinationURL: fileURL)

        let fileMetadata = try fileSystem.getMetadata(ExecServerFsGetMetadataParams(path: absolutePath(fileURL.path)))
        let linkMetadata = try fileSystem.getMetadata(ExecServerFsGetMetadataParams(path: absolutePath(linkURL.path)))
        _ = try fileSystem.copy(ExecServerFsCopyParams(
            sourcePath: absolutePath(linkURL.path),
            destinationPath: absolutePath(copiedLinkURL.path),
            recursive: false
        ))

        XCTAssertFalse(fileMetadata.isDirectory)
        XCTAssertTrue(fileMetadata.isFile)
        XCTAssertFalse(fileMetadata.isSymlink)
        XCTAssertGreaterThan(fileMetadata.modifiedAtMs, 0)
        XCTAssertFalse(linkMetadata.isDirectory)
        XCTAssertTrue(linkMetadata.isFile)
        XCTAssertTrue(linkMetadata.isSymlink)
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: copiedLinkURL.path), fileURL.path)
    }

    func testFilesystemRustErrorsAndSandboxDefaults() throws {
        let fileSystem = ExecServerFileSystem()
        let tempDirectory = try makeTemporaryDirectory()
        let sourceDirectory = tempDirectory.appendingPathComponent("source")
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)

        XCTAssertThrowsError(try fileSystem.copy(ExecServerFsCopyParams(
            sourcePath: absolutePath(sourceDirectory.path),
            destinationPath: absolutePath(tempDirectory.appendingPathComponent("dest").path),
            recursive: false
        ))) { error in
            XCTAssertEqual((error as? ExecServerFileSystemError)?.kind, .invalidInput)
            XCTAssertEqual(
                String(describing: error),
                "fs/copy requires recursive: true when sourcePath is a directory"
            )
        }

        XCTAssertThrowsError(try fileSystem.writeFile(ExecServerFsWriteFileParams(
            path: absolutePath(tempDirectory.appendingPathComponent("bad.txt").path),
            dataBase64: "@"
        ))) { error in
            XCTAssertEqual(error as? ExecServerJSONRPCErrorDetail, ExecServerRPC.invalidRequest(
                "fs/writeFile requires valid base64 dataBase64: Invalid byte 64, offset 0."
            ))
        }

        let disabledSandbox = FileSystemSandboxContext(permissions: .disabled)
        let externalSandbox = FileSystemSandboxContext(permissions: .external(network: .restricted))
        for (fileName, sandbox) in [("disabled.txt", disabledSandbox), ("external.txt", externalSandbox)] {
            let path = tempDirectory.appendingPathComponent(fileName)
            _ = try fileSystem.writeFile(ExecServerFsWriteFileParams(
                path: absolutePath(path.path),
                dataBase64: Data("ok".utf8).base64EncodedString(),
                sandbox: sandbox
            ))
            let response = try fileSystem.readFile(ExecServerFsReadFileParams(
                path: absolutePath(path.path),
                sandbox: sandbox
            ))
            XCTAssertEqual(Data(base64Encoded: response.dataBase64), Data("ok".utf8))
        }

        XCTAssertThrowsError(try fileSystem.readFile(ExecServerFsReadFileParams(
            path: absolutePath(tempDirectory.appendingPathComponent("managed.txt").path),
            sandbox: FileSystemSandboxContext(permissions: .readOnly())
        ))) { error in
            XCTAssertEqual((error as? ExecServerFileSystemError)?.kind, .invalidInput)
            XCTAssertEqual(String(describing: error), "sandboxed filesystem operations require configured runtime paths")
        }
    }

    func testConnectionProcessorRoutesFilesystemRequestsLikeRust() async throws {
        let tempDirectory = try makeTemporaryDirectory()
        let noteURL = tempDirectory.appendingPathComponent("note.txt")
        let connection = ExecServerConnection()
        _ = await connection.handle(.message(.request(ExecServerJSONRPCRequest(
            id: .integer(1),
            method: execServerInitializeMethod,
            params: try ExecServerRPC.jsonValue(from: ExecServerInitializeParams(clientName: "client"))
        ))))
        _ = await connection.handle(.message(.notification(ExecServerJSONRPCNotification(
            method: execServerInitializedMethod,
            params: .object([:])
        ))))

        let write = await connection.handle(.message(.request(ExecServerJSONRPCRequest(
            id: .integer(2),
            method: execServerFsWriteFileMethod,
            params: try ExecServerRPC.jsonValue(from: ExecServerFsWriteFileParams(
                path: absolutePath(noteURL.path),
                dataBase64: Data("routed".utf8).base64EncodedString()
            ))
        ))))
        let read = await connection.handle(.message(.request(ExecServerJSONRPCRequest(
            id: .integer(3),
            method: execServerFsReadFileMethod,
            params: try ExecServerRPC.jsonValue(from: ExecServerFsReadFileParams(path: absolutePath(noteURL.path)))
        ))))

        XCTAssertEqual(write?.jsonRPCMessage, ExecServerRPC.response(id: .integer(2), result: .object([:])))
        XCTAssertEqual(read?.jsonRPCMessage, ExecServerRPC.response(
            id: .integer(3),
            result: .object(["dataBase64": .string(Data("routed".utf8).base64EncodedString())])
        ))
    }

    func testConnectionProcessorReportsMalformedMessagesWithRustRequestID() async {
        let connection = ExecServerConnection()

        let response = await connection.handle(.malformedMessage(reason: "bad json"))

        XCTAssertEqual(response, .error(
            requestID: .integer(-1),
            error: ExecServerRPC.invalidRequest("bad json")
        ))
        let closed = await connection.isClosed()
        XCTAssertFalse(closed)
    }

    func testConnectionProcessorClosesOnUnexpectedClientMessagesLikeRust() async {
        let connection = ExecServerConnection()
        let responseMessage = ExecServerJSONRPCMessage.response(ExecServerJSONRPCResponse(
            id: .integer(1),
            result: .object([:])
        ))

        let response = await connection.handle(.message(responseMessage))
        let afterClose = await connection.handle(.malformedMessage(reason: "ignored"))

        XCTAssertNil(response)
        XCTAssertNil(afterClose)
        let closed = await connection.isClosed()
        XCTAssertTrue(closed)
    }

    func testConnectionProcessorClosesOnUnexpectedNotificationsLikeRust() async throws {
        let connection = ExecServerConnection()
        let unexpected = ExecServerJSONRPCNotification(method: "surprise", params: .object([:]))
        let initialize = ExecServerJSONRPCRequest(
            id: .integer(1),
            method: execServerInitializeMethod,
            params: try ExecServerRPC.jsonValue(from: ExecServerInitializeParams(clientName: "client"))
        )

        let response = await connection.handle(.message(.notification(unexpected)))
        let afterClose = await connection.handle(.message(.request(initialize)))

        XCTAssertNil(response)
        XCTAssertNil(afterClose)
        let closed = await connection.isClosed()
        XCTAssertTrue(closed)
    }

    func testConnectionProcessorShutdownDetachesSessionForResumeLikeRust() async throws {
        let processor = ExecServerConnectionProcessor(
            sessionRegistry: ExecServerSessionRegistry(makeID: sequenceIDs(["connection-1", "session-1", "connection-2"]))
        )
        let first = await processor.makeConnection()
        let firstInitialize = ExecServerJSONRPCRequest(
            id: .integer(1),
            method: execServerInitializeMethod,
            params: try ExecServerRPC.jsonValue(from: ExecServerInitializeParams(clientName: "first"))
        )
        let response = await first.handle(.message(.request(firstInitialize)))
        XCTAssertEqual(response?.jsonRPCMessage, ExecServerRPC.response(
            id: .integer(1),
            result: .object(["sessionId": .string("session-1")])
        ))

        _ = await first.handle(.disconnected(reason: nil))
        let second = await processor.makeConnection()
        let secondInitialize = ExecServerJSONRPCRequest(
            id: .integer(2),
            method: execServerInitializeMethod,
            params: try ExecServerRPC.jsonValue(from: ExecServerInitializeParams(
                clientName: "second",
                resumeSessionId: "session-1"
            ))
        )

        let resumed = await second.handle(.message(.request(secondInitialize)))

        XCTAssertEqual(resumed?.jsonRPCMessage, ExecServerRPC.response(
            id: .integer(2),
            result: .object(["sessionId": .string("session-1")])
        ))
    }

    func testConnectionProcessorIgnoresClosedConnectionAfterResumeLikeRust() async throws {
        let processor = ExecServerConnectionProcessor(
            sessionRegistry: ExecServerSessionRegistry(makeID: sequenceIDs(["connection-1", "session-1", "connection-2"]))
        )
        let first = await processor.makeConnection()
        let firstInitialize = ExecServerJSONRPCRequest(
            id: .integer(1),
            method: execServerInitializeMethod,
            params: try ExecServerRPC.jsonValue(from: ExecServerInitializeParams(clientName: "first"))
        )
        _ = await first.handle(.message(.request(firstInitialize)))
        await first.shutdown()
        let second = await processor.makeConnection()
        let secondInitialize = ExecServerJSONRPCRequest(
            id: .integer(2),
            method: execServerInitializeMethod,
            params: try ExecServerRPC.jsonValue(from: ExecServerInitializeParams(
                clientName: "second",
                resumeSessionId: "session-1"
            ))
        )
        _ = await second.handle(.message(.request(secondInitialize)))

        let evictedResponse = await first.handle(.malformedMessage(reason: "ignored"))

        XCTAssertNil(evictedResponse)
        let closed = await first.isClosed()
        XCTAssertTrue(closed)
    }

    func testRouterDispatchesInitializeRequestLikeRust() async throws {
        let router = ExecServerRouter()
        let handler = ExecServerHandler(sessionRegistry: ExecServerSessionRegistry(makeID: sequenceIDs(["connection-1", "session-1"])))
        let request = ExecServerJSONRPCRequest(
            id: .integer(1),
            method: execServerInitializeMethod,
            params: try ExecServerRPC.jsonValue(from: ExecServerInitializeParams(clientName: "client"))
        )

        let outbound = await router.handleRequest(request, using: handler)

        XCTAssertEqual(outbound?.jsonRPCMessage, ExecServerRPC.response(
            id: .integer(1),
            result: .object(["sessionId": .string("session-1")])
        ))
    }

    func testRouterConvertsHandlerFailuresToErrorResponsesLikeRust() async throws {
        let router = ExecServerRouter()
        let handler = ExecServerHandler(sessionRegistry: ExecServerSessionRegistry(makeID: sequenceIDs(["connection-1", "session-1"])))
        let request = ExecServerJSONRPCRequest(
            id: .string("dupe"),
            method: execServerInitializeMethod,
            params: try ExecServerRPC.jsonValue(from: ExecServerInitializeParams(clientName: "client"))
        )

        _ = await router.handleRequest(request, using: handler)
        let duplicate = await router.handleRequest(request, using: handler)

        XCTAssertEqual(duplicate?.jsonRPCMessage, ExecServerRPC.error(
            id: .string("dupe"),
            error: ExecServerRPC.invalidRequest("initialize may only be sent once per connection")
        ))
    }

    func testRouterConvertsInvalidParamsToRustErrorCode() async throws {
        let router = ExecServerRouter()
        let handler = ExecServerHandler()
        let request = ExecServerJSONRPCRequest(
            id: .integer(7),
            method: execServerInitializeMethod,
            params: .object(["resumeSessionId": .string("session-1")])
        )

        let outbound = await router.handleRequest(request, using: handler)

        guard case let .error(requestID, error) = outbound else {
            return XCTFail("Expected invalid params error")
        }
        XCTAssertEqual(requestID, .integer(7))
        XCTAssertEqual(error.code, -32602)
        XCTAssertTrue(error.message.contains("invalid params:"))
        XCTAssertTrue(error.message.contains("clientName"))
    }

    func testRouterDispatchesInitializedNotificationLikeRust() async throws {
        let router = ExecServerRouter()
        let handler = ExecServerHandler(sessionRegistry: ExecServerSessionRegistry(makeID: sequenceIDs(["connection-1", "session-1"])))

        await XCTAssertThrowsHandlerNotificationError(
            try await router.handleNotification(
                ExecServerJSONRPCNotification(method: execServerInitializedMethod, params: .object([:])),
                using: handler
            ),
            message: "received `initialized` notification before `initialize`"
        )
        _ = try await handler.initialize(ExecServerInitializeParams(clientName: "client"))
        try await router.handleNotification(
            ExecServerJSONRPCNotification(method: execServerInitializedMethod, params: .object([:])),
            using: handler
        )
        _ = try await handler.requireInitialized(for: "exec")
    }

    func testRouterUsesRustFamilyInitializationErrorsBeforeExecutionRoutes() async throws {
        let router = ExecServerRouter()
        let handler = ExecServerHandler(sessionRegistry: ExecServerSessionRegistry(makeID: sequenceIDs(["connection-1", "session-1"])))
        let processRead = ExecServerJSONRPCRequest(
            id: .integer(1),
            method: execServerProcessReadMethod,
            params: try ExecServerRPC.jsonValue(from: ExecServerReadParams(processId: "p1"))
        )
        let fsRead = ExecServerJSONRPCRequest(
            id: .integer(2),
            method: execServerFsReadFileMethod,
            params: .object(["path": .string("/tmp/file")])
        )

        let processReadResponse = await router.handleRequest(processRead, using: handler)
        XCTAssertEqual(processReadResponse, .error(
            requestID: .integer(1),
            error: ExecServerRPC.invalidRequest("client must call initialize before using exec methods")
        ))
        _ = try await handler.initialize(ExecServerInitializeParams(clientName: "client"))
        let fsReadResponse = await router.handleRequest(fsRead, using: handler)
        XCTAssertEqual(fsReadResponse, .error(
            requestID: .integer(2),
            error: ExecServerRPC.invalidRequest("client must send initialized before using filesystem methods")
        ))
    }

    func testRouterRoutesBufferedHttpRequestLikeRust() async throws {
        let router = ExecServerRouter()
        let recorder = HTTPRequestRecorder(response: URLSessionTransportResponse(
            statusCode: 201,
            headers: ["x-mcp-test": "buffered"],
            body: Data("response-body".utf8)
        ))
        let handler = ExecServerHandler(
            sessionRegistry: ExecServerSessionRegistry(makeID: sequenceIDs(["connection-1", "session-1"])),
            httpClient: ExecServerHTTPClient { request in
                await recorder.send(request)
            }
        )
        _ = try await handler.initialize(ExecServerInitializeParams(clientName: "client"))
        try await handler.markInitialized()

        let outbound = await router.handleRequest(ExecServerJSONRPCRequest(
            id: .integer(1),
            method: execServerHttpRequestMethod,
            params: try ExecServerRPC.jsonValue(from: ExecServerHttpRequestParams(
                method: "POST",
                url: "https://example.test/mcp?case=buffered",
                headers: [ExecServerHttpHeader(name: "x-codex-test", value: "buffered")],
                body: ExecServerByteChunk(Array("request-body".utf8)),
                timeoutMs: 5_000,
                requestId: "buffered-request"
            ))
        ), using: handler)

        guard case let .response(.integer(1), result) = outbound else {
            return XCTFail("Expected buffered http/request response")
        }
        XCTAssertEqual(try decodeJSONValue(result, as: ExecServerHttpRequestResponse.self), ExecServerHttpRequestResponse(
            status: 201,
            headers: [ExecServerHttpHeader(name: "x-mcp-test", value: "buffered")],
            body: ExecServerByteChunk(Array("response-body".utf8))
        ))

        let recordedRequest = await recorder.firstRequest()
        let request = try XCTUnwrap(recordedRequest)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.absoluteString, "https://example.test/mcp?case=buffered")
        XCTAssertEqual(request.allHTTPHeaderFields?["x-codex-test"], "buffered")
        XCTAssertEqual(request.httpBody, Data("request-body".utf8))
        XCTAssertEqual(request.timeoutInterval, 5.0, accuracy: 0.001)
    }

    func testRouterRoutesStreamingHttpResponseHeadersLikeRust() async throws {
        let router = ExecServerRouter()
        let handler = ExecServerHandler(
            sessionRegistry: ExecServerSessionRegistry(makeID: sequenceIDs(["connection-1", "session-1"])),
            httpClient: ExecServerHTTPClient(
                send: { _ in URLSessionTransportResponse(statusCode: 500) },
                stream: { _ in
                    APIStreamResponse(
                        statusCode: 200,
                        headers: ["content-type": "text/event-stream"],
                        byteStream: APIByteStream { continuation in
                            continuation.yield(.success(Data("hello".utf8)))
                            continuation.finish()
                        }
                    )
                }
            )
        )
        _ = try await handler.initialize(ExecServerInitializeParams(clientName: "client"))
        try await handler.markInitialized()

        let streaming = await router.handleRequest(ExecServerJSONRPCRequest(
            id: .integer(1),
            method: execServerHttpRequestMethod,
            params: try ExecServerRPC.jsonValue(from: ExecServerHttpRequestParams(
                method: "GET",
                url: "https://example.test",
                requestId: "request-1",
                streamResponse: true
            ))
        ), using: handler)

        guard case let .response(.integer(1), result) = streaming else {
            return XCTFail("Expected streaming http/request header response")
        }
        XCTAssertEqual(try decodeJSONValue(result, as: ExecServerHttpRequestResponse.self), ExecServerHttpRequestResponse(
            status: 200,
            headers: [ExecServerHttpHeader(name: "content-type", value: "text/event-stream")],
            body: ExecServerByteChunk([])
        ))
    }

    func testRouterReportsUnknownMethodsWithRustStubMessage() async throws {
        let router = ExecServerRouter()
        let handler = ExecServerHandler(sessionRegistry: ExecServerSessionRegistry(makeID: sequenceIDs(["connection-1", "session-1"])))
        _ = try await handler.initialize(ExecServerInitializeParams(clientName: "client"))
        try await handler.markInitialized()

        let unknown = await router.handleRequest(ExecServerJSONRPCRequest(
            id: .integer(2),
            method: "made/up",
            params: .object([:])
        ), using: handler)

        XCTAssertEqual(unknown, .error(
            requestID: .integer(2),
            error: ExecServerRPC.methodNotFound("exec-server stub does not implement `made/up` yet")
        ))
    }

    func testConnectionStreamsHttpBodyDeltaNotificationsLikeRust() async throws {
        let connection = try await initializedConnection(httpClient: ExecServerHTTPClient(
            send: { _ in URLSessionTransportResponse(statusCode: 500) },
            stream: { _ in
                APIStreamResponse(
                    statusCode: 200,
                    headers: ["x-mcp-test": "streaming"],
                    byteStream: APIByteStream { continuation in
                        continuation.yield(.success(Data("hello ".utf8)))
                        continuation.yield(.success(Data("world".utf8)))
                        continuation.finish()
                    }
                )
            }
        ))

        let response = await connection.handle(.message(.request(ExecServerJSONRPCRequest(
            id: .integer(42),
            method: execServerHttpRequestMethod,
            params: try ExecServerRPC.jsonValue(from: ExecServerHttpRequestParams(
                method: "GET",
                url: "https://example.test/mcp?case=streaming",
                headers: [ExecServerHttpHeader(name: "accept", value: "text/event-stream")],
                requestId: "stream-1",
                streamResponse: true
            ))
        ))))
        guard case let .response(.integer(42), result) = response else {
            return XCTFail("Expected streaming http/request response before body deltas")
        }
        XCTAssertEqual(try decodeJSONValue(result, as: ExecServerHttpRequestResponse.self), ExecServerHttpRequestResponse(
            status: 200,
            headers: [ExecServerHttpHeader(name: "x-mcp-test", value: "streaming")],
            body: ExecServerByteChunk([])
        ))

        let deltas = try await collectHTTPBodyDeltas(from: connection, requestId: "stream-1")
        XCTAssertEqual(deltas.map(\.seq), [1, 2, 3])
        XCTAssertEqual(
            deltas.flatMap { $0.delta.bytes },
            Array("hello world".utf8)
        )
        XCTAssertEqual(deltas.last?.done, true)
        XCTAssertNil(deltas.last?.error)
    }

    func testStreamingHttpRejectsDuplicateRequestIDWhileActiveLikeRust() async throws {
        let gate = HTTPStreamGate()
        let handler = ExecServerHandler(
            sessionRegistry: ExecServerSessionRegistry(makeID: sequenceIDs(["connection-1", "session-1"])),
            httpClient: ExecServerHTTPClient(
                send: { _ in URLSessionTransportResponse(statusCode: 500) },
                stream: { _ in
                    APIStreamResponse(
                        statusCode: 200,
                        byteStream: APIByteStream { continuation in
                            continuation.yield(.success(Data("hello".utf8)))
                            Task {
                                await gate.store(continuation)
                            }
                        }
                    )
                }
            )
        )
        let router = ExecServerRouter()
        _ = try await handler.initialize(ExecServerInitializeParams(clientName: "client"))
        try await handler.markInitialized()

        _ = await router.handleRequest(ExecServerJSONRPCRequest(
            id: .integer(1),
            method: execServerHttpRequestMethod,
            params: try ExecServerRPC.jsonValue(from: ExecServerHttpRequestParams(
                method: "GET",
                url: "https://example.test/mcp",
                requestId: "stream-dup",
                streamResponse: true
            ))
        ), using: handler)
        let duplicate = await router.handleRequest(ExecServerJSONRPCRequest(
            id: .integer(2),
            method: execServerHttpRequestMethod,
            params: try ExecServerRPC.jsonValue(from: ExecServerHttpRequestParams(
                method: "GET",
                url: "https://example.test/mcp",
                requestId: "stream-dup",
                streamResponse: true
            ))
        ), using: handler)

        XCTAssertEqual(duplicate, .error(
            requestID: .integer(2),
            error: ExecServerRPC.invalidParams("http/request streamResponse requestId `stream-dup` is already active")
        ))
        await gate.finish()
        await handler.shutdown()
    }

    func testHttpRequestRejectsInvalidMethodAndSchemeLikeRust() async throws {
        let client = ExecServerHTTPClient { _ in
            XCTFail("Invalid http/request params should fail before transport")
            return URLSessionTransportResponse(statusCode: 200)
        }

        await XCTAssertThrowsExecServerError(
            try await client.run(ExecServerHttpRequestParams(
                method: "GET POST",
                url: "https://example.test",
                requestId: "bad-method"
            )),
            code: -32602,
            message: "http/request method is invalid: invalid HTTP method"
        )
        await XCTAssertThrowsExecServerError(
            try await client.run(ExecServerHttpRequestParams(
                method: "GET",
                url: "file:///tmp/not-http",
                requestId: "bad-scheme"
            )),
            code: -32602,
            message: "http/request only supports http and https URLs, got file"
        )
    }

    func testRouterRejectsUnexpectedNotificationsLikeRustProcessor() async {
        let router = ExecServerRouter()
        let handler = ExecServerHandler()

        await XCTAssertThrowsRouterNotificationError(
            try await router.handleNotification(
                ExecServerJSONRPCNotification(method: "surprise", params: .object([:])),
                using: handler
            ),
            message: "unexpected exec-server notification: surprise"
        )
    }

    func testHandlerInitializeAttachesSessionAndRejectsDuplicateLikeRust() async throws {
        let registry = ExecServerSessionRegistry(makeID: sequenceIDs(["connection-1", "session-1"]))
        let handler = ExecServerHandler(sessionRegistry: registry)

        let response = try await handler.initialize(ExecServerInitializeParams(clientName: "client"))

        XCTAssertEqual(response.sessionId, "session-1")
        let isAttached = await handler.isSessionAttached()
        XCTAssertTrue(isAttached)
        await XCTAssertThrowsExecServerError(
            try await handler.initialize(ExecServerInitializeParams(clientName: "client")),
            code: -32600,
            message: "initialize may only be sent once per connection"
        )
    }

    func testHandlerInitializeFailureAllowsRetryLikeRust() async throws {
        let registry = ExecServerSessionRegistry(makeID: sequenceIDs(["connection-1", "connection-2", "session-1"]))
        let handler = ExecServerHandler(sessionRegistry: registry)

        await XCTAssertThrowsExecServerError(
            try await handler.initialize(ExecServerInitializeParams(clientName: "client", resumeSessionId: "missing")),
            code: -32600,
            message: "unknown session id missing"
        )

        let response = try await handler.initialize(ExecServerInitializeParams(clientName: "client"))
        XCTAssertEqual(response.sessionId, "session-1")
    }

    func testHandlerInitializedNotificationOrderingMatchesRust() async throws {
        let registry = ExecServerSessionRegistry(makeID: sequenceIDs(["connection-1", "session-1"]))
        let handler = ExecServerHandler(sessionRegistry: registry)

        await XCTAssertThrowsHandlerNotificationError(
            try await handler.markInitialized(),
            message: "received `initialized` notification before `initialize`"
        )
        _ = try await handler.initialize(ExecServerInitializeParams(clientName: "client"))
        try await handler.markInitialized()
    }

    func testHandlerRequireInitializedForMethodFamiliesMatchesRust() async throws {
        let registry = ExecServerSessionRegistry(makeID: sequenceIDs(["connection-1", "session-1"]))
        let handler = ExecServerHandler(sessionRegistry: registry)

        await XCTAssertThrowsExecServerError(
            try await handler.requireInitialized(for: "exec"),
            code: -32600,
            message: "client must call initialize before using exec methods"
        )
        _ = try await handler.initialize(ExecServerInitializeParams(clientName: "client"))
        await XCTAssertThrowsExecServerError(
            try await handler.requireInitialized(for: "filesystem"),
            code: -32600,
            message: "client must send initialized before using filesystem methods"
        )
        try await handler.markInitialized()

        let session = try await handler.requireInitialized(for: "http")
        XCTAssertEqual(session.sessionID, "session-1")
    }

    func testHandlerReportsResumedSessionLikeRust() async throws {
        let registry = ExecServerSessionRegistry(makeID: sequenceIDs(["connection-1", "session-1", "connection-2"]))
        let first = ExecServerHandler(sessionRegistry: registry)
        let second = ExecServerHandler(sessionRegistry: registry)
        let response = try await first.initialize(ExecServerInitializeParams(clientName: "first"))
        try await first.markInitialized()
        await first.shutdown()

        _ = try await second.initialize(ExecServerInitializeParams(clientName: "second", resumeSessionId: response.sessionId))

        let firstIsAttached = await first.isSessionAttached()
        XCTAssertFalse(firstIsAttached)
        await XCTAssertThrowsExecServerError(
            try await first.requireInitialized(for: "exec"),
            code: -32600,
            message: "session has been resumed by another connection"
        )
    }

    func testHandlerShutdownDetachesSessionForResume() async throws {
        let registry = ExecServerSessionRegistry(makeID: sequenceIDs(["connection-1", "session-1", "connection-2"]))
        let first = ExecServerHandler(sessionRegistry: registry)
        let response = try await first.initialize(ExecServerInitializeParams(clientName: "first"))

        await first.shutdown()
        let second = try await registry.attach(resumeSessionID: response.sessionId)

        XCTAssertEqual(second.sessionID, "session-1")
        let firstIsAttached = await first.isSessionAttached()
        let secondIsAttached = await second.isSessionAttached()
        XCTAssertFalse(firstIsAttached)
        XCTAssertTrue(secondIsAttached)
    }

    func testSessionRegistryCreatesNewSessionsWithActiveConnection() async throws {
        let registry = ExecServerSessionRegistry(makeID: sequenceIDs(["connection-1", "session-1"]))

        let handle = try await registry.attach()

        XCTAssertEqual(handle.sessionID, "session-1")
        XCTAssertEqual(handle.connectionID, "connection-1")
        let isAttached = await handle.isSessionAttached()
        let registryContainsSession = await registry.contains(sessionID: "session-1")
        XCTAssertTrue(isAttached)
        XCTAssertTrue(registryContainsSession)
    }

    func testSessionRegistryRejectsUnknownAndActiveResumeLikeRust() async throws {
        let registry = ExecServerSessionRegistry(makeID: sequenceIDs(["connection-1", "session-1", "connection-2"]))
        let handle = try await registry.attach()

        await XCTAssertThrowsExecServerError(
            try await registry.attach(resumeSessionID: "missing"),
            code: -32600,
            message: "unknown session id missing"
        )
        await XCTAssertThrowsExecServerError(
            try await registry.attach(resumeSessionID: handle.sessionID),
            code: -32600,
            message: "session session-1 is already attached to another connection"
        )
    }

    func testSessionRegistryDetachedSessionCanResumeAndEvictsOldConnection() async throws {
        let registry = ExecServerSessionRegistry(makeID: sequenceIDs(["connection-1", "session-1", "connection-2"]))
        let first = try await registry.attach()

        await first.detach()
        let second = try await registry.attach(resumeSessionID: first.sessionID)

        XCTAssertEqual(second.sessionID, "session-1")
        XCTAssertEqual(second.connectionID, "connection-2")
        let firstIsAttached = await first.isSessionAttached()
        let secondIsAttached = await second.isSessionAttached()
        XCTAssertFalse(firstIsAttached)
        XCTAssertTrue(secondIsAttached)
    }

    func testSessionRegistryExpiredDetachedSessionLooksUnknownLikeRust() async throws {
        let registry = ExecServerSessionRegistry(
            detachedSessionTTL: -1,
            makeID: sequenceIDs(["connection-1", "session-1", "connection-2"])
        )
        let handle = try await registry.attach()

        await handle.detach()

        await XCTAssertThrowsExecServerError(
            try await registry.attach(resumeSessionID: handle.sessionID),
            code: -32600,
            message: "unknown session id session-1"
        )
        let registryContainsSession = await registry.contains(sessionID: "session-1")
        XCTAssertFalse(registryContainsSession)
    }

    func testSessionRegistryOldDetachCannotDetachResumedSession() async throws {
        let registry = ExecServerSessionRegistry(makeID: sequenceIDs(["connection-1", "session-1", "connection-2"]))
        let first = try await registry.attach()
        await first.detach()
        let second = try await registry.attach(resumeSessionID: first.sessionID)

        await first.detach()

        let firstIsAttached = await first.isSessionAttached()
        let secondIsAttached = await second.isSessionAttached()
        XCTAssertFalse(firstIsAttached)
        XCTAssertTrue(secondIsAttached)
    }

    func testJSONRPCMessagesUseRustShapeWithoutJsonrpcField() throws {
        try XCTAssertJSONObjectEqual(ExecServerJSONRPCMessage.request(ExecServerJSONRPCRequest(
            id: .integer(1),
            method: execServerInitializeMethod,
            params: try ExecServerRPC.jsonValue(from: ExecServerInitializeParams(clientName: "client"))
        )), [
            "id": 1,
            "method": "initialize",
            "params": [
                "clientName": "client"
            ]
        ])

        try XCTAssertJSONObjectEqual(ExecServerRPC.response(
            id: .string("req-1"),
            result: .object(["sessionId": .string("session-1")])
        ), [
            "id": "req-1",
            "result": [
                "sessionId": "session-1"
            ]
        ])

        try XCTAssertJSONObjectEqual(ExecServerRPC.notification(
            method: execServerInitializedMethod,
            params: .object([:])
        ), [
            "method": "initialized",
            "params": [:]
        ])
    }

    func testJSONRPCMessageDecodingDistinguishesMessageKinds() throws {
        let decoder = JSONDecoder()

        XCTAssertEqual(
            try decoder.decode(ExecServerJSONRPCMessage.self, from: Data(#"{"id":1,"method":"process/read","params":{"processId":"p1"}}"#.utf8)),
            .request(ExecServerJSONRPCRequest(
                id: .integer(1),
                method: execServerProcessReadMethod,
                params: .object(["processId": .string("p1")])
            ))
        )
        XCTAssertEqual(
            try decoder.decode(ExecServerJSONRPCMessage.self, from: Data(#"{"method":"initialized","params":{}}"#.utf8)),
            .notification(ExecServerJSONRPCNotification(method: execServerInitializedMethod, params: .object([:])))
        )
        XCTAssertEqual(
            try decoder.decode(ExecServerJSONRPCMessage.self, from: Data(#"{"id":"a","result":{"ok":true}}"#.utf8)),
            .response(ExecServerJSONRPCResponse(id: .string("a"), result: .object(["ok": .bool(true)])))
        )
        XCTAssertEqual(
            try decoder.decode(ExecServerJSONRPCMessage.self, from: Data(#"{"id":-1,"error":{"code":-32600,"message":"bad"}}"#.utf8)),
            .error(ExecServerJSONRPCError(id: .integer(-1), error: ExecServerRPC.invalidRequest("bad")))
        )
    }

    func testJSONRPCErrorCodesMatchRustHelpers() {
        XCTAssertEqual(ExecServerRPC.invalidRequest("bad"), ExecServerJSONRPCErrorDetail(code: -32600, message: "bad"))
        XCTAssertEqual(ExecServerRPC.methodNotFound("missing"), ExecServerJSONRPCErrorDetail(code: -32601, message: "missing"))
        XCTAssertEqual(ExecServerRPC.invalidParams("params"), ExecServerJSONRPCErrorDetail(code: -32602, message: "params"))
        XCTAssertEqual(ExecServerRPC.notFound("gone"), ExecServerJSONRPCErrorDetail(code: -32004, message: "gone"))
        XCTAssertEqual(ExecServerRPC.internalError("boom"), ExecServerJSONRPCErrorDetail(code: -32603, message: "boom"))
    }

    func testRequestParamDecodingRetriesEmptyObjectAsNullLikeRust() throws {
        struct NullParams: Decodable, Equatable {
            init() {}

            init(from decoder: Decoder) throws {
                let container = try decoder.singleValueContainer()
                guard container.decodeNil() else {
                    throw DecodingError.dataCorruptedError(
                        in: container,
                        debugDescription: "expected null"
                    )
                }
            }
        }

        XCTAssertEqual(
            try ExecServerRPC.decodeRequestParams(.object([:]), as: NullParams.self),
            NullParams()
        )
        XCTAssertEqual(
            try ExecServerRPC.decodeNotificationParams(nil, as: NullParams.self),
            NullParams()
        )
        XCTAssertThrowsError(try ExecServerRPC.decodeRequestParams(
            .object(["unexpected": .bool(true)]),
            as: NullParams.self
        )) { error in
            XCTAssertTrue(String(describing: error).contains("invalid params:"))
        }
    }

    private func sequenceIDs(_ ids: [String]) -> @Sendable () -> String {
        final class Box: @unchecked Sendable {
            var ids: [String]
            init(_ ids: [String]) {
                self.ids = ids
            }
        }
        let box = Box(ids)
        return {
            if box.ids.isEmpty {
                return "unexpected-id"
            }
            return box.ids.removeFirst()
        }
    }

    private func XCTAssertThrowsExecServerError(
        _ expression: @autoclosure () async throws -> some Any,
        code: Int,
        message: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await expression()
            XCTFail("Expected exec-server JSON-RPC error", file: file, line: line)
        } catch let error as ExecServerJSONRPCErrorDetail {
            XCTAssertEqual(error.code, code, file: file, line: line)
            XCTAssertEqual(error.message, message, file: file, line: line)
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
    }

    private func XCTAssertThrowsHandlerNotificationError(
        _ expression: @autoclosure () async throws -> some Any,
        message: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await expression()
            XCTFail("Expected exec-server handler notification error", file: file, line: line)
        } catch let error as ExecServerHandlerNotificationError {
            XCTAssertEqual(error.message, message, file: file, line: line)
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
    }

    private func XCTAssertThrowsRouterNotificationError(
        _ expression: @autoclosure () async throws -> some Any,
        message: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await expression()
            XCTFail("Expected exec-server router notification error", file: file, line: line)
        } catch let error as ExecServerRouterNotificationError {
            XCTAssertEqual(error.message, message, file: file, line: line)
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
    }

    func testProtocolMethodConstantsMatchRust() {
        XCTAssertEqual(execServerInitializeMethod, "initialize")
        XCTAssertEqual(execServerInitializedMethod, "initialized")
        XCTAssertEqual(execServerProcessStartMethod, "process/start")
        XCTAssertEqual(execServerProcessReadMethod, "process/read")
        XCTAssertEqual(execServerProcessWriteMethod, "process/write")
        XCTAssertEqual(execServerProcessTerminateMethod, "process/terminate")
        XCTAssertEqual(execServerProcessOutputDeltaMethod, "process/output")
        XCTAssertEqual(execServerProcessExitedMethod, "process/exited")
        XCTAssertEqual(execServerProcessClosedMethod, "process/closed")
        XCTAssertEqual(execServerFsReadFileMethod, "fs/readFile")
        XCTAssertEqual(execServerFsWriteFileMethod, "fs/writeFile")
        XCTAssertEqual(execServerFsCreateDirectoryMethod, "fs/createDirectory")
        XCTAssertEqual(execServerFsGetMetadataMethod, "fs/getMetadata")
        XCTAssertEqual(execServerFsReadDirectoryMethod, "fs/readDirectory")
        XCTAssertEqual(execServerFsRemoveMethod, "fs/remove")
        XCTAssertEqual(execServerFsCopyMethod, "fs/copy")
        XCTAssertEqual(execServerHttpRequestMethod, "http/request")
        XCTAssertEqual(execServerHttpRequestBodyDeltaMethod, "http/request/bodyDelta")
    }

    func testByteChunkUsesTransparentBase64StringLikeRust() throws {
        let chunk = ExecServerByteChunk(Array("hello".utf8))

        let data = try JSONEncoder().encode(chunk)
        XCTAssertEqual(String(data: data, encoding: .utf8), "\"aGVsbG8=\"")
        XCTAssertEqual(try JSONDecoder().decode(ExecServerByteChunk.self, from: data), chunk)
    }

    func testProcessProtocolWireShapesMatchRustCamelCase() throws {
        let params = ExecServerExecParams(
            processId: "proc-1",
            argv: ["zsh", "-lc", "echo hi"],
            cwd: "/repo",
            envPolicy: ExecServerExecEnvPolicy(
                inherit: .core,
                ignoreDefaultExcludes: false,
                exclude: ["SECRET_*"],
                set: ["FOO": "bar"],
                includeOnly: ["PATH"]
            ),
            env: ["TERM": "xterm-256color"],
            tty: true,
            pipeStdin: true,
            arg0: "codex"
        )

        try XCTAssertJSONObjectEqual(params, [
            "processId": "proc-1",
            "argv": ["zsh", "-lc", "echo hi"],
            "cwd": "/repo",
            "envPolicy": [
                "inherit": "core",
                "ignoreDefaultExcludes": false,
                "exclude": ["SECRET_*"],
                "set": ["FOO": "bar"],
                "includeOnly": ["PATH"]
            ],
            "env": ["TERM": "xterm-256color"],
            "tty": true,
            "pipeStdin": true,
            "arg0": "codex"
        ])

        let defaulted = try JSONDecoder().decode(ExecServerExecParams.self, from: Data(#"""
        {
          "processId": "proc-2",
          "argv": ["pwd"],
          "cwd": "/repo",
          "env": {},
          "tty": false
        }
        """#.utf8))
        XCTAssertEqual(defaulted.pipeStdin, false)
        XCTAssertNil(defaulted.envPolicy)
        XCTAssertNil(defaulted.arg0)
    }

    func testReadAndNotificationWireShapesCarryBase64Chunks() throws {
        let readResponse = ExecServerReadResponse(
            chunks: [
                ExecServerProcessOutputChunk(
                    seq: 7,
                    stream: .stdout,
                    chunk: ExecServerByteChunk(Array("hi\n".utf8))
                )
            ],
            nextSeq: 8,
            exited: true,
            exitCode: 0,
            closed: false
        )

        try XCTAssertJSONObjectEqual(readResponse, [
            "chunks": [
                [
                    "seq": 7,
                    "stream": "stdout",
                    "chunk": "aGkK"
                ]
            ],
            "nextSeq": 8,
            "exited": true,
            "exitCode": 0,
            "closed": false
        ])

        try XCTAssertJSONObjectEqual(ExecServerOutputDeltaNotification(
            processId: "proc-1",
            seq: 9,
            stream: .pty,
            chunk: ExecServerByteChunk(Array(">".utf8))
        ), [
            "processId": "proc-1",
            "seq": 9,
            "stream": "pty",
            "chunk": "Pg=="
        ])
    }

    func testFilesystemProtocolWireShapesIncludeSandboxContext() throws {
        let sandbox = FileSystemSandboxContext(
            permissions: .readOnly(),
            cwd: try AbsolutePath(absolutePath: "/repo"),
            windowsSandboxLevel: .restrictedToken,
            windowsSandboxPrivateDesktop: true,
            useLegacyLandlock: false
        )
        let params = ExecServerFsCopyParams(
            sourcePath: try AbsolutePath(absolutePath: "/repo/a.txt"),
            destinationPath: try AbsolutePath(absolutePath: "/repo/b.txt"),
            recursive: false,
            sandbox: sandbox
        )

        try XCTAssertJSONObjectEqual(params, [
            "sourcePath": "/repo/a.txt",
            "destinationPath": "/repo/b.txt",
            "recursive": false,
            "sandbox": [
                "permissions": [
                    "type": "managed",
                    "file_system": [
                        "type": "restricted",
                        "entries": [
                            [
                                "path": [
                                    "type": "special",
                                    "value": ["kind": "root"]
                                ],
                                "access": "read"
                            ]
                        ]
                    ],
                    "network": "restricted"
                ],
                "cwd": "/repo",
                "windowsSandboxLevel": "restricted-token",
                "windowsSandboxPrivateDesktop": true,
                "useLegacyLandlock": false
            ]
        ])

        let decoded = try JSONDecoder().decode(FileSystemSandboxContext.self, from: Data(#"""
        {
          "permissions": { "type": "disabled" },
          "windowsSandboxLevel": "disabled"
        }
        """#.utf8))
        XCTAssertEqual(decoded.windowsSandboxPrivateDesktop, false)
        XCTAssertEqual(decoded.useLegacyLandlock, false)
    }

    func testHttpRequestDefaultsAndTimeoutNullMatchRust() throws {
        let omitted = try JSONDecoder().decode(ExecServerHttpRequestParams.self, from: Data(#"""
        {
          "method": "GET",
          "url": "https://example.test",
          "requestId": "req-omitted-timeout"
        }
        """#.utf8))
        let nullTimeout = try JSONDecoder().decode(ExecServerHttpRequestParams.self, from: Data(#"""
        {
          "method": "GET",
          "url": "https://example.test",
          "requestId": "req-null-timeout",
          "timeoutMs": null
        }
        """#.utf8))
        let explicitTimeout = try JSONDecoder().decode(ExecServerHttpRequestParams.self, from: Data(#"""
        {
          "method": "POST",
          "url": "https://example.test",
          "requestId": "req-explicit-timeout",
          "headers": [{ "name": "x-test", "value": "1" }],
          "bodyBase64": "aGVsbG8=",
          "timeoutMs": 1234,
          "streamResponse": true
        }
        """#.utf8))

        XCTAssertEqual(omitted.requestId, "req-omitted-timeout")
        XCTAssertNil(omitted.timeoutMs)
        XCTAssertEqual(omitted.headers, [])
        XCTAssertNil(omitted.body)
        XCTAssertFalse(omitted.streamResponse)
        XCTAssertEqual(nullTimeout.requestId, "req-null-timeout")
        XCTAssertNil(nullTimeout.timeoutMs)
        XCTAssertEqual(explicitTimeout.timeoutMs, 1234)
        XCTAssertEqual(explicitTimeout.body, ExecServerByteChunk(Array("hello".utf8)))

        try XCTAssertJSONObjectEqual(ExecServerHttpRequestParams(
            method: "POST",
            url: "https://example.test",
            headers: [ExecServerHttpHeader(name: "x-test", value: "1")],
            body: ExecServerByteChunk(Array("hello".utf8)),
            timeoutMs: 1234,
            requestId: "req-explicit-timeout",
            streamResponse: true
        ), [
            "method": "POST",
            "url": "https://example.test",
            "headers": [["name": "x-test", "value": "1"]],
            "bodyBase64": "aGVsbG8=",
            "timeoutMs": 1234,
            "requestId": "req-explicit-timeout",
            "streamResponse": true
        ])
    }

    func testHttpBodyDeltaDefaultsMatchRust() throws {
        let decoded = try JSONDecoder().decode(ExecServerHttpRequestBodyDeltaNotification.self, from: Data(#"""
        {
          "requestId": "req-1",
          "seq": 1,
          "deltaBase64": "aGk="
        }
        """#.utf8))

        XCTAssertEqual(decoded, ExecServerHttpRequestBodyDeltaNotification(
            requestId: "req-1",
            seq: 1,
            delta: ExecServerByteChunk(Array("hi".utf8))
        ))
        XCTAssertFalse(decoded.done)
        XCTAssertNil(decoded.error)
    }

    func testListenURLParserAcceptsRustSupportedForms() throws {
        XCTAssertEqual(try ExecServerListenURLParser.parse("stdio"), .stdio)
        XCTAssertEqual(try ExecServerListenURLParser.parse("stdio://"), .stdio)
        XCTAssertEqual(
            try ExecServerListenURLParser.parse("ws://127.0.0.1:0"),
            .webSocket(host: "127.0.0.1", port: 0)
        )
        XCTAssertEqual(
            try ExecServerListenURLParser.parse("ws://[::1]:4500"),
            .webSocket(host: "::1", port: 4500)
        )
    }

    func testListenURLParserRejectsRustInvalidForms() {
        XCTAssertThrowsError(try ExecServerListenURLParser.parse("http://127.0.0.1:4500")) { error in
            XCTAssertEqual(
                error as? ExecServerListenURLParseError,
                .unsupportedListenURL("http://127.0.0.1:4500")
            )
            XCTAssertEqual(
                String(describing: error),
                "unsupported --listen URL `http://127.0.0.1:4500`; expected `ws://IP:PORT` or `stdio`"
            )
        }

        for listenURL in ["ws://127.0.0.1", "ws://localhost:4500", "ws://127.0.0.1:4500/path"] {
            XCTAssertThrowsError(try ExecServerListenURLParser.parse(listenURL)) { error in
                XCTAssertEqual(error as? ExecServerListenURLParseError, .invalidWebSocketListenURL(listenURL))
                XCTAssertEqual(
                    String(describing: error),
                    "invalid websocket --listen URL `\(listenURL)`; expected `ws://IP:PORT`"
                )
            }
        }
    }

    func testRemoteExecutorConfigurationNormalizesRustValues() throws {
        let config = try ExecServerRemoteExecutorConfiguration.fromEnvironment(
            baseURL: " https://registry.example.test/// ",
            executorID: " exec-123 ",
            name: nil,
            environment: [codexExecServerRemoteBearerTokenEnvironmentVariable: " token "]
        )

        XCTAssertEqual(config.baseURL, "https://registry.example.test")
        XCTAssertEqual(config.executorID, "exec-123")
        XCTAssertEqual(config.name, "codex-exec-server")
        XCTAssertEqual(config.bearerToken, "token")
    }

    func testRemoteExecutorConfigurationErrorsMatchRustMessages() {
        XCTAssertThrowsError(try ExecServerRemoteExecutorConfiguration.fromEnvironment(
            baseURL: "https://registry.example.test",
            executorID: "exec-123",
            environment: [:]
        )) { error in
            XCTAssertEqual(
                String(describing: error),
                "executor registry authentication error: executor registry bearer token environment variable `CODEX_EXEC_SERVER_REMOTE_BEARER_TOKEN` is not set"
            )
        }

        XCTAssertThrowsError(try ExecServerRemoteExecutorConfiguration(
            baseURL: "https://registry.example.test",
            executorID: " ",
            bearerToken: "token"
        )) { error in
            XCTAssertEqual(
                String(describing: error),
                "executor registry configuration error: executor id is required for remote exec-server registration"
            )
        }

        XCTAssertThrowsError(try ExecServerRemoteExecutorConfiguration(
            baseURL: " ",
            executorID: "exec-123",
            bearerToken: "token"
        )) { error in
            XCTAssertEqual(
                String(describing: error),
                "executor registry configuration error: executor registry base URL is required"
            )
        }

        XCTAssertThrowsError(try ExecServerRemoteExecutorConfiguration(
            baseURL: "https://registry.example.test",
            executorID: "exec-123",
            bearerToken: " "
        )) { error in
            XCTAssertEqual(
                String(describing: error),
                "executor registry authentication error: executor registry bearer token environment variable `CODEX_EXEC_SERVER_REMOTE_BEARER_TOKEN` is empty"
            )
        }
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-swift-exec-fs-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func absolutePath(_ path: String) throws -> AbsolutePath {
        try AbsolutePath(absolutePath: path)
    }

    private func initializedConnection(
        httpClient: ExecServerHTTPClient = ExecServerHTTPClient()
    ) async throws -> ExecServerConnection {
        let connection = ExecServerConnection(httpClient: httpClient)
        _ = await connection.handle(.message(.request(ExecServerJSONRPCRequest(
            id: .integer(1),
            method: execServerInitializeMethod,
            params: try ExecServerRPC.jsonValue(from: ExecServerInitializeParams(clientName: "client"))
        ))))
        _ = await connection.handle(.message(.notification(ExecServerJSONRPCNotification(
            method: execServerInitializedMethod,
            params: .object([:])
        ))))
        return connection
    }

    private func collectHTTPBodyDeltas(
        from connection: ExecServerConnection,
        requestId: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws -> [ExecServerHttpRequestBodyDeltaNotification] {
        var deltas: [ExecServerHttpRequestBodyDeltaNotification] = []
        for _ in 0..<20 {
            guard let outbound = try await nextOutbound(from: connection, file: file, line: line) else {
                continue
            }
            guard case let .notification(notification) = outbound else {
                XCTFail("Expected http/request body delta notification", file: file, line: line)
                continue
            }
            XCTAssertEqual(notification.method, execServerHttpRequestBodyDeltaMethod, file: file, line: line)
            let params = try XCTUnwrap(notification.params, file: file, line: line)
            let delta = try decodeJSONValue(params, as: ExecServerHttpRequestBodyDeltaNotification.self)
            XCTAssertEqual(delta.requestId, requestId, file: file, line: line)
            deltas.append(delta)
            if delta.done {
                return deltas
            }
        }
        XCTFail("Timed out waiting for terminal http/request body delta", file: file, line: line)
        return deltas
    }

    private func nextOutbound(
        from connection: ExecServerConnection,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws -> ExecServerOutboundMessage? {
        for _ in 0..<50 {
            if let message = await connection.nextOutbound() {
                return message
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Timed out waiting for outbound exec-server message", file: file, line: line)
        return nil
    }

    private func collectHTTPBodyDeltaLines(
        from server: ExecServerLineServer,
        requestId: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws -> [ExecServerHttpRequestBodyDeltaNotification] {
        var deltas: [ExecServerHttpRequestBodyDeltaNotification] = []
        for _ in 0..<50 {
            for rawLine in try await server.drainQueuedLines() {
                guard case let .notification(notification) = try decodeLine(rawLine) else {
                    XCTFail("Expected http/request body delta notification", file: file, line: line)
                    continue
                }
                XCTAssertEqual(notification.method, execServerHttpRequestBodyDeltaMethod, file: file, line: line)
                let params = try XCTUnwrap(notification.params, file: file, line: line)
                let delta = try decodeJSONValue(params, as: ExecServerHttpRequestBodyDeltaNotification.self)
                XCTAssertEqual(delta.requestId, requestId, file: file, line: line)
                deltas.append(delta)
                if delta.done {
                    return deltas
                }
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Timed out waiting for terminal http/request body delta line", file: file, line: line)
        return deltas
    }

    private func collectProcessLifecycleNotifications(
        from connection: ExecServerConnection,
        processId: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws -> (
        output: ExecServerOutputDeltaNotification?,
        exited: ExecServerExitedNotification?,
        closed: ExecServerClosedNotification?
    ) {
        var output: ExecServerOutputDeltaNotification?
        var exited: ExecServerExitedNotification?
        var closed: ExecServerClosedNotification?

        for _ in 0..<50 {
            guard let outbound = try await nextOutbound(from: connection, file: file, line: line) else {
                continue
            }
            guard case let .notification(notification) = outbound else {
                XCTFail("Expected process lifecycle notification", file: file, line: line)
                continue
            }
            let params = try XCTUnwrap(notification.params, file: file, line: line)
            switch notification.method {
            case execServerProcessOutputDeltaMethod:
                let decoded = try decodeJSONValue(params, as: ExecServerOutputDeltaNotification.self)
                XCTAssertEqual(decoded.processId, processId, file: file, line: line)
                output = decoded
            case execServerProcessExitedMethod:
                let decoded = try decodeJSONValue(params, as: ExecServerExitedNotification.self)
                XCTAssertEqual(decoded.processId, processId, file: file, line: line)
                exited = decoded
            case execServerProcessClosedMethod:
                let decoded = try decodeJSONValue(params, as: ExecServerClosedNotification.self)
                XCTAssertEqual(decoded.processId, processId, file: file, line: line)
                closed = decoded
            default:
                XCTFail("Unexpected process notification method \(notification.method)", file: file, line: line)
            }
            if output != nil, exited != nil, closed != nil {
                return (output, exited, closed)
            }
        }

        XCTFail("Timed out waiting for process lifecycle notifications", file: file, line: line)
        return (output, exited, closed)
    }

    private func decodeLine(_ data: Data) throws -> ExecServerJSONRPCMessage {
        XCTAssertEqual(data.last, 0x0A)
        return try JSONDecoder().decode(ExecServerJSONRPCMessage.self, from: Data(data.dropLast()))
    }

    private actor StdioTransportOutput {
        private var lines: [Data] = []

        func append(_ line: Data) {
            lines.append(line)
        }

        func waitForMessages(
            count: Int,
            file: StaticString = #filePath,
            line: UInt = #line
        ) async throws -> [ExecServerJSONRPCMessage] {
            for _ in 0..<50 {
                if lines.count >= count {
                    return try lines.map { try JSONDecoder().decode(
                        ExecServerJSONRPCMessage.self,
                        from: Data($0.dropLast())
                    ) }
                }
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            XCTFail("Timed out waiting for stdio transport output", file: file, line: line)
            return []
        }
    }

    private actor HTTPRequestRecorder {
        private let response: URLSessionTransportResponse
        private var requests: [URLRequest] = []

        init(response: URLSessionTransportResponse) {
            self.response = response
        }

        func send(_ request: URLRequest) -> URLSessionTransportResponse {
            requests.append(request)
            return response
        }

        func firstRequest() -> URLRequest? {
            requests.first
        }
    }

    private actor HTTPStreamGate {
        private var continuation: APIByteStream.Continuation?

        func store(_ continuation: APIByteStream.Continuation) {
            self.continuation = continuation
        }

        func finish() {
            continuation?.finish()
            continuation = nil
        }
    }

    private func readProcessUntilClosed(
        _ connection: ExecServerConnection,
        processId: String
    ) async throws -> (output: String, exitCode: Int32?, closed: Bool) {
        var output = ""
        var afterSeq: UInt64?
        var exitCode: Int32?
        for index in 0..<20 {
            let response = await connection.handle(.message(.request(ExecServerJSONRPCRequest(
                id: .integer(Int64(100 + index)),
                method: execServerProcessReadMethod,
                params: try ExecServerRPC.jsonValue(from: ExecServerReadParams(
                    processId: processId,
                    afterSeq: afterSeq,
                    waitMs: 250
                ))
            ))))
            guard case let .response(_, result) = response else {
                throw NSError(
                    domain: "ExecServerTests",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Expected process/read response"]
                )
            }
            let read = try decodeJSONValue(result, as: ExecServerReadResponse.self)
            for chunk in read.chunks {
                output += String(decoding: chunk.chunk.bytes, as: UTF8.self)
                afterSeq = chunk.seq
            }
            if read.exited {
                exitCode = read.exitCode
            }
            if read.closed {
                return (output, exitCode, true)
            }
            afterSeq = read.nextSeq > 0 ? read.nextSeq - 1 : afterSeq
        }
        return (output, exitCode, false)
    }

    private func readHandlerProcessUntilClosed(
        _ handler: ExecServerHandler,
        processId: String
    ) async throws -> (output: String, exitCode: Int32?, closed: Bool) {
        var output = ""
        var afterSeq: UInt64?
        var exitCode: Int32?
        for _ in 0..<20 {
            let read = try await handler.readProcess(ExecServerReadParams(
                processId: processId,
                afterSeq: afterSeq,
                waitMs: 250
            ))
            for chunk in read.chunks {
                output += String(decoding: chunk.chunk.bytes, as: UTF8.self)
                afterSeq = chunk.seq
            }
            if read.exited {
                exitCode = read.exitCode
            }
            if read.closed {
                return (output, exitCode, true)
            }
            afterSeq = read.nextSeq > 0 ? read.nextSeq - 1 : afterSeq
        }
        return (output, exitCode, false)
    }

    private func decodeJSONValue<T: Decodable>(_ value: JSONValue, as type: T.Type) throws -> T {
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode(type, from: data)
    }
}
