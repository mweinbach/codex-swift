import CodexCore
import XCTest

final class RolloutRecorderTests: XCTestCase {
    func testCreateWritesSessionMetaAndFiltersRecordedItems() throws {
        let temp = try RolloutRecorderTemporaryDirectory()
        let conversationID = try ConversationId(string: "67e55044-10b1-426f-9247-bb680e5fe0c8")
        let dates = DateSequence([
            fixedDate(year: 2026, month: 5, day: 8, hour: 11, minute: 22, second: 33, millisecond: 123),
            fixedDate(year: 2026, month: 5, day: 8, hour: 11, minute: 22, second: 34),
            fixedDate(year: 2026, month: 5, day: 8, hour: 11, minute: 22, second: 35),
            fixedDate(year: 2026, month: 5, day: 8, hour: 11, minute: 22, second: 36)
        ])

        let recorder = try RolloutRecorder.create(
            codexHome: temp.url,
            cwd: URL(fileURLWithPath: "/repo", isDirectory: true),
            conversationID: conversationID,
            instructions: "be exact",
            source: .cli,
            originator: "codex_swift",
            cliVersion: "0.1.0",
            modelProvider: "openai",
            gitInfo: GitInfo(commitHash: "abc123", branch: "main"),
            calendar: utcCalendar(),
            timestampProvider: dates.next
        )

        XCTAssertTrue(recorder.rolloutPath.path.hasSuffix(
            "/sessions/2026/05/08/rollout-2026-05-08T11-22-33-67e55044-10b1-426f-9247-bb680e5fe0c8.jsonl"
        ))

        try recorder.recordItems([
            .responseItem(.message(role: "assistant", content: [.outputText(text: "kept")])),
            .responseItem(.other),
            .eventMsg(.warning(WarningEvent(message: "filtered"))),
            .eventMsg(.userMessage(UserMessageEvent(message: "persisted")))
        ])
        try recorder.flush()

        let lines = try rolloutLines(at: recorder.rolloutPath)
        XCTAssertEqual(lines.count, 3)
        XCTAssertEqual(lines.map(\.timestamp), [
            "2026-05-08T11:22:34.000Z",
            "2026-05-08T11:22:35.000Z",
            "2026-05-08T11:22:36.000Z"
        ])

        guard case let .sessionMeta(sessionMetaLine) = lines[0].item else {
            return XCTFail("expected session meta first")
        }
        XCTAssertEqual(sessionMetaLine.meta.id, conversationID)
        XCTAssertEqual(sessionMetaLine.meta.timestamp, "2026-05-08T11:22:33.123Z")
        XCTAssertEqual(sessionMetaLine.meta.cwd, "/repo")
        XCTAssertEqual(sessionMetaLine.meta.originator, "codex_swift")
        XCTAssertEqual(sessionMetaLine.meta.cliVersion, "0.1.0")
        XCTAssertEqual(sessionMetaLine.meta.source, .cli)
        XCTAssertEqual(sessionMetaLine.meta.modelProvider, "openai")
        XCTAssertEqual(sessionMetaLine.git, GitInfo(commitHash: "abc123", branch: "main"))

        let firstLineObject = try XCTUnwrap(jsonObjects(at: recorder.rolloutPath).first)
        let firstPayload = try XCTUnwrap(firstLineObject["payload"] as? [String: Any])
        XCTAssertNil(firstPayload["instructions"])

        XCTAssertEqual(
            lines[1].item,
            .responseItem(.message(role: "assistant", content: [.outputText(text: "kept")]))
        )
        XCTAssertEqual(
            lines[2].item,
            .eventMsg(.userMessage(UserMessageEvent(message: "persisted")))
        )
    }

    func testResumeAppendsWithoutWritingSessionMeta() throws {
        let temp = try RolloutRecorderTemporaryDirectory()
        let path = temp.url.appendingPathComponent("rollout.jsonl")
        let conversationID = try ConversationId(string: "67e55044-10b1-426f-9247-bb680e5fe0c8")
        try writeLines([
            RolloutLine(
                timestamp: "2026-05-08T00:00:00.000Z",
                item: .sessionMeta(SessionMetaLine(meta: SessionMeta(
                    id: conversationID,
                    timestamp: "2026-05-08T00:00:00.000Z",
                    cwd: "/repo",
                    originator: "codex_swift",
                    cliVersion: "0.1.0",
                    source: .cli
                )))
            )
        ], to: path)

        let dates = DateSequence([fixedDate(year: 2026, month: 5, day: 8, hour: 1, minute: 2, second: 3)])
        let recorder = try RolloutRecorder.resume(path: path, timestampProvider: dates.next)
        try recorder.recordItems([.responseItem(.message(role: "assistant", content: [.outputText(text: "appended")]))])
        try recorder.shutdown()

        let lines = try rolloutLines(at: path)
        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(lines[1].timestamp, "2026-05-08T01:02:03.000Z")
        XCTAssertEqual(lines[1].item, .responseItem(.message(role: "assistant", content: [.outputText(text: "appended")])))
    }

