import CodexCore
import Foundation
import XCTest

final class NonInteractiveExecTests: XCTestCase {
    func testMakePromptBuildsEnvironmentAndUserInput() {
        let schema = JSONValue.object(["type": .string("object")])
        let prompt = NonInteractiveExec.makePrompt(
            prompt: "ship it",
            imagePaths: ["/tmp/screenshot.png"],
            outputSchema: schema,
            cwd: URL(fileURLWithPath: "/tmp/project", isDirectory: true),
            approvalPolicy: .never,
            sandboxPolicy: .readOnly,
            shell: Shell(shellType: .zsh, shellPath: "/bin/zsh")
        )

        XCTAssertEqual(prompt.tools, [])
        XCTAssertEqual(prompt.outputSchema, schema)
        XCTAssertEqual(prompt.input.count, 2)

        guard case let .message(_, role, content) = prompt.input[1] else {
            return XCTFail("expected user message")
        }
        XCTAssertEqual(role, "user")
        XCTAssertEqual(content.count, 2)
        guard case let .inputText(text) = content[1] else {
            return XCTFail("expected prompt text")
        }
        XCTAssertEqual(text, "ship it")
    }

    func testMakePromptPlacesResumeHistoryBeforeNewUserInput() {
        let history: [ResponseItem] = [
            .message(role: "user", content: [.inputText(text: "previous request")]),
            .message(role: "assistant", content: [.outputText(text: "previous answer")])
        ]
        let prompt = NonInteractiveExec.makePrompt(
            prompt: "continue",
            imagePaths: [],
            outputSchema: nil,
            cwd: URL(fileURLWithPath: "/tmp/project", isDirectory: true),
            approvalPolicy: .never,
            sandboxPolicy: .dangerFullAccess,
            shell: Shell(shellType: .zsh, shellPath: "/bin/zsh"),
            history: history
        )

        XCTAssertEqual(prompt.input.count, 4)
        XCTAssertEqual(Array(prompt.input[1...2]), history)
        guard case let .message(_, role, content) = prompt.input[3] else {
            return XCTFail("expected user message")
        }
        XCTAssertEqual(role, "user")
        XCTAssertEqual(content, [.inputText(text: "continue")])
    }

    func testMakePromptAcceptsToolsAndParallelToolCalls() {
        let shellTool = ToolSpecFactory.createShellCommandTool()
        let prompt = NonInteractiveExec.makePrompt(
            prompt: "ship it",
            imagePaths: [],
            outputSchema: nil,
            cwd: URL(fileURLWithPath: "/tmp/project", isDirectory: true),
            approvalPolicy: .never,
            sandboxPolicy: .dangerFullAccess,
            shell: Shell(shellType: .zsh, shellPath: "/bin/zsh"),
            tools: [shellTool],
            parallelToolCalls: true
        )

        XCTAssertEqual(prompt.tools, [shellTool])
        XCTAssertTrue(prompt.parallelToolCalls)
    }

    func testToolSpecsFollowModelFamilyAndFeatureOverrides() {
        var features = FeatureStates.withDefaults()
        features.set(.unifiedExec, enabled: true)
        features.set(.webSearchRequest, enabled: true)
        let config = CodexRuntimeConfig(
            includeApplyPatchTool: true,
            toolsViewImage: false,
            features: features
        )
        let modelFamily = ModelFamily(
            slug: "test-model",
            family: "test",
            supportsParallelToolCalls: true,
            experimentalSupportedTools: ["grep_files"],
            shellType: .shellCommand
        )

        let names = NonInteractiveExec.toolSpecs(modelFamily: modelFamily, config: config).map(\.spec.name)

        XCTAssertTrue(names.contains("exec_command"))
        XCTAssertTrue(names.contains("write_stdin"))
        XCTAssertTrue(names.contains("apply_patch"))
        XCTAssertTrue(names.contains("grep_files"))
        XCTAssertTrue(names.contains("web_search"))
        XCTAssertFalse(names.contains("shell_command"))
        XCTAssertFalse(names.contains("view_image"))
    }

