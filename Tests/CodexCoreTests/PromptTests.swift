import XCTest
@testable import CodexCore

final class PromptTests: XCTestCase {
    func testFullInstructionsAppendApplyPatchGuidanceForRustLegacyShellModels() {
        let prompt = Prompt()
        let cases: [(slug: String, expectsApplyPatchInstructions: Bool)] = [
            ("gpt-3.5", true),
            ("gpt-4.1", true),
            ("gpt-4o", true),
            ("gpt-5", true),
            ("gpt-5.1", false),
            ("codex-mini-latest", true),
            ("gpt-oss:120b", false),
            ("gpt-5.1-codex", false),
            ("gpt-5.1-codex-max", false)
        ]

        for testCase in cases {
            let modelFamily = ModelsManager.constructModelFamilyOffline(model: testCase.slug)
            let full = prompt.fullInstructions(for: modelFamily)

            if testCase.expectsApplyPatchInstructions {
                XCTAssertTrue(
                    full.hasPrefix("\(modelFamily.baseInstructions)\n## `apply_patch`"),
                    "Expected apply_patch instructions for \(testCase.slug)"
                )
            } else {
                XCTAssertEqual(full, modelFamily.baseInstructions, testCase.slug)
            }
        }
    }

    func testFullInstructionsDoNotAppendApplyPatchGuidanceWhenBaseIsOverridden() {
        let modelFamily = ModelsManager.constructModelFamilyOffline(model: "gpt-4.1")
        let prompt = Prompt(baseInstructionsOverride: "custom instructions")

        XCTAssertEqual(prompt.fullInstructions(for: modelFamily), "custom instructions")
    }

    func testFullInstructionsOnlyFreeformApplyPatchToolSuppressesLegacyGuidance() {
        let modelFamily = ModelsManager.constructModelFamilyOffline(model: "gpt-4.1")

        let functionPrompt = Prompt(tools: [
            .function(ResponsesAPITool(
                name: "apply_patch",
                description: "Apply a patch",
                parameters: .object(properties: [:], required: nil, additionalProperties: nil)
            ))
        ])
        XCTAssertTrue(
            functionPrompt.fullInstructions(for: modelFamily)
                .hasPrefix("\(modelFamily.baseInstructions)\n## `apply_patch`")
        )

        let freeformPrompt = Prompt(tools: [
            ToolSpecFactory.createApplyPatchFreeformTool()
        ])
        XCTAssertEqual(freeformPrompt.fullInstructions(for: modelFamily), modelFamily.baseInstructions)
    }
}
