import CodexCore
import XCTest

final class ExecPolicyTests: XCTestCase {
    func testBasicMatch() throws {
        let policy = try parsePolicy("""
        prefix_rule(
            pattern = ["git", "status"],
        )
        """)

        XCTAssertEqual(
            policy.check(tokens("git", "status"), heuristicsFallback: allowAll),
            PolicyEvaluation(
                decision: .allow,
                matchedRules: [.prefixRuleMatch(matchedPrefix: tokens("git", "status"), decision: .allow)]
            )
        )
    }

    func testAddPrefixRuleExtendsPolicy() throws {
        var policy = ExecPolicy.empty()
        try policy.addPrefixRule(tokens("ls", "-l"), decision: .prompt)

        XCTAssertEqual(
            policy.rules(for: "ls"),
            [
                PrefixRule(
                    pattern: PrefixPattern(first: "ls", rest: [.single("-l")]),
                    decision: .prompt
                )
            ]
        )
        XCTAssertEqual(
            policy.check(tokens("ls", "-l", "/tmp"), heuristicsFallback: allowAll),
            PolicyEvaluation(
                decision: .prompt,
                matchedRules: [.prefixRuleMatch(matchedPrefix: tokens("ls", "-l"), decision: .prompt)]
            )
        )
    }

    func testAddPrefixRuleRejectsEmptyPrefix() {
        var policy = ExecPolicy.empty()
        XCTAssertThrowsError(try policy.addPrefixRule([], decision: .allow)) { error in
            XCTAssertEqual(error as? ExecPolicyError, .invalidPattern("prefix cannot be empty"))
        }
    }

    func testJustificationIsAttachedToPrefixMatches() throws {
        let policy = try parsePolicy("""
        prefix_rule(
            pattern = ["rm"],
            decision = "forbidden",
            justification = "destructive command",
        )
        prefix_rule(
            pattern = ["ls"],
            decision = "allow",
            justification = "safe and commonly used",
        )
        """)

        XCTAssertEqual(
            policy.check(tokens("rm", "-rf", "/tmp/work"), heuristicsFallback: allowAll),
            PolicyEvaluation(
                decision: .forbidden,
                matchedRules: [.prefixRuleMatch(
                    matchedPrefix: tokens("rm"),
                    decision: .forbidden,
                    justification: "destructive command"
                )]
            )
        )
        XCTAssertEqual(
            policy.check(tokens("ls", "-l"), heuristicsFallback: promptAll),
            PolicyEvaluation(
                decision: .allow,
                matchedRules: [.prefixRuleMatch(
                    matchedPrefix: tokens("ls"),
                    decision: .allow,
                    justification: "safe and commonly used"
                )]
            )
        )
    }

    func testJustificationCannotBeEmpty() {
        XCTAssertThrowsError(try parsePolicy("""
        prefix_rule(
            pattern = ["ls"],
            decision = "prompt",
            justification = "   ",
        )
        """)) { error in
            XCTAssertEqual(error as? ExecPolicyError, .invalidRule("justification cannot be empty"))
        }
    }

    func testNetworkRulesCompileIntoDomainLists() throws {
        let policy = try parsePolicy("""
        network_rule(host = "google.com", protocol = "http", decision = "allow")
        network_rule(host = "api.github.com", protocol = "https", decision = "allow")
        network_rule(host = "blocked.example.com", protocol = "https", decision = "deny")
        network_rule(host = "prompt-only.example.com", protocol = "https", decision = "prompt")
        """)

        XCTAssertEqual(policy.networkRules().count, 4)
        XCTAssertEqual(policy.networkRules()[1].protocol, .https)
        let domains = policy.compiledNetworkDomains()
        XCTAssertEqual(domains.allowed, ["google.com", "api.github.com"])
        XCTAssertEqual(domains.denied, ["blocked.example.com"])
    }

    func testNetworkRuleNormalizesHostAndProtocolAliases() throws {
        let policy = try parsePolicy("""
        network_rule(host = " EXAMPLE.com.:443 ", protocol = "http-connect", decision = "allow")
        network_rule(host = "[2001:db8::1]:443", protocol = "socks5_tcp", decision = "deny")
        """)

        XCTAssertEqual(policy.networkRules()[0].host, "example.com")
        XCTAssertEqual(policy.networkRules()[0].protocol, .https)
        XCTAssertEqual(policy.networkRules()[1].host, "2001:db8::1")
        XCTAssertEqual(policy.networkRules()[1].protocol, .socks5Tcp)
        let domains = policy.compiledNetworkDomains()
        XCTAssertEqual(domains.allowed, ["example.com"])
        XCTAssertEqual(domains.denied, ["2001:db8::1"])
    }

