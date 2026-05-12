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

    func testWebSocketTransportListensAndRoutesJSONRPCLikeRust() async throws {
        let (stream, continuation) = AsyncStream.makeStream(of: String.self)
        let transport = ExecServerWebSocketTransport(processor: ExecServerConnectionProcessor(
            sessionRegistry: ExecServerSessionRegistry(makeID: sequenceIDs(["connection-1", "session-1"]))
        ))
        let serverTask = Task.detached {
            try await transport.run(host: "127.0.0.1", port: 0) { url in
                continuation.yield(url.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
        defer {
            serverTask.cancel()
        }

        var iterator = stream.makeAsyncIterator()
        let nextURL = await iterator.next()
        let urlString = try XCTUnwrap(nextURL)
        XCTAssertTrue(urlString.hasPrefix("ws://127.0.0.1:"))

        let webSocket = URLSession.shared.webSocketTask(with: try XCTUnwrap(URL(string: urlString)))
        webSocket.resume()
        defer {
            webSocket.cancel(with: .goingAway, reason: nil)
        }

        try await webSocket.send(.string(#"{"id":1,"method":"initialize","params":{"clientName":"client"}}"#))
        let received = try await webSocket.receive()
        let text: String
        switch received {
        case let .string(value):
            text = value
        case let .data(data):
            text = String(decoding: data, as: UTF8.self)
        @unknown default:
            return XCTFail("Unexpected websocket message")
        }

        let message = try JSONDecoder().decode(ExecServerJSONRPCMessage.self, from: Data(text.utf8))
        XCTAssertEqual(message, .response(ExecServerJSONRPCResponse(
            id: .integer(1),
            result: try ExecServerRPC.jsonValue(from: ExecServerInitializeResponse(sessionId: "session-1"))
        )))
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

        let responseLines = try await server.receiveLine(
            #"{"id":2,"method":"http/request","params":{"method":"GET","url":"https://example.test/mcp","requestId":"stream-stdio","streamResponse":true}}"#,
            drainMode: .directOnly
        )

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

    func testStdioTransportDisconnectDetachesSessionDuringInFlightReadLikeRust() async throws {
        var inputContinuation: AsyncStream<String>.Continuation?
        let input = AsyncStream<String> { continuation in
            inputContinuation = continuation
        }
        let output = StdioTransportOutput()
        let registry = ExecServerSessionRegistry(makeID: sequenceIDs(["connection-1", "session-1", "connection-2"]))
        let firstTransport = ExecServerStdioTransport(server: ExecServerLineServer(sessionRegistry: registry))

        let firstRunTask = Task {
            try await firstTransport.run(lines: input) { line in
                await output.append(line)
            }
        }
        let continuation = try XCTUnwrap(inputContinuation)
        continuation.yield(#"{"id":1,"method":"initialize","params":{"clientName":"client"}}"#)
        let initializeMessages = try await output.waitForMessages(count: 1)
        XCTAssertEqual(initializeMessages[0], ExecServerRPC.response(
            id: .integer(1),
            result: .object(["sessionId": .string("session-1")])
        ))

        continuation.yield(#"{"method":"initialized","params":{}}"#)
        try await Task.sleep(nanoseconds: 10_000_000)
        continuation.yield(#"{"id":2,"method":"process/start","params":{"processId":"transport-long-read","argv":["/bin/sh","-c","sleep 5"],"cwd":"/tmp","env":{},"tty":false}}"#)

        let firstMessages = try await output.waitForMessages(count: 2)
        XCTAssertEqual(firstMessages[1], ExecServerRPC.response(
            id: .integer(2),
            result: .object(["processId": .string("transport-long-read")])
        ))

        continuation.yield(#"{"id":3,"method":"process/read","params":{"processId":"transport-long-read","waitMs":5000}}"#)
        continuation.finish()
        try await withTimeout(seconds: 1) {
            try await firstRunTask.value
        }

        let second = await ExecServerConnectionProcessor(sessionRegistry: registry).makeConnection()
        let resumed = await second.handle(.message(.request(ExecServerJSONRPCRequest(
            id: .integer(4),
            method: execServerInitializeMethod,
            params: try ExecServerRPC.jsonValue(from: ExecServerInitializeParams(
                clientName: "second",
                resumeSessionId: "session-1"
            ))
        ))))
        _ = await second.handle(.message(.notification(ExecServerJSONRPCNotification(
            method: execServerInitializedMethod,
            params: .object([:])
        ))))
        let terminated = await second.handle(.message(.request(ExecServerJSONRPCRequest(
            id: .integer(5),
            method: execServerProcessTerminateMethod,
            params: try ExecServerRPC.jsonValue(from: ExecServerTerminateParams(processId: "transport-long-read"))
        ))))

        XCTAssertEqual(resumed?.jsonRPCMessage, ExecServerRPC.response(
            id: .integer(4),
            result: .object(["sessionId": .string("session-1")])
        ))
        XCTAssertEqual(terminated?.jsonRPCMessage, ExecServerRPC.response(
            id: .integer(5),
            result: .object(["running": .bool(true)])
        ))
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

    func testConnectionProcessorWritesToPtyProcessWithoutPipeStdinLikeRust() async throws {
        let connection = try await initializedConnection()
        let cwd = FileManager.default.currentDirectoryPath
        let start = await connection.handle(.message(.request(ExecServerJSONRPCRequest(
            id: .integer(2),
            method: execServerProcessStartMethod,
            params: try ExecServerRPC.jsonValue(from: ExecServerExecParams(
                processId: "proc-pty-stdin",
                argv: ["/bin/sh", "-c", "IFS= read line; printf 'from-stdin:%s\\n' \"$line\""],
                cwd: cwd,
                env: [:],
                tty: true,
                pipeStdin: false
            ))
        ))))

        let write = await connection.handle(.message(.request(ExecServerJSONRPCRequest(
            id: .integer(3),
            method: execServerProcessWriteMethod,
            params: try ExecServerRPC.jsonValue(from: ExecServerWriteParams(
                processId: "proc-pty-stdin",
                chunk: ExecServerByteChunk(Array("hello\n".utf8))
            ))
        ))))
        let notifications = try await collectProcessLifecycleNotifications(
            from: connection,
            processId: "proc-pty-stdin"
        )
        let read = try await readProcessUntilClosed(connection, processId: "proc-pty-stdin")

        XCTAssertEqual(start?.jsonRPCMessage, ExecServerRPC.response(
            id: .integer(2),
            result: .object(["processId": .string("proc-pty-stdin")])
        ))
        XCTAssertEqual(write?.jsonRPCMessage, ExecServerRPC.response(
            id: .integer(3),
            result: .object(["status": .string("accepted")])
        ))
        XCTAssertEqual(notifications.output?.stream, .pty)
        XCTAssertTrue(read.output.contains("from-stdin:hello"), "unexpected PTY output: \(read.output)")
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

    func testFilesystemRemoveNonRecursiveDirectoryMatchesRust() throws {
        let fileSystem = ExecServerFileSystem()
        let tempDirectory = try makeTemporaryDirectory()
        let nonEmptyDirectory = tempDirectory.appendingPathComponent("non-empty")
        let emptyDirectory = tempDirectory.appendingPathComponent("empty")
        try FileManager.default.createDirectory(at: nonEmptyDirectory, withIntermediateDirectories: true)
        try Data("kept".utf8).write(to: nonEmptyDirectory.appendingPathComponent("note.txt"))
        try FileManager.default.createDirectory(at: emptyDirectory, withIntermediateDirectories: true)

        XCTAssertThrowsError(try fileSystem.remove(ExecServerFsRemoveParams(
            path: absolutePath(nonEmptyDirectory.path),
            recursive: false,
            force: false
        ))) { error in
            XCTAssertEqual((error as? ExecServerFileSystemError)?.kind, .other)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: nonEmptyDirectory.path))

        _ = try fileSystem.remove(ExecServerFsRemoveParams(
            path: absolutePath(emptyDirectory.path),
            recursive: false,
            force: false
        ))
        XCTAssertFalse(FileManager.default.fileExists(atPath: emptyDirectory.path))
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

    func testConnectionProcessorResumesDetachedSessionWithoutKillingProcessLikeRust() async throws {
        let processor = ExecServerConnectionProcessor(
            sessionRegistry: ExecServerSessionRegistry(makeID: sequenceIDs(["connection-1", "session-1", "connection-2"]))
        )
        let first = await processor.makeConnection()
        let firstInitialize = await first.handle(.message(.request(ExecServerJSONRPCRequest(
            id: .integer(1),
            method: execServerInitializeMethod,
            params: try ExecServerRPC.jsonValue(from: ExecServerInitializeParams(clientName: "first"))
        ))))
        _ = await first.handle(.message(.notification(ExecServerJSONRPCNotification(
            method: execServerInitializedMethod,
            params: .object([:])
        ))))
        let start = await first.handle(.message(.request(ExecServerJSONRPCRequest(
            id: .integer(2),
            method: execServerProcessStartMethod,
            params: try ExecServerRPC.jsonValue(from: ExecServerExecParams(
                processId: "proc-resume",
                argv: ["/bin/sh", "-c", "sleep 5"],
                cwd: FileManager.default.currentDirectoryPath,
                env: [:],
                tty: false
            ))
        ))))

        _ = await first.handle(.disconnected(reason: nil))
        let second = await processor.makeConnection()
        let resumed = await second.handle(.message(.request(ExecServerJSONRPCRequest(
            id: .integer(3),
            method: execServerInitializeMethod,
            params: try ExecServerRPC.jsonValue(from: ExecServerInitializeParams(
                clientName: "second",
                resumeSessionId: "session-1"
            ))
        ))))
        _ = await second.handle(.message(.notification(ExecServerJSONRPCNotification(
            method: execServerInitializedMethod,
            params: .object([:])
        ))))
        let read = await second.handle(.message(.request(ExecServerJSONRPCRequest(
            id: .integer(4),
            method: execServerProcessReadMethod,
            params: try ExecServerRPC.jsonValue(from: ExecServerReadParams(processId: "proc-resume"))
        ))))
        let terminated = await second.handle(.message(.request(ExecServerJSONRPCRequest(
            id: .integer(5),
            method: execServerProcessTerminateMethod,
            params: try ExecServerRPC.jsonValue(from: ExecServerTerminateParams(processId: "proc-resume"))
        ))))

        XCTAssertEqual(firstInitialize?.jsonRPCMessage, ExecServerRPC.response(
            id: .integer(1),
            result: .object(["sessionId": .string("session-1")])
        ))
        XCTAssertEqual(start?.jsonRPCMessage, ExecServerRPC.response(
            id: .integer(2),
            result: .object(["processId": .string("proc-resume")])
        ))
        XCTAssertEqual(resumed?.jsonRPCMessage, ExecServerRPC.response(
            id: .integer(3),
            result: .object(["sessionId": .string("session-1")])
        ))
        guard case let .response(_, result) = read else {
            return XCTFail("Expected process/read response after resume")
        }
        let readResponse = try decodeJSONValue(result, as: ExecServerReadResponse.self)
        XCTAssertTrue(readResponse.chunks.isEmpty)
        XCTAssertFalse(readResponse.exited)
        XCTAssertFalse(readResponse.closed)
        XCTAssertNil(readResponse.failure)
        XCTAssertEqual(terminated?.jsonRPCMessage, ExecServerRPC.response(
            id: .integer(5),
            result: .object(["running": .bool(true)])
        ))
    }

    func testConnectionProcessorRebindsProcessNotificationsAfterResumeLikeRust() async throws {
        let processor = ExecServerConnectionProcessor(
            sessionRegistry: ExecServerSessionRegistry(makeID: sequenceIDs(["connection-1", "session-1", "connection-2"]))
        )
        let first = await processor.makeConnection()
        _ = await first.handle(.message(.request(ExecServerJSONRPCRequest(
            id: .integer(1),
            method: execServerInitializeMethod,
            params: try ExecServerRPC.jsonValue(from: ExecServerInitializeParams(clientName: "first"))
        ))))
        _ = await first.handle(.message(.notification(ExecServerJSONRPCNotification(
            method: execServerInitializedMethod,
            params: .object([:])
        ))))
        _ = await first.handle(.message(.request(ExecServerJSONRPCRequest(
            id: .integer(2),
            method: execServerProcessStartMethod,
            params: try ExecServerRPC.jsonValue(from: ExecServerExecParams(
                processId: "proc-resume-notify",
                argv: ["/bin/sh", "-c", "IFS= read line; printf 'resumed:%s\\n' \"$line\""],
                cwd: FileManager.default.currentDirectoryPath,
                env: [:],
                tty: false,
                pipeStdin: true
            ))
        ))))

        _ = await first.handle(.disconnected(reason: nil))
        let second = await processor.makeConnection()
        _ = await second.handle(.message(.request(ExecServerJSONRPCRequest(
            id: .integer(3),
            method: execServerInitializeMethod,
            params: try ExecServerRPC.jsonValue(from: ExecServerInitializeParams(
                clientName: "second",
                resumeSessionId: "session-1"
            ))
        ))))
        _ = await second.handle(.message(.notification(ExecServerJSONRPCNotification(
            method: execServerInitializedMethod,
            params: .object([:])
        ))))
        let write = await second.handle(.message(.request(ExecServerJSONRPCRequest(
            id: .integer(4),
            method: execServerProcessWriteMethod,
            params: try ExecServerRPC.jsonValue(from: ExecServerWriteParams(
                processId: "proc-resume-notify",
                chunk: ExecServerByteChunk(Array("hello\n".utf8))
            ))
        ))))
        let notifications = try await collectProcessLifecycleNotifications(
            from: second,
            processId: "proc-resume-notify"
        )
        let retained = try await readProcessUntilClosed(second, processId: "proc-resume-notify")

        XCTAssertEqual(write?.jsonRPCMessage, ExecServerRPC.response(
            id: .integer(4),
            result: .object(["status": .string("accepted")])
        ))
        XCTAssertEqual(notifications.output?.stream, .stdout)
        XCTAssertEqual(notifications.output?.chunk.bytes, Array("resumed:hello\n".utf8))
        XCTAssertEqual(notifications.exited?.exitCode, 0)
        XCTAssertEqual(retained.output, "resumed:hello\n")
        XCTAssertEqual(retained.exitCode, 0)
        XCTAssertTrue(retained.closed)
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

    func testHandlerLongPollReadFailsAfterSessionResumeLikeRust() async throws {
        let registry = ExecServerSessionRegistry(makeID: sequenceIDs(["connection-1", "session-1", "connection-2"]))
        let first = ExecServerHandler(sessionRegistry: registry)
        let second = ExecServerHandler(sessionRegistry: registry)
        let response = try await first.initialize(ExecServerInitializeParams(clientName: "first"))
        try await first.markInitialized()

        _ = try await first.startProcess(ExecServerExecParams(
            processId: "proc-long-poll",
            argv: ["/bin/sh", "-c", "sleep 5"],
            cwd: FileManager.default.currentDirectoryPath,
            env: [:],
            tty: false
        ))

        let readTask = Task {
            try await first.readProcess(ExecServerReadParams(
                processId: "proc-long-poll",
                waitMs: 500
            ))
        }

        try await Task.sleep(nanoseconds: 50_000_000)
        await first.shutdown()
        _ = try await second.initialize(ExecServerInitializeParams(
            clientName: "second",
            resumeSessionId: response.sessionId
        ))
        try await second.markInitialized()

        do {
            _ = try await readTask.value
            XCTFail("Expected evicted long-poll read to fail")
        } catch let error as ExecServerJSONRPCErrorDetail {
            XCTAssertEqual(error.code, -32600)
            XCTAssertEqual(error.message, "session has been resumed by another connection")
        }

        _ = try await second.terminateProcess(ExecServerTerminateParams(processId: "proc-long-poll"))
        await second.shutdown()
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

    private func XCTAssertThrowsExecServerRemoteError(
        _ expression: @autoclosure () async throws -> some Any,
        description: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await expression()
            XCTFail("Expected exec-server remote executor error", file: file, line: line)
        } catch let error as ExecServerRemoteExecutorError {
            XCTAssertEqual(String(describing: error), description, file: file, line: line)
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

    func testAppServerListenURLParserAcceptsRustSupportedForms() throws {
        let codexHome = URL(fileURLWithPath: "/tmp/codex-home", isDirectory: true)

        XCTAssertEqual(try AppServerListenURLParser.parse("stdio://", codexHome: codexHome), .stdio)
        XCTAssertEqual(
            try AppServerListenURLParser.parse("unix://", codexHome: codexHome),
            .unixSocket(socketPath: "/tmp/codex-home/app-server-control/app-server-control.sock")
        )
        XCTAssertEqual(
            try AppServerListenURLParser.parse(
                "unix://codex.sock",
                codexHome: codexHome,
                currentDirectory: "/tmp/workspace"
            ),
            .unixSocket(socketPath: "/tmp/workspace/codex.sock")
        )
        XCTAssertEqual(
            try AppServerListenURLParser.parse("unix:///tmp/codex.sock", codexHome: codexHome),
            .unixSocket(socketPath: "/tmp/codex.sock")
        )
        XCTAssertEqual(
            try AppServerListenURLParser.parse("ws://127.0.0.1:4500", codexHome: codexHome),
            .webSocket(host: "127.0.0.1", port: 4500)
        )
        XCTAssertEqual(
            try AppServerListenURLParser.parse("ws://[::1]:4500", codexHome: codexHome),
            .webSocket(host: "::1", port: 4500)
        )
        XCTAssertEqual(try AppServerListenURLParser.parse("off", codexHome: codexHome), .off)
    }

    func testAppServerListenURLParserRejectsRustInvalidForms() {
        XCTAssertThrowsError(try AppServerListenURLParser.parse("http://foo", codexHome: URL(fileURLWithPath: "/tmp/home"))) { error in
            XCTAssertEqual(error as? AppServerTransportParseError, .unsupportedListenURL("http://foo"))
            XCTAssertEqual(
                String(describing: error),
                "unsupported --listen URL `http://foo`; expected `stdio://`, `unix://`, `unix://PATH`, `ws://IP:PORT`, or `off`"
            )
        }

        for listenURL in ["ws://127.0.0.1", "ws://localhost:4500", "ws://127.0.0.1:4500/path"] {
            XCTAssertThrowsError(try AppServerListenURLParser.parse(listenURL, codexHome: URL(fileURLWithPath: "/tmp/home"))) { error in
                XCTAssertEqual(error as? AppServerTransportParseError, .invalidWebSocketListenURL(listenURL))
                XCTAssertEqual(
                    String(describing: error),
                    "invalid websocket --listen URL `\(listenURL)`; expected `ws://IP:PORT`"
                )
            }
        }
    }

    func testAppServerExecutableTransportValidatorAcceptsStdioAndUnauthenticatedWebSocket() {
        XCTAssertNoThrow(try AppServerExecutableTransportValidator.validateSupportedTransport(
            .stdio,
            remoteControlFeatureEnabled: false,
            stateStoreAvailable: false
        ))

        XCTAssertNoThrow(try AppServerExecutableTransportValidator.validateSupportedTransport(
            .webSocket(host: "::1", port: 4500),
            remoteControlFeatureEnabled: false,
            stateStoreAvailable: false
        ))
    }

    func testAppServerExecutableTransportValidatorRejectsUnsupportedRuntimeModes() {
        XCTAssertThrowsError(try AppServerExecutableTransportValidator.validateSupportedTransport(
            .off,
            remoteControlFeatureEnabled: false,
            stateStoreAvailable: true
        )) { error in
            XCTAssertEqual(error as? AppServerExecutableTransportError, .noTransportConfigured)
            XCTAssertEqual(
                String(describing: error),
                "no transport configured; use --listen or enable remote control"
            )
        }

        XCTAssertThrowsError(try AppServerExecutableTransportValidator.validateSupportedTransport(
            .off,
            remoteControlFeatureEnabled: true,
            stateStoreAvailable: false
        )) { error in
            XCTAssertEqual(error as? AppServerExecutableTransportError, .remoteControlUnavailableWithoutStateDB)
            XCTAssertEqual(
                String(describing: error),
                "no transport configured; remote control disabled because sqlite state db is unavailable"
            )
        }
    }

    func testAppServerExecutableTransportValidatorValidatesRemoteControlURLLikeRustStartup() {
        XCTAssertNoThrow(try AppServerExecutableTransportValidator.validateSupportedTransport(
            .stdio,
            remoteControlFeatureEnabled: true,
            stateStoreAvailable: true,
            remoteControlBaseURL: "https://chatgpt.com/backend-api"
        ))

        XCTAssertThrowsError(try AppServerExecutableTransportValidator.validateSupportedTransport(
            .stdio,
            remoteControlFeatureEnabled: true,
            stateStoreAvailable: true,
            remoteControlBaseURL: "https://example.com/backend-api"
        )) { error in
            XCTAssertEqual(
                String(describing: error),
                "invalid remote control URL `https://example.com/backend-api`; expected HTTPS URL for chatgpt.com or chatgpt-staging.com, or HTTP/HTTPS URL for localhost"
            )
        }

        XCTAssertNoThrow(try AppServerExecutableTransportValidator.validateSupportedTransport(
            .stdio,
            remoteControlFeatureEnabled: true,
            stateStoreAvailable: false,
            remoteControlBaseURL: "https://example.com/backend-api"
        ))
    }

    func testAppServerExecutableTransportValidatorAllowsUnixSocketAfterControlSocketPort() {
        XCTAssertNoThrow(try AppServerExecutableTransportValidator.validateSupportedTransport(
            .unixSocket(socketPath: "/tmp/codex.sock"),
            remoteControlFeatureEnabled: false,
            stateStoreAvailable: false
        ))
    }

    func testAppServerExecutableTransportValidatorAllowsWebSocketAuthAfterPolicyEnforcement() {
        XCTAssertNoThrow(try AppServerExecutableTransportValidator.validateSupportedTransport(
            .webSocket(host: "::1", port: 4500),
            websocketAuth: AppServerWebsocketAuthSettings(config: .capabilityToken(source: .tokenSHA256([]))),
            remoteControlFeatureEnabled: false,
            stateStoreAvailable: false
        ))
    }

    func testRemoteControlURLNormalizerAcceptsRustSupportedTargets() throws {
        XCTAssertEqual(
            try RemoteControlURLNormalizer.normalize("https://chatgpt.com/backend-api"),
            RemoteControlTarget(
                websocketURL: "wss://chatgpt.com/backend-api/wham/remote/control/server",
                enrollURL: "https://chatgpt.com/backend-api/wham/remote/control/server/enroll"
            )
        )
        XCTAssertEqual(
            try RemoteControlURLNormalizer.normalize("https://api.chatgpt-staging.com/backend-api"),
            RemoteControlTarget(
                websocketURL: "wss://api.chatgpt-staging.com/backend-api/wham/remote/control/server",
                enrollURL: "https://api.chatgpt-staging.com/backend-api/wham/remote/control/server/enroll"
            )
        )
        XCTAssertEqual(
            try RemoteControlURLNormalizer.normalize("http://localhost:8080/backend-api"),
            RemoteControlTarget(
                websocketURL: "ws://localhost:8080/backend-api/wham/remote/control/server",
                enrollURL: "http://localhost:8080/backend-api/wham/remote/control/server/enroll"
            )
        )
        XCTAssertEqual(
            try RemoteControlURLNormalizer.normalize("https://localhost:8443/backend-api"),
            RemoteControlTarget(
                websocketURL: "wss://localhost:8443/backend-api/wham/remote/control/server",
                enrollURL: "https://localhost:8443/backend-api/wham/remote/control/server/enroll"
            )
        )
        XCTAssertEqual(
            try RemoteControlURLNormalizer.normalize("http://127.0.0.1:8080/backend-api"),
            RemoteControlTarget(
                websocketURL: "ws://127.0.0.1:8080/backend-api/wham/remote/control/server",
                enrollURL: "http://127.0.0.1:8080/backend-api/wham/remote/control/server/enroll"
            )
        )
        XCTAssertEqual(
            try RemoteControlURLNormalizer.normalize("https://[::1]:8443/backend-api"),
            RemoteControlTarget(
                websocketURL: "wss://[::1]:8443/backend-api/wham/remote/control/server",
                enrollURL: "https://[::1]:8443/backend-api/wham/remote/control/server/enroll"
            )
        )
    }

    func testRemoteControlURLNormalizerRejectsUnsupportedTargetsLikeRust() {
        for remoteControlURL in [
            "http://chatgpt.com/backend-api",
            "http://example.com/backend-api",
            "https://example.com/backend-api",
            "https://chat.openai.com/backend-api",
            "https://chatgpt.com.evil.com/backend-api",
            "https://evilchatgpt.com/backend-api",
            "https://foo.localhost/backend-api",
        ] {
            XCTAssertThrowsError(try RemoteControlURLNormalizer.normalize(remoteControlURL)) { error in
                XCTAssertEqual(
                    String(describing: error),
                    "invalid remote control URL `\(remoteControlURL)`; expected HTTPS URL for chatgpt.com or chatgpt-staging.com, or HTTP/HTTPS URL for localhost"
                )
            }
        }
    }

    func testRemoteControlStartStateMatchesRustInitialStatusAndURLValidation() throws {
        let disabled = try RemoteControlStartState(
            remoteControlURL: "https://example.com/backend-api",
            installationID: "install-123",
            requestedEnabled: false,
            stateDatabaseAvailable: true
        )
        XCTAssertFalse(disabled.enabled)
        XCTAssertNil(disabled.target)
        XCTAssertEqual(disabled.statusSnapshot, RemoteControlStatusSnapshot(
            status: .disabled,
            installationID: "install-123",
            environmentID: nil
        ))

        let missingStateDB = try RemoteControlStartState(
            remoteControlURL: "https://example.com/backend-api",
            installationID: "install-123",
            requestedEnabled: true,
            stateDatabaseAvailable: false
        )
        XCTAssertFalse(missingStateDB.enabled)
        XCTAssertNil(missingStateDB.target)
        XCTAssertEqual(missingStateDB.statusSnapshot.status, .disabled)

        let enabled = try RemoteControlStartState(
            remoteControlURL: "https://chatgpt.com/backend-api",
            installationID: "install-123",
            requestedEnabled: true,
            stateDatabaseAvailable: true
        )
        XCTAssertTrue(enabled.enabled)
        XCTAssertEqual(enabled.target, RemoteControlTarget(
            websocketURL: "wss://chatgpt.com/backend-api/wham/remote/control/server",
            enrollURL: "https://chatgpt.com/backend-api/wham/remote/control/server/enroll"
        ))
        XCTAssertEqual(enabled.statusSnapshot, RemoteControlStatusSnapshot(
            status: .connecting,
            installationID: "install-123",
            environmentID: nil
        ))

        XCTAssertThrowsError(try RemoteControlStartState(
            remoteControlURL: "https://example.com/backend-api",
            installationID: "install-123",
            requestedEnabled: true,
            stateDatabaseAvailable: true
        )) { error in
            XCTAssertEqual(
                String(describing: error),
                "invalid remote control URL `https://example.com/backend-api`; expected HTTPS URL for chatgpt.com or chatgpt-staging.com, or HTTP/HTTPS URL for localhost"
            )
        }
    }

    func testRemoteControlStartStateSetEnabledUsesRustEffectiveStateGate() throws {
        var missingStateDB = try RemoteControlStartState(
            remoteControlURL: "https://chatgpt.com/backend-api",
            installationID: "install-123",
            requestedEnabled: false,
            stateDatabaseAvailable: false
        )
        XCTAssertNil(try missingStateDB.setRequestedEnabled(true))
        XCTAssertTrue(missingStateDB.requestedEnabled)
        XCTAssertFalse(missingStateDB.enabled)
        XCTAssertNil(missingStateDB.target)
        XCTAssertEqual(missingStateDB.statusSnapshot.status, .disabled)

        var withStateDB = try RemoteControlStartState(
            remoteControlURL: "https://chatgpt.com/backend-api",
            installationID: "install-123",
            requestedEnabled: false,
            stateDatabaseAvailable: true
        )
        XCTAssertEqual(try withStateDB.setRequestedEnabled(true), RemoteControlStatusSnapshot(
            status: .connecting,
            installationID: "install-123",
            environmentID: nil
        ))
        XCTAssertEqual(withStateDB.target, RemoteControlTarget(
            websocketURL: "wss://chatgpt.com/backend-api/wham/remote/control/server",
            enrollURL: "https://chatgpt.com/backend-api/wham/remote/control/server/enroll"
        ))
        XCTAssertNil(try withStateDB.setRequestedEnabled(true))
        XCTAssertEqual(try withStateDB.setRequestedEnabled(false), RemoteControlStatusSnapshot(
            status: .disabled,
            installationID: "install-123",
            environmentID: nil
        ))
    }

    func testRemoteControlHandleCoreMirrorsRustEnablementGateAndInitialStatus() throws {
        let disabledInvalidURL = try RemoteControlHandleCore(
            remoteControlURL: "https://example.com/backend-api",
            installationID: "install-123",
            requestedEnabled: false,
            stateDatabaseAvailable: true
        )
        XCTAssertFalse(disabledInvalidURL.effectiveEnabled)
        XCTAssertNil(disabledInvalidURL.target)
        XCTAssertEqual(disabledInvalidURL.statusSnapshot, RemoteControlStatusSnapshot(
            status: .disabled,
            installationID: "install-123",
            environmentID: nil
        ))

        let missingStateDB = try RemoteControlHandleCore(
            remoteControlURL: "https://chatgpt.com/backend-api",
            installationID: "install-123",
            requestedEnabled: true,
            stateDatabaseAvailable: false
        )
        XCTAssertTrue(missingStateDB.requestedEnabled)
        XCTAssertFalse(missingStateDB.effectiveEnabled)
        XCTAssertNil(missingStateDB.target)
        XCTAssertEqual(missingStateDB.statusSnapshot.status, .disabled)

        let enabled = try RemoteControlHandleCore(
            remoteControlURL: "https://chatgpt.com/backend-api",
            installationID: "install-123",
            requestedEnabled: true,
            stateDatabaseAvailable: true
        )
        XCTAssertTrue(enabled.effectiveEnabled)
        XCTAssertEqual(enabled.target, RemoteControlTarget(
            websocketURL: "wss://chatgpt.com/backend-api/wham/remote/control/server",
            enrollURL: "https://chatgpt.com/backend-api/wham/remote/control/server/enroll"
        ))
        XCTAssertEqual(enabled.statusSnapshot.status, .connecting)

        XCTAssertThrowsError(try RemoteControlHandleCore(
            remoteControlURL: "https://example.com/backend-api",
            installationID: "install-123",
            requestedEnabled: true,
            stateDatabaseAvailable: true
        )) { error in
            XCTAssertEqual(
                String(describing: error),
                "invalid remote control URL `https://example.com/backend-api`; expected HTTPS URL for chatgpt.com or chatgpt-staging.com, or HTTP/HTTPS URL for localhost"
            )
        }
    }

    func testRemoteControlHandleCoreSetEnabledDefersURLValidationToConnectLoopLikeRust() throws {
        var handle = try RemoteControlHandleCore(
            remoteControlURL: "https://example.com/backend-api",
            installationID: "install-123",
            requestedEnabled: false,
            stateDatabaseAvailable: true
        )

        XCTAssertEqual(handle.setEnabled(true), RemoteControlHandleEnablementChange(
            requestedEnabled: true,
            effectiveEnabled: true,
            changed: true,
            stateDatabaseUnavailable: false
        ))
        XCTAssertTrue(handle.effectiveEnabled)
        XCTAssertNil(handle.target)
        XCTAssertEqual(handle.statusSnapshot.status, .disabled)

        var connectLoop = handle.beginConnectLoop()
        let connectStep = connectLoop.beginConnect()
        XCTAssertEqual(
            connectStep.action,
            .waitForDisableAfterInvalidURL("invalid remote control URL `https://example.com/backend-api`; expected HTTPS URL for chatgpt.com or chatgpt-staging.com, or HTTP/HTTPS URL for localhost")
        )
        XCTAssertEqual(connectStep.statusUpdates.map(\.status), [.connecting, .errored])
        handle.applyConnectLoopStatus(connectLoop)
        XCTAssertEqual(handle.statusSnapshot.status, .errored)

        XCTAssertEqual(handle.setEnabled(false), RemoteControlHandleEnablementChange(
            requestedEnabled: false,
            effectiveEnabled: false,
            changed: true,
            stateDatabaseUnavailable: false
        ))
        XCTAssertFalse(handle.effectiveEnabled)
        XCTAssertEqual(handle.statusSnapshot.status, .errored)

        var missingStateDB = try RemoteControlHandleCore(
            remoteControlURL: "https://chatgpt.com/backend-api",
            installationID: "install-123",
            requestedEnabled: false,
            stateDatabaseAvailable: false
        )
        XCTAssertEqual(missingStateDB.setEnabled(true), RemoteControlHandleEnablementChange(
            requestedEnabled: true,
            effectiveEnabled: false,
            changed: false,
            stateDatabaseUnavailable: true
        ))
        XCTAssertEqual(missingStateDB.statusSnapshot.status, .disabled)
    }

    func testRemoteControlStatusPublisherCoreSendsOnlyRustStatusChanges() {
        var publisher = RemoteControlStatusPublisherCore(snapshot: RemoteControlStatusSnapshot(
            status: .connecting,
            installationID: "install-123",
            environmentID: nil
        ))

        XCTAssertNil(publisher.publishEnvironmentID(nil))
        XCTAssertEqual(publisher.publishEnvironmentID("env-first"), RemoteControlStatusSnapshot(
            status: .connecting,
            installationID: "install-123",
            environmentID: "env-first"
        ))
        XCTAssertNil(publisher.publishEnvironmentID("env-first"))
        XCTAssertEqual(publisher.publishStatus(.connected), RemoteControlStatusSnapshot(
            status: .connected,
            installationID: "install-123",
            environmentID: "env-first"
        ))
        XCTAssertEqual(publisher.publishEnvironmentID(nil), RemoteControlStatusSnapshot(
            status: .connected,
            installationID: "install-123",
            environmentID: nil
        ))
        XCTAssertEqual(publisher.publishStatus(.disabled), RemoteControlStatusSnapshot(
            status: .disabled,
            installationID: "install-123",
            environmentID: nil
        ))
        XCTAssertNil(publisher.publishEnvironmentID("env-disabled"))
        XCTAssertNil(publisher.publishStatus(.disabled))
    }

    func testRemoteControlConnectLoopCoreMirrorsRustStatusAndReconnectDecisions() throws {
        var loop = RemoteControlConnectLoopCore(
            remoteControlURL: "https://chatgpt.com/backend-api",
            statusPublisher: RemoteControlStatusPublisherCore(snapshot: RemoteControlStatusSnapshot(
                status: .disabled,
                installationID: "install-123",
                environmentID: nil
            ))
        )

        XCTAssertEqual(loop.beginConnect(), RemoteControlConnectLoopStep(
            action: .connect(RemoteControlTarget(
                websocketURL: "wss://chatgpt.com/backend-api/wham/remote/control/server",
                enrollURL: "https://chatgpt.com/backend-api/wham/remote/control/server/enroll"
            )),
            statusUpdates: [RemoteControlStatusSnapshot(
                status: .connecting,
                installationID: "install-123",
                environmentID: nil
            )]
        ))
        XCTAssertEqual(loop.target, RemoteControlTarget(
            websocketURL: "wss://chatgpt.com/backend-api/wham/remote/control/server",
            enrollURL: "https://chatgpt.com/backend-api/wham/remote/control/server/enroll"
        ))

        XCTAssertEqual(loop.connectionEstablished(environmentID: "env-test"), RemoteControlConnectLoopStep(
            action: .connected,
            statusUpdates: [
                RemoteControlStatusSnapshot(
                    status: .connecting,
                    installationID: "install-123",
                    environmentID: "env-test"
                ),
                RemoteControlStatusSnapshot(
                    status: .connected,
                    installationID: "install-123",
                    environmentID: "env-test"
                ),
            ]
        ))

        let waitingForAccountID = loop.connectionFailed(.waitingForAccountID)
        XCTAssertEqual(waitingForAccountID, RemoteControlConnectLoopStep(
            action: .retryAfterAccountID,
            statusUpdates: []
        ))
        XCTAssertEqual(loop.reconnectAttempt, 0)
        XCTAssertEqual(loop.statusPublisher.snapshot.status, .connected)

        XCTAssertEqual(loop.connectionFailed(.failed("connection refused")), RemoteControlConnectLoopStep(
            action: .retryAfterBackoff(RemoteControlReconnectDelay(
                attempt: 0,
                baseMilliseconds: 200,
                minimumMilliseconds: 180,
                maximumMilliseconds: 220
            )),
            statusUpdates: [RemoteControlStatusSnapshot(
                status: .errored,
                installationID: "install-123",
                environmentID: "env-test"
            )]
        ))
        XCTAssertEqual(loop.reconnectAttempt, 1)
        XCTAssertEqual(loop.connectionFailed(.failed("connection refused")).action, .retryAfterBackoff(
            RemoteControlReconnectDelay(
                attempt: 1,
                baseMilliseconds: 200,
                minimumMilliseconds: 180,
                maximumMilliseconds: 220
            )
        ))
        XCTAssertEqual(loop.reconnectAttempt, 2)

        XCTAssertEqual(loop.disabled(), RemoteControlConnectLoopStep(
            action: .disabled,
            statusUpdates: [RemoteControlStatusSnapshot(
                status: .disabled,
                installationID: "install-123",
                environmentID: nil
            )]
        ))
    }

    func testRemoteControlConnectLoopCoreHandlesInvalidURLLikeRust() {
        var loop = RemoteControlConnectLoopCore(
            remoteControlURL: "https://example.com/backend-api",
            statusPublisher: RemoteControlStatusPublisherCore(snapshot: RemoteControlStatusSnapshot(
                status: .disabled,
                installationID: "install-123",
                environmentID: nil
            ))
        )

        let step = loop.beginConnect()
        XCTAssertEqual(step.statusUpdates, [
            RemoteControlStatusSnapshot(
                status: .connecting,
                installationID: "install-123",
                environmentID: nil
            ),
            RemoteControlStatusSnapshot(
                status: .errored,
                installationID: "install-123",
                environmentID: nil
            ),
        ])
        XCTAssertEqual(
            step.action,
            .waitForDisableAfterInvalidURL("invalid remote control URL `https://example.com/backend-api`; expected HTTPS URL for chatgpt.com or chatgpt-staging.com, or HTTP/HTTPS URL for localhost")
        )
        XCTAssertNil(loop.target)
        XCTAssertEqual(loop.reconnectAttempt, 0)
    }

    func testRemoteControlSessionLoopCoreWaitsForStdioClientNameLikeRust() {
        var loop = RemoteControlSessionLoopCore(statusPublisher: RemoteControlStatusPublisherCore(
            snapshot: RemoteControlStatusSnapshot(
                status: .connecting,
                installationID: "install-123",
                environmentID: "env-test"
            )
        ))

        XCTAssertEqual(loop.start(appServerClientNameRequired: true), RemoteControlSessionLoopStep(
            action: .waitForAppServerClientName
        ))
        XCTAssertEqual(loop.receiveAppServerClientName(.received("stdio-client")), RemoteControlSessionLoopStep(
            action: .waitUntilEnabled(appServerClientName: "stdio-client")
        ))
        XCTAssertEqual(loop.enabled(), RemoteControlSessionLoopStep(
            action: .connect(appServerClientName: "stdio-client")
        ))

        var unavailableLoop = RemoteControlSessionLoopCore(statusPublisher: RemoteControlStatusPublisherCore(
            snapshot: RemoteControlStatusSnapshot(
                status: .connecting,
                installationID: "install-123",
                environmentID: nil
            )
        ))
        XCTAssertEqual(unavailableLoop.receiveAppServerClientName(.unavailable), RemoteControlSessionLoopStep(
            action: .shutdownTracker
        ))
    }

    func testRemoteControlSessionLoopCoreMirrorsRustReconnectAndDisableActions() {
        var loop = RemoteControlSessionLoopCore(
            appServerClientName: "stdio-client",
            statusPublisher: RemoteControlStatusPublisherCore(snapshot: RemoteControlStatusSnapshot(
                status: .connected,
                installationID: "install-123",
                environmentID: "env-test"
            ))
        )

        XCTAssertEqual(loop.connectionEnded(.workerEnded), RemoteControlSessionLoopStep(
            action: .reconnect(appServerClientName: "stdio-client")
        ))
        XCTAssertEqual(loop.statusPublisher.snapshot, RemoteControlStatusSnapshot(
            status: .connected,
            installationID: "install-123",
            environmentID: "env-test"
        ))

        XCTAssertEqual(loop.connectionEnded(.disabled), RemoteControlSessionLoopStep(
            action: .waitUntilEnabled(appServerClientName: "stdio-client"),
            statusUpdates: [RemoteControlStatusSnapshot(
                status: .disabled,
                installationID: "install-123",
                environmentID: nil
            )]
        ))
        XCTAssertEqual(loop.connectionEnded(.shutdown), RemoteControlSessionLoopStep(
            action: .shutdownTracker
        ))
    }

    func testRemoteControlEnrollmentClientBuildsRustRequestShape() async throws {
        let target = try RemoteControlURLNormalizer.normalize("https://chatgpt.com/backend-api")
        let client = RemoteControlEnrollmentClient(
            auth: RemoteControlConnectionAuth(
                authProvider: StaticAPIAuthProvider(bearerToken: "chatgpt-token"),
                accountID: "remote-account"
            ),
            installationID: "install-123",
            appServerVersion: "1.2.3",
            serverName: "test-host",
            os: "macos",
            arch: "aarch64"
        )

        let request = try client.buildEnrollmentRequest(enrollURL: target.enrollURL)
        let body = try XCTUnwrap(request.httpBody)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: String])

        XCTAssertEqual(request.url?.absoluteString, "https://chatgpt.com/backend-api/wham/remote/control/server/enroll")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.timeoutInterval, 30)
        XCTAssertEqual(request.value(forHTTPHeaderField: "authorization"), "Bearer chatgpt-token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "chatgpt-account-id"), "remote-account")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-codex-installation-id"), "install-123")
        XCTAssertEqual(object, [
            "name": "test-host",
            "os": "macos",
            "arch": "aarch64",
            "app_server_version": "1.2.3",
            "installation_id": "install-123",
        ])
    }

    func testRemoteControlEnrollmentClientDecodesSuccessLikeRust() async throws {
        let target = try RemoteControlURLNormalizer.normalize("https://chatgpt.com/backend-api")
        let client = RemoteControlEnrollmentClient(
            auth: RemoteControlConnectionAuth(
                authProvider: StaticAPIAuthProvider(bearerToken: "chatgpt-token"),
                accountID: "remote-account"
            ),
            installationID: "install-123",
            appServerVersion: "1.2.3",
            serverName: "test-host",
            os: "macos",
            arch: "aarch64",
            send: { _ in
                URLSessionTransportResponse(
                    statusCode: 200,
                    headers: ["x-request-id": "req-1"],
                    body: Data(#"{"server_id":"srv_123","environment_id":"env_123"}"#.utf8)
                )
            }
        )

        let enrollment = try await client.enroll(target: target)

        XCTAssertEqual(enrollment, RemoteControlEnrollment(
            accountID: "remote-account",
            environmentID: "env_123",
            serverID: "srv_123",
            serverName: "test-host"
        ))
    }

    func testRemoteControlEnrollmentClientErrorsPreserveRustPreviewAndHeaders() async throws {
        let target = try RemoteControlURLNormalizer.normalize("https://chatgpt.com/backend-api")
        let client = RemoteControlEnrollmentClient(
            auth: RemoteControlConnectionAuth(
                authProvider: StaticAPIAuthProvider(bearerToken: "chatgpt-token"),
                accountID: "remote-account"
            ),
            installationID: "install-123",
            appServerVersion: "1.2.3",
            serverName: "test-host",
            send: { _ in
                URLSessionTransportResponse(
                    statusCode: 403,
                    headers: ["x-oai-request-id": "req-oai", "cf-ray": "cf-1"],
                    body: Data("  denied  ".utf8)
                )
            }
        )

        do {
            _ = try await client.enroll(target: target)
            XCTFail("enrollment should fail")
        } catch let error as RemoteControlEnrollmentError {
            XCTAssertTrue(error.isPermissionDenied)
            XCTAssertEqual(
                error.description,
                "remote control server enrollment failed at `https://chatgpt.com/backend-api/wham/remote/control/server/enroll`: HTTP 403 Forbidden, request-id: req-oai, cf-ray: cf-1, body: denied"
            )
        }
    }

    func testRemoteControlEnrollmentClientBodyPreviewMatchesRustLimits() {
        typealias Client = RemoteControlEnrollmentClient<StaticAPIAuthProvider>
        XCTAssertEqual(Client.previewResponseBody(Data(" \n\t ".utf8)), "<empty>")
        XCTAssertEqual(Client.previewResponseBody(Data("  ok  ".utf8)), "ok")

        let body = String(repeating: "a", count: 4_095) + "é" + "tail"
        let preview = Client.previewResponseBody(Data(body.utf8))

        XCTAssertEqual(preview, "\(String(repeating: "a", count: 4_095))...")
    }

    func testRemoteControlWebSocketRequestBuilderBuildsRustHandshakeShape() throws {
        let target = try RemoteControlURLNormalizer.normalize("https://chatgpt.com/backend-api")
        let builder = RemoteControlWebSocketRequestBuilder(
            auth: RemoteControlConnectionAuth(
                authProvider: StaticAPIAuthProvider(bearerToken: "chatgpt-token", accountID: "provider-account"),
                accountID: "connection-account"
            ),
            installationID: "install-123"
        )
        let enrollment = RemoteControlEnrollment(
            accountID: "remote-account",
            environmentID: "env_123",
            serverID: "srv_123",
            serverName: "test-server"
        )

        let request = try builder.buildRequest(
            websocketURL: target.websocketURL,
            enrollment: enrollment,
            subscribeCursor: "cursor-1"
        )

        XCTAssertEqual(request.url?.absoluteString, "wss://chatgpt.com/backend-api/wham/remote/control/server")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.value(forHTTPHeaderField: "authorization"), "Bearer chatgpt-token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-codex-server-id"), "srv_123")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-codex-name"), "dGVzdC1zZXJ2ZXI=")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-codex-protocol-version"), "3")
        XCTAssertEqual(request.value(forHTTPHeaderField: "chatgpt-account-id"), "remote-account")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-codex-installation-id"), "install-123")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-codex-subscribe-cursor"), "cursor-1")
    }

    func testRemoteControlWebSocketRequestBuilderRejectsInvalidHeaderLikeRust() throws {
        let target = try RemoteControlURLNormalizer.normalize("https://chatgpt.com/backend-api")
        let builder = RemoteControlWebSocketRequestBuilder(
            auth: RemoteControlConnectionAuth(
                authProvider: StaticAPIAuthProvider(bearerToken: "chatgpt-token"),
                accountID: "connection-account"
            ),
            installationID: "install-123"
        )
        let enrollment = RemoteControlEnrollment(
            accountID: "remote-account",
            environmentID: "env_123",
            serverID: "srv_123",
            serverName: "test-server"
        )

        XCTAssertThrowsError(try builder.buildRequest(
            websocketURL: target.websocketURL,
            enrollment: enrollment,
            subscribeCursor: "bad\ncursor"
        )) { error in
            XCTAssertTrue(
                String(describing: error).hasPrefix("invalid remote control header `x-codex-subscribe-cursor`:")
            )
        }
    }

    func testRemoteControlWebSocketConnectErrorFormatsRustHTTPDetails() {
        let message = RemoteControlWebSocketConnectErrorFormatter.formatHTTPError(
            websocketURL: "wss://chatgpt.com/backend-api/wham/remote/control/server",
            statusCode: 503,
            headers: ["x-trace-id": "trace", "x-region": "us-east-1"],
            body: Data("upstream unavailable".utf8)
        )

        XCTAssertEqual(
            message,
            "failed to connect app-server remote control websocket `wss://chatgpt.com/backend-api/wham/remote/control/server`: HTTP error: 503 Service Unavailable, request-id: <none>, cf-ray: <none>, body: upstream unavailable"
        )
    }

    func testRemoteControlWebSocketConnectorReusesPersistedEnrollmentBeforeEnrolling() async throws {
        let target = try RemoteControlURLNormalizer.normalize("https://chatgpt.com/backend-api")
        let store = RemoteControlEnrollmentMemoryStore()
        let persistedEnrollment = RemoteControlEnrollment(
            accountID: "account_id",
            environmentID: "env_persisted",
            serverID: "srv_e_persisted",
            serverName: "persisted-server"
        )
        try await RemoteControlEnrollmentPersistence.update(
            store: store,
            target: target,
            accountID: "account_id",
            appServerClientName: nil,
            enrollment: persistedEnrollment
        )
        let probe = RemoteControlWebSocketConnectorProbe()
        let connector = RemoteControlWebSocketConnector(
            auth: RemoteControlConnectionAuth(
                authProvider: StaticAPIAuthProvider(bearerToken: "chatgpt-token"),
                accountID: "account_id"
            ),
            installationID: "install-123",
            appServerClientName: nil,
            enroll: { target in
                await probe.enroll(target: target, returning: RemoteControlEnrollment(
                    accountID: "account_id",
                    environmentID: "env_new",
                    serverID: "srv_e_new",
                    serverName: "new-server"
                ))
            },
            connect: { request, enrollment in
                try await probe.connect(request: request, enrollment: enrollment)
            }
        )

        let result = try await connector.connect(
            target: target,
            store: store,
            currentEnrollment: nil,
            subscribeCursor: "cursor-1",
            statusPublisher: RemoteControlStatusPublisherCore(snapshot: RemoteControlStatusSnapshot(
                status: .connecting,
                installationID: "install-123",
                environmentID: nil
            ))
        )

        XCTAssertEqual(result.enrollment, persistedEnrollment)
        XCTAssertEqual(result.statusUpdates, [
            RemoteControlStatusSnapshot(
                status: .connecting,
                installationID: "install-123",
                environmentID: "env_persisted"
            ),
        ])
        let enrollCount = await probe.enrollCount()
        let connectedServerIDs = await probe.connectedServerIDs()
        XCTAssertEqual(enrollCount, 0)
        XCTAssertEqual(connectedServerIDs, ["srv_e_persisted"])
        XCTAssertEqual(result.request.value(forHTTPHeaderField: "x-codex-server-id"), "srv_e_persisted")
        XCTAssertEqual(result.request.value(forHTTPHeaderField: "x-codex-subscribe-cursor"), "cursor-1")
    }

    func testRemoteControlWebSocketConnectorClearsStaleEnrollmentAfter404ThenReenrolls() async throws {
        let target = try RemoteControlURLNormalizer.normalize("https://chatgpt.com/backend-api")
        let store = RemoteControlEnrollmentMemoryStore()
        let staleEnrollment = RemoteControlEnrollment(
            accountID: "account_id",
            environmentID: "env_stale",
            serverID: "srv_e_stale",
            serverName: "stale-server"
        )
        let refreshedEnrollment = RemoteControlEnrollment(
            accountID: "account_id",
            environmentID: "env_refreshed",
            serverID: "srv_e_refreshed",
            serverName: "test-host"
        )
        try await RemoteControlEnrollmentPersistence.update(
            store: store,
            target: target,
            accountID: "account_id",
            appServerClientName: nil,
            enrollment: staleEnrollment
        )
        let probe = RemoteControlWebSocketConnectorProbe(staleServerID: staleEnrollment.serverID)
        let connector = RemoteControlWebSocketConnector(
            auth: RemoteControlConnectionAuth(
                authProvider: StaticAPIAuthProvider(bearerToken: "chatgpt-token"),
                accountID: "account_id"
            ),
            installationID: "install-123",
            appServerClientName: nil,
            enroll: { target in
                await probe.enroll(target: target, returning: refreshedEnrollment)
            },
            connect: { request, enrollment in
                try await probe.connect(request: request, enrollment: enrollment)
            }
        )

        do {
            _ = try await connector.connect(
                target: target,
                store: store,
                currentEnrollment: nil,
                subscribeCursor: nil,
                statusPublisher: RemoteControlStatusPublisherCore(snapshot: RemoteControlStatusSnapshot(
                    status: .connecting,
                    installationID: "install-123",
                    environmentID: nil
                ))
            )
            XCTFail("stale websocket enrollment should fail with HTTP 404 before re-enrolling")
        } catch let error as RemoteControlWebSocketConnectionError {
            XCTAssertEqual(
                error.description,
                "failed to connect app-server remote control websocket `wss://chatgpt.com/backend-api/wham/remote/control/server`: HTTP error: 404 Not Found, request-id: req-404, cf-ray: <none>, body: stale enrollment"
            )
        }

        let clearedEnrollment = try await RemoteControlEnrollmentPersistence.load(
            store: store,
            target: target,
            accountID: "account_id",
            appServerClientName: nil
        )
        XCTAssertNil(clearedEnrollment)

        let result = try await connector.connect(
            target: target,
            store: store,
            currentEnrollment: nil,
            subscribeCursor: nil,
            statusPublisher: RemoteControlStatusPublisherCore(snapshot: RemoteControlStatusSnapshot(
                status: .connecting,
                installationID: "install-123",
                environmentID: nil
            ))
        )

        XCTAssertEqual(result.enrollment, refreshedEnrollment)
        XCTAssertEqual(result.statusUpdates, [
            RemoteControlStatusSnapshot(
                status: .connecting,
                installationID: "install-123",
                environmentID: "env_refreshed"
            ),
        ])
        let enrollCount = await probe.enrollCount()
        let connectedServerIDs = await probe.connectedServerIDs()
        let records = await store.records()
        XCTAssertEqual(enrollCount, 1)
        XCTAssertEqual(connectedServerIDs, ["srv_e_stale", "srv_e_refreshed"])
        XCTAssertEqual(
            records,
            [RemoteControlEnrollmentRecord(
                websocketURL: target.websocketURL,
                accountID: "account_id",
                appServerClientName: nil,
                serverID: "srv_e_refreshed",
                environmentID: "env_refreshed",
                serverName: "test-host"
            )]
        )
    }

    func testRemoteControlClientEnvelopeWireShapesMatchRust() throws {
        let envelope = RemoteControlClientEnvelope(
            event: .clientMessage(message: .request(ExecServerJSONRPCRequest(
                id: .integer(1),
                method: "initialize",
                params: .object(["clientInfo": .object(["name": .string("remote-test-client")])])
            ))),
            clientID: RemoteControlClientID("client-1"),
            streamID: RemoteControlStreamID("stream-1"),
            seqID: 7,
            cursor: "cursor-1"
        )

        let object = try jsonObject(from: envelope)
        XCTAssertEqual(object["type"] as? String, "client_message")
        XCTAssertEqual(object["client_id"] as? String, "client-1")
        XCTAssertEqual(object["stream_id"] as? String, "stream-1")
        XCTAssertEqual(object["seq_id"] as? Int, 7)
        XCTAssertEqual(object["cursor"] as? String, "cursor-1")
        let message = try XCTUnwrap(object["message"] as? [String: Any])
        XCTAssertEqual(message["id"] as? Int, 1)
        XCTAssertEqual(message["method"] as? String, "initialize")
        XCTAssertNil(message["jsonrpc"])

        XCTAssertEqual(try JSONDecoder().decode(RemoteControlClientEnvelope.self, from: JSONEncoder().encode(envelope)), envelope)

        let ack = RemoteControlClientEnvelope(
            event: .ack(segmentID: nil),
            clientID: RemoteControlClientID("client-1"),
            streamID: RemoteControlStreamID("stream-1"),
            seqID: 8,
            cursor: nil
        )
        let ackObject = try jsonObject(from: ack)
        XCTAssertEqual(ackObject["type"] as? String, "ack")
        XCTAssertNil(ackObject["segment_id"])
        XCTAssertNil(ackObject["cursor"])
    }

    func testRemoteControlServerEnvelopeWireShapesMatchRust() throws {
        let envelope = RemoteControlServerEnvelope(
            event: .serverMessage(message: .notification(ExecServerJSONRPCNotification(
                method: "initialized",
                params: .object(["ok": .bool(true)])
            ))),
            clientID: RemoteControlClientID("client-1"),
            streamID: RemoteControlStreamID("stream-1"),
            seqID: 4
        )

        let object = try jsonObject(from: envelope)
        XCTAssertEqual(object["type"] as? String, "server_message")
        XCTAssertEqual(object["client_id"] as? String, "client-1")
        XCTAssertEqual(object["stream_id"] as? String, "stream-1")
        XCTAssertEqual(object["seq_id"] as? Int, 4)
        let message = try XCTUnwrap(object["message"] as? [String: Any])
        XCTAssertEqual(message["method"] as? String, "initialized")
        XCTAssertNil(message["jsonrpc"])

        let pong = RemoteControlServerEnvelope(
            event: .pong(status: .unknown),
            clientID: RemoteControlClientID("client-1"),
            streamID: RemoteControlStreamID("stream-1"),
            seqID: 5
        )
        let pongObject = try jsonObject(from: pong)
        XCTAssertEqual(pongObject["type"] as? String, "pong")
        XCTAssertEqual(pongObject["status"] as? String, "unknown")
        XCTAssertEqual(try JSONDecoder().decode(RemoteControlServerEnvelope.self, from: JSONEncoder().encode(pong)), pong)
    }

    func testRemoteControlOutboundBufferAcksByRustCursorRules() {
        let clientID = RemoteControlClientID("client-1")
        let streamID = RemoteControlStreamID("stream-1")
        let otherStreamID = RemoteControlStreamID("stream-2")
        var buffer = RemoteControlOutboundBuffer()

        let chunk0 = RemoteControlServerEnvelope(
            event: .serverMessageChunk(
                segmentID: 0,
                segmentCount: 2,
                messageSizeBytes: 18,
                messageChunkBase64: "Zmlyc3Q="
            ),
            clientID: clientID,
            streamID: streamID,
            seqID: 1
        )
        let chunk1 = RemoteControlServerEnvelope(
            event: .serverMessageChunk(
                segmentID: 1,
                segmentCount: 2,
                messageSizeBytes: 18,
                messageChunkBase64: "c2Vjb25k"
            ),
            clientID: clientID,
            streamID: streamID,
            seqID: 1
        )
        let nextMessage = RemoteControlServerEnvelope(
            event: .serverMessage(message: .notification(ExecServerJSONRPCNotification(method: "initialized"))),
            clientID: clientID,
            streamID: streamID,
            seqID: 2
        )
        let otherStreamMessage = RemoteControlServerEnvelope(
            event: .pong(status: .active),
            clientID: clientID,
            streamID: otherStreamID,
            seqID: 1
        )

        buffer.insert(chunk0)
        buffer.insert(chunk1)
        buffer.insert(nextMessage)
        buffer.insert(otherStreamMessage)
        XCTAssertEqual(buffer.usedCount, 4)

        buffer.ack(clientID: clientID, streamID: streamID, ackedSeqID: 1, ackedSegmentID: 0)
        XCTAssertEqual(buffer.usedCount, 3)
        XCTAssertFalse(buffer.serverEnvelopes().contains(chunk0))
        XCTAssertTrue(buffer.serverEnvelopes().contains(chunk1))
        XCTAssertTrue(buffer.serverEnvelopes().contains(nextMessage))
        XCTAssertTrue(buffer.serverEnvelopes().contains(otherStreamMessage))

        buffer.ack(clientID: clientID, streamID: streamID, ackedSeqID: 1, ackedSegmentID: nil)
        XCTAssertEqual(buffer.usedCount, 2)
        XCTAssertFalse(buffer.serverEnvelopes().contains(chunk1))
        XCTAssertTrue(buffer.serverEnvelopes().contains(nextMessage))
        XCTAssertTrue(buffer.serverEnvelopes().contains(otherStreamMessage))

        buffer.ack(clientID: clientID, streamID: streamID, ackedSeqID: 2, ackedSegmentID: nil)
        XCTAssertEqual(buffer.usedCount, 1)
        XCTAssertEqual(buffer.serverEnvelopes(), [otherStreamMessage])
    }

    func testRemoteControlServerEnvelopeSplitterPassesThroughSmallAndNonMessageEnvelopesLikeRust() throws {
        let pong = RemoteControlServerEnvelope(
            event: .pong(status: .active),
            clientID: RemoteControlClientID("client-1"),
            streamID: RemoteControlStreamID("stream-1"),
            seqID: 1
        )
        XCTAssertEqual(try RemoteControlServerEnvelopeSplitter.splitForTransport(pong), [pong])

        let smallMessage = RemoteControlServerEnvelope(
            event: .serverMessage(message: .notification(ExecServerJSONRPCNotification(method: "initialized"))),
            clientID: RemoteControlClientID("client-1"),
            streamID: RemoteControlStreamID("stream-1"),
            seqID: 2
        )
        XCTAssertEqual(try RemoteControlServerEnvelopeSplitter.splitForTransport(smallMessage), [smallMessage])
    }

    func testRemoteControlServerEnvelopeSplitterBuildsRustChunkEnvelopeSequence() throws {
        let payload = String(repeating: "x", count: RemoteControlClientMessageObserver.segmentMaxBytes)
        let message = ExecServerJSONRPCMessage.notification(ExecServerJSONRPCNotification(
            method: "initialized",
            params: .object(["payload": .string(payload)])
        ))
        let envelope = RemoteControlServerEnvelope(
            event: .serverMessage(message: message),
            clientID: RemoteControlClientID("client-1"),
            streamID: RemoteControlStreamID("stream-1"),
            seqID: 8
        )

        let chunks = try RemoteControlServerEnvelopeSplitter.splitForTransport(envelope)

        XCTAssertGreaterThan(chunks.count, 1)
        let messageSizeBytes = try JSONEncoder().encode(message).count
        var reassembled = Data()
        for (index, chunkEnvelope) in chunks.enumerated() {
            XCTAssertEqual(chunkEnvelope.clientID, envelope.clientID)
            XCTAssertEqual(chunkEnvelope.streamID, envelope.streamID)
            XCTAssertEqual(chunkEnvelope.seqID, envelope.seqID)
            XCTAssertLessThanOrEqual(try JSONEncoder().encode(chunkEnvelope).count, RemoteControlClientMessageObserver.segmentMaxBytes)

            guard case let .serverMessageChunk(segmentID, segmentCount, chunkMessageSizeBytes, messageChunkBase64) = chunkEnvelope.event else {
                return XCTFail("Expected server_message_chunk")
            }
            XCTAssertEqual(segmentID, index)
            XCTAssertEqual(segmentCount, chunks.count)
            XCTAssertEqual(chunkMessageSizeBytes, messageSizeBytes)
            reassembled.append(try XCTUnwrap(Data(base64Encoded: messageChunkBase64)))
        }

        XCTAssertEqual(try JSONDecoder().decode(ExecServerJSONRPCMessage.self, from: reassembled), message)
    }

    func testRemoteControlClientTrackerOpensAndRoutesVirtualClientsLikeRust() {
        let clientID = RemoteControlClientID("client-1")
        let streamID = RemoteControlStreamID("stream-1")
        let initialize = remoteControlInitializeEnvelope(clientID: clientID, streamID: streamID, seqID: 0)
        let followup = RemoteControlClientEnvelope(
            event: .clientMessage(message: .notification(ExecServerJSONRPCNotification(method: "initialized"))),
            clientID: clientID,
            streamID: streamID,
            seqID: 1,
            cursor: nil
        )
        var tracker = RemoteControlClientTracker()

        XCTAssertEqual(tracker.handleClientEnvelope(initialize, now: 10), [
            .connectionOpened(
                connectionID: RemoteControlVirtualConnectionID(1),
                clientID: clientID,
                streamID: streamID
            ),
            .incomingMessage(
                connectionID: RemoteControlVirtualConnectionID(1),
                message: tryInitializeMessage()
            )
        ])
        XCTAssertEqual(tracker.handleClientEnvelope(followup, now: 11), [
            .incomingMessage(
                connectionID: RemoteControlVirtualConnectionID(1),
                message: .notification(ExecServerJSONRPCNotification(method: "initialized"))
            )
        ])

        let outgoing = ExecServerJSONRPCMessage.notification(ExecServerJSONRPCNotification(method: "configWarning"))
        XCTAssertEqual(
            tracker.enqueueOutgoingMessage(connectionID: RemoteControlVirtualConnectionID(1), message: outgoing),
            RemoteControlQueuedServerEnvelope(event: .serverMessage(message: outgoing), clientID: clientID, streamID: streamID)
        )
        XCTAssertEqual(tracker.activeConnectionCount, 1)
    }

    func testRemoteControlClientTrackerDropsStaleSeqAndReinitializesSameStreamLikeRust() {
        let clientID = RemoteControlClientID("client-1")
        let streamID = RemoteControlStreamID("stream-1")
        let initialize = remoteControlInitializeEnvelope(clientID: clientID, streamID: streamID, seqID: 2)
        var tracker = RemoteControlClientTracker()
        _ = tracker.handleClientEnvelope(initialize, now: 10)

        let stale = RemoteControlClientEnvelope(
            event: .clientMessage(message: .notification(ExecServerJSONRPCNotification(method: "initialized"))),
            clientID: clientID,
            streamID: streamID,
            seqID: 2,
            cursor: nil
        )
        XCTAssertEqual(tracker.handleClientEnvelope(stale, now: 11), [])

        XCTAssertEqual(tracker.handleClientEnvelope(initialize, now: 12), [
            .connectionClosed(connectionID: RemoteControlVirtualConnectionID(1)),
            .connectionOpened(
                connectionID: RemoteControlVirtualConnectionID(2),
                clientID: clientID,
                streamID: streamID
            ),
            .incomingMessage(
                connectionID: RemoteControlVirtualConnectionID(2),
                message: tryInitializeMessage()
            )
        ])
    }

    func testRemoteControlClientTrackerPreservesLegacyStreamAndPingRulesLikeRust() {
        let clientID = RemoteControlClientID("client-1")
        let initialize = remoteControlInitializeEnvelope(clientID: clientID, streamID: nil, seqID: 0)
        var tracker = RemoteControlClientTracker()
        let opened = tracker.handleClientEnvelope(initialize, now: 10)
        guard case let .connectionOpened(connectionID: connectionID, clientID: _, streamID: legacyStreamID) = opened.first else {
            return XCTFail("Expected legacy initialize to open a connection")
        }

        let legacyFollowup = RemoteControlClientEnvelope(
            event: .clientMessage(message: .notification(ExecServerJSONRPCNotification(method: "initialized"))),
            clientID: clientID,
            streamID: nil,
            seqID: 0,
            cursor: nil
        )
        XCTAssertEqual(tracker.handleClientEnvelope(legacyFollowup, now: 11), [
            .incomingMessage(
                connectionID: connectionID,
                message: .notification(ExecServerJSONRPCNotification(method: "initialized"))
            )
        ])

        let activePing = RemoteControlClientEnvelope(
            event: .ping,
            clientID: clientID,
            streamID: nil,
            seqID: nil,
            cursor: nil
        )
        XCTAssertEqual(tracker.handleClientEnvelope(activePing, now: 12), [
            .serverEvent(RemoteControlQueuedServerEnvelope(
                event: .pong(status: .active),
                clientID: clientID,
                streamID: legacyStreamID
            ))
        ])

        let unknownClientID = RemoteControlClientID("missing-client")
        let unknownPing = RemoteControlClientEnvelope(
            event: .ping,
            clientID: unknownClientID,
            streamID: nil,
            seqID: nil,
            cursor: nil
        )
        let unknownEffects = tracker.handleClientEnvelope(unknownPing, now: 13)
        guard case let .serverEvent(unknownPong) = unknownEffects.first else {
            return XCTFail("Expected ping from an unknown client to queue an unknown pong")
        }
        XCTAssertEqual(unknownEffects.count, 1)
        XCTAssertEqual(unknownPong.event, .pong(status: .unknown))
        XCTAssertEqual(unknownPong.clientID, unknownClientID)
        XCTAssertFalse(unknownPong.streamID.rawValue.isEmpty)
    }

    func testRemoteControlClientTrackerClosesExpiredClientsLikeRust() {
        let clientID = RemoteControlClientID("client-1")
        let streamID = RemoteControlStreamID("stream-1")
        var tracker = RemoteControlClientTracker()
        _ = tracker.handleClientEnvelope(
            remoteControlInitializeEnvelope(clientID: clientID, streamID: streamID, seqID: 0),
            now: 10
        )

        XCTAssertEqual(
            tracker.closeExpiredClients(now: 10 + RemoteControlClientTracker.idleTimeoutSeconds - 1),
            []
        )
        XCTAssertEqual(
            tracker.closeExpiredClients(now: 10 + RemoteControlClientTracker.idleTimeoutSeconds),
            [.connectionClosed(connectionID: RemoteControlVirtualConnectionID(1))]
        )
        XCTAssertEqual(tracker.activeConnectionCount, 0)
    }

    func testRemoteControlWebsocketReaderCoreRoutesTextFramesThroughStateAndTrackerLikeRust() throws {
        let clientID = RemoteControlClientID("client-1")
        let streamID = RemoteControlStreamID("stream-1")
        let initialize = RemoteControlClientEnvelope(
            event: .clientMessage(message: tryInitializeMessage()),
            clientID: clientID,
            streamID: streamID,
            seqID: 0,
            cursor: "cursor-1"
        )
        var reader = RemoteControlWebsocketReaderCore()
        var state = RemoteControlWebsocketState()
        var tracker = RemoteControlClientTracker()

        XCTAssertEqual(
            try reader.process(
                .text(try remoteControlEnvelopeText(initialize)),
                state: &state,
                clientTracker: &tracker,
                now: 10
            ),
            [
                .connectionOpened(
                    connectionID: RemoteControlVirtualConnectionID(1),
                    clientID: clientID,
                    streamID: streamID
                ),
                .incomingMessage(
                    connectionID: RemoteControlVirtualConnectionID(1),
                    message: tryInitializeMessage()
                )
            ]
        )
        XCTAssertEqual(state.subscribeCursor, "cursor-1")

        let queued = RemoteControlQueuedServerEnvelope(
            event: .pong(status: .active),
            clientID: clientID,
            streamID: streamID
        )
        XCTAssertEqual(try state.enqueueServerEvent(queued).count, 1)
        XCTAssertEqual(state.bufferedEnvelopeCount, 1)

        let ack = RemoteControlClientEnvelope(
            event: .ack(segmentID: nil),
            clientID: clientID,
            streamID: streamID,
            seqID: 1,
            cursor: "cursor-2"
        )
        XCTAssertEqual(
            try reader.process(
                .text(try remoteControlEnvelopeText(ack)),
                state: &state,
                clientTracker: &tracker,
                now: 11
            ),
            []
        )
        XCTAssertEqual(state.subscribeCursor, "cursor-2")
        XCTAssertEqual(state.bufferedEnvelopeCount, 0)
    }

    func testRemoteControlWebsocketReaderCoreIgnoresUnsupportedFramesAndReportsRustErrors() throws {
        var reader = RemoteControlWebsocketReaderCore()
        var state = RemoteControlWebsocketState()
        var tracker = RemoteControlClientTracker()

        XCTAssertEqual(try reader.process(.text("{"), state: &state, clientTracker: &tracker), [])
        XCTAssertEqual(try reader.process(.binary(Data([1, 2, 3])), state: &state, clientTracker: &tracker), [])
        XCTAssertEqual(try reader.process(.ping, state: &state, clientTracker: &tracker), [])
        XCTAssertEqual(try reader.process(.pong, state: &state, clientTracker: &tracker), [])

        XCTAssertThrowsError(try reader.process(.streamEnded, state: &state, clientTracker: &tracker)) { error in
            XCTAssertEqual(String(describing: error), "websocket stream ended")
        }
        XCTAssertThrowsError(try reader.process(.close, state: &state, clientTracker: &tracker)) { error in
            XCTAssertEqual(String(describing: error), "websocket disconnected")
        }
        XCTAssertThrowsError(try reader.process(.readError("bad frame"), state: &state, clientTracker: &tracker)) { error in
            XCTAssertEqual(String(describing: error), "failed to read from websocket: bad frame")
        }
    }

    func testRemoteControlWebsocketReaderCoreInvalidatesClientChunksOnCloseLikeRust() throws {
        let clientID = "client-1"
        let streamID = "stream-1"
        let message = ExecServerJSONRPCMessage.notification(ExecServerJSONRPCNotification(method: "initialized"))
        let raw = try JSONEncoder().encode(message)
        let split = raw.count / 2
        let firstChunk = remoteControlClientChunkEnvelope(
            clientID: clientID,
            streamID: streamID,
            seqID: 4,
            segmentID: 0,
            segmentCount: 2,
            messageSizeBytes: raw.count,
            chunk: raw.prefix(split)
        )
        let secondChunk = remoteControlClientChunkEnvelope(
            clientID: clientID,
            streamID: streamID,
            seqID: 4,
            segmentID: 1,
            segmentCount: 2,
            messageSizeBytes: raw.count,
            chunk: raw.suffix(raw.count - split)
        )
        var reader = RemoteControlWebsocketReaderCore()
        var state = RemoteControlWebsocketState()
        var tracker = RemoteControlClientTracker()

        XCTAssertEqual(
            try reader.process(
                .text(try remoteControlEnvelopeText(firstChunk)),
                state: &state,
                clientTracker: &tracker
            ),
            []
        )
        XCTAssertEqual(
            try reader.process(
                .text(try remoteControlEnvelopeText(secondChunk)),
                state: &state,
                clientTracker: &tracker
            ),
            []
        )
        XCTAssertEqual(
            state.observeClientEnvelope(firstChunk, wireSizeBytes: try JSONEncoder().encode(firstChunk).count),
            .dropped
        )

        let close = RemoteControlClientEnvelope(
            event: .clientClosed,
            clientID: RemoteControlClientID(clientID),
            streamID: nil,
            seqID: nil,
            cursor: nil
        )
        XCTAssertEqual(
            try reader.process(
                .text(try remoteControlEnvelopeText(close)),
                state: &state,
                clientTracker: &tracker
            ),
            []
        )
        XCTAssertEqual(
            state.observeClientEnvelope(firstChunk, wireSizeBytes: try JSONEncoder().encode(firstChunk).count),
            .pending
        )
    }

    func testRemoteControlWebsocketWriterCoreReplaysBufferedServerFramesLikeRust() throws {
        let clientID = RemoteControlClientID("client-1")
        let streamID = RemoteControlStreamID("stream-1")
        let queued = RemoteControlQueuedServerEnvelope(
            event: .pong(status: .active),
            clientID: clientID,
            streamID: streamID
        )
        var writer = RemoteControlWebsocketWriterCore()
        var state = RemoteControlWebsocketState()

        let firstWrite = try writer.process(.queuedServerEvent(queued), state: &state)
        XCTAssertEqual(firstWrite.count, 1)
        XCTAssertEqual(state.bufferedEnvelopeCount, 1)

        let firstEnvelope = try remoteControlServerEnvelope(from: firstWrite[0])
        XCTAssertEqual(
            firstEnvelope,
            RemoteControlServerEnvelope(
                event: .pong(status: .active),
                clientID: clientID,
                streamID: streamID,
                seqID: 1
            )
        )

        let replay = try writer.process(.connectionOpened, state: &state)
        XCTAssertEqual(replay, firstWrite)
        XCTAssertEqual(state.bufferedEnvelopeCount, 1)
    }

    func testRemoteControlWebsocketWriterCoreAppliesRustCapacityAndPingRules() throws {
        let clientID = RemoteControlClientID("client-1")
        let streamID = RemoteControlStreamID("stream-1")
        let queued = RemoteControlQueuedServerEnvelope(
            event: .pong(status: .active),
            clientID: clientID,
            streamID: streamID
        )
        var writer = RemoteControlWebsocketWriterCore()
        var state = RemoteControlWebsocketState()

        XCTAssertEqual(try writer.process(.pingTick, state: &state), [.ping])
        for index in 0..<RemoteControlWebsocketState.channelCapacity {
            let frames = try writer.process(.queuedServerEvent(queued), state: &state)
            XCTAssertEqual(frames.count, 1)
            XCTAssertEqual(try remoteControlServerEnvelope(from: frames[0]).seqID, UInt64(index + 1))
        }
        XCTAssertEqual(state.bufferedEnvelopeCount, RemoteControlWebsocketState.channelCapacity)
        XCTAssertFalse(state.outboundHasCapacity)

        XCTAssertEqual(try writer.process(.queuedServerEvent(queued), state: &state), [])
        XCTAssertEqual(state.bufferedEnvelopeCount, RemoteControlWebsocketState.channelCapacity)
    }

    func testRemoteControlWebsocketConnectionCoreRoutesWriterReaderAndStopEventsLikeRust() throws {
        let clientID = RemoteControlClientID("client-1")
        let streamID = RemoteControlStreamID("stream-1")
        let queued = RemoteControlQueuedServerEnvelope(
            event: .pong(status: .active),
            clientID: clientID,
            streamID: streamID
        )
        var core = RemoteControlWebsocketConnectionCore(statusPublisher: RemoteControlStatusPublisherCore(
            snapshot: RemoteControlStatusSnapshot(
                status: .connected,
                installationID: "install-1",
                environmentID: "env-1"
            )
        ))
        var state = RemoteControlWebsocketState()
        var tracker = RemoteControlClientTracker()

        let queuedStep = try core.process(.queuedServerEvent(queued), state: &state, clientTracker: &tracker)
        XCTAssertEqual(queuedStep.frames.count, 1)
        XCTAssertNil(queuedStep.end)

        let replayStep = try core.process(.connectionOpened, state: &state, clientTracker: &tracker)
        XCTAssertEqual(replayStep.frames, queuedStep.frames)
        XCTAssertEqual(
            try remoteControlServerEnvelope(from: replayStep.frames[0]),
            RemoteControlServerEnvelope(
                event: .pong(status: .active),
                clientID: clientID,
                streamID: streamID,
                seqID: 1
            )
        )

        XCTAssertEqual(
            try core.process(.pingTick, state: &state, clientTracker: &tracker).frames,
            [.ping]
        )

        let initialize = remoteControlInitializeEnvelope(clientID: clientID, streamID: streamID, seqID: 0)
        XCTAssertEqual(
            try core.process(
                .incoming(.text(try remoteControlEnvelopeText(initialize)), now: 10),
                state: &state,
                clientTracker: &tracker
            ).trackerEffects,
            [
                .connectionOpened(
                    connectionID: RemoteControlVirtualConnectionID(1),
                    clientID: clientID,
                    streamID: streamID
                ),
                .incomingMessage(
                    connectionID: RemoteControlVirtualConnectionID(1),
                    message: tryInitializeMessage()
                )
            ]
        )
        XCTAssertNil(try core.process(.incoming(.pong, now: 11), state: &state, clientTracker: &tracker).end)
        XCTAssertEqual(
            try core.process(.incoming(.close, now: 12), state: &state, clientTracker: &tracker).end,
            .reconnect("websocket disconnected")
        )
        XCTAssertEqual(
            try core.process(.workerEnded, state: &state, clientTracker: &tracker).end,
            .reconnect("remote control websocket worker stopped")
        )

        let disabledStep = try core.process(.disabled, state: &state, clientTracker: &tracker)
        XCTAssertEqual(disabledStep.end, .disabled)
        XCTAssertEqual(disabledStep.statusUpdates, [
            RemoteControlStatusSnapshot(status: .disabled, installationID: "install-1", environmentID: nil)
        ])
        XCTAssertEqual(try core.process(.shutdown, state: &state, clientTracker: &tracker).end, .shutdown)
    }

    func testRemoteControlWebsocketConnectionCoreSweepsIdleClientsAndPongDeadlineLikeRust() throws {
        let clientID = RemoteControlClientID("client-1")
        let streamID = RemoteControlStreamID("stream-1")
        let message = ExecServerJSONRPCMessage.notification(ExecServerJSONRPCNotification(method: "initialized"))
        let raw = try JSONEncoder().encode(message)
        let split = raw.count / 2
        let firstChunk = remoteControlClientChunkEnvelope(
            clientID: clientID.rawValue,
            streamID: streamID.rawValue,
            seqID: 4,
            segmentID: 0,
            segmentCount: 2,
            messageSizeBytes: raw.count,
            chunk: raw.prefix(split)
        )
        let secondChunk = remoteControlClientChunkEnvelope(
            clientID: clientID.rawValue,
            streamID: streamID.rawValue,
            seqID: 4,
            segmentID: 1,
            segmentCount: 2,
            messageSizeBytes: raw.count,
            chunk: raw.suffix(raw.count - split)
        )
        var core = RemoteControlWebsocketConnectionCore(statusPublisher: RemoteControlStatusPublisherCore(
            snapshot: RemoteControlStatusSnapshot(status: .connected, installationID: "install-1", environmentID: nil)
        ))
        var state = RemoteControlWebsocketState()
        var tracker = RemoteControlClientTracker()

        _ = try core.process(
            .incoming(.text(try remoteControlEnvelopeText(remoteControlInitializeEnvelope(
                clientID: clientID,
                streamID: streamID,
                seqID: 0
            ))), now: 10),
            state: &state,
            clientTracker: &tracker
        )
        XCTAssertEqual(
            try core.process(.incoming(.text(try remoteControlEnvelopeText(firstChunk)), now: 11), state: &state, clientTracker: &tracker),
            RemoteControlWebsocketConnectionStep()
        )
        XCTAssertEqual(
            try core.process(.incoming(.text(try remoteControlEnvelopeText(secondChunk)), now: 12), state: &state, clientTracker: &tracker).trackerEffects,
            [
                .incomingMessage(
                    connectionID: RemoteControlVirtualConnectionID(1),
                    message: message
                )
            ]
        )
        XCTAssertEqual(
            state.observeClientEnvelope(firstChunk, wireSizeBytes: try JSONEncoder().encode(firstChunk).count),
            .dropped
        )

        let notExpired = try core.process(
            .idleSweep(now: 12 + RemoteControlClientTracker.idleTimeoutSeconds - 1),
            state: &state,
            clientTracker: &tracker
        )
        XCTAssertEqual(notExpired, RemoteControlWebsocketConnectionStep())

        let expired = try core.process(
            .idleSweep(now: 12 + RemoteControlClientTracker.idleTimeoutSeconds),
            state: &state,
            clientTracker: &tracker
        )
        XCTAssertEqual(expired.trackerEffects, [
            .connectionClosed(connectionID: RemoteControlVirtualConnectionID(1))
        ])
        XCTAssertEqual(
            state.observeClientEnvelope(firstChunk, wireSizeBytes: try JSONEncoder().encode(firstChunk).count),
            .pending
        )
        XCTAssertEqual(
            try core.process(.pongDeadline, state: &state, clientTracker: &tracker).end,
            .reconnect("remote control websocket pong timeout")
        )
    }

    func testRemoteControlWebSocketSessionRunnerSendsFramesAndClosesOnTerminalEventsLikeRust() async throws {
        let clientID = RemoteControlClientID("client-1")
        let streamID = RemoteControlStreamID("stream-1")
        let transport = RemoteControlRecordingWebSocketTransport()
        var runner = RemoteControlWebSocketSessionRunner(
            transport: transport,
            statusPublisher: RemoteControlStatusPublisherCore(snapshot: RemoteControlStatusSnapshot(
                status: .connected,
                installationID: "install-1",
                environmentID: "env-1"
            ))
        )
        var state = RemoteControlWebsocketState()
        var tracker = RemoteControlClientTracker()
        let queued = RemoteControlQueuedServerEnvelope(
            event: .pong(status: .active),
            clientID: clientID,
            streamID: streamID
        )

        let queuedStep = try await runner.process(.queuedServerEvent(queued), state: &state, clientTracker: &tracker)
        XCTAssertNil(queuedStep.end)
        let sentFrameCount = await transport.sentFrameCount()
        let sentFrames = await transport.sentFrames()
        XCTAssertEqual(sentFrameCount, 1)
        XCTAssertEqual(try remoteControlServerEnvelope(from: sentFrames[0]), RemoteControlServerEnvelope(
            event: .pong(status: .active),
            clientID: clientID,
            streamID: streamID,
            seqID: 1
        ))

        let pingStep = try await runner.process(.pingTick, state: &state, clientTracker: &tracker)
        XCTAssertEqual(pingStep.frames, [.ping])
        let sentFramesAfterPing = await transport.sentFrames()
        XCTAssertEqual(sentFramesAfterPing.suffix(1), [.ping])

        let disabledStep = try await runner.process(.disabled, state: &state, clientTracker: &tracker)
        XCTAssertEqual(disabledStep.end, .disabled)
        XCTAssertEqual(disabledStep.statusUpdates, [
            RemoteControlStatusSnapshot(status: .disabled, installationID: "install-1", environmentID: nil)
        ])
        let closeCount = await transport.closeCount()
        XCTAssertEqual(closeCount, 1)
    }

    func testRemoteControlWebSocketSessionRunnerReceivesAndMapsTransportFailuresLikeRust() async throws {
        let clientID = RemoteControlClientID("client-1")
        let streamID = RemoteControlStreamID("stream-1")
        let initialize = remoteControlInitializeEnvelope(clientID: clientID, streamID: streamID, seqID: 0)
        let transport = RemoteControlRecordingWebSocketTransport(incoming: [
            .text(try remoteControlEnvelopeText(initialize))
        ])
        var runner = RemoteControlWebSocketSessionRunner(
            transport: transport,
            statusPublisher: RemoteControlStatusPublisherCore(snapshot: RemoteControlStatusSnapshot(
                status: .connected,
                installationID: "install-1",
                environmentID: nil
            ))
        )
        var state = RemoteControlWebsocketState()
        var tracker = RemoteControlClientTracker()

        let receiveStep = try await runner.receive(state: &state, clientTracker: &tracker, now: 10)
        XCTAssertEqual(
            receiveStep.trackerEffects,
            [
                .connectionOpened(
                    connectionID: RemoteControlVirtualConnectionID(1),
                    clientID: clientID,
                    streamID: streamID
                ),
                .incomingMessage(
                    connectionID: RemoteControlVirtualConnectionID(1),
                    message: tryInitializeMessage()
                )
            ]
        )

        await transport.setReceiveError("bad frame")
        let receiveFailure = try await runner.receive(state: &state, clientTracker: &tracker, now: 11)
        XCTAssertEqual(receiveFailure.end, .reconnect("failed to read from websocket: bad frame"))
        let closeCount = await transport.closeCount()
        XCTAssertEqual(closeCount, 1)

        let failingSendTransport = RemoteControlRecordingWebSocketTransport(sendError: "send failed")
        var failingRunner = RemoteControlWebSocketSessionRunner(
            transport: failingSendTransport,
            statusPublisher: RemoteControlStatusPublisherCore(snapshot: RemoteControlStatusSnapshot(
                status: .connected,
                installationID: "install-1",
                environmentID: nil
            ))
        )
        let sendFailure = try await failingRunner.process(
            .queuedServerEvent(RemoteControlQueuedServerEnvelope(event: .pong(status: .active), clientID: clientID, streamID: streamID)),
            state: &state,
            clientTracker: &tracker
        )
        XCTAssertEqual(sendFailure.end, .reconnect("send failed"))
        let failingSendCloseCount = await failingSendTransport.closeCount()
        XCTAssertEqual(failingSendCloseCount, 1)
    }

    func testRemoteControlWebsocketStateSequencesSplitsAndBuffersLikeRust() throws {
        let clientID = RemoteControlClientID("client-1")
        let streamID = RemoteControlStreamID("stream-1")
        var state = RemoteControlWebsocketState()
        let largePayload = String(repeating: "x", count: RemoteControlClientMessageObserver.segmentMaxBytes)
        let largeMessage = ExecServerJSONRPCMessage.notification(ExecServerJSONRPCNotification(
            method: "initialized",
            params: .object(["payload": .string(largePayload)])
        ))

        let firstEnvelopes = try state.enqueueServerEvent(RemoteControlQueuedServerEnvelope(
            event: .serverMessage(message: largeMessage),
            clientID: clientID,
            streamID: streamID
        ))
        let secondEnvelopes = try state.enqueueServerEvent(RemoteControlQueuedServerEnvelope(
            event: .pong(status: .active),
            clientID: clientID,
            streamID: streamID
        ))

        XCTAssertGreaterThan(firstEnvelopes.count, 1)
        XCTAssertTrue(firstEnvelopes.allSatisfy { $0.seqID == 1 })
        XCTAssertEqual(secondEnvelopes, [
            RemoteControlServerEnvelope(
                event: .pong(status: .active),
                clientID: clientID,
                streamID: streamID,
                seqID: 2
            )
        ])
        XCTAssertEqual(state.bufferedEnvelopeCount, firstEnvelopes.count + secondEnvelopes.count)
        XCTAssertEqual(state.replayBufferedServerEnvelopes(), firstEnvelopes + secondEnvelopes)
    }

    func testRemoteControlWebsocketStateAppliesRustAckCursorAndSubscribeCursorRules() throws {
        let clientID = RemoteControlClientID("client-1")
        let streamID = RemoteControlStreamID("stream-1")
        var state = RemoteControlWebsocketState()
        let payload = String(repeating: "x", count: RemoteControlClientMessageObserver.segmentMaxBytes)
        let chunks = try state.enqueueServerEvent(RemoteControlQueuedServerEnvelope(
            event: .serverMessage(message: .notification(ExecServerJSONRPCNotification(
                method: "initialized",
                params: .object(["payload": .string(payload)])
            ))),
            clientID: clientID,
            streamID: streamID
        ))
        XCTAssertGreaterThan(chunks.count, 1)

        let pendingChunk = RemoteControlClientEnvelope(
            event: .clientMessageChunk(
                segmentID: 0,
                segmentCount: 2,
                messageSizeBytes: 18,
                messageChunkBase64: "eyJtZXRob2QiOiJpbml0"
            ),
            clientID: clientID,
            streamID: streamID,
            seqID: 9,
            cursor: "cursor-before-complete"
        )
        XCTAssertEqual(
            state.observeClientEnvelope(pendingChunk, wireSizeBytes: try JSONEncoder().encode(pendingChunk).count),
            .pending
        )
        XCTAssertNil(state.subscribeCursor)

        let ackChunk0 = RemoteControlClientEnvelope(
            event: .ack(segmentID: 0),
            clientID: clientID,
            streamID: streamID,
            seqID: 1,
            cursor: "cursor-1"
        )
        XCTAssertEqual(
            state.observeClientEnvelope(ackChunk0, wireSizeBytes: try JSONEncoder().encode(ackChunk0).count),
            .forward(ackChunk0)
        )
        XCTAssertEqual(state.subscribeCursor, "cursor-1")
        XCTAssertEqual(state.bufferedEnvelopeCount, chunks.count - 1)
        XCTAssertFalse(state.replayBufferedServerEnvelopes().contains(chunks[0]))

        let ackRest = RemoteControlClientEnvelope(
            event: .ack(segmentID: nil),
            clientID: clientID,
            streamID: streamID,
            seqID: 1,
            cursor: nil
        )
        XCTAssertEqual(
            state.observeClientEnvelope(ackRest, wireSizeBytes: try JSONEncoder().encode(ackRest).count),
            .forward(ackRest)
        )
        XCTAssertEqual(state.subscribeCursor, "cursor-1")
        XCTAssertEqual(state.bufferedEnvelopeCount, 0)
        XCTAssertEqual(state.replayBufferedServerEnvelopes(), [])
    }

    func testRemoteControlClientMessageObserverReassemblesChunksLikeRust() throws {
        var observer = RemoteControlClientMessageObserver()
        let message = ExecServerJSONRPCMessage.notification(ExecServerJSONRPCNotification(method: "initialized"))
        let raw = try JSONEncoder().encode(message)
        let split = raw.count / 2
        let firstChunk = remoteControlClientChunkEnvelope(
            seqID: 4,
            segmentID: 0,
            segmentCount: 2,
            messageSizeBytes: raw.count,
            chunk: raw.prefix(split)
        )
        let secondChunk = remoteControlClientChunkEnvelope(
            seqID: 4,
            segmentID: 1,
            segmentCount: 2,
            messageSizeBytes: raw.count,
            chunk: raw.suffix(raw.count - split)
        )

        XCTAssertEqual(try observeRemoteControlClientMessage(&observer, firstChunk), .pending)
        XCTAssertEqual(
            try observeRemoteControlClientMessage(&observer, secondChunk),
            .forward(RemoteControlClientEnvelope(
                event: .clientMessage(message: message),
                clientID: RemoteControlClientID("client-1"),
                streamID: RemoteControlStreamID("stream-1"),
                seqID: 4,
                cursor: nil
            ))
        )
        XCTAssertEqual(try observeRemoteControlClientMessage(&observer, firstChunk), .dropped)
    }

    func testRemoteControlClientMessageObserverDropsDuplicateChunksWhilePendingLikeRust() throws {
        var observer = RemoteControlClientMessageObserver()
        let firstChunk = remoteControlClientChunkEnvelope(
            seqID: 4,
            segmentID: 0,
            segmentCount: 2,
            messageSizeBytes: 2,
            chunk: Data("x".utf8)
        )
        let secondChunk = remoteControlClientChunkEnvelope(
            seqID: 4,
            segmentID: 1,
            segmentCount: 2,
            messageSizeBytes: 2,
            chunk: Data("y".utf8)
        )

        XCTAssertEqual(try observeRemoteControlClientMessage(&observer, firstChunk), .pending)
        XCTAssertEqual(try observeRemoteControlClientMessage(&observer, firstChunk), .dropped)
        XCTAssertEqual(try observeRemoteControlClientMessage(&observer, secondChunk), .dropped)
        XCTAssertEqual(try observeRemoteControlClientMessage(&observer, firstChunk), .pending)
    }

    func testRemoteControlClientMessageObserverAllowsReplayAfterOutOfOrderOrInvalidLaterChunkLikeRust() throws {
        var outOfOrderObserver = RemoteControlClientMessageObserver()
        let firstChunk = remoteControlClientChunkEnvelope(
            seqID: 4,
            segmentID: 0,
            segmentCount: 2,
            messageSizeBytes: 2,
            chunk: Data("x".utf8)
        )
        let secondChunk = remoteControlClientChunkEnvelope(
            seqID: 4,
            segmentID: 1,
            segmentCount: 2,
            messageSizeBytes: 2,
            chunk: Data("y".utf8)
        )

        XCTAssertEqual(try observeRemoteControlClientMessage(&outOfOrderObserver, secondChunk), .dropped)
        XCTAssertEqual(try observeRemoteControlClientMessage(&outOfOrderObserver, firstChunk), .pending)

        var invalidLaterObserver = RemoteControlClientMessageObserver()
        let invalidSecondChunk = remoteControlClientChunkEnvelope(
            seqID: 4,
            segmentID: 1,
            segmentCount: 2,
            messageSizeBytes: 2,
            chunk: Data()
        )

        XCTAssertEqual(try observeRemoteControlClientMessage(&invalidLaterObserver, firstChunk), .pending)
        XCTAssertEqual(try observeRemoteControlClientMessage(&invalidLaterObserver, invalidSecondChunk), .dropped)
        XCTAssertEqual(try observeRemoteControlClientMessage(&invalidLaterObserver, firstChunk), .pending)
    }

    func testRemoteControlClientMessageObserverOversizedDuplicateDoesNotDropCurrentAssemblyLikeRust() throws {
        var observer = RemoteControlClientMessageObserver()
        let message = ExecServerJSONRPCMessage.notification(ExecServerJSONRPCNotification(method: "initialized"))
        let raw = try JSONEncoder().encode(message)
        let split = raw.count / 2
        let firstChunk = remoteControlClientChunkEnvelope(
            seqID: 8,
            segmentID: 0,
            segmentCount: 2,
            messageSizeBytes: raw.count,
            chunk: raw.prefix(split)
        )
        let secondChunk = remoteControlClientChunkEnvelope(
            seqID: 8,
            segmentID: 1,
            segmentCount: 2,
            messageSizeBytes: raw.count,
            chunk: raw.suffix(raw.count - split)
        )

        XCTAssertEqual(try observeRemoteControlClientMessage(&observer, firstChunk), .pending)
        XCTAssertEqual(
            observer.observe(firstChunk, wireSizeBytes: RemoteControlClientMessageObserver.segmentMaxBytes + 1),
            .dropped
        )
        XCTAssertEqual(
            try observeRemoteControlClientMessage(&observer, secondChunk),
            .forward(RemoteControlClientEnvelope(
                event: .clientMessage(message: message),
                clientID: RemoteControlClientID("client-1"),
                streamID: RemoteControlStreamID("stream-1"),
                seqID: 8,
                cursor: nil
            ))
        )
    }

    func testRemoteControlClientMessageObserverInvalidationClearsCompletedChunkCursorLikeRust() throws {
        var observer = RemoteControlClientMessageObserver()
        let clientID = RemoteControlClientID("client-1")
        let streamID = RemoteControlStreamID("stream-1")

        XCTAssertEqual(
            try observeRemoteControlClientMessage(&observer, remoteControlClientChunkEnvelope(
                seqID: 4,
                segmentID: 0,
                segmentCount: 2,
                messageSizeBytes: 2,
                chunk: Data("x".utf8)
            )),
            .pending
        )
        observer.invalidateStream(clientID: clientID, streamID: streamID)

        XCTAssertEqual(
            try observeRemoteControlClientMessage(&observer, remoteControlClientChunkEnvelope(
                seqID: 1,
                segmentID: 0,
                segmentCount: 2,
                messageSizeBytes: 2,
                chunk: Data("x".utf8)
            )),
            .pending
        )
    }

    func testRemoteControlAuthLoaderReloadsMissingAuthOnceLikeRust() async throws {
        let authStore = RemoteControlAuthSequence([
            nil,
            AuthDotJSON(
                authMode: .chatGPT,
                openAIAPIKey: nil,
                tokens: AuthTokenData(
                    idToken: "header.payload.signature",
                    accessToken: "fresh-token",
                    refreshToken: "refresh-token",
                    accountID: "account_id"
                ),
                lastRefresh: nil
            ),
        ])
        let loader = RemoteControlAuthLoader(
            loadAuth: { await authStore.load() },
            reloadAuth: { await authStore.reload() }
        )

        let auth = try await loader.load()

        XCTAssertEqual(auth.authProvider.bearerToken, "fresh-token")
        XCTAssertEqual(auth.authProvider.accountID, "account_id")
        XCTAssertEqual(auth.accountID, "account_id")
        let reloadCount = await authStore.reloadCount()
        XCTAssertEqual(reloadCount, 1)
    }

    func testRemoteControlAuthLoaderRejectsAPIKeyAuthLikeRust() async {
        let authStore = RemoteControlAuthSequence([
            AuthDotJSON(authMode: .apiKey, openAIAPIKey: "sk-api", tokens: nil, lastRefresh: nil),
        ])
        let loader = RemoteControlAuthLoader(
            loadAuth: { await authStore.load() },
            reloadAuth: { await authStore.reload() }
        )

        do {
            _ = try await loader.load()
            XCTFail("Expected remote-control auth loading to reject API key auth")
        } catch {
            XCTAssertEqual(
                String(describing: error),
                "remote control requires ChatGPT authentication; API key auth is not supported"
            )
        }
    }

    func testRemoteControlAuthLoaderWaitsForAccountIDAfterReloadLikeRust() async {
        let authWithoutAccount = AuthDotJSON(
            authMode: .chatGPT,
            openAIAPIKey: nil,
            tokens: AuthTokenData(
                idToken: "header.payload.signature",
                accessToken: "token",
                refreshToken: "refresh-token",
                accountID: nil
            ),
            lastRefresh: nil
        )
        let authStore = RemoteControlAuthSequence([authWithoutAccount, authWithoutAccount])
        let loader = RemoteControlAuthLoader(
            loadAuth: { await authStore.load() },
            reloadAuth: { await authStore.reload() }
        )

        do {
            _ = try await loader.load()
            XCTFail("Expected remote-control auth loading to wait for a ChatGPT account id")
        } catch {
            XCTAssertEqual(
                String(describing: error),
                "remote control enrollment is waiting for a ChatGPT account id"
            )
        }
        let reloadCount = await authStore.reloadCount()
        XCTAssertEqual(reloadCount, 1)
    }

    func testRemoteControlEnrollmentPersistenceLoadsAndUpdatesRustCacheShape() async throws {
        let target = try RemoteControlURLNormalizer.normalize("https://chatgpt.com/backend-api")
        let store = RemoteControlEnrollmentMemoryStore()
        let enrollment = RemoteControlEnrollment(
            accountID: "account_id",
            environmentID: "env_123",
            serverID: "srv_123",
            serverName: "test-server"
        )

        try await RemoteControlEnrollmentPersistence.update(
            store: store,
            target: target,
            accountID: "account_id",
            appServerClientName: "desktop",
            enrollment: enrollment
        )
        let loaded = try await RemoteControlEnrollmentPersistence.load(
            store: store,
            target: target,
            accountID: "account_id",
            appServerClientName: "desktop"
        )

        XCTAssertEqual(loaded, enrollment)
        let records = await store.records()
        XCTAssertEqual(records, [
            RemoteControlEnrollmentRecord(
                websocketURL: target.websocketURL,
                accountID: "account_id",
                appServerClientName: "desktop",
                serverID: "srv_123",
                environmentID: "env_123",
                serverName: "test-server"
            ),
        ])

        try await RemoteControlEnrollmentPersistence.update(
            store: store,
            target: target,
            accountID: "account_id",
            appServerClientName: "desktop",
            enrollment: nil
        )
        let cleared = try await RemoteControlEnrollmentPersistence.load(
            store: store,
            target: target,
            accountID: "account_id",
            appServerClientName: "desktop"
        )

        XCTAssertNil(cleared)
    }

    func testRemoteControlEnrollmentPersistenceErrorsMatchRust() async throws {
        let target = try RemoteControlURLNormalizer.normalize("https://chatgpt.com/backend-api")

        do {
            _ = try await RemoteControlEnrollmentPersistence.load(
                store: nil,
                target: target,
                accountID: "account_id",
                appServerClientName: nil
            )
            XCTFail("Expected disabled state DB to reject enrollment cache loads")
        } catch {
            XCTAssertEqual(
                String(describing: error),
                "remote control enrollment cache unavailable because sqlite state db is disabled: websocket_url=wss://chatgpt.com/backend-api/wham/remote/control/server, account_id=account_id, app_server_client_name=None"
            )
        }

        do {
            try await RemoteControlEnrollmentPersistence.update(
                store: nil,
                target: target,
                accountID: "account_id",
                appServerClientName: "desktop",
                enrollment: RemoteControlEnrollment(
                    accountID: "account_id",
                    environmentID: "env_123",
                    serverID: "srv_123",
                    serverName: "test-server"
                )
            )
            XCTFail("Expected disabled state DB to reject enrollment persistence")
        } catch {
            XCTAssertEqual(
                String(describing: error),
                "remote control enrollment persistence unavailable because sqlite state db is disabled: websocket_url=wss://chatgpt.com/backend-api/wham/remote/control/server, account_id=account_id, app_server_client_name=Some(\"desktop\"), has_enrollment=true"
            )
        }

        do {
            try await RemoteControlEnrollmentPersistence.update(
                store: RemoteControlEnrollmentMemoryStore(),
                target: target,
                accountID: "account_id",
                appServerClientName: nil,
                enrollment: RemoteControlEnrollment(
                    accountID: "other_account",
                    environmentID: "env_123",
                    serverID: "srv_123",
                    serverName: "test-server"
                )
            )
            XCTFail("Expected enrollment account mismatch to be rejected")
        } catch {
            XCTAssertEqual(
                String(describing: error),
                "enrollment account_id does not match expected account_id `account_id`"
            )
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

    func testRemoteExecutorRegistrationRequestMatchesRustShape() throws {
        let config = try ExecServerRemoteExecutorConfiguration(
            baseURL: "https://registry.example.test",
            executorID: "exec-requested",
            bearerToken: "registry-token"
        )
        let registrationID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let request = config.registrationRequest(registrationID: registrationID)

        XCTAssertEqual(
            request.idempotencyId,
            "codex-exec-server-ca85dcc8eab43dfc6a5e632a7fe44adb7f5e904895bec68497baa50e37305fed"
        )
        try XCTAssertJSONObjectEqual(request, [
            "idempotency_id": request.idempotencyId,
            "executor_id": "exec-requested",
            "name": "codex-exec-server",
            "labels": [:],
            "metadata": [:]
        ])
    }

    func testRemoteExecutorRegistryClientPostsWithBearerTokenLikeRust() async throws {
        let recorder = HTTPRequestRecorder(response: URLSessionTransportResponse(
            statusCode: 200,
            body: Data(#"""
            {
              "id": "registration-1",
              "executor_id": "exec-1",
              "url": "wss://rendezvous.test/executor/exec-1?role=executor&sig=abc"
            }
            """#.utf8)
        ))
        let client = try ExecServerRemoteExecutorRegistryClient(
            baseURL: "https://registry.example.test/",
            bearerToken: "registry-token",
            send: { request in await recorder.send(request) }
        )

        let response = try await client.registerExecutor(ExecServerRemoteExecutorRegistrationRequest(
            idempotencyId: "idem-1",
            executorId: "exec-requested",
            name: "codex-exec-server"
        ))

        XCTAssertEqual(response, ExecServerRemoteExecutorRegistrationResponse(
            id: "registration-1",
            executorId: "exec-1",
            url: "wss://rendezvous.test/executor/exec-1?role=executor&sig=abc"
        ))
        let recordedRequest = await recorder.firstRequest()
        let request = try XCTUnwrap(recordedRequest)
        XCTAssertEqual(request.url?.absoluteString, "https://registry.example.test/cloud/executor/exec-requested/register")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer registry-token")
        let body = try XCTUnwrap(request.httpBody)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(NSDictionary(dictionary: object), NSDictionary(dictionary: [
            "idempotency_id": "idem-1",
            "executor_id": "exec-requested",
            "name": "codex-exec-server",
            "labels": [:],
            "metadata": [:]
        ]))
    }

    func testRemoteExecutorRegistryClientErrorsMatchRustMessages() async throws {
        let authClient = try ExecServerRemoteExecutorRegistryClient(
            baseURL: "https://registry.example.test",
            bearerToken: "registry-token",
            send: { _ in URLSessionTransportResponse(
                statusCode: 403,
                body: Data(#"{"error":{"message":"bad token"}}"#.utf8)
            ) }
        )
        await XCTAssertThrowsExecServerRemoteError(
            try await authClient.registerExecutor(ExecServerRemoteExecutorRegistrationRequest(
                idempotencyId: "idem-1",
                executorId: "exec-1",
                name: nil
            )),
            description: "executor registry authentication error: executor registry authentication failed (403): bad token"
        )

        let httpClient = try ExecServerRemoteExecutorRegistryClient(
            baseURL: "https://registry.example.test",
            bearerToken: "registry-token",
            send: { _ in URLSessionTransportResponse(
                statusCode: 500,
                body: Data(#"{"error":{"code":"registry_failed","message":"try again"}}"#.utf8)
            ) }
        )
        await XCTAssertThrowsExecServerRemoteError(
            try await httpClient.registerExecutor(ExecServerRemoteExecutorRegistrationRequest(
                idempotencyId: "idem-1",
                executorId: "exec-1",
                name: nil
            )),
            description: "executor registry request failed (500, registry_failed): try again"
        )
    }

    func testRemoteExecutorRunnerRegistersConnectsAndSleepsLikeRust() async throws {
        let config = try ExecServerRemoteExecutorConfiguration(
            baseURL: "https://registry.example.test",
            executorID: "exec-requested",
            bearerToken: "registry-token"
        )
        let registrationID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let recorder = RemoteExecutorRunRecorder(
            responses: [ExecServerRemoteExecutorRegistrationResponse(
                id: "registration-1",
                executorId: "exec-1",
                url: "wss://rendezvous.test/executor/exec-1"
            )],
            connectFailures: [false]
        )
        let executor = ExecServerRemoteExecutor(
            config: config,
            registrationID: registrationID,
            registerExecutor: { request in await recorder.register(request) },
            connectAndServe: { url, _ in try await recorder.connect(url) },
            sleep: { seconds in try await recorder.sleep(seconds, stopAfter: 1) },
            messageSink: { message in await recorder.message(message) }
        )

        do {
            try await executor.run()
            XCTFail("Expected test stop")
        } catch RemoteExecutorRunStop.stopped {
        } catch {
            XCTFail("Unexpected remote executor runner error: \(error)")
        }

        let snapshot = await recorder.snapshot()
        XCTAssertEqual(snapshot.requests.map(\.executorId), ["exec-requested"])
        XCTAssertEqual(snapshot.requests.map(\.idempotencyId), [
            "codex-exec-server-ca85dcc8eab43dfc6a5e632a7fe44adb7f5e904895bec68497baa50e37305fed"
        ])
        XCTAssertEqual(snapshot.connectedURLs, ["wss://rendezvous.test/executor/exec-1"])
        XCTAssertEqual(snapshot.sleeps, [1.0])
        XCTAssertEqual(snapshot.messages, [
            "codex exec-server remote executor registration-1 registered with executor_id exec-1"
        ])
    }

    func testRemoteExecutorRunnerRetriesWithRustBackoffAfterWebSocketFailures() async throws {
        let config = try ExecServerRemoteExecutorConfiguration(
            baseURL: "https://registry.example.test",
            executorID: "exec-requested",
            bearerToken: "registry-token"
        )
        let registrationID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let recorder = RemoteExecutorRunRecorder(
            responses: [
                ExecServerRemoteExecutorRegistrationResponse(
                    id: "registration-1",
                    executorId: "exec-1",
                    url: "wss://rendezvous.test/first"
                ),
                ExecServerRemoteExecutorRegistrationResponse(
                    id: "registration-2",
                    executorId: "exec-1",
                    url: "wss://rendezvous.test/second"
                )
            ],
            connectFailures: [true, true]
        )
        let executor = ExecServerRemoteExecutor(
            config: config,
            registrationID: registrationID,
            registerExecutor: { request in await recorder.register(request) },
            connectAndServe: { url, _ in try await recorder.connect(url) },
            sleep: { seconds in try await recorder.sleep(seconds, stopAfter: 2) },
            messageSink: { message in await recorder.message(message) }
        )

        do {
            try await executor.run()
            XCTFail("Expected test stop")
        } catch RemoteExecutorRunStop.stopped {
        } catch {
            XCTFail("Unexpected remote executor runner error: \(error)")
        }

        let snapshot = await recorder.snapshot()
        XCTAssertEqual(snapshot.requests.count, 2)
        XCTAssertEqual(Set(snapshot.requests.map(\.idempotencyId)).count, 1)
        XCTAssertEqual(snapshot.connectedURLs, [
            "wss://rendezvous.test/first",
            "wss://rendezvous.test/second"
        ])
        XCTAssertEqual(snapshot.sleeps, [1.0, 2.0])
        XCTAssertEqual(snapshot.messages, [
            "codex exec-server remote executor registration-1 registered with executor_id exec-1",
            "failed to connect remote exec-server websocket: test websocket connect failed",
            "codex exec-server remote executor registration-2 registered with executor_id exec-1",
            "failed to connect remote exec-server websocket: test websocket connect failed"
        ])
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

    private func withTimeout<T: Sendable>(
        seconds: TimeInterval,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw XCTestError(.timeoutWhileWaiting)
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
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

    private func remoteControlClientChunkEnvelope(
        clientID: String = "client-1",
        streamID: String = "stream-1",
        seqID: UInt64?,
        segmentID: Int,
        segmentCount: Int,
        messageSizeBytes: Int,
        chunk: Data
    ) -> RemoteControlClientEnvelope {
        RemoteControlClientEnvelope(
            event: .clientMessageChunk(
                segmentID: segmentID,
                segmentCount: segmentCount,
                messageSizeBytes: messageSizeBytes,
                messageChunkBase64: chunk.base64EncodedString()
            ),
            clientID: RemoteControlClientID(clientID),
            streamID: RemoteControlStreamID(streamID),
            seqID: seqID,
            cursor: nil
        )
    }

    private func observeRemoteControlClientMessage(
        _ observer: inout RemoteControlClientMessageObserver,
        _ envelope: RemoteControlClientEnvelope
    ) throws -> RemoteControlClientSegmentObservation {
        observer.observe(envelope, wireSizeBytes: try JSONEncoder().encode(envelope).count)
    }

    private func remoteControlEnvelopeText(_ envelope: RemoteControlClientEnvelope) throws -> String {
        String(decoding: try JSONEncoder().encode(envelope), as: UTF8.self)
    }

    private func remoteControlServerEnvelope(from frame: RemoteControlWebsocketWriterFrame) throws -> RemoteControlServerEnvelope {
        guard case let .text(text) = frame else {
            throw TestError("expected websocket text frame")
        }
        return try JSONDecoder().decode(RemoteControlServerEnvelope.self, from: Data(text.utf8))
    }

    private struct TestError: Error, CustomStringConvertible, Equatable, Sendable {
        var description: String

        init(_ description: String) {
            self.description = description
        }
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

    private enum RemoteExecutorRunStop: Error, Equatable, Sendable {
        case stopped
    }

    private struct RemoteExecutorConnectFailure: Error, CustomStringConvertible, Sendable {
        var description: String {
            "test websocket connect failed"
        }
    }

    private actor RemoteExecutorRunRecorder {
        private var responses: [ExecServerRemoteExecutorRegistrationResponse]
        private var connectFailures: [Bool]
        private var requests: [ExecServerRemoteExecutorRegistrationRequest] = []
        private var connectedURLs: [String] = []
        private var sleeps: [TimeInterval] = []
        private var messages: [String] = []

        init(
            responses: [ExecServerRemoteExecutorRegistrationResponse],
            connectFailures: [Bool]
        ) {
            self.responses = responses
            self.connectFailures = connectFailures
        }

        func register(
            _ request: ExecServerRemoteExecutorRegistrationRequest
        ) -> ExecServerRemoteExecutorRegistrationResponse {
            requests.append(request)
            if responses.count > 1 {
                return responses.removeFirst()
            }
            return responses[0]
        }

        func connect(_ url: String) throws {
            connectedURLs.append(url)
            let shouldFail = connectFailures.isEmpty ? false : connectFailures.removeFirst()
            if shouldFail {
                throw RemoteExecutorConnectFailure()
            }
        }

        func sleep(_ seconds: TimeInterval, stopAfter: Int) throws {
            sleeps.append(seconds)
            if sleeps.count >= stopAfter {
                throw RemoteExecutorRunStop.stopped
            }
        }

        func message(_ message: String) {
            messages.append(message)
        }

        func snapshot() -> (
            requests: [ExecServerRemoteExecutorRegistrationRequest],
            connectedURLs: [String],
            sleeps: [TimeInterval],
            messages: [String]
        ) {
            (requests, connectedURLs, sleeps, messages)
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

    private func jsonObject<T: Encodable>(from value: T) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func remoteControlInitializeEnvelope(
        clientID: RemoteControlClientID,
        streamID: RemoteControlStreamID?,
        seqID: UInt64?
    ) -> RemoteControlClientEnvelope {
        RemoteControlClientEnvelope(
            event: .clientMessage(message: tryInitializeMessage()),
            clientID: clientID,
            streamID: streamID,
            seqID: seqID,
            cursor: nil
        )
    }

    private func tryInitializeMessage() -> ExecServerJSONRPCMessage {
        .request(ExecServerJSONRPCRequest(
            id: .integer(1),
            method: execServerInitializeMethod,
            params: .object([
                "clientInfo": .object([
                    "name": .string("remote-test-client"),
                    "version": .string("0.1.0")
                ])
            ])
        ))
    }

    private actor RemoteControlAuthSequence {
        private var values: [AuthDotJSON?]
        private var loads = 0
        private var reloads = 0

        init(_ values: [AuthDotJSON?]) {
            self.values = values
        }

        func load() -> AuthDotJSON? {
            defer { loads += 1 }
            guard loads < values.count else {
                return values.last ?? nil
            }
            return values[loads]
        }

        func reload() {
            reloads += 1
        }

        func reloadCount() -> Int {
            reloads
        }
    }

    private actor RemoteControlRecordingWebSocketTransport: RemoteControlWebSocketTransport {
        private var incoming: [RemoteControlWebsocketIncomingMessage]
        private var receiveError: String?
        private let sendError: String?
        private var frames: [RemoteControlWebsocketWriterFrame] = []
        private var closes = 0

        init(
            incoming: [RemoteControlWebsocketIncomingMessage] = [],
            receiveError: String? = nil,
            sendError: String? = nil
        ) {
            self.incoming = incoming
            self.receiveError = receiveError
            self.sendError = sendError
        }

        func receiveRemoteControlMessage() throws -> RemoteControlWebsocketIncomingMessage {
            if let receiveError {
                throw TestError(receiveError)
            }
            guard !incoming.isEmpty else {
                return .streamEnded
            }
            return incoming.removeFirst()
        }

        func sendRemoteControlFrame(_ frame: RemoteControlWebsocketWriterFrame) throws {
            if let sendError {
                throw TestError(sendError)
            }
            frames.append(frame)
        }

        func closeRemoteControlWebSocket() {
            closes += 1
        }

        func setReceiveError(_ message: String?) {
            receiveError = message
        }

        func sentFrames() -> [RemoteControlWebsocketWriterFrame] {
            frames
        }

        func sentFrameCount() -> Int {
            frames.count
        }

        func closeCount() -> Int {
            closes
        }
    }

    private actor RemoteControlWebSocketConnectorProbe {
        private let staleServerID: String?
        private var enrolls = 0
        private var serverIDs: [String] = []

        init(staleServerID: String? = nil) {
            self.staleServerID = staleServerID
        }

        func enroll(
            target _: RemoteControlTarget,
            returning enrollment: RemoteControlEnrollment
        ) -> RemoteControlEnrollment {
            enrolls += 1
            return enrollment
        }

        func connect(
            request _: URLRequest,
            enrollment: RemoteControlEnrollment
        ) throws {
            serverIDs.append(enrollment.serverID)
            if enrollment.serverID == staleServerID {
                throw RemoteControlWebSocketConnectionError.http(
                    websocketURL: "wss://chatgpt.com/backend-api/wham/remote/control/server",
                    statusCode: 404,
                    headers: ["x-request-id": "req-404"],
                    body: Data("stale enrollment".utf8)
                )
            }
        }

        func enrollCount() -> Int {
            enrolls
        }

        func connectedServerIDs() -> [String] {
            serverIDs
        }
    }

    private actor RemoteControlEnrollmentMemoryStore: RemoteControlEnrollmentStore {
        private var storage: [RemoteControlEnrollmentRecord] = []

        func getRemoteControlEnrollment(
            websocketURL: String,
            accountID: String,
            appServerClientName: String?
        ) async throws -> RemoteControlEnrollmentRecord? {
            storage.first {
                $0.websocketURL == websocketURL
                    && $0.accountID == accountID
                    && $0.appServerClientName == appServerClientName
            }
        }

        func upsertRemoteControlEnrollment(_ enrollment: RemoteControlEnrollmentRecord) async throws {
            storage.removeAll {
                $0.websocketURL == enrollment.websocketURL
                    && $0.accountID == enrollment.accountID
                    && $0.appServerClientName == enrollment.appServerClientName
            }
            storage.append(enrollment)
        }

        func deleteRemoteControlEnrollment(
            websocketURL: String,
            accountID: String,
            appServerClientName: String?
        ) async throws -> Int {
            let oldCount = storage.count
            storage.removeAll {
                $0.websocketURL == websocketURL
                    && $0.accountID == accountID
                    && $0.appServerClientName == appServerClientName
            }
            return oldCount - storage.count
        }

        func records() -> [RemoteControlEnrollmentRecord] {
            storage
        }
    }
}
