import CodexCore
import XCTest

final class PersonalityMigrationTests: XCTestCase {
    func testMigrationMarkerExistsNoSessionsNoChange() throws {
        let temp = try PersonalityMigrationTemporaryDirectory()
        try "v1\n".write(to: temp.marker, atomically: true, encoding: .utf8)
        try #"profile = "missing""#.write(to: temp.config, atomically: true, encoding: .utf8)

        let status = try PersonalityMigration.maybeMigratePersonality(codexHome: temp.url)

        XCTAssertEqual(status, .skippedMarker)
        XCTAssertEqual(try String(contentsOf: temp.config, encoding: .utf8), #"profile = "missing""#)
    }

    func testNoMarkerNoSessionsNoChange() throws {
        let temp = try PersonalityMigrationTemporaryDirectory()
        try #"model = "gpt-5.4""#.write(to: temp.config, atomically: true, encoding: .utf8)

        let status = try PersonalityMigration.maybeMigratePersonality(codexHome: temp.url)

        XCTAssertEqual(status, .skippedNoSessions)
        XCTAssertEqual(try String(contentsOf: temp.marker, encoding: .utf8), "v1\n")
        let config = try String(contentsOf: temp.config, encoding: .utf8)
        XCTAssertFalse(config.contains("personality"))
        XCTAssertTrue(config.contains(#"model = "gpt-5.4""#))
    }

    func testNoMarkerSessionsSetsPersonalityAndPreservesExistingFields() throws {
        let temp = try PersonalityMigrationTemporaryDirectory()
        try """
        model = "gpt-5.4"
        model_provider = "openai"
        """.write(to: temp.config, atomically: true, encoding: .utf8)
        try writeSession(codexHome: temp.url)

        let status = try PersonalityMigration.maybeMigratePersonality(codexHome: temp.url)

        XCTAssertEqual(status, .applied)
        XCTAssertEqual(try String(contentsOf: temp.marker, encoding: .utf8), "v1\n")
        let config = try String(contentsOf: temp.config, encoding: .utf8)
        XCTAssertTrue(config.contains(#"model = "gpt-5.4""#))
        XCTAssertTrue(config.contains(#"model_provider = "openai""#))
        XCTAssertTrue(config.contains(#"personality = "pragmatic""#))
    }

    func testNoMarkerMetaOnlyRolloutIsTreatedAsNoSessions() throws {
        let temp = try PersonalityMigrationTemporaryDirectory()
        try writeSession(codexHome: temp.url, includeUserMessage: false)

        let status = try PersonalityMigration.maybeMigratePersonality(codexHome: temp.url)

        XCTAssertEqual(status, .skippedNoSessions)
        XCTAssertFalse(FileManager.default.fileExists(atPath: temp.config.path))
        XCTAssertEqual(try String(contentsOf: temp.marker, encoding: .utf8), "v1\n")
    }

    func testNoMarkerExplicitGlobalPersonalitySkipsMigration() throws {
        let temp = try PersonalityMigrationTemporaryDirectory()
        try #"personality = "friendly""#.write(to: temp.config, atomically: true, encoding: .utf8)
        try writeSession(codexHome: temp.url)

        let status = try PersonalityMigration.maybeMigratePersonality(codexHome: temp.url)

        XCTAssertEqual(status, .skippedExplicitPersonality)
        XCTAssertEqual(try String(contentsOf: temp.marker, encoding: .utf8), "v1\n")
        XCTAssertEqual(try String(contentsOf: temp.config, encoding: .utf8), #"personality = "friendly""#)
    }

    func testNoMarkerProfilePersonalitySkipsMigration() throws {
        let temp = try PersonalityMigrationTemporaryDirectory()
        try """
        profile = "work"

        [profiles.work]
        personality = "friendly"
        """.write(to: temp.config, atomically: true, encoding: .utf8)
        try writeSession(codexHome: temp.url)

        let status = try PersonalityMigration.maybeMigratePersonality(codexHome: temp.url)

        XCTAssertEqual(status, .skippedExplicitPersonality)
        XCTAssertEqual(try String(contentsOf: temp.marker, encoding: .utf8), "v1\n")
        XCTAssertFalse(try String(contentsOf: temp.config, encoding: .utf8).contains(#"personality = "pragmatic""#))
    }

    func testInvalidSelectedProfileReturnsErrorAndDoesNotWriteMarker() throws {
        let temp = try PersonalityMigrationTemporaryDirectory()
        try #"profile = "missing""#.write(to: temp.config, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try PersonalityMigration.maybeMigratePersonality(codexHome: temp.url)) { error in
            XCTAssertEqual(String(describing: error), "config profile `missing` not found")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: temp.marker.path))
    }

    func testAppliedMigrationIsIdempotentOnSecondRun() throws {
        let temp = try PersonalityMigrationTemporaryDirectory()
        try writeSession(codexHome: temp.url)

        XCTAssertEqual(try PersonalityMigration.maybeMigratePersonality(codexHome: temp.url), .applied)
        let firstConfig = try String(contentsOf: temp.config, encoding: .utf8)
        XCTAssertEqual(try PersonalityMigration.maybeMigratePersonality(codexHome: temp.url), .skippedMarker)
        XCTAssertEqual(try String(contentsOf: temp.config, encoding: .utf8), firstConfig)
    }

    func testNoMarkerArchivedSessionsSetsPersonality() throws {
        let temp = try PersonalityMigrationTemporaryDirectory()
        try writeSession(codexHome: temp.url, archived: true)

        let status = try PersonalityMigration.maybeMigratePersonality(codexHome: temp.url)

        XCTAssertEqual(status, .applied)
        XCTAssertTrue(try String(contentsOf: temp.config, encoding: .utf8).contains(#"personality = "pragmatic""#))
        XCTAssertEqual(try String(contentsOf: temp.marker, encoding: .utf8), "v1\n")
    }

    private func writeSession(
        codexHome: URL,
        archived: Bool = false,
        includeUserMessage: Bool = true
    ) throws {
        let timestamp = "2026-05-12T10-11-12"
        let id = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000123"))
        let root = codexHome
            .appendingPathComponent(archived ? RolloutErrors.archivedSessionsSubdirectory : RolloutListing.sessionsSubdirectory, isDirectory: true)
            .appendingPathComponent("2026", isDirectory: true)
            .appendingPathComponent("05", isDirectory: true)
            .appendingPathComponent("12", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("rollout-\(timestamp)-\(id.uuidString.lowercased()).jsonl")
        var lines = [
            try encodeLine(RolloutLine(
                timestamp: "2026-05-12T10:11:12.000Z",
                item: .sessionMeta(SessionMetaLine(meta: SessionMeta(
                    id: try ConversationId(string: id.uuidString.lowercased()),
                    timestamp: "2026-05-12T10:11:12.000Z",
                    cwd: "/repo",
                    originator: "codex_swift",
                    cliVersion: "0.1.0",
                    source: .cli,
                    modelProvider: "openai"
                )))
            ))
        ]
        if includeUserMessage {
            lines.append(try encodeLine(RolloutLine(
                timestamp: "2026-05-12T10:11:13.000Z",
                item: .eventMsg(.userMessage(UserMessageEvent(message: "hello")))
            )))
        }
        try (lines.joined(separator: "\n") + "\n").write(to: file, atomically: true, encoding: .utf8)
    }

    private func encodeLine<T: Encodable>(_ value: T) throws -> String {
        let data = try JSONEncoder().encode(value)
        return try XCTUnwrap(String(data: data, encoding: .utf8))
    }
}

private final class PersonalityMigrationTemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    var config: URL {
        url.appendingPathComponent("config.toml", isDirectory: false)
    }

    var marker: URL {
        url.appendingPathComponent(PersonalityMigration.markerFilename, isDirectory: false)
    }
}