    func testNetworkRuleRejectsWildcardHosts() {
        XCTAssertThrowsError(try parsePolicy(
            #"network_rule(host="*", protocol="http", decision="allow")"#
        )) { error in
            XCTAssertEqual(
                error as? ExecPolicyError,
                .invalidRule("network_rule host must be a specific host; wildcards are not allowed")
            )
        }
    }

    func testParsesHostExecutablePaths() throws {
        let policy = try parsePolicy("""
        host_executable(
            name = "git",
            paths = [
                "/opt/homebrew/bin/git",
                "/usr/bin/git",
                "/usr/bin/git",
            ],
        )
        """)

        XCTAssertEqual(policy.hostExecutables()["git"], ["/opt/homebrew/bin/git", "/usr/bin/git"])
    }

    func testHostExecutableValidationMatchesRust() {
        XCTAssertThrowsError(try parsePolicy(#"host_executable(name = "git", paths = ["git"])"#)) { error in
            XCTAssertEqual(error as? ExecPolicyError, .invalidRule("host_executable paths must be absolute (got git)"))
        }
        XCTAssertThrowsError(try parsePolicy(#"host_executable(name = "/usr/bin/git", paths = ["/usr/bin/git"])"#)) { error in
            XCTAssertEqual(
                error as? ExecPolicyError,
                .invalidRule("host_executable name must be a bare executable name (got /usr/bin/git)")
            )
        }
        XCTAssertThrowsError(try parsePolicy(#"host_executable(name = "git", paths = ["/usr/bin/rg"])"#)) { error in
            XCTAssertEqual(
                error as? ExecPolicyError,
                .invalidRule("host_executable path `/usr/bin/rg` must have basename `git`")
            )
        }
    }

    func testHostExecutableLastDefinitionWins() throws {
        let parser = PolicyParser()
        try parser.parse("shared.rules", #"host_executable(name = "git", paths = ["/usr/bin/git"])"#)
        try parser.parse("user.rules", #"host_executable(name = "git", paths = ["/opt/homebrew/bin/git"])"#)
        let policy = parser.build()

        XCTAssertEqual(policy.hostExecutables()["git"], ["/opt/homebrew/bin/git"])
    }

    func testHostExecutableResolutionUsesBasenameRuleWhenAllowed() throws {
        let policy = try parsePolicy("""
        prefix_rule(pattern = ["git", "status"], decision = "prompt")
        host_executable(name = "git", paths = ["/usr/bin/git"])
        """)

        XCTAssertEqual(
            policy.check(
                tokens("/usr/bin/git", "status"),
                heuristicsFallback: allowAll,
                options: ExecPolicyMatchOptions(resolveHostExecutables: true)
            ),
            PolicyEvaluation(
                decision: .prompt,
                matchedRules: [.prefixRuleMatch(
                    matchedPrefix: tokens("git", "status"),
                    decision: .prompt,
                    resolvedProgram: "/usr/bin/git"
                )]
            )
        )
    }

    func testPrefixRuleExamplesHonorHostExecutableResolution() throws {
        _ = try parsePolicy("""
        prefix_rule(
            pattern = ["git", "status"],
            match = [["/usr/bin/git", "status"]],
            not_match = [["/opt/homebrew/bin/git", "status"]],
        )
        host_executable(name = "git", paths = ["/usr/bin/git"])
        """)
    }

    func testHostExecutableResolutionRespectsExplicitEmptyAllowlist() throws {
        let policy = try parsePolicy("""
        prefix_rule(pattern = ["git"], decision = "prompt")
        host_executable(name = "git", paths = [])
        """)

        XCTAssertEqual(
            policy.check(
                tokens("/usr/bin/git", "status"),
                heuristicsFallback: allowAll,
                options: ExecPolicyMatchOptions(resolveHostExecutables: true)
            ),
            PolicyEvaluation(
                decision: .allow,
                matchedRules: [.heuristicsRuleMatch(command: tokens("/usr/bin/git", "status"), decision: .allow)]
            )
        )
    }

    func testHostExecutableResolutionIgnoresPathNotInAllowlist() throws {
        let policy = try parsePolicy("""
        prefix_rule(pattern = ["git"], decision = "prompt")
        host_executable(name = "git", paths = ["/usr/bin/git"])
        """)

        XCTAssertEqual(
            policy.check(
                tokens("/opt/homebrew/bin/git", "status"),
                heuristicsFallback: allowAll,
                options: ExecPolicyMatchOptions(resolveHostExecutables: true)
            ),
            PolicyEvaluation(
                decision: .allow,
                matchedRules: [.heuristicsRuleMatch(command: tokens("/opt/homebrew/bin/git", "status"), decision: .allow)]
            )
        )
    }

    func testHostExecutableResolutionFallsBackWithoutMapping() throws {
        let policy = try parsePolicy(#"prefix_rule(pattern = ["git"], decision = "prompt")"#)

        XCTAssertEqual(
            policy.check(
                tokens("/usr/bin/git", "status"),
                heuristicsFallback: allowAll,
                options: ExecPolicyMatchOptions(resolveHostExecutables: true)
            ),
            PolicyEvaluation(
                decision: .prompt,
                matchedRules: [.prefixRuleMatch(
                    matchedPrefix: tokens("git"),
                    decision: .prompt,
                    resolvedProgram: "/usr/bin/git"
                )]
            )
        )
    }

    func testHostExecutableResolutionDoesNotOverrideExactMatch() throws {
        let policy = try parsePolicy("""
        prefix_rule(pattern = ["/usr/bin/git"], decision = "allow")
        prefix_rule(pattern = ["git"], decision = "prompt")
        host_executable(name = "git", paths = ["/usr/bin/git"])
        """)

        XCTAssertEqual(
            policy.check(
                tokens("/usr/bin/git", "status"),
                heuristicsFallback: allowAll,
                options: ExecPolicyMatchOptions(resolveHostExecutables: true)
            ),
            PolicyEvaluation(
                decision: .allow,
                matchedRules: [.prefixRuleMatch(matchedPrefix: tokens("/usr/bin/git"), decision: .allow)]
            )
        )
    }

    func testParsesMultiplePolicyFiles() throws {
        let parser = PolicyParser()
        try parser.parse("first.rules", """
        prefix_rule(
            pattern = ["git"],
            decision = "prompt",
        )
        """)
        try parser.parse("second.rules", """
        prefix_rule(
            pattern = ["git", "commit"],
            decision = "forbidden",
        )
        """)
        let policy = parser.build()

        XCTAssertEqual(
            policy.rules(for: "git"),
            [
                PrefixRule(pattern: PrefixPattern(first: "git", rest: []), decision: .prompt),
                PrefixRule(pattern: PrefixPattern(first: "git", rest: [.single("commit")]), decision: .forbidden)
            ]
        )
        XCTAssertEqual(
            policy.check(tokens("git", "commit", "-m", "hi"), heuristicsFallback: allowAll),
            PolicyEvaluation(
                decision: .forbidden,
                matchedRules: [
                    .prefixRuleMatch(matchedPrefix: tokens("git"), decision: .prompt),
                    .prefixRuleMatch(matchedPrefix: tokens("git", "commit"), decision: .forbidden)
                ]
            )
        )
    }

    func testOnlyFirstTokenAliasExpandsToMultipleRules() throws {
        let policy = try parsePolicy("""
        prefix_rule(
            pattern = [["bash", "sh"], ["-c", "-l"]],
        )
        """)

        XCTAssertEqual(
            policy.rules(for: "bash"),
            [
                PrefixRule(
                    pattern: PrefixPattern(first: "bash", rest: [.alts(["-c", "-l"])]),
                    decision: .allow
                )
            ]
        )
        XCTAssertEqual(
            policy.rules(for: "sh"),
            [
                PrefixRule(
                    pattern: PrefixPattern(first: "sh", rest: [.alts(["-c", "-l"])]),
                    decision: .allow
                )
            ]
        )
        XCTAssertEqual(
            policy.check(tokens("bash", "-c", "echo", "hi"), heuristicsFallback: allowAll),
            PolicyEvaluation(
                decision: .allow,
                matchedRules: [.prefixRuleMatch(matchedPrefix: tokens("bash", "-c"), decision: .allow)]
            )
        )
    }

    func testTailAliasesAreNotCartesianExpanded() throws {
        let policy = try parsePolicy("""
        prefix_rule(
            pattern = ["npm", ["i", "install"], ["--legacy-peer-deps", "--no-save"]],
        )
        """)

        XCTAssertEqual(
            policy.rules(for: "npm"),
            [
                PrefixRule(
                    pattern: PrefixPattern(
                        first: "npm",
                        rest: [
                            .alts(["i", "install"]),
                            .alts(["--legacy-peer-deps", "--no-save"])
                        ]
                    ),
                    decision: .allow
                )
            ]
        )
        XCTAssertEqual(
            policy.check(tokens("npm", "install", "--no-save", "leftpad"), heuristicsFallback: allowAll),
            PolicyEvaluation(
                decision: .allow,
                matchedRules: [.prefixRuleMatch(matchedPrefix: tokens("npm", "install", "--no-save"), decision: .allow)]
            )
        )
    }

    func testMatchAndNotMatchExamplesAreEnforced() throws {
        let policy = try parsePolicy("""
        prefix_rule(
            pattern = ["git", "status"],
            match = [["git", "status"], "git status"],
            not_match = [
                ["git", "--config", "color.status=always", "status"],
                "git --config color.status=always status",
            ],
        )
        """)

        XCTAssertEqual(
            policy.check(tokens("git", "--config", "color.status=always", "status"), heuristicsFallback: allowAll),
            PolicyEvaluation(
                decision: .allow,
                matchedRules: [
                    .heuristicsRuleMatch(
                        command: tokens("git", "--config", "color.status=always", "status"),
                        decision: .allow
                    )
                ]
            )
        )
    }

    func testParserIgnoresStarlarkCommentsAndStringMentions() throws {
        let policy = try parsePolicy("""
        # prefix_rule(pattern = ["rm"], decision = "forbidden")
        ignored_doc = "prefix_rule(pattern = [\\"rm\\"])"
        prefix_rule(
            pattern = ["git", "status"], # trailing comment
            decision = "prompt",
            match = [
                "git status", # comment inside arguments
            ],
        )
        """)

        XCTAssertEqual(
            policy.rules(for: "git"),
            [
                PrefixRule(
                    pattern: PrefixPattern(first: "git", rest: [.single("status")]),
                    decision: .prompt
                )
            ]
        )
        XCTAssertEqual(policy.rules(for: "rm"), [])
    }

    func testParserPreservesHashInsideStringLiterals() throws {
        let policy = try parsePolicy("""
        prefix_rule(
            pattern = ["echo", "#tag"],
            match = [["echo", "#tag"]],
            not_match = ["echo other"],
        )
        """)

        XCTAssertEqual(
            policy.check(tokens("echo", "#tag", "rest"), heuristicsFallback: allowAll),
            PolicyEvaluation(
                decision: .allow,
                matchedRules: [.prefixRuleMatch(matchedPrefix: tokens("echo", "#tag"), decision: .allow)]
            )
        )
    }

    func testParserResolvesTopLevelLiteralConstantsLikeRustStarlark() throws {
        let policy = try parsePolicy("""
        GIT = "git"
        STATUS_PATTERN = [GIT, "status"]
        PROMPT = "prompt"
        MATCHES = [[GIT, "status"], "git status"]
        GITHUB_HOST = "api.github.com"
        GIT_PATHS = ["/usr/bin/git", "/usr/bin/git"]

        prefix_rule(
            pattern = STATUS_PATTERN,
            decision = PROMPT,
            match = MATCHES,
        )
        network_rule(host = GITHUB_HOST, protocol = "https", decision = "allow")
        host_executable(name = GIT, paths = GIT_PATHS)
        """)

        XCTAssertEqual(
            policy.rules(for: "git"),
            [
                PrefixRule(
                    pattern: PrefixPattern(first: "git", rest: [.single("status")]),
                    decision: .prompt
                )
            ]
        )
        XCTAssertEqual(policy.networkRules(), [
            NetworkRule(host: "api.github.com", protocol: .https, decision: .allow)
        ])
        XCTAssertEqual(policy.hostExecutables(), ["git": ["/usr/bin/git"]])
    }

    func testParserResolvesLiteralConstantsInNestedPatternAlternatives() throws {
        let policy = try parsePolicy("""
        PACKAGE_MANAGERS = ["npm", "pnpm"]
        INSTALL = "install"
        LEGACY_FLAGS = ["--legacy-peer-deps", "--no-save"]
        pattern = [PACKAGE_MANAGERS, INSTALL, LEGACY_FLAGS]

        prefix_rule(pattern = pattern)
        """)

        XCTAssertEqual(
            policy.rules(for: "npm"),
            [
                PrefixRule(
                    pattern: PrefixPattern(
                        first: "npm",
                        rest: [.single("install"), .alts(["--legacy-peer-deps", "--no-save"])]
                    ),
                    decision: .allow
                )
            ]
        )
        XCTAssertEqual(
            policy.check(tokens("pnpm", "install", "--no-save"), heuristicsFallback: promptAll),
            PolicyEvaluation(
                decision: .allow,
                matchedRules: [.prefixRuleMatch(
                    matchedPrefix: tokens("pnpm", "install", "--no-save"),
                    decision: .allow
                )]
            )
        )
    }

    func testParserIgnoresUnsupportedUnusedAssignmentsLikeRustStarlarkAllows() throws {
        let policy = try parsePolicy("""
        UNUSED = [value for value in ["git"]]

        prefix_rule(pattern = ["git", "status"])
        """)

        XCTAssertEqual(
            policy.rules(for: "git"),
            [
                PrefixRule(
                    pattern: PrefixPattern(first: "git", rest: [.single("status")]),
                    decision: .allow
                )
            ]
        )
    }

    func testParserAcceptsRustStarlarkBuiltinPositionalArguments() throws {
        let policy = try parsePolicy("""
        prefix_rule(["git", "status"], "prompt", [["git", "status"]], ["git commit"], "inspect git state")
        network_rule("api.github.com", "https", "allow", "allow API access")
        host_executable("git", ["/usr/bin/git", "/usr/bin/git"])
        """)

        XCTAssertEqual(
            policy.rules(for: "git"),
            [
                PrefixRule(
                    pattern: PrefixPattern(first: "git", rest: [.single("status")]),
                    decision: .prompt,
                    justification: "inspect git state"
                )
            ]
        )
        XCTAssertEqual(policy.networkRules(), [
            NetworkRule(
                host: "api.github.com",
                protocol: .https,
                decision: .allow,
                justification: "allow API access"
            )
        ])
        XCTAssertEqual(policy.hostExecutables(), ["git": ["/usr/bin/git"]])
    }

    func testParserAcceptsRustStarlarkMixedPositionalAndNamedArguments() throws {
        let policy = try parsePolicy("""
        PREFIX = ["npm", "publish"]
        DECISION = "prompt"

        prefix_rule(PREFIX, decision = DECISION, justification = "review publish")
        network_rule("registry.npmjs.org", protocol = "https", decision = "deny")
        host_executable("npm", paths = ["/usr/bin/npm"])
        """)

        XCTAssertEqual(
            policy.rules(for: "npm"),
            [
                PrefixRule(
                    pattern: PrefixPattern(first: "npm", rest: [.single("publish")]),
                    decision: .prompt,
                    justification: "review publish"
                )
            ]
        )
        XCTAssertEqual(policy.networkRules(), [
            NetworkRule(host: "registry.npmjs.org", protocol: .https, decision: .forbidden)
        ])
        XCTAssertEqual(policy.hostExecutables(), ["npm": ["/usr/bin/npm"]])
    }

    func testParserRejectsRustStarlarkArgumentOrderingAndDuplicates() {
        XCTAssertThrowsError(try parsePolicy(#"prefix_rule(decision = "prompt", ["git"])"#)) { error in
            XCTAssertEqual(
                error as? ExecPolicyError,
                .invalidSyntax(#"positional argument follows keyword argument: ["git"]"#)
            )
        }

        XCTAssertThrowsError(try parsePolicy(#"prefix_rule(["git"], pattern = ["git", "status"])"#)) { error in
            XCTAssertEqual(error as? ExecPolicyError, .invalidSyntax("duplicate argument: pattern"))
        }

        XCTAssertThrowsError(
            try parsePolicy(#"host_executable("git", ["/usr/bin/git"], "extra")"#)
        ) { error in
            XCTAssertEqual(error as? ExecPolicyError, .invalidSyntax("too many positional arguments"))
        }
    }

    func testStrictestDecisionWinsAcrossMatches() throws {
        let policy = try parsePolicy("""
        prefix_rule(pattern = ["git"], decision = "prompt")
        prefix_rule(pattern = ["git", "commit"], decision = "forbidden")
        """)

        XCTAssertEqual(
            policy.check(tokens("git", "commit", "-m", "hi"), heuristicsFallback: allowAll),
            PolicyEvaluation(
                decision: .forbidden,
                matchedRules: [
                    .prefixRuleMatch(matchedPrefix: tokens("git"), decision: .prompt),
                    .prefixRuleMatch(matchedPrefix: tokens("git", "commit"), decision: .forbidden)
                ]
            )
        )
    }

    func testStrictestDecisionAcrossMultipleCommands() throws {
        let policy = try parsePolicy("""
        prefix_rule(pattern = ["git"], decision = "prompt")
        prefix_rule(pattern = ["git", "commit"], decision = "forbidden")
        """)

        XCTAssertEqual(
            policy.checkMultiple([
                tokens("git", "status"),
                tokens("git", "commit", "-m", "hi")
            ], heuristicsFallback: allowAll),
            PolicyEvaluation(
                decision: .forbidden,
                matchedRules: [
                    .prefixRuleMatch(matchedPrefix: tokens("git"), decision: .prompt),
                    .prefixRuleMatch(matchedPrefix: tokens("git"), decision: .prompt),
                    .prefixRuleMatch(matchedPrefix: tokens("git", "commit"), decision: .forbidden)
                ]
            )
        )
    }

    func testHeuristicsMatchIsReturnedWhenNoPolicyMatches() {
        let policy = ExecPolicy.empty()
        XCTAssertEqual(
            policy.check(tokens("python"), heuristicsFallback: promptAll),
            PolicyEvaluation(
                decision: .prompt,
                matchedRules: [.heuristicsRuleMatch(command: tokens("python"), decision: .prompt)]
            )
        )
    }

    func testExecApprovalRequirementPrefersExecPolicyMatch() throws {
        let manager = ExecPolicyManager(policy: try parsePolicy(#"prefix_rule(pattern=["rm"], decision="prompt")"#))

        XCTAssertEqual(
            manager.createExecApprovalRequirementForCommand(
                features: .withDefaults(),
                command: tokens("rm"),
                approvalPolicy: .onRequest,
                sandboxPolicy: .dangerFullAccess,
                sandboxPermissions: .useDefault
            ),
            .needsApproval(reason: ExecPolicyManager.promptReason, proposedExecPolicyAmendment: nil)
        )
    }

    func testExecApprovalRequirementRespectsApprovalPolicyNever() throws {
        let manager = ExecPolicyManager(policy: try parsePolicy(#"prefix_rule(pattern=["rm"], decision="prompt")"#))

        XCTAssertEqual(
            manager.createExecApprovalRequirementForCommand(
                features: .withDefaults(),
                command: tokens("rm"),
                approvalPolicy: .never,
                sandboxPolicy: .dangerFullAccess,
                sandboxPermissions: .useDefault
            ),
            .forbidden(reason: ExecPolicyManager.promptConflictReason)
        )
    }

    func testExecApprovalRequirementRespectsGranularApprovalFlags() throws {
        let manager = ExecPolicyManager(policy: try parsePolicy(#"prefix_rule(pattern=["rm"], decision="prompt")"#))

        XCTAssertEqual(
            manager.createExecApprovalRequirementForCommand(
                features: .withDefaults(),
                command: tokens("rm"),
                approvalPolicy: .granular(GranularApprovalConfig(
                    sandboxApproval: true,
                    rules: false,
                    mcpElicitations: true
                )),
                sandboxPolicy: .dangerFullAccess,
                sandboxPermissions: .useDefault
            ),
            .forbidden(reason: ExecPolicyManager.granularRulesApprovalConflictReason)
        )

        XCTAssertEqual(
            ExecPolicyManager().createExecApprovalRequirementForCommand(
                features: .withDefaults(),
                command: tokens("python3", "script.py"),
                approvalPolicy: .granular(GranularApprovalConfig(
                    sandboxApproval: false,
                    rules: true,
                    mcpElicitations: true
                )),
                sandboxPolicy: .readOnly,
                sandboxPermissions: .requireEscalated
            ),
            .forbidden(reason: ExecPolicyManager.granularSandboxApprovalConflictReason)
        )
    }

    func testExecApprovalRequirementFallsBackToHeuristics() {
        let command = tokens("cargo", "build")
        let manager = ExecPolicyManager()

        XCTAssertEqual(
            manager.createExecApprovalRequirementForCommand(
                features: .withDefaults(),
                command: command,
                approvalPolicy: .unlessTrusted,
                sandboxPolicy: .readOnly,
                sandboxPermissions: .useDefault
            ),
            .needsApproval(reason: nil, proposedExecPolicyAmendment: ExecPolicyAmendment(command: command))
        )
    }

    func testExecApprovalRequirementEvaluatesHeredocPrefixRulesWithoutAmendment() throws {
        let manager = ExecPolicyManager(policy: try parsePolicy(#"prefix_rule(pattern=["python3"], decision="allow")"#))
        let command = tokens("bash", "-lc", "python3 <<'PY'\nprint('hello')\nPY")

        XCTAssertEqual(
            manager.createExecApprovalRequirementForCommand(
                features: .withDefaults(),
                command: command,
                approvalPolicy: .onRequest,
                sandboxPolicy: .readOnly,
                sandboxPermissions: .useDefault
            ),
            .skip(bypassSandbox: true, proposedExecPolicyAmendment: nil)
        )
    }

    func testExecApprovalRequirementSuppressesHeredocFallbackAmendment() {
        let command = tokens("bash", "-lc", "python3 <<'PY'\nprint('hello')\nPY")

        XCTAssertEqual(
            ExecPolicyManager().createExecApprovalRequirementForCommand(
                features: .withDefaults(),
                command: command,
                approvalPolicy: .unlessTrusted,
                sandboxPolicy: .readOnly,
                sandboxPermissions: .useDefault
            ),
            .needsApproval(reason: nil, proposedExecPolicyAmendment: nil)
        )
    }

    func testHeuristicsApplyWhenOtherCommandsMatchPolicy() throws {
        let manager = ExecPolicyManager(policy: try parsePolicy(#"prefix_rule(pattern=["apple"], decision="allow")"#))
        let command = ["bash", "-lc", "apple | orange"]

        XCTAssertEqual(
            manager.createExecApprovalRequirementForCommand(
                features: .withDefaults(),
                command: command,
                approvalPolicy: .unlessTrusted,
                sandboxPolicy: .dangerFullAccess,
                sandboxPermissions: .useDefault
            ),
            .needsApproval(reason: nil, proposedExecPolicyAmendment: ExecPolicyAmendment(command: tokens("orange")))
        )
    }

    func testCollectPolicyFilesReturnsSortedRulesAndIgnoresOtherEntries() throws {
        let tempDir = try CoreTemporaryDirectory()
        let policyDir = tempDir.url.appendingPathComponent("rules", isDirectory: true)
        try FileManager.default.createDirectory(at: policyDir, withIntermediateDirectories: true)
        try "".write(to: policyDir.appendingPathComponent("z.rules"), atomically: true, encoding: .utf8)
        try "".write(to: policyDir.appendingPathComponent("a.rules"), atomically: true, encoding: .utf8)
        try "".write(to: policyDir.appendingPathComponent("ignore.txt"), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(
            at: policyDir.appendingPathComponent("nested.rules", isDirectory: true),
            withIntermediateDirectories: true
        )

        XCTAssertEqual(
            try ExecPolicyManager.collectPolicyFiles(in: policyDir).map(\.lastPathComponent),
            ["a.rules", "z.rules"]
        )
        XCTAssertEqual(
            try ExecPolicyManager.collectPolicyFiles(
                in: tempDir.url.appendingPathComponent("missing", isDirectory: true)
            ),
            []
        )
    }

    func testLoadExecPolicyLoadsRulesFromConfigLayerFolders() throws {
        let tempDir = try CoreTemporaryDirectory()
        let userFolder = tempDir.url.appendingPathComponent("user-codex", isDirectory: true)
        let projectDotCodex = tempDir.url
            .appendingPathComponent("repo", isDirectory: true)
            .appendingPathComponent(".codex", isDirectory: true)
        try FileManager.default.createDirectory(at: userFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: projectDotCodex, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: userFolder.appendingPathComponent("rules", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: projectDotCodex.appendingPathComponent("rules", isDirectory: true),
            withIntermediateDirectories: true
        )
        try #"prefix_rule(pattern=["rm"], decision="forbidden")"#.write(
            to: userFolder.appendingPathComponent("rules/user.rules"),
            atomically: true,
            encoding: .utf8
        )
        try #"prefix_rule(pattern=["ls"], decision="prompt")"#.write(
            to: projectDotCodex.appendingPathComponent("rules/project.rules"),
            atomically: true,
            encoding: .utf8
        )
        try #"prefix_rule(pattern=["pwd"], decision="forbidden")"#.write(
            to: projectDotCodex.appendingPathComponent("root.rules"),
            atomically: true,
            encoding: .utf8
        )

        let stack = try ConfigLayerStack(layers: [
            ConfigLayerEntry(
                name: .user(file: try AbsolutePath(absolutePath: userFolder.appendingPathComponent("config.toml").path)),
                config: .table([:])
            ),
            ConfigLayerEntry(
                name: .project(dotCodexFolder: try AbsolutePath(absolutePath: projectDotCodex.path)),
                config: .table([:])
            )
        ])
        let policy = try ExecPolicyManager.load(features: .withDefaults(), configStack: stack).current()

        XCTAssertEqual(
            policy.check(tokens("rm", "-rf", "/tmp"), heuristicsFallback: allowAll),
            PolicyEvaluation(
                decision: .forbidden,
                matchedRules: [.prefixRuleMatch(matchedPrefix: tokens("rm"), decision: .forbidden)]
            )
        )
        XCTAssertEqual(
            policy.check(tokens("ls"), heuristicsFallback: allowAll),
            PolicyEvaluation(
                decision: .prompt,
                matchedRules: [.prefixRuleMatch(matchedPrefix: tokens("ls"), decision: .prompt)]
            )
        )
        XCTAssertEqual(
            policy.check(tokens("pwd"), heuristicsFallback: allowAll),
            PolicyEvaluation(
                decision: .allow,
                matchedRules: [.heuristicsRuleMatch(command: tokens("pwd"), decision: .allow)]
            )
        )
    }

    func testAppendExecPolicyAmendmentUpdatesPolicyAndFile() throws {
        let tempDir = try CoreTemporaryDirectory()
        let prefix = tokens("echo", "hello")
        let manager = ExecPolicyManager()

        try manager.appendAmendmentAndUpdate(
            codexHome: tempDir.url,
            amendment: ExecPolicyAmendment(command: prefix)
        )

        XCTAssertEqual(
            manager.current().check(tokens("echo", "hello", "world"), heuristicsFallback: allowAll).decision,
            .allow
        )
        let contents = try String(
            contentsOf: ExecPolicyManager.defaultPolicyPath(codexHome: tempDir.url),
            encoding: .utf8
        )
        XCTAssertEqual(
            contents,
            #"prefix_rule(pattern=["echo", "hello"], decision="allow")"# + "\n"
        )
    }

    func testBlockingAppendAllowPrefixRuleDedupesExistingRuleLikeRust() throws {
        let tempDir = try CoreTemporaryDirectory()
        let policyPath = ExecPolicyManager.defaultPolicyPath(codexHome: tempDir.url)
        let prefix = tokens("python3")

        try ExecPolicyManager.blockingAppendAllowPrefixRule(policyPath: policyPath, prefix: prefix)
        try ExecPolicyManager.blockingAppendAllowPrefixRule(policyPath: policyPath, prefix: prefix)

        let contents = try String(contentsOf: policyPath, encoding: .utf8)
        XCTAssertEqual(
            contents,
            #"prefix_rule(pattern=["python3"], decision="allow")"# + "\n"
        )
    }

    func testBlockingAppendNetworkRuleMatchesRustSerialization() throws {
        let tempDir = try CoreTemporaryDirectory()
        let policyPath = ExecPolicyManager.defaultPolicyPath(codexHome: tempDir.url)

        try ExecPolicyManager.blockingAppendNetworkRule(
            policyPath: policyPath,
            host: "Api.GitHub.com",
            protocol: .https,
            decision: .allow,
            justification: "Allow https_connect access to api.github.com"
        )
        try ExecPolicyManager.blockingAppendNetworkRule(
            policyPath: policyPath,
            host: "api.github.com",
            protocol: .https,
            decision: .allow,
            justification: "Allow https_connect access to api.github.com"
        )
        try ExecPolicyManager.blockingAppendNetworkRule(
            policyPath: policyPath,
            host: "blocked.example.com",
            protocol: .http,
            decision: .forbidden,
            justification: nil
        )

        let contents = try String(contentsOf: policyPath, encoding: .utf8)
        XCTAssertEqual(
            contents,
            "network_rule(host=\"api.github.com\", protocol=\"https\", decision=\"allow\", justification=\"Allow https_connect access to api.github.com\")\n" +
                "network_rule(host=\"blocked.example.com\", protocol=\"http\", decision=\"deny\")\n"
        )
    }

    func testBlockingAppendNetworkRuleRejectsInvalidInputsLikeRust() throws {
        let tempDir = try CoreTemporaryDirectory()
        let policyPath = ExecPolicyManager.defaultPolicyPath(codexHome: tempDir.url)

        XCTAssertThrowsError(try ExecPolicyManager.blockingAppendNetworkRule(
            policyPath: policyPath,
            host: "*.example.com",
            protocol: .https,
            decision: .allow,
            justification: nil
        )) { error in
            XCTAssertEqual(
                String(describing: error),
                "invalid network rule: invalid rule: network_rule host must be a specific host; wildcards are not allowed"
            )
        }

        XCTAssertThrowsError(try ExecPolicyManager.blockingAppendNetworkRule(
            policyPath: policyPath,
            host: "api.github.com",
            protocol: .https,
            decision: .allow,
            justification: "   "
        )) { error in
            XCTAssertEqual(
                error as? ExecPolicyAmendError,
                .invalidNetworkRule("justification cannot be empty")
            )
        }
    }

    func testAppendExecPolicyAmendmentRejectsEmptyPrefix() throws {
        let tempDir = try CoreTemporaryDirectory()
        XCTAssertThrowsError(try ExecPolicyManager().appendAmendmentAndUpdate(
            codexHome: tempDir.url,
            amendment: ExecPolicyAmendment(command: [])
        )) { error in
            XCTAssertEqual(error as? ExecPolicyAmendError, .emptyPrefix)
        }
    }

    func testProposedExecPolicyAmendmentIsPresentWhenHeuristicsAllow() {
        let command = tokens("echo", "safe")
        XCTAssertEqual(
            ExecPolicyManager().createExecApprovalRequirementForCommand(
                features: .withDefaults(),
                command: command,
                approvalPolicy: .onRequest,
                sandboxPolicy: .readOnly,
                sandboxPermissions: .useDefault
            ),
            .skip(bypassSandbox: false, proposedExecPolicyAmendment: ExecPolicyAmendment(command: command))
        )
    }

    func testProposedExecPolicyAmendmentIsSuppressedWhenPolicyMatchesAllow() throws {
        let command = tokens("echo", "safe")
        let manager = ExecPolicyManager(policy: try parsePolicy(#"prefix_rule(pattern=["echo"], decision="allow")"#))

        XCTAssertEqual(
            manager.createExecApprovalRequirementForCommand(
                features: .withDefaults(),
                command: command,
                approvalPolicy: .onRequest,
                sandboxPolicy: .readOnly,
                sandboxPermissions: .useDefault
            ),
            .skip(bypassSandbox: true, proposedExecPolicyAmendment: nil)
        )
    }
}

private func parsePolicy(_ source: String) throws -> ExecPolicy {
    let parser = PolicyParser()
    try parser.parse("test.rules", source)
    return parser.build()
}

private func tokens(_ values: String...) -> [String] {
    values
}

private func allowAll(_: ArraySlice<String>) -> ExecPolicyDecision {
    .allow
}

private func promptAll(_: ArraySlice<String>) -> ExecPolicyDecision {
    .prompt
}

private final class CoreTemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
}