    func testExtendedEventPersistenceSanitizesExecEndLikeRust() throws {
        let temp = try RolloutRecorderTemporaryDirectory()
        let conversationID = try ConversationId(string: "67e55044-10b1-426f-9247-bb680e5fe0c8")
        let dates = DateSequence([
            fixedDate(year: 2026, month: 5, day: 8, hour: 11, minute: 22, second: 33),
            fixedDate(year: 2026, month: 5, day: 8, hour: 11, minute: 22, second: 34)
        ])
        let recorder = try RolloutRecorder.create(
            codexHome: temp.url,
            cwd: URL(fileURLWithPath: "/repo", isDirectory: true),
            conversationID: conversationID,
            source: .cli,
            originator: "codex_swift",
            cliVersion: "0.1.0",
            modelProvider: "openai",
            eventPersistenceMode: .extended,
            calendar: utcCalendar(),
            timestampProvider: dates.next
        )
        let aggregate = String(repeating: "a", count: 12_000) + "tail"
        try recorder.recordItems([
            .eventMsg(.execCommandEnd(ExecCommandEndEvent(
                callID: "call-1",
                turnID: "turn-1",
                command: ["bash", "-lc", "generate-output"],
                cwd: "/repo",
                parsedCmd: [.unknown(cmd: "generate-output")],
                stdout: "raw stdout",
                stderr: "raw stderr",
                aggregatedOutput: aggregate,
                exitCode: 0,
                duration: ProtocolDuration(secs: 1),
                formattedOutput: "formatted output"
            )))
        ])
        try recorder.flush()

        let lines = try rolloutLines(at: recorder.rolloutPath)
        XCTAssertEqual(lines.count, 2)
        guard case let .eventMsg(.execCommandEnd(event)) = lines[1].item else {
            return XCTFail("expected persisted exec command end event")
        }
        XCTAssertEqual(event.stdout, "")
        XCTAssertEqual(event.stderr, "")
        XCTAssertEqual(event.formattedOutput, "")
        XCTAssertTrue(event.aggregatedOutput.hasPrefix(String(repeating: "a", count: 100)))
        XCTAssertTrue(event.aggregatedOutput.contains("chars truncated"))
        XCTAssertTrue(event.aggregatedOutput.hasSuffix("tail"))
    }

    func testLimitedEventPersistenceFiltersExtendedExecEndLikeRust() throws {
        let temp = try RolloutRecorderTemporaryDirectory()
        let conversationID = try ConversationId(string: "67e55044-10b1-426f-9247-bb680e5fe0c8")
        let dates = DateSequence([
            fixedDate(year: 2026, month: 5, day: 8, hour: 11, minute: 22, second: 33),
            fixedDate(year: 2026, month: 5, day: 8, hour: 11, minute: 22, second: 34)
        ])
        let recorder = try RolloutRecorder.create(
            codexHome: temp.url,
            cwd: URL(fileURLWithPath: "/repo", isDirectory: true),
            conversationID: conversationID,
            source: .cli,
            originator: "codex_swift",
            cliVersion: "0.1.0",
            modelProvider: "openai",
            calendar: utcCalendar(),
            timestampProvider: dates.next
        )
        try recorder.recordItems([
            .eventMsg(.execCommandEnd(ExecCommandEndEvent(
                callID: "call-1",
                turnID: "turn-1",
                command: ["bash", "-lc", "generate-output"],
                cwd: "/repo",
                parsedCmd: [.unknown(cmd: "generate-output")],
                stdout: "raw stdout",
                stderr: "raw stderr",
                aggregatedOutput: "aggregate",
                exitCode: 0,
                duration: ProtocolDuration(secs: 1),
                formattedOutput: "formatted output"
            )))
        ])
        try recorder.flush()

        let lines = try rolloutLines(at: recorder.rolloutPath)
        XCTAssertEqual(lines.count, 1)
        guard case .sessionMeta = lines[0].item else {
            return XCTFail("limited mode should only keep the session meta")
        }
    }

