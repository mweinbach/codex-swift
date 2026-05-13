import CodexCore
import XCTest

final class MemoryWriteStorageTests: XCTestCase {
    private let fixedPrefix = "2025-02-11T15-35-19-jqmb"

    func testRolloutSummaryFileStemUsesUUIDTimestampAndHashWhenSlugMissing() throws {
        let memory = try stage1Output(rolloutSlug: nil)

        XCTAssertEqual(rolloutSummaryFileStem(memory), fixedPrefix)
    }

    func testRolloutSummaryFileStemSanitizesAndTruncatesSlugLikeRust() throws {
        let memory = try stage1Output(
            rolloutSlug: "Unsafe Slug/With Spaces & Symbols + EXTRA_LONG_12345_67890_ABCDE_fghij_klmno"
        )

        let stem = rolloutSummaryFileStem(memory)
        let slug = try XCTUnwrap(stem.dropFirst("\(fixedPrefix)-".count).nilIfEmpty)

        XCTAssertEqual(slug.count, 60)
        XCTAssertEqual(slug, "unsafe_slug_with_spaces___symbols___extra_long_12345_67890_a")
    }

    func testRolloutSummaryFileStemUsesUUIDTimestampAndHashWhenSlugIsEmpty() throws {
        let memory = try stage1Output(rolloutSlug: "")

        XCTAssertEqual(rolloutSummaryFileStem(memory), fixedPrefix)
    }

    func testSyncRolloutSummariesAndRawMemoriesFileKeepsLatestMemoriesOnly() throws {
        let root = try temporaryDirectory()
        try ensureMemoryLayout(root: root)

        let keepID = ThreadId()
        let dropID = ThreadId()
        let staleKeepPath = rolloutSummariesDirectory(root: root)
            .appendingPathComponent("\(keepID).md", isDirectory: false)
        let staleDropPath = rolloutSummariesDirectory(root: root)
            .appendingPathComponent("\(dropID).md", isDirectory: false)
        try "keep".write(to: staleKeepPath, atomically: true, encoding: .utf8)
        try "drop".write(to: staleDropPath, atomically: true, encoding: .utf8)

        let memory = Stage1Output(
            threadID: keepID,
            rolloutPath: "/tmp/rollout-100.jsonl",
            sourceUpdatedAt: Date(timeIntervalSince1970: 100),
            rawMemory: "\nraw memory\n",
            rolloutSummary: "short summary",
            cwd: "/tmp/workspace",
            generatedAt: Date(timeIntervalSince1970: 101)
        )

        try syncRolloutSummariesFromMemories(
            root: root,
            memories: [memory],
            maxRawMemoriesForConsolidation: 512
        )
        try rebuildRawMemoriesFileFromMemories(
            root: root,
            memories: [memory],
            maxRawMemoriesForConsolidation: 512
        )

        XCTAssertFalse(FileManager.default.fileExists(atPath: staleKeepPath.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: staleDropPath.path))

        let files = try FileManager.default.contentsOfDirectory(
            at: rolloutSummariesDirectory(root: root),
            includingPropertiesForKeys: nil
        )
        .map(\.lastPathComponent)
        .sorted()
        XCTAssertEqual(files.count, 1)

        let rawMemories = try String(contentsOf: rawMemoriesFile(root: root), encoding: .utf8)
        XCTAssertTrue(rawMemories.contains("raw memory"))
        XCTAssertTrue(rawMemories.contains(keepID.description))
        XCTAssertTrue(rawMemories.contains("updated_at: 1970-01-01T00:01:40+00:00"))
        XCTAssertTrue(rawMemories.contains("cwd: /tmp/workspace"))
        XCTAssertTrue(rawMemories.contains("rollout_path: /tmp/rollout-100.jsonl"))
        XCTAssertTrue(rawMemories.contains("rollout_summary_file: \(files[0])"))

        let rolloutSummary = try String(
            contentsOf: rolloutSummariesDirectory(root: root)
                .appendingPathComponent(files[0], isDirectory: false),
            encoding: .utf8
        )
        XCTAssertTrue(rolloutSummary.contains("thread_id: \(keepID)"))
        XCTAssertTrue(rolloutSummary.contains("short summary\n"))
    }

    func testRawMemoriesFileUsesRustEmptyPlaceholder() throws {
        let root = try temporaryDirectory()

        try rebuildRawMemoriesFileFromMemories(
            root: root,
            memories: [],
            maxRawMemoriesForConsolidation: 512
        )

        XCTAssertEqual(
            try String(contentsOf: rawMemoriesFile(root: root), encoding: .utf8),
            "# Raw Memories\n\nNo raw memories yet.\n"
        )
    }

    private func stage1Output(rolloutSlug: String?) throws -> Stage1Output {
        Stage1Output(
            threadID: try ThreadId(string: "0194f5a6-89ab-7cde-8123-456789abcdef"),
            rolloutPath: "/tmp/rollout.jsonl",
            sourceUpdatedAt: Date(timeIntervalSince1970: 123),
            rawMemory: "raw memory",
            rolloutSummary: "summary",
            rolloutSlug: rolloutSlug,
            cwd: "/tmp/workspace",
            generatedAt: Date(timeIntervalSince1970: 124)
        )
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-swift-memory-write-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

private extension Substring {
    var nilIfEmpty: String? {
        isEmpty ? nil : String(self)
    }
}
