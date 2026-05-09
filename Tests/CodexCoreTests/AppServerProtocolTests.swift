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
                fileSystem: .object(["read": .array([.string("/tmp/project")])])
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
                        "read": ["/tmp/project"]
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
            from: Data(#"{"method":"item/commandExecution/requestApproval","id":4,"params":{"threadId":"thr_123","turnId":"turn_123","itemId":"item_123","startedAtMs":43,"reason":"needs network","networkApprovalContext":{"host":"example.com","protocol":"https"},"command":"git status","cwd":"/tmp/project","commandActions":[{"type":"read","command":"cat Package.swift","name":"Package.swift","path":"/tmp/project/Package.swift"},{"type":"listFiles","command":"ls Sources","path":"Sources"}],"additionalPermissions":{"network":{"enabled":true},"fileSystem":{"read":["/tmp/project"]}},"proposedExecpolicyAmendment":["git","status"],"proposedNetworkPolicyAmendments":[{"host":"example.com","action":"allow"}],"availableDecisions":["accept",{"acceptWithExecpolicyAmendment":{"execpolicy_amendment":["git","status"]}},{"applyNetworkPolicyAmendment":{"network_policy_amendment":{"host":"example.com","action":"allow"}}},"cancel"]}}"#.utf8)
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

    func testUnknownServerRequestMethodFailsLikeTaggedRustEnum() {
        XCTAssertThrowsError(try JSONDecoder().decode(
            AppServerProtocol.ServerRequest.self,
            from: Data(#"{"method":"attestation/unknown","id":1,"params":{}}"#.utf8)
        ))
    }
}
