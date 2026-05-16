import CodexCLI
import XCTest

final class DoctorCommandRuntimeTests: XCTestCase {
    func testNpmGlobalRootProbeUsesWindowsShimLikeRustDoctor() {
        XCTAssertEqual(DoctorCommandRuntime.npmGlobalRootCommand(isWindows: true), "npm.cmd")
        XCTAssertEqual(DoctorCommandRuntime.npmGlobalRootArguments, ["root", "-g"])
    }

    func testNpmGlobalRootProbeUsesNpmOffWindowsLikeRustDoctor() {
        XCTAssertEqual(DoctorCommandRuntime.npmGlobalRootCommand(isWindows: false), "npm")
        XCTAssertEqual(DoctorCommandRuntime.npmGlobalRootArguments, ["root", "-g"])
    }
}
