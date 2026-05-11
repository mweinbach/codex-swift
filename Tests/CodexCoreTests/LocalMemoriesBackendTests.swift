import CodexCore
import Foundation
import XCTest

final class LocalMemoriesBackendTests: XCTestCase {
    func testListReturnsShallowVisibleMemoryPaths() throws {
        let temp = try TemporaryDirectory()
        try FileManager.default.createDirectory(
            at: temp.url.appendingPathComponent("skills/example", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: temp.url.appendingPathComponent(".git", isDirectory: true),
            withIntermediateDirectories: true
        )
        try "summary".write(
            to: temp.url.appendingPathComponent("MEMORY.md", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        try "metadata".write(
            to: temp.url.appendingPathComponent(".DS_Store", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )

        let response = try LocalMemoriesBackend(memoryRoot: temp.url).list(ListMemoriesRequest())

        XCTAssertEqual(
            response.entries,
            [
                MemoryEntry(path: "MEMORY.md", entryType: .file),
                MemoryEntry(path: "skills", entryType: .directory)
            ]
        )
        XCTAssertNil(response.nextCursor)
        XCTAssertFalse(response.truncated)
    }

    func testListSupportsPaginationAndCursorValidation() throws {
        let temp = try TemporaryDirectory()
        try FileManager.default.createDirectory(at: temp.url.appendingPathComponent("skills", isDirectory: true), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: temp.url.appendingPathComponent("rollout_summaries", isDirectory: true), withIntermediateDirectories: true)
        try "summary".write(to: temp.url.appendingPathComponent("MEMORY.md", isDirectory: false), atomically: true, encoding: .utf8)
        try "summary".write(to: temp.url.appendingPathComponent("memory_summary.md", isDirectory: false), atomically: true, encoding: .utf8)

        let backend = LocalMemoriesBackend(memoryRoot: temp.url)
        let page1 = try backend.list(ListMemoriesRequest(maxResults: 2))
        XCTAssertEqual(page1.entries.map { $0.path }, ["MEMORY.md", "memory_summary.md"])
        XCTAssertEqual(page1.nextCursor, "2")
        XCTAssertTrue(page1.truncated)

        let page2 = try backend.list(ListMemoriesRequest(cursor: page1.nextCursor, maxResults: 2))
        XCTAssertEqual(page2.entries.map { $0.path }, ["rollout_summaries", "skills"])
        XCTAssertNil(page2.nextCursor)
        XCTAssertFalse(page2.truncated)

        XCTAssertThrowsError(try backend.list(ListMemoriesRequest(cursor: "bogus"))) { error in
            XCTAssertEqual(error as? MemoriesBackendError, .invalidCursor(cursor: "bogus", reason: "must be a non-negative integer"))
        }
        XCTAssertThrowsError(try backend.list(ListMemoriesRequest(cursor: "5"))) { error in
            XCTAssertEqual(error as? MemoriesBackendError, .invalidCursor(cursor: "5", reason: "exceeds result count"))
        }
    }

    func testReadSupportsOffsetsLimitsAndHiddenPathRejection() throws {
        let temp = try TemporaryDirectory()
        try FileManager.default.createDirectory(at: temp.url.appendingPathComponent(".git", isDirectory: true), withIntermediateDirectories: true)
        try "alpha\nbeta\ngamma\n".write(
            to: temp.url.appendingPathComponent("MEMORY.md", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        try "hidden".write(
            to: temp.url.appendingPathComponent(".git/HEAD", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )

        let backend = LocalMemoriesBackend(memoryRoot: temp.url)
        XCTAssertEqual(
            try backend.read(ReadMemoryRequest(path: "MEMORY.md", lineOffset: 2, maxLines: 1)),
            ReadMemoryResponse(path: "MEMORY.md", startLineNumber: 2, content: "beta\n", truncated: true)
        )
        XCTAssertThrowsError(try backend.read(ReadMemoryRequest(path: ".git/HEAD"))) { error in
            XCTAssertEqual(error as? MemoriesBackendError, .notFound(path: ".git/HEAD"))
        }
        XCTAssertThrowsError(try backend.read(ReadMemoryRequest(path: "MEMORY.md", lineOffset: 5))) { error in
            XCTAssertEqual(error as? MemoriesBackendError, .lineOffsetExceedsFileLength)
        }
    }

    func testSearchSupportsRustMatchModesAndScopedFiles() throws {
        let temp = try TemporaryDirectory()
        try FileManager.default.createDirectory(at: temp.url.appendingPathComponent("rollout_summaries", isDirectory: true), withIntermediateDirectories: true)
        try "Alpha value\nbeta nearby\ngamma\n".write(
            to: temp.url.appendingPathComponent("MEMORY.md", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        try "needle again\n".write(
            to: temp.url.appendingPathComponent("rollout_summaries/a.jsonl", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )

        let backend = LocalMemoriesBackend(memoryRoot: temp.url)
        let any = try backend.search(SearchMemoriesRequest(queries: ["needle"]))
        XCTAssertEqual(any.matches.map { $0.path }, ["rollout_summaries/a.jsonl"])
        XCTAssertEqual(any.matches.first?.matchLineNumber, 1)

        let normalized = try backend.search(SearchMemoriesRequest(
            queries: ["alphavalue", "beta"],
            matchMode: SearchMatchMode.allWithinLines(lineCount: 2),
            contextLines: 1,
            caseSensitive: false,
            normalized: true
        ))
        XCTAssertEqual(
            normalized.matches,
            [
                MemorySearchMatch(
                    path: "MEMORY.md",
                    matchLineNumber: 1,
                    contentStartLineNumber: 1,
                    content: "Alpha value\nbeta nearby\ngamma",
                    matchedQueries: ["alphavalue", "beta"]
                )
            ]
        )
    }

    func testPathsStayInsideMemoryRootAndRejectSymlinks() throws {
        let temp = try TemporaryDirectory()
        try "summary".write(
            to: temp.url.appendingPathComponent("MEMORY.md", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        let link = temp.url.appendingPathComponent("linked.md", isDirectory: false)
        try FileManager.default.createSymbolicLink(
            at: link,
            withDestinationURL: temp.url.appendingPathComponent("MEMORY.md", isDirectory: false)
        )

        let backend = LocalMemoriesBackend(memoryRoot: temp.url)
        XCTAssertThrowsError(try backend.list(ListMemoriesRequest(path: "../outside"))) { error in
            XCTAssertEqual(
                error as? MemoriesBackendError,
                .invalidPath(path: "../outside", reason: "must stay within the memories root")
            )
        }
        XCTAssertThrowsError(try backend.read(ReadMemoryRequest(path: "linked.md"))) { error in
            XCTAssertEqual(error as? MemoriesBackendError, .invalidPath(path: "linked.md", reason: "must not be a symlink"))
        }
    }
}

private final class TemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-swift-local-memories-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}
