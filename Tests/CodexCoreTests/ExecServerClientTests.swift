import CodexCore
import Darwin
import Foundation
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

    func testRemoteFileSystemDelegatesOperationsThroughExecServerClientLikeRust() async throws {
        let sandbox = FileSystemSandboxContext(
            permissions: .readOnly(),
            cwd: try AbsolutePath(absolutePath: "/repo")
        )
        let transport = ScriptedExecServerClientTransport { message in
            guard case let .request(request) = message else {
                return nil
            }
            switch request.method {
            case execServerFsReadFileMethod:
                XCTAssertEqual(request.params?["path"], .string("/repo/note.txt"))
                XCTAssertNil(request.params?["sandbox"]?["cwd"])
                return ExecServerRPC.response(
                    id: request.id,
                    result: try ExecServerRPC.jsonValue(from: ExecServerFsReadFileResponse(dataBase64: "aGVsbG8="))
                )
            case execServerFsWriteFileMethod:
                XCTAssertEqual(request.params?["path"], .string("/repo/out.txt"))
                XCTAssertEqual(request.params?["dataBase64"], .string("d3JpdHRlbg=="))
                XCTAssertNil(request.params?["sandbox"]?["cwd"])
                return ExecServerRPC.response(
                    id: request.id,
                    result: try ExecServerRPC.jsonValue(from: ExecServerFsWriteFileResponse())
                )
            case execServerFsCreateDirectoryMethod:
                XCTAssertEqual(request.params?["path"], .string("/repo/new"))
                XCTAssertEqual(request.params?["recursive"], .bool(false))
                return ExecServerRPC.response(
                    id: request.id,
                    result: try ExecServerRPC.jsonValue(from: ExecServerFsCreateDirectoryResponse())
                )
            case execServerFsGetMetadataMethod:
                XCTAssertEqual(request.params?["path"], .string("/repo/out.txt"))
                return ExecServerRPC.response(
                    id: request.id,
                    result: try ExecServerRPC.jsonValue(from: ExecServerFsGetMetadataResponse(
                        isDirectory: false,
                        isFile: true,
                        isSymlink: false,
                        createdAtMs: 11,
                        modifiedAtMs: 22
                    ))
                )
            case execServerFsReadDirectoryMethod:
                XCTAssertEqual(request.params?["path"], .string("/repo"))
                return ExecServerRPC.response(
                    id: request.id,
                    result: try ExecServerRPC.jsonValue(from: ExecServerFsReadDirectoryResponse(entries: [
                        ExecServerFsReadDirectoryEntry(fileName: "out.txt", isDirectory: false, isFile: true)
                    ]))
                )
            case execServerFsRemoveMethod:
                XCTAssertEqual(request.params?["path"], .string("/repo/out.txt"))
                XCTAssertEqual(request.params?["recursive"], .bool(true))
                XCTAssertEqual(request.params?["force"], .bool(false))
                return ExecServerRPC.response(
                    id: request.id,
                    result: try ExecServerRPC.jsonValue(from: ExecServerFsRemoveResponse())
                )
            case execServerFsCopyMethod:
                XCTAssertEqual(request.params?["sourcePath"], .string("/repo/source.txt"))
                XCTAssertEqual(request.params?["destinationPath"], .string("/repo/dest.txt"))
                XCTAssertEqual(request.params?["recursive"], .bool(true))
                return ExecServerRPC.response(
                    id: request.id,
                    result: try ExecServerRPC.jsonValue(from: ExecServerFsCopyResponse())
                )
            default:
                XCTFail("Unexpected method \(request.method)")
                return nil
            }
        }
        let fileSystem = ExecServerRemoteFileSystem(client: ExecServerClient(transport: transport))

        let contents = try await fileSystem.readFile(
            try AbsolutePath(absolutePath: "/repo/note.txt"),
            sandbox: sandbox
        )
        try await fileSystem.writeFile(
            try AbsolutePath(absolutePath: "/repo/out.txt"),
            contents: Data("written".utf8),
            sandbox: sandbox
        )
        try await fileSystem.createDirectory(
            try AbsolutePath(absolutePath: "/repo/new"),
            options: CreateDirectoryOptions(recursive: false),
            sandbox: sandbox
        )
        let metadata = try await fileSystem.getMetadata(try AbsolutePath(absolutePath: "/repo/out.txt"))
        let entries = try await fileSystem.readDirectory(try AbsolutePath(absolutePath: "/repo"))
        try await fileSystem.remove(
            try AbsolutePath(absolutePath: "/repo/out.txt"),
            options: RemoveOptions(recursive: true, force: false)
        )
        try await fileSystem.copy(
            from: try AbsolutePath(absolutePath: "/repo/source.txt"),
            to: try AbsolutePath(absolutePath: "/repo/dest.txt"),
            options: CopyOptions(recursive: true)
        )

        XCTAssertEqual(contents, Data("hello".utf8))
        XCTAssertEqual(metadata, FileMetadata(
            isDirectory: false,
            isFile: true,
            isSymlink: false,
            createdAtMs: 11,
            modifiedAtMs: 22
        ))
        XCTAssertEqual(entries, [
            ReadDirectoryEntry(fileName: "out.txt", isDirectory: false, isFile: true)
        ])
        let methods = await transport.snapshot().compactMap { message -> String? in
            guard case let .request(request) = message else {
                return nil
            }
            return request.method
        }
        XCTAssertEqual(methods, [
            execServerFsReadFileMethod,
            execServerFsWriteFileMethod,
            execServerFsCreateDirectoryMethod,
            execServerFsGetMetadataMethod,
            execServerFsReadDirectoryMethod,
            execServerFsRemoveMethod,
            execServerFsCopyMethod
        ])
    }

    func testRemoteFileSystemPreservesCwdWhenPermissionsDependOnItLikeRust() async throws {
        let sandbox = FileSystemSandboxContext(
            permissions: .workspaceWrite(),
            cwd: try AbsolutePath(absolutePath: "/repo")
        )
        let transport = ScriptedExecServerClientTransport { message in
            guard case let .request(request) = message else {
                return nil
            }
            XCTAssertEqual(request.method, execServerFsReadFileMethod)
            XCTAssertEqual(request.params?["sandbox"]?["cwd"], .string("/repo"))
            return ExecServerRPC.response(
                id: request.id,
                result: try ExecServerRPC.jsonValue(from: ExecServerFsReadFileResponse(dataBase64: "b2s="))
            )
        }
        let fileSystem = ExecServerRemoteFileSystem(client: ExecServerClient(transport: transport))

        let contents = try await fileSystem.readFile(
            try AbsolutePath(absolutePath: "/repo/note.txt"),
            sandbox: sandbox
        )

        XCTAssertEqual(contents, Data("ok".utf8))
    }

    func testRemoteFileSystemMapsInvalidBase64AndServerErrorsLikeRust() async throws {
        let invalidBase64Transport = ScriptedExecServerClientTransport { message in
            guard case let .request(request) = message else {
                return nil
            }
            return ExecServerRPC.response(
                id: request.id,
                result: try ExecServerRPC.jsonValue(from: ExecServerFsReadFileResponse(dataBase64: "%%%"))
            )
        }
        let invalidBase64FileSystem = ExecServerRemoteFileSystem(
            client: ExecServerClient(transport: invalidBase64Transport)
        )
        await XCTAssertThrowsExecServerFileSystemError(
            try await invalidBase64FileSystem.readFile(try AbsolutePath(absolutePath: "/repo/bad.txt")),
            kind: .invalidInput,
            description: "remote fs/readFile returned invalid base64 dataBase64: Invalid byte 37, offset 0."
        )

        let notFoundTransport = ScriptedExecServerClientTransport { message in
            guard case let .request(request) = message else {
                return nil
            }
            return ExecServerRPC.error(
                id: request.id,
                error: ExecServerRPC.notFound("No such file or directory")
            )
        }
        let notFoundFileSystem = ExecServerRemoteFileSystem(client: ExecServerClient(transport: notFoundTransport))
        await XCTAssertThrowsExecServerFileSystemError(
            try await notFoundFileSystem.getMetadata(try AbsolutePath(absolutePath: "/repo/missing.txt")),
            kind: .notFound,
            description: "No such file or directory"
        )

        let invalidInputTransport = ScriptedExecServerClientTransport { message in
            guard case let .request(request) = message else {
                return nil
            }
            return ExecServerRPC.error(
                id: request.id,
                error: ExecServerRPC.invalidRequest("bad fs request")
            )
        }
        let invalidInputFileSystem = ExecServerRemoteFileSystem(
            client: ExecServerClient(transport: invalidInputTransport)
        )
        await XCTAssertThrowsExecServerFileSystemError(
            try await invalidInputFileSystem.remove(
                try AbsolutePath(absolutePath: "/repo/bad.txt"),
                options: RemoveOptions(recursive: false, force: false)
            ),
            kind: .invalidInput,
            description: "bad fs request"
        )
    }

    func testRemoteProcessStartsAndDelegatesSessionOperationsLikeRust() async throws {
        let transport = ScriptedExecServerClientTransport { message in
            guard case let .request(request) = message else {
                return nil
            }
            switch request.method {
            case execServerProcessStartMethod:
                XCTAssertEqual(request.params?["processId"], .string("proc-remote"))
                XCTAssertEqual(request.params?["argv"], .array([.string("/bin/cat")]))
                XCTAssertEqual(request.params?["pipeStdin"], .bool(true))
                return ExecServerRPC.response(
                    id: request.id,
                    result: try ExecServerRPC.jsonValue(from: ExecServerExecResponse(processId: "proc-remote"))
                )
            case execServerProcessReadMethod:
                XCTAssertEqual(request.params?["processId"], .string("proc-remote"))
                XCTAssertEqual(request.params?["afterSeq"], .integer(4))
                XCTAssertEqual(request.params?["maxBytes"], .integer(128))
                XCTAssertEqual(request.params?["waitMs"], .integer(50))
                return ExecServerRPC.response(
                    id: request.id,
                    result: try ExecServerRPC.jsonValue(from: ExecServerReadResponse(
                        chunks: [
                            ExecServerProcessOutputChunk(
                                seq: 5,
                                stream: .stdout,
                                chunk: ExecServerByteChunk(Array("pong".utf8))
                            )
                        ],
                        nextSeq: 6,
                        exited: false,
                        closed: false
                    ))
                )
            case execServerProcessWriteMethod:
                XCTAssertEqual(request.params?["processId"], .string("proc-remote"))
                XCTAssertEqual(request.params?["chunk"], .string("cGluZw=="))
                return ExecServerRPC.response(
                    id: request.id,
                    result: try ExecServerRPC.jsonValue(from: ExecServerWriteResponse(status: .accepted))
                )
            case execServerProcessTerminateMethod:
                XCTAssertEqual(request.params?["processId"], .string("proc-remote"))
                return ExecServerRPC.response(
                    id: request.id,
                    result: try ExecServerRPC.jsonValue(from: ExecServerTerminateResponse(running: true))
                )
            default:
                XCTFail("Unexpected method \(request.method)")
                return nil
            }
        }
        let remoteProcess = ExecServerRemoteProcess(client: ExecServerClient(transport: transport))

        let started = try await remoteProcess.start(ExecServerExecParams(
            processId: "proc-remote",
            argv: ["/bin/cat"],
            cwd: "/tmp",
            env: [:],
            tty: false,
            pipeStdin: true
        ))
        let read = try await started.process.read(afterSeq: 4, maxBytes: 128, waitMs: 50)
        let write = try await started.process.write(Data("ping".utf8))
        try await started.process.terminate()

        XCTAssertEqual(started.process.processId, "proc-remote")
        XCTAssertEqual(read.chunks.first?.chunk.bytes, Array("pong".utf8))
        XCTAssertEqual(write.status, .accepted)
        let methods = await transport.snapshot().compactMap { message -> String? in
            guard case let .request(request) = message else {
                return nil
            }
            return request.method
        }
        XCTAssertEqual(methods, [
            execServerProcessStartMethod,
            execServerProcessReadMethod,
            execServerProcessWriteMethod,
            execServerProcessTerminateMethod
        ])
    }

    func testRemoteProcessUnregistersSessionWhenStartFailsLikeRust() async throws {
        let startAttempts = AsyncCounter()
        let transport = ScriptedExecServerClientTransport { message in
            guard case let .request(request) = message else {
                return nil
            }
            XCTAssertEqual(request.method, execServerProcessStartMethod)
            if await startAttempts.increment() == 1 {
                return ExecServerRPC.error(
                    id: request.id,
                    error: ExecServerRPC.invalidRequest("cannot start process")
                )
            }
            return ExecServerRPC.response(
                id: request.id,
                result: try ExecServerRPC.jsonValue(from: ExecServerExecResponse(processId: "proc-retry"))
            )
        }
        let remoteProcess = ExecServerRemoteProcess(client: ExecServerClient(transport: transport))
        let params = ExecServerExecParams(
            processId: "proc-retry",
            argv: ["/bin/echo", "ok"],
            cwd: "/tmp",
            env: [:],
            tty: false
        )

        await XCTAssertThrowsExecServerClientError(
            try await remoteProcess.start(params),
            description: "exec-server rejected request (-32600): cannot start process"
        )
        let started = try await remoteProcess.start(params)

        XCTAssertEqual(started.process.processId, "proc-retry")
    }

    func testRemoteProcessSessionOrdersNotificationsAndRemovesClosedRouteLikeRust() async throws {
        let transport = ScriptedExecServerClientTransport { message in
            guard case let .request(request) = message else {
                return nil
            }
            return ExecServerRPC.response(
                id: request.id,
                result: try ExecServerRPC.jsonValue(from: ExecServerExecResponse(processId: "proc-events"))
            )
        }
        let client = ExecServerClient(transport: transport)
        let remoteProcess = ExecServerRemoteProcess(client: client)
        let started = try await remoteProcess.start(ExecServerExecParams(
            processId: "proc-events",
            argv: ["/bin/echo", "hi"],
            cwd: "/tmp",
            env: [:],
            tty: false
        ))

        try await client.handleServerNotification(ExecServerJSONRPCNotification(
            method: execServerProcessClosedMethod,
            params: try ExecServerRPC.jsonValue(from: ExecServerClosedNotification(processId: "proc-events", seq: 3))
        ))
        let closedFirstSnapshot = await started.process.eventSnapshot()
        XCTAssertEqual(closedFirstSnapshot, [])

        try await client.handleServerNotification(ExecServerJSONRPCNotification(
            method: execServerProcessOutputDeltaMethod,
            params: try ExecServerRPC.jsonValue(from: ExecServerOutputDeltaNotification(
                processId: "proc-events",
                seq: 1,
                stream: .stdout,
                chunk: ExecServerByteChunk(Array("hi".utf8))
            ))
        ))
        let outputSnapshot = await started.process.eventSnapshot()
        XCTAssertEqual(outputSnapshot, [
            .output(ExecServerProcessOutputChunk(
                seq: 1,
                stream: .stdout,
                chunk: ExecServerByteChunk(Array("hi".utf8))
            ))
        ])

        try await client.handleServerNotification(ExecServerJSONRPCNotification(
            method: execServerProcessExitedMethod,
            params: try ExecServerRPC.jsonValue(from: ExecServerExitedNotification(
                processId: "proc-events",
                seq: 2,
                exitCode: 0
            ))
        ))
        let terminalSnapshot = await started.process.eventSnapshot()
        XCTAssertEqual(terminalSnapshot, [
            .output(ExecServerProcessOutputChunk(
                seq: 1,
                stream: .stdout,
                chunk: ExecServerByteChunk(Array("hi".utf8))
            )),
            .exited(seq: 2, exitCode: 0),
            .closed(seq: 3)
        ])

        let replacement = try await remoteProcess.start(ExecServerExecParams(
            processId: "proc-events",
            argv: ["/bin/echo", "again"],
            cwd: "/tmp",
            env: [:],
            tty: false
        ))
        XCTAssertEqual(replacement.process.processId, "proc-events")
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

    func testConnectStdioCommandSpawnsProcessAndInitializesLikeRust() async throws {
        let temp = try TemporaryDirectory()
        let initPath = temp.url.appendingPathComponent("initialize.jsonl").path
        let initializedPath = temp.url.appendingPathComponent("initialized.jsonl").path
        let cwdPath = temp.url.path
        let envPath = temp.url.appendingPathComponent("env.txt").path
        let script = """
        IFS= read -r initialize
        printf '%s\\n' "$initialize" > '\(shellQuote(initPath))'
        pwd > '\(shellQuote(cwdPath))/cwd.txt'
        printf '%s\\n' "$CODEX_SWIFT_EXEC_SERVER_TEST" > '\(shellQuote(envPath))'
        printf '%s\\n' '{"id":1,"result":{"sessionId":"stdio-session"}}'
        IFS= read -r initialized
        printf '%s\\n' "$initialized" > '\(shellQuote(initializedPath))'
        sleep 2
        """

        let client = try await ExecServerClient.connectStdioCommand(StdioExecServerConnectArgs(
            command: StdioExecServerCommand(
                program: "sh",
                args: ["-c", script],
                env: ["CODEX_SWIFT_EXEC_SERVER_TEST": "env-value"],
                cwd: temp.url.path
            ),
            clientName: "stdio-test-client",
            initializeTimeoutSeconds: 1,
            resumeSessionID: "resume-me"
        ))

        let sessionID = await client.sessionID
        XCTAssertEqual(sessionID, "stdio-session")
        let initializeLine = try waitForTextFile(initPath).trimmingCharacters(in: .newlines)
        let initializedLine = try waitForTextFile(initializedPath).trimmingCharacters(in: .newlines)
        let cwdLine = try waitForTextFile(temp.url.appendingPathComponent("cwd.txt").path)
            .trimmingCharacters(in: .newlines)
        let envLine = try waitForTextFile(envPath).trimmingCharacters(in: .newlines)

        let initialize = try JSONDecoder().decode(ExecServerJSONRPCMessage.self, from: Data(initializeLine.utf8))
        guard case let .request(request) = initialize else {
            return XCTFail("Expected initialize request")
        }
        XCTAssertEqual(request.method, execServerInitializeMethod)
        XCTAssertEqual(request.params?["clientName"], .string("stdio-test-client"))
        XCTAssertEqual(request.params?["resumeSessionId"], .string("resume-me"))
        let initialized = try JSONDecoder().decode(ExecServerJSONRPCMessage.self, from: Data(initializedLine.utf8))
        XCTAssertEqual(initialized.method, execServerInitializedMethod)
        XCTAssertEqual(
            URL(fileURLWithPath: cwdLine).standardizedFileURL.path,
            temp.url.standardizedFileURL.path
        )
        XCTAssertEqual(envLine, "env-value")
    }

    func testConnectWebSocketInitializesJSONRPCClientLikeRust() async throws {
        let urlString = try await startWebSocketExecServer()

        let client = try await ExecServerClient.connectWebSocket(RemoteExecServerConnectArgs(
            websocketURL: urlString,
            clientName: "websocket-test-client",
            connectTimeoutSeconds: 1,
            initializeTimeoutSeconds: 1
        ))

        let sessionID = await client.sessionID
        XCTAssertEqual(sessionID, "session-1")
    }

    func testConnectForTransportInitializesWebSocketLikeRustEnvironmentTransport() async throws {
        let urlString = try await startWebSocketExecServer()

        let client = try await ExecServerClient.connectForTransport(.webSocketURL(urlString))

        let sessionID = await client.sessionID
        XCTAssertEqual(sessionID, "session-1")
    }

    func testConnectStdioCommandTerminatesProcessOnMalformedInitializeLikeRust() async throws {
        let temp = try TemporaryDirectory()
        let markerPath = temp.url.appendingPathComponent("marker").path
        let script = """
        IFS= read -r _initialize
        printf '%s\\n' "$$" > '\(shellQuote(markerPath))'
        printf '%s\\n' 'not-json'
        sleep 10
        """

        await XCTAssertThrowsExecServerClientError(
            try await ExecServerClient.connectStdioCommand(StdioExecServerConnectArgs(
                command: StdioExecServerCommand(program: "sh", args: ["-c", script]),
                clientName: "stdio-test-client",
                initializeTimeoutSeconds: 1
            )),
            descriptionPrefix: "exec-server protocol error: failed to parse JSON-RPC message from exec-server stdio command:"
        )
        let pid = try waitForPIDFile(markerPath)
        try await waitForProcessExit(pid)
    }

    func testDroppingStdioClientTerminatesSpawnedProcessTreeLikeRust() async throws {
        let temp = try TemporaryDirectory()
        let serverPIDPath = temp.url.appendingPathComponent("server.pid").path
        let childPIDPath = temp.url.appendingPathComponent("server-child.pid").path
        let script = """
        IFS= read -r _initialize
        printf '%s\\n' "$$" > '\(shellQuote(serverPIDPath))'
        sleep 60 >/dev/null 2>&1 &
        printf '%s\\n' "$!" > '\(shellQuote(childPIDPath))'
        printf '%s\\n' '{"id":1,"result":{"sessionId":"stdio-session"}}'
        IFS= read -r _initialized
        wait
        """

        var client: ExecServerClient? = try await ExecServerClient.connectStdioCommand(StdioExecServerConnectArgs(
            command: StdioExecServerCommand(program: "sh", args: ["-c", script]),
            clientName: "stdio-test-client",
            initializeTimeoutSeconds: 1
        ))
        let serverPID = try waitForPIDFile(serverPIDPath)
        let childPID = try waitForPIDFile(childPIDPath)
        XCTAssertNotNil(client)
        XCTAssertTrue(processExists(serverPID), "spawned stdio process should be running before client drop")
        XCTAssertTrue(processExists(childPID), "spawned stdio child process should be running before client drop")

        client = nil

        try await waitForProcessExit(serverPID)
        try await waitForProcessExit(childPID)
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

    private func XCTAssertThrowsExecServerFileSystemError<T>(
        _ expression: @autoclosure @escaping () async throws -> T,
        kind: ExecServerFileSystemError.Kind,
        description: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await expression()
            XCTFail("Expected exec-server filesystem error", file: file, line: line)
        } catch let error as ExecServerFileSystemError {
            XCTAssertEqual(error.kind, kind, file: file, line: line)
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

private actor AsyncCounter {
    private var value = 0

    func increment() -> Int {
        value += 1
        return value
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

private func startWebSocketExecServer() async throws -> String {
    let (stream, continuation) = AsyncStream.makeStream(of: String.self)
    let transport = ExecServerWebSocketTransport(processor: ExecServerConnectionProcessor(
        sessionRegistry: ExecServerSessionRegistry(makeID: sequenceIDs(["connection-1", "session-1"]))
    ))
    let serverTask = Task.detached {
        try await transport.run(host: "127.0.0.1", port: 0) { url in
            continuation.yield(url.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
    Task {
        try? await Task.sleep(nanoseconds: 5_000_000_000)
        serverTask.cancel()
    }
    var iterator = stream.makeAsyncIterator()
    guard let url = await iterator.next() else {
        throw NSError(domain: "ExecServerClientTests", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "websocket listen URL was not announced"
        ])
    }
    return url
}

private func sequenceIDs(_ ids: [String]) -> @Sendable () -> String {
    let sequence = LockedStringSequence(ids)
    return { sequence.next() }
}

private final class LockedStringSequence: @unchecked Sendable {
    private let lock = NSLock()
    private var remaining: [String]

    init(_ values: [String]) {
        remaining = values
    }

    func next() -> String {
        lock.withLock {
            if remaining.isEmpty {
                return "exhausted"
            }
            return remaining.removeFirst()
        }
    }
}

private func shellQuote(_ value: String) -> String {
    value.replacingOccurrences(of: "'", with: "'\\''")
}

private func waitForPIDFile(_ path: String) throws -> Int32 {
    for _ in 0..<20 {
        if let contents = try? String(contentsOfFile: path, encoding: .utf8),
           let pid = Int32(contents.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return pid
        }
        Thread.sleep(forTimeInterval: 0.05)
    }
    throw NSError(domain: "ExecServerClientTests", code: 1, userInfo: [
        NSLocalizedDescriptionKey: "PID file was not written"
    ])
}

private func waitForTextFile(_ path: String) throws -> String {
    for _ in 0..<20 {
        if let contents = try? String(contentsOfFile: path, encoding: .utf8), !contents.isEmpty {
            return contents
        }
        Thread.sleep(forTimeInterval: 0.05)
    }
    throw NSError(domain: "ExecServerClientTests", code: 1, userInfo: [
        NSLocalizedDescriptionKey: "text file \(path) was not written"
    ])
}

private func waitForProcessExit(_ pid: Int32) async throws {
    for _ in 0..<30 {
        if !processExists(pid) {
            return
        }
        try await Task.sleep(nanoseconds: 100_000_000)
    }
    XCTFail("process \(pid) should exit")
}

private func processExists(_ pid: Int32) -> Bool {
    Darwin.kill(pid, 0) == 0
}

private final class TemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "codex-swift-exec-server-client-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
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