    func testGetRolloutHistorySkipsBadLinesAndUsesFirstSessionMetaID() throws {
        let temp = try RolloutRecorderTemporaryDirectory()
        let path = temp.url.appendingPathComponent("history.jsonl")
        let firstID = try ConversationId(string: "67e55044-10b1-426f-9247-bb680e5fe0c8")
        let secondID = try ConversationId(string: "77e55044-10b1-426f-9247-bb680e5fe0c8")
        let firstMeta = RolloutRecordItem.sessionMeta(SessionMetaLine(meta: SessionMeta(
            id: firstID,
            timestamp: "2026-05-08T00:00:00.000Z",
            cwd: "/repo",
            originator: "codex_swift",
            cliVersion: "0.1.0",
            source: .cli
        )))
        let response = RolloutRecordItem.responseItem(.message(role: "assistant", content: [.outputText(text: "kept")]))
        let secondMeta = RolloutRecordItem.sessionMeta(SessionMetaLine(meta: SessionMeta(
            id: secondID,
            timestamp: "2026-05-08T00:00:01.000Z",
            cwd: "/repo2",
            originator: "codex_swift",
            cliVersion: "0.1.0",
            source: .cli
        )))
        let encoded = try [
            "not json",
            jsonLine(RolloutLine(timestamp: "2026-05-08T00:00:00.000Z", item: firstMeta)),
            "",
            jsonLine(RolloutLine(timestamp: "2026-05-08T00:00:01.000Z", item: response)),
            jsonLine(RolloutLine(timestamp: "2026-05-08T00:00:02.000Z", item: secondMeta))
        ].joined(separator: "\n")
        try encoded.write(to: path, atomically: true, encoding: .utf8)

        let history = try RolloutRecorder.getRolloutHistory(path: path)

        guard case let .resumed(resumed) = history else {
            return XCTFail("expected resumed history")
        }
        XCTAssertEqual(resumed.conversationID, firstID)
        XCTAssertEqual(resumed.rolloutPath, path.path)
        XCTAssertEqual(resumed.history, [firstMeta, response, secondMeta])
    }

    func testGetRolloutHistoryReportsEmptyAndMissingSessionMeta() throws {
        let temp = try RolloutRecorderTemporaryDirectory()
        let empty = temp.url.appendingPathComponent("empty.jsonl")
        try "".write(to: empty, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try RolloutRecorder.getRolloutHistory(path: empty)) { error in
            XCTAssertEqual(error as? RolloutRecorderError, .emptySessionFile)
        }

        let noMeta = temp.url.appendingPathComponent("no-meta.jsonl")
        try writeLines([
            RolloutLine(
                timestamp: "2026-05-08T00:00:00.000Z",
                item: .responseItem(.message(role: "assistant", content: [.outputText(text: "kept")]))
            )
        ], to: noMeta)
        XCTAssertThrowsError(try RolloutRecorder.getRolloutHistory(path: noMeta)) { error in
            XCTAssertEqual(error as? RolloutRecorderError, .missingConversationID)
        }
    }

    func testGetRolloutHistorySkipsLegacyGhostSnapshotLines() throws {
        let temp = try RolloutRecorderTemporaryDirectory()
        let path = temp.url.appendingPathComponent("legacy-ghost.jsonl")
        let conversationID = try ConversationId(string: "67e55044-10b1-426f-9247-bb680e5fe0c8")
        let sessionMeta = RolloutRecordItem.sessionMeta(SessionMetaLine(meta: SessionMeta(
            id: conversationID,
            timestamp: "2026-05-08T00:00:00.000Z",
            cwd: "/repo",
            originator: "codex_swift",
            cliVersion: "0.1.0",
            source: .cli
        )))
        let ghost = RolloutRecordItem.responseItem(.ghostSnapshot(ghostCommit: GhostCommit(
            id: "deadbeef",
            preexistingUntrackedFiles: [],
            preexistingUntrackedDirs: []
        )))
        let message = RolloutRecordItem.responseItem(.message(
            role: "assistant",
            content: [.outputText(text: "kept")]
        ))
        try writeLines([
            RolloutLine(timestamp: "2026-05-08T00:00:00.000Z", item: sessionMeta),
            RolloutLine(timestamp: "2026-05-08T00:00:01.000Z", item: ghost),
            RolloutLine(timestamp: "2026-05-08T00:00:02.000Z", item: message)
        ], to: path)

        let history = try RolloutRecorder.getRolloutHistory(path: path)

        guard case let .resumed(resumed) = history else {
            return XCTFail("expected resumed history")
        }
        XCTAssertEqual(resumed.history, [sessionMeta, message])
    }

