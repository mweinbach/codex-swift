@testable import CodexCore
import XCTest

final class MemoryWritePhaseOneTests: XCTestCase {
    func testOutputSchemaRequiresRolloutSlugAndKeepsItNullableLikeRust() throws {
        try XCTAssertJSONObjectEqual(memoryStageOneOutputSchema(), [
            "type": "object",
            "properties": [
                "rollout_summary": ["type": "string"],
                "rollout_slug": ["type": ["string", "null"]],
                "raw_memory": ["type": "string"]
            ],
            "required": ["rollout_summary", "rollout_slug", "raw_memory"],
            "additionalProperties": false
        ])
    }

    func testStageOneOutputDecodesMissingSlugAsNilAndRejectsUnknownFields() throws {
        let output = try JSONDecoder().decode(MemoryStageOneOutput.self, from: Data(#"""
        {
          "raw_memory": "details",
          "rollout_summary": "summary"
        }
        """#.utf8))
        XCTAssertEqual(output, MemoryStageOneOutput(rawMemory: "details", rolloutSummary: "summary", rolloutSlug: nil))

        XCTAssertThrowsError(try JSONDecoder().decode(MemoryStageOneOutput.self, from: Data(#"""
        {
          "raw_memory": "details",
          "rollout_summary": "summary",
          "rollout_slug": null,
          "extra": true
        }
        """#.utf8)))
    }

    func testClassifiesMemoryExcludedFragmentsLikeRust() {
        XCTAssertTrue(isMemoryExcludedContextualUserFragment(.inputText(text: """
        # AGENTS.md instructions for /repo

        <INSTRUCTIONS>
        Follow project rules.
        </INSTRUCTIONS>
        """)))
        XCTAssertTrue(isMemoryExcludedContextualUserFragment(.inputText(text: """
        <SKILL>
        <name>example</name>
        </skill>
        """)))
        XCTAssertFalse(isMemoryExcludedContextualUserFragment(.inputText(text: """
        <environment_context>
        <cwd>/repo</cwd>
        </environment_context>
        """)))
        XCTAssertFalse(isMemoryExcludedContextualUserFragment(.inputText(text: "<subagent_notification>done</subagent_notification>")))
    }

    func testSerializeFilteredRolloutResponseItemsDropsDeveloperAndContextualUserFragments() throws {
        let items: [RolloutItem] = [
            .sessionMeta,
            .responseItem(.message(role: "developer", content: [.inputText(text: "repo rules")])),
            .responseItem(.message(role: "user", content: [
                .inputText(text: "keep this"),
                .inputText(text: UserInstructions(directory: "/repo", text: "do not persist").intoText()),
                .inputText(text: SkillInstructions(name: "build", path: "/skills/build", contents: "do not persist").asTextForTest()),
                .inputImage(imageURL: "data:image/png;base64,abc")
            ])),
            .responseItem(.message(role: "assistant", content: [.outputText(text: "assistant output")])),
            .responseItem(.reasoning(id: "rs-1", summary: [])),
            .responseItem(.functionCall(name: "exec", arguments: #"{"cmd":"echo ok"}"#, callID: "call-1"))
        ]

        let json = try serializeFilteredRolloutResponseItemsForMemories(items)
        let decoded = try JSONDecoder().decode([ResponseItem].self, from: Data(json.utf8))

        XCTAssertEqual(decoded, [
            .message(role: "user", content: [
                .inputText(text: "keep this"),
                .inputImage(imageURL: "data:image/png;base64,abc")
            ]),
            .message(role: "assistant", content: [.outputText(text: "assistant output")]),
            .functionCall(name: "exec", arguments: #"{"cmd":"echo ok"}"#, callID: "call-1")
        ])
    }

    func testSerializeFilteredRolloutResponseItemsDropsUserMessageWhenOnlyExcludedFragments() throws {
        let items: [RolloutItem] = [
            .responseItem(.message(role: "user", content: [
                .inputText(text: UserInstructions(directory: "/repo", text: "do not persist").intoText())
            ]))
        ]

        let json = try serializeFilteredRolloutResponseItemsForMemories(items)

        XCTAssertEqual(json, "[]")
    }

    func testSerializeFilteredRolloutResponseItemsRedactsSecretsAfterEncodingLikeRust() throws {
        let secret = "sk-" + String(repeating: "A", count: 20)
        let json = try serializeFilteredRolloutResponseItemsForMemories([
            .responseItem(.message(role: "user", content: [.inputText(text: "token \(secret)")]))
        ])

        XCTAssertFalse(json.contains(secret))
        XCTAssertTrue(json.contains("[REDACTED_SECRET]"))
    }
}

private extension SkillInstructions {
    func asTextForTest() -> String {
        guard case let .message(_, _, content, _) = asResponseItem(),
              case let .inputText(text) = content[0] else {
            return ""
        }
        return text
    }
}
