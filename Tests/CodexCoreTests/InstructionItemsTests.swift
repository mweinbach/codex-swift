import XCTest
@testable import CodexCore

final class InstructionItemsTests: XCTestCase {
    func testUserInstructionsResponseItem() {
        let userInstructions = UserInstructions(directory: "test_directory", text: "test_text")
        let expectedText = "# AGENTS.md instructions for test_directory\n\n<INSTRUCTIONS>\ntest_text\n</INSTRUCTIONS>"

        XCTAssertEqual(userInstructions.intoText(), expectedText)
        XCTAssertEqual(userInstructions.asResponseItem(), .message(
            role: "user",
            content: [.inputText(text: expectedText)]
        ))
    }

    func testIsUserInstructions() {
        XCTAssertTrue(UserInstructions.isUserInstructions(message: [
            .inputText(text: "# AGENTS.md instructions for test_directory\n\n<INSTRUCTIONS>\ntest_text\n</INSTRUCTIONS>")
        ]))
        XCTAssertTrue(UserInstructions.isUserInstructions(message: [
            .inputText(text: "<user_instructions>test_text</user_instructions>")
        ]))
        XCTAssertTrue(UserInstructions.isUserInstructions(message: [
            .inputText(text: "  # agents.md instructions for test_directory\n\n<INSTRUCTIONS>\ntest_text\n</instructions>\n")
        ]))
        XCTAssertFalse(UserInstructions.isUserInstructions(message: [
            .inputText(text: "test_text")
        ]))
        XCTAssertFalse(UserInstructions.isUserInstructions(message: [
            .inputText(text: "# AGENTS.md instructions for test_directory")
        ]))
        XCTAssertFalse(UserInstructions.isUserInstructions(message: [
            .inputText(text: "<user_instructions>test_text")
        ]))
        XCTAssertFalse(UserInstructions.isUserInstructions(message: [
            .inputText(text: "# AGENTS.md instructions for test_directory"),
            .inputText(text: "extra")
        ]))
        XCTAssertFalse(UserInstructions.isUserInstructions(message: [
            .inputImage(imageURL: "file:///tmp/image.png")
        ]))
    }

    func testSkillInstructionsResponseItem() {
        let skillInstructions = SkillInstructions(
            name: "demo-skill",
            path: "skills/demo/SKILL.md",
            contents: "body"
        )

        XCTAssertEqual(skillInstructions.asResponseItem(), .message(
            role: "user",
            content: [.inputText(
                text: "<skill>\n<name>demo-skill</name>\n<path>skills/demo/SKILL.md</path>\nbody\n</skill>"
            )]
        ))
    }

    func testIsSkillInstructions() {
        XCTAssertTrue(SkillInstructions.isSkillInstructions(message: [
            .inputText(text: "<skill>\n<name>demo-skill</name>\n<path>skills/demo/SKILL.md</path>\nbody\n</skill>")
        ]))
        XCTAssertTrue(SkillInstructions.isSkillInstructions(message: [
            .inputText(text: "  <SKILL>\nbody\n</SKILL>\n")
        ]))
        XCTAssertFalse(SkillInstructions.isSkillInstructions(message: [
            .inputText(text: "regular text")
        ]))
        XCTAssertFalse(SkillInstructions.isSkillInstructions(message: [
            .inputText(text: "<skill>\nbody")
        ]))
        XCTAssertFalse(SkillInstructions.isSkillInstructions(message: [
            .inputText(text: "<skillish>\nbody\n</skill>")
        ]))
        XCTAssertFalse(SkillInstructions.isSkillInstructions(message: [
            .inputText(text: "<skill>\nbody\n</skill>"),
            .inputText(text: "extra")
        ]))
    }

    func testStandardContextualUserFragmentsMatchRustMarkers() {
        XCTAssertTrue(ContextualUserFragments.isStandardText(
            "  <ENVIRONMENT_CONTEXT>ctx</environment_context>\n"
        ))
        XCTAssertTrue(ContextualUserFragments.isStandardText(
            "  <TURN_ABORTED>interrupted</turn_aborted>\n"
        ))
        XCTAssertTrue(ContextualUserFragments.isStandardText(
            "  <SUBAGENT_NOTIFICATION>{}</subagent_notification>\n"
        ))
        XCTAssertTrue(ContextualUserFragments.isStandardText(
            " Warning: The maximum number of unified exec processes you can keep open is 60 and you currently have 61 processes open. "
        ))
        XCTAssertTrue(ContextualUserFragments.isStandardText(
            " Warning: apply_patch was requested via exec_command. Use the apply_patch tool instead of exec_command. "
        ))
        XCTAssertTrue(ContextualUserFragments.isStandardText(
            " Warning: Your account was flagged for potentially high-risk cyber activity and this request was routed to gpt-5.2 as a fallback. "
        ))

        XCTAssertFalse(ContextualUserFragments.isStandardText("<environment_context>ctx"))
        XCTAssertFalse(ContextualUserFragments.isStandardText("<turn_aborted>interrupted"))
        XCTAssertFalse(ContextualUserFragments.isStandardText("<subagent_notification>{}"))
        XCTAssertFalse(ContextualUserFragments.isStandardText(
            "Warning: apply_patch was requested via exec_command."
        ))
    }

    func testDeveloperInstructions() {
        let instructions = DeveloperInstructions("developer text")

        XCTAssertEqual(instructions.intoText(), "developer text")
        XCTAssertEqual(instructions.asResponseItem(), .message(
            role: "developer",
            content: [.inputText(text: "developer text")]
        ))
    }

    func testImageGenerationInstructionsMatchRustContextFragment() {
        let instructions = ImageGenerationInstructions(
            imageOutputDirectory: "/tmp/codex/generated_images/session-1",
            imageOutputPath: "/tmp/codex/generated_images/session-1/<image_id>.png"
        )

        XCTAssertEqual(
            instructions.intoText(),
            "Generated images are saved to /tmp/codex/generated_images/session-1 as /tmp/codex/generated_images/session-1/<image_id>.png by default.\nIf you need to use a generated image at another path, copy it and leave the original in place unless the user explicitly asks you to delete it."
        )
        XCTAssertEqual(instructions.asResponseItem(), .message(
            role: "developer",
            content: [.inputText(text: instructions.intoText())]
        ))
    }

    func testInstructionCodableShapesUseRustFieldNames() throws {
        try XCTAssertJSONObjectEqual(
            UserInstructions(directory: "repo", text: "contents"),
            [
                "directory": "repo",
                "text": "contents"
            ]
        )
        try XCTAssertJSONObjectEqual(
            SkillInstructions(name: "skill", path: "skills/skill/SKILL.md", contents: "body"),
            [
                "name": "skill",
                "path": "skills/skill/SKILL.md",
                "contents": "body"
            ]
        )
        try XCTAssertJSONObjectEqual(DeveloperInstructions("developer text"), [
            "text": "developer text"
        ])
    }
}
