import CodexCore
import XCTest

final class RolloutListingTests: XCTestCase {
    func testMissingSessionsDirectoryReturnsEmptyPage() throws {
        let temp = try TemporaryDirectory()

        let page = try RolloutListing.getConversations(
            codexHome: temp.url,
            pageSize: 10,
            defaultProvider: "openai"
        )

        XCTAssertEqual(page, ConversationsPage())
    }

    func testListsConversationsNewestFirstWithHeadSummary() throws {
        let temp = try TemporaryDirectory()
        let firstID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let secondID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
        let thirdID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000003"))

        let first = try writeSessionFile(home: temp.url, timestamp: "2025-01-01T12-00-00", id: firstID)
        let second = try writeSessionFile(home: temp.url, timestamp: "2025-01-02T12-00-00", id: secondID)
        let third = try writeSessionFile(home: temp.url, timestamp: "2025-01-03T12-00-00", id: thirdID)

        let page = try RolloutListing.getConversations(
            codexHome: temp.url,
            pageSize: 10,
            allowedSources: [.vscode],
            modelProviders: ["test-provider"],
            defaultProvider: "test-provider"
        )

        XCTAssertEqual(
            page.items.map { comparablePath($0.path) },
            [third.path, second.path, first.path].map(comparablePath)
        )
        XCTAssertEqual(page.items.map(\.createdAt), [
            "2025-01-03T12-00-00",
            "2025-01-02T12-00-00",
            "2025-01-01T12-00-00"
        ])
        XCTAssertEqual(page.items.map(\.head), [
            [sessionMetaHead(id: thirdID, timestamp: "2025-01-03T12-00-00", source: .vscode, provider: "test-provider")],
            [sessionMetaHead(id: secondID, timestamp: "2025-01-02T12-00-00", source: .vscode, provider: "test-provider")],
            [sessionMetaHead(id: firstID, timestamp: "2025-01-01T12-00-00", source: .vscode, provider: "test-provider")]
        ])
        XCTAssertTrue(page.items.allSatisfy { $0.updatedAt != nil })
        XCTAssertNil(page.nextCursor)
        XCTAssertEqual(page.numScannedFiles, 3)
        XCTAssertFalse(page.reachedScanCap)
    }

    func testPaginationUsesTimestampThenUUIDCursor() throws {
        let temp = try TemporaryDirectory()
        let lowerID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let higherID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
        let olderID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000003"))

        let lower = try writeSessionFile(home: temp.url, timestamp: "2025-01-02T12-00-00", id: lowerID)
        let higher = try writeSessionFile(home: temp.url, timestamp: "2025-01-02T12-00-00", id: higherID)
        let older = try writeSessionFile(home: temp.url, timestamp: "2025-01-01T12-00-00", id: olderID)

        let firstPage = try RolloutListing.getConversations(
            codexHome: temp.url,
            pageSize: 2,
            defaultProvider: "test-provider"
        )

        XCTAssertEqual(
            firstPage.items.map { comparablePath($0.path) },
            [higher.path, lower.path].map(comparablePath)
        )
        let cursor = try XCTUnwrap(firstPage.nextCursor)
        XCTAssertEqual(cursor.token, "2025-01-02T12:00:00Z")

        let cursorData = try JSONEncoder().encode(cursor)
        XCTAssertEqual(try JSONDecoder().decode(ConversationCursor.self, from: cursorData), cursor)
        XCTAssertEqual(RolloutListing.parseCursor(cursor.token), cursor)

        let secondPage = try RolloutListing.getConversations(
            codexHome: temp.url,
            pageSize: 2,
            cursor: cursor,
            defaultProvider: "test-provider"
        )

        XCTAssertEqual(secondPage.items.map { comparablePath($0.path) }, [older.path].map(comparablePath))
        XCTAssertNil(secondPage.nextCursor)
    }

    func testFilenameTimestampCursorNormalizesToRustAnchorFormat() throws {
        let cursor = try XCTUnwrap(RolloutListing.parseCursor("2026-01-27T12-34-56"))

        XCTAssertEqual(cursor.token, "2026-01-27T12:34:56Z")
        XCTAssertEqual(
            RolloutListing.parseCursor(
                "2026-01-27T12-34-56|00000000-0000-0000-0000-000000000001"
            ),
            cursor
        )
    }

