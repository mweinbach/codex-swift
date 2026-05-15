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
        XCTAssertEqual(result.stdout, "Success. Updated the following files:\nM old/name.txt\n")
        XCTAssertEqual(
            result.delta,
            AppliedPatchDelta(
                changes: [
                    AppliedPatchChange(
                        path: original.path,
                        change: .update(
                            movePath: moved.path,
                            originalContent: "old content\n",
                            overwrittenMoveContent: nil,
                            newContent: "new content\n"
                        )
                    )
                ],
                exact: true
            )
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: original.path))
        XCTAssertEqual(try String(contentsOf: moved), "new content\n")
    }

    func testApplyPatchFailedMovePreservesCommittedDestinationDelta() throws {
        let dir = try TemporaryDirectory()
        let locked = dir.url.appendingPathComponent("locked", isDirectory: true)
        let output = dir.url.appendingPathComponent("out", isDirectory: true)
        let original = locked.appendingPathComponent("source.txt")
        let moved = output.appendingPathComponent("dest.txt")
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try "line\n".write(to: original, atomically: true, encoding: .utf8)
        try setPosixPermissions(0o555, at: locked)
        defer {
            try? setPosixPermissions(0o755, at: locked)
        }

        let patch = """
        *** Begin Patch
        *** Update File: locked/source.txt
        *** Move to: out/dest.txt
        @@
        -line
        +line2
        *** End Patch
        """

        let result = ApplyPatch.apply(patch, cwd: dir.url)
        XCTAssertEqual(result.stdout, "")
        XCTAssertTrue(result.stderr.contains("Failed to remove original \(original.path)"))
        XCTAssertEqual(
            result.delta,
            AppliedPatchDelta(
                changes: [
                    AppliedPatchChange(
                        path: moved.path,
                        change: .add(content: "line2\n", overwrittenContent: nil)
                    )
                ],
                exact: true
            )
        )
        XCTAssertEqual(try String(contentsOf: original), "line\n")
        XCTAssertEqual(try String(contentsOf: moved), "line2\n")
    }

    func testApplyPatchWriteFailureMarksCommittedDeltaInexact() throws {
        let dir = try TemporaryDirectory()
        let locked = dir.url.appendingPathComponent("locked", isDirectory: true)
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        try setPosixPermissions(0o555, at: locked)
        defer {
            try? setPosixPermissions(0o755, at: locked)
        }

        let patch = """
        *** Begin Patch
        *** Add File: locked/new.txt
        +after
        *** End Patch
        """

        let result = ApplyPatch.apply(patch, cwd: dir.url)
        XCTAssertEqual(result.stdout, "")
        XCTAssertTrue(result.stderr.contains("Failed to write file"))
        XCTAssertEqual(result.delta, AppliedPatchDelta(changes: [], exact: false))
    }

    func testApplyPatchDeleteSymlinkReturnsInexactDeltaLikeRust() throws {
        let dir = try TemporaryDirectory()
        let target = dir.url.appendingPathComponent("target.txt")
        let link = dir.url.appendingPathComponent("link.txt")
        try "target\n".write(to: target, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        let patch = """
        *** Begin Patch
        *** Delete File: link.txt
        *** End Patch
        """

        let result = ApplyPatch.apply(patch, cwd: dir.url)
        XCTAssertEqual(result.stderr, "")
        XCTAssertEqual(result.stdout, "Success. Updated the following files:\nD link.txt\n")
        XCTAssertFalse(result.delta.isExact)
        XCTAssertFalse(FileManager.default.fileExists(atPath: link.path))
        XCTAssertEqual(try String(contentsOf: target), "target\n")
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

    func testApplyPatchFindsExpectedLinesWithRustSeekSequenceLenience() throws {
        let dir = try TemporaryDirectory()

        let trailing = dir.url.appendingPathComponent("trailing.txt")
        try "foo   \nbar\t\t\n".write(to: trailing, atomically: true, encoding: .utf8)
        let trailingPatch = """
        *** Begin Patch
        *** Update File: trailing.txt
        @@
        -foo
        -bar
        +FOO
        +BAR
        *** End Patch
        """

        let trailingResult = ApplyPatch.apply(trailingPatch, cwd: dir.url)
        XCTAssertEqual(trailingResult.stderr, "")
        XCTAssertEqual(try String(contentsOf: trailing), "FOO\nBAR\n")

        let trimmed = dir.url.appendingPathComponent("trimmed.txt")
        try "    foo   \n   bar\t\n".write(to: trimmed, atomically: true, encoding: .utf8)
        let trimmedPatch = """
        *** Begin Patch
        *** Update File: trimmed.txt
        @@
        -foo
        -bar
        +FOO
        +BAR
        *** End Patch
        """

        let trimmedResult = ApplyPatch.apply(trimmedPatch, cwd: dir.url)
        XCTAssertEqual(trimmedResult.stderr, "")
        XCTAssertEqual(try String(contentsOf: trimmed), "FOO\nBAR\n")

        let unicode = dir.url.appendingPathComponent("unicode.txt")
        try "import asyncio  # local import \u{2013} avoids top\u{2011}level dep\n"
            .write(to: unicode, atomically: true, encoding: .utf8)
        let unicodePatch = """
        *** Begin Patch
        *** Update File: unicode.txt
        @@
        -import asyncio  # local import - avoids top-level dep
        +import asyncio  # HELLO
        *** End Patch
        """

        let unicodeResult = ApplyPatch.apply(unicodePatch, cwd: dir.url)
        XCTAssertEqual(unicodeResult.stderr, "")
        XCTAssertEqual(try String(contentsOf: unicode), "import asyncio  # HELLO\n")
    }

    func testApplyPatchRejectsEmptyUpdateHunk() {
        let result = ApplyPatch.apply("*** Begin Patch\n*** Update File: foo.txt\n*** End Patch")
        XCTAssertEqual(result.stderr, "Invalid patch hunk on line 2: Update file hunk for path 'foo.txt' is empty\n")
    }

    func testParsePatchReturnsRustShapedUpdateChunkErrors() {
        assertParsePatchError(
            """
            *** Begin Patch
            *** Update File: file.txt
            @@
            *** End Patch
            """,
            .invalidHunk(message: "Update hunk does not contain any lines", lineNumber: 4)
        )

        assertParsePatchError(
            """
            *** Begin Patch
            *** Update File: file.txt
            @@
            bad
            *** End Patch
            """,
            .invalidHunk(
                message: "Unexpected line found in update hunk: 'bad'. Every line should start with ' ' (context line), '+' (added line), or '-' (removed line)",
                lineNumber: 4
            )
        )

        assertParsePatchError(
            """
            *** Begin Patch
            *** Update File: file.txt
            @@
            *** End of File
            *** End Patch
            """,
            .invalidHunk(message: "Update hunk does not contain any lines", lineNumber: 4)
        )

        assertParsePatchError(
            """
            *** Begin Patch
            *** Update File: file.txt
            @@
            -old
            bad
            *** End Patch
            """,
            .invalidHunk(
                message: "Expected update hunk to start with a @@ context marker, got: 'bad'",
                lineNumber: 5
            )
        )

        assertParsePatchError(
            """
            *** Begin Patch
            *** Update File: file.txt
            @@
            *** Update File: other.txt
            *** End Patch
            """,
            .invalidHunk(
                message: "Unexpected line found in update hunk: '*** Update File: other.txt'. Every line should start with ' ' (context line), '+' (added line), or '-' (removed line)",
                lineNumber: 4
            )
        )
    }

    private func assertParsePatchError(
        _ patch: String,
        _ expectedError: ApplyPatchError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try ApplyPatch.parsePatch(patch), file: file, line: line) { error in
            XCTAssertEqual(error as? ApplyPatchError, expectedError, file: file, line: line)
        }
    }

    private func setPosixPermissions(_ permissions: Int, at url: URL) throws {
        try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: url.path)
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
