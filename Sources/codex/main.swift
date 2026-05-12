import CodexApplyPatch
import CodexAppServer
import CodexChatGPT
import CodexCLI
import CodexCore
import CodexMCPServer
import CodexResponsesAPIProxy
import CodexStdioToUDS
import Darwin
import Foundation

if let result = ApplyPatchCommand.runForArg0Dispatch(
    argv0: CommandLine.arguments.first ?? "",
    arguments: Array(CommandLine.arguments.dropFirst()),
    stdin: { FileHandle.standardInput.readDataToEndOfFile() }
) {
    if !result.stdout.isEmpty {
        print(result.stdout, terminator: "")
    }
    if !result.stderr.isEmpty {
        fputs(result.stderr, stderr)
    }
    exit(result.exitCode)
}

DotenvLoader.loadCodexDotenv()

let codexAliasDirectory: ApplyPatchAliasDirectory?
do {
    codexAliasDirectory = try ApplyPatchCommand.prependPathEntryForCodexAliases()
} catch {
    codexAliasDirectory = nil
    fputs("WARNING: proceeding, even though we could not update PATH: \(error)\n", stderr)
}

ProcessHardening.preMainHardening()

let cli = CodexCLI()
let exitCode = await cli.runAsync(
    arguments: Array(CommandLine.arguments.dropFirst()),
    applyRunner: { request in
        let (codexHome, settings) = try resolvedAuthSettings(overrides: request.configOverrides)
        let client = CloudTaskClient(configuration: CloudTaskClientConfiguration(
            chatgptBaseURL: settings.chatgptBaseURL,
            codexHome: codexHome,
            authCredentialsStoreMode: settings.cliAuthCredentialsStoreMode
        ))
        return try await client.applyTask(taskID: request.taskID).message
    },
    loginRunner: runLoginCommand,
    logoutRunner: runLogoutCommand,
    featuresRunner: runFeaturesCommand,
    execRunner: { request in try await runExecCommand(request) },
    computerUseRunner: runComputerUseCommand,
    reviewRunner: runReviewCommand,
    resumeRunner: runResumeCommand,
    forkRunner: runForkCommand,
    execServerRunner: runExecServerCommand,
    mcpServerRunner: runMcpServerCommand,
    appServerRunner: runAppServerCommand,
    appRunner: runAppCommand,
    execPolicyRunner: runExecPolicyCommand,
    sandboxRunner: runSandboxCommand,
    debugRunner: { request in try await DebugCommandRuntime.run(request) },
    mcpRunner: { request in try await McpCommandRuntime.run(request) },
    stdioToUDSRunner: runStdioToUDSCommand,
    pluginRunner: runPluginCommand,
    cloudRunner: runCloudCommand,
    responsesAPIProxyRunner: runResponsesAPIProxyCommand,
    updateRunner: runUpdateCommand
)
exit(exitCode)

private func resolvedAuthSettings(
    overrides: CliConfigOverrides,
    loaderOverrides: ConfigLayerLoaderOverrides = ConfigLayerLoaderOverrides()
) throws -> (codexHome: URL, settings: CodexRuntimeConfig) {
    let codexHome = try CodexHome.find()
    let settings = try CodexConfigLoader.load(
        codexHome: codexHome,
        cwd: URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true),
        overrides: overrides,
        managedConfigOverrides: loaderOverrides
    )
    return (codexHome, settings)
}

private func execLoaderOverrides(options: CodexCLI.ExecCommandOptions) -> ConfigLayerLoaderOverrides {
    ConfigLayerLoaderOverrides(
        ignoreUserConfig: options.ignoreUserConfig,
        ignoreUserAndProjectExecPolicyRules: options.ignoreRules
    )
}

private func runLoginCommand(_ request: CodexCLI.LoginCommandRequest) async throws -> CodexCLI.CommandExecutionResult {
    switch request.action {
    case .status:
        let (codexHome, settings) = try resolvedAuthSettings(overrides: request.configOverrides)
        switch try CodexAuthStorage.authStatus(codexHome: codexHome, mode: settings.cliAuthCredentialsStoreMode) {
        case let .apiKey(apiKey):
            return CodexCLI.CommandExecutionResult(
                exitCode: 0,
                stderrMessage: "Logged in using an API key - \(safeFormatAPIKey(apiKey))"
            )
        case .chatGPT:
            return CodexCLI.CommandExecutionResult(exitCode: 0, stderrMessage: "Logged in using ChatGPT")
        case .notLoggedIn:
            return CodexCLI.CommandExecutionResult(exitCode: 1, stderrMessage: "Not logged in")
        }

    case .withAPIKeyFromStdin:
        let readResult = readAPIKeyFromStdin()
        guard readResult.exitCode == 0, let apiKey = readResult.apiKey else {
            return CodexCLI.CommandExecutionResult(exitCode: readResult.exitCode, stderrMessage: readResult.message)
        }
        let (codexHome, settings) = try resolvedAuthSettings(overrides: request.configOverrides)
        if settings.forcedLoginMethod == .chatgpt {
            return CodexCLI.CommandExecutionResult(
                exitCode: 1,
                stderrMessage: "\(readResult.message)\nAPI key login is disabled. Use ChatGPT login instead."
            )
        }
        try CodexAuthStorage.loginWithAPIKey(
            codexHome: codexHome,
            apiKey: apiKey,
            mode: settings.cliAuthCredentialsStoreMode
        )
        return CodexCLI.CommandExecutionResult(
            exitCode: 0,
            stderrMessage: "\(readResult.message)\nSuccessfully logged in"
        )

    case .chatGPT:
        let (codexHome, settings) = try resolvedAuthSettings(overrides: request.configOverrides)
        if settings.forcedLoginMethod == .api {
            return CodexCLI.CommandExecutionResult(
                exitCode: 1,
                stderrMessage: "ChatGPT login is disabled. Use API key login instead."
            )
        }
        do {
            try await ChatGPTLogin.run(
                options: ChatGPTLoginOptions(
                    codexHome: codexHome,
                    forcedChatGPTWorkspaceID: settings.forcedChatGPTWorkspaceID,
                    authCredentialsStoreMode: settings.cliAuthCredentialsStoreMode
                ),
                messageSink: { message in
                    fputs(message.renderedText + "\n", Darwin.stderr)
                }
            )
            return CodexCLI.CommandExecutionResult(exitCode: 0, stderrMessage: "Successfully logged in")
        } catch {
            return CodexCLI.CommandExecutionResult(
                exitCode: 1,
                stderrMessage: "Error logging in: \(String(describing: error))"
            )
        }

    case let .deviceCode(issuerBaseURL, clientID):
        let (codexHome, settings) = try resolvedAuthSettings(overrides: request.configOverrides)
        if settings.forcedLoginMethod == .api {
            return CodexCLI.CommandExecutionResult(
                exitCode: 1,
                stderrMessage: "ChatGPT login is disabled. Use API key login instead."
            )
        }
        do {
            try await ChatGPTDeviceCodeLogin.run(
                options: ChatGPTDeviceCodeLoginOptions(
                    codexHome: codexHome,
                    issuer: issuerBaseURL ?? ChatGPTDeviceCodeLogin.defaultIssuer,
                    clientID: clientID ?? CodexAuthStorage.refreshClientID,
                    forcedChatGPTWorkspaceID: settings.forcedChatGPTWorkspaceID,
                    authCredentialsStoreMode: settings.cliAuthCredentialsStoreMode,
                    cliVersion: CodexCLI.version
                ),
                messageSink: { message in
                    print(message.renderedText)
                }
            )
            return CodexCLI.CommandExecutionResult(exitCode: 0, stderrMessage: "Successfully logged in")
        } catch {
            return CodexCLI.CommandExecutionResult(
                exitCode: 1,
                stderrMessage: "Error logging in with device code: \(String(describing: error))"
            )
        }
    }
}

