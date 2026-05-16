import CodexCore
import Foundation
import XCTest

final class McpOAuthCallbackTests: XCTestCase {
    func testParseCallbackExtractsDecodedCodeAndState() {
        XCTAssertEqual(
            McpOAuthCallbackParser.parse(path: "/callback?code=auth%20code&state=csrf%2Fstate"),
            McpOAuthCallbackResult(code: "auth code", state: "csrf/state")
        )
    }

    func testParseCallbackIgnoresUnknownQueryPairs() {
        XCTAssertEqual(
            McpOAuthCallbackParser.parse(path: "/callback?ignored=yes&code=abc&state=xyz"),
            McpOAuthCallbackResult(code: "abc", state: "xyz")
        )
    }

    func testParseCallbackUsesConfiguredCallbackPath() {
        XCTAssertEqual(
            McpOAuthCallbackParser.parse(
                path: "/oauth/callback?code=abc&state=xyz",
                callbackPath: "/oauth/callback"
            ),
            McpOAuthCallbackResult(code: "abc", state: "xyz")
        )
        XCTAssertNil(
            McpOAuthCallbackParser.parse(
                path: "/callback?code=abc&state=xyz",
                callbackPath: "/oauth/callback"
            )
        )
    }

    func testParseCallbackAcceptsCallbackIDPathLikeRust() {
        XCTAssertEqual(
            McpOAuthCallbackParser.parse(
                path: "/callback/abc123?code=abc&state=xyz",
                callbackPath: "/callback/abc123"
            ),
            McpOAuthCallbackResult(code: "abc", state: "xyz")
        )
        XCTAssertNil(
            McpOAuthCallbackParser.parse(
                path: "/callback?code=abc&state=xyz",
                callbackPath: "/callback/abc123"
            )
        )
    }

    func testParseCallbackRejectsRustInvalidShapes() {
        XCTAssertNil(McpOAuthCallbackParser.parse(path: "/other?code=abc&state=xyz"))
        XCTAssertNil(McpOAuthCallbackParser.parse(path: "/callback"))
        XCTAssertNil(McpOAuthCallbackParser.parse(path: "/callback?code=abc"))
        XCTAssertNil(McpOAuthCallbackParser.parse(path: "/callback?state=xyz"))
        XCTAssertNil(McpOAuthCallbackParser.parse(path: "/callback?code=abc&state"))
        XCTAssertNil(McpOAuthCallbackParser.parse(path: "/callback?code=%ZZ&state=xyz"))
    }

    func testParseCallbackReturnsProviderErrorLikeRust() {
        XCTAssertEqual(
            McpOAuthCallbackParser.parseOutcome(
                path: "/callback?error=invalid_scope&error_description=scope%20rejected"
            ),
            .providerError(McpOAuthProviderError(
                oauthError: "invalid_scope",
                errorDescription: "scope rejected"
            ))
        )
        XCTAssertEqual(
            String(describing: McpOAuthProviderError(
                oauthError: "invalid_scope",
                errorDescription: "scope rejected"
            )),
            "OAuth provider returned `invalid_scope`: scope rejected"
        )
    }

