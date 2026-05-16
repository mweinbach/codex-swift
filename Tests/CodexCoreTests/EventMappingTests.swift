import CodexCore
import XCTest

final class EventMappingTests: XCTestCase {
    func testParsesUserMessageWithTextAndTwoImages() {
        let img1 = "https://example.com/one.png"
        let img2 = "https://example.com/two.jpg"

        let item = ResponseItem.message(
            role: "user",
            content: [
                .inputText(text: "Hello world"),
                .inputImage(imageURL: img1),
                .inputImage(imageURL: img2, detail: .original)
            ]
        )

        let turnItem = EventMapping.parseTurnItem(item)

        guard case let .userMessage(message) = turnItem else {
            return XCTFail("expected user message, got \(String(describing: turnItem))")
        }
        XCTAssertEqual(message.content, [
            .text("Hello world"),
            .image(imageURL: img1),
            .image(imageURL: img2, detail: .original)
        ])
    }

    func testSkipsLocalImageLabelTextLikeRust() {
        let imageURL = "data:image/png;base64,abc"
        let userText = "Please review this image."

        let item = ResponseItem.message(
            role: "user",
            content: [
                .inputText(text: "<image name=[Image #1]>"),
                .inputImage(imageURL: imageURL, detail: defaultImageDetail),
                .inputText(text: "</image>"),
                .inputText(text: userText)
            ]
        )

        guard case let .userMessage(message) = EventMapping.parseTurnItem(item) else {
            return XCTFail("expected user message")
        }
        XCTAssertEqual(message.content, [
            .image(imageURL: imageURL, detail: defaultImageDetail),
            .text(userText)
        ])
    }

    func testSkipsUnnamedImageLabelTextLikeRust() {
        let imageURL = "data:image/png;base64,abc"
        let userText = "Please review this image."

        let item = ResponseItem.message(
            role: "user",
            content: [
                .inputText(text: "<image>"),
                .inputImage(imageURL: imageURL, detail: defaultImageDetail),
                .inputText(text: "</image>"),
                .inputText(text: userText)
            ]
        )

        guard case let .userMessage(message) = EventMapping.parseTurnItem(item) else {
            return XCTFail("expected user message")
        }
        XCTAssertEqual(message.content, [
            .image(imageURL: imageURL, detail: defaultImageDetail),
            .text(userText)
        ])
    }

