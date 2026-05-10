import CodexCore
import XCTest

final class PermissionsInstructionsTests: XCTestCase {
    func testSandboxModeTextMatchesRustTemplates() {
        XCTAssertEqual(
            PermissionsInstructions.sandboxText(mode: .workspaceWrite, networkAccess: .restricted),
            "Filesystem sandboxing defines which files can be read or written. `sandbox_mode` is `workspace-write`: The sandbox permits reading files, and editing files in `cwd` and `writable_roots`. Editing files in other directories requires approval. Network access is restricted."
        )
        XCTAssertEqual(
            PermissionsInstructions.sandboxText(mode: .readOnly, networkAccess: .restricted),
            "Filesystem sandboxing defines which files can be read or written. `sandbox_mode` is `read-only`: The sandbox only permits reading files. Network access is restricted."
        )
        XCTAssertEqual(
            PermissionsInstructions.sandboxText(mode: .dangerFullAccess, networkAccess: .enabled),
            "Filesystem sandboxing defines which files can be read or written. `sandbox_mode` is `danger-full-access`: No filesystem sandboxing - all commands are permitted. Network access is enabled."
        )
    }

    func testBuildsPermissionsFromProfileWithWritableRootLikeRust() throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-swift-permissions-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let cwd = try AbsolutePath(absolutePath: tempURL.path)
        let writableRoot = try cwd.join("repo")
        let profile = PermissionProfile.fromRuntimePermissions(
            fileSystem: .restricted(entries: [
                FileSystemSandboxEntry(path: .path(writableRoot.path), access: .write)
            ]),
            network: .enabled
        )
        let renderedRoot = try XCTUnwrap(profile.fileSystemSandboxPolicy.getWritableRootsWithCwd(cwd.path).first?.root.path)

        let instructions = PermissionsInstructions.fromPermissionProfile(
            profile,
            config: PermissionsPromptConfig(approvalPolicy: .unlessTrusted),
            cwd: cwd.path
        )

        XCTAssertTrue(instructions.text.contains("`sandbox_mode` is `workspace-write`"))
        XCTAssertTrue(instructions.text.contains("Network access is enabled."))
        XCTAssertTrue(instructions.text.contains("`approval_policy` is `unless-trusted`"))
        XCTAssertTrue(instructions.text.contains("The writable root is `\(renderedRoot)`"))
    }

    func testOnRequestIncludesApprovedCommandPrefixesLikeRust() throws {
        var policy = ExecPolicy.empty()
        try policy.addPrefixRule(["git", "pull"], decision: .allow)

        let text = PermissionsInstructions.approvalText(config: PermissionsPromptConfig(
            approvalPolicy: .onRequest,
            execPolicy: policy
        ))

        XCTAssertTrue(text.contains("prefix_rule"))
        XCTAssertTrue(text.contains("Approved command prefixes"))
        XCTAssertTrue(text.contains(#"["git", "pull"]"#))
    }

    func testRequestPermissionsToolGuidanceMatchesRustApprovalPolicies() {
        let unlessTrusted = PermissionsInstructions.approvalText(config: PermissionsPromptConfig(
            approvalPolicy: .unlessTrusted,
            requestPermissionsToolEnabled: true
        ))
        let onRequest = PermissionsInstructions.approvalText(config: PermissionsPromptConfig(
            approvalPolicy: .onRequest,
            execPermissionApprovalsEnabled: true,
            requestPermissionsToolEnabled: true
        ))

        XCTAssertTrue(unlessTrusted.contains("# request_permissions Tool"))
        XCTAssertTrue(onRequest.contains("with_additional_permissions"))
        XCTAssertTrue(onRequest.contains("# request_permissions Tool"))
    }

    func testAutoReviewGuidanceUsesRustReviewerNameAndSkipsNeverPolicy() {
        let onRequest = PermissionsInstructions.approvalText(config: PermissionsPromptConfig(
            approvalPolicy: .onRequest,
            approvalsReviewer: .autoReview
        ))
        let never = PermissionsInstructions.approvalText(config: PermissionsPromptConfig(
            approvalPolicy: .never,
            approvalsReviewer: .autoReview
        ))

        XCTAssertTrue(onRequest.contains("`approvals_reviewer` is `auto_review`"))
        XCTAssertFalse(onRequest.contains("`approvals_reviewer` is `guardian_subagent`"))
        XCTAssertTrue(onRequest.contains("materially safer alternative"))
        XCTAssertFalse(never.contains("`approvals_reviewer` is `auto_review`"))
    }

    func testGranularPolicyListsPromptedAndRejectedCategoriesLikeRust() {
        let text = PermissionsInstructions.approvalText(config: PermissionsPromptConfig(
            approvalPolicy: .granular(GranularApprovalConfig(
                sandboxApproval: false,
                rules: true,
                skillApproval: false,
                requestPermissions: true,
                mcpElicitations: false
            )),
            execPermissionApprovalsEnabled: true,
            requestPermissionsToolEnabled: false
        ))

        XCTAssertEqual(text, """
        # Approval Requests

        Approval policy is `granular`. Categories set to `false` are automatically rejected instead of prompting the user.

        These approval categories may still prompt the user when needed:
        - `rules`

        These approval categories are automatically rejected instead of prompting the user:
        - `sandbox_approval`
        - `skill_approval`
        - `mcp_elicitations`
        """)
    }
}
