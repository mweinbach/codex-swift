import Darwin
import Foundation

public enum NonInteractiveExecOutputMode: Equatable, Sendable {
    case human
    case jsonLines
}

public struct NonInteractiveExecRunResult: Equatable, Sendable {
    public let exitCode: Int32
    public let stdoutMessage: String?
    public let stderrMessages: [String]
    public let lastAgentMessage: String?
    public let tokenUsage: TokenUsage?

    public init(
        exitCode: Int32,
        stdoutMessage: String?,
        stderrMessages: [String],
        lastAgentMessage: String?,
        tokenUsage: TokenUsage?
    ) {
        self.exitCode = exitCode
        self.stdoutMessage = stdoutMessage
        self.stderrMessages = stderrMessages
        self.lastAgentMessage = lastAgentMessage
        self.tokenUsage = tokenUsage
    }
}

public enum NonInteractiveExec {
    private static let unifiedExecSessions = UnifiedExecSessionRegistry()

    public static func makePrompt(
        prompt: String,
        imagePaths: [String],
        outputSchema: JSONValue?,
        cwd: URL,
        approvalPolicy: AskForApproval,
        sandboxPolicy: SandboxPolicy,
        shell: Shell,
        tools: [ToolSpec] = [],
        parallelToolCalls: Bool = false
    ) -> Prompt {
        let context = TurnContext(
            cwd: cwd.path,
            approvalPolicy: approvalPolicy,
            sandboxPolicy: sandboxPolicy
        )
        var input = [
            EnvironmentContext
                .fromTurnContext(context, shell: shell)
                .asResponseItem()
        ]

        let userInputs = imagePaths.map { UserInput.localImage(path: $0) } + [.text(prompt)]
        input.append(ResponseInputItem(userInputs: userInputs).responseItem())

        return Prompt(
            input: input,
            tools: tools,
            parallelToolCalls: parallelToolCalls,
            outputSchema: outputSchema
        )
    }

    public static func toolsConfig(
        modelFamily: ModelFamily,
        config: CodexRuntimeConfig
    ) -> ToolsConfig {
        let shellType: ConfigShellToolType
        if !config.features.isEnabled(.shellTool) {
            shellType = .disabled
        } else if config.features.isEnabled(.unifiedExec) || config.experimentalUseUnifiedExecTool == true {
            shellType = .unifiedExec
        } else {
            shellType = modelFamily.shellType
        }

        let applyPatchToolType = modelFamily.applyPatchToolType
            ?? ((config.features.isEnabled(.applyPatchFreeform)
                 || config.includeApplyPatchTool == true
                 || config.experimentalUseFreeformApplyPatch == true)
                ? .freeform
                : nil)

        return ToolsConfig(
            shellType: shellType,
            applyPatchToolType: applyPatchToolType,
            webSearchRequest: config.toolsWebSearch ?? config.features.isEnabled(.webSearchRequest),
            includeViewImageTool: config.toolsViewImage ?? config.features.isEnabled(.viewImageTool),
            includeComputerUseTools: config.features.isEnabled(.computerUseGui),
            experimentalSupportedTools: modelFamily.experimentalSupportedTools
        )
    }

    public static func toolSpecs(
        modelFamily: ModelFamily,
        config: CodexRuntimeConfig
    ) -> [ConfiguredToolSpec] {
        ToolSpecFactory.buildSpecs(config: toolsConfig(modelFamily: modelFamily, config: config))
    }

    public static func responsesOptions(
        conversationID: ConversationId,
        modelFamily: ModelFamily,
        reasoningEffort: ReasoningEffort?,
        reasoningSummary: ReasoningSummary?,
        verbosity: Verbosity?,
        outputSchema: JSONValue?
    ) -> ResponsesOptions {
        let effort = reasoningEffort ?? modelFamily.defaultReasoningEffort
        let summary = reasoningSummary ?? (modelFamily.supportsReasoningSummaries ? .auto : nil)
        let reasoning = effort == nil && summary == nil
            ? nil
            : ResponsesAPIReasoning(effort: effort, summary: summary)

        return ResponsesOptions(
            reasoning: reasoning,
            text: ResponsesAPITextControls.createForRequest(
                verbosity: verbosity ?? modelFamily.defaultVerbosity,
                outputSchema: outputSchema
            ),
            conversationID: conversationID.description,
            sessionSource: .exec
        )
    }

    public typealias ResponseStreamer = (Prompt) async -> Result<ResponseEventResults, APIError>
    public typealias FunctionCallExecutor = (ResponseItem) async -> ResponseItem

