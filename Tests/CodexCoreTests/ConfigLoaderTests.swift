import CodexCore
import XCTest

final class ConfigLoaderTests: XCTestCase {
    func testDefaultsWhenConfigTomlIsAbsent() throws {
        let dir = try CoreTemporaryDirectory()

        let config = try CodexConfigLoader.load(codexHome: dir.url)

        XCTAssertEqual(config.chatgptBaseURL, "https://chatgpt.com/backend-api/")
        XCTAssertEqual(config.cliAuthCredentialsStoreMode, .file)
        XCTAssertNil(config.activeProfile)
    }

    func testLoadsApplyRelevantTopLevelValues() throws {
        let dir = try CoreTemporaryDirectory()
        try """
        chatgpt_base_url = "https://example.test/backend-api/"
        cli_auth_credentials_store = "auto"
        """.write(to: dir.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        let config = try CodexConfigLoader.load(codexHome: dir.url)

        XCTAssertEqual(config.chatgptBaseURL, "https://example.test/backend-api/")
        XCTAssertEqual(config.cliAuthCredentialsStoreMode, .auto)
    }

    func testProfileChatGPTBaseURLOverridesTopLevelValue() throws {
        let dir = try CoreTemporaryDirectory()
        try """
        profile = "work"
        chatgpt_base_url = "https://top-level.example/backend-api/"

        [profiles.work]
        chatgpt_base_url = "https://profile.example/backend-api/"
        """.write(to: dir.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        let config = try CodexConfigLoader.load(codexHome: dir.url)

        XCTAssertEqual(config.activeProfile, "work")
        XCTAssertEqual(config.chatgptBaseURL, "https://profile.example/backend-api/")
    }

    func testCLIOverridesCanSelectAndPatchProfile() throws {
        let dir = try CoreTemporaryDirectory()
        try """
        profile = "default"
        chatgpt_base_url = "https://top-level.example/backend-api/"

        [profiles.default]
        chatgpt_base_url = "https://default.example/backend-api/"

        [profiles.work]
        chatgpt_base_url = "https://work.example/backend-api/"
        """.write(to: dir.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        let config = try CodexConfigLoader.load(
            codexHome: dir.url,
            overrides: CliConfigOverrides(rawOverrides: [
                "profile=\"work\"",
                "profiles.work.chatgpt_base_url=\"https://override.example/backend-api/\"",
                "cli_auth_credentials_store=\"keyring\""
            ])
        )

        XCTAssertEqual(config.activeProfile, "work")
        XCTAssertEqual(config.chatgptBaseURL, "https://override.example/backend-api/")
        XCTAssertEqual(config.cliAuthCredentialsStoreMode, .keyring)
    }

    func testMissingProfileMatchesRustError() throws {
        let dir = try CoreTemporaryDirectory()
        try #"profile = "missing""#.write(to: dir.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try CodexConfigLoader.load(codexHome: dir.url)) { error in
            XCTAssertEqual((error as? CodexConfigLoadError)?.description, "config profile `missing` not found")
        }
    }

    func testProfileWithoutApplyRelevantKeysFallsBackToTopLevel() throws {
        let dir = try CoreTemporaryDirectory()
        try """
        profile = "work"
        chatgpt_base_url = "https://top-level.example/backend-api/"

        [profiles.work]
        model = "o3"
        """.write(to: dir.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        let config = try CodexConfigLoader.load(codexHome: dir.url)

        XCTAssertEqual(config.activeProfile, "work")
        XCTAssertEqual(config.chatgptBaseURL, "https://top-level.example/backend-api/")
    }

    func testIgnoresUnknownSectionsAndKeys() throws {
        let dir = try CoreTemporaryDirectory()
        try """
        chatgpt_base_url = "https://example.test/backend-api/" # keep this comment out of the value

        [model_providers.openai-chat-completions]
        base_url = "https://api.openai.com/v1"
        env_key = "OPENAI_API_KEY"
        wire_api = "chat"

        [profiles."quoted.profile"]
        chatgpt_base_url = "https://quoted.example/backend-api/#fragment"
        """.write(to: dir.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        let config = try CodexConfigLoader.load(
            codexHome: dir.url,
            overrides: CliConfigOverrides(rawOverrides: ["profile=\"quoted.profile\""])
        )

        XCTAssertEqual(config.activeProfile, "quoted.profile")
        XCTAssertEqual(config.chatgptBaseURL, "https://quoted.example/backend-api/#fragment")
    }
}

private final class CoreTemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}
