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

    func testUnknownServerRequestMethodFailsLikeTaggedRustEnum() {
        XCTAssertThrowsError(try JSONDecoder().decode(
            AppServerProtocol.ServerRequest.self,
            from: Data(#"{"method":"attestation/unknown","id":1,"params":{}}"#.utf8)
        ))
    }
}
