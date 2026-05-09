import XCTest
@testable import CodexCore

final class TurnItemTests: XCTestCase {
    func testUserMessageItemBuildsLegacyMessageAndImageURLs() throws {
        let item = UserMessageItem(
            id: "user-1",
            content: [
                .text("hello"),
                .image(imageURL: "data:image/png;base64,aaa"),
                .localImage(path: "/tmp/local.png"),
                .text(" world"),
                .skill(name: "swift", path: "/skills/swift/SKILL.md")
            ]
        )

        XCTAssertEqual(item.message, "hello world")
        XCTAssertEqual(item.imageURLs, ["data:image/png;base64,aaa"])
        XCTAssertEqual(item.asLegacyEvent(), .userMessage(UserMessageEvent(
            message: "hello world",
            images: ["data:image/png;base64,aaa"]
        )))
    }

    func testUserMessageLegacyEventKeepsEmptyImagesArray() throws {
        let event = UserMessageItem(id: "user-1", content: [.text("hello")]).asLegacyEvent()

        try XCTAssertJSONObjectEqual(event, [
            "type": "user_message",
            "message": "hello",
            "images": []
        ])
    }

    func testUserMessageEventOmitsNilImages() throws {
        let event = LegacyEventMessage.userMessage(UserMessageEvent(message: "hello", images: nil))

        try XCTAssertJSONObjectEqual(event, [
            "type": "user_message",
            "message": "hello"
        ])
    }

    func testAgentMessageItemSplitsLegacyTextEvents() {
        let item = AgentMessageItem(id: "agent-1", content: [.text("one"), .text("two")])

        XCTAssertEqual(item.asLegacyEvents(), [
            .agentMessage(AgentMessageEvent(message: "one")),
            .agentMessage(AgentMessageEvent(message: "two"))
        ])
    }

    func testAgentMessageItemPreservesPhaseAndMemoryCitationWireShape() throws {
        let item = AgentMessageItem(
            id: "agent-1",
            content: [.text("hello")],
            phase: .commentary,
            memoryCitation: MemoryCitation(
                entries: [
                    MemoryCitationEntry(
                        path: "MEMORY.md",
                        lineStart: 12,
                        lineEnd: 14,
                        note: "port checkpoint"
                    )
                ],
                rolloutIDs: ["019cc2ea-1dff-7902-8d40-c8f6e5d83cc4"]
            )
        )

        try XCTAssertJSONObjectEqual(item, [
            "id": "agent-1",
            "content": [
                [
                    "type": "Text",
                    "text": "hello"
                ]
            ],
            "phase": "commentary",
            "memory_citation": [
                "entries": [
                    [
                        "path": "MEMORY.md",
                        "lineStart": 12,
                        "lineEnd": 14,
                        "note": "port checkpoint"
                    ]
                ],
                "rolloutIds": ["019cc2ea-1dff-7902-8d40-c8f6e5d83cc4"]
            ]
        ])

        let data = try JSONEncoder().encode(item)
        XCTAssertEqual(try JSONDecoder().decode(AgentMessageItem.self, from: data), item)
    }

    func testReasoningItemHonorsRawReasoningFlag() {
        let item = ReasoningItem(
            id: "reason-1",
            summaryText: ["summary 1", "summary 2"],
            rawContent: ["raw"]
        )

        XCTAssertEqual(item.asLegacyEvents(showRawAgentReasoning: false), [
            .agentReasoning(AgentReasoningEvent(text: "summary 1")),
            .agentReasoning(AgentReasoningEvent(text: "summary 2"))
        ])
        XCTAssertEqual(item.asLegacyEvents(showRawAgentReasoning: true), [
            .agentReasoning(AgentReasoningEvent(text: "summary 1")),
            .agentReasoning(AgentReasoningEvent(text: "summary 2")),
            .agentReasoningRawContent(AgentReasoningRawContentEvent(text: "raw"))
        ])
    }

    func testReasoningItemDefaultsMissingRawContentToEmptyArray() throws {
        let json = #"{"id":"reason-1","summary_text":["summary"]}"#
        let item = try JSONDecoder().decode(ReasoningItem.self, from: Data(json.utf8))

        XCTAssertEqual(item, ReasoningItem(id: "reason-1", summaryText: ["summary"], rawContent: []))
    }

    func testWebSearchAndTurnItemIDs() {
        let item = TurnItem.webSearch(WebSearchItem(id: "search-1", query: "find docs"))

        XCTAssertEqual(item.id, "search-1")
        XCTAssertEqual(item.asLegacyEvents(showRawAgentReasoning: false), [
            .webSearchEnd(WebSearchEndEvent(
                callID: "search-1",
                query: "find docs",
                action: .search(query: "find docs")
            ))
        ])
    }