    func testGetRolloutHistoryFiltersLegacyGhostSnapshotsFromCompactionHistory() throws {
        let temp = try RolloutRecorderTemporaryDirectory()
        let path = temp.url.appendingPathComponent("legacy-ghost-compaction.jsonl")
        let conversationID = try ConversationId(string: "67e55044-10b1-426f-9247-bb680e5fe0c8")
        let sessionMeta = RolloutRecordItem.sessionMeta(SessionMetaLine(meta: SessionMeta(
            id: conversationID,
            timestamp: "2026-05-08T00:00:00.000Z",
            cwd: "/repo",
            originator: "codex_swift",
            cliVersion: "0.1.0",
            source: .cli
        )))
        let kept = ResponseItem.message(role: "assistant", content: [.outputText(text: "kept")])
        let ghost = ResponseItem.ghostSnapshot(ghostCommit: GhostCommit(
            id: "deadbeef",
            preexistingUntrackedFiles: [],
            preexistingUntrackedDirs: []
        ))
        let compacted = RolloutRecordItem.compacted(CompactedItem(
            message: "summary",
            replacementHistory: [kept, ghost]
        ))
        try writeLines([
            RolloutLine(timestamp: "2026-05-08T00:00:00.000Z", item: sessionMeta),
            RolloutLine(timestamp: "2026-05-08T00:00:01.000Z", item: compacted)
        ], to: path)

        let history = try RolloutRecorder.getRolloutHistory(path: path)

        guard case let .resumed(resumed) = history,
              case let .compacted(sanitized)? = resumed.history.dropFirst().first
        else {
            return XCTFail("expected sanitized compacted history")
        }
        XCTAssertEqual(sanitized.replacementHistory, [kept])
    }

    func testPersistsStructuredToolOutputResponseItemsLikeRust() throws {
        let output = FunctionCallOutputPayload(
            content: "ignored when content items exist",
            contentItems: [
                .inputText(text: "screenshot attached"),
                .inputImage(imageURL: "data:image/png;base64,AAAA", detail: .high)
            ],
            success: false
        )
        let line = RolloutLine(
            timestamp: "2026-05-08T00:00:00.000Z",
            item: .responseItem(.functionCallOutput(callID: "call-1", output: output))
        )

        let object = try JSONObject(line)
        XCTAssertEqual(object["type"] as? String, "response_item")
        XCTAssertEqual(object["timestamp"] as? String, "2026-05-08T00:00:00.000Z")
        let payload = try XCTUnwrap(object["payload"] as? [String: Any])
        XCTAssertEqual(payload["type"] as? String, "function_call_output")
        XCTAssertEqual(payload["call_id"] as? String, "call-1")
        XCTAssertNil(payload["success"])
        let outputItems = try XCTUnwrap(payload["output"] as? [[String: Any]])
        XCTAssertEqual(outputItems.count, 2)
        XCTAssertEqual(outputItems[0]["type"] as? String, "input_text")
        XCTAssertEqual(outputItems[0]["text"] as? String, "screenshot attached")
        XCTAssertEqual(outputItems[1]["type"] as? String, "input_image")
        XCTAssertEqual(outputItems[1]["image_url"] as? String, "data:image/png;base64,AAAA")
        XCTAssertEqual(outputItems[1]["detail"] as? String, "high")

        let decoded = try JSONDecoder().decode(RolloutLine.self, from: JSONEncoder().encode(line))
        guard case let .responseItem(.functionCallOutput(decodedCallID, decodedOutput)) = decoded.item else {
            return XCTFail("expected persisted structured function-call output")
        }
        XCTAssertEqual(decodedCallID, "call-1")
        XCTAssertEqual(decodedOutput.contentItems, output.contentItems)
        XCTAssertEqual(decodedOutput.content, output.description)
        XCTAssertNil(decodedOutput.success)

        let customLine = RolloutLine(
            timestamp: "2026-05-08T00:00:01.000Z",
            item: .responseItem(.customToolCallOutput(
                callID: "custom-1",
                name: "apply_patch",
                output: output
            ))
        )
        let customObject = try JSONObject(customLine)
        let customPayload = try XCTUnwrap(customObject["payload"] as? [String: Any])
        XCTAssertEqual(customPayload["type"] as? String, "custom_tool_call_output")
        XCTAssertEqual(customPayload["call_id"] as? String, "custom-1")
        XCTAssertEqual(customPayload["name"] as? String, "apply_patch")
        XCTAssertNil(customPayload["success"])
        XCTAssertEqual(try XCTUnwrap(customPayload["output"] as? [[String: Any]]).count, 2)

        let customDecoded = try JSONDecoder().decode(RolloutLine.self, from: JSONEncoder().encode(customLine))
        guard case let .responseItem(.customToolCallOutput(decodedCustomID, decodedName, decodedCustomOutput)) =
            customDecoded.item
        else {
            return XCTFail("expected persisted structured custom-tool output")
        }
        XCTAssertEqual(decodedCustomID, "custom-1")
        XCTAssertEqual(decodedName, "apply_patch")
        XCTAssertEqual(decodedCustomOutput.contentItems, output.contentItems)
        XCTAssertNil(decodedCustomOutput.success)
    }