    public static func runResponsesLoop(
        initialPrompt: Prompt,
        maxToolIterations: Int = 20,
        streamPrompt: ResponseStreamer,
        executeFunctionCall: FunctionCallExecutor
    ) async -> ResponseEventResults {
        var prompt = initialPrompt
        var allEvents: ResponseEventResults = []

        for _ in 0..<maxToolIterations {
            let streamResult = await streamPrompt(prompt)
            let turnEvents: ResponseEventResults
            switch streamResult {
            case let .success(results):
                turnEvents = results
            case let .failure(error):
                turnEvents = [.failure(error)]
            }

            allEvents.append(contentsOf: turnEvents)
            if containsFailure(turnEvents) {
                return allEvents
            }

            let completedItems = completedOutputItems(from: turnEvents)
            prompt.input.append(contentsOf: completedItems)

            let toolCalls = toolCalls(from: completedItems)
            if toolCalls.isEmpty {
                return allEvents
            }

            for call in toolCalls {
                prompt.input.append(await executeFunctionCall(call))
            }
        }

        allEvents.append(.failure(.stream("too many tool call iterations")))
        return allEvents
    }

    public static func executeFunctionCall(
        _ item: ResponseItem,
        cwd: URL,
        approvalPolicy: AskForApproval,
        sandboxPolicy: SandboxPolicy,
        shell: Shell,
        truncationPolicy: TruncationPolicy,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) async -> ResponseItem {
        switch item {
        case let .functionCall(_, name, arguments, callID):
            return await executeFunctionCall(
                name: name,
                arguments: arguments,
                callID: callID,
                cwd: cwd,
                approvalPolicy: approvalPolicy,
                sandboxPolicy: sandboxPolicy,
                shell: shell,
                truncationPolicy: truncationPolicy,
                environment: environment
            )

        case let .localShellCall(id, callID, _, action):
            guard case let .exec(params) = action else {
                return functionOutput(
                    callID: callID ?? id ?? "local_shell",
                    content: "unsupported local_shell action",
                    success: false
                )
            }
            return await executeShellCommand(
                toolName: "local_shell",
                command: params.command,
                workdir: params.workingDirectory,
                timeoutMS: params.timeoutMS,
                sandboxPermissions: .useDefault,
                callID: callID ?? id ?? "local_shell",
                cwd: cwd,
                approvalPolicy: approvalPolicy,
                sandboxPolicy: sandboxPolicy,
                truncationPolicy: truncationPolicy,
                environment: environment,
                responseFormat: .structured
            )

        default:
            return functionOutput(
                callID: "unknown",
                content: "unsupported tool response item",
                success: false
            )
        }
    }

    public static func finish(
        responseEvents: ResponseEventResults,
        outputMode: NonInteractiveExecOutputMode,
        conversationID: ConversationId,
        lastMessageFile: String?,
        writeFile: NonInteractiveInput.FileWriter? = nil
    ) -> NonInteractiveExecRunResult {
        let events = ResponseEventAggregator.aggregate(responseEvents, mode: .aggregatedOnly)
        var lastAgentMessage: String?
        var tokenUsage: TokenUsage?
        var errors: [String] = []
        var sawCompletion = false
        let jsonEncoder = JSONEncoder()
        jsonEncoder.outputFormatting = [.withoutEscapingSlashes]
        var jsonLines: [String] = []

        if outputMode == .jsonLines {
            jsonLines.append(encodeJSONLine(ThreadStartedEvent(threadID: conversationID.description), using: jsonEncoder))
            jsonLines.append(encodeJSONLine(TurnStartedEvent(), using: jsonEncoder))
        }

        var itemIndex = 0
        for result in events {
            switch result {
            case let .failure(error):
                let message = String(describing: error)
                errors.append(message)
                if outputMode == .jsonLines {
                    jsonLines.append(encodeJSONLine(ErrorJSONEvent(message: message), using: jsonEncoder))
                }

            case let .success(event):
                switch event {
                case let .outputItemDone(item):
                    if let message = StreamEventUtils.lastAssistantMessage(from: item) {
                        lastAgentMessage = message
                        if outputMode == .jsonLines {
                            jsonLines.append(encodeJSONLine(
                                ExecJSONItemCompletedEvent(
                                    item: CompletedItem(
                                        id: "item_\(itemIndex)",
                                        type: "agent_message",
                                        text: message
                                    )
                                ),
                                using: jsonEncoder
                            ))
                            itemIndex += 1
                        }
                    } else if outputMode == .jsonLines,
                              let reasoningText = reasoningText(from: item)
                    {
                        jsonLines.append(encodeJSONLine(
                            ExecJSONItemCompletedEvent(
                                item: CompletedItem(
                                    id: "item_\(itemIndex)",
                                    type: "reasoning",
                                    text: reasoningText
                                )
                            ),
                            using: jsonEncoder
                        ))
                        itemIndex += 1
                    }

                case let .completed(_, usage):
                    sawCompletion = true
                    tokenUsage = usage

                case .created,
                     .outputItemAdded,
                     .outputTextDelta,
                     .reasoningSummaryDelta,
                     .reasoningContentDelta,
                     .reasoningSummaryPartAdded,
                     .rateLimits:
                    continue
                }
            }
        }

        if !sawCompletion, errors.isEmpty {
            errors.append("stream closed before response.completed")
        }

        let lastMessageWrite = NonInteractiveInput.writeLastMessage(
            lastAgentMessage,
            path: lastMessageFile,
            writeFile: writeFile ?? defaultWriteFile
        )

        let exitCode: Int32 = errors.isEmpty ? 0 : 1
        var stderrMessages = errors
        stderrMessages.append(contentsOf: lastMessageWrite.stderrMessages)

        if outputMode == .jsonLines {
            if errors.isEmpty {
                jsonLines.append(encodeJSONLine(TurnCompletedEvent(usage: tokenUsage.map(JSONUsage.init)), using: jsonEncoder))
            } else {
                jsonLines.append(encodeJSONLine(TurnFailedEvent(error: errors.last ?? "unknown error"), using: jsonEncoder))
            }
        }

        let stdoutMessage: String?
        switch outputMode {
        case .human:
            stdoutMessage = lastAgentMessage
        case .jsonLines:
            stdoutMessage = jsonLines.joined(separator: "\n")
        }

        return NonInteractiveExecRunResult(
            exitCode: exitCode,
            stdoutMessage: stdoutMessage,
            stderrMessages: stderrMessages,
            lastAgentMessage: lastAgentMessage,
            tokenUsage: tokenUsage
        )
    }

