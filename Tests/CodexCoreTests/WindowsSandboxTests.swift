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
