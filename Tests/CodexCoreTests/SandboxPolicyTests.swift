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

    func testSandboxPolicyOmittedDefaultFieldsMatchRustSerdeDefaults() throws {
        let decoder = JSONDecoder()

        let readOnly = try decoder.decode(
            SandboxPolicy.self,
            from: Data(#"{"type":"read-only"}"#.utf8)
        )
        XCTAssertEqual(readOnly, .readOnly)

        let external = try decoder.decode(
            SandboxPolicy.self,
            from: Data(#"{"type":"external-sandbox"}"#.utf8)
        )
        XCTAssertEqual(external, .externalSandbox(networkAccess: .restricted))

        let workspaceWrite = try decoder.decode(
            SandboxPolicy.self,
            from: Data(#"{"type":"workspace-write"}"#.utf8)
        )
        XCTAssertEqual(workspaceWrite, SandboxPolicy.newWorkspaceWritePolicy())
    }

    func testSandboxPolicyRejectsExplicitNullForRustDefaultedFields() {
        let nullFields = [
            #"{"type":"read-only","network_access":null}"#,
            #"{"type":"external-sandbox","network_access":null}"#,
            #"{"type":"workspace-write","writable_roots":null}"#,
            #"{"type":"workspace-write","network_access":null}"#,
            #"{"type":"workspace-write","exclude_tmpdir_env_var":null}"#,
            #"{"type":"workspace-write","exclude_slash_tmp":null}"#
        ]

        for payload in nullFields {
            XCTAssertThrowsError(
                try JSONDecoder().decode(SandboxPolicy.self, from: Data(payload.utf8)),
                "Expected Rust #[serde(default)] sandbox field to reject explicit null: \(payload)"
            )
        }
    }
}
