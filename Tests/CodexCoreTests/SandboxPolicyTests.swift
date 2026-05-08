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
        try XCTAssertJSONObjectEqual(policy, [
            "type": "workspace-write",
            "network_access": false,
            "exclude_tmpdir_env_var": false,
            "exclude_slash_tmp": false
        ])

        try XCTAssertJSONObjectEqual(SandboxPolicy.externalSandbox(networkAccess: .restricted), [
            "type": "external-sandbox",
            "network_access": "restricted"
        ])

        let encoded = try JSONEncoder().encode(policy)
        XCTAssertEqual(try JSONDecoder().decode(SandboxPolicy.self, from: encoded), policy)
    }
}
