import CodexCore
import XCTest

final class ConfigLoaderTests: XCTestCase {
    func testDefaultsWhenConfigTomlIsAbsent() throws {
        let dir = try CoreTemporaryDirectory()

        let config = try CodexConfigLoader.load(codexHome: dir.url, systemConfigFile: nil)

        XCTAssertEqual(config.chatgptBaseURL, "https://chatgpt.com/backend-api/")
        XCTAssertEqual(config.cliAuthCredentialsStoreMode, .file)
        XCTAssertNil(config.forcedLoginMethod)
        XCTAssertTrue(config.features.isEnabled(.parallel))
        XCTAssertFalse(config.features.isEnabled(.webSearchRequest))
        XCTAssertNil(config.activeProfile)
        XCTAssertEqual(config.projectRootMarkers, [".git"])
        XCTAssertEqual(config.projectDocMaxBytes, 32 * 1024)
        XCTAssertEqual(config.projectDocFallbackFilenames, [])
    }

    func testLoadsApplyRelevantTopLevelValues() throws {
        let dir = try CoreTemporaryDirectory()
        try """
        chatgpt_base_url = "https://example.test/backend-api/"
        cli_auth_credentials_store = "auto"
        forced_login_method = "api"
        """.write(to: dir.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        let config = try CodexConfigLoader.load(codexHome: dir.url, systemConfigFile: nil)

        XCTAssertEqual(config.chatgptBaseURL, "https://example.test/backend-api/")
        XCTAssertEqual(config.cliAuthCredentialsStoreMode, .auto)
        XCTAssertEqual(config.forcedLoginMethod, .api)
    }

    func testProfileChatGPTBaseURLOverridesTopLevelValue() throws {
        let dir = try CoreTemporaryDirectory()
        try """
        profile = "work"
        chatgpt_base_url = "https://top-level.example/backend-api/"

        [profiles.work]
        chatgpt_base_url = "https://profile.example/backend-api/"
        """.write(to: dir.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        let config = try CodexConfigLoader.load(codexHome: dir.url, systemConfigFile: nil)

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
                "cli_auth_credentials_store=\"keyring\"",
                "forced_login_method=\"chatgpt\""
            ]),
            systemConfigFile: nil
        )

