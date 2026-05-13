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