private func runLogoutCommand(_ request: CodexCLI.LogoutCommandRequest) async throws -> CodexCLI.CommandExecutionResult {
    let (codexHome, settings) = try resolvedAuthSettings(overrides: request.configOverrides)
    let removed = try CodexAuthStorage.logout(codexHome: codexHome, mode: settings.cliAuthCredentialsStoreMode)
    return CodexCLI.CommandExecutionResult(
        exitCode: 0,
        stderrMessage: removed ? "Successfully logged out" : "Not logged in"
    )
}

private func runFeaturesCommand(_ request: CodexCLI.FeaturesCommandRequest) async throws -> CodexCLI.CommandExecutionResult {
    switch request.action {
    case .list:
        let (_, settings) = try resolvedAuthSettings(overrides: request.configOverrides)
        let rows = FeatureRegistry.specs
            .map { spec in (name: spec.key, stage: spec.stage.listName, enabled: settings.features.isEnabled(spec.id)) }
            .sorted { $0.name < $1.name }
        let nameWidth = rows.map(\.name.count).max() ?? 0
        let stageWidth = rows.map(\.stage.count).max() ?? 0
        let output = rows
            .map { row in
                "\(row.name.padding(toLength: nameWidth, withPad: " ", startingAt: 0))  \(row.stage.padding(toLength: stageWidth, withPad: " ", startingAt: 0))  \(row.enabled)"
            }
            .joined(separator: "\n")
        return CodexCLI.CommandExecutionResult(exitCode: 0, stdoutMessage: output)
    case let .enable(feature):
        let codexHome = try CodexHome.find()
        try ConfigFeatureEditor.setFeatureEnabled(
            codexHome: codexHome,
            feature: feature,
            enabled: true,
            profile: request.configProfile
        )
        let warning = underDevelopmentFeatureWarning(codexHome: codexHome, feature: feature, profile: request.configProfile)
        return CodexCLI.CommandExecutionResult(
            exitCode: 0,
            stdoutMessage: "Enabled feature `\(feature)` in config.toml.",
            stderrMessage: warning
        )
    case let .disable(feature):
        let codexHome = try CodexHome.find()
        try ConfigFeatureEditor.setFeatureEnabled(
            codexHome: codexHome,
            feature: feature,
            enabled: false,
            profile: request.configProfile
        )
        return CodexCLI.CommandExecutionResult(
            exitCode: 0,
            stdoutMessage: "Disabled feature `\(feature)` in config.toml."
        )
    }
}

private func underDevelopmentFeatureWarning(codexHome: URL, feature: String, profile: String?) -> String? {
    guard profile == nil else {
        return nil
    }
    guard let spec = FeatureRegistry.specs.first(where: { $0.key == feature }),
          spec.stage == .underDevelopment
    else {
        return nil
    }
    let configPath = codexHome.appendingPathComponent("config.toml", isDirectory: false).path
    return "Under-development features enabled: \(feature). Under-development features are incomplete and may behave unpredictably. To suppress this warning, set `suppress_unstable_features_warning = true` in \(configPath)."
}

private func runExecCommand(
    _ request: CodexCLI.ExecCommandRequest,
    baseInstructionsOverride: String? = nil
) async throws -> CodexCLI.CommandExecutionResult {
    let operation = try request.resolvedInitialOperation(
        stdinIsTerminal: isatty(STDIN_FILENO) != 0,
        readStdin: readUTF8FromStdin,
        readFile: { path in
            try Data(contentsOf: URL(fileURLWithPath: path))
        }
    )

    let cwd = resolveExecWorkingDirectory(from: request.arguments)
    switch operation {
    case let .userTurn(promptResolution, outputSchema):
        return try await runNonInteractiveExec(
            promptResolution: promptResolution,
            outputSchema: outputSchema,
            options: request.options,
            arguments: request.arguments,
            configOverrides: request.configOverrides,
            cwd: cwd,
            baseInstructionsOverride: baseInstructionsOverride,
            sessionStartSource: .startup
        )

    case let .review(reviewRequest):
        let resolved = try ReviewPrompts.resolveReviewRequest(
            reviewRequest,
            cwd: cwd.path,
            mergeBaseWithHead: gitMergeBaseWithHead
        )
        return try await runNonInteractiveExec(
            promptResolution: NonInteractivePromptResolution(prompt: resolved.prompt),
            outputSchema: nil,
            options: request.options,
            arguments: request.arguments,
            configOverrides: request.configOverrides,
            cwd: cwd,
            baseInstructionsOverride: baseInstructionsOverride,
            sessionStartSource: .startup
        )

    case let .resume(sessionID, last, all, promptResolution, outputSchema):
        let codexHome = try CodexHome.find()
        let resumeResolution = try ResumeCommandResolver.resolve(
            CodexCLI.ResumeCommandRequest(sessionID: sessionID, last: last, all: all),
            codexHome: codexHome
        )
        guard case let .session(session) = resumeResolution else {
            return CodexCLI.CommandExecutionResult(
                exitCode: 0,
                stdoutMessage: ResumeCommandFormatter.render(resumeResolution)
            )
        }
        let initialHistory = try RolloutRecorder.getRolloutHistory(path: URL(fileURLWithPath: session.path))
        let responseHistory = RolloutRecorder.reconstructResponseHistory(from: initialHistory.rolloutItems)
        return try await runNonInteractiveExec(
            promptResolution: promptResolution,
            outputSchema: outputSchema,
            options: request.options,
            arguments: request.arguments,
            configOverrides: request.configOverrides,
            cwd: cwd,
            conversationID: session.conversationID,
            history: responseHistory,
            rolloutPath: URL(fileURLWithPath: session.path),
            baseInstructionsOverride: baseInstructionsOverride,
            sessionStartSource: .resume
        )
    }
}

private func runReviewCommand(_ request: CodexCLI.ReviewCommandRequest) async throws -> CodexCLI.CommandExecutionResult {
    let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    let reviewRequest = try request.target.resolvedReviewRequest(
        stdinIsTerminal: isatty(STDIN_FILENO) != 0,
        readStdin: readUTF8FromStdin
    )
    let resolved = try ReviewPrompts.resolveReviewRequest(
        reviewRequest,
        cwd: cwd.path,
        mergeBaseWithHead: gitMergeBaseWithHead
    )
    return try await runNonInteractiveExec(
        promptResolution: NonInteractivePromptResolution(prompt: resolved.prompt),
        outputSchema: nil,
        options: CodexCLI.ExecCommandOptions(),
        arguments: [],
        configOverrides: request.configOverrides,
        cwd: cwd
    )
}

private func runComputerUseCommand(_ request: CodexCLI.ComputerUseCommandRequest) async throws -> CodexCLI.CommandExecutionResult {
    var parsedRequest: CodexCLI.ExecCommandRequest?
    var parseError: String?
    let parseExitCode = await CodexCLI().runAsync(
        arguments: ["exec"] + request.arguments,
        stdout: { _ in },
        stderr: { parseError = $0 },
        execRunner: { execRequest in
            parsedRequest = execRequest
            return CodexCLI.CommandExecutionResult(exitCode: 0)
        }
    )
    guard parseExitCode == 0, let parsedRequest else {
        return CodexCLI.CommandExecutionResult(
            exitCode: parseExitCode,
            stderrMessage: parseError
        )
    }

    let execRequest = CodexCLI.ExecCommandRequest(
        arguments: parsedRequest.arguments,
        action: parsedRequest.action,
        options: parsedRequest.options,
        configOverrides: request.configOverrides
    )
    return try await runExecCommand(execRequest, baseInstructionsOverride: CodexPrompts.computerUsePrompt)
}