    func testResponsesLoopExecutesFunctionCallAndContinues() async throws {
        let initial = Prompt(input: [
            .message(role: "user", content: [.inputText(text: "run echo")])
        ])
        let script = ExecLoopScript()

        let events = await NonInteractiveExec.runResponsesLoop(
            initialPrompt: initial,
            streamPrompt: { prompt in
                .success(await script.next(prompt))
            },
            executeFunctionCall: { item in
                guard case let .functionCall(_, name, _, callID) = item else {
                    return .functionCallOutput(
                        callID: "bad",
                        output: FunctionCallOutputPayload(content: "bad", success: false)
                    )
                }
                return .functionCallOutput(
                    callID: callID,
                    output: FunctionCallOutputPayload(content: "\(name) ok", success: true)
                )
            }
        )

        let prompts = await script.prompts()
        XCTAssertEqual(prompts.count, 2)
        XCTAssertTrue(prompts[1].input.contains {
            if case let .functionCallOutput(callID, output) = $0 {
                return callID == "call-1" && output.content == "shell_command ok"
            }
            return false
        })

        let result = NonInteractiveExec.finish(
            responseEvents: events,
            outputMode: .human,
            conversationID: ConversationId(),
            lastMessageFile: nil
        )
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stdoutMessage, "done")
    }

    func testResponsesLoopWithTranscriptIncludesToolCallsOutputsAndFinalMessage() async throws {
        let initial = Prompt(input: [
            .message(role: "user", content: [.inputText(text: "run echo")])
        ])
        let script = ExecLoopScript()

        let result = await NonInteractiveExec.runResponsesLoopWithTranscript(
            initialPrompt: initial,
            streamPrompt: { prompt in
                .success(await script.next(prompt))
            },
            executeFunctionCall: { item in
                guard case let .functionCall(_, _, _, callID) = item else {
                    return .functionCallOutput(
                        callID: "bad",
                        output: FunctionCallOutputPayload(content: "bad", success: false)
                    )
                }
                return .functionCallOutput(
                    callID: callID,
                    output: FunctionCallOutputPayload(content: "ok", success: true)
                )
            }
        )

        XCTAssertEqual(result.transcriptItems, [
            .functionCall(name: "shell_command", arguments: #"{"command":"echo hi"}"#, callID: "call-1"),
            .functionCallOutput(callID: "call-1", output: FunctionCallOutputPayload(content: "ok", success: true)),
            .message(role: "assistant", content: [.outputText(text: "done")])
        ])
    }

    func testResponsesLoopExecutesCustomToolCallAndContinues() async throws {
        let initial = Prompt(input: [
            .message(role: "user", content: [.inputText(text: "patch")])
        ])
        let script = CustomToolLoopScript()

        let result = await NonInteractiveExec.runResponsesLoopWithTranscript(
            initialPrompt: initial,
            streamPrompt: { prompt in
                .success(await script.next(prompt))
            },
            executeFunctionCall: { item in
                guard case let .customToolCall(_, _, callID, name, _) = item else {
                    return .customToolCallOutput(callID: "bad", output: "bad")
                }
                return .customToolCallOutput(callID: callID, output: "\(name) ok")
            }
        )

        let prompts = await script.prompts()
        XCTAssertEqual(prompts.count, 2)
        XCTAssertTrue(prompts[1].input.contains(.customToolCallOutput(callID: "custom-1", output: "apply_patch ok")))
        XCTAssertEqual(result.transcriptItems, [
            .customToolCall(callID: "custom-1", name: "apply_patch", input: "*** Begin Patch\n*** End Patch"),
            .customToolCallOutput(callID: "custom-1", output: "apply_patch ok"),
            .message(role: "assistant", content: [.outputText(text: "done")])
        ])
    }

    func testShellCommandFunctionCallRunsUserShellCommand() async throws {
        let temp = try NonInteractiveExecTemporaryDirectory()
        let item = ResponseItem.functionCall(
            name: "shell_command",
            arguments: #"{"command":"printf hello","login":false}"#,
            callID: "call-shell"
        )

        let output = await NonInteractiveExec.executeFunctionCall(
            item,
            cwd: temp.url,
            approvalPolicy: .never,
            sandboxPolicy: .dangerFullAccess,
            shell: Shell(shellType: .sh, shellPath: "/bin/sh"),
            truncationPolicy: .bytes(10_000),
            environment: ["PATH": "/bin:/usr/bin", "HOME": temp.url.path]
        )

        guard case let .functionCallOutput(callID, payload) = output else {
            return XCTFail("expected function call output")
        }
        XCTAssertEqual(callID, "call-shell")
        XCTAssertEqual(payload.success, true)
        XCTAssertTrue(payload.content.contains("Exit code: 0"))
        XCTAssertTrue(payload.content.contains("Output:\nhello"))
    }

    func testEscalatedSandboxRequestReturnsFailureOutput() async throws {
        let item = ResponseItem.functionCall(
            name: "exec_command",
            arguments: #"{"cmd":"echo no","sandbox_permissions":"require_escalated"}"#,
            callID: "call-escalated"
        )

        let output = await NonInteractiveExec.executeFunctionCall(
            item,
            cwd: URL(fileURLWithPath: "/tmp", isDirectory: true),
            approvalPolicy: .never,
            sandboxPolicy: .readOnly,
            shell: Shell(shellType: .sh, shellPath: "/bin/sh"),
            truncationPolicy: .bytes(10_000),
            environment: ["PATH": "/bin:/usr/bin"]
        )

        guard case let .functionCallOutput(callID, payload) = output else {
            return XCTFail("expected function call output")
        }
        XCTAssertEqual(callID, "call-escalated")
        XCTAssertEqual(payload.success, false)
        XCTAssertTrue(payload.content.contains("reject command"))
    }

    func testApplyPatchFunctionCallAppliesJsonInput() async throws {
        let temp = try NonInteractiveExecTemporaryDirectory()
        let patch = """
        *** Begin Patch
        *** Add File: created.txt
        +hello
        *** End Patch
        """
        let encodedPatch = try Self.jsonString(patch)
        let item = ResponseItem.functionCall(
            name: "apply_patch",
            arguments: #"{"input":\#(encodedPatch)}"#,
            callID: "call-patch"
        )

        let output = await NonInteractiveExec.executeFunctionCall(
            item,
            cwd: temp.url,
            approvalPolicy: .never,
            sandboxPolicy: .dangerFullAccess,
            shell: Shell(shellType: .sh, shellPath: "/bin/sh"),
            truncationPolicy: .bytes(10_000),
            environment: [:]
        )

        guard case let .functionCallOutput(callID, payload) = output else {
            return XCTFail("expected function call output")
        }
        XCTAssertEqual(callID, "call-patch")
        XCTAssertEqual(payload.success, true)
        XCTAssertTrue(payload.content.contains("Success. Updated the following files:"))
        XCTAssertTrue(payload.content.contains("A created.txt"))
        XCTAssertEqual(
            try String(contentsOf: temp.url.appendingPathComponent("created.txt"), encoding: .utf8),
            "hello\n"
        )
    }

    func testApplyPatchCustomToolCallAppliesFreeformInput() async throws {
        let temp = try NonInteractiveExecTemporaryDirectory()
        let patch = """
        *** Begin Patch
        *** Add File: custom.txt
        +custom
        *** End Patch
        """
        let item = ResponseItem.customToolCall(callID: "custom-patch", name: "apply_patch", input: patch)

        let output = await NonInteractiveExec.executeFunctionCall(
            item,
            cwd: temp.url,
            approvalPolicy: .never,
            sandboxPolicy: .dangerFullAccess,
            shell: Shell(shellType: .sh, shellPath: "/bin/sh"),
            truncationPolicy: .bytes(10_000),
            environment: [:]
        )

        XCTAssertEqual(
            output,
            .customToolCallOutput(
                callID: "custom-patch",
                output: "Success. Updated the following files:\nA custom.txt\n"
            )
        )
        XCTAssertEqual(
            try String(contentsOf: temp.url.appendingPathComponent("custom.txt"), encoding: .utf8),
            "custom\n"
        )
    }

    func testApplyPatchCustomToolCallRejectsReadOnlySandboxWithNeverApproval() async throws {
        let temp = try NonInteractiveExecTemporaryDirectory()
        let patch = """
        *** Begin Patch
        *** Add File: blocked.txt
        +blocked
        *** End Patch
        """
        let item = ResponseItem.customToolCall(callID: "custom-patch", name: "apply_patch", input: patch)

        let output = await NonInteractiveExec.executeFunctionCall(
            item,
            cwd: temp.url,
            approvalPolicy: .never,
            sandboxPolicy: .readOnly,
            shell: Shell(shellType: .sh, shellPath: "/bin/sh"),
            truncationPolicy: .bytes(10_000),
            environment: [:]
        )

        XCTAssertEqual(
            output,
            .customToolCallOutput(
                callID: "custom-patch",
                output: "apply_patch rejected: writing outside of the project; rejected by user approval settings"
            )
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: temp.url.appendingPathComponent("blocked.txt").path))
    }

    func testApplyPatchShellCommandInterceptAppliesVerifiedHeredoc() async throws {
        let temp = try NonInteractiveExecTemporaryDirectory()
        let script = """
        apply_patch <<'PATCH'
        *** Begin Patch
        *** Add File: shell.txt
        +shell
        *** End Patch
        PATCH
        """
        let encodedScript = try Self.jsonString(script)
        let item = ResponseItem.functionCall(
            name: "shell_command",
            arguments: #"{"command":\#(encodedScript),"login":false}"#,
            callID: "call-shell-patch"
        )

        let output = await NonInteractiveExec.executeFunctionCall(
            item,
            cwd: temp.url,
            approvalPolicy: .never,
            sandboxPolicy: .dangerFullAccess,
            shell: Shell(shellType: .sh, shellPath: "/bin/sh"),
            truncationPolicy: .bytes(10_000),
            environment: ["PATH": "/bin:/usr/bin"]
        )

        guard case let .functionCallOutput(callID, payload) = output else {
            return XCTFail("expected function call output")
        }
        XCTAssertEqual(callID, "call-shell-patch")
        XCTAssertEqual(payload.success, true)
        XCTAssertTrue(payload.content.contains("Exit code: 0"))
        XCTAssertTrue(payload.content.contains("A shell.txt"))
        XCTAssertEqual(
            try String(contentsOf: temp.url.appendingPathComponent("shell.txt"), encoding: .utf8),
            "shell\n"
        )
    }

    func testApplyPatchShellCommandInterceptRejectsReadOnlySandboxWithNeverApproval() async throws {
        let temp = try NonInteractiveExecTemporaryDirectory()
        let script = """
        apply_patch <<'PATCH'
        *** Begin Patch
        *** Add File: blocked-shell.txt
        +blocked
        *** End Patch
        PATCH
        """
        let encodedScript = try Self.jsonString(script)
        let item = ResponseItem.functionCall(
            name: "shell_command",
            arguments: #"{"command":\#(encodedScript),"login":false}"#,
            callID: "call-shell-patch"
        )

        let output = await NonInteractiveExec.executeFunctionCall(
            item,
            cwd: temp.url,
            approvalPolicy: .never,
            sandboxPolicy: .readOnly,
            shell: Shell(shellType: .sh, shellPath: "/bin/sh"),
            truncationPolicy: .bytes(10_000),
            environment: ["PATH": "/bin:/usr/bin"]
        )

        guard case let .functionCallOutput(_, payload) = output else {
            return XCTFail("expected function call output")
        }
        XCTAssertEqual(payload.success, false)
        XCTAssertTrue(payload.content.contains("apply_patch rejected"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: temp.url.appendingPathComponent("blocked-shell.txt").path))
    }

    func testUnifiedExecCommandPersistsSessionAndWriteStdinContinuesIt() async throws {
        let temp = try NonInteractiveExecTemporaryDirectory()
        let start = ResponseItem.functionCall(
            name: "exec_command",
            arguments: #"{"cmd":"read line; echo got:$line","yield_time_ms":100}"#,
            callID: "call-start"
        )

        let startOutput = await NonInteractiveExec.executeFunctionCall(
            start,
            cwd: temp.url,
            approvalPolicy: .never,
            sandboxPolicy: .dangerFullAccess,
            shell: Shell(shellType: .sh, shellPath: "/bin/sh"),
            truncationPolicy: .bytes(10_000),
            environment: ["PATH": "/bin:/usr/bin", "HOME": temp.url.path]
        )

        guard case let .functionCallOutput(_, startPayload) = startOutput else {
            return XCTFail("expected function call output")
        }
        XCTAssertEqual(startPayload.success, true)
        let sessionID = try XCTUnwrap(Self.sessionID(from: startPayload.content))

        let write = ResponseItem.functionCall(
            name: "write_stdin",
            arguments: #"{"session_id":\#(sessionID),"chars":"hello\n","yield_time_ms":2500}"#,
            callID: "call-write"
        )
        let writeOutput = await NonInteractiveExec.executeFunctionCall(
            write,
            cwd: temp.url,
            approvalPolicy: .never,
            sandboxPolicy: .dangerFullAccess,
            shell: Shell(shellType: .sh, shellPath: "/bin/sh"),
            truncationPolicy: .bytes(10_000),
            environment: ["PATH": "/bin:/usr/bin", "HOME": temp.url.path]
        )

        guard case let .functionCallOutput(callID, payload) = writeOutput else {
            return XCTFail("expected function call output")
        }
        XCTAssertEqual(callID, "call-write")
        XCTAssertEqual(payload.success, true)
        XCTAssertTrue(payload.content.contains("Process exited with code 0"))
        XCTAssertTrue(payload.content.contains("got:hello"))
    }

    func testHumanOutputReturnsFinalAssistantMessageAndWritesLastMessage() throws {
        let id = try ConversationId(string: "018f7a2d-4c5b-7abc-8def-0123456789ab")
        let writes = WriteSink()

        let result = NonInteractiveExec.finish(
            responseEvents: [
                .success(.outputTextDelta("do")),
                .success(.outputTextDelta("ne")),
                .success(.completed(responseID: "resp_1", tokenUsage: TokenUsage(totalTokens: 12)))
            ],
            outputMode: .human,
            conversationID: id,
            lastMessageFile: "/tmp/last.txt",
            writeFile: { path, contents in
                writes.write(path: path, contents: contents)
            }
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stdoutMessage, "done")
        XCTAssertEqual(result.stderrMessages, [])
        XCTAssertEqual(result.lastAgentMessage, "done")
        XCTAssertEqual(writes.contents(at: "/tmp/last.txt"), "done")
    }

    func testJSONLinesOutputUsesExecEventEnvelope() throws {
        let id = try ConversationId(string: "018f7a2d-4c5b-7abc-8def-0123456789ab")
        let result = NonInteractiveExec.finish(
            responseEvents: [
                .success(.outputItemDone(.message(role: "assistant", content: [.outputText(text: "done")]))),
                .success(.completed(
                    responseID: "resp_1",
                    tokenUsage: TokenUsage(
                        inputTokens: 3,
                        cachedInputTokens: 1,
                        outputTokens: 5,
                        reasoningOutputTokens: 2,
                        totalTokens: 8
                    )
                ))
            ],
            outputMode: .jsonLines,
            conversationID: id,
            lastMessageFile: nil
        )

        XCTAssertEqual(result.exitCode, 0)
        let lines = try XCTUnwrap(result.stdoutMessage?.split(separator: "\n").map(String.init))
        XCTAssertEqual(lines.count, 4)
        let objects = try lines.map(jsonObject)
        XCTAssertEqual(objects[0]["type"], .string("thread.started"))
        XCTAssertEqual(objects[0]["thread_id"], .string(id.description))
        XCTAssertEqual(objects[1]["type"], .string("turn.started"))
        XCTAssertEqual(objects[2]["type"], .string("item.completed"))
        XCTAssertEqual(objects[3]["type"], .string("turn.completed"))
        guard case let .object(item)? = objects[2]["item"] else {
            return XCTFail("expected completed item")
        }
        XCTAssertEqual(item["type"], .string("agent_message"))
        XCTAssertEqual(item["text"], .string("done"))
        guard case let .object(usage)? = objects[3]["usage"] else {
            return XCTFail("expected usage")
        }
        XCTAssertEqual(usage["input_tokens"], .integer(3))
        XCTAssertEqual(usage["cached_input_tokens"], .integer(1))
        XCTAssertEqual(usage["output_tokens"], .integer(5))
        XCTAssertEqual(usage["reasoning_output_tokens"], .integer(2))
        XCTAssertEqual(usage["total_tokens"], .integer(8))
    }

    func testFailureOutputReturnsExitOneAndWritesEmptyLastMessage() throws {
        let id = try ConversationId(string: "018f7a2d-4c5b-7abc-8def-0123456789ab")
        let writes = WriteSink()

        let result = NonInteractiveExec.finish(
            responseEvents: [.failure(.quotaExceeded)],
            outputMode: .human,
            conversationID: id,
            lastMessageFile: "/tmp/last.txt",
            writeFile: { path, contents in
                writes.write(path: path, contents: contents)
            }
        )

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertNil(result.stdoutMessage)
        XCTAssertEqual(result.stderrMessages.first, "quota exceeded")
        XCTAssertEqual(writes.contents(at: "/tmp/last.txt"), "")
        XCTAssertEqual(result.stderrMessages.last, "Warning: no last agent message; wrote empty content to /tmp/last.txt")
    }

    private func jsonObject(_ line: String) throws -> [String: JSONValue] {
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(line.utf8))
        guard case let .object(object) = value else {
            throw XCTSkip("expected object")
        }
        return object
    }
}

