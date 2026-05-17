import CodexCore
import XCTest

final class WindowsSandboxTests: XCTestCase {
    func testSetupIsIncompleteOffWindowsLikeRust() throws {
        #if os(Windows)
        throw XCTSkip("native Windows setup completion is platform-specific")
        #else
        let dir = try WindowsSandboxTemporaryDirectory()

        XCTAssertFalse(windowsSandboxSetupIsComplete(codexHome: dir.url))
        #endif
    }

    func testElevatedSetupFailsOffWindowsWithRustErrorText() throws {
        #if os(Windows)
        throw XCTSkip("native Windows setup execution is platform-specific")
        #else
        let dir = try WindowsSandboxTemporaryDirectory()
        let request = WindowsSandboxSetupRequest(
            mode: .elevated,
            codexHome: dir.url,
            commandCwd: dir.url
        )

        XCTAssertThrowsError(try runWindowsSandboxSetup(request)) { error in
            XCTAssertEqual(
                String(describing: error),
                "elevated Windows sandbox setup is only supported on Windows"
            )
        }
        #endif
    }

    func testUnelevatedSetupFailsOffWindowsWithRustErrorText() throws {
        #if os(Windows)
        throw XCTSkip("native Windows setup execution is platform-specific")
        #else
        let dir = try WindowsSandboxTemporaryDirectory()
        let request = WindowsSandboxSetupRequest(
            mode: .unelevated,
            codexHome: dir.url,
            commandCwd: dir.url
        )

        XCTAssertThrowsError(try runWindowsSandboxSetup(request)) { error in
            XCTAssertEqual(
                String(describing: error),
                "legacy Windows sandbox setup is only supported on Windows"
            )
        }
        #endif
    }

    func testSetupErrorCodesIncludeFirewallPolicyIneffectiveLikeRust() throws {
        let encoded = try JSONEncoder().encode(WindowsSandboxSetupErrorCode.helperFirewallPolicyIneffective)
        XCTAssertEqual(String(data: encoded, encoding: .utf8), #""helper_firewall_policy_ineffective""#)
        XCTAssertEqual(
            try JSONDecoder().decode(WindowsSandboxSetupErrorCode.self, from: encoded),
            .helperFirewallPolicyIneffective
        )
        XCTAssertTrue(
            WindowsSandboxSetupErrorCode.allCases.contains(.helperFirewallPolicyIneffective)
        )
    }

    func testSetupFailureDescriptionMatchesRustDisplay() {
        let failure = WindowsSandboxSetupFailure(
            code: .helperFirewallPolicyIneffective,
            message: "local firewall policy modifications will not take effect"
        )

        XCTAssertEqual(
            String(describing: failure),
            "helper_firewall_policy_ineffective: local firewall policy modifications will not take effect"
        )
    }

    func testRuntimeBinDirectoryUsesLocalAppDataBeforeUserProfileLikeRust() throws {
        let dir = try WindowsSandboxTemporaryDirectory()
        let localAppData = dir.url.appendingPathComponent("local-app-data", isDirectory: true)
        let userProfile = dir.url.appendingPathComponent("profile", isDirectory: true)
        let runtimeBin = localAppData
            .appendingPathComponent("OpenAI", isDirectory: true)
            .appendingPathComponent("Codex", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
        let fallbackBin = userProfile
            .appendingPathComponent("AppData", isDirectory: true)
            .appendingPathComponent("Local", isDirectory: true)
            .appendingPathComponent("OpenAI", isDirectory: true)
            .appendingPathComponent("Codex", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: runtimeBin, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: fallbackBin, withIntermediateDirectories: true)

        XCTAssertEqual(
            windowsSandboxCodexAppRuntimeBinDirectory(
                environment: [
                    "LOCALAPPDATA": localAppData.path,
                    "USERPROFILE": userProfile.path
                ]
            ),
            runtimeBin
        )
    }

    func testRuntimeBinDirectoryFallsBackToUserProfileLikeRust() throws {
        let dir = try WindowsSandboxTemporaryDirectory()
        let userProfile = dir.url.appendingPathComponent("profile", isDirectory: true)
        let runtimeBin = userProfile
            .appendingPathComponent("AppData", isDirectory: true)
            .appendingPathComponent("Local", isDirectory: true)
            .appendingPathComponent("OpenAI", isDirectory: true)
            .appendingPathComponent("Codex", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: runtimeBin, withIntermediateDirectories: true)

        XCTAssertEqual(
            windowsSandboxCodexAppRuntimeBinDirectory(
                environment: ["USERPROFILE": userProfile.path]
            ),
            runtimeBin
        )
    }

    func testRuntimeBinDirectoryNoOpsWhenMissingLikeRust() throws {
        let dir = try WindowsSandboxTemporaryDirectory()
        let localAppData = dir.url.appendingPathComponent("local-app-data", isDirectory: true)
        try FileManager.default.createDirectory(at: localAppData, withIntermediateDirectories: true)

        XCTAssertNil(
            windowsSandboxCodexAppRuntimeBinDirectory(
                environment: ["LOCALAPPDATA": localAppData.path]
            )
        )
        XCTAssertNil(windowsSandboxCodexAppRuntimeBinDirectory(environment: [:]))
    }

    func testPersistSetupModeWritesWindowsSandboxAndClearsLegacyFlags() throws {
        let dir = try WindowsSandboxTemporaryDirectory()
        let configFile = dir.url.appendingPathComponent("config.toml")
        try """
        model = "gpt-5"

        [features]
        experimental_windows_sandbox = true
        elevated_windows_sandbox = true
        other_feature = true
        """.write(to: configFile, atomically: true, encoding: .utf8)

        try persistWindowsSandboxSetupMode(
            codexHome: dir.url,
            activeProfile: nil,
            mode: .unelevated
        )

        let config = try CodexConfigLayerLoader.readConfig(from: configFile)
        XCTAssertEqual(config, .table([
            "model": .string("gpt-5"),
            "features": .table([
                "other_feature": .bool(true)
            ]),
            "windows": .table([
                "sandbox": .string("unelevated")
            ])
        ]))
    }

    func testPersistSetupModeWritesActiveProfileAndClearsProfileLegacyFlags() throws {
        let dir = try WindowsSandboxTemporaryDirectory()
        let configFile = dir.url.appendingPathComponent("config.toml")
        try """
        profile = "work"

        [features]
        experimental_windows_sandbox = true

        [profiles.work.features]
        enable_experimental_windows_sandbox = true
        elevated_windows_sandbox = true

        [profiles.work.windows]
        sandbox_private_desktop = false
        """.write(to: configFile, atomically: true, encoding: .utf8)

        try persistWindowsSandboxSetupMode(
            codexHome: dir.url,
            activeProfile: "work",
            mode: .elevated
        )

        let config = try CodexConfigLayerLoader.readConfig(from: configFile)
        XCTAssertEqual(config, .table([
            "profile": .string("work"),
            "features": .table([
                "experimental_windows_sandbox": .bool(true)
            ]),
            "profiles": .table([
                "work": .table([
                    "windows": .table([
                        "sandbox": .string("elevated"),
                        "sandbox_private_desktop": .bool(false)
                    ])
                ])
            ])
        ]))
    }
}

private final class WindowsSandboxTemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-windows-sandbox-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}
