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
        XCTAssertFalse(SandboxPolicy.newReadOnlyPolicy().hasFullDiskWriteAccess)
        XCTAssertFalse(SandboxPolicy.newReadOnlyPolicy().hasFullNetworkAccess)
        XCTAssertTrue(SandboxPolicy.readOnlyWithNetworkAccess.hasFullNetworkAccess)
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

        try XCTAssertJSONObjectEqual(SandboxPolicy.newReadOnlyPolicy(), [
            "type": "read-only"
        ])
        try XCTAssertJSONObjectEqual(SandboxPolicy.readOnlyWithNetworkAccess, [
            "type": "read-only",
            "network_access": true
        ])

        let encoded = try JSONEncoder().encode(policy)
        XCTAssertEqual(try JSONDecoder().decode(SandboxPolicy.self, from: encoded), policy)
    }
}
