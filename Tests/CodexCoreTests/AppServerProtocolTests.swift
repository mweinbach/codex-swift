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

    func testUnknownServerRequestMethodFailsLikeTaggedRustEnum() {
        XCTAssertThrowsError(try JSONDecoder().decode(
            AppServerProtocol.ServerRequest.self,
            from: Data(#"{"method":"attestation/unknown","id":1,"params":{}}"#.utf8)
        ))
    }
}