    private enum ShellResponseFormat {
        case structured
        case freeform
        case unifiedExec
    }

    private static func executeFunctionCall(
        name: String,
        arguments: String,
        callID: String,
        cwd: URL,
        approvalPolicy: AskForApproval,
        sandboxPolicy: SandboxPolicy,
        shell: Shell,
        truncationPolicy: TruncationPolicy,
        environment: [String: String]
    ) async -> ResponseItem {
        let decoder = JSONDecoder()
        do {
            switch name {
            case "exec_command":
                let params = try decoder.decode(ExecCommandToolCallParams.self, from: Data(arguments.utf8))
                let requestedShell = params.shell.map(ShellResolver.getShellByModelProvidedPath) ?? shell
                return await executeUnifiedExecCommand(
                    command: requestedShell.deriveExecArgs(command: params.cmd, useLoginShell: params.login),
                    workdir: params.workdir,
                    timeoutMS: params.yieldTimeMS,
                    sandboxPermissions: params.sandboxPermissions,
                    callID: callID,
                    cwd: cwd,
                    approvalPolicy: approvalPolicy,
                    sandboxPolicy: sandboxPolicy,
                    truncationPolicy: params.maxOutputTokens.map { .tokens($0) } ?? truncationPolicy,
                    environment: environment
                )

            case "shell_command":
                let params = try decoder.decode(ShellCommandToolCallParams.self, from: Data(arguments.utf8))
                return await executeShellCommand(
                    toolName: name,
                    command: shell.deriveExecArgs(command: params.command, useLoginShell: params.login ?? true),
                    workdir: params.workdir,
                    timeoutMS: params.timeoutMS,
                    sandboxPermissions: params.sandboxPermissions ?? .useDefault,
                    callID: callID,
                    cwd: cwd,
                    approvalPolicy: approvalPolicy,
                    sandboxPolicy: sandboxPolicy,
                    truncationPolicy: truncationPolicy,
                    environment: environment,
                    responseFormat: .freeform
                )

            case "shell", "container.exec":
                let params = try decoder.decode(ShellToolCallParams.self, from: Data(arguments.utf8))
                return await executeShellCommand(
                    toolName: name,
                    command: params.command,
                    workdir: params.workdir,
                    timeoutMS: params.timeoutMS,
                    sandboxPermissions: params.sandboxPermissions ?? .useDefault,
                    callID: callID,
                    cwd: cwd,
                    approvalPolicy: approvalPolicy,
                    sandboxPolicy: sandboxPolicy,
                    truncationPolicy: truncationPolicy,
                    environment: environment,
                    responseFormat: .structured
                )

            case "write_stdin":
                let params = try decoder.decode(WriteStdinToolCallParams.self, from: Data(arguments.utf8))
                do {
                    let output = try await unifiedExecSessions.writeStdin(
                        sessionID: String(params.sessionID),
                        chars: params.chars,
                        yieldTimeMS: params.yieldTimeMS,
                        truncationPolicy: params.maxOutputTokens.map { .tokens($0) } ?? truncationPolicy
                    )
                    return functionOutput(
                        callID: callID,
                        content: formatUnifiedExecResponse(output),
                        success: true
                    )
                } catch {
                    return functionOutput(
                        callID: callID,
                        content: "write_stdin failed: \(String(describing: error))",
                        success: false
                    )
                }

            default:
                return functionOutput(
                    callID: callID,
                    content: "unsupported tool: \(name)",
                    success: false
                )
            }
        } catch {
            return functionOutput(
                callID: callID,
                content: "failed to parse \(name) arguments: \(String(describing: error))",
                success: false
            )
        }
    }