    func testImageGenerationAndTurnItemIDs() throws {
        let savedPath = try AbsolutePath(absolutePath: "/tmp/generated.png")
        let item = TurnItem.imageGeneration(ImageGenerationItem(
            id: "ig-1",
            status: "completed",
            revisedPrompt: "a clearer prompt",
            result: "base64-png",
            savedPath: savedPath
        ))

        XCTAssertEqual(item.id, "ig-1")
        XCTAssertEqual(item.asLegacyEvents(showRawAgentReasoning: false), [
            .imageGenerationEnd(ImageGenerationEndEvent(
                callID: "ig-1",
                status: "completed",
                revisedPrompt: "a clearer prompt",
                result: "base64-png",
                savedPath: savedPath
            ))
        ])
    }

    func testTurnItemWireShapeUsesRustTags() throws {
        let item = TurnItem.agentMessage(AgentMessageItem(
            id: "agent-1",
            content: [.text("hello")],
            phase: .finalAnswer
        ))

        try XCTAssertJSONObjectEqual(item, [
            "type": "AgentMessage",
            "id": "agent-1",
            "content": [
                [
                    "type": "Text",
                    "text": "hello"
                ]
            ],
            "phase": "final_answer"
        ])

        let data = try JSONEncoder().encode(item)
        XCTAssertEqual(try JSONDecoder().decode(TurnItem.self, from: data), item)
    }

    func testHookPromptTurnItemWireShapeUsesRustTags() throws {
        let item = TurnItem.hookPrompt(HookPromptItem(
            id: "hook-prompt-1",
            fragments: [
                HookPromptFragment(text: "Retry with care & joy.", hookRunID: "hook-run-1")
            ]
        ))

        try XCTAssertJSONObjectEqual(item, [
            "type": "HookPrompt",
            "id": "hook-prompt-1",
            "fragments": [
                [
                    "text": "Retry with care & joy.",
                    "hookRunId": "hook-run-1"
                ]
            ]
        ])
        XCTAssertEqual(item.id, "hook-prompt-1")
        XCTAssertEqual(item.asLegacyEvents(showRawAgentReasoning: false), [])

        let data = try JSONEncoder().encode(item)
        XCTAssertEqual(try JSONDecoder().decode(TurnItem.self, from: data), item)
    }

    func testHookPromptXMLRoundTripsMultipleFragments() throws {
        let original = [
            HookPromptFragment.fromSingleHook(text: "Retry with care & joy.", hookRunID: "hook-run-1"),
            HookPromptFragment.fromSingleHook(text: "Then summarize <cleanly>.", hookRunID: "hook-run-2")
        ]

        let message = try XCTUnwrap(HookPromptItem.buildMessage(fragments: original))
        guard case let .message(_, role, content, phase) = message else {
            return XCTFail("expected hook prompt message, got \(message)")
        }

        XCTAssertEqual(role, "user")
        XCTAssertNil(phase)
        XCTAssertEqual(content.count, 2)
        guard case let .inputText(firstXML) = content[0] else {
            return XCTFail("expected input text")
        }
        XCTAssertEqual(
            firstXML,
            #"<hook_prompt hook_run_id="hook-run-1">Retry with care &amp; joy.</hook_prompt>"#
        )

        let parsed = try XCTUnwrap(HookPromptItem.parseMessage(id: nil, content: content))
        XCTAssertEqual(parsed.fragments, original)
    }