private func runMcpServerCommand(_ request: CodexCLI.McpServerCommandRequest) async throws -> CodexCLI.CommandExecutionResult {
    try await CodexMCPServer.run(
        codexToolRunner: { toolCall in
            let execRequest = CodexCLI.ExecCommandRequest(
                arguments: mcpExecArguments(for: toolCall),
                action: .run(prompt: toolCall.prompt),
                options: CodexCLI.ExecCommandOptions(),
                configOverrides: mcpConfigOverrides(for: toolCall, rootOverrides: request.configOverrides)
            )
            let result = try await runExecCommand(execRequest, baseInstructionsOverride: toolCall.baseInstructions)
            return CodexMCPToolResult(
                text: mcpToolText(for: result),
                isError: result.exitCode != 0
            )
        },
        codexReplyRunner: { reply in
            let execRequest = CodexCLI.ExecCommandRequest(
                arguments: ["resume", reply.conversationID, reply.prompt],
                action: .resume(CodexCLI.ExecResumeCommand(
                    sessionID: reply.conversationID,
                    last: false,
                    prompt: reply.prompt
                )),
                options: CodexCLI.ExecCommandOptions(),
                configOverrides: request.configOverrides
            )
            let result = try await runExecCommand(execRequest, baseInstructionsOverride: nil)
            return CodexMCPToolResult(
                text: mcpToolText(for: result),
                isError: result.exitCode != 0
            )
        }
    )
    return CodexCLI.CommandExecutionResult(exitCode: 0)
}

private func runAppServerCommand(_ request: CodexCLI.AppServerCommandRequest) async throws -> CodexCLI.CommandExecutionResult {
    switch request.action {
    case .run, .remoteControl:
        let websocketAuth = try AppServerWebsocketAuthValidator.settings(from: request.websocketAuth)
        let codexHome = try CodexHome.find()
        let settings = try CodexConfigLoader.load(
            codexHome: codexHome,
            overrides: request.configOverrides
        )
        let stateStore: SQLiteAgentGraphStore?
        do {
            stateStore = try CodexAppServer.defaultStateStore(codexHome: codexHome, runtimeConfig: settings)
        } catch {
            fputs("failed to initialize sqlite state db: \(error)\n", stderr)
            stateStore = nil
        }
        try AppServerExecutableTransportValidator.validateSupportedTransport(
            request.listenTransport,
            websocketAuth: websocketAuth,
            remoteControlFeatureEnabled: settings.features.isEnabled(.remoteControl),
            stateStoreAvailable: stateStore != nil
        )
        let remoteControlEnabled = settings.features.isEnabled(.remoteControl) && stateStore != nil
        let remoteControlStatusSnapshot = CodexAppServerConfiguration.RemoteControlStatusSnapshot(
            status: remoteControlEnabled ? .connecting : .disabled,
            installationID: try InstallationIDResolver.resolve(codexHome: codexHome),
            environmentID: nil
        )
        let configuration = CodexAppServerConfiguration(
            codexHome: codexHome,
            defaultModelProvider: settings.selectedModelProviderID,
            version: CodexCLI.version,
            requiresOpenAIAuth: settings.selectedModelProvider?.requiresOpenAIAuth ?? true,
            authCredentialsStoreMode: settings.cliAuthCredentialsStoreMode,
            activeProfile: settings.activeProfile,
            stateStore: stateStore,
            remoteControlStatusSnapshot: remoteControlStatusSnapshot
        )
        switch request.listenTransport {
        case .stdio:
            try CodexAppServer.run(configuration: configuration)
        case let .webSocket(host, port):
            let authPolicy = try AppServerWebsocketAuthPolicyBuilder.policy(from: websocketAuth)
            try await AppServerWebSocketTransport(
                configuration: configuration,
                authPolicy: authPolicy
            ).run(host: host, port: port) { url in
                printAppServerWebSocketStartupBanner(listenURL: url)
            }
        case let .unixSocket(socketPath):
            try await AppServerWebSocketTransport(configuration: configuration).run(socketPath: socketPath)
        case .off:
            throw AppServerExecutableTransportError.liveTransportPending(request.listenTransport.listenURLDescription)
        }
        return CodexCLI.CommandExecutionResult(exitCode: 0)
    case let .proxy(socketPath):
        let resolvedSocketPath: String
        if let socketPath {
            resolvedSocketPath = socketPath
        } else {
            let codexHome = try CodexHome.find()
            resolvedSocketPath = codexHome
                .appendingPathComponent("app-server-control", isDirectory: true)
                .appendingPathComponent("app-server-control.sock")
                .path
        }
        try StdioToUDS.run(socketPath: resolvedSocketPath)
        return CodexCLI.CommandExecutionResult(exitCode: 0)
    case let .generateTS(outDir, prettier, experimental):
        return try runAppServerGenerator(
            subcommand: "generate-ts",
            arguments: buildGeneratorArguments(
                outDir: outDir,
                prettier: prettier,
                experimental: experimental
            )
        )
    case let .generateJSONSchema(outDir, experimental):
        return try runAppServerGenerator(
            subcommand: "generate-json-schema",
            arguments: buildGeneratorArguments(outDir: outDir, experimental: experimental)
        )
    case let .generateInternalJSONSchema(outDir):
        return try runAppServerGenerator(
            subcommand: "generate-internal-json-schema",
            arguments: ["--out", outDir]
        )
    }
}

private func printAppServerWebSocketStartupBanner(listenURL: String) {
    let trimmed = listenURL.trimmingCharacters(in: .whitespacesAndNewlines)
    let readyURL = httpURL(fromWebSocketURL: trimmed, path: "readyz")
    let healthURL = httpURL(fromWebSocketURL: trimmed, path: "healthz")
    fputs("codex app-server (WebSockets)\n", stderr)
    fputs("  listening on: \(trimmed)\n", stderr)
    fputs("  readyz: \(readyURL)\n", stderr)
    fputs("  healthz: \(healthURL)\n", stderr)
    let note = isLoopbackWebSocketURL(trimmed)
        ? "binds localhost only (use SSH port-forwarding for remote access)"
        : "websocket auth is opt-in in this build; configure `--ws-auth ...` before real remote use"
    fputs("  note: \(note)\n", stderr)
}

private func httpURL(fromWebSocketURL url: String, path: String) -> String {
    guard var components = URLComponents(string: url) else {
        return url
    }
    components.scheme = "http"
    components.path = "/\(path)"
    return components.string ?? url
}

private func isLoopbackWebSocketURL(_ url: String) -> Bool {
    guard let host = URLComponents(string: url)?.host else {
        return false
    }
    var ipv4 = in_addr()
    if host.withCString({ inet_pton(AF_INET, $0, &ipv4) }) == 1 {
        return (UInt32(bigEndian: ipv4.s_addr) & 0xff00_0000) == 0x7f00_0000
    }
    var ipv6 = in6_addr()
    if host.withCString({ inet_pton(AF_INET6, $0, &ipv6) }) == 1 {
        var loopback = in6addr_loopback
        return memcmp(&ipv6, &loopback, MemoryLayout<in6_addr>.size) == 0
    }
    return false
}

private func runAppCommand(_ request: CodexCLI.AppCommandRequest) async throws -> CodexCLI.CommandExecutionResult {
    try AppCommandRuntime.run(request)
}

