import CodexCore
import XCTest

final class ExecPolicyCheckTests: XCTestCase {
    func testFormatMatchesJSONUsesRustShape() throws {
        let output = try ExecPolicyCheck.formatMatchesJSON(matchedRules: [
            .prefixRuleMatch(matchedPrefix: ["git", "push"], decision: .forbidden)
        ])

        XCTAssertEqual(
            try JSONObjectFromString(output),
            [
                "decision": "forbidden",
                "matchedRules": [
                    [
                        "prefixRuleMatch": [
                            "matchedPrefix": ["git", "push"],
                            "decision": "forbidden"
                        ]
                    ]
                ]
            ]
        )
    }

    func testFormatMatchesJSONIncludesOptionalPrefixMatchFields() throws {
        let output = try ExecPolicyCheck.formatMatchesJSON(matchedRules: [
            .prefixRuleMatch(
                matchedPrefix: ["rm"],
                decision: .forbidden,
                resolvedProgram: "/bin/rm",
                justification: "destructive command"
            )
        ])

        XCTAssertEqual(
            try JSONObjectFromString(output),
            [
                "decision": "forbidden",
                "matchedRules": [
                    [
                        "prefixRuleMatch": [
                            "matchedPrefix": ["rm"],
                            "decision": "forbidden",
                            "resolvedProgram": "/bin/rm",
                            "justification": "destructive command"
                        ]
                    ]
                ]
            ]
        )
    }

    func testFormatMatchesJSONOmitsDecisionWhenNoRulesMatch() throws {
        let output = try ExecPolicyCheck.formatMatchesJSON(matchedRules: [])

        XCTAssertEqual(
            try JSONObjectFromString(output),
            [
                "matchedRules": []
            ]
        )
    }

    func testRunLoadsPolicyFilesAndChecksCommand() throws {
        let tempDir = try CoreExecPolicyCheckTemporaryDirectory()
        let policyPath = tempDir.url.appendingPathComponent("policy.rules")
        try """
        prefix_rule(
            pattern = ["git", "push"],
            decision = "forbidden",
        )
        """.write(to: policyPath, atomically: true, encoding: .utf8)

        let output = try ExecPolicyCheck.run(
            rulePaths: [policyPath],
            command: ["git", "push", "origin", "main"]
        )

        XCTAssertEqual(
            try JSONObjectFromString(output),
            [
                "decision": "forbidden",
                "matchedRules": [
                    [
                        "prefixRuleMatch": [
                            "matchedPrefix": ["git", "push"],
                            "decision": "forbidden"
                        ]
                    ]
                ]
            ]
        )
    }

    func testPrettyOutputIsIndentedJSON() throws {
        let output = try ExecPolicyCheck.formatMatchesJSON(
            matchedRules: [.prefixRuleMatch(matchedPrefix: ["git"], decision: .prompt)],
            pretty: true
        )

        XCTAssertTrue(output.contains("\n"))
        XCTAssertTrue(output.contains(#""matchedRules""#))
        XCTAssertEqual(try JSONObjectFromString(output)["decision"] as? String, "prompt")
    }
}

private func JSONObjectFromString(_ source: String) throws -> NSDictionary {
    try JSONSerialization.jsonObject(with: Data(source.utf8)) as? NSDictionary ?? [:]
}

private final class CoreExecPolicyCheckTemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
}