    func testListsConversationsWithRustSortDirectionAndBackwardsCursor() throws {
        let temp = try TemporaryDirectory()
        let olderID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000004"))
        let middleID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000005"))
        let newerID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000006"))

        let older = try writeSessionFile(home: temp.url, timestamp: "2025-01-01T12-00-00", id: olderID)
        let middle = try writeSessionFile(home: temp.url, timestamp: "2025-01-02T12-00-00", id: middleID)
        let newer = try writeSessionFile(home: temp.url, timestamp: "2025-01-03T12-00-00", id: newerID)

        let firstPage = try RolloutListing.getConversations(
            codexHome: temp.url,
            pageSize: 2,
            sortDirection: .ascending,
            defaultProvider: "test-provider"
        )

        XCTAssertEqual(
            firstPage.items.map { comparablePath($0.path) },
            [older.path, middle.path].map(comparablePath)
        )
        XCTAssertEqual(firstPage.nextCursor?.token, "2025-01-02T12:00:00Z")
        XCTAssertEqual(firstPage.backwardsCursor?.token, "2025-01-01T12:00:00.001Z")

        let secondPage = try RolloutListing.getConversations(
            codexHome: temp.url,
            pageSize: 2,
            cursor: try XCTUnwrap(firstPage.nextCursor),
            sortDirection: .ascending,
            defaultProvider: "test-provider"
        )

        XCTAssertEqual(secondPage.items.map { comparablePath($0.path) }, [newer.path].map(comparablePath))
        XCTAssertNil(secondPage.nextCursor)
        XCTAssertEqual(secondPage.backwardsCursor?.token, "2025-01-03T12:00:00.001Z")
    }

    func testSourceProviderAndUserMessageFiltersMatchRustListingRules() throws {
        let temp = try TemporaryDirectory()
        let vscodeID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000010"))
        let cliID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000011"))
        let missingProviderID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000012"))
        let noUserID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000013"))

        let vscode = try writeSessionFile(
            home: temp.url,
            timestamp: "2025-01-04T12-00-00",
            id: vscodeID,
            source: .vscode,
            provider: "openai"
        )
        _ = try writeSessionFile(
            home: temp.url,
            timestamp: "2025-01-03T12-00-00",
            id: cliID,
            source: .cli,
            provider: "openai"
        )
        let missingProvider = try writeSessionFile(
            home: temp.url,
            timestamp: "2025-01-02T12-00-00",
            id: missingProviderID,
            source: .vscode,
            provider: nil
        )
        _ = try writeSessionFile(
            home: temp.url,
            timestamp: "2025-01-01T12-00-00",
            id: noUserID,
            source: .vscode,
            provider: "openai",
            includeUserMessage: false
        )

        let openAIPage = try RolloutListing.getConversations(
            codexHome: temp.url,
            pageSize: 10,
            allowedSources: [.vscode],
            modelProviders: ["openai"],
            defaultProvider: "openai"
        )
        XCTAssertEqual(
            openAIPage.items.map { comparablePath($0.path) },
            [vscode.path, missingProvider.path].map(comparablePath)
        )

        let betaPage = try RolloutListing.getConversations(
            codexHome: temp.url,
            pageSize: 10,
            allowedSources: [.vscode],
            modelProviders: ["beta"],
            defaultProvider: "openai"
        )
        XCTAssertTrue(betaPage.items.isEmpty)
    }

    func testReadHeadSummarySkipsRuntimeOnlyItemsAndKeepsResponseItems() throws {
        let temp = try TemporaryDirectory()
        let id = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000020"))
        let session = try writeSessionFile(
            home: temp.url,
            timestamp: "2025-01-05T12-00-00",
            id: id,
            responseItemsBeforeUser: [.message(role: "assistant", content: [.outputText(text: "hello")])]
        )

        let head = try RolloutListing.readHeadForSummary(path: URL(fileURLWithPath: session.path))

        XCTAssertEqual(head, [
            sessionMetaHead(id: id, timestamp: "2025-01-05T12-00-00", source: .vscode, provider: "test-provider"),
            .object([
                "type": .string("message"),
                "role": .string("assistant"),
                "content": .array([
                    .object([
                        "type": .string("output_text"),
                        "text": .string("hello")
                    ])
                ])
            ])
        ])
    }

