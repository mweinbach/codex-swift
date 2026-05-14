import CodexCore
import XCTest

final class ConfigRequirementsTests: XCTestCase {
    func testMergeUnsetFieldsOnlyFillsMissingValues() throws {
        let source = try ConfigRequirementsToml.parse("""
        allowed_approval_policies = ["on-request"]
        allowed_approvals_reviewers = ["guardian_subagent"]
        allowed_web_search_modes = ["cached"]
        enforce_residency = "us"
        guardian_policy_config = "Use the company guardian policy."

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
        XCTAssertEqual(emptyTarget.guardianPolicyConfig, "Use the company guardian policy.")
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
        XCTAssertEqual(populatedTarget.guardianPolicyConfig, "Use the company guardian policy.")
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
        let requirements = try config.requirements()
        XCTAssertEqual(requirements.approvalsReviewer.value, .user)
        XCTAssertNoThrow(try requirements.approvalsReviewer.canSet(.autoReview).get())
    }

    func testAllowedApprovalsReviewersConstraintMatchesRust() throws {
        let config = try ConfigRequirementsToml.parse("""
        allowed_approvals_reviewers = ["guardian_subagent"]
        """)
        let requirements = try config.requirements()

        XCTAssertEqual(requirements.approvalsReviewer.value, .autoReview)
        XCTAssertNoThrow(try requirements.approvalsReviewer.canSet(.autoReview).get())
        XCTAssertConstraintFailure(
            requirements.approvalsReviewer.canSet(.user),
            .invalidValue(candidate: "User", allowed: "[AutoReview]")
        )
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

    func testDeserializeRemoteSandboxConfigRequiresHostnamePatternsList() throws {
        let config = try ConfigRequirementsToml.parse("""
        [[remote_sandbox_config]]
        hostname_patterns = ["*.org", "runner-??.ci"]
        allowed_sandbox_modes = ["read-only", "workspace-write"]
        """)

        XCTAssertEqual(config.remoteSandboxConfig, [
            RemoteSandboxConfigToml(
                hostnamePatterns: ["*.org", "runner-??.ci"],
                allowedSandboxModes: [.readOnly, .workspaceWrite]
            )
        ])

        XCTAssertThrowsError(try ConfigRequirementsToml.parse("""
        [[remote_sandbox_config]]
        hostname_patterns = "*.org"
        allowed_sandbox_modes = ["read-only"]
        """)) { error in
            XCTAssertEqual(
                error as? ConfigRequirementsParseError,
                .invalidArray("remote_sandbox_config.hostname_patterns")
            )
        }
    }

    func testRemoteSandboxConfigFirstMatchOverridesTopLevel() throws {
        var config = try ConfigRequirementsToml.parse("""
        allowed_sandbox_modes = ["read-only"]

        [[remote_sandbox_config]]
        hostname_patterns = ["build-*.example.com"]
        allowed_sandbox_modes = ["read-only", "workspace-write"]

        [[remote_sandbox_config]]
        hostname_patterns = ["build-01.example.com"]
        allowed_sandbox_modes = ["read-only", "danger-full-access"]
        """)

        config.applyRemoteSandboxConfig(hostname: "BUILD-01.EXAMPLE.COM..")
        XCTAssertEqual(config.allowedSandboxModes, [.readOnly, .workspaceWrite])

        let requirements = try config.requirements()
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
    }

    func testRemoteSandboxConfigNonMatchPreservesTopLevel() throws {
        var config = try ConfigRequirementsToml.parse("""
        allowed_sandbox_modes = ["read-only"]

        [[remote_sandbox_config]]
        hostname_patterns = ["build-*.example.com"]
        allowed_sandbox_modes = ["read-only", "workspace-write"]
        """)

        config.applyRemoteSandboxConfig(hostname: "laptop.example.com")
        XCTAssertEqual(config.allowedSandboxModes, [.readOnly])
    }

    func testRemoteSandboxConfigDoesNotOverrideHigherPrecedenceSandboxModes() throws {
        var highPrecedence = try ConfigRequirementsToml.parse("""
        allowed_sandbox_modes = ["read-only"]
        """)
        highPrecedence.applyRemoteSandboxConfig(hostname: "runner-01.ci.example.com")

        var lowPrecedence = try ConfigRequirementsToml.parse("""
        [[remote_sandbox_config]]
        hostname_patterns = ["runner-*.ci.example.com"]
        allowed_sandbox_modes = ["read-only", "workspace-write"]
        """)
        lowPrecedence.applyRemoteSandboxConfig(hostname: "runner-01.ci.example.com")

        var merged = ConfigRequirementsToml()
        merged.mergeUnsetFields(from: highPrecedence)
        merged.mergeUnsetFields(from: lowPrecedence)
        XCTAssertEqual(merged.allowedSandboxModes, [.readOnly])

        let requirements = try merged.requirements()
        XCTAssertConstraintFailure(
            requirements.sandboxPolicy.canSet(.workspaceWrite(
                writableRoots: [],
                networkAccess: false,
                excludeTmpdirEnvVar: false,
                excludeSlashTmp: false
            )),
            .invalidValue(
                candidate: "WorkspaceWrite { writable_roots: [], network_access: false, exclude_tmpdir_env_var: false, exclude_slash_tmp: false }",
                allowed: "[ReadOnly]"
            )
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

    func testDeserializeMcpServerRequirements() throws {
        let config = try ConfigRequirementsToml.parse("""
        [mcp_servers.docs.identity]
        command = "codex-mcp"

        [mcp_servers.remote.identity]
        url = "https://example.com/mcp"
        """)

        let expected: [String: McpServerRequirement] = [
            "docs": McpServerRequirement(identity: .command(command: "codex-mcp")),
            "remote": McpServerRequirement(identity: .url(url: "https://example.com/mcp"))
        ]
        XCTAssertEqual(config.mcpServers, expected)
        XCTAssertEqual(try config.requirements().mcpServers, expected)
        XCTAssertFalse(config.isEmpty)
    }

    func testDeserializePluginMcpServerRequirements() throws {
        let config = try ConfigRequirementsToml.parse("""
        [plugins."sample@test".mcp_servers.sample.identity]
        command = "sample-mcp"

        [plugins."remote@test".mcp_servers.remote.identity]
        url = "https://example.com/mcp"
        """)

        let expected: [String: PluginRequirementsToml] = [
            "remote@test": PluginRequirementsToml(mcpServers: [
                "remote": McpServerRequirement(identity: .url(url: "https://example.com/mcp"))
            ]),
            "sample@test": PluginRequirementsToml(mcpServers: [
                "sample": McpServerRequirement(identity: .command(command: "sample-mcp"))
            ])
        ]
        XCTAssertEqual(config.plugins, expected)
        XCTAssertEqual(try config.requirements().plugins, expected)
        XCTAssertFalse(config.isEmpty)
        XCTAssertTrue(ConfigRequirementsToml(plugins: [
            "empty@test": PluginRequirementsToml()
        ]).isEmpty)
    }

    func testMergeUnsetFieldsPreservesHigherPrecedenceMcpAndPluginRequirements() throws {
        var merged = try ConfigRequirementsToml.parse("""
        [mcp_servers.docs.identity]
        command = "high-mcp"

        [plugins."sample@test".mcp_servers.sample.identity]
        command = "high-plugin-mcp"
        """)

        let lower = try ConfigRequirementsToml.parse("""
        [mcp_servers.docs.identity]
        command = "low-mcp"

        [mcp_servers.remote.identity]
        url = "https://example.com/mcp"

        [plugins."sample@test".mcp_servers.sample.identity]
        command = "low-plugin-mcp"

        [plugins."remote@test".mcp_servers.remote.identity]
        url = "https://example.com/plugin-mcp"
        """)

        merged.mergeUnsetFields(from: lower)
        XCTAssertEqual(merged.mcpServers, [
            "docs": McpServerRequirement(identity: .command(command: "high-mcp"))
        ])
        XCTAssertEqual(merged.plugins, [
            "sample@test": PluginRequirementsToml(mcpServers: [
                "sample": McpServerRequirement(identity: .command(command: "high-plugin-mcp"))
            ])
        ])

        var empty = ConfigRequirementsToml()
        empty.mergeUnsetFields(from: lower)
        XCTAssertEqual(empty.mcpServers, [
            "docs": McpServerRequirement(identity: .command(command: "low-mcp")),
            "remote": McpServerRequirement(identity: .url(url: "https://example.com/mcp"))
        ])
        XCTAssertEqual(empty.plugins, [
            "remote@test": PluginRequirementsToml(mcpServers: [
                "remote": McpServerRequirement(identity: .url(url: "https://example.com/plugin-mcp"))
            ]),
            "sample@test": PluginRequirementsToml(mcpServers: [
                "sample": McpServerRequirement(identity: .command(command: "low-plugin-mcp"))
            ])
        ])
    }

    func testDeserializeRequirementsExecPolicyRules() throws {
        let config = try ConfigRequirementsToml.parse("""
        [rules]
        prefix_rules = [{ pattern = [{ token = "rm" }], decision = "forbidden" }, { pattern = [{ any_of = ["npm", "pnpm"] }, { token = "publish" }], decision = "prompt", justification = "publishing packages" }]
        """)

        XCTAssertEqual(config.rules, RequirementsExecPolicyToml(prefixRules: [
            RequirementsExecPolicyPrefixRuleToml(
                pattern: [RequirementsExecPolicyPatternTokenToml(token: "rm")],
                decision: .forbidden
            ),
            RequirementsExecPolicyPrefixRuleToml(
                pattern: [
                    RequirementsExecPolicyPatternTokenToml(anyOf: ["npm", "pnpm"]),
                    RequirementsExecPolicyPatternTokenToml(token: "publish")
                ],
                decision: .prompt,
                justification: "publishing packages"
            )
        ]))
        XCTAssertFalse(config.isEmpty)

        let policy = try XCTUnwrap(try config.requirements().execPolicy)
        XCTAssertEqual(
            policy.check(["rm", "-rf"], heuristicsFallback: { _ in .allow }),
            PolicyEvaluation(
                decision: .forbidden,
                matchedRules: [.prefixRuleMatch(matchedPrefix: ["rm"], decision: .forbidden)]
            )
        )
        XCTAssertEqual(
            policy.check(["pnpm", "publish", "--dry-run"], heuristicsFallback: { _ in .allow }),
            PolicyEvaluation(
                decision: .prompt,
                matchedRules: [.prefixRuleMatch(
                    matchedPrefix: ["pnpm", "publish"],
                    decision: .prompt,
                    justification: "publishing packages"
                )]
            )
        )
    }

    func testRequirementsExecPolicyRejectsRustInvalidShapes() throws {
        let missingDecision = try ConfigRequirementsToml.parse("""
        [rules]
        prefix_rules = [{ pattern = [{ token = "rm" }] }]
        """)
        XCTAssertThrowsError(try missingDecision.requirements()) { error in
            XCTAssertEqual(
                error as? ConstraintError,
                .invalidRequirementsExecPolicy(reason: "rules prefix_rule at index 0 is missing a decision")
            )
        }

        let allowDecision = try ConfigRequirementsToml.parse("""
        [rules]
        prefix_rules = [{ pattern = [{ token = "ls" }], decision = "allow" }]
        """)
        XCTAssertThrowsError(try allowDecision.requirements()) { error in
            XCTAssertEqual(
                error as? ConstraintError,
                .invalidRequirementsExecPolicy(reason: "rules prefix_rule at index 0 has decision 'allow', which is not permitted in requirements.toml: Codex merges these rules with other config and uses the most restrictive result (use 'prompt' or 'forbidden')")
            )
        }

        let bothTokenForms = try ConfigRequirementsToml.parse("""
        [rules]
        prefix_rules = [{ pattern = [{ token = "npm", any_of = ["pnpm"] }], decision = "prompt" }]
        """)
        XCTAssertThrowsError(try bothTokenForms.requirements()) { error in
            XCTAssertEqual(
                error as? ConstraintError,
                .invalidRequirementsExecPolicy(
                    reason: "rules prefix_rule at index 0 has an invalid pattern token at index 0: set either token or any_of, not both"
                )
            )
        }
    }

    func testMergeUnsetFieldsPreservesHigherPrecedenceRequirementsExecPolicy() throws {
        var merged = try ConfigRequirementsToml.parse("""
        [rules]
        prefix_rules = [{ pattern = [{ token = "rm" }], decision = "forbidden" }]
        """)
        let lower = try ConfigRequirementsToml.parse("""
        [rules]
        prefix_rules = [{ pattern = [{ token = "git" }, { token = "push" }], decision = "prompt" }]
        """)

        merged.mergeUnsetFields(from: lower)
        XCTAssertEqual(merged.rules?.prefixRules.first?.pattern.first?.token, "rm")

        var empty = ConfigRequirementsToml()
        empty.mergeUnsetFields(from: lower)
        XCTAssertEqual(empty.rules, lower.rules)
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

    func testEmptyAllowedApprovalsReviewersMatchesRustConstraintError() {
        let config = ConfigRequirementsToml(allowedApprovalsReviewers: [])
        XCTAssertThrowsError(try config.requirements()) { error in
            XCTAssertEqual(error as? ConstraintError, .emptyField(fieldName: "allowed_approvals_reviewers"))
        }
    }

    func testGuardianPolicyConfigBlankIsEmptyAndDoesNotBlockLowerPrecedenceValue() throws {
        let blank = try ConfigRequirementsToml.parse("""
        guardian_policy_config = "   \t"
        """)
        XCTAssertTrue(blank.isEmpty)

        var merged = blank
        let lower = try ConfigRequirementsToml.parse("""
        guardian_policy_config = "Use the system guardian policy."
        """)
        merged.mergeUnsetFields(from: lower)
        XCTAssertEqual(merged.guardianPolicyConfig, "Use the system guardian policy.")
        XCTAssertFalse(merged.isEmpty)

        var high = try ConfigRequirementsToml.parse("""
        guardian_policy_config = "Use the higher guardian policy."
        """)
        high.mergeUnsetFields(from: lower)
        XCTAssertEqual(high.guardianPolicyConfig, "Use the higher guardian policy.")
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

    func testDeserializeAppsRequirements() throws {
        let config = try ConfigRequirementsToml.parse("""
        [apps.connector_123123]
        enabled = false

        [apps.connector_unset]
        """)

        XCTAssertEqual(config.apps, AppsRequirementsToml(apps: [
            "connector_123123": AppRequirementToml(enabled: false),
            "connector_unset": AppRequirementToml()
        ]))
        XCTAssertFalse(config.isEmpty)
        XCTAssertTrue(ConfigRequirementsToml(apps: AppsRequirementsToml()).isEmpty)
        XCTAssertTrue(ConfigRequirementsToml(apps: AppsRequirementsToml(apps: [
            "connector_unset": AppRequirementToml()
        ])).isEmpty)
    }

    func testAppsRequirementsMergeEnablementSettingsLikeRust() {
        var merged = AppsRequirementsToml(apps: [
            "connector_high": AppRequirementToml(enabled: true),
            "connector_shared": AppRequirementToml(enabled: true),
            "connector_disabled": AppRequirementToml(enabled: false)
        ])

        merged.mergeEnablementSettingsDescending(from: AppsRequirementsToml(apps: [
            "connector_low": AppRequirementToml(enabled: true),
            "connector_shared": AppRequirementToml(enabled: false),
            "connector_disabled": AppRequirementToml(),
            "connector_unset": AppRequirementToml()
        ]))

        XCTAssertEqual(merged, AppsRequirementsToml(apps: [
            "connector_high": AppRequirementToml(enabled: true),
            "connector_low": AppRequirementToml(enabled: true),
            "connector_shared": AppRequirementToml(enabled: false),
            "connector_disabled": AppRequirementToml(enabled: false),
            "connector_unset": AppRequirementToml()
        ]))
    }

    func testMergeUnsetFieldsMergesAppsAcrossSourcesWithDescendingDisableWinsSemantics() throws {
        var merged = try ConfigRequirementsToml.parse("""
        [apps.connector_high]
        enabled = true

        [apps.connector_shared]
        enabled = true
        """)

        let lower = try ConfigRequirementsToml.parse("""
        [apps.connector_low]
        enabled = false

        [apps.connector_shared]
        enabled = false
        """)

        merged.mergeUnsetFields(from: lower)
        XCTAssertEqual(merged.apps, AppsRequirementsToml(apps: [
            "connector_high": AppRequirementToml(enabled: true),
            "connector_low": AppRequirementToml(enabled: false),
            "connector_shared": AppRequirementToml(enabled: false)
        ]))

        var emptyHigher = try ConfigRequirementsToml.parse("""
        [apps.connector_empty]
        """)
        emptyHigher.mergeUnsetFields(from: lower)
        XCTAssertEqual(emptyHigher.apps, AppsRequirementsToml(apps: [
            "connector_low": AppRequirementToml(enabled: false),
            "connector_shared": AppRequirementToml(enabled: false)
        ]))
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

    func testCloudRequirementsParsingMatchesRustEmptyAndPopulatedSemantics() throws {
        XCTAssertNil(try CloudRequirements.parse(""))
        XCTAssertNil(try CloudRequirements.parse("   \n\t"))
        XCTAssertNil(try CloudRequirements.parse("""
        [apps.some_app]
        """))

        let parsed = try XCTUnwrap(try CloudRequirements.parse("""
        allowed_approval_policies = ["never"]
        [features]
        remote_control = true
        """))

        let requirements = try parsed.requirements()
        XCTAssertEqual(requirements.approvalPolicy.value, .never)
        XCTAssertEqual(parsed.featureRequirements, ["remote_control": true])
    }

    func testCloudRequirementsParseFailureMessageMatchesRustPrefix() {
        let message = CloudRequirements.parseFailedMessage(
            details: ConfigRequirementsParseError.invalidApprovalPolicy("sometimes")
        )

        XCTAssertTrue(message.hasPrefix("Cloud requirements (workspace-managed policies) are invalid and could not be parsed. Please contact your workspace admin.\n\nDetails:\n"))
        XCTAssertTrue(message.contains("Invalid approval policy requirement: sometimes"))
    }

    func testCloudRequirementsEligibilityMatchesRustPlanBoundary() {
        XCTAssertEqual(CloudRequirements.timeout, 15)
        XCTAssertEqual(CloudRequirements.maxAttempts, 5)
        XCTAssertEqual(CloudRequirements.cacheRefreshInterval, 5 * 60)
        XCTAssertEqual(CloudRequirements.fetchAttemptMetricName, "codex.cloud_requirements.fetch_attempt")
        XCTAssertEqual(CloudRequirements.fetchFinalMetricName, "codex.cloud_requirements.fetch_final")
        XCTAssertEqual(CloudRequirements.loadMetricName, "codex.cloud_requirements.load")
        XCTAssertEqual(CloudRequirements.cacheTTL, 30 * 60)
        XCTAssertEqual(
            CloudRequirements.authRecoveryFailedMessage,
            "Your authentication session could not be refreshed automatically. Please log out and sign in again."
        )

        XCTAssertFalse(CloudRequirements.isEligibleAuth(planType: nil, usesCodexBackend: true))
        XCTAssertFalse(CloudRequirements.isEligibleAuth(planType: .business, usesCodexBackend: false))

        XCTAssertTrue(CloudRequirements.isEligibleAuth(planType: .business, usesCodexBackend: true))
        XCTAssertTrue(CloudRequirements.isEligibleAuth(planType: .enterpriseCbpUsageBased, usesCodexBackend: true))
        XCTAssertTrue(CloudRequirements.isEligibleAuth(planType: .enterprise, usesCodexBackend: true))

        XCTAssertFalse(CloudRequirements.isEligibleAuth(planType: .team, usesCodexBackend: true))
        XCTAssertFalse(CloudRequirements.isEligibleAuth(planType: .selfServeBusinessUsageBased, usesCodexBackend: true))
        XCTAssertFalse(CloudRequirements.isEligibleAuth(planType: .edu, usesCodexBackend: true))
        XCTAssertFalse(CloudRequirements.isEligibleAuth(planType: .pro, usesCodexBackend: true))
        XCTAssertFalse(CloudRequirements.isEligibleAuth(planType: .unknown, usesCodexBackend: true))
    }

    func testCloudRequirementsFetchAttemptStatusCodesMatchRust() {
        XCTAssertNil(CloudRequirementsRetryableFailureKind.backendClientInit.statusCode)
        XCTAssertNil(CloudRequirementsRetryableFailureKind.request(statusCode: nil).statusCode)
        XCTAssertEqual(CloudRequirementsRetryableFailureKind.request(statusCode: 503).statusCode, 503)

        XCTAssertEqual(
            CloudRequirementsFetchAttemptError.retryable(.backendClientInit).statusCode,
            nil
        )
        XCTAssertEqual(
            CloudRequirementsFetchAttemptError.retryable(.request(statusCode: 502)).statusCode,
            502
        )
        XCTAssertEqual(
            CloudRequirementsFetchAttemptError.unauthorized(
                statusCode: 401,
                message: "GET /config/requirements failed: 401"
            ).statusCode,
            401
        )
        XCTAssertEqual(CloudRequirements.statusCodeTag(nil), "none")
        XCTAssertEqual(CloudRequirements.statusCodeTag(429), "429")
    }

    func testCloudRequirementsMetricTagsMatchRustOrderAndKeys() {
        XCTAssertEqual(
            CloudRequirements.fetchAttemptMetricTags(
                trigger: "startup",
                attempt: 2,
                outcome: "unauthorized",
                statusCode: 401
            ),
            [
                CloudRequirementsMetricTag(key: "trigger", value: "startup"),
                CloudRequirementsMetricTag(key: "attempt", value: "2"),
                CloudRequirementsMetricTag(key: "outcome", value: "unauthorized"),
                CloudRequirementsMetricTag(key: "status_code", value: "401")
            ]
        )

        XCTAssertEqual(
            CloudRequirements.fetchFinalMetricTags(
                trigger: "refresh",
                outcome: "error",
                reason: "request_retry_exhausted",
                attemptCount: CloudRequirements.maxAttempts,
                statusCode: nil
            ),
            [
                CloudRequirementsMetricTag(key: "trigger", value: "refresh"),
                CloudRequirementsMetricTag(key: "outcome", value: "error"),
                CloudRequirementsMetricTag(key: "reason", value: "request_retry_exhausted"),
                CloudRequirementsMetricTag(key: "attempt_count", value: "5"),
                CloudRequirementsMetricTag(key: "status_code", value: "none")
            ]
        )
    }

    func testCloudRequirementsLoaderSharesSingleResultLikeRust() async throws {
        let counter = Counter()
        let loader = CloudRequirementsLoader {
            await counter.increment()
            return .success(ConfigRequirementsToml())
        }

        async let first = loader.get()
        async let second = loader.get()

        _ = try await (first, second)
        let invocationCount = await counter.value
        XCTAssertEqual(invocationCount, 1)
    }

    func testCloudRequirementsLoaderDefaultReturnsNoRequirementsLikeRust() async throws {
        let loader = CloudRequirementsLoader()

        let requirements = try await loader.get()

        XCTAssertNil(requirements)
    }

    func testCloudRequirementsLoadErrorCodesMatchRustSet() {
        XCTAssertEqual(CloudRequirementsLoadErrorCode.auth.rawValue, "Auth")
        XCTAssertEqual(CloudRequirementsLoadErrorCode.timeout.rawValue, "Timeout")
        XCTAssertEqual(CloudRequirementsLoadErrorCode.parse.rawValue, "Parse")
        XCTAssertEqual(CloudRequirementsLoadErrorCode.requestFailed.rawValue, "RequestFailed")
        XCTAssertEqual(CloudRequirementsLoadErrorCode.internalError.rawValue, "Internal")
    }

    func testCloudRequirementsCachePayloadSignsAndParsesLikeRust() throws {
        let cachedAt = Date(timeIntervalSince1970: 1_778_752_800)
        let cacheFile = try CloudRequirements.makeCacheFile(
            cachedAt: cachedAt,
            chatgptUserID: "user-12345",
            accountID: "account-12345",
            contents: #"allowed_approval_policies = ["never"]"#
        )

        let payloadBytes = try CloudRequirements.cachePayloadBytes(cacheFile.signedPayload)
        XCTAssertEqual(
            String(decoding: payloadBytes, as: UTF8.self),
            #"{"cached_at":"2026-05-14T10:00:00Z","expires_at":"2026-05-14T10:30:00Z","chatgpt_user_id":"user-12345","account_id":"account-12345","contents":"allowed_approval_policies = [\"never\"]"}"#
        )
        XCTAssertEqual(cacheFile.signature, "yjgMb/kCjSFMpyh+SyIUwf21DmT0yoW6E6iktDwJpZA=")
        XCTAssertTrue(CloudRequirements.verifyCacheSignature(payloadBytes: payloadBytes, signature: cacheFile.signature))
        XCTAssertFalse(CloudRequirements.verifyCacheSignature(payloadBytes: payloadBytes, signature: "not-base64"))

        let requirements = try XCTUnwrap(cacheFile.signedPayload.requirements())
        XCTAssertEqual(try requirements.requirements().approvalPolicy.value, .never)
        XCTAssertFalse(cacheFile.signedPayload.isExpired(now: cachedAt.addingTimeInterval(60)))
        XCTAssertTrue(cacheFile.signedPayload.isExpired(now: cachedAt.addingTimeInterval(CloudRequirements.cacheTTL)))
    }

    func testCloudRequirementsCacheFileUsesRustSnakeCaseJSON() throws {
        let cacheFile = try CloudRequirements.makeCacheFile(
            cachedAt: Date(timeIntervalSince1970: 1_778_752_800),
            chatgptUserID: nil,
            accountID: nil,
            contents: nil
        )

        let prettyJSON = String(decoding: try CloudRequirements.prettyCacheFileData(cacheFile), as: UTF8.self)
        XCTAssertTrue(prettyJSON.contains(#""signed_payload" : {"#))
        XCTAssertTrue(prettyJSON.contains(#""signature" : ""#))
        XCTAssertTrue(prettyJSON.contains(#""chatgpt_user_id" : null"#))
        XCTAssertTrue(prettyJSON.contains(#""account_id" : null"#))
        XCTAssertTrue(prettyJSON.contains(#""contents" : null"#))
    }

    func testCloudRequirementsLoadCacheFileDataAcceptsValidCacheLikeRust() throws {
        let now = Date(timeIntervalSince1970: 1_778_752_800)
        let cacheFile = try CloudRequirements.makeCacheFile(
            cachedAt: now.addingTimeInterval(-60),
            chatgptUserID: "user-12345",
            accountID: "account-12345",
            contents: #"allowed_approval_policies = ["never"]"#
        )

        let payload = try CloudRequirements.loadCacheFileData(
            try CloudRequirements.prettyCacheFileData(cacheFile),
            chatgptUserID: "user-12345",
            accountID: "account-12345",
            now: now
        )

        XCTAssertEqual(payload, cacheFile.signedPayload)
        XCTAssertEqual(try payload.requirements()?.requirements().approvalPolicy.value, .never)
    }

    func testCloudRequirementsLoadCacheFileDataRejectsIncompleteCallerIdentityLikeRust() throws {
        let cacheFile = try CloudRequirements.makeCacheFile(
            cachedAt: Date(timeIntervalSince1970: 1_778_752_800),
            chatgptUserID: "user-12345",
            accountID: "account-12345",
            contents: nil
        )
        let data = try CloudRequirements.prettyCacheFileData(cacheFile)

        XCTAssertThrowsError(try CloudRequirements.loadCacheFileData(
            data,
            chatgptUserID: nil,
            accountID: "account-12345"
        )) { error in
            XCTAssertEqual(error as? CloudRequirementsCacheLoadStatus, .authIdentityIncomplete)
        }

        XCTAssertThrowsError(try CloudRequirements.loadCacheFileData(
            data,
            chatgptUserID: "user-12345",
            accountID: nil
        )) { error in
            XCTAssertEqual(error as? CloudRequirementsCacheLoadStatus, .authIdentityIncomplete)
        }
    }

    func testCloudRequirementsLoadCacheFileDataRejectsTamperingIdentityAndExpiryLikeRust() throws {
        let now = Date(timeIntervalSince1970: 1_778_752_800)
        let valid = try CloudRequirements.makeCacheFile(
            cachedAt: now,
            chatgptUserID: "user-12345",
            accountID: "account-12345",
            contents: nil
        )
        var tamperedPayload = valid.signedPayload
        tamperedPayload.contents = #"allowed_approval_policies = ["never"]"#
        let tampered = CloudRequirementsCacheFile(
            signedPayload: tamperedPayload,
            signature: valid.signature
        )

        XCTAssertThrowsError(try CloudRequirements.loadCacheFileData(
            try CloudRequirements.prettyCacheFileData(tampered),
            chatgptUserID: "user-12345",
            accountID: "account-12345",
            now: now
        )) { error in
            XCTAssertEqual(error as? CloudRequirementsCacheLoadStatus, .cacheSignatureInvalid)
        }

        let incompleteIdentity = try signedCacheFile(payload: CloudRequirementsCacheSignedPayload(
            cachedAt: now,
            expiresAt: now.addingTimeInterval(CloudRequirements.cacheTTL),
            chatgptUserID: nil,
            accountID: "account-12345",
            contents: nil
        ))
        XCTAssertThrowsError(try CloudRequirements.loadCacheFileData(
            try CloudRequirements.prettyCacheFileData(incompleteIdentity),
            chatgptUserID: "user-12345",
            accountID: "account-12345",
            now: now
        )) { error in
            XCTAssertEqual(error as? CloudRequirementsCacheLoadStatus, .cacheIdentityIncomplete)
        }

        XCTAssertThrowsError(try CloudRequirements.loadCacheFileData(
            try CloudRequirements.prettyCacheFileData(valid),
            chatgptUserID: "different-user",
            accountID: "account-12345",
            now: now
        )) { error in
            XCTAssertEqual(error as? CloudRequirementsCacheLoadStatus, .cacheIdentityMismatch)
        }

        let expired = try signedCacheFile(payload: CloudRequirementsCacheSignedPayload(
            cachedAt: now.addingTimeInterval(-CloudRequirements.cacheTTL),
            expiresAt: now,
            chatgptUserID: "user-12345",
            accountID: "account-12345",
            contents: nil
        ))
        XCTAssertThrowsError(try CloudRequirements.loadCacheFileData(
            try CloudRequirements.prettyCacheFileData(expired),
            chatgptUserID: "user-12345",
            accountID: "account-12345",
            now: now
        )) { error in
            XCTAssertEqual(error as? CloudRequirementsCacheLoadStatus, .cacheExpired)
        }
    }

    func testCloudRequirementsLoadCacheFileReportsMissingAndMalformedCacheLikeRust() {
        let missingURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent(CloudRequirements.cacheFilename)

        XCTAssertThrowsError(try CloudRequirements.loadCacheFile(
            at: missingURL,
            chatgptUserID: nil,
            accountID: "account-12345"
        )) { error in
            XCTAssertEqual(error as? CloudRequirementsCacheLoadStatus, .authIdentityIncomplete)
        }

        XCTAssertThrowsError(try CloudRequirements.loadCacheFile(
            at: missingURL,
            chatgptUserID: "user-12345",
            accountID: "account-12345"
        )) { error in
            XCTAssertEqual(error as? CloudRequirementsCacheLoadStatus, .cacheFileNotFound)
        }

        XCTAssertThrowsError(try CloudRequirements.loadCacheFileData(
            Data("not json".utf8),
            chatgptUserID: "user-12345",
            accountID: "account-12345"
        )) { error in
            guard case .cacheParseFailed = error as? CloudRequirementsCacheLoadStatus else {
                return XCTFail("expected cache parse failure, got \(error)")
            }
        }
    }

    func testCloudRequirementsSaveCacheFileWritesSignedPrettyCacheLikeRust() throws {
        let now = Date(timeIntervalSince1970: 1_778_752_800)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("nested", isDirectory: true)
        let path = directory.appendingPathComponent(CloudRequirements.cacheFilename)
        defer {
            try? FileManager.default.removeItem(at: directory.deletingLastPathComponent())
        }

        try CloudRequirements.saveCacheFile(
            at: path,
            cachedAt: now,
            chatgptUserID: "user-12345",
            accountID: "account-12345",
            contents: #"allowed_approval_policies = ["never"]"#
        )

        let data = try Data(contentsOf: path)
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(json.contains(#""signed_payload" : {"#))
        XCTAssertTrue(json.contains(#""signature" : ""#))

        let payload = try CloudRequirements.loadCacheFile(
            at: path,
            chatgptUserID: "user-12345",
            accountID: "account-12345",
            now: now
        )
        XCTAssertEqual(payload.cachedAt, now)
        XCTAssertEqual(payload.expiresAt, now.addingTimeInterval(CloudRequirements.cacheTTL))
        XCTAssertEqual(payload.chatgptUserID, "user-12345")
        XCTAssertEqual(payload.accountID, "account-12345")
        XCTAssertEqual(try payload.requirements()?.requirements().approvalPolicy.value, .never)
    }

    func testCloudRequirementsSaveCacheFileKeepsIncompleteIdentityLikeRust() throws {
        let now = Date(timeIntervalSince1970: 1_778_752_800)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let path = directory.appendingPathComponent(CloudRequirements.cacheFilename)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        try CloudRequirements.saveCacheFile(
            at: path,
            cachedAt: now,
            chatgptUserID: nil,
            accountID: nil,
            contents: nil
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: path.path))
        XCTAssertThrowsError(try CloudRequirements.loadCacheFile(
            at: path,
            chatgptUserID: "user-12345",
            accountID: "account-12345",
            now: now
        )) { error in
            XCTAssertEqual(error as? CloudRequirementsCacheLoadStatus, .cacheIdentityIncomplete)
        }

        let cacheFile = try JSONDecoder().decode(
            CloudRequirementsCacheFile.self,
            from: Data(contentsOf: path)
        )
        XCTAssertNil(cacheFile.signedPayload.chatgptUserID)
        XCTAssertNil(cacheFile.signedPayload.accountID)
        XCTAssertTrue(CloudRequirements.verifyCacheSignature(
            payloadBytes: try CloudRequirements.cachePayloadBytes(cacheFile.signedPayload),
            signature: cacheFile.signature
        ))
    }

    func testCloudRequirementsSaveCacheFileReportsWriteFailureLikeRust() throws {
        let fileAsParent = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try Data().write(to: fileAsParent)
        defer {
            try? FileManager.default.removeItem(at: fileAsParent)
        }

        XCTAssertThrowsError(try CloudRequirements.saveCacheFile(
            at: fileAsParent.appendingPathComponent(CloudRequirements.cacheFilename),
            cachedAt: Date(timeIntervalSince1970: 1_778_752_800),
            chatgptUserID: "user-12345",
            accountID: "account-12345",
            contents: nil
        )) { error in
            XCTAssertEqual(error as? CloudRequirementsCacheWriteError, .cacheWrite)
            XCTAssertEqual("\(error)", "failed to write cloud requirements cache")
        }
    }

    func testCloudRequirementsCacheLoadStatusDescriptionsMatchRust() {
        XCTAssertEqual(
            CloudRequirementsCacheLoadStatus.authIdentityIncomplete.description,
            "Skipping cloud requirements cache read because auth identity is incomplete."
        )
        XCTAssertEqual(
            CloudRequirementsCacheLoadStatus.cacheFileNotFound.description,
            "Cloud requirements cache file not found."
        )
        XCTAssertEqual(
            CloudRequirementsCacheLoadStatus.cacheReadFailed("permission denied").description,
            "Failed to read cloud requirements cache: permission denied."
        )
        XCTAssertEqual(
            CloudRequirementsCacheLoadStatus.cacheParseFailed("invalid json").description,
            "Failed to parse cloud requirements cache: invalid json."
        )
        XCTAssertEqual(
            CloudRequirementsCacheLoadStatus.cacheSignatureInvalid.description,
            "Cloud requirements cache failed signature verification."
        )
        XCTAssertEqual(
            CloudRequirementsCacheLoadStatus.cacheIdentityIncomplete.description,
            "Ignoring cloud requirements cache because cached identity is incomplete."
        )
        XCTAssertEqual(
            CloudRequirementsCacheLoadStatus.cacheIdentityMismatch.description,
            "Ignoring cloud requirements cache for different auth identity."
        )
        XCTAssertEqual(
            CloudRequirementsCacheLoadStatus.cacheExpired.description,
            "Cloud requirements cache expired."
        )
    }

    private func signedCacheFile(payload: CloudRequirementsCacheSignedPayload) throws -> CloudRequirementsCacheFile {
        let payloadBytes = try CloudRequirements.cachePayloadBytes(payload)
        return CloudRequirementsCacheFile(
            signedPayload: payload,
            signature: CloudRequirements.signCachePayload(payloadBytes)
        )
    }
}

private actor Counter {
    private var count = 0

    var value: Int {
        count
    }

    func increment() {
        count += 1
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
