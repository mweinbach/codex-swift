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

    func testAppendExecPolicyAmendmentRejectsEmptyPrefix() throws {
        let tempDir = try CoreTemporaryDirectory()
        XCTAssertThrowsError(try ExecPolicyManager().appendAmendmentAndUpdate(
            codexHome: tempDir.url,
            amendment: ExecPolicyAmendment(command: [])
        )) { error in
            XCTAssertEqual(error as? ExecPolicyAmendError, .emptyPrefix)
        }
    }

    func testProposedExecPolicyAmendmentIsDisabledWhenFeatureDisabled() {
        var features = FeatureStates.withDefaults()
        features.set(.execPolicy, enabled: false)

        XCTAssertEqual(
            ExecPolicyManager().createExecApprovalRequirementForCommand(
                features: features,
                command: tokens("cargo", "build"),
                approvalPolicy: .unlessTrusted,
                sandboxPolicy: .readOnly,
                sandboxPermissions: .useDefault
            ),
            .needsApproval(reason: nil, proposedExecPolicyAmendment: nil)
        )
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
