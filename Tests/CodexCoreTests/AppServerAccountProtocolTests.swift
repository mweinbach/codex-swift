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

    func testLoginAccountParamsEncodeRustTaggedShape() throws {
        try XCTAssertJSONObjectEqual(
            LoginAccountParams.apiKey(apiKey: "sk-test"),
            [
                "type": "apiKey",
                "apiKey": "sk-test"
            ]
        )
        try XCTAssertJSONObjectEqual(
            LoginAccountParams.chatGPT(codexStreamlinedLogin: false),
            [
                "type": "chatgpt"
            ]
        )
        try XCTAssertJSONObjectEqual(
            LoginAccountParams.chatGPT(codexStreamlinedLogin: true),
            [
                "type": "chatgpt",
                "codexStreamlinedLogin": true
            ]
        )
        try XCTAssertJSONObjectEqual(
            LoginAccountParams.chatGPTDeviceCode,
            [
                "type": "chatgptDeviceCode"
            ]
        )
        try XCTAssertJSONObjectEqual(
            LoginAccountParams.chatGPTAuthTokens(
                accessToken: "access-token",
                chatGPTAccountID: "org-1",
                chatGPTPlanType: nil
            ),
            [
                "type": "chatgptAuthTokens",
                "accessToken": "access-token",
                "chatgptAccountId": "org-1",
                "chatgptPlanType": NSNull()
            ]
        )
    }

    func testLoginAccountResponseEncodeRustTaggedShape() throws {
        try XCTAssertJSONObjectEqual(LoginAccountResponse.apiKey, ["type": "apiKey"])
        try XCTAssertJSONObjectEqual(
            LoginAccountResponse.chatGPT(loginID: "login-1", authURL: "https://example.test/auth"),
            [
                "type": "chatgpt",
                "loginId": "login-1",
                "authUrl": "https://example.test/auth"
            ]
        )
        try XCTAssertJSONObjectEqual(
            LoginAccountResponse.chatGPTDeviceCode(
                loginID: "login-2",
                verificationURL: "https://example.test/device",
                userCode: "ABCD-EFGH"
            ),
            [
                "type": "chatgptDeviceCode",
                "loginId": "login-2",
                "verificationUrl": "https://example.test/device",
                "userCode": "ABCD-EFGH"
            ]
        )
        try XCTAssertJSONObjectEqual(LoginAccountResponse.chatGPTAuthTokens, ["type": "chatgptAuthTokens"])
    }

    func testLoginSupportPayloadsEncodeRustWireShapes() throws {
        try XCTAssertJSONObjectEqual(
            CancelLoginAccountParams(loginID: "login-1"),
            [
                "loginId": "login-1"
            ]
        )
        try XCTAssertJSONObjectEqual(
            CancelLoginAccountResponse(status: .notFound),
            [
                "status": "notFound"
            ]
        )
        try XCTAssertJSONObjectEqual(LogoutAccountResponse(), [:])
    }

    func testExternalAuthTokenRefreshPayloadsEncodeExplicitNullOptionalsLikeRustProtocol() throws {
        try XCTAssertJSONObjectEqual(
            ChatGPTAuthTokensRefreshParams(reason: .unauthorized, previousAccountID: nil),
            [
                "reason": "unauthorized",
                "previousAccountId": NSNull()
            ]
        )
        try XCTAssertJSONObjectEqual(
            ChatGPTAuthTokensRefreshResponse(
                accessToken: "replacement-token",
                chatGPTAccountID: "org-1",
                chatGPTPlanType: nil
            ),
            [
                "accessToken": "replacement-token",
                "chatgptAccountId": "org-1",
                "chatgptPlanType": NSNull()
            ]
        )
    }

    func testLoginAccountDecodeMatchesRustProtocol() throws {
        let missingStreamlinedFlag = try JSONDecoder().decode(
            LoginAccountParams.self,
            from: Data(#"{"type":"chatgpt"}"#.utf8)
        )
        XCTAssertEqual(missingStreamlinedFlag, .chatGPT(codexStreamlinedLogin: false))

        let authTokens = try JSONDecoder().decode(
            LoginAccountParams.self,
            from: Data(
                #"{"type":"chatgptAuthTokens","accessToken":"access-token","chatgptAccountId":"org-1","chatgptPlanType":null}"#.utf8
            )
        )
        XCTAssertEqual(
            authTokens,
            .chatGPTAuthTokens(accessToken: "access-token", chatGPTAccountID: "org-1", chatGPTPlanType: nil)
        )

        let deviceCode = try JSONDecoder().decode(
            LoginAccountResponse.self,
            from: Data(
                #"{"type":"chatgptDeviceCode","loginId":"login-2","verificationUrl":"https://example.test/device","userCode":"ABCD-EFGH"}"#.utf8
            )
        )
        XCTAssertEqual(
            deviceCode,
            .chatGPTDeviceCode(
                loginID: "login-2",
                verificationURL: "https://example.test/device",
                userCode: "ABCD-EFGH"
            )
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
