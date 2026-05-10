import CodexCore
import XCTest

final class APIAuthTests: XCTestCase {
    func testAddAuthHeadersAddsBearerAndAccountHeaders() {
        let request = APIRequest(
            method: .get,
            url: "https://example.com/models",
            headers: ["x-existing": "1"]
        )

        let authed = request.addingAuthHeaders(from: StaticAPIAuthProvider(
            bearerToken: "token",
            accountID: "account-id"
        ))

        XCTAssertEqual(authed.method, .get)
        XCTAssertEqual(authed.url, request.url)
        XCTAssertEqual(authed.headers, [
            "x-existing": "1",
            "authorization": "Bearer token",
            "ChatGPT-Account-ID": "account-id"
        ])
        XCTAssertNil(authed.body)
        XCTAssertNil(authed.timeoutMilliseconds)
    }

    func testAddAuthHeadersSkipsMissingValues() {
        let request = APIRequest(method: .get, url: "https://example.com/models")

        XCTAssertEqual(
            request.addingAuthHeaders(from: StaticAPIAuthProvider()).headers,
            [:]
        )
    }

    func testAddAuthHeadersSkipsInvalidHeaderValuesLikeRustParseFailures() {
        let request = APIRequest(
            method: .get,
            url: "https://example.com/models",
            headers: ["authorization": "original", "ChatGPT-Account-ID": "original-account"]
        )

        let authed = request.addingAuthHeaders(from: StaticAPIAuthProvider(
            bearerToken: "bad\nvalue",
            accountID: "bad\rvalue"
        ))

        XCTAssertEqual(authed.headers, [
            "authorization": "original",
            "ChatGPT-Account-ID": "original-account"
        ])
    }

    func testAuthResolverUsesProviderEnvironmentAPIKeyFirst() throws {
        let provider = ModelProviderInfo(
            name: "Provider",
            envKey: "PROVIDER_KEY",
            experimentalBearerToken: "experimental"
        )
        let auth = AuthDotJSON(
            openAIAPIKey: "auth-json-key",
            tokens: tokenData(accessToken: "chatgpt-token", accountID: "acct"),
            lastRefresh: nil
        )

        XCTAssertEqual(
            try APIAuthResolver.authProvider(
                auth: auth,
                provider: provider,
                environment: ["PROVIDER_KEY": "provider-key"]
            ),
            StaticAPIAuthProvider(bearerToken: "provider-key")
        )
    }

    func testAuthResolverUsesExperimentalBearerBeforeAuthJSON() throws {
        let provider = ModelProviderInfo(
            name: "Provider",
            experimentalBearerToken: "experimental"
        )
        let auth = AuthDotJSON(
            openAIAPIKey: "auth-json-key",
            tokens: tokenData(accessToken: "chatgpt-token", accountID: "acct"),
            lastRefresh: nil
        )

        XCTAssertEqual(
            try APIAuthResolver.authProvider(auth: auth, provider: provider, environment: [:]),
            StaticAPIAuthProvider(bearerToken: "experimental")
        )
    }

    func testAuthResolverUsesAuthJSONAPIKeyBeforeChatGPTTokens() throws {
        let auth = AuthDotJSON(
            openAIAPIKey: "auth-json-key",
            tokens: tokenData(accessToken: "chatgpt-token", accountID: "acct"),
            lastRefresh: nil
        )

        XCTAssertEqual(
            try APIAuthResolver.authProvider(
                auth: auth,
                provider: ModelProviderInfo(name: "OpenAI"),
                environment: [:]
            ),
            StaticAPIAuthProvider(bearerToken: "auth-json-key")
        )
    }

    func testAuthResolverUsesChatGPTAccessTokenAndAccountID() throws {
        let auth = AuthDotJSON(
            openAIAPIKey: nil,
            tokens: tokenData(accessToken: "chatgpt-token", accountID: "acct"),
            lastRefresh: nil
        )

        XCTAssertEqual(
            try APIAuthResolver.authProvider(
                auth: auth,
                provider: ModelProviderInfo(name: "OpenAI"),
                environment: [:]
            ),
            StaticAPIAuthProvider(bearerToken: "chatgpt-token", accountID: "acct")
        )
    }

    func testAuthResolverReturnsEmptyProviderWhenNoAuthMaterialExists() throws {
        XCTAssertEqual(
            try APIAuthResolver.authProvider(
                auth: nil,
                provider: ModelProviderInfo(name: "OpenAI"),
                environment: [:]
            ),
            StaticAPIAuthProvider()
        )
    }

    func testAuthResolverPropagatesMissingProviderEnvironmentKey() {
        let provider = ModelProviderInfo(
            name: "Provider",
            envKey: "PROVIDER_KEY",
            envKeyInstructions: "Export PROVIDER_KEY."
        )

        XCTAssertThrowsError(
            try APIAuthResolver.authProvider(auth: nil, provider: provider, environment: [:])
        ) { error in
            XCTAssertEqual(
                error as? ModelProviderError,
                .missingEnvironmentVariable(name: "PROVIDER_KEY", instructions: "Export PROVIDER_KEY.")
            )
        }
    }

    func testAuthResolverUsesProviderCommandAuthLikeRust() async throws {
        let script = try ProviderAuthScript(tokens: ["provider-token", "next-token"])
        let provider = try ModelProviderInfo(
            name: "Provider",
            auth: script.authConfig()
        )
        let auth = AuthDotJSON(
            openAIAPIKey: "auth-json-key",
            tokens: tokenData(accessToken: "chatgpt-token", accountID: "acct"),
            lastRefresh: nil
        )

        let resolved = try await APIAuthResolver.authProvider(
            auth: auth,
            provider: provider,
            commandRunner: ProviderAuthCommandRunner()
        )

        XCTAssertEqual(resolved, StaticAPIAuthProvider(bearerToken: "provider-token"))
    }