    func testParsesHookPromptBeforePlainUserMessage() {
        let item = ResponseItem.message(
            id: "hook-prompt-1",
            role: "user",
            content: [
                .inputText(text: #"<hook_prompt hook_run_id="hook-run-1">Retry with tests.</hook_prompt>"#),
                .inputText(text: #"<hook_prompt hook_run_id="hook-run-2">Then summarize cleanly.</hook_prompt>"#)
            ]
        )

        let turnItem = EventMapping.parseTurnItem(item)

        XCTAssertEqual(turnItem, .hookPrompt(HookPromptItem(
            id: "hook-prompt-1",
            fragments: [
                HookPromptFragment(text: "Retry with tests.", hookRunID: "hook-run-1"),
                HookPromptFragment(text: "Then summarize cleanly.", hookRunID: "hook-run-2")
            ]
        )))
    }

    func testParsesHookPromptAndHidesContextualFragments() {
        let item = ResponseItem.message(
            id: "hook-prompt-1",
            role: "user",
            content: [
                .inputText(text: "<environment_context>ctx</environment_context>"),
                .inputText(text: #"<hook_prompt hook_run_id="hook-run-1">Retry with care &amp; joy.</hook_prompt>"#)
            ]
        )

        XCTAssertEqual(EventMapping.parseTurnItem(item), .hookPrompt(HookPromptItem(
            id: "hook-prompt-1",
            fragments: [
                HookPromptFragment(text: "Retry with care & joy.", hookRunID: "hook-run-1")
            ]
        )))
    }

    func testInvalidHookPromptFallsBackToUserMessage() {
        let item = ResponseItem.message(
            id: "user-1",
            role: "user",
            content: [
                .inputText(text: #"<hook_prompt hook_run_id="">Retry with tests.</hook_prompt>"#)
            ]
        )

        guard case let .userMessage(message) = EventMapping.parseTurnItem(item) else {
            return XCTFail("expected user message fallback")
        }
        XCTAssertEqual(message.content, [.text(#"<hook_prompt hook_run_id="">Retry with tests.</hook_prompt>"#)])
    }

    func testSkipsUserInstructionsSkillInstructionsEnvironmentAndShellCommands() {
        let items: [ResponseItem] = [
            .message(role: "user", content: [
                .inputText(text: "<user_instructions>test_text</user_instructions>")
            ]),
            .message(role: "user", content: [
                .inputText(text: "<environment_context>test_text</environment_context>")
            ]),
            .message(role: "user", content: [
                .inputText(text: "# AGENTS.md instructions for test_directory\n\n<INSTRUCTIONS>\ntest_text\n</INSTRUCTIONS>")
            ]),
            .message(role: "user", content: [
                .inputText(text: "<skill>\n<name>demo</name>\n<path>skills/demo/SKILL.md</path>\nbody\n</skill>")
            ]),
            .message(role: "user", content: [
                .inputText(text: "<user_shell_command>echo 42</user_shell_command>")
            ])
        ]

        for item in items {
            XCTAssertNil(EventMapping.parseTurnItem(item), "\(item)")
        }
    }

    func testSkipsMixedContextualUserFragmentsLikeRust() {
        let items: [ResponseItem] = [
            .message(role: "user", content: [
                .inputText(text: "<environment_context>ctx</environment_context>"),
                .inputText(text: "# AGENTS.md instructions for dir\n\n<INSTRUCTIONS>\nbody\n</INSTRUCTIONS>")
            ]),
            .message(role: "user", content: [
                .inputText(text: "<turn_aborted>interrupted</turn_aborted>"),
                .inputText(text: "plain text")
            ]),
            .message(role: "user", content: [
                .inputText(text: "<SUBAGENT_NOTIFICATION>{}</subagent_notification>"),
                .inputText(text: "plain text")
            ])
        ]

        for item in items {
            XCTAssertNil(EventMapping.parseTurnItem(item), "\(item)")
        }
    }

    func testParsesAgentMessageAndPreservesID() {
        let item = ResponseItem.message(
            id: "msg-1",
            role: "assistant",
            content: [.outputText(text: "Hello from Codex")],
            phase: .commentary
        )

        let turnItem = EventMapping.parseTurnItem(item)

        XCTAssertEqual(turnItem, .agentMessage(AgentMessageItem(
            id: "msg-1",
            content: [.text("Hello from Codex")],
            phase: .commentary
        )))
    }

    func testIgnoresSystemDeveloperAndUnknownMessages() {
        XCTAssertNil(EventMapping.parseTurnItem(.message(role: "system", content: [.inputText(text: "system")])))
        XCTAssertNil(EventMapping.parseTurnItem(.message(role: "developer", content: [.inputText(text: "developer")])))
        XCTAssertNil(EventMapping.parseTurnItem(.message(role: "tool", content: [.inputText(text: "tool")])))
    }

    func testParsesReasoningSummaryAndRawContent() {
        let item = ResponseItem.reasoning(
            id: "reasoning_1",
            summary: [
                .summaryText(text: "Step 1"),
                .summaryText(text: "Step 2")
            ],
            content: [.reasoningText(text: "raw details")]
        )

        let turnItem = EventMapping.parseTurnItem(item)

        XCTAssertEqual(turnItem, .reasoning(ReasoningItem(
            id: "reasoning_1",
            summaryText: ["Step 1", "Step 2"],
            rawContent: ["raw details"]
        )))
    }

    func testParsesReasoningIncludingTextContent() {
        let item = ResponseItem.reasoning(
            id: "reasoning_2",
            summary: [.summaryText(text: "Summarized step")],
            content: [
                .reasoningText(text: "raw step"),
                .text("final thought")
            ]
        )

        let turnItem = EventMapping.parseTurnItem(item)

        XCTAssertEqual(turnItem, .reasoning(ReasoningItem(
            id: "reasoning_2",
            summaryText: ["Summarized step"],
            rawContent: ["raw step", "final thought"]
        )))
    }

    func testParsesWebSearchCall() {
        let item = ResponseItem.webSearchCall(
            id: "ws_1",
            status: "completed",
            action: .search(query: "weather")
        )

        let turnItem = EventMapping.parseTurnItem(item)

        XCTAssertEqual(turnItem, .webSearch(WebSearchItem(
            id: "ws_1",
            query: "weather",
            action: .search(query: "weather")
        )))
    }

    func testParsesWebSearchOpenPageAndFindInPageCalls() {
        XCTAssertEqual(EventMapping.parseTurnItem(.webSearchCall(
            id: "ws_open",
            status: "completed",
            action: .openPage(url: "https://example.com")
        )), .webSearch(WebSearchItem(
            id: "ws_open",
            query: "https://example.com",
            action: .openPage(url: "https://example.com")
        )))

        XCTAssertEqual(EventMapping.parseTurnItem(.webSearchCall(
            id: "ws_find",
            status: "completed",
            action: .findInPage(url: "https://example.com", pattern: "needle")
        )), .webSearch(WebSearchItem(
            id: "ws_find",
            query: "'needle' in https://example.com",
            action: .findInPage(url: "https://example.com", pattern: "needle")
        )))
    }

    func testParsesPartialWebSearchCallAsOtherAction() {
        XCTAssertEqual(EventMapping.parseTurnItem(.webSearchCall(
            id: "ws_partial",
            status: "in_progress",
            action: nil
        )), .webSearch(WebSearchItem(
            id: "ws_partial",
            query: "",
            action: .other
        )))
    }

    func testWebSearchActionDetailUsesFirstQueryPreview() {
        XCTAssertEqual(EventMapping.parseTurnItem(.webSearchCall(
            id: "ws_multi",
            action: .search(query: nil, queries: ["first", "second"])
        )), .webSearch(WebSearchItem(
            id: "ws_multi",
            query: "first ...",
            action: .search(query: nil, queries: ["first", "second"])
        )))
    }

    func testParsesImageGenerationCall() {
        let item = ResponseItem.imageGenerationCall(
            id: "ig_1",
            status: "completed",
            revisedPrompt: "a clearer prompt",
            result: "base64-png"
        )

        let turnItem = EventMapping.parseTurnItem(item)

        XCTAssertEqual(turnItem, .imageGeneration(ImageGenerationItem(
            id: "ig_1",
            status: "completed",
            revisedPrompt: "a clearer prompt",
            result: "base64-png"
        )))
    }

    func testSkipsNonSearchWebSearchActionsAndOtherItems() {
        XCTAssertNil(EventMapping.parseTurnItem(.compaction(encryptedContent: "encrypted")))
        XCTAssertNil(EventMapping.parseTurnItem(.contextCompaction(encryptedContent: "encrypted")))
        XCTAssertNil(EventMapping.parseTurnItem(.knownPersisted(type: "function_call")))
        XCTAssertNil(EventMapping.parseTurnItem(.other))
    }
}
