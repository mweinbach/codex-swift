import CodexCore
import XCTest

final class AppServerAccountProtocolTests: XCTestCase {
    func testAccountVariantsEncodeRustTaggedShape() throws {
        try XCTAssertJSONObjectEqual(Account.apiKey, ["type": "apiKey"])
        try XCTAssertJSONObjectEqual(Account.amazonBedrock, ["type": "amazonBedrock"])
        try XCTAssertJSONObjectEqual(
            Account.chatGPT(email: "user@example.com", planType: .pro),
            [
                "type": "chatgpt",
                "email": "user@example.com",
                "planType": "pro"
            ]
        )
    }

    func testGetAccountParamsDefaultAndEncodingMatchRustProtocol() throws {
        let decoded = try JSONDecoder().decode(GetAccountParams.self, from: Data(#"{}"#.utf8))
        XCTAssertEqual(decoded, GetAccountParams(refreshToken: false))

        try XCTAssertJSONObjectEqual(
            GetAccountParams(),
            [
                "refreshToken": false
            ]
        )
        try XCTAssertJSONObjectEqual(
            GetAccountParams(refreshToken: true),
            [
                "refreshToken": true
            ]
        )
    }

    func testGetAccountResponseEncodesExplicitNullAccountLikeRustProtocol() throws {
        try XCTAssertJSONObjectEqual(
            GetAccountResponse(account: nil, requiresOpenAIAuth: true),
            [
                "account": NSNull(),
                "requiresOpenAIAuth": true
            ]
        )

        try XCTAssertJSONObjectEqual(
            GetAccountResponse(
                account: .chatGPT(email: "user@example.com", planType: .team),
                requiresOpenAIAuth: false
            ),
            [
                "account": [
                    "type": "chatgpt",
                    "email": "user@example.com",
                    "planType": "team"
                ],
                "requiresOpenAIAuth": false
            ]
        )
    }

    func testAccountNotificationsEncodeExplicitNullOptionalsLikeRustProtocol() throws {
        try XCTAssertJSONObjectEqual(
            AccountUpdatedNotification(authMode: nil, planType: nil),
            [
                "authMode": NSNull(),
                "planType": NSNull()
            ]
        )
        try XCTAssertJSONObjectEqual(
            AccountUpdatedNotification(authMode: .chatGPTAuthTokens, planType: .pro),
            [
                "authMode": "chatgptAuthTokens",
                "planType": "pro"
            ]
        )

        try XCTAssertJSONObjectEqual(
            AccountLoginCompletedNotification(loginID: nil, success: false, error: "denied"),
            [
                "loginId": NSNull(),
                "success": false,
                "error": "denied"
            ]
        )
        try XCTAssertJSONObjectEqual(
            AccountLoginCompletedNotification(loginID: "login-1", success: true, error: nil),
            [
                "loginId": "login-1",
                "success": true,
                "error": NSNull()
            ]
        )
    }

    func testAccountDecodeMatchesRustProtocol() throws {
        let account = try JSONDecoder().decode(
            Account.self,
            from: Data(#"{"type":"chatgpt","email":"user@example.com","planType":"enterprise"}"#.utf8)
        )
        XCTAssertEqual(account, .chatGPT(email: "user@example.com", planType: .enterprise))

        let response = try JSONDecoder().decode(
            GetAccountResponse.self,
            from: Data(#"{"account":null,"requiresOpenAIAuth":false}"#.utf8)
        )
        XCTAssertEqual(response, GetAccountResponse(account: nil, requiresOpenAIAuth: false))
    }
}
