import CodexCore
import XCTest

final class ExecServerTests: XCTestCase {
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

    func testRouterReportsPendingRegisteredAndUnknownMethodsWithRustStubMessage() async throws {
        let router = ExecServerRouter()
        let handler = ExecServerHandler(sessionRegistry: ExecServerSessionRegistry(makeID: sequenceIDs(["connection-1", "session-1"])))
        _ = try await handler.initialize(ExecServerInitializeParams(clientName: "client"))
        try await handler.markInitialized()

        let pending = await router.handleRequest(ExecServerJSONRPCRequest(
            id: .integer(1),
            method: execServerProcessTerminateMethod,
            params: try ExecServerRPC.jsonValue(from: ExecServerTerminateParams(processId: "p1"))
        ), using: handler)
        let unknown = await router.handleRequest(ExecServerJSONRPCRequest(
            id: .integer(2),
            method: "made/up",
            params: .object([:])
        ), using: handler)

        XCTAssertEqual(pending, .error(
            requestID: .integer(1),
            error: ExecServerRPC.methodNotFound("exec-server stub does not implement `process/terminate` yet")
        ))
        XCTAssertEqual(unknown, .error(
            requestID: .integer(2),
            error: ExecServerRPC.methodNotFound("exec-server stub does not implement `made/up` yet")
        ))
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
}