    func testPersistsReasoningResponseItemsLikeRust() throws {
        let reasoning = ResponseItem.reasoning(
            id: "rs_runtime_only",
            summary: [.summaryText(text: "checked the Rust serde attributes")],
            content: [
                .reasoningText(text: "raw chain fragment"),
                .text("visible explanation")
            ],
            encryptedContent: "encrypted-payload"
        )
        let line = RolloutLine(
            timestamp: "2026-05-08T00:00:00.000Z",
            item: .responseItem(reasoning)
        )

        let object = try JSONObject(line)
        XCTAssertEqual(object["type"] as? String, "response_item")
        XCTAssertEqual(object["timestamp"] as? String, "2026-05-08T00:00:00.000Z")
        let payload = try XCTUnwrap(object["payload"] as? [String: Any])
        XCTAssertEqual(payload["type"] as? String, "reasoning")
        XCTAssertNil(payload["id"])
        XCTAssertEqual(payload["encrypted_content"] as? String, "encrypted-payload")

        let summary = try XCTUnwrap(payload["summary"] as? [[String: Any]])
        XCTAssertEqual(summary.count, 1)
        XCTAssertEqual(summary[0]["type"] as? String, "summary_text")
        XCTAssertEqual(summary[0]["text"] as? String, "checked the Rust serde attributes")

        let content = try XCTUnwrap(payload["content"] as? [[String: Any]])
        XCTAssertEqual(content.count, 2)
        XCTAssertEqual(content[0]["type"] as? String, "reasoning_text")
        XCTAssertEqual(content[0]["text"] as? String, "raw chain fragment")
        XCTAssertEqual(content[1]["type"] as? String, "text")
        XCTAssertEqual(content[1]["text"] as? String, "visible explanation")

        let decoded = try JSONDecoder().decode(RolloutLine.self, from: JSONEncoder().encode(line))
        let expectedDecoded = ResponseItem.reasoning(
            id: "",
            summary: [.summaryText(text: "checked the Rust serde attributes")],
            content: [
                .reasoningText(text: "raw chain fragment"),
                .text("visible explanation")
            ],
            encryptedContent: "encrypted-payload"
        )
        XCTAssertEqual(decoded.item, .responseItem(expectedDecoded))

        let textOnly = ResponseItem.reasoning(
            id: "rs_text_only",
            summary: [.summaryText(text: "text-only reasoning content is not persisted")],
            content: [.text("display-only reasoning text")],
            encryptedContent: nil
        )
        let textOnlyLine = RolloutLine(
            timestamp: "2026-05-08T00:00:01.000Z",
            item: .responseItem(textOnly)
        )
        let textOnlyPayload = try XCTUnwrap(JSONObject(textOnlyLine)["payload"] as? [String: Any])
        XCTAssertNil(textOnlyPayload["id"])
        XCTAssertNil(textOnlyPayload["content"])
        XCTAssertTrue(textOnlyPayload["encrypted_content"] is NSNull)

        let temp = try RolloutRecorderTemporaryDirectory()
        let path = temp.url.appendingPathComponent("reasoning-rollout.jsonl")
        let conversationID = try ConversationId(string: "67e55044-10b1-426f-9247-bb680e5fe0c8")
        let sessionMeta = RolloutRecordItem.sessionMeta(SessionMetaLine(meta: SessionMeta(
            id: conversationID,
            timestamp: "2026-05-08T00:00:00.000Z",
            cwd: "/repo",
            originator: "codex_swift",
            cliVersion: "0.1.0",
            source: .cli
        )))
        try writeLines([
            RolloutLine(timestamp: "2026-05-08T00:00:00.000Z", item: sessionMeta),
            line,
            textOnlyLine
        ], to: path)

        guard case let .resumed(resumed) = try RolloutRecorder.getRolloutHistory(path: path) else {
            return XCTFail("expected resumed history")
        }
        let expectedTextOnlyDecoded = ResponseItem.reasoning(
            id: "",
            summary: [.summaryText(text: "text-only reasoning content is not persisted")],
            content: nil,
            encryptedContent: nil
        )
        XCTAssertEqual(resumed.history, [
            sessionMeta,
            .responseItem(expectedDecoded),
            .responseItem(expectedTextOnlyDecoded)
        ])
        XCTAssertEqual(
            RolloutRecorder.reconstructResponseHistory(from: resumed.history),
            [expectedDecoded, expectedTextOnlyDecoded]
        )
    }