    private static func executeShellCommand(
        toolName: String,
        command: [String],
        workdir: String?,
        timeoutMS: UInt64?,
        sandboxPermissions: SandboxPermissions,
        callID: String,
        cwd: URL,
        approvalPolicy: AskForApproval,
        sandboxPolicy: SandboxPolicy,
        truncationPolicy: TruncationPolicy,
        environment: [String: String],
        responseFormat: ShellResponseFormat
    ) async -> ResponseItem {
        if sandboxPermissions.requiresEscalatedPermissions, approvalPolicy != .onRequest {
            return functionOutput(
                callID: callID,
                content: "approval policy is \(approvalPolicy); reject command — you cannot ask for escalated permissions if the approval policy is \(approvalPolicy)",
                success: false
            )
        }

        guard !command.isEmpty else {
            return functionOutput(callID: callID, content: "\(toolName) command is empty", success: false)
        }

        let commandCwd = resolveWorkdir(workdir, relativeTo: cwd)
        let output = await Task.detached(priority: .userInitiated) {
            runCommandSync(
                command: command,
                cwd: commandCwd,
                sandboxPolicy: sandboxPermissions.requiresEscalatedPermissions ? .dangerFullAccess : sandboxPolicy,
                timeoutMS: timeoutMS,
                environment: environment
            )
        }.value

        return functionOutput(
            callID: callID,
            content: formatShellResponse(output, truncationPolicy: truncationPolicy, format: responseFormat),
            success: output.exitCode == 0 && !output.timedOut
        )
    }

    private static func executeUnifiedExecCommand(
        command: [String],
        workdir: String?,
        timeoutMS: UInt64?,
        sandboxPermissions: SandboxPermissions,
        callID: String,
        cwd: URL,
        approvalPolicy: AskForApproval,
        sandboxPolicy: SandboxPolicy,
        truncationPolicy: TruncationPolicy,
        environment: [String: String]
    ) async -> ResponseItem {
        if sandboxPermissions.requiresEscalatedPermissions, approvalPolicy != .onRequest {
            return functionOutput(
                callID: callID,
                content: "approval policy is \(approvalPolicy); reject command — you cannot ask for escalated permissions if the approval policy is \(approvalPolicy)",
                success: false
            )
        }

        guard !command.isEmpty else {
            return functionOutput(callID: callID, content: "exec_command command is empty", success: false)
        }

        let commandCwd = resolveWorkdir(workdir, relativeTo: cwd)
        do {
            let output = try await unifiedExecSessions.start(
                command: command,
                cwd: commandCwd,
                sandboxPolicy: sandboxPermissions.requiresEscalatedPermissions ? .dangerFullAccess : sandboxPolicy,
                yieldTimeMS: timeoutMS ?? 10_000,
                truncationPolicy: truncationPolicy,
                environment: environment
            )
            return functionOutput(
                callID: callID,
                content: formatUnifiedExecResponse(output),
                success: output.exitCode.map { $0 == 0 } ?? true
            )
        } catch {
            return functionOutput(
                callID: callID,
                content: "exec_command failed: \(String(describing: error))",
                success: false
            )
        }
    }

    private static func completedOutputItems(from events: ResponseEventResults) -> [ResponseItem] {
        ResponseEventAggregator.aggregate(events, mode: .aggregatedOnly).compactMap { result in
            guard case let .success(.outputItemDone(item)) = result else {
                return nil
            }
            return item
        }
    }

    private static func toolCalls(from items: [ResponseItem]) -> [ResponseItem] {
        items.filter { item in
            switch item {
            case .functionCall, .localShellCall:
                return true
            case .message,
                 .reasoning,
                 .functionCallOutput,
                 .customToolCall,
                 .customToolCallOutput,
                 .webSearchCall,
                 .compaction,
                 .knownPersisted,
                 .other:
                return false
            }
        }
    }

    private static func containsFailure(_ events: ResponseEventResults) -> Bool {
        events.contains { result in
            if case .failure = result {
                return true
            }
            return false
        }
    }

    private static func functionOutput(callID: String, content: String, success: Bool) -> ResponseItem {
        .functionCallOutput(
            callID: callID,
            output: FunctionCallOutputPayload(content: content, success: success)
        )
    }

