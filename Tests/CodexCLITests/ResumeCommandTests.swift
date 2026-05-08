import CodexCLI
import CodexCore
import XCTest

final class ResumeCommandTests: XCTestCase {
    func testResolveLastUsesDefaultProviderFilterUnlessAllIsSet() throws {
        let temp = try ResumeCommandTemporaryDirectory()
        let openAIID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000101"))
        let betaID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000102"))

        let openAI = try writeSessionFile(
            home: temp.url,
            timestamp: "2026-05-07T12-00-00",
            id: openAIID,
            provider: "openai"
        )
        let beta = try writeSessionFile(
            home: temp.url,
            timestamp: "2026-05-08T12-00-00",
            id: betaID,
            provider: "beta"
        )

        let defaultFiltered = try ResumeCommandResolver.resolve(
            CodexCLI.ResumeCommandRequest(sessionID: nil, last: true, all: false),
            codexHome: temp.url
        )
        assertSession(
            defaultFiltered,
            id: try ConversationId(string: openAIID.uuidString.lowercased()),
            path: openAI.path,
            historyItemCount: 3
        )

        let allProviders = try ResumeCommandResolver.resolve(
            CodexCLI.ResumeCommandRequest(sessionID: nil, last: true, all: true),
            codexHome: temp.url
        )
        assertSession(
            allProviders,
            id: try ConversationId(string: betaID.uuidString.lowercased()),
            path: beta.path,
            historyItemCount: 3
        )
    }

    func testResolveSessionIDFindsSpecificRollout() throws {
        let temp = try ResumeCommandTemporaryDirectory()
        let sessionID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000201"))
        let session = try writeSessionFile(
            home: temp.url,
            timestamp: "2026-05-08T12-30-00",
            id: sessionID,
            provider: "beta"
        )

        let resolution = try ResumeCommandResolver.resolve(
            CodexCLI.ResumeCommandRequest(sessionID: sessionID.uuidString.lowercased(), last: false, all: false),
            codexHome: temp.url
        )

        assertSession(
            resolution,
            id: try ConversationId(string: sessionID.uuidString.lowercased()),
            path: session.path,
            historyItemCount: 3
        )
    }

    func testResolveWithoutTargetReturnsPickerPage() throws {
        let temp = try ResumeCommandTemporaryDirectory()
        let sessionID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000301"))
        let session = try writeSessionFile(
            home: temp.url,
            timestamp: "2026-05-08T13-00-00",
            id: sessionID,
            provider: "openai"
        )

        let resolution = try ResumeCommandResolver.resolve(
            CodexCLI.ResumeCommandRequest(sessionID: nil, last: false, all: false),
            codexHome: temp.url
        )

        guard case let .picker(page) = resolution else {
            return XCTFail("expected picker page")
        }
        XCTAssertEqual(page.items.map { comparablePath($0.path) }, [session.path].map(comparablePath))
        XCTAssertTrue(ResumeCommandFormatter.render(resolution).contains("Saved sessions:"))
        XCTAssertTrue(ResumeCommandFormatter.render(resolution).contains(sessionID.uuidString.lowercased()))
    }

    func testResolveErrorsWhenNoLastSessionExists() throws {
        let temp = try ResumeCommandTemporaryDirectory()

        XCTAssertThrowsError(try ResumeCommandResolver.resolve(
            CodexCLI.ResumeCommandRequest(sessionID: nil, last: true, all: false),
            codexHome: temp.url
        )) { error in
            XCTAssertEqual(error as? ResumeCommandError, .noSavedSessions)
        }
    }

    private struct WrittenSession {
        let path: String
    }

    private func writeSessionFile(
        home: URL,
        timestamp: String,
        id: UUID,
        provider: String
    ) throws -> WrittenSession {
        let sessions = home
            .appendingPathComponent("sessions", isDirectory: true)
            .appendingPathComponent(String(timestamp.prefix(4)), isDirectory: true)
            .appendingPathComponent(String(timestamp.dropFirst(5).prefix(2)), isDirectory: true)
            .appendingPathComponent(String(timestamp.dropFirst(8).prefix(2)), isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)

        let file = sessions.appendingPathComponent("rollout-\(timestamp)-\(id.uuidString.lowercased()).jsonl")
        let conversationID = try ConversationId(string: id.uuidString.lowercased())
        let lines = [
            try encodeLine(RolloutLine(
                timestamp: timestamp,
                item: .sessionMeta(SessionMetaLine(meta: SessionMeta(
                    id: conversationID,
                    timestamp: timestamp,
                    cwd: ".",
                    originator: "test_originator",
                    cliVersion: "test_version",
                    source: .exec,
                    modelProvider: provider
                )))
            )),
            try encodeLine(RolloutLine(
                timestamp: timestamp,
                item: .turnContext(TurnContextItem(
                    cwd: ".",
                    approvalPolicy: .never,
                    sandboxPolicy: .readOnly,
                    model: "gpt-5.4",
                    summary: .auto
                ))
            )),
            try encodeLine(RolloutLine(
                timestamp: timestamp,
                item: .eventMsg(.userMessage(UserMessageEvent(message: "Hello from resume test")))
            ))
        ]

        try (lines.joined(separator: "\n") + "\n").write(to: file, atomically: true, encoding: .utf8)
        return WrittenSession(path: file.resolvingSymlinksInPath().path)
    }

    private func encodeLine<T: Encodable>(_ value: T) throws -> String {
        let data = try JSONEncoder().encode(value)
        return try XCTUnwrap(String(data: data, encoding: .utf8))
    }

    private func comparablePath(_ path: String) -> String {
        path.replacingOccurrences(of: "/private/var/", with: "/var/")
    }

    private func assertSession(
        _ resolution: ResumeCommandResolution,
        id: ConversationId,
        path: String,
        historyItemCount: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case let .session(session) = resolution else {
            return XCTFail("expected session resolution", file: file, line: line)
        }
        XCTAssertEqual(session.conversationID, id, file: file, line: line)
        XCTAssertEqual(comparablePath(session.path), comparablePath(path), file: file, line: line)
        XCTAssertEqual(session.historyItemCount, historyItemCount, file: file, line: line)
    }
}

private final class ResumeCommandTemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-swift-resume-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}
