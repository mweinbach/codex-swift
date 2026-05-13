import CodexApplyPatch
import XCTest

final class StreamingPatchParserTests: XCTestCase {
    func testStreamsCompleteLinesBeforeEndPatch() throws {
        var parser = StreamingPatchParser()
        XCTAssertEqual(
            try parser.pushDelta(delta: "*** Begin Patch\n*** Add File: src/hello.txt\n+hello\n+wor"),
            [
                .addFile(path: "src/hello.txt", contents: "hello\n")
            ]
        )
        XCTAssertEqual(
            try parser.pushDelta(delta: "ld\n"),
            [
                .addFile(path: "src/hello.txt", contents: "hello\nworld\n")
            ]
        )

        var updateParser = StreamingPatchParser()
        XCTAssertEqual(
            try updateParser.pushDelta(delta: """
            *** Begin Patch
            *** Update File: src/old.rs
            *** Move to: src/new.rs
            @@
            -old
            +new

            """),
            [
                .updateFile(
                    path: "src/old.rs",
                    movePath: "src/new.rs",
                    chunks: [
                        UpdateFileChunk(
                            changeContext: nil,
                            oldLines: ["old"],
                            newLines: ["new"],
                            isEndOfFile: false
                        )
                    ]
                )
            ]
        )

        var deleteParser = StreamingPatchParser()
        XCTAssertEqual(
            try deleteParser.pushDelta(delta: "*** Begin Patch\n*** Delete File: gone.txt"),
            []
        )
        XCTAssertEqual(
            try deleteParser.pushDelta(delta: "\n"),
            [
                .deleteFile(path: "gone.txt")
            ]
        )
    }

    func testLargePatchSplitByCharacterNeverLosesHunks() throws {
        let patch = """
        *** Begin Patch
        *** Add File: docs/release-notes.md
        +# Release notes
        +
        +## CLI
        +- Surface apply_patch progress while arguments stream.
        +- Keep final patch application gated on the completed tool call.
        +- Include file summaries in the progress event payload.
        *** Update File: src/config.rs
        @@ impl Config
        -    pub apply_patch_progress: bool,
        +    pub stream_apply_patch_progress: bool,
             pub include_diagnostics: bool,
        @@ fn default_progress_interval()
        -    Duration::from_millis(500)
        +    Duration::from_millis(250)
        *** Delete File: src/legacy_patch_progress.rs
        *** Update File: crates/cli/src/main.rs
        *** Move to: crates/cli/src/bin/codex.rs
        @@ fn run()
        -    let args = Args::parse();
        -    dispatch(args)
        +    let cli = Cli::parse();
        +    dispatch(cli)
        *** Add File: tests/fixtures/apply_patch_progress.json
        +{
        +  "type": "apply_patch_progress",
        +  "hunks": [
        +    { "operation": "add", "path": "docs/release-notes.md" },
        +    { "operation": "update", "path": "src/config.rs" }
        +  ]
        +}
        *** Update File: README.md
        @@ Development workflow
         Build the Rust workspace before opening a pull request.
        +When touching streamed tool calls, include parser coverage for partial input.
        +Prefer tests that exercise the exact event payload shape.
        *** Delete File: docs/old-apply-patch-progress.md
        *** End Patch
        """

        var parser = StreamingPatchParser()
        var maxHunkCount = 0
        var sawHunkCounts: [Int] = []
        var hunks: [Hunk] = []
        for character in patch {
            let updatedHunks = try parser.pushDelta(delta: String(character))
            if !updatedHunks.isEmpty {
                let hunkCount = updatedHunks.count
                XCTAssertGreaterThanOrEqual(hunkCount, maxHunkCount)
                if hunkCount > maxHunkCount {
                    sawHunkCounts.append(hunkCount)
                    maxHunkCount = hunkCount
                }
                hunks = updatedHunks
            }
        }

        XCTAssertEqual(sawHunkCounts, [1, 2, 3, 4, 5, 6, 7])
        XCTAssertEqual(hunks.count, 7)
        XCTAssertEqual(
            hunks.map(Self.kind),
            ["add", "update", "delete", "move-update", "add", "update", "delete"]
        )
    }

    func testKeepsIndentedUpdateMarkersAsContextLines() throws {
        var parser = StreamingPatchParser()
        XCTAssertEqual(
            try parser.pushDelta(delta: """
            *** Begin Patch
            *** Update File: a.txt
            @@
            -old a
            +new a
             *** Update File: b.txt
            @@
            -old b
            +new b
            *** End Patch

            """),
            [
                .updateFile(
                    path: "a.txt",
                    movePath: nil,
                    chunks: [
                        UpdateFileChunk(
                            changeContext: nil,
                            oldLines: ["old a", "*** Update File: b.txt"],
                            newLines: ["new a", "*** Update File: b.txt"],
                            isEndOfFile: false
                        ),
                        UpdateFileChunk(
                            changeContext: nil,
                            oldLines: ["old b"],
                            newLines: ["new b"],
                            isEndOfFile: false
                        )
                    ]
                )
            ]
        )
    }