    func testReconstructResponseHistoryUsesResponseItemsAndNormalizesToolPairs() {
        let history = RolloutRecorder.reconstructResponseHistory(from: [
            .sessionMeta(SessionMetaLine(meta: SessionMeta(
                id: ConversationId(),
                timestamp: "",
                cwd: "",
                originator: "",
                cliVersion: ""
            ))),
            .responseItem(.message(role: "user", content: [.inputText(text: "run it")])),
            .responseItem(.functionCall(name: "shell_command", arguments: "{}", callID: "call-1")),
            .eventMsg(.warning(WarningEvent(message: "ignored")))
        ])

        XCTAssertEqual(history, [
            .message(role: "user", content: [.inputText(text: "run it")]),
            .functionCall(name: "shell_command", arguments: "{}", callID: "call-1"),
            .functionCallOutput(callID: "call-1", output: FunctionCallOutputPayload(content: "aborted"))
        ])
    }

    func testReconstructResponseHistoryAppliesCompactionReplacementAndFallback() {
        let replacement: [ResponseItem] = [
            .message(role: "user", content: [.inputText(text: "replacement")])
        ]
        XCTAssertEqual(
            RolloutRecorder.reconstructResponseHistory(from: [
                .responseItem(.message(role: "user", content: [.inputText(text: "old")])),
                .compacted(CompactedItem(message: "summary", replacementHistory: replacement))
            ]),
            replacement
        )

        let rebuilt = RolloutRecorder.reconstructResponseHistory(from: [
            .responseItem(.message(role: "user", content: [.inputText(text: "old request")])),
            .compacted(CompactedItem(message: "summary"))
        ])
        XCTAssertEqual(rebuilt, [
            .message(role: "user", content: [.inputText(text: "old request")]),
            .message(role: "user", content: [.inputText(text: "summary")])
        ])
    }
}

private func rolloutLines(at path: URL) throws -> [RolloutLine] {
    try String(contentsOf: path, encoding: .utf8)
        .split(whereSeparator: \.isNewline)
        .map { line in
            try JSONDecoder().decode(RolloutLine.self, from: Data(line.utf8))
        }
}

private func jsonObjects(at path: URL) throws -> [[String: Any]] {
    try String(contentsOf: path, encoding: .utf8)
        .split(whereSeparator: \.isNewline)
        .map { line in
            let object = try JSONSerialization.jsonObject(with: Data(line.utf8))
            return try XCTUnwrap(object as? [String: Any])
        }
}

private func writeLines(_ lines: [RolloutLine], to path: URL) throws {
    let text = try lines.map(jsonLine).joined(separator: "\n") + "\n"
    try text.write(to: path, atomically: true, encoding: .utf8)
}

private func jsonLine<T: Encodable>(_ value: T) throws -> String {
    String(data: try JSONEncoder().encode(value), encoding: .utf8)!
}

private func fixedDate(
    year: Int,
    month: Int,
    day: Int,
    hour: Int,
    minute: Int,
    second: Int,
    millisecond: Int = 0
) -> Date {
    DateComponents(
        calendar: utcCalendar(),
        timeZone: TimeZone(secondsFromGMT: 0),
        year: year,
        month: month,
        day: day,
        hour: hour,
        minute: minute,
        second: second,
        nanosecond: millisecond * 1_000_000
    ).date!
}

private func utcCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
}

private final class DateSequence {
    private var dates: [Date]

    init(_ dates: [Date]) {
        self.dates = dates
    }

    func next() -> Date {
        guard !dates.isEmpty else {
            return fixedDate(year: 2026, month: 5, day: 8, hour: 0, minute: 0, second: 0)
        }
        return dates.removeFirst()
    }
}

private final class RolloutRecorderTemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
}