    private static func resolveWorkdir(_ workdir: String?, relativeTo cwd: URL) -> URL {
        guard let workdir, !workdir.isEmpty else {
            return cwd.standardizedFileURL
        }
        if workdir.hasPrefix("/") {
            return URL(fileURLWithPath: workdir, isDirectory: true).standardizedFileURL
        }
        return cwd.appendingPathComponent(workdir, isDirectory: true).standardizedFileURL
    }

    private static func runCommandSync(
        command: [String],
        cwd: URL,
        sandboxPolicy: SandboxPolicy,
        timeoutMS: UInt64?,
        environment: [String: String]
    ) -> ExecToolCallOutput {
        let start = Date()
        let launch: [String]
        var childEnvironment = ExecEnvironment.createEnv(policy: ShellEnvironmentPolicy(), environment: environment)

        if sandboxPolicy == .dangerFullAccess {
            launch = command
        } else {
            guard let absoluteCwd = try? AbsolutePath(absolutePath: cwd.standardizedFileURL.path) else {
                return ExecToolCallOutput(
                    exitCode: -1,
                    stdout: "",
                    stderr: "invalid sandbox cwd: \(cwd.path)",
                    aggregatedOutput: "invalid sandbox cwd: \(cwd.path)",
                    duration: 0
                )
            }
            launch = [SeatbeltSandbox.executablePath] + SeatbeltSandbox.commandArguments(
                command: command,
                sandboxPolicy: sandboxPolicy,
                sandboxPolicyCwd: absoluteCwd,
                environment: environment
            )
            childEnvironment["CODEX_SANDBOX"] = SeatbeltSandbox.sandboxEnvironmentValue
            if !sandboxPolicy.hasFullNetworkAccess {
                childEnvironment["CODEX_SANDBOX_NETWORK_DISABLED"] = "1"
            }
        }

        guard let executable = launch.first else {
            return ExecToolCallOutput(
                exitCode: -1,
                stdout: "",
                stderr: "command is empty",
                aggregatedOutput: "command is empty",
                duration: 0
            )
        }

        let process = Process()
        if executable.contains("/") {
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = Array(launch.dropFirst())
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = launch
        }
        process.currentDirectoryURL = cwd
        process.environment = childEnvironment

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let stdoutCapture = DataCapture()
        let stderrCapture = DataCapture()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty {
                stdoutCapture.append(data)
            }
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty {
                stderrCapture.append(data)
            }
        }

        var timedOut = false
        do {
            try process.run()
        } catch {
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            let message = "failed to launch command: \(String(describing: error))"
            return ExecToolCallOutput(
                exitCode: -1,
                stdout: "",
                stderr: message,
                aggregatedOutput: message,
                duration: Date().timeIntervalSince(start)
            )
        }

        let timeoutSeconds = timeoutMS.map { TimeInterval($0) / 1_000 }
        while process.isRunning {
            if let timeoutSeconds, Date().timeIntervalSince(start) >= timeoutSeconds {
                timedOut = true
                process.terminate()
                Thread.sleep(forTimeInterval: 0.2)
                if process.isRunning {
                    Darwin.kill(process.processIdentifier, SIGKILL)
                }
                break
            }
            Thread.sleep(forTimeInterval: 0.02)
        }
        process.waitUntilExit()

        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil
        var stdoutData = stdoutCapture.snapshot()
        stdoutData.append(stdoutPipe.fileHandleForReading.readDataToEndOfFile())
        var stderrData = stderrCapture.snapshot()
        stderrData.append(stderrPipe.fileHandleForReading.readDataToEndOfFile())

        let stdout = String(decoding: stdoutData, as: UTF8.self)
        let stderr = String(decoding: stderrData, as: UTF8.self)
        let aggregatedOutput: String
        if stdout.isEmpty {
            aggregatedOutput = stderr
        } else if stderr.isEmpty {
            aggregatedOutput = stdout
        } else {
            aggregatedOutput = stdout + stderr
        }

