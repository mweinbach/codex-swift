@testable import CodexCore
import XCTest

final class MemoryWriteWorkspaceTests: XCTestCase {
    func testResetMemoryWorkspaceBaselineRemovesGeneratedDiff() throws {
        let root = try temporaryDirectory().appendingPathComponent("memories", isDirectory: true)
        try prepareMemoryWorkspace(root: root)
        try "memory".write(
            to: root.appendingPathComponent("MEMORY.md", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        try writeMemoryWorkspaceDiff(
            root: root,
            diff: MemoryWorkspaceDiff(
                changes: [MemoryWorkspaceChange(status: .added, path: "MEMORY.md")],
                unifiedDiff: "+memory\n"
            )
        )

        try resetMemoryWorkspaceBaseline(root: root)

        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent(memoryWorkspaceDiffFilename, isDirectory: false).path
            )
        )
        XCTAssertEqual(try memoryWorkspaceDiff(root: root).changes, [])
    }

    func testPrepareMemoryWorkspaceRecoversUnusableGitDirectory() throws {
        let root = try temporaryDirectory().appendingPathComponent("memories", isDirectory: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent(".git", isDirectory: true),
            withIntermediateDirectories: true
        )
        try "memory".write(
            to: root.appendingPathComponent("MEMORY.md", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )

        try prepareMemoryWorkspace(root: root)

        XCTAssertEqual(try memoryWorkspaceDiff(root: root).changes, [])
        XCTAssertEqual(try gitStdout(root: root, args: ["status", "--porcelain"]), "")
        XCTAssertEqual(try gitStdout(root: root, args: ["ls-files"]), "MEMORY.md\n")
    }

    func testWorkspaceDiffReportsAddedModifiedAndDeletedFiles() throws {
        let root = try temporaryDirectory().appendingPathComponent("memories", isDirectory: true)
        let summaries = root.appendingPathComponent("rollout_summaries", isDirectory: true)
        try FileManager.default.createDirectory(at: summaries, withIntermediateDirectories: true)
        try "old".write(
            to: root.appendingPathComponent("MEMORY.md", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        try """
        thread_id: 00000000-0000-4000-8000-000000000001
        important stale evidence
        """.write(
            to: summaries.appendingPathComponent("deleted.md", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        try resetMemoryWorkspaceBaseline(root: root)

        try "new".write(
            to: root.appendingPathComponent("MEMORY.md", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        try "summary".write(
            to: root.appendingPathComponent("memory_summary.md", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        try FileManager.default.removeItem(at: summaries.appendingPathComponent("deleted.md", isDirectory: false))

        let diff = try memoryWorkspaceDiff(root: root)

        XCTAssertEqual(
            diff.changes,
            [
                MemoryWorkspaceChange(status: .modified, path: "MEMORY.md"),
                MemoryWorkspaceChange(status: .added, path: "memory_summary.md"),
                MemoryWorkspaceChange(status: .deleted, path: "rollout_summaries/deleted.md")
            ]
        )
        XCTAssertTrue(diff.unifiedDiff.contains("diff --git a/MEMORY.md b/MEMORY.md"))
        XCTAssertTrue(diff.unifiedDiff.contains("-old"))
        XCTAssertTrue(diff.unifiedDiff.contains("+new"))
        XCTAssertTrue(diff.unifiedDiff.contains("diff --git a/memory_summary.md b/memory_summary.md"))
        XCTAssertTrue(diff.unifiedDiff.contains("+summary"))
        XCTAssertTrue(
            diff.unifiedDiff.contains(
                "diff --git a/rollout_summaries/deleted.md b/rollout_summaries/deleted.md"
            )
        )
        XCTAssertTrue(diff.unifiedDiff.contains("deleted file mode 100644"))
        XCTAssertTrue(diff.unifiedDiff.contains("-thread_id: 00000000-0000-4000-8000-000000000001"))
        XCTAssertTrue(diff.unifiedDiff.contains("-important stale evidence"))
    }

    func testMemoryWorkspaceDiffRemovesStaleGeneratedDiffArtifact() throws {
        let root = try temporaryDirectory().appendingPathComponent("memories", isDirectory: true)
        try resetMemoryWorkspaceBaseline(root: root)
        let stalePath = root.appendingPathComponent(memoryWorkspaceDiffFilename, isDirectory: false)
        try "stale".write(to: stalePath, atomically: true, encoding: .utf8)

        let diff = try memoryWorkspaceDiff(root: root)

        XCTAssertFalse(FileManager.default.fileExists(atPath: stalePath.path))
        XCTAssertEqual(diff.changes, [])
    }

    func testMemoryWorkspaceDiffIgnoresConfiguredHooksPathLikeRust() throws {
        #if os(Windows)
        throw XCTSkip("POSIX hook scripts are not used on Windows")
        #else
        let root = try temporaryDirectory().appendingPathComponent("memories", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "memory".write(
            to: root.appendingPathComponent("MEMORY.md", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        try resetMemoryWorkspaceBaseline(root: root)

        let marker = root.appendingPathComponent("post-index-change-ran", isDirectory: false)
        let hooksDirectory = root.appendingPathComponent(".git/hooks-path-test", isDirectory: true)
        try FileManager.default.createDirectory(at: hooksDirectory, withIntermediateDirectories: true)
        let hook = hooksDirectory.appendingPathComponent("post-index-change", isDirectory: false)
        let markerPath = marker.path.replacingOccurrences(of: "'", with: "'\\''")
        try """
        #!/bin/sh
        printf hook > '\(markerPath)'
        """.write(to: hook, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hook.path)
        _ = try gitStdout(root: root, args: ["config", "core.hooksPath", hooksDirectory.path])

        try FileManager.default.setAttributes(
            [.modificationDate: Date()],
            ofItemAtPath: root.appendingPathComponent("MEMORY.md", isDirectory: false).path
        )

        XCTAssertEqual(try memoryWorkspaceDiff(root: root).changes, [])
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: marker.path),
            "memory workspace git helpers should disable configured hooks for internal git status calls"
        )
        #endif
    }

    func testWriteMemoryWorkspaceDiffWritesRenderedArtifact() throws {
        let root = try temporaryDirectory().appendingPathComponent("memories", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        try writeMemoryWorkspaceDiff(
            root: root,
            diff: MemoryWorkspaceDiff(
                changes: [MemoryWorkspaceChange(status: .modified, path: "MEMORY.md")],
                unifiedDiff: "-old\n+new\n"
            )
        )

        let content = try String(
            contentsOf: root.appendingPathComponent(memoryWorkspaceDiffFilename, isDirectory: false),
            encoding: .utf8
        )
        XCTAssertTrue(content.contains("- M MEMORY.md"))
        XCTAssertTrue(content.contains("-old\n+new\n"))
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-swift-memory-workspace-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func gitStdout(root: URL, args: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git"] + args
        process.currentDirectoryURL = root
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(
            process.terminationStatus,
            0,
            String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        )
        return String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }
}
