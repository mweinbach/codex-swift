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
        XCTAssertEqual(sessionMetaLine.meta.instructions, "be exact")
        XCTAssertEqual(sessionMetaLine.meta.source, .cli)
        XCTAssertEqual(sessionMetaLine.meta.modelProvider, "openai")
        XCTAssertEqual(sessionMetaLine.git, GitInfo(commitHash: "abc123", branch: "main"))

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
}

private func rolloutLines(at path: URL) throws -> [RolloutLine] {
    try String(contentsOf: path, encoding: .utf8)
        .split(whereSeparator: \.isNewline)
        .map { line in
            try JSONDecoder().decode(RolloutLine.self, from: Data(line.utf8))
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