private func runAppServerGenerator(
    subcommand: String,
    arguments: [String]
) throws -> CodexCLI.CommandExecutionResult {
    guard let executable = resolveRustAppServerBinary() else {
        return CodexCLI.CommandExecutionResult(
            exitCode: 1,
            stderrMessage: "codex-swift: app-server protocol generators require the Rust codex binary. Set CODEX_RUST_BINARY or run from a workspace checkout with ../codex-rs/target/debug/codex or ../codex/codex-rs/target/debug/codex."
        )
    }

    let process = Process()
    if executable.contains("/") {
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["app-server", subcommand] + arguments
    } else {
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [executable, "app-server", subcommand] + arguments
    }

    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe
    process.environment = ProcessInfo.processInfo.environment

    do {
        try process.run()
    } catch {
        return CodexCLI.CommandExecutionResult(
            exitCode: 1,
            stderrMessage: "codex-swift: failed to launch app-server generator command: \(error)"
        )
    }
    process.waitUntilExit()

    let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
    let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
    let stdout = String(decoding: stdoutData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    let stderr = String(decoding: stderrData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)

    return CodexCLI.CommandExecutionResult(
        exitCode: Int32(process.terminationStatus),
        stdoutMessage: stdout.isEmpty ? nil : stdout,
        stderrMessage: stderr.isEmpty ? nil : stderr
    )
}

private func buildGeneratorArguments(
    outDir: String,
    prettier: String?,
    experimental: Bool
) -> [String] {
    var arguments = ["--out", outDir]
    if let prettier {
        arguments += ["--prettier", prettier]
    }
    if experimental {
        arguments.append("--experimental")
    }
    return arguments
}

private func buildGeneratorArguments(outDir: String, experimental: Bool) -> [String] {
    if experimental {
        return ["--out", outDir, "--experimental"]
    }
    return ["--out", outDir]
}

private func resolveRustAppServerBinary() -> String? {
    if let configured = ProcessInfo.processInfo.environment["CODEX_RUST_BINARY"], !configured.isEmpty {
        if isExecutableBinary(configured) {
            return configured
        }
        return nil
    }

    if let candidate = resolveCodexRustFromMonorepo() {
        return candidate
    }

    let currentExecutable = absoluteExecutablePath()
    for candidate in pathExecutableCandidates("codex-rs") where candidate != currentExecutable {
        if isExecutableBinary(candidate) {
            return candidate
        }
    }

    for candidate in pathExecutableCandidates("codex") where candidate != currentExecutable {
        if isExecutableBinary(candidate) {
            return candidate
        }
    }

    return nil
}

private func resolveCodexRustFromMonorepo() -> String? {
    let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    let relativeCandidates = [
        "../codex-rs/target/debug/codex",
        "../codex/codex-rs/target/debug/codex"
    ]
    for relativeCandidate in relativeCandidates {
        let candidate = cwd.appendingPathComponent(relativeCandidate).standardized
        if isExecutableBinary(candidate.path) {
            return candidate.path
        }
    }
    return nil
}

private func pathExecutableCandidates(_ binaryName: String) -> [String] {
    let pathValue = ProcessInfo.processInfo.environment["PATH"] ?? ""
    return pathValue
        .split(separator: ":", omittingEmptySubsequences: true)
        .map { String($0) + "/" + binaryName }
}

private func isExecutableBinary(_ path: String) -> Bool {
    let normalizedPath = path.hasPrefix("~") ? (path as NSString).expandingTildeInPath : path
    return FileManager.default.fileExists(atPath: normalizedPath)
        && FileManager.default.isExecutableFile(atPath: normalizedPath)
}

private func absoluteExecutablePath() -> String {
    let executable = CommandLine.arguments.first ?? "codex"
    if executable.hasPrefix("/") {
        return URL(fileURLWithPath: executable).standardized.path
    }
    return URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        .appendingPathComponent(executable)
        .standardized
        .path
}

private func mcpExecArguments(for toolCall: CodexMCPToolCall) -> [String] {
    var arguments: [String] = []
    if let model = toolCall.model {
        arguments.append(contentsOf: ["--model", model])
    }
    if let profile = toolCall.profile {
        arguments.append(contentsOf: ["--profile", profile])
    }
    if let cwd = toolCall.cwd {
        arguments.append(contentsOf: ["--cd", cwd])
    }
    if let approvalPolicy = toolCall.approvalPolicy {
        arguments.append(contentsOf: ["--ask-for-approval", approvalPolicy])
    }
    if let sandbox = toolCall.sandbox {
        arguments.append(contentsOf: ["--sandbox", sandbox])
    }
    return arguments
}

private func mcpConfigOverrides(
    for toolCall: CodexMCPToolCall,
    rootOverrides: CliConfigOverrides
) -> CliConfigOverrides {
    var rawOverrides = rootOverrides.rawOverrides
    if let model = toolCall.model {
        rawOverrides.append("model=\(tomlString(model))")
    }
    if let profile = toolCall.profile {
        rawOverrides.append("profile=\(tomlString(profile))")
    }
    if let approvalPolicy = toolCall.approvalPolicy {
        rawOverrides.append("approval_policy=\(tomlString(approvalPolicy))")
    }
    if let sandbox = toolCall.sandbox {
        rawOverrides.append("sandbox_mode=\(tomlString(sandbox))")
    }
    for (key, value) in toolCall.config.sorted(by: { $0.key < $1.key }) {
        rawOverrides.append("\(key)=\(tomlLiteral(value))")
    }
    return CliConfigOverrides(rawOverrides: rawOverrides)
}

private func mcpToolText(for result: CodexCLI.CommandExecutionResult) -> String {
    var parts: [String] = []
    if let stdout = result.stdoutMessage, !stdout.isEmpty {
        parts.append(stdout)
    }
    if let stderr = result.stderrMessage, !stderr.isEmpty {
        parts.append(stderr)
    }
    return parts.joined(separator: "\n")
}

private func tomlLiteral(_ value: AnyJSONValue) -> String {
    switch value {
    case .null:
        return "\"\""
    case let .bool(value):
        return value ? "true" : "false"
    case let .integer(value):
        return String(value)
    case let .double(value):
        return String(value)
    case let .string(value):
        return tomlString(value)
    case let .array(values):
        return "[\(values.map(tomlLiteral).joined(separator: ", "))]"
    case let .object(values):
        let entries = values
            .sorted(by: { $0.key < $1.key })
            .map { "\(tomlKey($0.key)) = \(tomlLiteral($0.value))" }
            .joined(separator: ", ")
        return "{ \(entries) }"
    }
}

private func tomlString(_ value: String) -> String {
    let escaped = value
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
        .replacingOccurrences(of: "\n", with: "\\n")
    return "\"\(escaped)\""
}

private func tomlKey(_ value: String) -> String {
    if value.range(of: #"^[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil {
        return value
    }
    return tomlString(value)
}

private func runNonInteractiveExec(
    promptResolution: NonInteractivePromptResolution,
    outputSchema: JSONValue?,
    options: CodexCLI.ExecCommandOptions,
    arguments: [String],
    configOverrides: CliConfigOverrides,
    cwd: URL,
    conversationID: ConversationId = ConversationId(),
    history: [ResponseItem] = [],
    rolloutPath: URL? = nil,
    baseInstructionsOverride: String? = nil,
    sessionStartSource: HookSessionStartSource = .startup
) async throws -> CodexCLI.CommandExecutionResult {
    try NonInteractiveInput.enforceGitRepository(
        cwd: cwd,
        skipGitRepoCheck: options.skipGitRepoCheck
    )

    let environment = ProcessInfo.processInfo.environment
    let loaderOverrides = execLoaderOverrides(options: options)
    let (codexHome, settings) = try resolvedAuthSettings(
        overrides: configOverrides,
        loaderOverrides: loaderOverrides
    )
    let configStack = try CodexConfigLayerLoader.loadConfigLayerStack(
        codexHome: codexHome,
        cwd: cwd,
        cliOverrides: configOverrides,
        overrides: loaderOverrides,
        environment: environment
    )
    let hookHandlers = HookConfig.configuredHandlers(from: configStack, codexHome: codexHome, environment: environment)
    try await CodexAuthStorage.enforceLoginRestrictions(
        codexHome: codexHome,
        config: settings,
        environment: environment
    )

    let providerResolution = try resolveExecModelProvider(
        settings: settings,
        environment: environment,
        arguments: arguments
    )
    if let message = McpRequiredStartupValidator.requiredStartupFailureMessage(
        mcpServers: settings.mcpServers,
        environment: environment
    ) {
        return CodexCLI.CommandExecutionResult(exitCode: 1, stderrMessage: message)
    }
    guard providerResolution.info.wireAPI == .responses else {
        return CodexCLI.CommandExecutionResult(
            exitCode: 78,
            stderrMessage: "codex-swift: exec currently supports Responses API model providers only."
        )
    }
    let cliModel = execOptionValue(short: "-m", long: "--model", in: arguments)
    let ossModel = providerResolution.isOSS
        ? OSSProvider.defaultModelOverride(providerID: providerResolution.id, cliModel: cliModel)
        : nil
    let model = ossModel ?? cliModel ?? settings.model
        ?? (providerResolution.isOSS
            ? ModelsManager.openAIDefaultAPIModel
            : nil)

    if providerResolution.isOSS {
        try await OSSProvider.ensureProviderReady(
            providerID: providerResolution.id,
            providerInfo: providerResolution.info,
            model: model ?? ModelsManager.openAIDefaultAPIModel
        )
    }

    let commandAuthRunner = ProviderAuthCommandRunner()
    let runtimeProvider = ModelProviderFactory.create(providerInfo: providerResolution.info)
    let authResolution: ExecAuthResolution
    let provider: APIProvider
    if providerResolution.info.isAmazonBedrock() {
        authResolution = ExecAuthResolution(
            auth: try runtimeProvider.apiAuth(environment: environment),
            authMode: nil
        )
        provider = try runtimeProvider.apiProvider(environment: environment)
    } else {
        authResolution = try await resolveExecAuth(
            codexHome: codexHome,
            settings: settings,
            providerInfo: providerResolution.info,
            environment: environment,
            commandAuthRunner: commandAuthRunner
        )
        provider = providerResolution.info.toAPIProvider(
            authMode: authResolution.authMode,
            environment: environment
        )
    }
    let resolvedModel = model
        ?? (authResolution.authMode?.isChatGPT == true
            ? ModelsManager.openAIDefaultChatGPTModel
            : ModelsManager.openAIDefaultAPIModel)
    let modelFamily = ModelsManager.constructModelFamilyOffline(
        model: resolvedModel,
        configOverrides: settings.modelFamilyConfigOverrides
    )
    let approvalPolicy = resolveExecApprovalPolicy(settings: settings, arguments: arguments)
    let sandboxPolicy = resolveExecSandboxPolicy(settings: settings, arguments: arguments)
    let shell = ShellSnapshot.attachSnapshotIfEnabled(
        codexHome: codexHome,
        sessionID: ThreadId(uuid: conversationID.uuid),
        sessionCwd: cwd,
        shell: ShellResolver.defaultUserShell(),
        features: settings.features
    )
    let configuredTools = NonInteractiveExec.toolSpecs(modelFamily: modelFamily, config: settings)
    let projectInstructions = ProjectDoc.getUserInstructions(
        config: ProjectDocConfig(runtimeConfig: settings, cwd: cwd)
    ).map { UserInstructions(directory: cwd.path, text: $0) }
    let loadedSkills = settings.includeSkillInstructions
        ? SkillLoader.load(
            cwd: cwd,
            codexHome: codexHome,
            configLayerStack: configStack
        )
        : nil
    let availableSkills = loadedSkills.flatMap {
        Skills.buildAvailableSkills(
            outcome: $0,
            budget: Skills.defaultSkillMetadataBudget(contextWindow: modelFamily.contextWindow.map(Int.init))
        )
    }
    let memoryToolDeveloperInstructions = MemoryToolInstructions.build(codexHome: codexHome, config: settings)
    var prompt = NonInteractiveExec.makePrompt(
        prompt: promptResolution.prompt,
        imagePaths: options.imagePaths,
        outputSchema: outputSchema,
        cwd: cwd,
        approvalPolicy: approvalPolicy,
        sandboxPolicy: sandboxPolicy,
        shell: shell,
        includeEnvironmentContext: settings.includeEnvironmentContext,
        includePermissionsInstructions: settings.includePermissionsInstructions,
        developerInstructions: settings.developerInstructions,
        memoryToolDeveloperInstructions: memoryToolDeveloperInstructions,
        availableSkills: availableSkills,
        userInstructions: projectInstructions,
        history: history,
        tools: configuredTools.map(\.spec),
        parallelToolCalls: modelFamily.supportsParallelToolCalls
    )
    if let baseInstructionsOverride {
        prompt.baseInstructionsOverride = baseInstructionsOverride
    } else {
        prompt.baseInstructionsOverride = try readExperimentalInstructionsFile(
            settings.experimentalInstructionsFile,
            cwd: cwd
        )
    }
    let userPromptItem = prompt.input.last
    let sessionStartHookInputCount = prompt.input.count
    let sessionStartOutcome = await NonInteractiveExec.runSessionStartHooks(
        handlers: hookHandlers,
        prompt: &prompt,
        conversationID: conversationID,
        cwd: cwd,
        model: resolvedModel,
        approvalPolicy: approvalPolicy,
        source: sessionStartSource
    )
    let sessionStartHookAdditionalItems = Array(prompt.input.dropFirst(sessionStartHookInputCount))
    let userPromptSubmitHookInputCount = prompt.input.count
    let userPromptSubmitOutcome = await NonInteractiveExec.runUserPromptSubmitHooks(
        handlers: hookHandlers,
        prompt: &prompt,
        userPrompt: promptResolution.prompt,
        conversationID: conversationID,
        turnID: "turn-1",
        cwd: cwd,
        model: resolvedModel,
        approvalPolicy: approvalPolicy
    )
    let userPromptSubmitHookAdditionalItems = Array(prompt.input.dropFirst(userPromptSubmitHookInputCount))

    let recorder = try createExecRolloutRecorder(
        codexHome: codexHome,
        cwd: cwd,
        conversationID: conversationID,
        modelProviderID: providerResolution.id,
        rolloutPath: rolloutPath,
        ephemeral: options.ephemeral
    )
    defer { try? recorder?.shutdown() }
    try recorder?.recordItems([
        .turnContext(TurnContextItem(
            cwd: cwd.path,
            approvalPolicy: approvalPolicy,
            sandboxPolicy: sandboxPolicy,
            model: resolvedModel,
            effort: settings.modelReasoningEffort ?? modelFamily.defaultReasoningEffort,
            summary: settings.modelReasoningSummary ?? (modelFamily.supportsReasoningSummaries ? .auto : .none),
            finalOutputJSONSchema: outputSchema,
            truncationPolicy: modelFamily.truncationPolicy
        ))
    ])
    if let newUserItem = userPromptItem {
        try recorder?.recordItems([.responseItem(newUserItem)])
    }
    let hookAdditionalItems = sessionStartHookAdditionalItems + userPromptSubmitHookAdditionalItems
    if !hookAdditionalItems.isEmpty {
        try recorder?.recordItems(hookAdditionalItems.map(RolloutRecordItem.responseItem))
    }
    if sessionStartOutcome.shouldStop {
        return CodexCLI.CommandExecutionResult(
            exitCode: 0,
            stdoutMessage: sessionStartOutcome.stopReason,
            stderrMessage: nil
        )
    }
    if userPromptSubmitOutcome.shouldStop {
        return CodexCLI.CommandExecutionResult(
            exitCode: 0,
            stdoutMessage: userPromptSubmitOutcome.stopReason,
            stderrMessage: nil
        )
    }

    let client = ResponsesClient(
        transport: URLSessionAPITransport(),
        provider: provider,
        auth: authResolution.auth
    )
    let requestTrace = W3CTraceContext.fromEnvironment()
    let loopResult = await NonInteractiveExec.runResponsesLoopWithTranscript(
        initialPrompt: prompt,
        streamPrompt: { nextPrompt in
            await client.streamPromptRetryingProviderCommandAuth(
                model: resolvedModel,
                instructions: nextPrompt.fullInstructions(for: modelFamily),
                prompt: nextPrompt,
                options: NonInteractiveExec.responsesOptions(
                    conversationID: conversationID,
                    modelFamily: modelFamily,
                    reasoningEffort: settings.modelReasoningEffort,
                    reasoningSummary: settings.modelReasoningSummary,
                    verbosity: settings.modelVerbosity,
                    serviceTier: settings.serviceTier,
                    outputSchema: outputSchema,
                    requestTrace: requestTrace
                ),
                providerInfo: providerResolution.info,
                commandRunner: commandAuthRunner
            )
        },
        stopHookContext: NonInteractiveExec.StopHookContext(
            handlers: hookHandlers,
            conversationID: conversationID,
            turnID: "turn-1",
            cwd: cwd,
            model: resolvedModel,
            approvalPolicy: approvalPolicy
        ),
        executeFunctionCall: { item in
            await NonInteractiveExec.executeFunctionCallWithHooks(
                item,
                handlers: hookHandlers,
                conversationID: conversationID,
                turnID: "turn-1",
                cwd: cwd,
                model: resolvedModel,
                approvalPolicy: approvalPolicy,
                sandboxPolicy: sandboxPolicy,
                shell: shell,
                truncationPolicy: modelFamily.truncationPolicy,
                environment: environment,
                shellEnvironmentPolicy: settings.shellEnvironmentPolicy,
                explicitEnvOverrides: settings.shellEnvironmentPolicy.set,
                allowLoginShell: settings.allowLoginShell,
                backgroundTerminalMaxTimeoutMS: settings.backgroundTerminalMaxTimeoutMS
            )
        }
    )
    try recorder?.recordItems(loopResult.transcriptItems.map(RolloutRecordItem.responseItem))

    let result = NonInteractiveExec.finish(
        responseEvents: loopResult.events,
        outputMode: options.json ? .jsonLines : .human,
        conversationID: conversationID,
        lastMessageFile: options.lastMessageFile
    )
    var stderrMessages = [String]()
    if let promptStderr = promptResolution.stderrMessage {
        stderrMessages.append(promptStderr)
    }
    stderrMessages.append(contentsOf: result.stderrMessages)

    return CodexCLI.CommandExecutionResult(
        exitCode: result.exitCode,
        stdoutMessage: result.stdoutMessage,
        stderrMessage: stderrMessages.isEmpty ? nil : stderrMessages.joined(separator: "\n")
    )
}

private func createExecRolloutRecorder(
    codexHome: URL,
    cwd: URL,
    conversationID: ConversationId,
    modelProviderID: String,
    rolloutPath: URL?,
    ephemeral: Bool
) throws -> RolloutRecorder? {
    if let rolloutPath {
        return try RolloutRecorder.resume(path: rolloutPath)
    }
    guard !ephemeral else {
        return nil
    }

    return try RolloutRecorder.create(
        codexHome: codexHome,
        cwd: cwd,
        conversationID: conversationID,
        instructions: nil,
        source: .exec,
        originator: "codex_swift",
        cliVersion: CodexCLI.version,
        modelProvider: modelProviderID
    )
}

private func gitMergeBaseWithHead(cwd: String, branch: String) throws -> String? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["git", "merge-base", "HEAD", branch]
    process.currentDirectoryURL = URL(fileURLWithPath: cwd, isDirectory: true)
    let outputPipe = Pipe()
    let errorPipe = Pipe()
    process.standardOutput = outputPipe
    process.standardError = errorPipe

    do {
        try process.run()
    } catch {
        return nil
    }
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        return nil
    }
    let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
    let value = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    return value.isEmpty ? nil : value
}