        return ExecToolCallOutput(
            exitCode: Int(process.terminationStatus),
            stdout: stdout,
            stderr: stderr,
            aggregatedOutput: aggregatedOutput,
            duration: Date().timeIntervalSince(start),
            timedOut: timedOut
        )
    }

    private static func formatShellResponse(
        _ output: ExecToolCallOutput,
        truncationPolicy: TruncationPolicy,
        format: ShellResponseFormat
    ) -> String {
        switch format {
        case .structured:
            return formatStructuredShellResponse(output, truncationPolicy: truncationPolicy)
        case .freeform:
            return formatFreeformShellResponse(output, truncationPolicy: truncationPolicy)
        case .unifiedExec:
            return formatUnifiedExecResponse(output, truncationPolicy: truncationPolicy)
        }
    }

    private static func formatStructuredShellResponse(
        _ output: ExecToolCallOutput,
        truncationPolicy: TruncationPolicy
    ) -> String {
        struct Metadata: Encodable {
            let exitCode: Int
            let durationSeconds: Double

            enum CodingKeys: String, CodingKey {
                case exitCode = "exit_code"
                case durationSeconds = "duration_seconds"
            }
        }
        struct Payload: Encodable {
            let output: String
            let metadata: Metadata
        }

        let payload = Payload(
            output: ExecOutputFormatter.formatOutputString(output, truncationPolicy: truncationPolicy),
            metadata: Metadata(
                exitCode: output.exitCode,
                durationSeconds: roundedDurationSeconds(output.duration)
            )
        )
        guard let data = try? JSONEncoder().encode(payload),
              let text = String(data: data, encoding: .utf8)
        else {
            return ExecOutputFormatter.formatOutputString(output, truncationPolicy: truncationPolicy)
        }
        return text
    }

    private static func formatFreeformShellResponse(
        _ output: ExecToolCallOutput,
        truncationPolicy: TruncationPolicy
    ) -> String {
        let content = ExecOutputFormatter.buildContentWithTimeout(output)
        let formattedOutput = Truncation.truncateText(content, policy: truncationPolicy)
        let totalLines = lineCount(content)
        var sections = [
            "Exit code: \(output.exitCode)",
            "Wall time: \(roundedDurationSeconds(output.duration)) seconds"
        ]
        if totalLines != lineCount(formattedOutput) {
            sections.append("Total output lines: \(totalLines)")
        }
        sections.append("Output:")
        sections.append(formattedOutput)
        return sections.joined(separator: "\n")
    }

    private static func formatUnifiedExecResponse(
        _ output: ExecToolCallOutput,
        truncationPolicy: TruncationPolicy
    ) -> String {
        [
            "Wall time: \(String(format: "%.4f", locale: Locale(identifier: "en_US_POSIX"), output.duration)) seconds",
            "Process exited with code \(output.exitCode)",
            "Output:",
            ExecOutputFormatter.formatOutputString(output, truncationPolicy: truncationPolicy)
        ].joined(separator: "\n")
    }

    private static func formatUnifiedExecResponse(_ output: UnifiedExecToolOutput) -> String {
        var sections: [String] = []
        if !output.chunkID.isEmpty {
            sections.append("Chunk ID: \(output.chunkID)")
        }
        sections.append("Wall time: \(String(format: "%.4f", locale: Locale(identifier: "en_US_POSIX"), output.duration)) seconds")
        if let exitCode = output.exitCode {
            sections.append("Process exited with code \(exitCode)")
        }
        if let processID = output.processID {
            sections.append("Process running with session ID \(processID)")
        }
        if let originalTokenCount = output.originalTokenCount {
            sections.append("Original token count: \(originalTokenCount)")
        }
        sections.append("Output:")
        sections.append(output.output)
        return sections.joined(separator: "\n")
    }

    private static func roundedDurationSeconds(_ duration: TimeInterval) -> Double {
        (duration * 10).rounded() / 10
    }

    private static func lineCount(_ text: String) -> Int {
        text.split(whereSeparator: \.isNewline).count
    }

    private static func reasoningText(from item: ResponseItem) -> String? {
        guard case let .reasoning(_, _, content, _) = item else {
            return nil
        }
        let text = content?.compactMap { item -> String? in
            if case let .reasoningText(text) = item {
                return text
            }
            return nil
        }.joined()
        return text?.isEmpty == false ? text : nil
    }

    private static func defaultWriteFile(path: String, contents: String) throws {
        try contents.write(to: URL(fileURLWithPath: path), atomically: true, encoding: .utf8)
    }

    private static func encodeJSONLine<T: Encodable>(_ value: T, using encoder: JSONEncoder) -> String {
        do {
            return String(decoding: try encoder.encode(value), as: UTF8.self)
        } catch {
            return #"{"type":"error","message":"failed to encode exec event"}"#
        }
    }
}

private final class DataCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ chunk: Data) {
        lock.withLock {
            data.append(chunk)
        }
    }

    func snapshot() -> Data {
        lock.withLock {
            data
        }
    }

    func snapshot(from offset: Int) -> Data {
        lock.withLock {
            guard offset < data.count else {
                return Data()
            }
            return data.subdata(in: offset..<data.count)
        }
    }

    var count: Int {
        lock.withLock {
            data.count
        }
    }
}

private struct UnifiedExecToolOutput: Sendable {
    let chunkID: String
    let duration: TimeInterval
    let output: String
    let processID: String?
    let exitCode: Int?
    let originalTokenCount: Int?
}

