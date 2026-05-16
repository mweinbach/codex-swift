import CodexGit
import XCTest

final class ApplyGitPatchTests: XCTestCase {
    func testExtractPathsFromPatch() {
        let diff = """
        diff --git a/Sources/Old.swift b/Sources/New.swift
        index 1111111..2222222 100644
        --- a/Sources/Old.swift
        +++ b/Sources/New.swift
        diff --git a/README.md b/README.md
        index 3333333..4444444 100644
        --- a/README.md
        +++ b/README.md
        """
        XCTAssertEqual(CodexGit.extractPaths(fromPatch: diff), ["README.md", "Sources/New.swift", "Sources/Old.swift"])
    }

    func testParseGitApplyOutputGroupsPaths() {
        let parsed = CodexGit.parseGitApplyOutput(
            stdout: """
            Applied patch to clean.txt cleanly.
            Applied patch to conflict.txt with conflicts.
            Applying patch rejected.txt with 2 rejects...
            U unmerged.txt
            """,
            stderr: """
            Checking patch fallback.txt...
            Failed to perform three-way merge...
            error: patch failed: skipped.txt:1
            error: mismatch.txt: does not match index
            error: ghost.txt: does not exist in index
            error: already.txt already exists in working directory
            warning: Cannot merge binary files: asset.png (ours vs. theirs)
            """
        )
        XCTAssertEqual(parsed.applied, ["clean.txt"])
        XCTAssertEqual(parsed.skipped, ["already.txt", "fallback.txt", "ghost.txt", "mismatch.txt", "skipped.txt"])
        XCTAssertEqual(parsed.conflicted, ["asset.png", "conflict.txt", "rejected.txt", "unmerged.txt"])
    }

    func testApplyGitPatchPreflightAndApply() throws {
        let repo = try GitTestRepository()
        try "hello\n".write(to: repo.url.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)
        try repo.git(["add", "file.txt"])
        try repo.git(["commit", "-m", "initial"])

        let diff = """
        diff --git a/file.txt b/file.txt
        index ce01362..cc628cc 100644
        --- a/file.txt
        +++ b/file.txt
        @@ -1 +1 @@
        -hello
        +world
        """ + "\n"

        let preflight = try CodexGit.applyGitPatch(ApplyGitRequest(cwd: repo.url, diff: diff, preflight: true))
        XCTAssertEqual(preflight.exitCode, 0, preflight.stderr)
        XCTAssertEqual(try String(contentsOf: repo.url.appendingPathComponent("file.txt")), "hello\n")

        let applied = try CodexGit.applyGitPatch(ApplyGitRequest(cwd: repo.url, diff: diff))
        XCTAssertEqual(applied.exitCode, 0, applied.stderr)
        XCTAssertEqual(try String(contentsOf: repo.url.appendingPathComponent("file.txt")), "world\n")
        XCTAssertTrue(applied.commandForLog.contains("git apply --3way"))
    }

    func testRevertPreflightDoesNotStageIndex() throws {
        let repo = try GitTestRepository()
        try "orig\n".write(to: repo.url.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)
        try repo.git(["add", "file.txt"])
        try repo.git(["commit", "-m", "initial"])

        let diff = """
        diff --git a/file.txt b/file.txt
        --- a/file.txt
        +++ b/file.txt
        @@ -1 +1 @@
        -orig
        +ORIG
        """ + "\n"

        let apply = try CodexGit.applyGitPatch(ApplyGitRequest(cwd: repo.url, diff: diff))
        XCTAssertEqual(apply.exitCode, 0, apply.stderr)
        try repo.git(["commit", "-am", "apply change"])

        let stagedBefore = try repo.git(["diff", "--cached", "--name-only"]).trimmingCharacters(in: .whitespacesAndNewlines)
        let preflight = try CodexGit.applyGitPatch(ApplyGitRequest(cwd: repo.url, diff: diff, revert: true, preflight: true))
        XCTAssertEqual(preflight.exitCode, 0, preflight.stderr)
        let stagedAfter = try repo.git(["diff", "--cached", "--name-only"]).trimmingCharacters(in: .whitespacesAndNewlines)

        XCTAssertEqual(stagedAfter, stagedBefore)
        XCTAssertEqual(try String(contentsOf: repo.url.appendingPathComponent("file.txt")), "ORIG\n")
        XCTAssertTrue(preflight.commandForLog.contains("git apply --check -R"))
    }

    func testPreflightBlocksPartialChanges() throws {
        let repo = try GitTestRepository()
        let diff = """
        diff --git a/ok.txt b/ok.txt
        new file mode 100644
        --- /dev/null
        +++ b/ok.txt
        @@ -0,0 +1,2 @@
        +alpha
        +beta

        diff --git a/ghost.txt b/ghost.txt
        --- a/ghost.txt
        +++ b/ghost.txt
        @@ -1 +1 @@
        -old
        +new
        """ + "\n"

        let preflight = try CodexGit.applyGitPatch(ApplyGitRequest(cwd: repo.url, diff: diff, preflight: true))
        XCTAssertNotEqual(preflight.exitCode, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: repo.url.appendingPathComponent("ok.txt").path))
        XCTAssertTrue(preflight.commandForLog.contains("--check"))

        let direct = try CodexGit.applyGitPatch(ApplyGitRequest(cwd: repo.url, diff: diff))
        XCTAssertNotEqual(direct.exitCode, 0)
        XCTAssertFalse(direct.commandForLog.contains("--check"))
    }

    func testStagePathsIgnoresConfiguredHooksPathLikeRust() throws {
        #if os(Windows)
        throw XCTSkip("POSIX hook scripts are not used on Windows")
        #else
        let repo = try GitTestRepository()
        let marker = repo.url.appendingPathComponent("post-index-change-ran")
        let hooksDirectory = repo.url.appendingPathComponent(".git/hooks-path-test", isDirectory: true)
        try FileManager.default.createDirectory(at: hooksDirectory, withIntermediateDirectories: true)
        let hook = hooksDirectory.appendingPathComponent("post-index-change")
        let markerPath = marker.path.replacingOccurrences(of: "'", with: "'\\''")
        try """
        #!/bin/sh
        printf hook > '\(markerPath)'
        """.write(to: hook, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hook.path)

        try "hello\n".write(to: repo.url.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)
        try repo.git(["add", "file.txt"])
        try repo.git(["commit", "-m", "initial"])
        try repo.git(["config", "core.hooksPath", hooksDirectory.path])
        try "world\n".write(to: repo.url.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)

        let diff = """
        diff --git a/file.txt b/file.txt
        --- a/file.txt
        +++ b/file.txt
        @@ -1 +1 @@
        -hello
        +world
        """ + "\n"

        try CodexGit.stagePaths(gitRoot: repo.url, diff: diff)

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: marker.path),
            "CodexGit.stagePaths should disable configured hooks for internal git add calls"
        )
        #endif
    }
}

final class GitTestRepository {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try git(["init"])
        try git(["config", "user.email", "codex-swift@example.com"])
        try git(["config", "user.name", "Codex Swift"])
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    @discardableResult
    func git(_ args: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = url
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        let out = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let err = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "GitTestRepository", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: err])
        }
        return out
    }
}
