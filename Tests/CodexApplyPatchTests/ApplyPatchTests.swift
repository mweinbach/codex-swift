import CodexApplyPatch
import XCTest

final class ApplyPatchTests: XCTestCase {
    func testParsePatchWithMultipleHunks() throws {
        let patch = """
        *** Begin Patch
        *** Add File: path/add.py
        +abc
        +def
        *** Delete File: path/delete.py
        *** Update File: path/update.py
        *** Move to: path/update2.py
        @@ def f():
        -    pass
        +    return 123
        *** End Patch
        """

        XCTAssertEqual(
            try ApplyPatch.parsePatch(patch).hunks,
            [
                .addFile(path: "path/add.py", contents: "abc\ndef\n"),
                .deleteFile(path: "path/delete.py"),
                .updateFile(
                    path: "path/update.py",
                    movePath: "path/update2.py",
                    chunks: [
                        UpdateFileChunk(
                            changeContext: "def f():",
                            oldLines: ["    pass"],
                            newLines: ["    return 123"],
                            isEndOfFile: false
                        )
                    ]
                )
            ]
        )
    }

    func testLenientHeredocParsing() throws {
        let patch = """
        <<'EOF'
        *** Begin Patch
        *** Update File: file2.py
         import foo
        +bar
        *** End Patch
        EOF
        """
        XCTAssertEqual(
            try ApplyPatch.parsePatch(patch).hunks,
            [
                .updateFile(
                    path: "file2.py",
                    movePath: nil,
                    chunks: [
                        UpdateFileChunk(
                            changeContext: nil,
                            oldLines: ["import foo"],
                            newLines: ["import foo", "bar"],
                            isEndOfFile: false
                        )
                    ]
                )
            ]
        )
    }

    func testApplyPatchAppliesMultipleOperations() throws {
        let dir = try TemporaryDirectory()
        let modify = dir.url.appendingPathComponent("modify.txt")
        let delete = dir.url.appendingPathComponent("delete.txt")
        try "line1\nline2\n".write(to: modify, atomically: true, encoding: .utf8)
        try "obsolete\n".write(to: delete, atomically: true, encoding: .utf8)

        let patch = """
        *** Begin Patch
        *** Add File: nested/new.txt
        +created
        *** Delete File: delete.txt
        *** Update File: modify.txt
        @@
        -line2
        +changed
        *** End Patch
        """

        let result = ApplyPatch.apply(patch, cwd: dir.url)
        XCTAssertEqual(result.stderr, "")
        XCTAssertEqual(
            result.stdout,
            "Success. Updated the following files:\nA nested/new.txt\nM modify.txt\nD delete.txt\n"
        )
        XCTAssertEqual(try String(contentsOf: dir.url.appendingPathComponent("nested/new.txt")), "created\n")
        XCTAssertEqual(try String(contentsOf: modify), "line1\nchanged\n")
        XCTAssertFalse(FileManager.default.fileExists(atPath: delete.path))
    }

    func testApplyPatchAppliesMultipleChunks() throws {
        let dir = try TemporaryDirectory()
        let target = dir.url.appendingPathComponent("multi.txt")
        try "line1\nline2\nline3\nline4\n".write(to: target, atomically: true, encoding: .utf8)

        let patch = """
        *** Begin Patch
        *** Update File: multi.txt
        @@
        -line2
        +changed2
        @@
        -line4
        +changed4
        *** End Patch
        """

        let result = ApplyPatch.apply(patch, cwd: dir.url)
        XCTAssertEqual(result.stderr, "")
        XCTAssertEqual(result.stdout, "Success. Updated the following files:\nM multi.txt\n")
        XCTAssertEqual(try String(contentsOf: target), "line1\nchanged2\nline3\nchanged4\n")
    }

    func testApplyPatchMovesFileToNewDirectory() throws {
        let dir = try TemporaryDirectory()
        let original = dir.url.appendingPathComponent("old/name.txt")
        let moved = dir.url.appendingPathComponent("renamed/dir/name.txt")
        try FileManager.default.createDirectory(at: original.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "old content\n".write(to: original, atomically: true, encoding: .utf8)

        let patch = """
        *** Begin Patch
        *** Update File: old/name.txt
        *** Move to: renamed/dir/name.txt
        @@
        -old content
        +new content
        *** End Patch
        """

        let result = ApplyPatch.apply(patch, cwd: dir.url)
        XCTAssertEqual(result.stderr, "")
        XCTAssertEqual(result.stdout, "Success. Updated the following files:\nM renamed/dir/name.txt\n")
        XCTAssertFalse(FileManager.default.fileExists(atPath: original.path))
        XCTAssertEqual(try String(contentsOf: moved), "new content\n")
    }

    func testApplyPatchReportsMissingContext() throws {
        let dir = try TemporaryDirectory()
        let target = dir.url.appendingPathComponent("modify.txt")
        try "line1\nline2\n".write(to: target, atomically: true, encoding: .utf8)

        let patch = """
        *** Begin Patch
        *** Update File: modify.txt
        @@
        -missing
        +changed
        *** End Patch
        """

        let result = ApplyPatch.apply(patch, cwd: dir.url)
        XCTAssertEqual(result.stdout, "")
        XCTAssertEqual(result.stderr, "Failed to find expected lines in modify.txt:\nmissing\n")
        XCTAssertEqual(try String(contentsOf: target), "line1\nline2\n")
    }

    func testApplyPatchRejectsEmptyUpdateHunk() {
        let result = ApplyPatch.apply("*** Begin Patch\n*** Update File: foo.txt\n*** End Patch")
        XCTAssertEqual(result.stderr, "Invalid patch hunk on line 2: Update file hunk for path 'foo.txt' is empty\n")
    }
}

private final class TemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}
