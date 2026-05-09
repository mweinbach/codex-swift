import CodexCore
import XCTest

final class ConfigRequirementsTests: XCTestCase {
    func testMergeUnsetFieldsOnlyFillsMissingValues() throws {
        let source = try ConfigRequirementsToml.parse("""
        allowed_approval_policies = ["on-request"]
        allowed_approvals_reviewers = ["guardian_subagent"]
        allowed_web_search_modes = ["cached"]
        enforce_residency = "us"

        [features]
        tool_search = true

        [experimental_network]
        enabled = true

        [permissions.filesystem]
        deny_read = ["/private/keys"]
        """)

        var emptyTarget = try ConfigRequirementsToml.parse("""
        # intentionally left unset
        """)
        emptyTarget.mergeUnsetFields(from: source)
        XCTAssertEqual(emptyTarget.allowedApprovalPolicies, [.onRequest])
        XCTAssertEqual(emptyTarget.allowedApprovalsReviewers, [.autoReview])
        XCTAssertEqual(emptyTarget.allowedWebSearchModes, [.cached])
        XCTAssertEqual(emptyTarget.featureRequirements, ["tool_search": true])
        XCTAssertEqual(emptyTarget.enforceResidency, .us)
        XCTAssertEqual(emptyTarget.network?.enabled, true)
        XCTAssertEqual(emptyTarget.permissions?.filesystem?.denyRead, [
            FilesystemDenyReadPattern("/private/keys")
        ])

        var populatedTarget = try ConfigRequirementsToml.parse("""
        allowed_approval_policies = ["never"]
        allowed_web_search_modes = ["live"]
        """)
        populatedTarget.mergeUnsetFields(from: source)
        XCTAssertEqual(populatedTarget.allowedApprovalPolicies, [.never])
        XCTAssertEqual(populatedTarget.allowedApprovalsReviewers, [.autoReview])
        XCTAssertEqual(populatedTarget.allowedWebSearchModes, [.live])
        XCTAssertEqual(populatedTarget.featureRequirements, ["tool_search": true])
        XCTAssertEqual(populatedTarget.enforceResidency, .us)
        XCTAssertEqual(populatedTarget.network?.enabled, true)
        XCTAssertEqual(populatedTarget.permissions?.filesystem?.denyRead, [
            FilesystemDenyReadPattern("/private/keys")
        ])
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

    func testDeserializeAllowedApprovalsReviewers() throws {
        let config = try ConfigRequirementsToml.parse("""
        allowed_approvals_reviewers = ["user", "auto_review", "guardian_subagent"]
        """)

        XCTAssertEqual(config.allowedApprovalsReviewers, [.user, .autoReview, .autoReview])
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

    func testDeserializeAllowedWebSearchModesAndAppServerNormalization() throws {
        let config = try ConfigRequirementsToml.parse("""
        allowed_web_search_modes = ["cached"]
        """)

        XCTAssertEqual(config.allowedWebSearchModes, [.cached])
        let object = config.appServerRequirementsObject()
        XCTAssertEqual(object["allowedWebSearchModes"] as? [String], ["cached", "disabled"])

        let disabledOnly = ConfigRequirementsToml(allowedWebSearchModes: [])
        XCTAssertEqual(disabledOnly.appServerRequirementsObject()["allowedWebSearchModes"] as? [String], ["disabled"])
    }

    func testDeserializeFeatureRequirementsAndResidency() throws {
        let featuresAlias = try ConfigRequirementsToml.parse("""
        enforce_residency = "us"

        [feature_requirements]
        tool_search = true
        plugins = false
        """)

        XCTAssertEqual(featuresAlias.enforceResidency, .us)
        XCTAssertEqual(featuresAlias.featureRequirements, ["tool_search": true, "plugins": false])
        let object = featuresAlias.appServerRequirementsObject()
        XCTAssertEqual(object["enforceResidency"] as? String, "us")
        XCTAssertEqual(object["featureRequirements"] as? [String: Bool], ["tool_search": true, "plugins": false])
    }

    func testDeserializeExperimentalNetworkRequirements() throws {
        let config = try ConfigRequirementsToml.parse("""
        [experimental_network]
        enabled = true
        http_port = 8080
        socks_port = 9090
        allow_upstream_proxy = false
        dangerously_allow_non_loopback_proxy = true
        dangerously_allow_all_unix_sockets = false
        managed_allowed_domains_only = true
        allow_local_binding = true

        [experimental_network.domains]
        "api.openai.com" = "allow"
        "blocked.example.com" = "deny"

        [experimental_network.unix_sockets]
        "/tmp/codex.sock" = "allow"
        "/tmp/deny.sock" = "none"
        """)

        let network = try XCTUnwrap(config.network)
        XCTAssertEqual(network.enabled, true)
        XCTAssertEqual(network.httpPort, 8080)
        XCTAssertEqual(network.socksPort, 9090)
        XCTAssertEqual(network.allowUpstreamProxy, false)
        XCTAssertEqual(network.dangerouslyAllowNonLoopbackProxy, true)
        XCTAssertEqual(network.dangerouslyAllowAllUnixSockets, false)
        XCTAssertEqual(network.managedAllowedDomainsOnly, true)
        XCTAssertEqual(network.allowLocalBinding, true)
        XCTAssertEqual(network.domains, [
            "api.openai.com": .allow,
            "blocked.example.com": .deny
        ])
        XCTAssertEqual(network.unixSockets, [
            "/tmp/codex.sock": .allow,
            "/tmp/deny.sock": .none
        ])

        let object = network.appServerObject()
        XCTAssertEqual(object["enabled"] as? Bool, true)
        XCTAssertEqual(object["httpPort"] as? Int, 8080)
        XCTAssertEqual(object["socksPort"] as? Int, 9090)
        XCTAssertEqual(object["allowUpstreamProxy"] as? Bool, false)
        XCTAssertEqual(object["dangerouslyAllowNonLoopbackProxy"] as? Bool, true)
        XCTAssertEqual(object["dangerouslyAllowAllUnixSockets"] as? Bool, false)
        XCTAssertEqual(object["domains"] as? [String: String], [
            "api.openai.com": "allow",
            "blocked.example.com": "deny"
        ])
        XCTAssertEqual(object["managedAllowedDomainsOnly"] as? Bool, true)
        XCTAssertEqual(object["allowedDomains"] as? [String], ["api.openai.com"])
        XCTAssertEqual(object["deniedDomains"] as? [String], ["blocked.example.com"])
        XCTAssertEqual(object["unixSockets"] as? [String: String], [
            "/tmp/codex.sock": "allow",
            "/tmp/deny.sock": "none"
        ])
        XCTAssertEqual(object["allowUnixSockets"] as? [String], ["/tmp/codex.sock"])
        XCTAssertEqual(object["allowLocalBinding"] as? Bool, true)
    }

    func testExperimentalNetworkLegacyListsNormalizeToCanonicalMaps() throws {
        let config = try ConfigRequirementsToml.parse("""
        [experimental_network]
        allowed_domains = ["api.openai.com", "same.example.com"]
        denied_domains = ["blocked.example.com", "same.example.com"]
        allow_unix_sockets = ["/tmp/codex.sock"]
        """)

        let network = try XCTUnwrap(config.network)
        XCTAssertEqual(network.domains, [
            "api.openai.com": .allow,
            "blocked.example.com": .deny,
            "same.example.com": .deny
        ])
        XCTAssertEqual(network.unixSockets, ["/tmp/codex.sock": .allow])

        let object = network.appServerObject()
        XCTAssertEqual(object["allowedDomains"] as? [String], ["api.openai.com"])
        XCTAssertEqual(object["deniedDomains"] as? [String], ["blocked.example.com", "same.example.com"])
        XCTAssertEqual(object["allowUnixSockets"] as? [String], ["/tmp/codex.sock"])
    }

    func testExperimentalNetworkRejectsCanonicalAndLegacyConflicts() {
        XCTAssertThrowsError(try ConfigRequirementsToml.parse("""
        [experimental_network]
        allowed_domains = ["api.openai.com"]

        [experimental_network.domains]
        "api.openai.com" = "allow"
        """)) { error in
            XCTAssertEqual(
                error as? ConfigRequirementsParseError,
                .invalidNetworkRequirements(
                    "`experimental_network.domains` cannot be combined with legacy `allowed_domains` or `denied_domains`"
                )
            )
        }

        XCTAssertThrowsError(try ConfigRequirementsToml.parse("""
        [experimental_network]
        allow_unix_sockets = ["/tmp/codex.sock"]

        [experimental_network.unix_sockets]
        "/tmp/codex.sock" = "allow"
        """)) { error in
            XCTAssertEqual(
                error as? ConfigRequirementsParseError,
                .invalidNetworkRequirements(
                    "`experimental_network.unix_sockets` cannot be combined with legacy `allow_unix_sockets`"
                )
            )
        }
    }

    func testDeserializeManagedHookRequirementsMatchesRustFlattenedShape() throws {
        let config = try ConfigRequirementsToml.parse("""
        [hooks]
        managed_dir = "/enterprise/hooks"

        [[hooks.PreToolUse]]
        matcher = "^Bash$"

        [[hooks.PreToolUse.hooks]]
        type = "command"
        command = "python3 /enterprise/hooks/pre.py"
        timeout = 10
        statusMessage = "checking"
        """)

        let hooks = try XCTUnwrap(config.hooks)
        XCTAssertEqual(hooks.managedDir, "/enterprise/hooks")
        XCTAssertEqual(hooks.windowsManagedDir, nil)
        XCTAssertEqual(hooks.hookHandlerCount, 1)
        let requirements = try config.requirements()
        XCTAssertEqual(requirements.managedHooks?.value, hooks)
        XCTAssertEqual(requirements.managedHooks?.source, .unknown)

        let object = config.appServerRequirementsObject()
        let hooksObject = try XCTUnwrap(object["hooks"] as? [String: Any])
        XCTAssertEqual(hooksObject["managedDir"] as? String, "/enterprise/hooks")
        XCTAssertTrue(hooksObject["windowsManagedDir"] is NSNull)
        let preToolUse = try XCTUnwrap(hooksObject["PreToolUse"] as? [[String: Any]])
        XCTAssertEqual(preToolUse.count, 1)
        XCTAssertEqual(preToolUse[0]["matcher"] as? String, "^Bash$")
        let handlers = try XCTUnwrap(preToolUse[0]["hooks"] as? [[String: Any]])
        XCTAssertEqual(handlers[0]["type"] as? String, "command")
        XCTAssertEqual(handlers[0]["command"] as? String, "python3 /enterprise/hooks/pre.py")
        XCTAssertEqual(handlers[0]["timeoutSec"] as? Int, 10)
        XCTAssertEqual(handlers[0]["async"] as? Bool, false)
        XCTAssertEqual(handlers[0]["statusMessage"] as? String, "checking")
        XCTAssertEqual((hooksObject["PermissionRequest"] as? [[String: Any]])?.count, 0)
    }

    func testDeserializeFilesystemDenyReadRequirements() throws {
        let config = try ConfigRequirementsToml.parse("""
        [permissions.filesystem]
        deny_read = ["/home/alice/.gitconfig", "/home/alice/.ssh"]
        """)

        XCTAssertEqual(config.permissions?.filesystem?.denyRead, [
            FilesystemDenyReadPattern("/home/alice/.gitconfig"),
            FilesystemDenyReadPattern("/home/alice/.ssh")
        ])

        let requirements = try config.requirements()
        XCTAssertEqual(
            requirements.filesystem,
            FilesystemConstraints(denyRead: [
                FilesystemDenyReadPattern("/home/alice/.gitconfig"),
                FilesystemDenyReadPattern("/home/alice/.ssh")
            ])
        )
    }

    func testDeserializeFilesystemDenyReadGlobRequirements() throws {
        let cwd = FileManager.default.currentDirectoryPath
        let config = try ConfigRequirementsToml.parse("""
        [permissions.filesystem]
        deny_read = ["./private/**/*.txt"]
        """)

        XCTAssertEqual(config.permissions?.filesystem?.denyRead, [
            FilesystemDenyReadPattern("\(cwd)/private/**/*.txt")
        ])
        XCTAssertEqual(try config.requirements().filesystem?.denyRead, [
            FilesystemDenyReadPattern("\(cwd)/private/**/*.txt")
        ])
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
        allowed_approvals_reviewers = ["user", "guardian_subagent"]
        allowed_sandbox_modes = ["read-only", "danger-full-access", "external-sandbox"]
        allowed_web_search_modes = ["live"]
        enforce_residency = "us"

        [features]
        remote_control = true

        [experimental_network]
        enabled = true

        [permissions.filesystem]
        deny_read = ["/private/keys"]
        """)

        XCTAssertFalse(config.isEmpty)
        let object = config.appServerRequirementsObject()
        XCTAssertEqual(object["allowedApprovalPolicies"] as? [String], ["never"])
        XCTAssertEqual(object["allowedSandboxModes"] as? [String], ["read-only", "danger-full-access"])
        XCTAssertEqual(object["allowedApprovalsReviewers"] as? [String], ["user", "guardian_subagent"])
        XCTAssertEqual(object["allowedWebSearchModes"] as? [String], ["live", "disabled"])
        XCTAssertEqual(object["featureRequirements"] as? [String: Bool], ["remote_control": true])
        XCTAssertEqual(object["enforceResidency"] as? String, "us")
        XCTAssertEqual((object["network"] as? [String: Any])?["enabled"] as? Bool, true)
        XCTAssertEqual(config.permissions?.filesystem?.denyRead, [FilesystemDenyReadPattern("/private/keys")])
        XCTAssertTrue(ConfigRequirementsToml().isEmpty)
        XCTAssertTrue(ConfigRequirementsToml(permissions: PermissionsRequirementsToml()).isEmpty)
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
