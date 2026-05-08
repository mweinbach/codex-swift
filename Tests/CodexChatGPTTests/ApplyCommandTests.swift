import CodexChatGPT
import CodexGit
import Foundation
import XCTest

final class ApplyCommandTests: XCTestCase {
    func testDecodesTaskResponseAndExtractsPRDiff() throws {
        let json = #"""
        {
          "current_diff_task_turn": {
            "output_items": [
              {"type": "message"},
              {
                "type": "pr",
                "output_diff": {
                  "diff": "diff --git a/file.txt b/file.txt\n"
                }
              }
            ]
          }
        }
        """#
        let response = try JSONDecoder().decode(GetTaskResponse.self, from: Data(json.utf8))
        XCTAssertEqual(try CodexTaskDiffApplier.diff(from: response), "diff --git a/file.txt b/file.txt\n")
    }

    func testMissingDiffTurnMatchesRustError() throws {
        let response = try JSONDecoder().decode(GetTaskResponse.self, from: Data(#"{"current_diff_task_turn":null}"#.utf8))
        XCTAssertThrowsError(try CodexTaskDiffApplier.diff(from: response)) { error in
            XCTAssertEqual(error as? ApplyTaskDiffError, .noDiffTurnFound)
        }
    }

    func testMissingPROutputMatchesRustError() throws {
        let json = #"{"current_diff_task_turn":{"output_items":[{"type":"message"}]}}"#
        let response = try JSONDecoder().decode(GetTaskResponse.self, from: Data(json.utf8))
        XCTAssertThrowsError(try CodexTaskDiffApplier.diff(from: response)) { error in
            XCTAssertEqual(error as? ApplyTaskDiffError, .noPROutputItemFound)
        }
    }

    func testApplyDiffAppliesExtractedPatch() throws {
        let repo = try ChatGPTGitTestRepository()
        try "before\n".write(to: repo.url.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)
        try repo.git(["add", "file.txt"])
        try repo.git(["commit", "-m", "initial"])

        let diff = """
        diff --git a/file.txt b/file.txt
        --- a/file.txt
        +++ b/file.txt
        @@ -1 +1 @@
        -before
        +after
        """ + "\n"
        let response = try decodeTaskResponse(diff: diff)

        let result = try CodexTaskDiffApplier.applyDiff(from: response, cwd: repo.url)
        XCTAssertEqual(result.exitCode, 0, result.stderr)
        XCTAssertEqual(try String(contentsOf: repo.url.appendingPathComponent("file.txt")), "after\n")
    }

    func testGitApplyFailureDescriptionMatchesRustShape() {
        let result = ApplyGitResult(
            exitCode: 1,
            appliedPaths: ["applied.txt"],
            skippedPaths: ["skipped.txt"],
            conflictedPaths: ["conflict.txt"],
            stdout: "stdout text",
            stderr: "stderr text",
            commandForLog: "git apply"
        )
        XCTAssertEqual(
            ApplyTaskDiffError.gitApplyFailed(result).description,
            """
            Git apply failed (applied=1, skipped=1, conflicts=1)
            stdout:
            stdout text
            stderr:
            stderr text
            """
        )
    }

    private func decodeTaskResponse(diff: String) throws -> GetTaskResponse {
        let payload: [String: Any] = [
            "current_diff_task_turn": [
                "output_items": [
                    [
                        "type": "pr",
                        "output_diff": ["diff": diff]
                    ]
                ]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        return try JSONDecoder().decode(GetTaskResponse.self, from: data)
    }
}

final class ChatGPTGitTestRepository {
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
            throw NSError(domain: "ChatGPTGitTestRepository", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: err])
        }
        return out
    }
}