    func testPreservesBareEmptyUpdateLines() throws {
        var parser = StreamingPatchParser()
        XCTAssertEqual(
            try parser.pushDelta(delta: """
            *** Begin Patch
            *** Update File: file.txt
            @@
             context before

             context after
            *** End Patch

            """),
            [
                .updateFile(
                    path: "file.txt",
                    movePath: nil,
                    chunks: [
                        UpdateFileChunk(
                            changeContext: nil,
                            oldLines: ["context before", "", "context after"],
                            newLines: ["context before", "", "context after"],
                            isEndOfFile: false
                        )
                    ]
                )
            ]
        )
    }

    func testMatchesLineEndingBehavior() throws {
        var parser = StreamingPatchParser()
        XCTAssertEqual(
            try parser.pushDelta(delta: "*** Begin Patch\r\n*** Update File: file.txt\r\n@@\r\n-old\r\n+new\r\n*** End Patch\r\n"),
            [
                .updateFile(
                    path: "file.txt",
                    movePath: nil,
                    chunks: [
                        UpdateFileChunk(
                            changeContext: nil,
                            oldLines: ["old"],
                            newLines: ["new"],
                            isEndOfFile: false
                        )
                    ]
                )
            ]
        )

        var embeddedCarriageReturnParser = StreamingPatchParser()
        XCTAssertEqual(
            try embeddedCarriageReturnParser.pushDelta(delta: "*** Begin Patch\r\n*** Update File: file.txt\r\n@@\r\n-old\r\r\n+new\r\n*** End Patch\r\n"),
            [
                .updateFile(
                    path: "file.txt",
                    movePath: nil,
                    chunks: [
                        UpdateFileChunk(
                            changeContext: nil,
                            oldLines: ["old\r"],
                            newLines: ["new"],
                            isEndOfFile: false
                        )
                    ]
                )
            ]
        )
    }

    func testFinishProcessesFinalLineWithoutNewline() throws {
        var parser = StreamingPatchParser()
        XCTAssertEqual(
            try parser.pushDelta(delta: "*** Begin Patch\n*** Add File: file.txt\n+hello\n*** End Patch"),
            [
                .addFile(path: "file.txt", contents: "hello\n")
            ]
        )
        XCTAssertEqual(
            try parser.finish(),
            [
                .addFile(path: "file.txt", contents: "hello\n")
            ]
        )
    }

    func testFinishRequiresEndPatch() throws {
        var parser = StreamingPatchParser()
        XCTAssertEqual(
            try parser.pushDelta(delta: "*** Begin Patch\n*** Add File: file.txt\n+hello\n"),
            [
                .addFile(path: "file.txt", contents: "hello\n")
            ]
        )
        XCTAssertThrowsError(try parser.finish()) { error in
            XCTAssertEqual(
                error as? ApplyPatchError,
                .invalidPatch("The last line of the patch must be '*** End Patch'")
            )
        }
    }

    func testReturnsRustShapedErrors() throws {
        var badStartParser = StreamingPatchParser()
        XCTAssertThrowsError(try badStartParser.pushDelta(delta: "bad\n")) { error in
            XCTAssertEqual(
                error as? ApplyPatchError,
                .invalidPatch("The first line of the patch must be '*** Begin Patch'")
            )
        }

        var badUpdateParser = StreamingPatchParser()
        XCTAssertEqual(try badUpdateParser.pushDelta(delta: "*** Begin Patch\n"), [])
        XCTAssertThrowsError(try badUpdateParser.pushDelta(delta: "bad\n")) { error in
            XCTAssertEqual(
                error as? ApplyPatchError,
                .invalidHunk(
                    message: "'bad' is not a valid hunk header. Valid hunk headers: '*** Add File: {path}', '*** Delete File: {path}', '*** Update File: {path}'",
                    lineNumber: 2
                )
            )
        }

        var emptyUpdateParser = StreamingPatchParser()
        XCTAssertThrowsError(
            try emptyUpdateParser.pushDelta(delta: "*** Begin Patch\n*** Update File: file.txt\n*** End Patch\n")
        ) { error in
            XCTAssertEqual(
                error as? ApplyPatchError,
                .invalidHunk(message: "Update file hunk for path 'file.txt' is empty", lineNumber: 2)
            )
        }
    }

    private static func kind(_ hunk: Hunk) -> String {
        switch hunk {
        case .addFile:
            return "add"
        case .deleteFile:
            return "delete"
        case let .updateFile(_, movePath, _):
            return movePath == nil ? "update" : "move-update"
        }
    }
}