private struct ExecModelProviderResolution {
    let id: String
    let info: ModelProviderInfo
    let isOSS: Bool
}

private struct ExecAuthResolution {
    let auth: StaticAPIAuthProvider
    let authMode: AuthMode?
}

private struct ExecRuntimeError: Error, CustomStringConvertible {
    let description: String
}

private func resolveExecModelProvider(
    settings: CodexRuntimeConfig,
    environment: [String: String],
    arguments: [String]
) throws -> ExecModelProviderResolution {
    var providers = settings.modelProviders
    let versionedOpenAI = ModelProviderInfo.createOpenAIProvider(
        environment: environment,
        packageVersion: CodexCLI.version
    )
    providers["openai"] = versionedOpenAI
    providers["openai-responses"] = versionedOpenAI

    let ossEnabled = execHasFlag("--oss", in: arguments)
    let providerID: String
    if ossEnabled {
        guard let ossProviderID = OSSProvider.resolveProviderID(
            explicitProvider: execLongOptionValue("--local-provider", in: arguments),
            settings: settings
        ) else {
            throw ExecRuntimeError(description: OSSProvider.missingProviderMessage)
        }
        providerID = ossProviderID
    } else {
        providerID = settings.modelProvider ?? "openai"
    }

    guard let provider = providers[providerID] else {
        throw ExecRuntimeError(description: "Unknown model provider '\(providerID)'")
    }
    return ExecModelProviderResolution(id: providerID, info: provider, isOSS: ossEnabled)
}

