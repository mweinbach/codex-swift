import CodexCore
import XCTest

final class SandboxPolicyTests: XCTestCase {
    func testWorkspaceWriteDefaultsMatchRustConstructor() {
        XCTAssertEqual(
            SandboxPolicy.newWorkspaceWritePolicy(),
            .workspaceWrite(
                writableRoots: [],
                networkAccess: false,
                excludeTmpdirEnvVar: false,
                excludeSlashTmp: false
            )
        )
    }

    func testAccessHelpersMatchRustPolicyLogic() {
        XCTAssertTrue(SandboxPolicy.dangerFullAccess.hasFullDiskReadAccess)
        XCTAssertTrue(SandboxPolicy.dangerFullAccess.hasFullDiskWriteAccess)
        XCTAssertTrue(SandboxPolicy.dangerFullAccess.hasFullNetworkAccess)
        XCTAssertFalse(SandboxPolicy.readOnly.hasFullDiskWriteAccess)
        XCTAssertFalse(SandboxPolicy.readOnly.hasFullNetworkAccess)
        XCTAssertTrue(SandboxPolicy.externalSandbox(networkAccess: .enabled).hasFullNetworkAccess)
        XCTAssertFalse(SandboxPolicy.externalSandbox(networkAccess: .restricted).hasFullNetworkAccess)
    }

    func testTaggedCodableShapeMatchesSerde() throws {
        let policy = SandboxPolicy.newWorkspaceWritePolicy()
        let encoded = try String(data: JSONEncoder().encode(policy), encoding: .utf8)!
        XCTAssertEqual(encoded, #"{"type":"workspace-write"}"#)
        XCTAssertEqual(try JSONDecoder().decode(SandboxPolicy.self, from: Data(encoded.utf8)), policy)
    }
}