    func testAuthResolverUsesCachedProviderCommandTokenLikeRust() async throws {
        let script = try ProviderAuthScript(tokens: ["provider-token", "next-token"])
        let provider = try ModelProviderInfo(name: "Provider", auth: script.authConfig())
        let runner = ProviderAuthCommandRunner()

        let first = try await APIAuthResolver.authProvider(
            auth: nil,
            provider: provider,
            commandRunner: runner
        )
        let second = try await APIAuthResolver.authProvider(
            auth: nil,
            provider: provider,
            commandRunner: runner
        )

        XCTAssertEqual(first, StaticAPIAuthProvider(bearerToken: "provider-token"))
        XCTAssertEqual(second, StaticAPIAuthProvider(bearerToken: "provider-token"))
    }

    func testProviderCommandAuthZeroRefreshIntervalKeepsCachedTokenLikeRust() async throws {
        let script = try ProviderAuthScript(tokens: ["provider-token", "next-token"])
        let provider = try ModelProviderInfo(
            name: "Provider",
            auth: script.authConfig(refreshIntervalMilliseconds: 0)
        )
        let runner = ProviderAuthCommandRunner()

        let first = try await APIAuthResolver.authProvider(
            auth: nil,
            provider: provider,
            commandRunner: runner
        )
        let second = try await APIAuthResolver.authProvider(
            auth: nil,
            provider: provider,
            commandRunner: runner
        )

        XCTAssertEqual(first, StaticAPIAuthProvider(bearerToken: "provider-token"))
        XCTAssertEqual(second, StaticAPIAuthProvider(bearerToken: "provider-token"))
    }

    func testProviderCommandAuthFailuresReturnUnauthenticatedLikeRust() async throws {
        let script = try ProviderAuthScript.failing()
        let provider = try ModelProviderInfo(name: "Provider", auth: script.authConfig())
        let auth = AuthDotJSON(
            openAIAPIKey: "auth-json-key",
            tokens: tokenData(accessToken: "chatgpt-token", accountID: "acct"),
            lastRefresh: nil
        )

        let resolved = try await APIAuthResolver.authProvider(
            auth: auth,
            provider: provider,
            commandRunner: ProviderAuthCommandRunner()
        )

        XCTAssertEqual(resolved, StaticAPIAuthProvider())
    }

    func testProviderAuthCommandRunnerErrorsMatchRust() async throws {
        let emptyScript = try ProviderAuthScript(tokens: ["  "])
        await XCTAssertThrowsErrorAsync(
            try await ProviderAuthCommandRunner.runProviderAuthCommand(emptyScript.authConfig())
        ) { error in
            XCTAssertEqual(
                String(describing: error),
                "provider auth command `./print-token.sh` produced an empty token"
            )
        }

        let failingScript = try ProviderAuthScript.failing(stderr: "no token")
        await XCTAssertThrowsErrorAsync(
            try await ProviderAuthCommandRunner.runProviderAuthCommand(failingScript.authConfig())
        ) { error in
            XCTAssertEqual(
                String(describing: error),
                "provider auth command `./fail.sh` exited with status exit status: 1: no token"
            )
        }
    }
}

private func tokenData(accessToken: String, accountID: String?) -> AuthTokenData {
    AuthTokenData(
        idToken: IdTokenInfo(rawJWT: "header.payload.signature"),
        accessToken: accessToken,
        refreshToken: "refresh-token",
        accountID: accountID
    )
}

private struct ProviderAuthScript {
    let directory: URL
    let command: String

    init(tokens: [String]) throws {
        self.directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-provider-auth-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.command = "./print-token.sh"
        let tokenText = tokens.joined(separator: "\n") + "\n"
        try tokenText.write(
            to: directory.appendingPathComponent("tokens.txt"),
            atomically: true,
            encoding: .utf8
        )
        try Self.writeExecutable(
            """
            #!/bin/sh
            first_line=$(sed -n '1p' tokens.txt)
            printf '%s\\n' "$first_line"
            tail -n +2 tokens.txt > tokens.next
            mv tokens.next tokens.txt
            """,
            to: directory.appendingPathComponent("print-token.sh")
        )
    }

    static func failing(stderr: String = "") throws -> ProviderAuthScript {
        let script = try ProviderAuthScript(tokens: ["unused"])
        let stderrLine = stderr.isEmpty ? "" : "printf '%s\\n' '\(stderr)' >&2"
        try writeExecutable(
            """
            #!/bin/sh
            \(stderrLine)
            exit 1
            """,
            to: script.directory.appendingPathComponent("fail.sh")
        )
        return ProviderAuthScript(directory: script.directory, command: "./fail.sh")
    }

    private init(directory: URL, command: String) {
        self.directory = directory
        self.command = command
    }

    func authConfig(refreshIntervalMilliseconds: UInt64 = 60_000) throws -> ModelProviderAuthInfo {
        try ModelProviderAuthInfo(
            command: command,
            timeoutMilliseconds: 10_000,
            refreshIntervalMilliseconds: refreshIntervalMilliseconds,
            cwd: AbsolutePath(absolutePath: directory.path)
        )
    }

    private static func writeExecutable(_ contents: String, to url: URL) throws {
        try contents.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }
}

private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ verify: (Error) -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected error to be thrown", file: file, line: line)
    } catch {
        verify(error)
    }
}