private func resolveExecAuth(
    codexHome: URL,
    settings: CodexRuntimeConfig,
    providerInfo: ModelProviderInfo,
    environment: [String: String],
    commandAuthRunner: ProviderAuthCommandRunner = ProviderAuthCommandRunner()
) async throws -> ExecAuthResolution {
    if providerInfo.envKey != nil || providerInfo.experimentalBearerToken != nil || providerInfo.auth != nil {
        let auth = try await APIAuthResolver.authProvider(
            auth: nil,
            provider: providerInfo,
            environment: environment,
            commandRunner: commandAuthRunner
        )
        return ExecAuthResolution(
            auth: auth,
            authMode: auth.accountID == nil || providerInfo.auth != nil ? .apiKey : .chatGPT
        )
    }

    if let apiKey = CodexAuthStorage.readCodexAPIKeyFromEnvironment(environment) {
        return ExecAuthResolution(auth: StaticAPIAuthProvider(bearerToken: apiKey), authMode: .apiKey)
    }

    let storedAuth = try CodexAuthStorage.loadAuthDotJSON(
        codexHome: codexHome,
        mode: settings.cliAuthCredentialsStoreMode
    )

    if let apiKey = storedAuth?.openAIAPIKey {
        return ExecAuthResolution(auth: StaticAPIAuthProvider(bearerToken: apiKey), authMode: .apiKey)
    }

    if storedAuth?.tokens != nil {
        guard let tokenData = try await CodexAuthStorage.loadFreshTokenData(
            codexHome: codexHome,
            mode: settings.cliAuthCredentialsStoreMode,
            environment: environment
        ) else {
            throw ExecRuntimeError(description: "Stored ChatGPT credentials are missing token data.")
        }
        return ExecAuthResolution(
            auth: StaticAPIAuthProvider(
                bearerToken: tokenData.accessToken,
                accountID: tokenData.accountID
            ),
            authMode: .chatGPT
        )
    }

    if providerInfo.requiresOpenAIAuth {
        throw ExecRuntimeError(description: "Not logged in. Run `codex login` or set CODEX_API_KEY.")
    }

    return ExecAuthResolution(auth: StaticAPIAuthProvider(), authMode: nil)
}

private func readUTF8FromStdin() throws -> String {
    let data = FileHandle.standardInput.readDataToEndOfFile()
    guard let input = String(data: data, encoding: .utf8) else {
        throw ExecRuntimeError(description: "stream did not contain valid UTF-8")
    }
    return input
}

private func resolveExecWorkingDirectory(from arguments: [String]) -> URL {
    let base = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    guard let value = execOptionValue(short: "-C", long: "--cd", in: arguments) else {
        return base
    }
    if value.hasPrefix("/") {
        return URL(fileURLWithPath: value, isDirectory: true).standardizedFileURL
    }
    return base.appendingPathComponent(value, isDirectory: true).standardizedFileURL
}

private func resolveExecApprovalPolicy(
    settings: CodexRuntimeConfig,
    arguments: [String]
) -> AskForApproval {
    if execHasFlag("--dangerously-bypass-approvals-and-sandbox", in: arguments)
        || execHasFlag("--yolo", in: arguments)
    {
        return .never
    }
    if execHasFlag("--full-auto", in: arguments) {
        return .onFailure
    }
    if let raw = execOptionValue(short: "-a", long: "--ask-for-approval", in: arguments),
       let mode = ApprovalModeCLIArgument(rawValue: raw)
    {
        return mode.approvalMode
    }
    return settings.approvalPolicy ?? .never
}

