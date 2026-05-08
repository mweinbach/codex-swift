import CodexCore
import XCTest

final class WSLPathTests: XCTestCase {
    func testWinPathToWSLBasic() {
        XCTAssertEqual(WSLPath.winPathToWSL(#"C:\Temp\codex.zip"#), "/mnt/c/Temp/codex.zip")
        XCTAssertEqual(WSLPath.winPathToWSL("D:/Work/codex.tgz"), "/mnt/d/Work/codex.tgz")
        XCTAssertNil(WSLPath.winPathToWSL("/home/user/codex"))
    }

    func testWinPathToWSLDriveRoot() {
        XCTAssertEqual(WSLPath.winPathToWSL(#"E:\"#), "/mnt/e")
        XCTAssertEqual(WSLPath.winPathToWSL("F:/"), "/mnt/f")
    }

    func testNormalizeForWSLIsNoopWhenNotWSL() {
        XCTAssertEqual(WSLPath.normalizeForWSL(#"C:\Temp\codex.zip"#, isWSL: false), #"C:\Temp\codex.zip"#)
        XCTAssertEqual(WSLPath.normalizeForWSL("/home/u/x", isWSL: false), "/home/u/x")
    }

    func testNormalizeForWSLMapsWindowsPathWhenWSL() {
        XCTAssertEqual(WSLPath.normalizeForWSL(#"C:\Temp\codex.zip"#, isWSL: true), "/mnt/c/Temp/codex.zip")
        XCTAssertEqual(WSLPath.normalizeForWSL("/home/u/x", isWSL: true), "/home/u/x")
    }

    func testIsWSLRequiresLinux() {
        XCTAssertFalse(WSLPath.isWSL(
            environment: ["WSL_DISTRO_NAME": "Ubuntu"],
            procVersion: "Microsoft",
            isLinux: false
        ))
    }

    func testIsWSLDetectsDistroNameOrProcVersionOnLinux() {
        XCTAssertTrue(WSLPath.isWSL(
            environment: ["WSL_DISTRO_NAME": "Ubuntu"],
            procVersion: nil,
            isLinux: true
        ))
        XCTAssertTrue(WSLPath.isWSL(
            environment: [:],
            procVersion: "Linux version 5.15.90.1-microsoft-standard-WSL2",
            isLinux: true
        ))
        XCTAssertFalse(WSLPath.isWSL(
            environment: [:],
            procVersion: "Linux version 6.8.0-generic",
            isLinux: true
        ))
    }
}