private actor UnifiedExecSessionRegistry {
    private struct Session {
        let id: String
        let process: Process
        let stdinPipe: Pipe
        let stdoutPipe: Pipe
        let stderrPipe: Pipe
        let stdoutCapture: DataCapture
        let stderrCapture: DataCapture
        var stdoutOffset: Int
        var stderrOffset: Int
        let startedAt: Date
    }

    private var sessions: [String: Session] = [:]

    func start(
        command: [String],
        cwd: URL,
        sandboxPolicy: SandboxPolicy,
        yieldTimeMS: UInt64,
        truncationPolicy: TruncationPolicy,
        environment: [String: String]
    ) throws -> UnifiedExecToolOutput {
        let start = Date()
        let sessionID = allocateSessionID()
        let launch = try launchCommand(command: command, cwd: cwd, sandboxPolicy: sandboxPolicy, environment: environment)
        let process = Process()
        if launch.executable.contains("/") {
            process.executableURL = URL(fileURLWithPath: launch.executable)
            process.arguments = launch.arguments
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [launch.executable] + launch.arguments
        }
        process.currentDirectoryURL = cwd
        process.environment = launch.environment

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let stdoutCapture = DataCapture()
        let stderrCapture = DataCapture()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        attachCapture(stdoutPipe, to: stdoutCapture)
        attachCapture(stderrPipe, to: stderrCapture)

        do {
            try process.run()
        } catch {
            detach(stdoutPipe, stderrPipe)
            throw UnifiedExecError.createSession(String(describing: error))
        }

        waitUntilDeadlineOrExit(process: process, startedAt: start, yieldTimeMS: yieldTimeMS)

        if process.isRunning {
            let stdout = stdoutCapture.snapshot()
            let stderr = stderrCapture.snapshot()
            sessions[sessionID] = Session(
                id: sessionID,
                process: process,
                stdinPipe: stdinPipe,
                stdoutPipe: stdoutPipe,
                stderrPipe: stderrPipe,
                stdoutCapture: stdoutCapture,
                stderrCapture: stderrCapture,
                stdoutOffset: stdout.count,
                stderrOffset: stderr.count,
                startedAt: start
            )
            return makeOutput(
                stdout: stdout,
                stderr: stderr,
                duration: Date().timeIntervalSince(start),
                processID: sessionID,
                exitCode: nil,
                truncationPolicy: truncationPolicy
            )
        }

        detach(stdoutPipe, stderrPipe)
        let stdout = readFinalData(pipe: stdoutPipe, capture: stdoutCapture)
        let stderr = readFinalData(pipe: stderrPipe, capture: stderrCapture)
        return makeOutput(
            stdout: stdout,
            stderr: stderr,
            duration: Date().timeIntervalSince(start),
            processID: nil,
            exitCode: Int(process.terminationStatus),
            truncationPolicy: truncationPolicy
        )
    }

    func writeStdin(
        sessionID: String,
        chars: String,
        yieldTimeMS: UInt64,
        truncationPolicy: TruncationPolicy
    ) throws -> UnifiedExecToolOutput {
        guard var session = sessions[sessionID] else {
            throw UnifiedExecError.unknownSessionID(processID: sessionID)
        }

        let start = Date()
        if !chars.isEmpty {
            guard let data = chars.data(using: .utf8) else {
                throw UnifiedExecError.writeToStdin
            }
            do {
                try session.stdinPipe.fileHandleForWriting.write(contentsOf: data)
            } catch {
                throw UnifiedExecError.writeToStdin
            }
            Thread.sleep(forTimeInterval: 0.1)
        }

        waitUntilDeadlineOrExit(process: session.process, startedAt: start, yieldTimeMS: yieldTimeMS)

        let stdout = session.stdoutCapture.snapshot(from: session.stdoutOffset)
        let stderr = session.stderrCapture.snapshot(from: session.stderrOffset)
        session.stdoutOffset = session.stdoutCapture.count
        session.stderrOffset = session.stderrCapture.count

        if session.process.isRunning {
            sessions[sessionID] = session
            return makeOutput(
                stdout: stdout,
                stderr: stderr,
                duration: Date().timeIntervalSince(start),
                processID: sessionID,
                exitCode: nil,
                truncationPolicy: truncationPolicy
            )
        }

        detach(session.stdoutPipe, session.stderrPipe)
        var finalStdout = stdout
        finalStdout.append(session.stdoutPipe.fileHandleForReading.readDataToEndOfFile())
        var finalStderr = stderr
        finalStderr.append(session.stderrPipe.fileHandleForReading.readDataToEndOfFile())
        sessions.removeValue(forKey: sessionID)
        return makeOutput(
            stdout: finalStdout,
            stderr: finalStderr,
            duration: Date().timeIntervalSince(start),
            processID: nil,
            exitCode: Int(session.process.terminationStatus),
            truncationPolicy: truncationPolicy
        )
    }

    private func allocateSessionID() -> String {
        var candidate: String
        repeat {
            candidate = String(Int.random(in: 1_000..<100_000))
        } while sessions[candidate] != nil
        return candidate
    }

    private func launchCommand(
        command: [String],
        cwd: URL,
        sandboxPolicy: SandboxPolicy,
        environment: [String: String]
    ) throws -> (executable: String, arguments: [String], environment: [String: String]) {
        var childEnvironment = ExecEnvironment.createEnv(policy: ShellEnvironmentPolicy(), environment: environment)
        let launch: [String]
        if sandboxPolicy == .dangerFullAccess {
            launch = command
        } else {
            let absoluteCwd = try AbsolutePath(absolutePath: cwd.standardizedFileURL.path)
            launch = [SeatbeltSandbox.executablePath] + SeatbeltSandbox.commandArguments(
                command: command,
                sandboxPolicy: sandboxPolicy,
                sandboxPolicyCwd: absoluteCwd,
                environment: environment
            )
            childEnvironment["CODEX_SANDBOX"] = SeatbeltSandbox.sandboxEnvironmentValue
            if !sandboxPolicy.hasFullNetworkAccess {
                childEnvironment["CODEX_SANDBOX_NETWORK_DISABLED"] = "1"
            }
        }

        guard let executable = launch.first else {
            throw UnifiedExecError.missingCommandLine
        }
        return (executable, Array(launch.dropFirst()), childEnvironment)
    }

    private func attachCapture(_ pipe: Pipe, to capture: DataCapture) {
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty {
                capture.append(data)
            }
        }
    }

    private func detach(_ pipes: Pipe...) {
        for pipe in pipes {
            pipe.fileHandleForReading.readabilityHandler = nil
        }
    }

    private func waitUntilDeadlineOrExit(process: Process, startedAt: Date, yieldTimeMS: UInt64) {
        let deadline = startedAt.addingTimeInterval(TimeInterval(yieldTimeMS) / 1_000)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }
        if !process.isRunning {
            process.waitUntilExit()
        }
    }

    private func readFinalData(pipe: Pipe, capture: DataCapture) -> Data {
        var data = capture.snapshot()
        data.append(pipe.fileHandleForReading.readDataToEndOfFile())
        return data
    }

    private func makeOutput(
        stdout: Data,
        stderr: Data,
        duration: TimeInterval,
        processID: String?,
        exitCode: Int?,
        truncationPolicy: TruncationPolicy
    ) -> UnifiedExecToolOutput {
        let stdoutText = String(decoding: stdout, as: UTF8.self)
        let stderrText = String(decoding: stderr, as: UTF8.self)
        let rawOutput = stdoutText.isEmpty ? stderrText : (stderrText.isEmpty ? stdoutText : stdoutText + stderrText)
        let output = Truncation.formattedTruncateText(rawOutput, policy: truncationPolicy)
        return UnifiedExecToolOutput(
            chunkID: randomChunkID(),
            duration: duration,
            output: output,
            processID: processID,
            exitCode: exitCode,
            originalTokenCount: rawOutput.split(whereSeparator: \.isWhitespace).count
        )
    }

    private func randomChunkID() -> String {
        String((0..<6).map { _ in "0123456789abcdef".randomElement()! })
    }
}

