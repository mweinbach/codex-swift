import CodexApplyPatch
import XCTest

final class ApplyPatchInvocationTests: XCTestCase {
    func testDirectApplyPatchLiteralMatchesRustInvocationParser() {
        assertBody(
            maybeParseApplyPatch(["apply_patch", singleAddPatch]),
            workdir: nil
        )
    }

    func testDirectApplypatchAliasMatchesRustInvocationParser() {
        assertBody(
            maybeParseApplyPatch(["applypatch", singleAddPatch]),
            workdir: nil
        )
    }

    func testBashHeredocExtractsPatchBody() {
        assertBody(
            maybeParseApplyPatch(["bash", "-lc", heredocScript(prefix: "")]),
            workdir: nil
        )
    }

    func testBashNonLoginShellHeredocExtractsPatchBody() {
        assertBody(
            maybeParseApplyPatch(["bash", "-c", heredocScript(prefix: "")]),
            workdir: nil
        )
    }

    func testPowerShellAndCmdHeredocFormsReuseRustBashExtraction() {
        assertBody(
            maybeParseApplyPatch(["powershell.exe", "-Command", heredocScript(prefix: "")]),
            workdir: nil
        )
        assertBody(
            maybeParseApplyPatch(["powershell.exe", "-NoProfile", "-Command", heredocScript(prefix: "")]),
            workdir: nil
        )
        assertBody(
            maybeParseApplyPatch(["pwsh", "-NoProfile", "-Command", heredocScript(prefix: "")]),
            workdir: nil
        )
        assertBody(
            maybeParseApplyPatch(["cmd.exe", "/c", heredocScript(prefix: "cd foo && ")]),
            workdir: "foo"
        )
    }

    func testHeredocWithLeadingCDCapturesWorkdir() {
        assertBody(
            maybeParseApplyPatch(["bash", "-lc", heredocScript(prefix: "cd foo && ")]),
            workdir: "foo"
        )
    }

