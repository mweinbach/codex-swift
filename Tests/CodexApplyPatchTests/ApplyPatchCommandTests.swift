import CodexApplyPatch
import XCTest

final class ApplyPatchCommandTests: XCTestCase {
    func testStandaloneReadsPatchFromStdinWhenNoArgument() throws {
        let dir = try CommandTemporaryDirectory()
        let result = ApplyPatchCommand.runStandalone(
            arguments: [],
            stdin: { Data(addFilePatch.utf8) },
            cwd: dir.url
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stderr, "")
        XCTAssertEqual(result.stdout, "Success. Updated the following files:\nA created.txt\n")
        XCTAssertEqual(
            try String(contentsOf: dir.url.appendingPathComponent("created.txt"), encoding: .utf8),
            "hi\n"
        )
    }

    func testStandaloneRejectsEmptyStdinLikeRust() {
        let result = ApplyPatchCommand.runStandalone(arguments: [], stdin: { Data() })

        XCTAssertEqual(result.exitCode, 2)
        XCTAssertEqual(result.stdout, "")
        XCTAssertEqual(result.stderr, "Usage: apply_patch 'PATCH'\n       echo 'PATCH' | apply_patch\n")
    }

    func testStandaloneRejectsExtraArgumentsLikeRust() {
        let result = ApplyPatchCommand.runStandalone(
            arguments: [addFilePatch, "*** Begin Patch\n*** End Patch"],
            stdin: { Data() }
        )

        XCTAssertEqual(result.exitCode, 2)
        XCTAssertEqual(result.stdout, "")
        XCTAssertEqual(result.stderr, "Error: apply_patch accepts exactly one argument.\n")
    }

    func testArg0AliasDispatchesStandaloneCommand() throws {
        let dir = try CommandTemporaryDirectory()
        let result = ApplyPatchCommand.runForArg0Dispatch(
            argv0: "/tmp/applypatch",
            arguments: [addFilePatch],
            stdin: { Data() },
            cwd: dir.url
        )

        XCTAssertEqual(result?.exitCode, 0)
        XCTAssertEqual(result?.stderr, "")
        XCTAssertEqual(
            try String(contentsOf: dir.url.appendingPathComponent("created.txt"), encoding: .utf8),
            "hi\n"
        )
    }

    func testHiddenArgumentAppliesSecondArgumentAndIgnoresExtraArgumentsLikeRust() throws {
        let dir = try CommandTemporaryDirectory()
        let result = ApplyPatchCommand.runForArg0Dispatch(
            argv0: "/tmp/codex",
            arguments: [ApplyPatchCommand.hiddenArgument, addFilePatch, "ignored"],
            stdin: { Data("ignored".utf8) },
            cwd: dir.url
        )

        XCTAssertEqual(result?.exitCode, 0)
        XCTAssertEqual(result?.stderr, "")
        XCTAssertEqual(
            try String(contentsOf: dir.url.appendingPathComponent("created.txt"), encoding: .utf8),
            "hi\n"
        )
    }

    func testHiddenArgumentReportsMissingPatchArgumentLikeRust() {
        let result = ApplyPatchCommand.runForArg0Dispatch(
            argv0: "/tmp/codex",
            arguments: [ApplyPatchCommand.hiddenArgument],
            stdin: { Data() }
        )

        XCTAssertEqual(result?.exitCode, 1)
        XCTAssertEqual(result?.stdout, "")
        XCTAssertEqual(
            result?.stderr,
            "Error: \(ApplyPatchCommand.hiddenArgument) requires a UTF-8 PATCH argument.\n"
        )
    }

    func testNonApplyPatchInvocationDoesNotDispatch() {
        XCTAssertNil(ApplyPatchCommand.runForArg0Dispatch(
            argv0: "/tmp/codex",
            arguments: ["exec", "hello"],
            stdin: { Data() }
        ))
    }

    func testPrependPathEntryCreatesAliasesAndPrependsPath() throws {
        let executable = URL(fileURLWithPath: "/tmp/codex")
        var capturedPATH: String?

        let aliases = try ApplyPatchCommand.prependPathEntryForCodexAliases(
            currentExecutable: executable,
            existingPATH: "/bin:/usr/bin",
            setPATH: { capturedPATH = $0 }
        )

        XCTAssertEqual(capturedPATH, "\(aliases.url.path):/bin:/usr/bin")
        XCTAssertEqual(
            try FileManager.default.destinationOfSymbolicLink(
                atPath: aliases.url.appendingPathComponent("apply_patch").path
            ),
            executable.path
        )
        XCTAssertEqual(
            try FileManager.default.destinationOfSymbolicLink(
                atPath: aliases.url.appendingPathComponent("applypatch").path
            ),
            executable.path
        )
    }

    func testPrependPathEntryUsesDirectoryOnlyWhenPathIsMissing() throws {
        var capturedPATH: String?

        let aliases = try ApplyPatchCommand.prependPathEntryForCodexAliases(
            currentExecutable: URL(fileURLWithPath: "/tmp/codex"),
            existingPATH: nil,
            setPATH: { capturedPATH = $0 }
        )

        XCTAssertEqual(capturedPATH, aliases.url.path)
    }
}

private let addFilePatch = """
*** Begin Patch
*** Add File: created.txt
+hi
*** End Patch
"""

private final class CommandTemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}