    func testHookPromptParsesLegacySingleHookRunID() throws {
        let parsed = try XCTUnwrap(HookPromptFragment.parseXML(
            #"<hook_prompt hook_run_id="hook-run-1">Retry with tests.</hook_prompt>"#
        ))

        XCTAssertEqual(parsed, HookPromptFragment(text: "Retry with tests.", hookRunID: "hook-run-1"))
        XCTAssertNil(HookPromptFragment.parseXML(#"<hook_prompt hook_run_id="">Retry.</hook_prompt>"#))
    }

    func testPlanTurnItemWireShapeUsesRustTags() throws {
        let item = TurnItem.plan(PlanItem(id: "plan-1", text: "1. Port protocol events"))

        try XCTAssertJSONObjectEqual(item, [
            "type": "Plan",
            "id": "plan-1",
            "text": "1. Port protocol events"
        ])
        XCTAssertEqual(item.id, "plan-1")
        XCTAssertEqual(item.asLegacyEvents(showRawAgentReasoning: false), [])

        let data = try JSONEncoder().encode(item)
        XCTAssertEqual(try JSONDecoder().decode(TurnItem.self, from: data), item)
    }

    func testImageGenerationTurnItemWireShapeUsesRustTags() throws {
        let item = TurnItem.imageGeneration(ImageGenerationItem(
            id: "ig-1",
            status: "completed",
            revisedPrompt: "a clearer prompt",
            result: "base64-png",
            savedPath: try AbsolutePath(absolutePath: "/tmp/generated.png")
        ))

        try XCTAssertJSONObjectEqual(item, [
            "type": "ImageGeneration",
            "id": "ig-1",
            "status": "completed",
            "revised_prompt": "a clearer prompt",
            "result": "base64-png",
            "saved_path": "/tmp/generated.png"
        ])

        let data = try JSONEncoder().encode(item)
        XCTAssertEqual(try JSONDecoder().decode(TurnItem.self, from: data), item)
    }

    func testImageViewTurnItemWireShapeUsesRustTags() throws {
        let item = TurnItem.imageView(ImageViewItem(
            id: "view-1",
            path: try AbsolutePath(absolutePath: "/tmp/image.png")
        ))

        try XCTAssertJSONObjectEqual(item, [
            "type": "ImageView",
            "id": "view-1",
            "path": "/tmp/image.png"
        ])
        XCTAssertEqual(item.id, "view-1")
        XCTAssertEqual(item.asLegacyEvents(showRawAgentReasoning: false), [
            .viewImageToolCall(ViewImageToolCallEvent(callID: "view-1", path: "/tmp/image.png"))
        ])

        let data = try JSONEncoder().encode(item)
        XCTAssertEqual(try JSONDecoder().decode(TurnItem.self, from: data), item)
    }

    func testContextCompactionTurnItemWireShapeUsesRustTags() throws {
        let item = TurnItem.contextCompaction(ContextCompactionItem(id: "compact-1"))

        try XCTAssertJSONObjectEqual(item, [
            "type": "ContextCompaction",
            "id": "compact-1"
        ])
        XCTAssertEqual(item.id, "compact-1")
        XCTAssertEqual(item.asLegacyEvents(showRawAgentReasoning: false), [
            .contextCompacted(ContextCompactedEvent())
        ])

        let data = try JSONEncoder().encode(item)
        XCTAssertEqual(try JSONDecoder().decode(TurnItem.self, from: data), item)
    }

    func testLegacyEventWireShapeUsesRustSnakeCaseTags() throws {
        let event = LegacyEventMessage.webSearchEnd(WebSearchEndEvent(callID: "search-1", query: "docs"))

        try XCTAssertJSONObjectEqual(event, [
            "type": "web_search_end",
            "call_id": "search-1",
            "query": "docs",
            "action": [
                "type": "search",
                "query": "docs"
            ]
        ])

        let data = try JSONEncoder().encode(event)
        XCTAssertEqual(try JSONDecoder().decode(LegacyEventMessage.self, from: data), event)
    }

    func testImageViewAndContextCompactionLegacyEventWireShapesUseRustTags() throws {
        let imageView = LegacyEventMessage.viewImageToolCall(ViewImageToolCallEvent(
            callID: "view-1",
            path: "/tmp/image.png"
        ))
        let contextCompacted = LegacyEventMessage.contextCompacted(ContextCompactedEvent())

        try XCTAssertJSONObjectEqual(imageView, [
            "type": "view_image_tool_call",
            "call_id": "view-1",
            "path": "/tmp/image.png"
        ])
        try XCTAssertJSONObjectEqual(contextCompacted, [
            "type": "context_compacted"
        ])

        XCTAssertEqual(try JSONDecoder().decode(
            LegacyEventMessage.self,
            from: try JSONEncoder().encode(imageView)
        ), imageView)
        XCTAssertEqual(try JSONDecoder().decode(
            LegacyEventMessage.self,
            from: try JSONEncoder().encode(contextCompacted)
        ), contextCompacted)
    }

    func testImageGenerationLegacyEventWireShapeUsesRustSnakeCaseTags() throws {
        let event = LegacyEventMessage.imageGenerationEnd(ImageGenerationEndEvent(
            callID: "ig-1",
            status: "completed",
            revisedPrompt: "a clearer prompt",
            result: "base64-png",
            savedPath: try AbsolutePath(absolutePath: "/tmp/generated.png")
        ))

        try XCTAssertJSONObjectEqual(event, [
            "type": "image_generation_end",
            "call_id": "ig-1",
            "status": "completed",
            "revised_prompt": "a clearer prompt",
            "result": "base64-png",
            "saved_path": "/tmp/generated.png"
        ])

        let data = try JSONEncoder().encode(event)
        XCTAssertEqual(try JSONDecoder().decode(LegacyEventMessage.self, from: data), event)
    }

    func testItemStartedEventEmitsLegacyBeginForToolLikeItems() throws {
        let threadID = try ConversationId(string: "018f7a2d-4c5b-7abc-8def-0123456789ab")
        let webSearch = ItemStartedEvent(
            threadID: threadID,
            turnID: "turn-1",
            item: .webSearch(WebSearchItem(id: "search-1", query: "docs")),
            startedAtMilliseconds: 123
        )
        let imageGeneration = ItemStartedEvent(
            threadID: threadID,
            turnID: "turn-1",
            item: .imageGeneration(ImageGenerationItem(
                id: "ig-1",
                status: "in_progress",
                result: ""
            )),
            startedAtMilliseconds: 124
        )
        let userMessage = ItemStartedEvent(
            threadID: threadID,
            turnID: "turn-1",
            item: .userMessage(UserMessageItem(id: "user-1", content: [])),
            startedAtMilliseconds: 125
        )
        let imageView = ItemStartedEvent(
            threadID: threadID,
            turnID: "turn-1",
            item: .imageView(ImageViewItem(
                id: "view-1",
                path: try AbsolutePath(absolutePath: "/tmp/image.png")
            )),
            startedAtMilliseconds: 126
        )

        XCTAssertEqual(webSearch.asLegacyEvents(), [
            .webSearchBegin(WebSearchBeginEvent(callID: "search-1"))
        ])
        XCTAssertEqual(imageGeneration.asLegacyEvents(), [
            .imageGenerationBegin(ImageGenerationBeginEvent(callID: "ig-1"))
        ])
        XCTAssertEqual(userMessage.asLegacyEvents(), [])
        XCTAssertEqual(imageView.asLegacyEvents(), [])
    }

    func testItemLifecycleEventsCarryRustTimingFields() throws {
        let threadID = try ConversationId(string: "018f7a2d-4c5b-7abc-8def-0123456789ab")
        let started = ItemStartedEvent(
            threadID: threadID,
            turnID: "turn-1",
            item: .plan(PlanItem(id: "plan-1", text: "next")),
            startedAtMilliseconds: 123
        )
        let completed = ItemCompletedEvent(
            threadID: threadID,
            turnID: "turn-1",
            item: .plan(PlanItem(id: "plan-1", text: "next")),
            completedAtMilliseconds: 456
        )

        try XCTAssertJSONObjectEqual(started, [
            "thread_id": "018f7a2d-4c5b-7abc-8def-0123456789ab",
            "turn_id": "turn-1",
            "item": [
                "type": "Plan",
                "id": "plan-1",
                "text": "next"
            ],
            "started_at_ms": 123
        ])
        try XCTAssertJSONObjectEqual(completed, [
            "thread_id": "018f7a2d-4c5b-7abc-8def-0123456789ab",
            "turn_id": "turn-1",
            "item": [
                "type": "Plan",
                "id": "plan-1",
                "text": "next"
            ],
            "completed_at_ms": 456
        ])

        let missingCompletedAt = try JSONDecoder().decode(ItemCompletedEvent.self, from: Data("""
        {
          "thread_id": "018f7a2d-4c5b-7abc-8def-0123456789ab",
          "turn_id": "turn-1",
          "item": {
            "type": "Plan",
            "id": "plan-1",
            "text": "next"
          }
        }
        """.utf8))

        XCTAssertEqual(missingCompletedAt.completedAtMilliseconds, 0)
    }

    func testItemCompletedEventDelegatesToTurnItemLegacyEvents() throws {
        let threadID = try ConversationId(string: "018f7a2d-4c5b-7abc-8def-0123456789ab")
        let completed = ItemCompletedEvent(
            threadID: threadID,
            turnID: "turn-1",
            item: .reasoning(ReasoningItem(id: "reason-1", summaryText: ["summary"], rawContent: ["raw"]))
        )

        XCTAssertEqual(completed.asLegacyEvents(showRawAgentReasoning: true), [
            .agentReasoning(AgentReasoningEvent(text: "summary")),
            .agentReasoningRawContent(AgentReasoningRawContentEvent(text: "raw"))
        ])
    }
}
