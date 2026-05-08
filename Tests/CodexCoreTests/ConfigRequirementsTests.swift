import CodexCore
import XCTest

final class ConfigRequirementsTests: XCTestCase {
    func testMergeUnsetFieldsOnlyFillsMissingValues() throws {
        let source = try ConfigRequirementsToml.parse("""
        allowed_approval_policies = ["on-request"]
        """)

        var emptyTarget = try ConfigRequirementsToml.parse("""
        # intentionally left unset
        """)
        emptyTarget.mergeUnsetFields(from: source)
        XCTAssertEqual(emptyTarget.allowedApprovalPolicies, [.onRequest])

        var populatedTarget = try ConfigRequirementsToml.parse("""
        allowed_approval_policies = ["never"]
        """)
        populatedTarget.mergeUnsetFields(from: source)
        XCTAssertEqual(populatedTarget.allowedApprovalPolicies, [.never])
    }

    func testDeserializeAllowedApprovalPolicies() throws {
        let config = try ConfigRequirementsToml.parse("""
        allowed_approval_policies = ["untrusted", "on-request"]
        """)
        let requirements = try config.requirements()

        XCTAssertEqual(requirements.approvalPolicy.value, .unlessTrusted)
        XCTAssertNoThrow(try requirements.approvalPolicy.canSet(.unlessTrusted).get())
        XCTAssertConstraintFailure(
            requirements.approvalPolicy.canSet(.onFailure),
            .invalidValue(candidate: "OnFailure", allowed: "[UnlessTrusted, OnRequest]")
        )
        XCTAssertNoThrow(try requirements.approvalPolicy.canSet(.onRequest).get())
        XCTAssertConstraintFailure(
            requirements.approvalPolicy.canSet(.never),
            .invalidValue(candidate: "Never", allowed: "[UnlessTrusted, OnRequest]")
        )
        XCTAssertNoThrow(try requirements.sandboxPolicy.canSet(.readOnly).get())
    }

    func testDeserializeAllowedSandboxModes() throws {
        let config = try ConfigRequirementsToml.parse("""
        allowed_sandbox_modes = ["read-only", "workspace-write"]
        """)
        let requirements = try config.requirements()

        XCTAssertNoThrow(try requirements.sandboxPolicy.canSet(.readOnly).get())
        XCTAssertNoThrow(try requirements.sandboxPolicy.canSet(.workspaceWrite(
            writableRoots: [try AbsolutePath(absolutePath: "/repo")],
            networkAccess: false,
            excludeTmpdirEnvVar: false,
            excludeSlashTmp: false
        )).get())
        XCTAssertConstraintFailure(
            requirements.sandboxPolicy.canSet(.dangerFullAccess),
            .invalidValue(candidate: "DangerFullAccess", allowed: "[ReadOnly, WorkspaceWrite]")
        )
        XCTAssertConstraintFailure(
            requirements.sandboxPolicy.canSet(.externalSandbox(networkAccess: .restricted)),
            .invalidValue(candidate: "ExternalSandbox { network_access: Restricted }", allowed: "[ReadOnly, WorkspaceWrite]")
        )
    }

    func testEmptyAllowedApprovalPoliciesMatchesRustConstraintError() {
        let config = ConfigRequirementsToml(allowedApprovalPolicies: [])
        XCTAssertThrowsError(try config.requirements()) { error in
            XCTAssertEqual(error as? ConstraintError, .emptyField(fieldName: "allowed_approval_policies"))
        }
    }

    func testAllowedSandboxModesMustIncludeReadOnly() {
        let config = ConfigRequirementsToml(allowedSandboxModes: [.workspaceWrite])
        XCTAssertThrowsError(try config.requirements()) { error in
            XCTAssertEqual(
                error as? ConstraintError,
                .invalidValue(
                    candidate: "allowed_sandbox_modes",
                    allowed: "must include 'read-only' to allow any SandboxPolicy"
                )
            )
        }
    }

    func testSandboxModeRequirementConversions() {
        XCTAssertEqual(SandboxModeRequirement(sandboxMode: .readOnly), .readOnly)
        XCTAssertEqual(SandboxModeRequirement(sandboxMode: .workspaceWrite), .workspaceWrite)
        XCTAssertEqual(SandboxModeRequirement(sandboxMode: .dangerFullAccess), .dangerFullAccess)
        XCTAssertEqual(SandboxModeRequirement(sandboxPolicy: .externalSandbox(networkAccess: .enabled)), .externalSandbox)
    }

    func testAppServerRequirementsObjectMatchesPortedRustFields() throws {
        let config = try ConfigRequirementsToml.parse("""
        allowed_approval_policies = ["never"]
        allowed_sandbox_modes = ["read-only", "danger-full-access", "external-sandbox"]
        """)

        XCTAssertFalse(config.isEmpty)
        let object = config.appServerRequirementsObject()
        XCTAssertEqual(object["allowedApprovalPolicies"] as? [String], ["never"])
        XCTAssertEqual(object["allowedSandboxModes"] as? [String], ["read-only", "danger-full-access"])
        XCTAssertTrue(object["allowedApprovalsReviewers"] is NSNull)
        XCTAssertTrue(ConfigRequirementsToml().isEmpty)
    }
}

private func XCTAssertConstraintFailure(
    _ result: ConstraintResult<Void>,
    _ expected: ConstraintError,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    switch result {
    case .success:
        XCTFail("expected constraint failure", file: file, line: line)
    case let .failure(error):
        XCTAssertEqual(error, expected, file: file, line: line)
    }
}
