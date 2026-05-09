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

    func testParserEvaluatesRustStarlarkStringAndListAdditionExpressions() throws {
        let policy = try parsePolicy("""
        GIT = "g" + "it"
        STATUS = ["st" + "atus"]
        PATTERN = [GIT] + STATUS
        EXAMPLES = [["git"] + STATUS] + ["git status"]
        HOST = "api." + "github.com"
        PATHS = ["/usr/bin/" + GIT] + ["/opt/homebrew/bin/" + GIT]

        prefix_rule(
            PATTERN,
            "prompt",
            match = EXAMPLES,
            not_match = [["git"] + ["commit"]],
            justification = "review " + "git status",
        )
        network_rule(HOST, "https", "allow", justification = "allow " + HOST)
        host_executable(GIT, PATHS)
        """)

        XCTAssertEqual(
            policy.rules(for: "git"),
            [
                PrefixRule(
                    pattern: PrefixPattern(first: "git", rest: [.single("status")]),
                    decision: .prompt,
                    justification: "review git status"
                )
            ]
        )
        XCTAssertEqual(policy.networkRules(), [
            NetworkRule(
                host: "api.github.com",
                protocol: .https,
                decision: .allow,
                justification: "allow api.github.com"
            )
        ])
        XCTAssertEqual(
            policy.hostExecutables(),
            ["git": ["/usr/bin/git", "/opt/homebrew/bin/git"]]
        )
    }

    func testParserEvaluatesRustStarlarkFStringsAndParenthesizedExpressions() throws {
        let policy = try parsePolicy("""
        TOOL = "git"
        SUBCOMMAND = "status"
        HOST_PREFIX = "api"
        DOMAIN = "github.com"
        GIT_PATH = f"/usr/bin/{TOOL}"
        PATTERN = ([TOOL] + [f"{SUBCOMMAND}"])

        prefix_rule(
            (PATTERN),
            "prompt",
            match = [(f"{TOOL} {SUBCOMMAND}")],
            not_match = [[TOOL] + ["commit"]],
            justification = f"inspect {{literal}} {TOOL} {SUBCOMMAND}",
        )
        network_rule(f"{HOST_PREFIX}.{DOMAIN}", "https", "allow")
        host_executable(TOOL, ([GIT_PATH]))
        """)

        XCTAssertEqual(
            policy.rules(for: "git"),
            [
                PrefixRule(
                    pattern: PrefixPattern(first: "git", rest: [.single("status")]),
                    decision: .prompt,
                    justification: "inspect {literal} git status"
                )
            ]
        )
        XCTAssertEqual(policy.networkRules(), [
            NetworkRule(host: "api.github.com", protocol: .https, decision: .allow)
        ])
        XCTAssertEqual(policy.hostExecutables(), ["git": ["/usr/bin/git"]])
    }

    func testParserEvaluatesRustStarlarkListComprehensions() throws {
        let policy = try parsePolicy("""
        TOOLS = ["git", "jj"]
        SUBCOMMANDS = ["status", "log"]
        HOST_PARTS = ["api", "github", "com"]
        PATH_TOOLS = ["git"]
        PATTERN = [[tool for tool in TOOLS], [subcommand for subcommand in SUBCOMMANDS]]
        EXAMPLES = [f"git {subcommand}" for subcommand in SUBCOMMANDS]
        GIT_PATHS = ["/usr/bin/" + tool for tool in PATH_TOOLS]
        DECISIONS = ["allow", "prompt"]

        prefix_rule(
            PATTERN,
            DECISIONS[-1],
            match = EXAMPLES,
            not_match = [[tool, "commit"] for tool in TOOLS],
            justification = "inspect generated rules",
        )
        network_rule([part for part in HOST_PARTS][0] + ".github.com", "https", "allow")
        host_executable("git", GIT_PATHS)
        """)

        XCTAssertEqual(
            policy.rules(for: "git"),
            [
                PrefixRule(
                    pattern: PrefixPattern(first: "git", rest: [.alts(["status", "log"])]),
                    decision: .prompt,
                    justification: "inspect generated rules"
                )
            ]
        )
        XCTAssertEqual(
            policy.rules(for: "jj"),
            [
                PrefixRule(
                    pattern: PrefixPattern(first: "jj", rest: [.alts(["status", "log"])]),
                    decision: .prompt,
                    justification: "inspect generated rules"
                )
            ]
        )
        XCTAssertEqual(policy.networkRules(), [
            NetworkRule(host: "api.github.com", protocol: .https, decision: .allow)
        ])
        XCTAssertEqual(policy.hostExecutables(), ["git": ["/usr/bin/git"]])
    }

    func testParserEvaluatesRustStarlarkListComprehensionFilters() throws {
        let policy = try parsePolicy("""
        COMMANDS = ["status", "diff", "commit", "show"]
        SAFE = ["status", "diff", "show"]
        TOOL = "git"

        FILTERED = [command for command in COMMANDS if command in SAFE and command != "show"]
        EXAMPLES = [f"{TOOL} {command}" for command in FILTERED if command.startswith("s")]

        for command in FILTERED:
            prefix_rule(
                [TOOL, command],
                "prompt",
                match = [[TOOL, command]],
                justification = "inspect " + command,
            )

        if len(EXAMPLES) == 1:
            host_executable(TOOL, ["/usr/bin/" + TOOL])

        if len([command for command in COMMANDS if command not in SAFE]) == 1:
            network_rule("api.github.com", "https", "allow")
        """)

        XCTAssertEqual(policy.rules(for: "git"), [
            PrefixRule(
                pattern: PrefixPattern(first: "git", rest: [.single("status")]),
                decision: .prompt,
                justification: "inspect status"
            ),
            PrefixRule(
                pattern: PrefixPattern(first: "git", rest: [.single("diff")]),
                decision: .prompt,
                justification: "inspect diff"
            )
        ])
        XCTAssertEqual(policy.networkRules(), [
            NetworkRule(host: "api.github.com", protocol: .https, decision: .allow)
        ])
        XCTAssertEqual(policy.hostExecutables(), ["git": ["/usr/bin/git"]])
    }

    func testParserEvaluatesRustStarlarkLoopTargetDestructuring() throws {
        let policy = try parsePolicy("""
        COMMANDS = [["git", "status"], ["jj", "log"]]
        HOSTS = [["github", "api.github.com"], ["npm", "registry.npmjs.org"]]
        PATHS = [["git", "/usr/bin/git"]]
        EXAMPLES = [f"{tool} {subcommand}" for tool, subcommand in COMMANDS if tool == "git"]
        SELECTED = [tool for [tool, subcommand] in COMMANDS if subcommand != "log"]

        for tool, subcommand in COMMANDS:
            prefix_rule(
                [tool, subcommand],
                "prompt" if tool == "git" else "allow",
                match = [f"{tool} {subcommand}"],
                not_match = EXAMPLES if tool == "jj" else [],
                justification = f"inspect {tool} {subcommand}",
            )

        for name, host in HOSTS:
            if name == "github":
                network_rule(host, "https", "allow")

        for [tool, path] in PATHS:
            if tool in SELECTED:
                host_executable(tool, [path])
        """)

        XCTAssertEqual(policy.rules(for: "git"), [
            PrefixRule(
                pattern: PrefixPattern(first: "git", rest: [.single("status")]),
                decision: .prompt,
                justification: "inspect git status"
            )
        ])
        XCTAssertEqual(policy.rules(for: "jj"), [
            PrefixRule(
                pattern: PrefixPattern(first: "jj", rest: [.single("log")]),
                decision: .allow,
                justification: "inspect jj log"
            )
        ])
        XCTAssertEqual(policy.networkRules(), [
            NetworkRule(host: "api.github.com", protocol: .https, decision: .allow)
        ])
        XCTAssertEqual(policy.hostExecutables(), ["git": ["/usr/bin/git"]])
    }

    func testParserEvaluatesRustStarlarkEnumerateAndZip() throws {
        let policy = try parsePolicy("""
        TOOLS = ["git", "jj", "npm"]
        COMMANDS = ["status", "log"]
        DECISIONS = ["prompt", "allow"]
        HOSTS = ["api.github.com", "registry.npmjs.org", "ignored.example.com"]
        PATHS = ["/usr/bin/git", "/usr/bin/jj"]

        for index, pair in enumerate(zip(TOOLS, COMMANDS, DECISIONS), 1):
            tool, command, decision = pair
            prefix_rule(
                [tool, command],
                decision,
                match = [f"{tool} {command}"],
                justification = f"pair {index}",
            )

        for tool, path in zip(TOOLS, PATHS):
            host_executable(tool, [path])

        for host, char in zip(HOSTS, "ab"):
            if char == "a":
                network_rule(host, "https", "allow")
        """)

        XCTAssertEqual(policy.rules(for: "git"), [
            PrefixRule(
                pattern: PrefixPattern(first: "git", rest: [.single("status")]),
                decision: .prompt,
                justification: "pair 1"
            )
        ])
        XCTAssertEqual(policy.rules(for: "jj"), [
            PrefixRule(
                pattern: PrefixPattern(first: "jj", rest: [.single("log")]),
                decision: .allow,
                justification: "pair 2"
            )
        ])
        XCTAssertEqual(policy.rules(for: "npm"), [])
        XCTAssertEqual(policy.networkRules(), [
            NetworkRule(host: "api.github.com", protocol: .https, decision: .allow)
        ])
        XCTAssertEqual(policy.hostExecutables(), [
            "git": ["/usr/bin/git"],
            "jj": ["/usr/bin/jj"]
        ])
    }

    func testParserEvaluatesRustStarlarkRangeAndComputedIndexes() throws {
        let policy = try parsePolicy("""
        TOOL = "git"
        COMMANDS = ["status", "diff", "log", "show"]
        SELECTED = [COMMANDS[index] for index in range(len(COMMANDS)) if index != 1]
        LAST_INDEX = len(COMMANDS) - 1
        STEP = 1 + 1
        REVERSED = [COMMANDS[index] for index in range(LAST_INDEX, 0, -(STEP * 1))]
        EVEN_COMMANDS = [COMMANDS[index] for index in range(len(COMMANDS)) if index % 2 == 0]
        HALF = len(COMMANDS) // 2

        for index in range(0, len(SELECTED), HALF):
            prefix_rule(
                [TOOL, SELECTED[index]],
                "prompt",
                match = [f"{TOOL} {SELECTED[index]}"],
                justification = "range index " + SELECTED[index],
            )

        if COMMANDS[len(COMMANDS) - 1] == "show":
            network_rule("api.github.com", "https", "allow")

        if REVERSED[0] == "show" and REVERSED[1] == "diff":
            host_executable(TOOL, ["/usr/bin/" + TOOL])

        if EVEN_COMMANDS[1] == "log" and len(COMMANDS) / 2 == 2.0:
            prefix_rule([TOOL, "math"], "allow")
        """)

        XCTAssertEqual(policy.rules(for: "git"), [
            PrefixRule(
                pattern: PrefixPattern(first: "git", rest: [.single("status")]),
                decision: .prompt,
                justification: "range index status"
            ),
            PrefixRule(
                pattern: PrefixPattern(first: "git", rest: [.single("show")]),
                decision: .prompt,
                justification: "range index show"
            ),
            PrefixRule(
                pattern: PrefixPattern(first: "git", rest: [.single("math")]),
                decision: .allow
            )
        ])
        XCTAssertEqual(policy.networkRules(), [
            NetworkRule(host: "api.github.com", protocol: .https, decision: .allow)
        ])
        XCTAssertEqual(policy.hostExecutables(), ["git": ["/usr/bin/git"]])
    }

    func testParserEvaluatesRustStarlarkSequenceRepetitionAndFloorModulo() throws {
        let policy = try parsePolicy("""
        TOOL = "g" + ("i" * 1) + ("t" * (2 - 1))
        COMMANDS = (["status"] * 2) + ["diff"]
        EMPTY = ["ignored"] * -1
        INDEX = -1 % len(COMMANDS)
        FLOOR = -3 // 2
        HOST = ".".join(["api"] + (["github"] * 1) + ["com"])
        PATH = "/usr/bin/" + (1 * TOOL)

        if FLOOR == -2 and len(EMPTY) == 0:
            prefix_rule(
                [TOOL, COMMANDS[INDEX]],
                "prompt",
                match = [(TOOL + " ") * 1 + COMMANDS[INDEX]],
                justification = "repeat " + COMMANDS[INDEX],
            )

        if 2 * "j" == "jj" and len(2 * ["status"]) == 2:
            prefix_rule([2 * "j", (["status"] * 2)[1]], "allow")

        network_rule(HOST, "https", "allow")
        host_executable(TOOL, [PATH])
        """)

        XCTAssertEqual(policy.rules(for: "git"), [
            PrefixRule(
                pattern: PrefixPattern(first: "git", rest: [.single("diff")]),
                decision: .prompt,
                justification: "repeat diff"
            )
        ])
        XCTAssertEqual(policy.rules(for: "jj"), [
            PrefixRule(
                pattern: PrefixPattern(first: "jj", rest: [.single("status")]),
                decision: .allow
            )
        ])
        XCTAssertEqual(policy.networkRules(), [
            NetworkRule(host: "api.github.com", protocol: .https, decision: .allow)
        ])
        XCTAssertEqual(policy.hostExecutables(), ["git": ["/usr/bin/git"]])
    }

    func testParserEvaluatesRustStarlarkTopLevelForLoops() throws {
        let policy = try parsePolicy("""
        TOOLS = ["git", "jj"]
        HOSTS = ["api.github.com", "registry.npmjs.org"]
        DECISIONS = ["prompt", "forbidden"]
        PATH_TOOLS = ["git"]

        for tool in TOOLS:
            prefix_rule(
                [tool, "status"],
                DECISIONS[0],
                match = [f"{tool} status"],
                not_match = [[tool, "commit"]],
                justification = f"inspect {tool}",
            )

        for host in HOSTS:
            network_rule(host, "https", "allow", justification = "allow " + host)

        for tool in PATH_TOOLS:
            PATH = "/usr/bin/" + tool
            host_executable(tool, [PATH])
        prefix_rule([tool, "fallback"], DECISIONS[-1])
        """)

        XCTAssertEqual(
            policy.rules(for: "git"),
            [
                PrefixRule(
                    pattern: PrefixPattern(first: "git", rest: [.single("status")]),
                    decision: .prompt,
                    justification: "inspect git"
                ),
                PrefixRule(
                    pattern: PrefixPattern(first: "git", rest: [.single("fallback")]),
                    decision: .forbidden
                )
            ]
        )
        XCTAssertEqual(
            policy.rules(for: "jj"),
            [
                PrefixRule(
                    pattern: PrefixPattern(first: "jj", rest: [.single("status")]),
                    decision: .prompt,
                    justification: "inspect jj"
                )
            ]
        )
        XCTAssertEqual(policy.networkRules(), [
            NetworkRule(
                host: "api.github.com",
                protocol: .https,
                decision: .allow,
                justification: "allow api.github.com"
            ),
            NetworkRule(
                host: "registry.npmjs.org",
                protocol: .https,
                decision: .allow,
                justification: "allow registry.npmjs.org"
            )
        ])
        XCTAssertEqual(policy.hostExecutables(), ["git": ["/usr/bin/git"]])
    }

    func testParserEvaluatesRustStarlarkTopLevelConditionals() throws {
        let policy = try parsePolicy("""
        ENABLE_STATUS = True
        ENABLE_DANGEROUS = False
        TOOLS = ["git", "jj"]
        SELECTED = "git"

        if ENABLE_STATUS:
            prefix_rule(["git", "status"], "prompt", justification = "inspect status")
        else:
            prefix_rule(["git", "ignored"], "forbidden")

        if "jj" in TOOLS:
            prefix_rule(["jj", "status"], "allow")

        if SELECTED == "git":
            network_rule("api.github.com", "https", "allow")

        if SELECTED != "jj":
            prefix_rule(["git", "diff"], "prompt")

        if not ENABLE_DANGEROUS:
            host_executable("git", ["/usr/bin/git"])

        if ENABLE_DANGEROUS:
            prefix_rule(["rm"], "forbidden")
        else:
            prefix_rule(["echo", "safe"], "allow")
        """)

        XCTAssertEqual(
            policy.rules(for: "git"),
            [
                PrefixRule(
                    pattern: PrefixPattern(first: "git", rest: [.single("status")]),
                    decision: .prompt,
                    justification: "inspect status"
                ),
                PrefixRule(
                    pattern: PrefixPattern(first: "git", rest: [.single("diff")]),
                    decision: .prompt
                )
            ]
        )
        XCTAssertEqual(policy.rules(for: "jj"), [
            PrefixRule(pattern: PrefixPattern(first: "jj", rest: [.single("status")]), decision: .allow)
        ])
        XCTAssertEqual(policy.rules(for: "rm"), [])
        XCTAssertEqual(policy.rules(for: "echo"), [
            PrefixRule(pattern: PrefixPattern(first: "echo", rest: [.single("safe")]), decision: .allow)
        ])
        XCTAssertEqual(policy.networkRules(), [
            NetworkRule(host: "api.github.com", protocol: .https, decision: .allow)
        ])
        XCTAssertEqual(policy.hostExecutables(), ["git": ["/usr/bin/git"]])
    }

    func testParserEvaluatesRustStarlarkElifAndBooleanConditions() throws {
        let policy = try parsePolicy("""
        MODE = "publish"
        TOOL = "npm"
        FLAGS = ["--dry-run", "--tag"]
        ENABLE_NETWORK = True
        ALLOW_INSTALL = False

        if MODE == "status":
            prefix_rule([TOOL, "status"], "allow")
        elif MODE == "publish" and TOOL == "npm":
            prefix_rule([TOOL, "publish"], "prompt", justification = "review npm publish")
        elif MODE == "publish":
            prefix_rule([TOOL, "fallback"], "forbidden")
        else:
            prefix_rule([TOOL, "ignored"], "forbidden")

        if ("--dry-run" in FLAGS and ENABLE_NETWORK) or ALLOW_INSTALL:
            network_rule("registry.npmjs.org", "https", "allow")

        if not (ALLOW_INSTALL or MODE == "install"):
            host_executable(TOOL, ["/usr/bin/npm"])
        """)

        XCTAssertEqual(policy.rules(for: "npm"), [
            PrefixRule(
                pattern: PrefixPattern(first: "npm", rest: [.single("publish")]),
                decision: .prompt,
                justification: "review npm publish"
            )
        ])
        XCTAssertEqual(policy.networkRules(), [
            NetworkRule(host: "registry.npmjs.org", protocol: .https, decision: .allow)
        ])
        XCTAssertEqual(policy.hostExecutables(), ["npm": ["/usr/bin/npm"]])
    }

    func testParserEvaluatesRustStarlarkHelperFunctions() throws {
        let policy = try parsePolicy("""
        def pattern(tool, subcommand):
            return [tool, subcommand]

        def host(first, second, third):
            return first + "." + second + "." + third

        def path(tool):
            return "/usr/bin/" + tool

        TOOL = "git"
        SUBCOMMANDS = ["status", "diff"]
        HOST_PARTS = ["api", "github", "com"]

        for subcommand in SUBCOMMANDS:
            prefix_rule(
                pattern(TOOL, subcommand),
                "prompt",
                match = [f"{TOOL} {subcommand}"],
                justification = "inspect " + subcommand,
            )

        if host(HOST_PARTS[0], HOST_PARTS[1], HOST_PARTS[2]) == "api.github.com":
            network_rule(host(HOST_PARTS[0], HOST_PARTS[1], HOST_PARTS[2]), "https", "allow")

        host_executable(TOOL, [path(TOOL)])
        """)

        XCTAssertEqual(policy.rules(for: "git"), [
            PrefixRule(
                pattern: PrefixPattern(first: "git", rest: [.single("status")]),
                decision: .prompt,
                justification: "inspect status"
            ),
            PrefixRule(
                pattern: PrefixPattern(first: "git", rest: [.single("diff")]),
                decision: .prompt,
                justification: "inspect diff"
            )
        ])
        XCTAssertEqual(policy.networkRules(), [
            NetworkRule(host: "api.github.com", protocol: .https, decision: .allow)
        ])
        XCTAssertEqual(policy.hostExecutables(), ["git": ["/usr/bin/git"]])
    }

    func testParserEvaluatesRustStarlarkDictLiteralsAndStringIndexing() throws {
        let policy = try parsePolicy("""
        TOOL = "git"
        SETTINGS = {
            TOOL: {
                "pattern": [TOOL, "status"],
                "match": [TOOL, "status"],
                "host": "api.github.com",
                "path": "/usr/bin/git",
            },
            "npm": {
                "pattern": ["npm", "publish"],
            },
        }

        def setting(tool, name):
            return SETTINGS[tool][name]

        if TOOL in SETTINGS and "path" in SETTINGS[TOOL]:
            prefix_rule(
                setting(TOOL, "pattern"),
                "prompt",
                match = [setting(TOOL, "match")],
                justification = "inspect " + TOOL,
            )
            network_rule(setting(TOOL, "host"), "https", "allow")
            host_executable(TOOL, [setting(TOOL, "path")])
        """)

        XCTAssertEqual(policy.rules(for: "git"), [
            PrefixRule(
                pattern: PrefixPattern(first: "git", rest: [.single("status")]),
                decision: .prompt,
                justification: "inspect git"
            )
        ])
        XCTAssertEqual(policy.networkRules(), [
            NetworkRule(host: "api.github.com", protocol: .https, decision: .allow)
        ])
        XCTAssertEqual(policy.hostExecutables(), ["git": ["/usr/bin/git"]])
    }

    func testParserEvaluatesRustStarlarkLengthComparisonsAndMembership() throws {
        let policy = try parsePolicy("""
        TOOL = "git"
        COMMANDS = ["status", "diff", "log"]
        HOSTS = {"github": "api.github.com", "npm": "registry.npmjs.org"}
        MESSAGE = "inspect git history"

        if len(COMMANDS) >= 3 and len(HOSTS) == 2 and "git" in MESSAGE:
            prefix_rule([TOOL, COMMANDS[0]], "allow")

        if len(COMMANDS) > 4:
            prefix_rule([TOOL, "too-many"], "forbidden")
        elif "missing" not in HOSTS and len(TOOL) < 4 and "svn" not in MESSAGE:
            prefix_rule([TOOL, COMMANDS[-1]], "prompt", justification = MESSAGE)

        if len(COMMANDS) <= 3 and "github" in HOSTS:
            network_rule(HOSTS["github"], "https", "allow")
        """)

        XCTAssertEqual(policy.rules(for: "git"), [
            PrefixRule(
                pattern: PrefixPattern(first: "git", rest: [.single("status")]),
                decision: .allow
            ),
            PrefixRule(
                pattern: PrefixPattern(first: "git", rest: [.single("log")]),
                decision: .prompt,
                justification: "inspect git history"
            )
        ])
        XCTAssertEqual(policy.networkRules(), [
            NetworkRule(host: "api.github.com", protocol: .https, decision: .allow)
        ])
    }

    func testParserEvaluatesRustStarlarkStringMethods() throws {
        let policy = try parsePolicy("""
        TOOL = "git"
        SUBCOMMAND = "status"
        HOST_PARTS = ["api", "github", "com"]
        PATH_PARTS = ["", "usr", "bin", TOOL]
        HOST = ".".join(HOST_PARTS)
        PATH = "/".join(PATH_PARTS)

        def command(tool, subcommand):
            return " ".join([tool, subcommand])

        if HOST.startswith("api.") and HOST.endswith(".com") and command(TOOL, SUBCOMMAND).startswith("git "):
            prefix_rule(
                [TOOL, SUBCOMMAND],
                "prompt",
                match = [command(TOOL, SUBCOMMAND)],
                justification = "inspect " + command(TOOL, SUBCOMMAND),
            )
            network_rule(HOST, "https", "allow")
            host_executable(TOOL, [PATH])
        """)

        XCTAssertEqual(policy.rules(for: "git"), [
            PrefixRule(
                pattern: PrefixPattern(first: "git", rest: [.single("status")]),
                decision: .prompt,
                justification: "inspect git status"
            )
        ])
        XCTAssertEqual(policy.networkRules(), [
            NetworkRule(host: "api.github.com", protocol: .https, decision: .allow)
        ])
        XCTAssertEqual(policy.hostExecutables(), ["git": ["/usr/bin/git"]])
    }

    func testParserEvaluatesRustStarlarkStringNormalizationMethods() throws {
        let policy = try parsePolicy("""
        RAW_TOOL = " Git "
        TOOL = RAW_TOOL.strip().lower()
        COMMANDS = "status,diff,log".split(",")
        HOST_PARTS = "api.github.com".split(".")
        PATH = ("//usr/bin/" + TOOL + "//").strip("/")
        UPPER_TOOL = TOOL.upper()
        PREFIX = "xxstatus".lstrip("x")
        SUFFIX = "log!!".rstrip("!")

        def normalize(raw):
            return raw.strip().lower()

        for command in COMMANDS:
            if command == PREFIX or command == SUFFIX:
                prefix_rule(
                    [TOOL, command],
                    "prompt",
                    match = [f"{TOOL} {command}"],
                    justification = "inspect " + normalize(f" {UPPER_TOOL} {command} "),
                )

        if ".".join(HOST_PARTS) == "api.github.com":
            network_rule(".".join(HOST_PARTS), "https", "allow")

        if PATH == "usr/bin/git":
            host_executable(TOOL, ["/" + PATH])
        """)

        XCTAssertEqual(policy.rules(for: "git"), [
            PrefixRule(
                pattern: PrefixPattern(first: "git", rest: [.single("status")]),
                decision: .prompt,
                justification: "inspect git status"
            ),
            PrefixRule(
                pattern: PrefixPattern(first: "git", rest: [.single("log")]),
                decision: .prompt,
                justification: "inspect git log"
            )
        ])
        XCTAssertEqual(policy.networkRules(), [
            NetworkRule(host: "api.github.com", protocol: .https, decision: .allow)
        ])
        XCTAssertEqual(policy.hostExecutables(), ["git": ["/usr/bin/git"]])
    }

    func testParserEvaluatesRustStarlarkConditionalExpressions() throws {
        let policy = try parsePolicy("""
        USE_GIT = False
        TOOL = "jj" if USE_GIT else "git"
        RAW_COMMANDS = ["status", "publish"]
        COMMANDS = [command if command.startswith("s") else "diff" for command in RAW_COMMANDS]
        DECISION = "prompt" if len(COMMANDS) == 2 and TOOL == "git" else "allow"
        PUBLIC_HOST = True if DECISION == "prompt" else False
        MATCH = f"{TOOL} {COMMANDS[0]}" if DECISION == "prompt" else "jj log"

        def path(tool):
            return "/usr/bin/" + (tool if tool == "git" else "jj")

        def host(public):
            return "api.github.com" if public else "blocked.example.com"

        prefix_rule(
            [TOOL, COMMANDS[0] if TOOL == "git" else "log"],
            DECISION,
            match = [MATCH],
            justification = "inspect " + ("git state" if TOOL == "git" else "jj state"),
        )
        network_rule(host(PUBLIC_HOST), "https", "allow")
        host_executable(TOOL, [path(TOOL)])
        """)

        XCTAssertEqual(policy.rules(for: "git"), [
            PrefixRule(
                pattern: PrefixPattern(first: "git", rest: [.single("status")]),
                decision: .prompt,
                justification: "inspect git state"
            )
        ])
        XCTAssertEqual(policy.networkRules(), [
            NetworkRule(host: "api.github.com", protocol: .https, decision: .allow)
        ])
        XCTAssertEqual(policy.hostExecutables(), ["git": ["/usr/bin/git"]])
    }

    func testParserEvaluatesRustStarlarkBooleanExpressionsAsLiterals() throws {
        let policy = try parsePolicy("""
        TOOL = "git"
        COMMANDS = ["status", "diff", "log"]
        HOSTS = {"github": "api.github.com"}
        HAS_STATUS = COMMANDS[0] == "status"
        HAS_GITHUB = "github" in HOSTS
        SHOULD_PROMPT = HAS_STATUS and HAS_GITHUB and len(COMMANDS) >= 3
        SHOULD_BLOCK = not ("commit" in COMMANDS) and TOOL != "jj"
        MATCH = f"{TOOL} {COMMANDS[0]}" if SHOULD_PROMPT else "jj status"

        def host(public):
            return "api.github.com" if public else "blocked.example.com"

        if SHOULD_PROMPT:
            prefix_rule(
                [TOOL, COMMANDS[0]],
                "prompt",
                match = [MATCH],
                justification = "bool literal prompt",
            )

        if SHOULD_BLOCK:
            prefix_rule([TOOL, "commit"], "forbidden")

        network_rule(host(SHOULD_PROMPT or False), "https", "allow")
        host_executable(TOOL, ["/usr/bin/" + TOOL] if SHOULD_BLOCK else [])
        """)

        XCTAssertEqual(policy.rules(for: "git"), [
            PrefixRule(
                pattern: PrefixPattern(first: "git", rest: [.single("status")]),
                decision: .prompt,
                justification: "bool literal prompt"
            ),
            PrefixRule(
                pattern: PrefixPattern(first: "git", rest: [.single("commit")]),
                decision: .forbidden
            )
        ])
        XCTAssertEqual(policy.networkRules(), [
            NetworkRule(host: "api.github.com", protocol: .https, decision: .allow)
        ])
        XCTAssertEqual(policy.hostExecutables(), ["git": ["/usr/bin/git"]])
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