    func testLocalCallbackServerRejectsInvalidCallbacksThenCompletesOnValidCallback() async throws {
        let server = try McpOAuthLocalCallbackServer.start()
        defer { server.stop() }

        let baseURL = server.redirectURI.replacingOccurrences(of: "/callback", with: "")
        let invalidURL = try XCTUnwrap(URL(string: "\(baseURL)/nope?code=abc&state=xyz"))
        let (invalidBody, invalidResponse) = try await URLSession.shared.data(from: invalidURL)
        XCTAssertEqual((invalidResponse as? HTTPURLResponse)?.statusCode, 400)
        XCTAssertEqual(String(data: invalidBody, encoding: .utf8), "Invalid OAuth callback")

        async let callback = server.waitForCallback(timeout: 2)
        let validURL = try XCTUnwrap(URL(string: "\(baseURL)/callback?code=auth%20code&state=csrf%2Fstate"))
        let (validBody, validResponse) = try await URLSession.shared.data(from: validURL)
        XCTAssertEqual((validResponse as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual(
            String(data: validBody, encoding: .utf8),
            "Authentication complete. You may close this window."
        )
        let callbackResult = try await callback
        XCTAssertEqual(callbackResult, McpOAuthCallbackResult(code: "auth code", state: "csrf/state"))
    }

    func testLocalCallbackServerCompletesWithProviderError() async throws {
        let server = try McpOAuthLocalCallbackServer.start()
        defer { server.stop() }

        async let callback = server.waitForCallback(timeout: 2)
        let baseURL = server.redirectURI.replacingOccurrences(of: "/callback", with: "")
        let errorURL = try XCTUnwrap(
            URL(string: "\(baseURL)/callback?error=invalid_scope&error_description=scope%20rejected")
        )
        let (body, response) = try await URLSession.shared.data(from: errorURL)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 400)
        XCTAssertEqual(
            String(data: body, encoding: .utf8),
            "OAuth provider returned `invalid_scope`: scope rejected"
        )

        do {
            _ = try await callback
            XCTFail("provider errors should complete the callback wait by throwing")
        } catch {
            XCTAssertEqual(
                error as? McpOAuthProviderError,
                McpOAuthProviderError(oauthError: "invalid_scope", errorDescription: "scope rejected")
            )
        }
    }

    func testLocalCallbackServerUsesConfiguredRedirectURLAndPath() async throws {
        let probe = try McpOAuthLocalCallbackServer.start()
        let parsedPort = try XCTUnwrap(URL(string: probe.redirectURI)?.port)
        let availablePort = try XCTUnwrap(parsedPort.asUInt16())
        probe.stop()

        let server = try McpOAuthLocalCallbackServer.start(
            port: availablePort,
            redirectURI: "http://127.0.0.1:\(availablePort)/custom/callback"
        )
        defer { server.stop() }

        XCTAssertEqual(server.redirectURI, "http://127.0.0.1:\(availablePort)/custom/callback")
        let actualPort = try XCTUnwrap(URL(string: server.redirectURI)?.port)

        async let callback = server.waitForCallback(timeout: 2)
        let validURL = try XCTUnwrap(
            URL(string: "http://127.0.0.1:\(actualPort)/custom/callback?code=auth-code&state=csrf")
        )
        let (_, response) = try await URLSession.shared.data(from: validURL)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        let callbackResult = try await callback
        XCTAssertEqual(callbackResult, McpOAuthCallbackResult(code: "auth-code", state: "csrf"))
    }

    func testLocalCallbackServerAppendsAndRequiresCallbackIDPath() async throws {
        let server = try McpOAuthLocalCallbackServer.start(callbackID: "abc123")
        defer { server.stop() }

        XCTAssertTrue(server.redirectURI.hasSuffix("/callback/abc123"))
        let baseURL = server.redirectURI.replacingOccurrences(of: "/callback/abc123", with: "")
        let oldCallbackURL = try XCTUnwrap(URL(string: "\(baseURL)/callback?code=abc&state=xyz"))
        let (_, oldCallbackResponse) = try await URLSession.shared.data(from: oldCallbackURL)
        XCTAssertEqual((oldCallbackResponse as? HTTPURLResponse)?.statusCode, 400)

        async let callback = server.waitForCallback(timeout: 2)
        let validURL = try XCTUnwrap(URL(string: "\(baseURL)/callback/abc123?code=abc&state=xyz"))
        let (_, validResponse) = try await URLSession.shared.data(from: validURL)
        XCTAssertEqual((validResponse as? HTTPURLResponse)?.statusCode, 200)
        let callbackResult = try await callback
        XCTAssertEqual(callbackResult, McpOAuthCallbackResult(code: "abc", state: "xyz"))
    }

    func testLocalCallbackServerRejectsInvalidConfiguredPortAndURL() {
        XCTAssertThrowsError(try McpOAuthLocalCallbackServer.start(port: 0)) { error in
            XCTAssertEqual(
                error as? McpOAuthCallbackServerError,
                .invalidCallbackPort(0)
            )
        }
        XCTAssertThrowsError(try McpOAuthLocalCallbackServer.start(redirectURI: "not a url")) { error in
            XCTAssertEqual(
                error as? McpOAuthCallbackServerError,
                .invalidCallbackURL("not a url")
            )
        }
    }
}

private extension Int {
    func asUInt16() -> UInt16? {
        guard self >= 0, self <= Int(UInt16.max) else {
            return nil
        }
        return UInt16(self)
    }
}