    func testQuotedCDPathsWithSpacesMatchRustBehavior() {
        assertBody(
            maybeParseApplyPatch(["bash", "-lc", heredocScript(prefix: "cd 'foo bar' && ")]),
            workdir: "foo bar"
        )
        assertBody(
            maybeParseApplyPatch(["bash", "-lc", heredocScript(prefix: #"cd "foo bar" && "#)]),
            workdir: "foo bar"
        )
    }

    func testUnsupportedShellFormsAreNotApplyPatchLikeRust() {
        assertNotApplyPatch(heredocScript(prefix: "cd foo; "))
        assertNotApplyPatch(heredocScript(prefix: "cd bar || "))
        assertNotApplyPatch(heredocScript(prefix: "cd bar | "))
        assertNotApplyPatch(heredocScript(prefix: "echo foo && "))
        assertNotApplyPatch(heredocScript(prefix: "cd foo && cd bar && "))
        assertNotApplyPatch(heredocScript(prefix: "cd foo bar && "))
        assertNotApplyPatch(heredocScript(prefix: "echo foo; cd bar && "))
        assertNotApplyPatch(heredocScript(prefix: "cd bar && ", suffix: " && echo done"))
    }

    func testApplyPatchWithArgumentBeforeHeredocIsIgnored() {
        let script = """
        apply_patch foo <<'PATCH'
        \(singleAddPatch)
        PATCH
        """

        XCTAssertEqual(maybeParseApplyPatch(["bash", "-lc", script]), .notApplyPatch)
    }

    func testMalformedHeredocReportsShellParseErrorAfterCommandMatch() {
        let script = """
        apply_patch <<'PATCH'
        \(singleAddPatch)
        """

        XCTAssertEqual(
            maybeParseApplyPatch(["bash", "-lc", script]),
            .shellParseError(.failedToFindHeredocBody)
        )
    }

    func testVerifiedRejectsImplicitPatchSingleArg() {
        XCTAssertEqual(
            maybeParseApplyPatchVerified([singleAddPatch], cwd: URL(fileURLWithPath: "/tmp/session")),
            .correctnessError(.implicitInvocation)
        )
    }

    func testVerifiedRejectsImplicitPatchShellScript() {
        XCTAssertEqual(
            maybeParseApplyPatchVerified(["bash", "-lc", singleAddPatch], cwd: URL(fileURLWithPath: "/tmp/session")),
            .correctnessError(.implicitInvocation)
        )
    }

    func testVerifiedResolvesRelativeUpdatePathsAgainstCWD() throws {
        let dir = try TemporaryDirectory()
        let file = dir.url.appendingPathComponent("source.txt")
        try "session directory content\n".write(to: file, atomically: true, encoding: .utf8)

        let patch = """
        *** Begin Patch
        *** Update File: source.txt
        @@
        -session directory content
        +updated session directory content
        *** End Patch
        """

        XCTAssertEqual(
            maybeParseApplyPatchVerified(["apply_patch", patch], cwd: dir.url),
            .body(ApplyPatchAction(
                changes: [
                    file.path: .update(
                        unifiedDiff: """
                        @@ -1 +1 @@
                        -session directory content
                        +updated session directory content

                        """,
                        movePath: nil,
                        newContent: "updated session directory content\n"
                    )
                ],
                patch: patch,
                cwd: dir.url.path
            ))
        )
    }

    func testVerifiedHeredocCDResolvesEffectiveCWDAndMovePath() throws {
        let dir = try TemporaryDirectory()
        let workdir = dir.url.appendingPathComponent("alt", isDirectory: true)
        try FileManager.default.createDirectory(at: workdir, withIntermediateDirectories: true)
        let source = workdir.appendingPathComponent("old.txt")
        let destination = workdir.appendingPathComponent("renamed.txt")
        try "before\n".write(to: source, atomically: true, encoding: .utf8)

        let patch = """
        *** Begin Patch
        *** Update File: old.txt
        *** Move to: renamed.txt
        @@
        -before
        +after
        *** End Patch
        """
        let script = "cd alt && apply_patch <<'PATCH'\n\(patch)\nPATCH"

        XCTAssertEqual(
            maybeParseApplyPatchVerified(["bash", "-lc", script], cwd: dir.url),
            .body(ApplyPatchAction(
                changes: [
                    source.path: .update(
                        unifiedDiff: """
                        @@ -1 +1 @@
                        -before
                        +after

                        """,
                        movePath: destination.path,
                        newContent: "after\n"
                    )
                ],
                patch: patch,
                cwd: workdir.path
            ))
        )
    }

    func testVerifiedNotApplyPatchPassthrough() {
        XCTAssertEqual(
            maybeParseApplyPatchVerified(["bash", "-lc", "echo hi"], cwd: URL(fileURLWithPath: "/tmp/session")),
            .notApplyPatch
        )
    }

    private var singleAddPatch: String {
        """
        *** Begin Patch
        *** Add File: foo
        +hi
        *** End Patch
        """
    }

    private func heredocScript(prefix: String, suffix: String = "") -> String {
        """
        \(prefix)apply_patch <<'PATCH'
        \(singleAddPatch)
        PATCH\(suffix)
        """
    }

    private func assertBody(
        _ result: MaybeApplyPatch,
        workdir: String?,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case let .body(args) = result else {
            XCTFail("expected body, got \(result)", file: file, line: line)
            return
        }

        XCTAssertEqual(args.workdir, workdir, file: file, line: line)
        XCTAssertEqual(args.patch, singleAddPatch, file: file, line: line)
        XCTAssertEqual(args.hunks, [.addFile(path: "foo", contents: "hi\n")], file: file, line: line)
    }

    private func assertNotApplyPatch(
        _ script: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(maybeParseApplyPatch(["bash", "-lc", script]), .notApplyPatch, file: file, line: line)
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
