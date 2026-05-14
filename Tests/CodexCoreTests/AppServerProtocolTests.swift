import CodexCore
import XCTest

final class AppServerProtocolTests: XCTestCase {
    func testAttestationGenerateServerRequestMatchesRustWireShape() throws {
        let request = AppServerProtocol.ServerRequest.attestationGenerate(
            requestID: .integer(9),
            params: Attestation.GenerateParams()
        )

        XCTAssertEqual(request.id, .integer(9))
        XCTAssertEqual(request.method, "attestation/generate")
        try XCTAssertJSONObjectEqual(request, [
            "method": "attestation/generate",
            "id": 9,
            "params": [String: Any]()
        ])
        XCTAssertEqual(
            AppServerProtocol.ServerRequestPayload.attestationGenerate().request(withID: .integer(9)),
            request
        )

        let decoded = try JSONDecoder().decode(
            AppServerProtocol.ServerRequest.self,
            from: Data(#"{"method":"attestation/generate","id":9,"params":{}}"#.utf8)
        )
        XCTAssertEqual(decoded, request)
    }

    func testAttestationGenerateServerResponseMatchesRustWireShape() throws {
        let response = AppServerProtocol.ServerResponse.attestationGenerate(
            requestID: .string("request-9"),
            response: Attestation.GenerateResponse(token: "v1.integration-test")
        )

        XCTAssertEqual(response.id, .string("request-9"))
        XCTAssertEqual(response.method, "attestation/generate")
        try XCTAssertJSONObjectEqual(response, [
            "method": "attestation/generate",
            "id": "request-9",
            "response": [
                "token": "v1.integration-test"
            ]
        ])

        let decoded = try JSONDecoder().decode(
            AppServerProtocol.ServerResponse.self,
            from: Data(#"{"method":"attestation/generate","id":"request-9","response":{"token":"v1.integration-test"}}"#.utf8)
        )
        XCTAssertEqual(decoded, response)
    }

    func testChatGPTAuthTokensRefreshServerRequestMatchesRustWireShape() throws {
        let params = AppServerProtocol.ChatGPTAuthTokensRefreshParams(
            reason: .unauthorized,
            previousAccountID: "org-123"
        )
        let request = AppServerProtocol.ServerRequest.chatGPTAuthTokensRefresh(
            requestID: .integer(8),
            params: params
        )

        XCTAssertEqual(request.id, .integer(8))
        XCTAssertEqual(request.method, "account/chatgptAuthTokens/refresh")
        try XCTAssertJSONObjectEqual(request, [
            "method": "account/chatgptAuthTokens/refresh",
            "id": 8,
            "params": [
                "reason": "unauthorized",
                "previousAccountId": "org-123"
            ]
        ])
        XCTAssertEqual(
            AppServerProtocol.ServerRequestPayload.chatGPTAuthTokensRefresh(params).request(withID: .integer(8)),
            request
        )

        let decoded = try JSONDecoder().decode(
            AppServerProtocol.ServerRequest.self,
            from: Data(#"{"method":"account/chatgptAuthTokens/refresh","id":8,"params":{"reason":"unauthorized","previousAccountId":"org-123"}}"#.utf8)
        )
        XCTAssertEqual(decoded, request)
    }

    func testChatGPTAuthTokensRefreshServerResponseMatchesRustWireShape() throws {
        let response = AppServerProtocol.ServerResponse.chatGPTAuthTokensRefresh(
            requestID: .integer(8),
            response: AppServerProtocol.ChatGPTAuthTokensRefreshResponse(
                accessToken: "access-token",
                chatGPTAccountID: "org-123",
                chatGPTPlanType: nil
            )
        )

        XCTAssertEqual(response.id, .integer(8))
        XCTAssertEqual(response.method, "account/chatgptAuthTokens/refresh")
        try XCTAssertJSONObjectEqual(response, [
            "method": "account/chatgptAuthTokens/refresh",
            "id": 8,
            "response": [
                "accessToken": "access-token",
                "chatgptAccountId": "org-123",
                "chatgptPlanType": NSNull()
            ]
        ])

        let decoded = try JSONDecoder().decode(
            AppServerProtocol.ServerResponse.self,
            from: Data(#"{"method":"account/chatgptAuthTokens/refresh","id":8,"response":{"accessToken":"access-token","chatgptAccountId":"org-123","chatgptPlanType":null}}"#.utf8)
        )
        XCTAssertEqual(decoded, response)
    }

    func testExecCommandApprovalServerRequestMatchesRustWireShape() throws {
        let params = AppServerProtocol.ExecCommandApprovalParams(
            conversationID: "67e55044-10b1-426f-9247-bb680e5fe0c8",
            callID: "call-42",
            approvalID: "approval-42",
            command: ["echo", "hello"],
            cwd: "/tmp",
            reason: "because tests",
            parsedCmd: [.unknown(cmd: "echo hello")]
        )
        let request = AppServerProtocol.ServerRequest.execCommandApproval(
            requestID: .integer(7),
            params: params
        )

        XCTAssertEqual(request.id, .integer(7))
        XCTAssertEqual(request.method, "execCommandApproval")
        try XCTAssertJSONObjectEqual(request, [
            "method": "execCommandApproval",
            "id": 7,
            "params": [
                "conversationId": "67e55044-10b1-426f-9247-bb680e5fe0c8",
                "callId": "call-42",
                "approvalId": "approval-42",
                "command": ["echo", "hello"],
                "cwd": "/tmp",
                "reason": "because tests",
                "parsedCmd": [
                    [
                        "type": "unknown",
                        "cmd": "echo hello"
                    ]
                ]
            ]
        ])
        XCTAssertEqual(
            AppServerProtocol.ServerRequestPayload.execCommandApproval(params).request(withID: .integer(7)),
            request
        )

        let decoded = try JSONDecoder().decode(
            AppServerProtocol.ServerRequest.self,
            from: Data(#"{"method":"execCommandApproval","id":7,"params":{"conversationId":"67e55044-10b1-426f-9247-bb680e5fe0c8","callId":"call-42","approvalId":"approval-42","command":["echo","hello"],"cwd":"/tmp","reason":"because tests","parsedCmd":[{"type":"unknown","cmd":"echo hello"}]}}"#.utf8)
        )
        XCTAssertEqual(decoded, request)
    }

    func testExecCommandApprovalServerRequestEncodesNilOptionalsLikeRust() throws {
        let request = AppServerProtocol.ServerRequest.execCommandApproval(
            requestID: .integer(7),
            params: AppServerProtocol.ExecCommandApprovalParams(
                conversationID: "67e55044-10b1-426f-9247-bb680e5fe0c8",
                callID: "call-42",
                approvalID: nil,
                command: ["pwd"],
                cwd: "/tmp",
                reason: nil,
                parsedCmd: []
            )
        )

        try XCTAssertJSONObjectEqual(request, [
            "method": "execCommandApproval",
            "id": 7,
            "params": [
                "conversationId": "67e55044-10b1-426f-9247-bb680e5fe0c8",
                "callId": "call-42",
                "approvalId": NSNull(),
                "command": ["pwd"],
                "cwd": "/tmp",
                "reason": NSNull(),
                "parsedCmd": []
            ]
        ])
    }

    func testExecCommandApprovalServerResponseMatchesRustWireShape() throws {
        let response = AppServerProtocol.ServerResponse.execCommandApproval(
            requestID: .integer(7),
            response: AppServerProtocol.ExecCommandApprovalResponse(decision: .approvedForSession)
        )

        XCTAssertEqual(response.id, .integer(7))
        XCTAssertEqual(response.method, "execCommandApproval")
        try XCTAssertJSONObjectEqual(response, [
            "method": "execCommandApproval",
            "id": 7,
            "response": [
                "decision": "approved_for_session"
            ]
        ])

        let decoded = try JSONDecoder().decode(
            AppServerProtocol.ServerResponse.self,
            from: Data(#"{"method":"execCommandApproval","id":7,"response":{"decision":"approved_for_session"}}"#.utf8)
        )
        XCTAssertEqual(decoded, response)
    }

    func testApplyPatchApprovalServerRequestMatchesRustWireShape() throws {
        let params = AppServerProtocol.ApplyPatchApprovalParams(
            conversationID: "67e55044-10b1-426f-9247-bb680e5fe0c8",
            callID: "patch-42",
            fileChanges: [
                "/tmp/App.swift": .update(unifiedDiff: "@@ -1 +1 @@\n-old\n+new\n", movePath: nil)
            ],
            reason: nil,
            grantRoot: nil
        )
        let request = AppServerProtocol.ServerRequest.applyPatchApproval(
            requestID: .integer(6),
            params: params
        )

        XCTAssertEqual(request.id, .integer(6))
        XCTAssertEqual(request.method, "applyPatchApproval")
        try XCTAssertJSONObjectEqual(request, [
            "method": "applyPatchApproval",
            "id": 6,
            "params": [
                "conversationId": "67e55044-10b1-426f-9247-bb680e5fe0c8",
                "callId": "patch-42",
                "fileChanges": [
                    "/tmp/App.swift": [
                        "type": "update",
                        "unified_diff": "@@ -1 +1 @@\n-old\n+new\n",
                        "move_path": NSNull()
                    ]
                ],
                "reason": NSNull(),
                "grantRoot": NSNull()
            ]
        ])
        XCTAssertEqual(
            AppServerProtocol.ServerRequestPayload.applyPatchApproval(params).request(withID: .integer(6)),
            request
        )

        let decoded = try JSONDecoder().decode(
            AppServerProtocol.ServerRequest.self,
            from: Data(#"{"method":"applyPatchApproval","id":6,"params":{"conversationId":"67e55044-10b1-426f-9247-bb680e5fe0c8","callId":"patch-42","fileChanges":{"/tmp/App.swift":{"type":"update","unified_diff":"@@ -1 +1 @@\n-old\n+new\n","move_path":null}},"reason":null,"grantRoot":null}}"#.utf8)
        )
        XCTAssertEqual(decoded, request)
    }

    func testApplyPatchApprovalServerResponseMatchesRustWireShape() throws {
        let response = AppServerProtocol.ServerResponse.applyPatchApproval(
            requestID: .integer(6),
            response: AppServerProtocol.ApplyPatchApprovalResponse(decision: .approved)
        )

        XCTAssertEqual(response.id, .integer(6))
        XCTAssertEqual(response.method, "applyPatchApproval")
        try XCTAssertJSONObjectEqual(response, [
            "method": "applyPatchApproval",
            "id": 6,
            "response": [
                "decision": "approved"
            ]
        ])

        let decoded = try JSONDecoder().decode(
            AppServerProtocol.ServerResponse.self,
            from: Data(#"{"method":"applyPatchApproval","id":6,"response":{"decision":"approved"}}"#.utf8)
        )
        XCTAssertEqual(decoded, response)
    }

    func testFileChangeRequestApprovalServerRequestMatchesRustWireShape() throws {
        let params = AppServerProtocol.FileChangeRequestApprovalParams(
            threadID: "thr_123",
            turnID: "turn_123",
            itemID: "item_123",
            startedAtMilliseconds: 42,
            reason: nil,
            grantRoot: nil
        )
        let request = AppServerProtocol.ServerRequest.fileChangeRequestApproval(
            requestID: .integer(5),
            params: params
        )

        XCTAssertEqual(request.id, .integer(5))
        XCTAssertEqual(request.method, "item/fileChange/requestApproval")
        try XCTAssertJSONObjectEqual(request, [
            "method": "item/fileChange/requestApproval",
            "id": 5,
            "params": [
                "threadId": "thr_123",
                "turnId": "turn_123",
                "itemId": "item_123",
                "startedAtMs": 42,
                "reason": NSNull(),
                "grantRoot": NSNull()
            ]
        ])
        XCTAssertEqual(
            AppServerProtocol.ServerRequestPayload.fileChangeRequestApproval(params).request(withID: .integer(5)),
            request
        )

        let decoded = try JSONDecoder().decode(
            AppServerProtocol.ServerRequest.self,
            from: Data(#"{"method":"item/fileChange/requestApproval","id":5,"params":{"threadId":"thr_123","turnId":"turn_123","itemId":"item_123","startedAtMs":42,"reason":null,"grantRoot":null}}"#.utf8)
        )
        XCTAssertEqual(decoded, request)
    }

    func testFileChangeRequestApprovalServerResponseMatchesRustWireShape() throws {
        let response = AppServerProtocol.ServerResponse.fileChangeRequestApproval(
            requestID: .integer(5),
            response: AppServerProtocol.FileChangeRequestApprovalResponse(decision: .acceptForSession)
        )

        XCTAssertEqual(response.id, .integer(5))
        XCTAssertEqual(response.method, "item/fileChange/requestApproval")
        try XCTAssertJSONObjectEqual(response, [
            "method": "item/fileChange/requestApproval",
            "id": 5,
            "response": [
                "decision": "acceptForSession"
            ]
        ])

        let decoded = try JSONDecoder().decode(
            AppServerProtocol.ServerResponse.self,
            from: Data(#"{"method":"item/fileChange/requestApproval","id":5,"response":{"decision":"acceptForSession"}}"#.utf8)
        )
        XCTAssertEqual(decoded, response)
    }

    func testCommandExecutionRequestApprovalServerRequestMatchesRustWireShape() throws {
        let execAmendment = ExecPolicyAmendment(command: ["git", "status"])
        let networkAmendment = NetworkPolicyAmendment(host: "example.com", action: .allow)
        let params = AppServerProtocol.CommandExecutionRequestApprovalParams(
            threadID: "thr_123",
            turnID: "turn_123",
            itemID: "item_123",
            startedAtMilliseconds: 43,
            reason: "needs network",
            networkApprovalContext: NetworkApprovalContext(host: "example.com", protocol: .https),
            command: "git status",
            cwd: "/tmp/project",
            commandActions: [
                .read(command: "cat Package.swift", name: "Package.swift", path: "/tmp/project/Package.swift"),
                .listFiles(command: "ls Sources", path: "Sources")
            ],
            additionalPermissions: AppServerProtocol.AdditionalPermissionProfile(
                network: RequestPermissionNetworkPermissions(enabled: true),
                fileSystem: FileSystemPermissions(read: ["/tmp/project"])
            ),
            proposedExecPolicyAmendment: execAmendment,
            proposedNetworkPolicyAmendments: [networkAmendment],
            availableDecisions: [
                .accept,
                .acceptWithExecpolicyAmendment(execpolicyAmendment: execAmendment),
                .applyNetworkPolicyAmendment(networkPolicyAmendment: networkAmendment),
                .cancel
            ]
        )
        let request = AppServerProtocol.ServerRequest.commandExecutionRequestApproval(
            requestID: .integer(4),
            params: params
        )

        XCTAssertEqual(request.id, .integer(4))
        XCTAssertEqual(request.method, "item/commandExecution/requestApproval")
        try XCTAssertJSONObjectEqual(request, [
            "method": "item/commandExecution/requestApproval",
            "id": 4,
            "params": [
                "threadId": "thr_123",
                "turnId": "turn_123",
                "itemId": "item_123",
                "startedAtMs": 43,
                "reason": "needs network",
                "networkApprovalContext": [
                    "host": "example.com",
                    "protocol": "https"
                ],
                "command": "git status",
                "cwd": "/tmp/project",
                "commandActions": [
                    [
                        "type": "read",
                        "command": "cat Package.swift",
                        "name": "Package.swift",
                        "path": "/tmp/project/Package.swift"
                    ],
                    [
                        "type": "listFiles",
                        "command": "ls Sources",
                        "path": "Sources"
                    ]
                ],
                "additionalPermissions": [
                    "network": [
                        "enabled": true
                    ],
                    "fileSystem": [
                        "read": ["/tmp/project"],
                        "write": NSNull(),
                        "entries": [
                            [
                                "path": [
                                    "type": "path",
                                    "path": "/tmp/project"
                                ],
                                "access": "read"
                            ]
                        ]
                    ]
                ],
                "proposedExecpolicyAmendment": ["git", "status"],
                "proposedNetworkPolicyAmendments": [
                    [
                        "host": "example.com",
                        "action": "allow"
                    ]
                ],
                "availableDecisions": [
                    "accept",
                    [
                        "acceptWithExecpolicyAmendment": [
                            "execpolicy_amendment": ["git", "status"]
                        ]
                    ],
                    [
                        "applyNetworkPolicyAmendment": [
                            "network_policy_amendment": [
                                "host": "example.com",
                                "action": "allow"
                            ]
                        ]
                    ],
                    "cancel"
                ]
            ]
        ])
        XCTAssertEqual(
            AppServerProtocol.ServerRequestPayload.commandExecutionRequestApproval(params).request(withID: .integer(4)),
            request
        )

        let decoded = try JSONDecoder().decode(
            AppServerProtocol.ServerRequest.self,
            from: Data(#"{"method":"item/commandExecution/requestApproval","id":4,"params":{"threadId":"thr_123","turnId":"turn_123","itemId":"item_123","startedAtMs":43,"reason":"needs network","networkApprovalContext":{"host":"example.com","protocol":"https"},"command":"git status","cwd":"/tmp/project","commandActions":[{"type":"read","command":"cat Package.swift","name":"Package.swift","path":"/tmp/project/Package.swift"},{"type":"listFiles","command":"ls Sources","path":"Sources"}],"additionalPermissions":{"network":{"enabled":true},"fileSystem":{"read":["/tmp/project"],"write":null,"entries":[{"path":{"type":"path","path":"/tmp/project"},"access":"read"}]}},"proposedExecpolicyAmendment":["git","status"],"proposedNetworkPolicyAmendments":[{"host":"example.com","action":"allow"}],"availableDecisions":["accept",{"acceptWithExecpolicyAmendment":{"execpolicy_amendment":["git","status"]}},{"applyNetworkPolicyAmendment":{"network_policy_amendment":{"host":"example.com","action":"allow"}}},"cancel"]}}"#.utf8)
        )
        XCTAssertEqual(decoded, request)
    }

    func testCommandExecutionRequestApprovalSkipsNilOptionalsLikeRust() throws {
        let request = AppServerProtocol.ServerRequest.commandExecutionRequestApproval(
            requestID: .integer(4),
            params: AppServerProtocol.CommandExecutionRequestApprovalParams(
                threadID: "thr_123",
                turnID: "turn_123",
                itemID: "item_123",
                startedAtMilliseconds: 43
            )
        )

        try XCTAssertJSONObjectEqual(request, [
            "method": "item/commandExecution/requestApproval",
            "id": 4,
            "params": [
                "threadId": "thr_123",
                "turnId": "turn_123",
                "itemId": "item_123",
                "startedAtMs": 43
            ]
        ])
    }

    func testCommandExecutionRequestApprovalRedactsAdditionalPermissionsWithoutExperimentalAPI() throws {
        let params = AppServerProtocol.CommandExecutionRequestApprovalParams(
            threadID: "thr_123",
            turnID: "turn_123",
            itemID: "call_123",
            startedAtMilliseconds: 0,
            reason: "Need extra read access",
            command: "cat file",
            cwd: "/tmp",
            additionalPermissions: AppServerProtocol.AdditionalPermissionProfile(
                fileSystem: FileSystemPermissions(read: ["/tmp/allowed"])
            )
        )
        let request = AppServerProtocol.ServerRequest.commandExecutionRequestApproval(
            requestID: .integer(1),
            params: params
        )

        let redacted = request.redactingExperimentalFields(experimentalAPIEnabled: false)

        try XCTAssertJSONObjectEqual(redacted, [
            "method": "item/commandExecution/requestApproval",
            "id": 1,
            "params": [
                "threadId": "thr_123",
                "turnId": "turn_123",
                "itemId": "call_123",
                "startedAtMs": 0,
                "reason": "Need extra read access",
                "command": "cat file",
                "cwd": "/tmp"
            ]
        ])
    }

    func testCommandExecutionRequestApprovalKeepsAdditionalPermissionsWithExperimentalAPI() throws {
        let params = AppServerProtocol.CommandExecutionRequestApprovalParams(
            threadID: "thr_123",
            turnID: "turn_123",
            itemID: "call_123",
            startedAtMilliseconds: 0,
            reason: "Need extra read access",
            command: "cat file",
            cwd: "/tmp",
            additionalPermissions: AppServerProtocol.AdditionalPermissionProfile(
                fileSystem: FileSystemPermissions(read: ["/tmp/allowed"])
            )
        )
        let request = AppServerProtocol.ServerRequest.commandExecutionRequestApproval(
            requestID: .integer(1),
            params: params
        )

        let preserved = request.redactingExperimentalFields(experimentalAPIEnabled: true)

        try XCTAssertJSONObjectEqual(preserved, [
            "method": "item/commandExecution/requestApproval",
            "id": 1,
            "params": [
                "threadId": "thr_123",
                "turnId": "turn_123",
                "itemId": "call_123",
                "startedAtMs": 0,
                "reason": "Need extra read access",
                "command": "cat file",
                "cwd": "/tmp",
                "additionalPermissions": [
                    "fileSystem": [
                        "read": ["/tmp/allowed"],
                        "write": NSNull(),
                        "entries": [
                            [
                                "path": [
                                    "type": "path",
                                    "path": "/tmp/allowed"
                                ],
                                "access": "read"
                            ]
                        ]
                    ]
                ]
            ]
        ])
    }

    func testCommandExecutionRequestApprovalServerResponseMatchesRustWireShape() throws {
        let response = AppServerProtocol.ServerResponse.commandExecutionRequestApproval(
            requestID: .integer(8),
            response: AppServerProtocol.CommandExecutionRequestApprovalResponse(decision: .acceptForSession)
        )

        XCTAssertEqual(response.id, .integer(8))
        XCTAssertEqual(response.method, "item/commandExecution/requestApproval")
        try XCTAssertJSONObjectEqual(response, [
            "method": "item/commandExecution/requestApproval",
            "id": 8,
            "response": [
                "decision": "acceptForSession"
            ]
        ])

        let decoded = try JSONDecoder().decode(
            AppServerProtocol.ServerResponse.self,
            from: Data(#"{"method":"item/commandExecution/requestApproval","id":8,"response":{"decision":"acceptForSession"}}"#.utf8)
        )
        XCTAssertEqual(decoded, response)
    }

    func testToolRequestUserInputServerRequestMatchesRustWireShape() throws {
        let params = AppServerProtocol.ToolRequestUserInputParams(
            threadID: "thr_123",
            turnID: "turn_123",
            itemID: "item_123",
            questions: [
                RequestUserInputQuestion(
                    id: "choice",
                    header: "Pick",
                    question: "Which mode?",
                    options: [
                        RequestUserInputQuestionOption(label: "Auto", description: "Let Codex decide")
                    ]
                )
            ]
        )
        let request = AppServerProtocol.ServerRequest.toolRequestUserInput(
            requestID: .integer(3),
            params: params
        )

        XCTAssertEqual(request.id, .integer(3))
        XCTAssertEqual(request.method, "item/tool/requestUserInput")
        try XCTAssertJSONObjectEqual(request, [
            "method": "item/tool/requestUserInput",
            "id": 3,
            "params": [
                "threadId": "thr_123",
                "turnId": "turn_123",
                "itemId": "item_123",
                "questions": [
                    [
                        "id": "choice",
                        "header": "Pick",
                        "question": "Which mode?",
                        "isOther": false,
                        "isSecret": false,
                        "options": [
                            [
                                "label": "Auto",
                                "description": "Let Codex decide"
                            ]
                        ]
                    ]
                ]
            ]
        ])
        XCTAssertEqual(
            AppServerProtocol.ServerRequestPayload.toolRequestUserInput(params).request(withID: .integer(3)),
            request
        )

        let decoded = try JSONDecoder().decode(
            AppServerProtocol.ServerRequest.self,
            from: Data(#"{"method":"item/tool/requestUserInput","id":3,"params":{"threadId":"thr_123","turnId":"turn_123","itemId":"item_123","questions":[{"id":"choice","header":"Pick","question":"Which mode?","options":[{"label":"Auto","description":"Let Codex decide"}]}]}}"#.utf8)
        )
        XCTAssertEqual(decoded, request)
    }

    func testToolRequestUserInputServerResponseMatchesRustWireShape() throws {
        let response = AppServerProtocol.ServerResponse.toolRequestUserInput(
            requestID: .integer(3),
            response: AppServerProtocol.ToolRequestUserInputResponse(
                answers: [
                    "choice": RequestUserInputAnswer(answers: ["Auto"])
                ]
            )
        )

        XCTAssertEqual(response.id, .integer(3))
        XCTAssertEqual(response.method, "item/tool/requestUserInput")
        try XCTAssertJSONObjectEqual(response, [
            "method": "item/tool/requestUserInput",
            "id": 3,
            "response": [
                "answers": [
                    "choice": [
                        "answers": ["Auto"]
                    ]
                ]
            ]
        ])

        let decoded = try JSONDecoder().decode(
            AppServerProtocol.ServerResponse.self,
            from: Data(#"{"method":"item/tool/requestUserInput","id":3,"response":{"answers":{"choice":{"answers":["Auto"]}}}}"#.utf8)
        )
        XCTAssertEqual(decoded, response)
    }

    func testDynamicToolCallServerRequestMatchesRustWireShape() throws {
        let params = AppServerProtocol.DynamicToolCallParams(
            threadID: "thr_123",
            turnID: "turn_123",
            callID: "call_123",
            namespace: nil,
            tool: "summarize",
            arguments: .object([
                "topic": .string("protocol"),
                "limit": .integer(3)
            ])
        )
        let request = AppServerProtocol.ServerRequest.dynamicToolCall(
            requestID: .integer(2),
            params: params
        )

        XCTAssertEqual(request.id, .integer(2))
        XCTAssertEqual(request.method, "item/tool/call")
        try XCTAssertJSONObjectEqual(request, [
            "method": "item/tool/call",
            "id": 2,
            "params": [
                "threadId": "thr_123",
                "turnId": "turn_123",
                "callId": "call_123",
                "namespace": NSNull(),
                "tool": "summarize",
                "arguments": [
                    "topic": "protocol",
                    "limit": 3
                ]
            ]
        ])
        XCTAssertEqual(
            AppServerProtocol.ServerRequestPayload.dynamicToolCall(params).request(withID: .integer(2)),
            request
        )

        let decoded = try JSONDecoder().decode(
            AppServerProtocol.ServerRequest.self,
            from: Data(#"{"method":"item/tool/call","id":2,"params":{"threadId":"thr_123","turnId":"turn_123","callId":"call_123","namespace":null,"tool":"summarize","arguments":{"topic":"protocol","limit":3}}}"#.utf8)
        )
        XCTAssertEqual(decoded, request)
    }

    func testDynamicToolCallServerResponseMatchesRustWireShape() throws {
        let response = AppServerProtocol.ServerResponse.dynamicToolCall(
            requestID: .integer(2),
            response: AppServerProtocol.DynamicToolCallResponse(
                contentItems: [
                    .text("done"),
                    .imageURL("file:///tmp/image.png")
                ],
                success: true
            )
        )

        XCTAssertEqual(response.id, .integer(2))
        XCTAssertEqual(response.method, "item/tool/call")
        try XCTAssertJSONObjectEqual(response, [
            "method": "item/tool/call",
            "id": 2,
            "response": [
                "contentItems": [
                    [
                        "type": "inputText",
                        "text": "done"
                    ],
                    [
                        "type": "inputImage",
                        "imageUrl": "file:///tmp/image.png"
                    ]
                ],
                "success": true
            ]
        ])

        let decoded = try JSONDecoder().decode(
            AppServerProtocol.ServerResponse.self,
            from: Data(#"{"method":"item/tool/call","id":2,"response":{"contentItems":[{"type":"inputText","text":"done"},{"type":"inputImage","imageUrl":"file:///tmp/image.png"}],"success":true}}"#.utf8)
        )
        XCTAssertEqual(decoded, response)
    }

    func testPermissionsRequestApprovalServerRequestMatchesRustWireShape() throws {
        let params = AppServerProtocol.PermissionsRequestApprovalParams(
            threadID: "thr_123",
            turnID: "turn_123",
            itemID: "item_123",
            startedAtMilliseconds: 44,
            cwd: "/tmp/project",
            reason: nil,
            permissions: AppServerProtocol.PermissionsProfile(
                network: RequestPermissionNetworkPermissions(enabled: true),
                fileSystem: FileSystemPermissions(read: ["/tmp/project"], write: ["/tmp/project/Sources"])
            )
        )
        let request = AppServerProtocol.ServerRequest.permissionsRequestApproval(
            requestID: .integer(1),
            params: params
        )

        XCTAssertEqual(request.id, .integer(1))
        XCTAssertEqual(request.method, "item/permissions/requestApproval")
        try XCTAssertJSONObjectEqual(request, [
            "method": "item/permissions/requestApproval",
            "id": 1,
            "params": [
                "threadId": "thr_123",
                "turnId": "turn_123",
                "itemId": "item_123",
                "startedAtMs": 44,
                "cwd": "/tmp/project",
                "reason": NSNull(),
                "permissions": [
                    "network": [
                        "enabled": true
                    ],
                    "fileSystem": [
                        "read": ["/tmp/project"],
                        "write": ["/tmp/project/Sources"],
                        "entries": [
                            [
                                "path": [
                                    "type": "path",
                                    "path": "/tmp/project"
                                ],
                                "access": "read"
                            ],
                            [
                                "path": [
                                    "type": "path",
                                    "path": "/tmp/project/Sources"
                                ],
                                "access": "write"
                            ]
                        ]
                    ]
                ]
            ]
        ])
        XCTAssertEqual(
            AppServerProtocol.ServerRequestPayload.permissionsRequestApproval(params).request(withID: .integer(1)),
            request
        )

        let decoded = try JSONDecoder().decode(
            AppServerProtocol.ServerRequest.self,
            from: Data(#"{"method":"item/permissions/requestApproval","id":1,"params":{"threadId":"thr_123","turnId":"turn_123","itemId":"item_123","startedAtMs":44,"cwd":"/tmp/project","reason":null,"permissions":{"network":{"enabled":true},"fileSystem":{"read":["/tmp/project"],"write":["/tmp/project/Sources"],"entries":[{"path":{"type":"path","path":"/tmp/project"},"access":"read"},{"path":{"type":"path","path":"/tmp/project/Sources"},"access":"write"}]}}}}"#.utf8)
        )
        XCTAssertEqual(decoded, request)
    }

    func testPermissionsRequestApprovalServerResponseMatchesRustWireShapeAndDefaults() throws {
        let response = AppServerProtocol.ServerResponse.permissionsRequestApproval(
            requestID: .integer(1),
            response: AppServerProtocol.PermissionsRequestApprovalResponse(
                permissions: AppServerProtocol.GrantedPermissionProfile(),
                scope: .turn,
                strictAutoReview: nil
            )
        )

        XCTAssertEqual(response.id, .integer(1))
        XCTAssertEqual(response.method, "item/permissions/requestApproval")
        try XCTAssertJSONObjectEqual(response, [
            "method": "item/permissions/requestApproval",
            "id": 1,
            "response": [
                "permissions": [String: Any](),
                "scope": "turn"
            ]
        ])

        let decodedWithDefaultScope = try JSONDecoder().decode(
            AppServerProtocol.ServerResponse.self,
            from: Data(#"{"method":"item/permissions/requestApproval","id":1,"response":{"permissions":{}}}"#.utf8)
        )
        XCTAssertEqual(decodedWithDefaultScope, response)
    }

    func testPermissionsRequestApprovalServerResponseEncodesStrictAutoReview() throws {
        let response = AppServerProtocol.ServerResponse.permissionsRequestApproval(
            requestID: .integer(1),
            response: AppServerProtocol.PermissionsRequestApprovalResponse(
                permissions: AppServerProtocol.GrantedPermissionProfile(
                    network: RequestPermissionNetworkPermissions(enabled: true)
                ),
                scope: .session,
                strictAutoReview: true
            )
        )

        try XCTAssertJSONObjectEqual(response, [
            "method": "item/permissions/requestApproval",
            "id": 1,
            "response": [
                "permissions": [
                    "network": [
                        "enabled": true
                    ]
                ],
                "scope": "session",
                "strictAutoReview": true
            ]
        ])
    }

    func testMcpServerElicitationUrlRequestMatchesRustWireShape() throws {
        let params = AppServerProtocol.McpServerElicitationRequestParams(
            threadID: "thr_123",
            turnID: nil,
            serverName: "github",
            request: .url(
                meta: nil,
                message: "Finish GitHub sign-in",
                url: "https://example.test/device",
                elicitationID: "elicitation_123"
            )
        )
        let request = AppServerProtocol.ServerRequest.mcpServerElicitationRequest(
            requestID: .integer(10),
            params: params
        )

        XCTAssertEqual(request.id, .integer(10))
        XCTAssertEqual(request.method, "mcpServer/elicitation/request")
        try XCTAssertJSONObjectEqual(request, [
            "method": "mcpServer/elicitation/request",
            "id": 10,
            "params": [
                "threadId": "thr_123",
                "turnId": NSNull(),
                "serverName": "github",
                "mode": "url",
                "_meta": NSNull(),
                "message": "Finish GitHub sign-in",
                "url": "https://example.test/device",
                "elicitationId": "elicitation_123"
            ]
        ])
        XCTAssertEqual(
            AppServerProtocol.ServerRequestPayload.mcpServerElicitationRequest(params).request(withID: .integer(10)),
            request
        )

        let decoded = try JSONDecoder().decode(
            AppServerProtocol.ServerRequest.self,
            from: Data(#"{"method":"mcpServer/elicitation/request","id":10,"params":{"threadId":"thr_123","turnId":null,"serverName":"github","mode":"url","_meta":null,"message":"Finish GitHub sign-in","url":"https://example.test/device","elicitationId":"elicitation_123"}}"#.utf8)
        )
        XCTAssertEqual(decoded, request)
    }

    func testMcpServerElicitationFormRequestMatchesRustWireShape() throws {
        let request = AppServerProtocol.ServerRequest.mcpServerElicitationRequest(
            requestID: .integer(11),
            params: AppServerProtocol.McpServerElicitationRequestParams(
                threadID: "thr_123",
                turnID: "turn_123",
                serverName: "linear",
                request: .form(
                    meta: .object(["source": .string("mcp")]),
                    message: "Choose an issue",
                    requestedSchema: AppServerProtocol.McpElicitationSchema(
                        properties: [
                            "issueId": .string(AppServerProtocol.McpElicitationStringSchema(
                                title: "Issue ID"
                            ))
                        ]
                    )
                )
            )
        )

        try XCTAssertJSONObjectEqual(request, [
            "method": "mcpServer/elicitation/request",
            "id": 11,
            "params": [
                "threadId": "thr_123",
                "turnId": "turn_123",
                "serverName": "linear",
                "mode": "form",
                "_meta": [
                    "source": "mcp"
                ],
                "message": "Choose an issue",
                "requestedSchema": [
                    "type": "object",
                    "properties": [
                        "issueId": [
                            "type": "string",
                            "title": "Issue ID"
                        ]
                    ]
                ]
            ]
        ])

        let decoded = try JSONDecoder().decode(
            AppServerProtocol.ServerRequest.self,
            from: Data(#"{"method":"mcpServer/elicitation/request","id":11,"params":{"threadId":"thr_123","turnId":"turn_123","serverName":"linear","mode":"form","_meta":{"source":"mcp"},"message":"Choose an issue","requestedSchema":{"type":"object","properties":{"issueId":{"type":"string","title":"Issue ID"}}}}}"#.utf8)
        )
        XCTAssertEqual(decoded, request)
    }

    func testMcpElicitationSchemaPrimitiveVariantsMatchRustWireShape() throws {
        let schema = AppServerProtocol.McpElicitationSchema(
            schemaURI: "https://json-schema.org/draft/2020-12/schema",
            properties: [
                "email": .string(AppServerProtocol.McpElicitationStringSchema(
                    title: "Email",
                    minLength: 3,
                    maxLength: 80,
                    format: .email,
                    defaultValue: "agent@example.test"
                )),
                "count": .number(AppServerProtocol.McpElicitationNumberSchema(
                    type: .integer,
                    minimum: 1,
                    maximum: 5,
                    defaultValue: 2
                )),
                "enabled": .boolean(AppServerProtocol.McpElicitationBooleanSchema(
                    defaultValue: true
                )),
                "color": .enumSchema(.singleSelect(.untitled(
                    AppServerProtocol.McpElicitationUntitledSingleSelectEnumSchema(
                        values: ["red", "blue"],
                        defaultValue: "red"
                    )
                ))),
                "mode": .enumSchema(.singleSelect(.titled(
                    AppServerProtocol.McpElicitationTitledSingleSelectEnumSchema(
                        oneOf: [
                            AppServerProtocol.McpElicitationConstOption(constValue: "auto", title: "Auto"),
                            AppServerProtocol.McpElicitationConstOption(constValue: "manual", title: "Manual")
                        ]
                    )
                ))),
                "legacy": .enumSchema(.legacy(AppServerProtocol.McpElicitationLegacyTitledEnumSchema(
                    values: ["small", "large"],
                    enumNames: ["Small", "Large"]
                ))),
                "tags": .enumSchema(.multiSelect(.titled(
                    AppServerProtocol.McpElicitationTitledMultiSelectEnumSchema(
                        minItems: 1,
                        maxItems: 2,
                        items: AppServerProtocol.McpElicitationTitledEnumItems(anyOf: [
                            AppServerProtocol.McpElicitationConstOption(constValue: "ios", title: "iOS"),
                            AppServerProtocol.McpElicitationConstOption(constValue: "macos", title: "macOS")
                        ]),
                        defaultValue: ["ios"]
                    )
                )))
            ],
            required: ["email", "mode"]
        )

        try XCTAssertJSONObjectEqual(schema, [
            "$schema": "https://json-schema.org/draft/2020-12/schema",
            "type": "object",
            "properties": [
                "email": [
                    "type": "string",
                    "title": "Email",
                    "minLength": 3,
                    "maxLength": 80,
                    "format": "email",
                    "default": "agent@example.test"
                ],
                "count": [
                    "type": "integer",
                    "minimum": 1.0,
                    "maximum": 5.0,
                    "default": 2.0
                ],
                "enabled": [
                    "type": "boolean",
                    "default": true
                ],
                "color": [
                    "type": "string",
                    "enum": ["red", "blue"],
                    "default": "red"
                ],
                "mode": [
                    "type": "string",
                    "oneOf": [
                        ["const": "auto", "title": "Auto"],
                        ["const": "manual", "title": "Manual"]
                    ]
                ],
                "legacy": [
                    "type": "string",
                    "enum": ["small", "large"],
                    "enumNames": ["Small", "Large"]
                ],
                "tags": [
                    "type": "array",
                    "minItems": 1,
                    "maxItems": 2,
                    "items": [
                        "anyOf": [
                            ["const": "ios", "title": "iOS"],
                            ["const": "macos", "title": "macOS"]
                        ]
                    ],
                    "default": ["ios"]
                ]
            ],
            "required": ["email", "mode"]
        ])

        let decoded = try JSONDecoder().decode(
            AppServerProtocol.McpElicitationSchema.self,
            from: Data(#"{"$schema":"https://json-schema.org/draft/2020-12/schema","type":"object","properties":{"email":{"type":"string","title":"Email","minLength":3,"maxLength":80,"format":"email","default":"agent@example.test"},"count":{"type":"integer","minimum":1,"maximum":5,"default":2},"enabled":{"type":"boolean","default":true},"color":{"type":"string","enum":["red","blue"],"default":"red"},"mode":{"type":"string","oneOf":[{"const":"auto","title":"Auto"},{"const":"manual","title":"Manual"}]},"legacy":{"type":"string","enum":["small","large"],"enumNames":["Small","Large"]},"tags":{"type":"array","minItems":1,"maxItems":2,"items":{"oneOf":[{"const":"ios","title":"iOS"},{"const":"macos","title":"macOS"}]},"default":["ios"]}},"required":["email","mode"]}"#.utf8)
        )
        XCTAssertEqual(decoded, schema)
    }

    func testMcpServerElicitationServerResponseMatchesRustWireShape() throws {
        let response = AppServerProtocol.ServerResponse.mcpServerElicitationRequest(
            requestID: .integer(10),
            response: AppServerProtocol.McpServerElicitationRequestResponse(
                action: .decline,
                content: nil,
                meta: nil
            )
        )

        XCTAssertEqual(response.id, .integer(10))
        XCTAssertEqual(response.method, "mcpServer/elicitation/request")
        try XCTAssertJSONObjectEqual(response, [
            "method": "mcpServer/elicitation/request",
            "id": 10,
            "response": [
                "action": "decline",
                "content": NSNull(),
                "_meta": NSNull()
            ]
        ])

        let decoded = try JSONDecoder().decode(
            AppServerProtocol.ServerResponse.self,
            from: Data(#"{"method":"mcpServer/elicitation/request","id":10,"response":{"action":"decline","content":null,"_meta":null}}"#.utf8)
        )
        XCTAssertEqual(decoded, response)
    }

    func testUnknownServerRequestMethodFailsLikeTaggedRustEnum() {
        XCTAssertThrowsError(try JSONDecoder().decode(
            AppServerProtocol.ServerRequest.self,
            from: Data(#"{"method":"attestation/unknown","id":1,"params":{}}"#.utf8)
        ))
    }
}