private struct ThreadStartedEvent: Encodable {
    let type = "thread.started"
    let threadID: String

    enum CodingKeys: String, CodingKey {
        case type
        case threadID = "thread_id"
    }
}

private struct TurnStartedEvent: Encodable {
    let type = "turn.started"
}

private struct CompletedItem: Encodable {
    let id: String
    let type: String
    let text: String
}

private struct ExecJSONItemCompletedEvent: Encodable {
    let type = "item.completed"
    let item: CompletedItem
}

private struct TurnCompletedEvent: Encodable {
    let type = "turn.completed"
    let usage: JSONUsage?
}

private struct TurnFailedEvent: Encodable {
    let type = "turn.failed"
    let error: String
}

private struct ErrorJSONEvent: Encodable {
    let type = "error"
    let message: String
}

private struct JSONUsage: Encodable, Equatable, Sendable {
    let inputTokens: Int64
    let cachedInputTokens: Int64
    let outputTokens: Int64
    let reasoningOutputTokens: Int64
    let totalTokens: Int64

    init(_ usage: TokenUsage) {
        inputTokens = usage.inputTokens
        cachedInputTokens = usage.cachedInputTokens
        outputTokens = usage.outputTokens
        reasoningOutputTokens = usage.reasoningOutputTokens
        totalTokens = usage.totalTokens
    }

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case cachedInputTokens = "cached_input_tokens"
        case outputTokens = "output_tokens"
        case reasoningOutputTokens = "reasoning_output_tokens"
        case totalTokens = "total_tokens"
    }
}