private func resolveExecSandboxPolicy(
    settings: CodexRuntimeConfig,
    arguments: [String]
) -> SandboxPolicy {
    if execHasFlag("--dangerously-bypass-approvals-and-sandbox", in: arguments)
        || execHasFlag("--yolo", in: arguments)
    {
        return .dangerFullAccess
    }
    if execHasFlag("--full-auto", in: arguments) {
        return SandboxPolicy.newWorkspaceWritePolicy()
    }
    let mode = execOptionValue(short: "-s", long: "--sandbox", in: arguments)
        .flatMap(SandboxModeCLIArgument.init(rawValue:))?
        .sandboxMode
    return mode.map(sandboxPolicy(from:)) ?? settings.legacySandboxPolicy()
}

private func sandboxPolicy(from mode: SandboxMode) -> SandboxPolicy {
    SandboxPolicy.fromSandboxMode(mode)
}

private func readExperimentalInstructionsFile(_ path: String?, cwd: URL) throws -> String? {
    guard let path else {
        return nil
    }
    let url = path.hasPrefix("/")
        ? URL(fileURLWithPath: path)
        : cwd.appendingPathComponent(path)
    return try String(contentsOf: url, encoding: .utf8)
}

private func execHasFlag(_ flag: String, in arguments: [String]) -> Bool {
    arguments.contains(flag)
}

private func execOptionValue(short: String, long: String, in arguments: [String]) -> String? {
    var index = 0
    while index < arguments.count {
        let argument = arguments[index]
        if argument == short || argument == long {
            guard index + 1 < arguments.count else {
                return nil
            }
            return arguments[index + 1]
        }
        if argument.hasPrefix("\(long)=") {
            return String(argument.dropFirst(long.count + 1))
        }
        if argument.hasPrefix(short), argument.count > short.count, !short.hasPrefix("--") {
            return String(argument.dropFirst(short.count))
        }
        index += 1
    }
    return nil
}

private func execLongOptionValue(_ long: String, in arguments: [String]) -> String? {
    var index = 0
    while index < arguments.count {
        let argument = arguments[index]
        if argument == long {
            guard index + 1 < arguments.count else {
                return nil
            }
            return arguments[index + 1]
        }
        if argument.hasPrefix("\(long)=") {
            return String(argument.dropFirst(long.count + 1))
        }
        index += 1
    }
    return nil
}

private func runExecPolicyCommand(_ request: CodexCLI.ExecPolicyCommandRequest) async throws -> CodexCLI.CommandExecutionResult {
    switch request.action {
    case let .check(rules, pretty, command):
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let ruleURLs = rules.map { path -> URL in
            if path.hasPrefix("/") {
                return URL(fileURLWithPath: path)
            }
            return cwd.appendingPathComponent(path)
        }
        let output = try ExecPolicyCheck.run(rulePaths: ruleURLs, command: command, pretty: pretty)
        return CodexCLI.CommandExecutionResult(exitCode: 0, stdoutMessage: output)
    }
}

private func runSandboxCommand(_ request: CodexCLI.SandboxCommandRequest) async throws -> CodexCLI.CommandExecutionResult {
    switch request.action {
    case let .macos(profile, allowUnixSockets, logDenials, command):
        let codexHome = try CodexHome.find()
        let processCwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let sandboxConfiguration: CodexCLI.DebugSandboxConfiguration
        do {
            sandboxConfiguration = try CodexCLI.resolveDebugSandboxConfiguration(
                profile: profile,
                configOverrides: request.configOverrides,
                codexHome: codexHome,
                processCwd: processCwd
            )
        } catch let error as CodexCLI.DebugSandboxConfigurationError {
            let exitCode: Int32
            switch error {
            case .customProfile:
                exitCode = 78
            case .unknownBuiltinProfile:
                exitCode = 1
            }
            return CodexCLI.CommandExecutionResult(
                exitCode: exitCode,
                stderrMessage: error.description
            )
        }

        let exitCode = try SeatbeltSandbox.run(
            command: command,
            permissionProfile: sandboxConfiguration.permissionProfile,
            cwd: sandboxConfiguration.cwd,
            allowUnixSockets: allowUnixSockets,
            logDenials: logDenials
        )
        return CodexCLI.CommandExecutionResult(exitCode: exitCode)
    case .linux:
        return CodexCLI.CommandExecutionResult(
            exitCode: 1,
            stderrMessage: "Landlock sandbox is only available on Linux"
        )
    case .windows:
        return CodexCLI.CommandExecutionResult(
            exitCode: 1,
            stderrMessage: "Windows sandbox is only available on Windows"
        )
    }
}

private func runResumeCommand(_ request: CodexCLI.ResumeCommandRequest) async throws -> CodexCLI.CommandExecutionResult {
    let codexHome = try CodexHome.find()
    let resolution = try ResumeCommandResolver.resolve(request, codexHome: codexHome)
    let output = ResumeCommandFormatter.render(resolution)

    switch resolution {
    case .session:
        return CodexCLI.CommandExecutionResult(
            exitCode: 78,
            stdoutMessage: output,
            stderrMessage: "codex-swift: resume target resolved, but interactive resume runtime is not complete yet."
        )
    case .picker:
        return CodexCLI.CommandExecutionResult(exitCode: 0, stdoutMessage: output)
    }
}

private func runForkCommand(_ request: CodexCLI.ForkCommandRequest) async throws -> CodexCLI.CommandExecutionResult {
    let codexHome = try CodexHome.find()
    let resumeRequest = CodexCLI.ResumeCommandRequest(
        sessionID: request.sessionID,
        last: request.last,
        all: request.all,
        configOverrides: request.configOverrides
    )
    let resolution = try ResumeCommandResolver.resolve(resumeRequest, codexHome: codexHome)
    let output = ResumeCommandFormatter.render(resolution)

    switch resolution {
    case .session:
        return CodexCLI.CommandExecutionResult(
            exitCode: 78,
            stdoutMessage: output,
            stderrMessage: "codex-swift: fork target resolved, but interactive fork runtime is not complete yet."
        )
    case .picker:
        return CodexCLI.CommandExecutionResult(exitCode: 0, stdoutMessage: output)
    }
}

private func runExecServerCommand(_ request: CodexCLI.ExecServerCommandRequest) async throws -> CodexCLI.CommandExecutionResult {
    switch request.action {
    case let .listen(url):
        switch try ExecServerListenURLParser.parse(url) {
        case .stdio:
            let transport = ExecServerStdioTransport()
            try await transport.run(lines: FileHandle.standardInput.bytes.lines) { line in
                FileHandle.standardOutput.write(line)
            }
            return CodexCLI.CommandExecutionResult(exitCode: 0)
        case let .webSocket(host, port):
            let transport = ExecServerWebSocketTransport()
            try await transport.run(host: host, port: port) { line in
                FileHandle.standardOutput.write(Data(line.utf8))
            }
            return CodexCLI.CommandExecutionResult(exitCode: 0)
        }
    case let .remote(baseURL, executorID, name):
        let config = try ExecServerRemoteExecutorConfiguration.fromEnvironment(
            baseURL: baseURL,
            executorID: executorID,
            name: name
        )
        let executor = try ExecServerRemoteExecutor(config: config)
        try await executor.run()
        return CodexCLI.CommandExecutionResult(exitCode: 0)
    }
}

private func runStdioToUDSCommand(_ request: CodexCLI.StdioToUDSCommandRequest) async throws -> CodexCLI.CommandExecutionResult {
    try StdioToUDS.run(socketPath: request.socketPath)
    return CodexCLI.CommandExecutionResult(exitCode: 0)
}