        XCTAssertEqual(config.activeProfile, "work")
        XCTAssertEqual(config.chatgptBaseURL, "https://override.example/backend-api/")
        XCTAssertEqual(config.cliAuthCredentialsStoreMode, .keyring)
        XCTAssertEqual(config.forcedLoginMethod, .chatgpt)
    }

    func testInvalidForcedLoginMethodMatchesRustConfigErrorShape() throws {
        let dir = try CoreTemporaryDirectory()
        try #"forced_login_method = "browser""#
            .write(to: dir.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try CodexConfigLoader.load(codexHome: dir.url, systemConfigFile: nil)) { error in
            XCTAssertEqual((error as? CodexConfigLoadError)?.description, "Invalid override value for forced_login_method")
        }
    }

    func testLoadsFeatureTablesAndCLIOverrides() throws {
        let dir = try CoreTemporaryDirectory()
        try """
        profile = "work"

        [features]
        web_search_request = true
        parallel = false

        [profiles.work.features]
        parallel = true
        skills = false
        """.write(to: dir.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        let config = try CodexConfigLoader.load(
            codexHome: dir.url,
            overrides: CliConfigOverrides(rawOverrides: ["features.web_search_request=false"]),
            systemConfigFile: nil
        )

        XCTAssertEqual(config.activeProfile, "work")
        XCTAssertFalse(config.features.isEnabled(.webSearchRequest))
        XCTAssertTrue(config.features.isEnabled(.parallel))
        XCTAssertFalse(config.features.isEnabled(.skills))
    }

    func testMissingProfileMatchesRustError() throws {
        let dir = try CoreTemporaryDirectory()
        try #"profile = "missing""#.write(to: dir.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try CodexConfigLoader.load(codexHome: dir.url, systemConfigFile: nil)) { error in
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

        let config = try CodexConfigLoader.load(codexHome: dir.url, systemConfigFile: nil)

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
            overrides: CliConfigOverrides(rawOverrides: ["profile=\"quoted.profile\""]),
            systemConfigFile: nil
        )

        XCTAssertEqual(config.activeProfile, "quoted.profile")
        XCTAssertEqual(config.chatgptBaseURL, "https://quoted.example/backend-api/#fragment")
    }

    func testLayeredConfigUsesSystemUserAndProjectDotCodexOrder() throws {
        let dir = try CoreTemporaryDirectory()
        let home = dir.url.appendingPathComponent("home", isDirectory: true)
        let project = dir.url.appendingPathComponent("project", isDirectory: true)
        let child = project.appendingPathComponent("child", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        try "gitdir: here\n".write(to: project.appendingPathComponent(".git"), atomically: true, encoding: .utf8)

        let systemConfig = dir.url.appendingPathComponent("system.toml")
        try """
        chatgpt_base_url = "https://system.example/backend-api/"
        cli_auth_credentials_store = "keyring"
        """.write(to: systemConfig, atomically: true, encoding: .utf8)
        try """
        chatgpt_base_url = "https://user.example/backend-api/"
        cli_auth_credentials_store = "auto"
        """.write(to: home.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        let rootDotCodex = project.appendingPathComponent(".codex", isDirectory: true)
        let childDotCodex = child.appendingPathComponent(".codex", isDirectory: true)
        try FileManager.default.createDirectory(at: rootDotCodex, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: childDotCodex, withIntermediateDirectories: true)
        try #"chatgpt_base_url = "https://project.example/backend-api/""#
            .write(to: rootDotCodex.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)
        try #"chatgpt_base_url = "https://child.example/backend-api/""#
            .write(to: childDotCodex.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        let config = try CodexConfigLoader.load(
            codexHome: home,
            cwd: child,
            systemConfigFile: systemConfig
        )

        XCTAssertEqual(config.chatgptBaseURL, "https://child.example/backend-api/")
        XCTAssertEqual(config.cliAuthCredentialsStoreMode, .auto)
    }

    func testCLIOverridesBeatLayeredProjectConfigWhenNoProfileOverridesIt() throws {
        let dir = try CoreTemporaryDirectory()
        let home = dir.url.appendingPathComponent("home", isDirectory: true)
        let project = dir.url.appendingPathComponent("project", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try "gitdir: here\n".write(to: project.appendingPathComponent(".git"), atomically: true, encoding: .utf8)
        let dotCodex = project.appendingPathComponent(".codex", isDirectory: true)
        try FileManager.default.createDirectory(at: dotCodex, withIntermediateDirectories: true)
        try #"chatgpt_base_url = "https://project.example/backend-api/""#
            .write(to: dotCodex.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        let config = try CodexConfigLoader.load(
            codexHome: home,
            cwd: project,
            overrides: CliConfigOverrides(rawOverrides: ["chatgpt_base_url=\"https://cli.example/backend-api/\""]),
            systemConfigFile: nil
        )

        XCTAssertEqual(config.chatgptBaseURL, "https://cli.example/backend-api/")
    }

    func testProjectLayerStopsAtDetectedGitRoot() throws {
        let dir = try CoreTemporaryDirectory()
        let home = dir.url.appendingPathComponent("home", isDirectory: true)
        let outer = dir.url.appendingPathComponent("outer", isDirectory: true)
        let project = outer.appendingPathComponent("project", isDirectory: true)
        let child = project.appendingPathComponent("child", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        try "gitdir: here\n".write(to: project.appendingPathComponent(".git"), atomically: true, encoding: .utf8)

        let outerDotCodex = outer.appendingPathComponent(".codex", isDirectory: true)
        let projectDotCodex = project.appendingPathComponent(".codex", isDirectory: true)
        try FileManager.default.createDirectory(at: outerDotCodex, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: projectDotCodex, withIntermediateDirectories: true)
        try #"chatgpt_base_url = "https://outer.example/backend-api/""#
            .write(to: outerDotCodex.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)
        try #"chatgpt_base_url = "https://project.example/backend-api/""#
            .write(to: projectDotCodex.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        let config = try CodexConfigLoader.load(
            codexHome: home,
            cwd: child,
            systemConfigFile: nil
        )

        XCTAssertEqual(config.chatgptBaseURL, "https://project.example/backend-api/")
    }

    func testProjectRootMarkersSupportAlternateMarkersFromUserConfig() throws {
        let dir = try CoreTemporaryDirectory()
        let home = dir.url.appendingPathComponent("home", isDirectory: true)
        let outer = dir.url.appendingPathComponent("outer", isDirectory: true)
        let project = outer.appendingPathComponent("project", isDirectory: true)
        let child = project.appendingPathComponent("child", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        try "hg marker\n".write(to: project.appendingPathComponent(".hg"), atomically: true, encoding: .utf8)
        try #"project_root_markers = [".hg"]"#
            .write(to: home.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        let outerDotCodex = outer.appendingPathComponent(".codex", isDirectory: true)
        let projectDotCodex = project.appendingPathComponent(".codex", isDirectory: true)
        try FileManager.default.createDirectory(at: outerDotCodex, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: projectDotCodex, withIntermediateDirectories: true)
        try #"chatgpt_base_url = "https://outer.example/backend-api/""#
            .write(to: outerDotCodex.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)
        try #"chatgpt_base_url = "https://project.example/backend-api/""#
            .write(to: projectDotCodex.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        let config = try CodexConfigLoader.load(
            codexHome: home,
            cwd: child,
            systemConfigFile: nil
        )

        XCTAssertEqual(config.chatgptBaseURL, "https://project.example/backend-api/")
        XCTAssertEqual(config.projectRootMarkers, [".hg"])
    }

    func testEmptyProjectRootMarkersDisableAncestorProjectSearch() throws {
        let dir = try CoreTemporaryDirectory()
        let home = dir.url.appendingPathComponent("home", isDirectory: true)
        let project = dir.url.appendingPathComponent("project", isDirectory: true)
        let child = project.appendingPathComponent("child", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        try "gitdir: here\n".write(to: project.appendingPathComponent(".git"), atomically: true, encoding: .utf8)
        try """
        chatgpt_base_url = "https://user.example/backend-api/"
        project_root_markers = []
        """.write(to: home.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        let projectDotCodex = project.appendingPathComponent(".codex", isDirectory: true)
        try FileManager.default.createDirectory(at: projectDotCodex, withIntermediateDirectories: true)
        try #"chatgpt_base_url = "https://project.example/backend-api/""#
            .write(to: projectDotCodex.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        let config = try CodexConfigLoader.load(
            codexHome: home,
            cwd: child,
            systemConfigFile: nil
        )

        XCTAssertEqual(config.chatgptBaseURL, "https://user.example/backend-api/")
        XCTAssertEqual(config.projectRootMarkers, [])
    }

    func testInvalidProjectRootMarkersMatchesRustError() throws {
        let dir = try CoreTemporaryDirectory()
        try "project_root_markers = [1]\n"
            .write(to: dir.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try CodexConfigLoader.load(codexHome: dir.url, systemConfigFile: nil)) { error in
            XCTAssertEqual(
                (error as? CodexConfigLoadError)?.description,
                "project_root_markers must be an array of strings"
            )
        }
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