private final class WriteSink: @unchecked Sendable {
    private let lock = NSLock()
    private var writes: [String: String] = [:]

    func write(path: String, contents: String) {
        lock.withLock {
            writes[path] = contents
        }
    }

    func contents(at path: String) -> String? {
        lock.withLock {
            writes[path]
        }
    }
}

private extension NonInteractiveExecTests {
    static func sessionID(from content: String) -> Int? {
        let prefix = "Process running with session ID "
        guard let line = content
            .split(separator: "\n")
            .first(where: { $0.hasPrefix(prefix) })
        else {
            return nil
        }
        return Int(line.dropFirst(prefix.count))
    }

    static func jsonString(_ value: String) throws -> String {
        let data = try JSONEncoder().encode(value)
        return String(decoding: data, as: UTF8.self)
    }
}

private actor ExecLoopScript {
    private var calls = 0
    private var recordedPrompts: [Prompt] = []

    func next(_ prompt: Prompt) -> ResponseEventResults {
        calls += 1
        recordedPrompts.append(prompt)

        if calls == 1 {
            return [
                .success(.outputItemDone(.functionCall(
                    name: "shell_command",
                    arguments: #"{"command":"echo hi"}"#,
                    callID: "call-1"
                ))),
                .success(.completed(responseID: "resp-1", tokenUsage: nil))
            ]
        }

        return [
            .success(.outputItemDone(.message(role: "assistant", content: [.outputText(text: "done")]))),
            .success(.completed(responseID: "resp-2", tokenUsage: nil))
        ]
    }

    func prompts() -> [Prompt] {
        recordedPrompts
    }
}

private actor CustomToolLoopScript {
    private var calls = 0
    private var recordedPrompts: [Prompt] = []

    func next(_ prompt: Prompt) -> ResponseEventResults {
        calls += 1
        recordedPrompts.append(prompt)

        if calls == 1 {
            return [
                .success(.outputItemDone(.customToolCall(
                    callID: "custom-1",
                    name: "apply_patch",
                    input: "*** Begin Patch\n*** End Patch"
                ))),
                .success(.completed(responseID: "resp-1", tokenUsage: nil))
            ]
        }

        return [
            .success(.outputItemDone(.message(role: "assistant", content: [.outputText(text: "done")]))),
            .success(.completed(responseID: "resp-2", tokenUsage: nil))
        ]
    }

    func prompts() -> [Prompt] {
        recordedPrompts
    }
}

private final class NonInteractiveExecTemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-swift-noninteractive-exec-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}