private func runPluginCommand(_ request: CodexCLI.PluginCommandRequest) async throws -> CodexCLI.CommandExecutionResult {
    let codexHome = try CodexHome.find()
    let configuration = CodexAppServerConfiguration(
        codexHome: codexHome,
        cliConfigOverrides: request.configOverrides
    )

    switch request.action {
    case let .marketplaceAdd(source, refName, sparsePaths):
        let result = try CodexAppServer.marketplaceAddCommandResult(
            source: source,
            refName: refName,
            sparsePaths: sparsePaths,
            configuration: configuration
        )
        let marketplaceName = result["marketplaceName"] as? String ?? ""
        let sourceDisplay = result["sourceDisplay"] as? String ?? source
        let installedRoot = result["installedRoot"] as? String ?? ""
        let alreadyAdded = result["alreadyAdded"] as? Bool ?? false
        let firstLine = alreadyAdded
            ? "Marketplace `\(marketplaceName)` is already added from \(sourceDisplay)."
            : "Added marketplace `\(marketplaceName)` from \(sourceDisplay)."
        return CodexCLI.CommandExecutionResult(
            exitCode: 0,
            stdoutMessage: "\(firstLine)\nInstalled marketplace root: \(installedRoot)"
        )

    case let .marketplaceUpgrade(name):
        let result = try CodexAppServer.marketplaceUpgradeCommandResult(
            marketplaceName: name,
            configuration: configuration
        )
        let errors = result["errors"] as? [[String: String]] ?? []
        if !errors.isEmpty {
            let errorLines = errors.map { error in
                let marketplaceName = error["marketplaceName"] ?? ""
                let message = error["message"] ?? ""
                return "Failed to upgrade marketplace `\(marketplaceName)`: \(message)"
            }
            return CodexCLI.CommandExecutionResult(
                exitCode: 1,
                stderrMessage: (errorLines + ["\(errors.count) upgrade failure(s) occurred."]).joined(separator: "\n")
            )
        }
        let selectedMarketplaces = result["selectedMarketplaces"] as? [String] ?? []
        let upgradedRoots = result["upgradedRoots"] as? [String] ?? []
        let selectionLabel = name ?? "all configured Git marketplaces"
        var lines: [String]
        if selectedMarketplaces.isEmpty {
            lines = ["No configured Git marketplaces to upgrade."]
        } else if upgradedRoots.isEmpty {
            lines = [name == nil
                ? "All configured Git marketplaces are already up to date."
                : "Marketplace `\(selectionLabel)` is already up to date."]
        } else if name != nil {
            lines = ["Upgraded marketplace `\(selectionLabel)` to the latest configured revision."]
        } else {
            lines = ["Upgraded \(upgradedRoots.count) marketplace(s)."]
        }
        lines.append(contentsOf: upgradedRoots.map { "Installed marketplace root: \($0)" })
        return CodexCLI.CommandExecutionResult(exitCode: 0, stdoutMessage: lines.joined(separator: "\n"))

    case let .marketplaceRemove(name):
        let result = try CodexAppServer.marketplaceRemoveCommandResult(
            marketplaceName: name,
            configuration: configuration
        )
        let marketplaceName = result["marketplaceName"] as? String ?? name
        var lines = ["Removed marketplace `\(marketplaceName)`."]
        if let installedRoot = result["installedRoot"] as? String {
            lines.append("Removed installed marketplace root: \(installedRoot)")
        }
        return CodexCLI.CommandExecutionResult(exitCode: 0, stdoutMessage: lines.joined(separator: "\n"))
    }
}

private func runCloudCommand(_ request: CodexCLI.CloudCommandRequest) async throws -> CodexCLI.CommandExecutionResult {
    let (codexHome, settings) = try resolvedAuthSettings(overrides: request.configOverrides)
    let client = CloudTaskClient(configuration: CloudTaskClientConfiguration(
        chatgptBaseURL: settings.chatgptBaseURL,
        codexHome: codexHome,
        authCredentialsStoreMode: settings.cliAuthCredentialsStoreMode
    ))

    switch request.action {
    case let .status(taskID):
        let summary = try await client.taskSummary(taskID: taskID)
        return CodexCLI.CommandExecutionResult(
            exitCode: summary.status == .ready ? 0 : 1,
            stdoutMessage: CloudTaskCommandFormatter.statusLines(task: summary).joined(separator: "\n")
        )
    case let .list(environment, limit, cursor, json):
        let page = try await client.listTasks(environment: environment, limit: limit, cursor: cursor)
        if json {
            return CodexCLI.CommandExecutionResult(
                exitCode: 0,
                stdoutMessage: try CloudTaskCommandFormatter.listJSON(
                    tasks: page.tasks,
                    cursor: page.cursor,
                    baseURL: settings.chatgptBaseURL
                )
            )
        }
        guard !page.tasks.isEmpty else {
            return CodexCLI.CommandExecutionResult(exitCode: 0, stdoutMessage: "No tasks found.")
        }
        var lines = CloudTaskCommandFormatter.listLines(tasks: page.tasks, baseURL: settings.chatgptBaseURL)
        if let cursor = page.cursor {
            lines.append("")
            lines.append("To fetch the next page, run codex cloud list --cursor='\(cursor)'")
        }
        return CodexCLI.CommandExecutionResult(exitCode: 0, stdoutMessage: lines.joined(separator: "\n"))
    case let .diff(taskID, attempt):
        return CodexCLI.CommandExecutionResult(
            exitCode: 0,
            stdoutMessage: try await client.taskDiff(taskID: taskID, attempt: attempt)
        )
    case let .apply(taskID, attempt):
        let outcome = try await client.applyTaskOutcome(taskID: taskID, attempt: attempt)
        return CodexCLI.CommandExecutionResult(
            exitCode: outcome.status == .success ? 0 : 1,
            stdoutMessage: outcome.message
        )
    case let .exec(query, environment, branch, attempts):
        let prompt = try CloudExecPromptResolver.resolve(
            query: query,
            stdinIsTerminal: isatty(STDIN_FILENO) != 0,
            readStdin: { FileHandle.standardInput.readDataToEndOfFile() }
        )
        let url = try await client.createTask(
            prompt: prompt.prompt,
            environment: environment,
            branch: branch,
            attempts: attempts
        )
        return CodexCLI.CommandExecutionResult(
            exitCode: 0,
            stdoutMessage: url,
            stderrMessage: prompt.stderrMessage
        )
    }
}

private func runResponsesAPIProxyCommand(_ request: CodexCLI.ResponsesAPIProxyCommandRequest) async throws -> CodexCLI.CommandExecutionResult {
    try ResponsesAPIProxy.run(options: ResponsesAPIProxyOptions(
        port: request.port,
        serverInfoPath: request.serverInfoPath.map { URL(fileURLWithPath: $0) },
        httpShutdown: request.httpShutdown,
        upstreamURL: request.upstreamURL,
        dumpDir: request.dumpDir.map { URL(fileURLWithPath: $0, isDirectory: true) }
    ))
    return CodexCLI.CommandExecutionResult(exitCode: 1, stderrMessage: "server stopped unexpectedly")
}

private func runUpdateCommand(_ request: CodexCLI.UpdateCommandRequest) async throws -> CodexCLI.CommandExecutionResult {
    try UpdateCommandRuntime.run()
}

private struct APIKeyReadResult {
    let exitCode: Int32
    let message: String
    let apiKey: String?
}

private func readAPIKeyFromStdin() -> APIKeyReadResult {
    if isatty(STDIN_FILENO) != 0 {
        return APIKeyReadResult(
            exitCode: 1,
            message: "--with-api-key expects the API key on stdin. Try piping it, e.g. `printenv OPENAI_API_KEY | codex login --with-api-key`.",
            apiKey: nil
        )
    }

    let message = "Reading API key from stdin..."
    let data = FileHandle.standardInput.readDataToEndOfFile()
    guard let input = String(data: data, encoding: .utf8) else {
        return APIKeyReadResult(
            exitCode: 1,
            message: "Failed to read API key from stdin: stream did not contain valid UTF-8",
            apiKey: nil
        )
    }
    let apiKey = input.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !apiKey.isEmpty else {
        return APIKeyReadResult(exitCode: 1, message: "No API key provided via stdin.", apiKey: nil)
    }
    return APIKeyReadResult(exitCode: 0, message: message, apiKey: apiKey)
}

private func safeFormatAPIKey(_ apiKey: String) -> String {
    guard apiKey.count > 13 else {
        return "***"
    }
    return "\(apiKey.prefix(8))***\(apiKey.suffix(5))"
}
