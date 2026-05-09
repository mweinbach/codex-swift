import CodexCore
import XCTest

final class HookPermissionRequestTests: XCTestCase {
    func testCommandInputUsesRequestToolNameWithoutRunIDSuffix() throws {
        var request = try requestForPermission("call-approve-1")
        request.toolName = "apply_patch"

        let inputJSON = try HookPermissionRequest.commandInputJSON(request)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(inputJSON.utf8)) as? [String: Any])

        XCTAssertEqual(object["hook_event_name"] as? String, "PermissionRequest")
        XCTAssertEqual(object["tool_name"] as? String, "apply_patch")
        XCTAssertNil(object["tool_use_id"])
        XCTAssertEqual(object["transcript_path"] as? NSNull, NSNull())
        XCTAssertEqual((object["tool_input"] as? [String: Any])?["command"] as? String, "echo hello")
    }

    func testAllowDecisionCompletesWithDecision() throws {
        let parsed = try parseCompleted(
            stdout: #"{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}"#
        )

        XCTAssertEqual(parsed.data, HookPermissionRequestHandlerData(decision: .allow))
        XCTAssertEqual(parsed.completed.run.status, .completed)
        XCTAssertEqual(parsed.completed.run.entries, [])
    }

    func testDenyDecisionBlocksWithFeedback() throws {
        let parsed = try parseCompleted(
            stdout: #"{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"deny","message":"policy says no"}}}"#
        )

        XCTAssertEqual(parsed.data, HookPermissionRequestHandlerData(decision: .deny(message: "policy says no")))
        XCTAssertEqual(parsed.completed.run.status, .blocked)
        XCTAssertEqual(parsed.completed.run.entries, [
            HookOutputEntry(kind: .feedback, text: "policy says no")
        ])
    }

    func testDenyDecisionUsesDefaultMessageForBlankMessage() throws {
        let parsed = try parseCompleted(
            stdout: #"{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"deny","message":"  "}}}"#
        )

        XCTAssertEqual(parsed.data, HookPermissionRequestHandlerData(
            decision: .deny(message: "PermissionRequest hook denied approval")
        ))
        XCTAssertEqual(parsed.completed.run.entries, [
            HookOutputEntry(kind: .feedback, text: "PermissionRequest hook denied approval")
        ])
    }

    func testSystemMessageAndUnsupportedUniversalFieldFailOpen() throws {
        let warning = try parseCompleted(stdout: #"{"systemMessage":"check policy"}"#)
        let unsupported = try parseCompleted(stdout: #"{"continue":false}"#)

        XCTAssertEqual(warning.data, HookPermissionRequestHandlerData())
        XCTAssertEqual(warning.completed.run.status, .completed)
        XCTAssertEqual(warning.completed.run.entries, [
            HookOutputEntry(kind: .warning, text: "check policy")
        ])
        XCTAssertEqual(unsupported.data, HookPermissionRequestHandlerData())
        XCTAssertEqual(unsupported.completed.run.status, .failed)
        XCTAssertEqual(unsupported.completed.run.entries, [
            HookOutputEntry(kind: .error, text: "PermissionRequest hook returned unsupported continue:false")
        ])
    }

    func testUnsupportedDecisionFieldsFailOpen() throws {
        let updatedInput = try parseCompleted(
            stdout: #"{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow","updatedInput":{}}}}"#
        )
        let interrupt = try parseCompleted(
            stdout: #"{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"deny","interrupt":true}}}"#
        )

        XCTAssertEqual(updatedInput.completed.run.status, .failed)
        XCTAssertEqual(updatedInput.completed.run.entries, [
            HookOutputEntry(kind: .error, text: "PermissionRequest hook returned unsupported updatedInput")
        ])
        XCTAssertEqual(interrupt.completed.run.status, .failed)
        XCTAssertEqual(interrupt.completed.run.entries, [
            HookOutputEntry(kind: .error, text: "PermissionRequest hook returned unsupported interrupt:true")
        ])
    }

    func testInvalidAndPlainStdoutHandling() throws {
        let plain = try parseCompleted(stdout: "approved by external checker")
        let invalid = try parseCompleted(stdout: "{\"hookSpecificOutput\":\n")

        XCTAssertEqual(plain.data, HookPermissionRequestHandlerData())
        XCTAssertEqual(plain.completed.run.status, .completed)
        XCTAssertEqual(plain.completed.run.entries, [])
        XCTAssertEqual(invalid.completed.run.status, .failed)
        XCTAssertEqual(invalid.completed.run.entries, [
            HookOutputEntry(kind: .error, text: "hook returned invalid permission-request JSON output")
        ])
    }

    func testExitCodeTwoDeniesWithStderr() throws {
        let parsed = try parseCompleted(exitCode: 2, stdout: "", stderr: "approval denied\n")

        XCTAssertEqual(parsed.data, HookPermissionRequestHandlerData(decision: .deny(message: "approval denied")))
        XCTAssertEqual(parsed.completed.run.status, .blocked)
        XCTAssertEqual(parsed.completed.run.entries, [
            HookOutputEntry(kind: .feedback, text: "approval denied")
        ])
    }

    func testExitCodeTwoWithoutStderrAndNonzeroFailures() throws {
        let missingDenial = try parseCompleted(exitCode: 2, stdout: "", stderr: " ")
        let nonzero = try parseCompleted(exitCode: 7, stdout: "", stderr: "")
        let missingStatus = try parseCompleted(exitCode: nil, stdout: "", stderr: "")

        XCTAssertEqual(missingDenial.completed.run.status, .failed)
        XCTAssertEqual(missingDenial.completed.run.entries, [
            HookOutputEntry(
                kind: .error,
                text: "PermissionRequest hook exited with code 2 but did not write a denial reason to stderr"
            )
        ])
        XCTAssertEqual(nonzero.completed.run.entries, [
            HookOutputEntry(kind: .error, text: "hook exited with code 7")
        ])
        XCTAssertEqual(missingStatus.completed.run.entries, [
            HookOutputEntry(kind: .error, text: "hook exited without a status code")
        ])
    }

    func testResolveDecisionPrefersAnyDenyOtherwiseAllow() {
        XCTAssertEqual(
            HookPermissionRequest.resolveDecision([.allow, .deny(message: "repo deny")]),
            .deny(message: "repo deny")
        )
        XCTAssertEqual(HookPermissionRequest.resolveDecision([.allow, .allow]), .allow)
        XCTAssertNil(HookPermissionRequest.resolveDecision([]))
    }

    func testPreviewAndCompletedRunIDsIncludeRunIDSuffix() throws {
        let request = try requestForPermission("call-approve-1")
        let runs = try HookPermissionRequest.preview(handlers: [handler()], request: request, startedAt: 1)

        XCTAssertEqual(runs.count, 1)
        XCTAssertEqual(runs[0].id, "permission-request:0:/tmp/hooks.json:call-approve-1")

        let parsed = try parseCompleted(stdout: "")
        let completed = HookPermissionRequest.hookCompletedForRunSuffix(parsed.completed, runIDSuffix: request.runIDSuffix)

        XCTAssertEqual(completed.run.id, runs[0].id)
    }

    func testRunAggregatesConservativeDecision() async throws {
        let handlers = try [
            handler(command: #"printf %s '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}'"#),
            handler(
                command: #"printf %s '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"deny","message":"repo policy"}}}'"#,
                displayOrder: 1
            )
        ]

        let outcome = await HookPermissionRequest.run(
            handlers: handlers,
            shell: HookCommandShell(program: "/bin/sh", arguments: ["-c"]),
            request: try requestForPermission("call-approve-1")
        )

        XCTAssertEqual(outcome.decision, .deny(message: "repo policy"))
        XCTAssertEqual(outcome.hookEvents.map(\.run.status), [.completed, .blocked])
        XCTAssertEqual(outcome.hookEvents.map(\.run.id), [
            "permission-request:0:/tmp/hooks.json:call-approve-1",
            "permission-request:1:/tmp/hooks.json:call-approve-1",
        ])
    }

    private func parseCompleted(
        exitCode: Int32? = 0,
        stdout: String,
        stderr: String = ""
    ) throws -> ParsedHookHandler<HookPermissionRequestHandlerData> {
        try HookPermissionRequest.parseCompleted(
            handler: handler(),
            runResult: HookCommandRunResult(
                startedAt: 1,
                completedAt: 2,
                durationMs: 1,
                exitCode: exitCode,
                stdout: stdout,
                stderr: stderr
            ),
            turnID: "turn-1"
        )
    }

    private func handler(
        command: String = "echo hook",
        displayOrder: Int64 = 0
    ) throws -> ConfiguredHookHandler {
        try ConfiguredHookHandler(
            eventName: .permissionRequest,
            matcher: "^Bash$",
            command: command,
            timeoutSec: 5,
            statusMessage: "running permission request hook",
            sourcePath: AbsolutePath(absolutePath: "/tmp/hooks.json"),
            source: .user,
            displayOrder: displayOrder
        )
    }

    private func requestForPermission(_ runIDSuffix: String) throws -> HookPermissionRequestRequest {
        try HookPermissionRequestRequest(
            sessionID: ThreadId(),
            turnID: "turn-1",
            cwd: AbsolutePath(absolutePath: "/tmp"),
            model: "gpt-test",
            permissionMode: "default",
            toolName: "Bash",
            runIDSuffix: runIDSuffix,
            toolInput: .object(["command": .string("echo hello")])
        )
    }
}