    func testFindConversationPathByIDString() throws {
        let temp = try TemporaryDirectory()
        let id = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000030"))
        let session = try writeSessionFile(home: temp.url, timestamp: "2025-01-06T12-00-00", id: id)

        XCTAssertEqual(
            comparablePath(try XCTUnwrap(RolloutListing.findConversationPathByIDString(
                codexHome: temp.url,
                idString: id.uuidString.lowercased()
            ))),
            comparablePath(session.path)
        )
        XCTAssertNil(try RolloutListing.findConversationPathByIDString(codexHome: temp.url, idString: "not-a-uuid"))
        XCTAssertNil(try RolloutListing.findConversationPathByIDString(codexHome: temp.url, idString: "00000000-0000-0000-0000-000000009999"))
    }

    private struct WrittenSession {
        let path: String
    }

    private func writeSessionFile(
        home: URL,
        timestamp: String,
        id: UUID,
        source: SessionSource = .vscode,
        provider: String? = "test-provider",
        includeUserMessage: Bool = true,
        responseItemsBeforeUser: [ResponseItem] = []
    ) throws -> WrittenSession {
        let sessions = home
            .appendingPathComponent("sessions", isDirectory: true)
            .appendingPathComponent(String(timestamp.prefix(4)), isDirectory: true)
            .appendingPathComponent(String(timestamp.dropFirst(5).prefix(2)), isDirectory: true)
            .appendingPathComponent(String(timestamp.dropFirst(8).prefix(2)), isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)

        let file = sessions.appendingPathComponent("rollout-\(timestamp)-\(id.uuidString.lowercased()).jsonl")
        var lines = [
            try encodeLine(RolloutLine(
                timestamp: timestamp,
                item: .sessionMeta(SessionMetaLine(meta: SessionMeta(
                    id: try ConversationId(string: id.uuidString.lowercased()),
                    timestamp: timestamp,
                    cwd: ".",
                    originator: "test_originator",
                    cliVersion: "test_version",
                    source: source,
                    modelProvider: provider
                )))
            )),
            try encodeLine(RolloutLine(
                timestamp: timestamp,
                item: .turnContext(TurnContextItem(
                    cwd: ".",
                    approvalPolicy: .onRequest,
                    sandboxPolicy: .readOnly,
                    model: "gpt-5.4",
                    summary: .auto
                ))
            )),
            try encodeLine(RolloutLine(
                timestamp: timestamp,
                item: .compacted(CompactedItem(message: "summary"))
            ))
        ]

        for item in responseItemsBeforeUser {
            lines.append(try encodeLine(RolloutLine(timestamp: timestamp, item: .responseItem(item))))
        }

        if includeUserMessage {
            lines.append(try encodeLine(RolloutLine(
                timestamp: timestamp,
                item: .eventMsg(.userMessage(UserMessageEvent(message: "Hello from user")))
            )))
        }

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

    private func sessionMetaHead(
        id: UUID,
        timestamp: String,
        source: SessionSource,
        provider: String?
    ) -> JSONValue {
        .object([
            "id": .string(id.uuidString.lowercased()),
            "timestamp": .string(timestamp),
            "cwd": .string("."),
            "originator": .string("test_originator"),
            "cli_version": .string("test_version"),
            "source": sourceJSONValue(source),
            "model_provider": provider.map(JSONValue.string) ?? .null,
            "base_instructions": .null
        ])
    }

    private func sourceJSONValue(_ source: SessionSource) -> JSONValue {
        switch source {
        case .cli:
            return .string("cli")
        case .vscode:
            return .string("vscode")
        case .exec:
            return .string("exec")
        case .mcp:
            return .string("mcp")
        case let .custom(source):
            return .object(["custom": .string(source)])
        case let .internal(source):
            return .object(["internal": .string(source.rawValue)])
        case let .subagent(subagent):
            return .object(["subagent": subagentJSONValue(subagent)])
        case .unknown:
            return .string("unknown")
        }
    }

    private func subagentJSONValue(_ source: SubAgentSource) -> JSONValue {
        switch source {
        case .review:
            return .string("review")
        case .compact:
            return .string("compact")
        case let .threadSpawn(parentThreadID, depth, agentPath, agentNickname, agentRole):
            var value: [String: JSONValue] = [
                "parent_thread_id": .string(parentThreadID.description),
                "depth": .integer(Int64(depth))
            ]
            if let agentPath {
                value["agent_path"] = .string(agentPath.description)
            }
            if let agentNickname {
                value["agent_nickname"] = .string(agentNickname)
            }
            if let agentRole {
                value["agent_role"] = .string(agentRole)
            }
            return .object(["thread_spawn": .object(value)])
        case .memoryConsolidation:
            return .string("memory_consolidation")
        case let .other(label):
            return .object(["other": .string(label)])
        }
    }
}

private final class TemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}
