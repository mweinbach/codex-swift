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
    interactiveRunner: runInteractiveCommand,
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
    updateRunner: runUpdateCommand,
    doctorRunner: runDoctorCommand
)
exit(exitCode)

private func resolvedAuthSettings(
    overrides: CliConfigOverrides,
    loaderOverrides: ConfigLayerLoaderOverrides = ConfigLayerLoaderOverrides(),
    cwd: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
) throws -> (codexHome: URL, settings: CodexRuntimeConfig) {
    let codexHome = try CodexHome.find()
    let settings = try CodexConfigLoader.load(
        codexHome: codexHome,
        cwd: cwd,
        overrides: overrides,
        managedConfigOverrides: loaderOverrides
    )
    return (codexHome, settings)
}

private func profileV2ConfigPath(codexHome: URL, profile: String) -> URL {
    codexHome.appendingPathComponent("\(profile).config.toml", isDirectory: false).standardizedFileURL
}

private func execLoaderOverrides(options: CodexCLI.ExecCommandOptions, codexHome: URL) -> ConfigLayerLoaderOverrides {
    var overrides = ConfigLayerLoaderOverrides(
        ignoreUserConfig: options.ignoreUserConfig,
        ignoreUserAndProjectExecPolicyRules: options.ignoreRules
    )
    if let profile = options.configProfileV2 {
        overrides.userConfigPath = profileV2ConfigPath(codexHome: codexHome, profile: profile)
        overrides.userConfigProfile = profile
    }
    return overrides
}

private func profileV2LoaderOverrides(profile: String?, codexHome: URL) -> ConfigLayerLoaderOverrides {
    var overrides = ConfigLayerLoaderOverrides()
    if let profile {
        overrides.userConfigPath = profileV2ConfigPath(codexHome: codexHome, profile: profile)
        overrides.userConfigProfile = profile
    }
    return overrides
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
        let readResult = readSecretFromStdin(
            terminalMessage: "--with-api-key expects the API key on stdin. Try piping it, e.g. `printenv OPENAI_API_KEY | codex login --with-api-key`.",
            readingMessage: "Reading API key from stdin...",
            emptyMessage: "No API key provided via stdin.",
            invalidUTF8Message: "Failed to read API key from stdin: stream did not contain valid UTF-8"
        )
        guard readResult.exitCode == 0, let apiKey = readResult.value else {
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

    case .withAccessTokenFromStdin:
        let readResult = readSecretFromStdin(
            terminalMessage: "--with-access-token expects the access token on stdin. Try piping it, e.g. `printenv CODEX_ACCESS_TOKEN | codex login --with-access-token`.",
            readingMessage: "Reading access token from stdin...",
            emptyMessage: "No access token provided via stdin.",
            invalidUTF8Message: "Failed to read stdin: stream did not contain valid UTF-8"
        )
        guard readResult.exitCode == 0, let accessToken = readResult.value else {
            return CodexCLI.CommandExecutionResult(exitCode: readResult.exitCode, stderrMessage: readResult.message)
        }
        let (codexHome, settings) = try resolvedAuthSettings(overrides: request.configOverrides)
        if settings.forcedLoginMethod == .api {
            return CodexCLI.CommandExecutionResult(
                exitCode: 1,
                stderrMessage: "\(readResult.message)\nAccess token login is disabled. Use API key login instead."
            )
        }
        try await CodexAuthStorage.loginWithAccessToken(
            codexHome: codexHome,
            accessToken: accessToken,
            chatGPTBaseURL: settings.chatgptBaseURL,
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
                    forcedChatGPTWorkspaceIDs: settings.forcedChatGPTWorkspaceIDs,
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
                    forcedChatGPTWorkspaceIDs: settings.forcedChatGPTWorkspaceIDs,
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

private func runDoctorCommand(_ request: CodexCLI.DoctorCommandRequest) async throws -> CodexCLI.CommandExecutionResult {
    let baseDiagnosticChecks = [
        DoctorCommandRuntime.installationCheck(showDetails: !request.summary),
        DoctorCommandRuntime.runtimeProvenanceCheck(codexVersion: CodexCLI.version),
        DoctorCommandRuntime.searchCheck(),
        DoctorCommandRuntime.networkEnvironmentCheck(),
        DoctorCommandRuntime.terminalEnvironmentCheck(noColorFlag: request.noColor)
    ]
    return DoctorCommandRuntime.run(
        request: request,
        codexVersion: CodexCLI.version,
        diagnosticChecks: { baseDiagnosticChecks + doctorConfigDependentChecks(request) }
    ) {
        do {
            let (codexHome, settings) = try resolvedAuthSettings(overrides: request.configOverrides)
            let cwd = FileManager.default.currentDirectoryPath
            let configTomlPath = codexHome.appendingPathComponent("config.toml").path
            return DoctorCommandRuntime.configLoadedCheck(
                codexHome: codexHome.path,
                cwd: cwd,
                model: settings.model,
                modelProviderID: settings.modelProvider,
                logDir: settings.logDir,
                sqliteHome: settings.sqliteHome,
                mcpServerCount: settings.mcpServers.count,
                features: settings.features,
                configTomlPath: configTomlPath,
                configTomlStatus: doctorConfigTomlStatus(path: configTomlPath),
                startupWarnings: settings.startupWarnings
            )
        } catch {
            return DoctorCommandRuntime.configLoadFailedCheck(error)
        }
    }
}

private func doctorConfigDependentChecks(_ request: CodexCLI.DoctorCommandRequest) -> [DoctorCheck] {
    do {
        let (codexHome, settings) = try resolvedAuthSettings(overrides: request.configOverrides)
        let cwd = FileManager.default.currentDirectoryPath
        return [
            DoctorCommandRuntime.authCredentialsCheck(
                codexHome: codexHome,
                settings: settings
            ),
            DoctorCommandRuntime.updatesCheck(
                codexHome: codexHome,
                settings: settings,
                codexVersion: CodexCLI.version
            ),
            DoctorCommandRuntime.mcpConfigCheck(settings: settings),
            DoctorCommandRuntime.sandboxHelpersCheck(
                approvalPolicy: settings.approvalPolicy,
                sandboxPolicy: settings.legacySandboxPolicy(),
                permissionProfile: settings.permissionProfile,
                cwd: cwd,
                effectiveWorkspaceRoots: settings.workspaceRoots.map(\.path),
                helperPaths: .detect()
            ),
            DoctorCommandRuntime.statePathsCheck(
                codexHome: codexHome,
                settings: settings
            ),
            DoctorCommandRuntime.backgroundServerCheck(
                codexHome: codexHome
            ),
            DoctorCommandRuntime.providerReachabilityCheck(
                codexHome: codexHome,
                settings: settings
            ),
            DoctorCommandRuntime.websocketReachabilityCheck(
                codexHome: codexHome,
                settings: settings
            )
        ]
    } catch {
        return [
            DoctorCommandRuntime.fallbackStatePathsCheck(),
            DoctorCommandRuntime.defaultProviderReachabilityCheck()
        ]
    }
}

private func doctorConfigTomlStatus(path: String) -> String {
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else {
        return "missing"
    }
    guard !isDirectory.boolValue else {
        return "read: is a directory"
    }
    do {
        _ = try String(contentsOfFile: path, encoding: .utf8)
        return "parse: ok"
    } catch {
        return "read: \(error.localizedDescription)"
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

private final class InteractiveTurnHistory: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [ResponseItem] = []

    init(items: [ResponseItem] = []) {
        self.items = items
    }

    func snapshot() -> [ResponseItem] {
        lock.lock()
        defer { lock.unlock() }
        return items
    }

    func append(_ newItems: [ResponseItem]) {
        lock.lock()
        items.append(contentsOf: newItems)
        lock.unlock()
    }
}

private final class InteractiveStreamState: @unchecked Sendable {
    private let lock = NSLock()
    private var didStreamText = false

    func markTextStreamed() {
        lock.lock()
        didStreamText = true
        lock.unlock()
    }

    func consumeTextStreamed() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let value = didStreamText
        didStreamText = false
        return value
    }
}

private final class InteractiveRolloutPathStore: @unchecked Sendable {
    private let lock = NSLock()
    private let options: CodexCLI.InteractiveCommandOptions
    private let cwd: URL
    private let conversationID: ConversationId
    private let forkedFromID: ConversationId?
    private let initialHistory: InitialHistory?
    private var didResolve = false
    private var cachedPath: URL?

    init(
        options: CodexCLI.InteractiveCommandOptions,
        cwd: URL,
        conversationID: ConversationId,
        forkedFromID: ConversationId? = nil,
        initialHistory: InitialHistory? = nil
    ) {
        self.options = options
        self.cwd = cwd
        self.conversationID = conversationID
        self.forkedFromID = forkedFromID
        self.initialHistory = initialHistory
    }

    func path() throws -> URL? {
        lock.lock()
        defer { lock.unlock() }
        guard !didResolve else {
            return cachedPath
        }
        cachedPath = try createLineModeRolloutPath(
            options: options,
            cwd: cwd,
            conversationID: conversationID,
            forkedFromID: forkedFromID,
            initialHistory: initialHistory
        )
        didResolve = true
        return cachedPath
    }
}

private func runInteractiveCommand(_ request: CodexCLI.InteractiveCommandRequest) async throws -> CodexCLI.CommandExecutionResult {
    try await runLineModeInteractiveCommand(
        request,
        conversationID: ConversationId(),
        initialHistory: [],
        resumedRolloutPath: nil,
        forkedFromID: nil,
        initialHistoryForNewRollout: nil,
        firstTurnStartSource: .startup,
        initialThreadID: nil
    )
}

private func runLineModeInteractiveCommand(
    _ request: CodexCLI.InteractiveCommandRequest,
    conversationID: ConversationId,
    initialHistory: [ResponseItem],
    resumedRolloutPath: URL?,
    forkedFromID: ConversationId?,
    initialHistoryForNewRollout: InitialHistory?,
    firstTurnStartSource: HookSessionStartSource,
    initialThreadID: String?
) async throws -> CodexCLI.CommandExecutionResult {
    let io = lineModeIO()
    if request.remote != nil || request.remoteAuthTokenEnv != nil {
        return CodexCLI.CommandExecutionResult(
            exitCode: 78,
            stderrMessage: "codex-swift: line-mode interactive fallback does not support remote sessions yet."
        )
    }

    let options = request.interactiveOptions
    let arguments = interactiveExecArguments(from: options)
    let cwd = resolveExecWorkingDirectory(from: arguments)
    let rolloutPathStore = InteractiveRolloutPathStore(
        options: options,
        cwd: cwd,
        conversationID: conversationID,
        forkedFromID: forkedFromID,
        initialHistory: initialHistoryForNewRollout
    )
    let history = InteractiveTurnHistory(items: initialHistory)
    let approvalHandler = lineModeApprovalHandler(io: io)
    let fixedRolloutPath = try resumedRolloutPath ?? (forkedFromID == nil ? nil : rolloutPathStore.path())
    let runtime = LineModeInteractiveRuntime(request: request, initialThreadID: initialThreadID, io: io) { turn in
        let streamState = InteractiveStreamState()
        let result = try await runNonInteractiveExec(
            promptResolution: NonInteractivePromptResolution(prompt: turn.prompt),
            outputSchema: nil,
            options: interactiveExecOptions(
                from: options,
                request: request,
                imagePaths: turn.turnIndex == 1 ? options.imagePaths : []
            ),
            arguments: arguments,
            configOverrides: request.configOverrides,
            cwd: cwd,
            conversationID: conversationID,
            history: history.snapshot(),
            rolloutPath: try fixedRolloutPath ?? rolloutPathStore.path(),
            sessionStartSource: turn.turnIndex == 1 ? firstTurnStartSource : .resume,
            responseEventHandler: lineModeResponseEventHandler(streamState: streamState),
            turnHistoryHandler: { history.append($0) },
            approvalHandler: approvalHandler
        )
        if streamState.consumeTextStreamed() {
            fputs("\n", stdout)
            fflush(stdout)
            return CodexCLI.CommandExecutionResult(
                exitCode: result.exitCode,
                stdoutMessage: nil,
                stderrMessage: result.stderrMessage,
                threadID: result.threadID
            )
        }
        return result
    }
    let result = await runtime.run()
    return CodexCLI.CommandExecutionResult(
        exitCode: result.exitCode,
        threadID: result.threadID
    )
}

private func lineModeIO() -> LineModeInteractiveRuntime.IO {
    LineModeInteractiveRuntime.IO(
        readLine: { Swift.readLine(strippingNewline: true) },
        writeStdout: { message in
            print(message)
        },
        writeStderr: { message in
            fputs(message.hasSuffix("\n") ? message : "\(message)\n", Darwin.stderr)
            fflush(Darwin.stderr)
        },
        writePrompt: { prompt in
            fputs(prompt, Darwin.stderr)
            fflush(Darwin.stderr)
        }
    )
}

private func createLineModeRolloutPath(
    options: CodexCLI.InteractiveCommandOptions,
    cwd: URL,
    conversationID: ConversationId,
    forkedFromID: ConversationId? = nil,
    initialHistory: InitialHistory? = nil
) throws -> URL? {
    guard !options.ephemeral else {
        return nil
    }
    let codexHome = try CodexHome.find()
    let recorder: RolloutRecorder
    if let forkedFromID, let initialHistory {
        recorder = try RolloutRecorder.createFork(
            codexHome: codexHome,
            cwd: cwd,
            conversationID: conversationID,
            forkedFromID: forkedFromID,
            initialHistory: initialHistory,
            source: .cli,
            threadSource: .user,
            originator: "codex_swift",
            cliVersion: CodexCLI.version,
            modelProvider: firstSessionMeta(in: initialHistory.rolloutItems)?.modelProvider
        )
    } else {
        recorder = try RolloutRecorder.create(
            codexHome: codexHome,
            cwd: cwd,
            conversationID: conversationID,
            instructions: nil,
            source: .cli,
            originator: "codex_swift",
            cliVersion: CodexCLI.version,
            modelProvider: nil
        )
    }
    let path = recorder.rolloutPath
    try recorder.shutdown()
    return path
}

private func firstSessionMeta(in items: [RolloutRecordItem]) -> SessionMeta? {
    items.compactMap { item -> SessionMeta? in
        guard case let .sessionMeta(metaLine) = item else {
            return nil
        }
        return metaLine.meta
    }.first
}

private func interactiveExecOptions(
    from options: CodexCLI.InteractiveCommandOptions,
    request: CodexCLI.InteractiveCommandRequest,
    imagePaths: [String]
) -> CodexCLI.ExecCommandOptions {
    CodexCLI.ExecCommandOptions(
        imagePaths: imagePaths,
        skipGitRepoCheck: true,
        ephemeral: options.ephemeral,
        ignoreUserConfig: options.ignoreUserConfig,
        ignoreRules: options.ignoreRules,
        configProfileV2: options.configProfileV2,
        strictConfig: request.strictConfig,
        bypassHookTrust: options.bypassHookTrust
    )
}

private func interactiveExecArguments(from options: CodexCLI.InteractiveCommandOptions) -> [String] {
    var arguments: [String] = []
    appendOption("--model", value: options.model, to: &arguments)
    if options.useOSSProvider {
        arguments.append("--oss")
    }
    appendOption("--local-provider", value: options.localProvider, to: &arguments)
    appendOption("--profile", value: options.configProfile, to: &arguments)
    appendOption("--profile-v2", value: options.configProfileV2, to: &arguments)
    appendOption("--sandbox", value: options.sandboxMode, to: &arguments)
    if options.dangerouslyBypassApprovalsAndSandbox {
        arguments.append("--dangerously-bypass-approvals-and-sandbox")
    }
    appendOption("--cd", value: options.cwd, to: &arguments)
    for root in options.additionalWritableRoots {
        appendOption("--add-dir", value: root, to: &arguments)
    }
    appendOption("--ask-for-approval", value: options.approvalPolicy, to: &arguments)
    if options.searchEnabled {
        arguments.append("--search")
    }
    if options.ephemeral {
        arguments.append("--ephemeral")
    }
    if options.ignoreUserConfig {
        arguments.append("--ignore-user-config")
    }
    if options.ignoreRules {
        arguments.append("--ignore-rules")
    }
    if options.bypassHookTrust {
        arguments.append("--dangerously-bypass-hook-trust")
    }
    return arguments
}

private func appendOption(_ name: String, value: String?, to arguments: inout [String]) {
    guard let value else {
        return
    }
    arguments.append(contentsOf: [name, value])
}

private func lineModeResponseEventHandler(
    streamState: InteractiveStreamState
) -> NonInteractiveResponseEventHandler {
    { result in
        switch result {
        case let .success(.outputTextDelta(delta)):
            streamState.markTextStreamed()
            fputs(delta, stdout)
            fflush(stdout)
        case let .success(.runtimeEvent(event)):
            emitLineModeRuntimeEvent(event)
        case let .failure(error):
            fputs("codex-swift: stream error: \(String(describing: error))\n", Darwin.stderr)
            fflush(Darwin.stderr)
        default:
            break
        }
    }
}

private func emitLineModeRuntimeEvent(_ event: EventMessage) {
    switch event {
    case let .execCommandBegin(event):
        fputs("\n[command] \(event.command.joined(separator: " "))\n", Darwin.stderr)
        fflush(Darwin.stderr)
    case let .execCommandEnd(event):
        fputs("[command exited \(event.exitCode)]\n", Darwin.stderr)
        fflush(Darwin.stderr)
    case let .patchApplyBegin(event):
        fputs("\n[apply_patch] \(event.changes.count) file(s)\n", Darwin.stderr)
        fflush(Darwin.stderr)
    case let .patchApplyEnd(event):
        fputs("[apply_patch \(event.success ? "completed" : "failed")]\n", Darwin.stderr)
        fflush(Darwin.stderr)
    default:
        break
    }
}

private func lineModeApprovalHandler(io: LineModeInteractiveRuntime.IO) -> NonInteractiveExec.FunctionCallApprovalHandler {
    { request in
        switch request {
        case let .exec(event):
            return promptForLineModeApproval(
                io: io,
                title: "Command approval requested",
                detail: event.reason,
                body: [
                    "cwd: \(event.cwd)",
                    "command: \(event.command.joined(separator: " "))"
                ],
                availableDecisions: event.effectiveAvailableDecisions
            )
        case let .applyPatch(event):
            return promptForLineModeApproval(
                io: io,
                title: "Patch approval requested",
                detail: event.reason,
                body: [
                    "root: \(event.grantRoot ?? "")",
                    "files: \(event.changes.keys.sorted().joined(separator: ", "))"
                ],
                availableDecisions: [.approved, .abort]
            )
        }
    }
}

private func promptForLineModeApproval(
    io: LineModeInteractiveRuntime.IO,
    title: String,
    detail: String?,
    body: [String],
    availableDecisions: [ReviewDecision]
) -> ReviewDecision {
    io.writeStderr("")
    io.writeStderr(title)
    if let detail, !detail.isEmpty {
        io.writeStderr(detail)
    }
    for line in body where !line.isEmpty {
        io.writeStderr(line)
    }
    let allowsSession = availableDecisions.contains(.approvedForSession)
    let prompt = allowsSession
        ? "Approve? [y]es/[s]ession/[n]o/[a]bort: "
        : "Approve? [y]es/[n]o/[a]bort: "

    while true {
        io.writePrompt(prompt)
        guard let answer = io.readLine() else {
            return .denied
        }
        switch answer.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "y", "yes":
            return .approved
        case "s", "session":
            if allowsSession {
                return .approvedForSession
            }
            io.writeStderr("Session approval is not available for this request.")
        case "n", "no", "":
            return .denied
        case "a", "abort", "cancel":
            return .abort
        default:
            io.writeStderr("Enter y, n, or a.")
        }
    }
}

private func runExecCommand(
    _ request: CodexCLI.ExecCommandRequest,
    baseInstructionsOverride: String? = nil
) async throws -> CodexCLI.CommandExecutionResult {
    let operation = try request.resolvedInitialOperation(
        stdinIsTerminal: isatty(STDIN_FILENO) != 0,
        readStdin: readStdinData,
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
            CodexCLI.ResumeCommandRequest(
                sessionID: sessionID,
                last: last,
                all: all,
                includeNonInteractive: true
            ),
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
        readStdin: readStdinData
    )
    let resolved = try ReviewPrompts.resolveReviewRequest(
        reviewRequest,
        cwd: cwd.path,
        mergeBaseWithHead: gitMergeBaseWithHead
    )
    return try await runNonInteractiveExec(
        promptResolution: NonInteractivePromptResolution(prompt: resolved.prompt),
        outputSchema: nil,
        options: CodexCLI.ExecCommandOptions(
            configProfileV2: request.configProfileV2,
            strictConfig: request.strictConfig
        ),
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
                options: CodexCLI.ExecCommandOptions(strictConfig: request.strictConfig),
                configOverrides: mcpConfigOverrides(for: toolCall, rootOverrides: request.configOverrides)
            )
            let result = try await runExecCommand(execRequest, baseInstructionsOverride: toolCall.baseInstructions)
            return CodexMCPToolResult(
                text: mcpToolText(for: result),
                isError: result.exitCode != 0,
                threadID: result.threadID
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
                options: CodexCLI.ExecCommandOptions(strictConfig: request.strictConfig),
                configOverrides: request.configOverrides
            )
            let result = try await runExecCommand(execRequest, baseInstructionsOverride: nil)
            return CodexMCPToolResult(
                text: mcpToolText(for: result),
                isError: result.exitCode != 0,
                threadID: reply.threadID
            )
        }
    )
    return CodexCLI.CommandExecutionResult(exitCode: 0)
}

private func runAppServerCommand(_ request: CodexCLI.AppServerCommandRequest) async throws -> CodexCLI.CommandExecutionResult {
    switch request.action {
    case .run:
        let websocketAuth = try AppServerWebsocketAuthValidator.settings(from: request.websocketAuth)
        let codexHome = try CodexHome.find()
        let settings = try CodexConfigLoader.load(
            codexHome: codexHome,
            overrides: request.configOverrides,
            strictConfig: request.strictConfig
        )
        let logEnabled = settings.otel.exporter.isEnabled
        let traceEnabled = settings.otel.traceExporter.isEnabled
        let metricsEnabled = settings.otel.metricsEnabled(
            analyticsEnabled: settings.analyticsEnabled,
            defaultAnalyticsEnabled: request.analyticsDefaultEnabled
        )
        if logEnabled || traceEnabled || metricsEnabled {
            try settings.otel.validateProviderStartup(traceEnabled: traceEnabled)
        }
        let stateStore: SQLiteAgentGraphStore?
        do {
            stateStore = try CodexAppServer.defaultStateStore(codexHome: codexHome, runtimeConfig: settings)
        } catch {
            throw StateDBRecovery.startupError(
                codexHome: codexHome,
                runtimeConfig: settings,
                underlyingError: error
            )
        }
        try AppServerExecutableTransportValidator.validateSupportedTransport(
            request.listenTransport,
            websocketAuth: websocketAuth,
            remoteControlEnabled: request.remoteControlEnabled,
            stateStoreAvailable: stateStore != nil,
            remoteControlBaseURL: settings.chatgptBaseURL
        )
        let remoteControlStartState = try RemoteControlStartState(
            remoteControlURL: settings.chatgptBaseURL,
            installationID: try InstallationIDResolver.resolve(codexHome: codexHome),
            requestedEnabled: request.remoteControlEnabled,
            stateDatabaseAvailable: stateStore != nil
        )
        let configuration = CodexAppServerConfiguration(
            codexHome: codexHome,
            defaultModelProvider: settings.selectedModelProviderID,
            version: CodexCLI.version,
            requiresOpenAIAuth: settings.selectedModelProvider?.requiresOpenAIAuth ?? true,
            authCredentialsStoreMode: settings.cliAuthCredentialsStoreMode,
            sessionSource: request.sessionSource,
            activeProfile: settings.activeProfile,
            stateStore: stateStore,
            remoteControlStatusSnapshot: CodexAppServerConfiguration.RemoteControlStatusSnapshot(
                remoteControlStartState.statusSnapshot
            )
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
            guard let stateStore else {
                throw AppServerExecutableTransportError.remoteControlUnavailableWithoutStateDB
            }
            try await CodexAppServer.runRemoteControlExecutable(
                configuration: configuration,
                startState: remoteControlStartState,
                codexHome: codexHome,
                authCredentialsStoreMode: settings.cliAuthCredentialsStoreMode,
                stateStore: stateStore
            )
        }
        return CodexCLI.CommandExecutionResult(exitCode: 0)
    case .remoteControl:
        let output = try await AppServerDaemonLifecycle.ensureRemoteControlStarted(
            codexHome: try CodexHome.find(),
            cliVersion: CodexCLI.version
        )
        return CodexCLI.CommandExecutionResult(
            exitCode: 0,
            stdoutMessage: try AppServerDaemonLifecycle.encodeRemoteControlStartOutput(output) + "\n"
        )
    case .remoteControlStop:
        let output = try await AppServerDaemonLifecycle.stop(
            codexHome: try CodexHome.find(),
            cliVersion: CodexCLI.version
        )
        return CodexCLI.CommandExecutionResult(
            exitCode: 0,
            stdoutMessage: try AppServerDaemonLifecycle.encodeOutput(output) + "\n"
        )
    case .daemonStart:
        let output = try await AppServerDaemonLifecycle.start(
            codexHome: try CodexHome.find(),
            cliVersion: CodexCLI.version
        )
        return CodexCLI.CommandExecutionResult(
            exitCode: 0,
            stdoutMessage: try AppServerDaemonLifecycle.encodeOutput(output) + "\n"
        )
    case .daemonRestart:
        let output = try await AppServerDaemonLifecycle.restart(
            codexHome: try CodexHome.find(),
            cliVersion: CodexCLI.version
        )
        return CodexCLI.CommandExecutionResult(
            exitCode: 0,
            stdoutMessage: try AppServerDaemonLifecycle.encodeOutput(output) + "\n"
        )
    case let .daemonBootstrap(remoteControlEnabled):
        let output = try await AppServerDaemonLifecycle.bootstrap(
            codexHome: try CodexHome.find(),
            cliVersion: CodexCLI.version,
            remoteControlEnabled: remoteControlEnabled
        )
        return CodexCLI.CommandExecutionResult(
            exitCode: 0,
            stdoutMessage: try AppServerDaemonLifecycle.encodeBootstrapOutput(output) + "\n"
        )
    case .daemonEnableRemoteControl:
        let output = try await AppServerDaemonLifecycle.setRemoteControl(
            codexHome: try CodexHome.find(),
            cliVersion: CodexCLI.version,
            enabled: true
        )
        return CodexCLI.CommandExecutionResult(
            exitCode: 0,
            stdoutMessage: try AppServerDaemonLifecycle.encodeRemoteControlOutput(output) + "\n"
        )
    case .daemonDisableRemoteControl:
        let output = try await AppServerDaemonLifecycle.setRemoteControl(
            codexHome: try CodexHome.find(),
            cliVersion: CodexCLI.version,
            enabled: false
        )
        return CodexCLI.CommandExecutionResult(
            exitCode: 0,
            stdoutMessage: try AppServerDaemonLifecycle.encodeRemoteControlOutput(output) + "\n"
        )
    case .daemonStop:
        let output = try await AppServerDaemonLifecycle.stop(
            codexHome: try CodexHome.find(),
            cliVersion: CodexCLI.version
        )
        return CodexCLI.CommandExecutionResult(
            exitCode: 0,
            stdoutMessage: try AppServerDaemonLifecycle.encodeOutput(output) + "\n"
        )
    case .daemonVersion:
        let output = try await AppServerDaemonLifecycle.version(
            codexHome: try CodexHome.find(),
            cliVersion: CodexCLI.version
        )
        return CodexCLI.CommandExecutionResult(
            exitCode: 0,
            stdoutMessage: try AppServerDaemonLifecycle.encodeOutput(output) + "\n"
        )
    case .daemonPidUpdateLoop:
        try await AppServerDaemonLifecycle.runPidUpdateLoop()
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

private typealias NonInteractiveResponseEventHandler = @Sendable (Result<ResponseEvent, APIError>) async -> Void
private typealias NonInteractiveTurnHistoryHandler = @Sendable ([ResponseItem]) async -> Void

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
    sessionStartSource: HookSessionStartSource = .startup,
    responseEventHandler: NonInteractiveResponseEventHandler? = nil,
    turnHistoryHandler: NonInteractiveTurnHistoryHandler? = nil,
    approvalHandler: NonInteractiveExec.FunctionCallApprovalHandler? = nil
) async throws -> CodexCLI.CommandExecutionResult {
    try NonInteractiveInput.enforceGitRepository(
        cwd: cwd,
        skipGitRepoCheck: options.skipGitRepoCheck
    )

    let environment = ProcessInfo.processInfo.environment
    let codexHome = try CodexHome.find()
    let loaderOverrides = execLoaderOverrides(options: options, codexHome: codexHome)
    let settings = try CodexConfigLoader.load(
        codexHome: codexHome,
        cwd: cwd,
        overrides: configOverrides,
        managedConfigOverrides: loaderOverrides,
        strictConfig: options.strictConfig
    )
    let configStack = try CodexConfigLayerLoader.loadConfigLayerStack(
        codexHome: codexHome,
        cwd: cwd,
        cliOverrides: configOverrides,
        overrides: loaderOverrides,
        environment: environment,
        strictConfig: options.strictConfig
    )
    let execPolicyManager = try ExecPolicyManager.load(features: settings.features, configStack: configStack)
    let hookHandlers = HookConfig.configuredHandlers(
        from: configStack,
        codexHome: codexHome,
        bypassHookTrust: options.bypassHookTrust,
        environment: environment
    )
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
        return CodexCLI.CommandExecutionResult(
            exitCode: 1,
            stderrMessage: message,
            threadID: conversationID.description
        )
    }
    guard providerResolution.info.wireAPI == .responses else {
        return CodexCLI.CommandExecutionResult(
            exitCode: 78,
            stderrMessage: "codex-swift: exec currently supports Responses API model providers only.",
            threadID: conversationID.description
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
    let permissionProfile = resolveExecPermissionProfile(
        settings: settings,
        arguments: arguments,
        sandboxPolicy: sandboxPolicy,
        cwd: cwd
    )
    let effectiveWorkspaceRoots = ConfigSummary.resolveEffectiveWorkspaceRoots(
        config: settings,
        cwd: cwd,
        additionalWritableRootArguments: execLongOptionValues("--add-dir", in: arguments)
    )
    let shell = ShellSnapshot.attachSnapshotIfEnabled(
        codexHome: codexHome,
        sessionID: ThreadId(uuid: conversationID.uuid),
        sessionCwd: cwd,
        shell: ShellResolver.defaultUserShell(),
        features: settings.features
    )
    let configuredEnvironmentSnapshot = try loaderOverrides.ignoreUserConfig
        ? ConfiguredEnvironmentLoader.legacyEnvironmentSnapshot(environment: environment)
        : ConfiguredEnvironmentLoader.load(codexHome: codexHome, environment: environment)
    let turnEnvironmentSelections = configuredEnvironmentSnapshot.defaultThreadEnvironmentSelections(cwd: cwd.path)
    let configuredTools = NonInteractiveExec.toolSpecs(
        modelFamily: modelFamily,
        config: settings,
        environmentMode: .fromCount(turnEnvironmentSelections.count)
    )
    let configSummary = ConfigSummary.renderStartupBanner(
        version: CodexCLI.version,
        entries: ConfigSummary.createEntries(
            config: ConfigSummaryInput(
                workdir: cwd.standardizedFileURL.path,
                modelProviderID: providerResolution.id,
                approvalPolicy: approvalPolicy,
                sandboxPolicy: sandboxPolicy,
                permissionProfile: permissionProfile,
                effectiveWorkspaceRoots: effectiveWorkspaceRoots.map(\.path),
                modelProviderWireAPI: providerResolution.info.wireAPI,
                modelReasoningEffort: settings.modelReasoningEffort,
                modelReasoningSummary: settings.modelReasoningSummary ?? modelFamily.defaultReasoningSummary
            ),
            model: resolvedModel
        )
    )
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
    let multiAgentV2UsageHintText = settings.multiAgentV2.usageHintText(
        features: settings.features,
        sessionSource: .exec
    )
    var prompt = NonInteractiveExec.makePrompt(
        prompt: promptResolution.prompt,
        imagePaths: options.imagePaths,
        outputSchema: outputSchema,
        cwd: cwd,
        approvalPolicy: approvalPolicy,
        sandboxPolicy: sandboxPolicy,
        permissionProfile: permissionProfile,
        shell: shell,
        includeEnvironmentContext: settings.includeEnvironmentContext,
        includePermissionsInstructions: settings.includePermissionsInstructions,
        developerInstructions: settings.developerInstructions,
        memoryToolDeveloperInstructions: memoryToolDeveloperInstructions,
        multiAgentV2UsageHintText: multiAgentV2UsageHintText,
        availableSkills: availableSkills,
        userInstructions: projectInstructions,
        environmentContextEnvironments: configuredEnvironmentSnapshot.environmentContextEnvironments(
            cwd: cwd.path,
            shell: shell
        ),
        history: history,
        tools: configuredTools.map(\.spec),
        parallelToolCalls: modelFamily.supportsParallelToolCalls
    )
    if let baseInstructionsOverride {
        prompt.baseInstructionsOverride = baseInstructionsOverride
    } else {
        prompt.baseInstructionsOverride = try readModelInstructionsFile(
            settings.modelInstructionsFile,
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
            stderrMessage: nil,
            threadID: conversationID.description
        )
    }
    if userPromptSubmitOutcome.shouldStop {
        return CodexCLI.CommandExecutionResult(
            exitCode: 0,
            stdoutMessage: userPromptSubmitOutcome.stopReason,
            stderrMessage: nil,
            threadID: conversationID.description
        )
    }

    let client = ResponsesClient(
        transport: URLSessionAPITransport(),
        provider: provider,
        auth: authResolution.auth
    )
    let clientVersion = ModelsManager.formatClientVersion(packageVersion: CodexCLI.version)
    let requestTrace = W3CTraceContext.fromEnvironment()
    let stopHookContext = NonInteractiveExec.StopHookContext(
        handlers: hookHandlers,
        conversationID: conversationID,
        turnID: "turn-1",
        cwd: cwd,
        model: resolvedModel,
        approvalPolicy: approvalPolicy
    )
    let toolRouter = NonInteractiveExec.ToolRouter(
        hookContext: stopHookContext,
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
        canRequestOriginalImageDetail: modelFamily.supportsImageDetailOriginal,
        backgroundTerminalMaxTimeoutMS: settings.backgroundTerminalMaxTimeoutMS,
        turnEnvironmentSelections: turnEnvironmentSelections,
        configuredEnvironmentSnapshot: configuredEnvironmentSnapshot,
        features: settings.features,
        execPolicyManager: execPolicyManager,
        windowsSandboxLevel: settings.windowsSandboxLevel,
        approvalHandler: approvalHandler
    )
    let loopResult = await NonInteractiveExec.runResponsesLoopWithTranscript(
        initialPrompt: prompt,
        features: settings.features,
        handleModelsETag: { etag in
            _ = try? await ModelsManager.refreshCachedModelsIfNewETag(
                codexHome: codexHome,
                config: settings,
                provider: provider,
                auth: authResolution.auth,
                transport: URLSessionAPITransport(),
                clientVersion: clientVersion,
                modelsETag: etag
            )
        },
        streamPrompt: { nextPrompt in
            let responseOptions = NonInteractiveExec.responsesOptions(
                conversationID: conversationID,
                modelFamily: modelFamily,
                reasoningEffort: settings.modelReasoningEffort,
                reasoningSummary: settings.modelReasoningSummary,
                verbosity: settings.modelVerbosity,
                serviceTier: settings.serviceTier,
                outputSchema: outputSchema,
                requestTrace: requestTrace
            )
            if let responseEventHandler {
                switch await client.streamPromptEventsRetryingProviderCommandAuth(
                    model: resolvedModel,
                    instructions: nextPrompt.fullInstructions(for: modelFamily),
                    prompt: nextPrompt,
                    options: responseOptions,
                    providerInfo: providerResolution.info,
                    commandRunner: commandAuthRunner
                ) {
                case let .success(stream):
                    var results: ResponseEventResults = []
                    for await result in ResponseEventAggregator.aggregate(stream, mode: .streaming) {
                        results.append(result)
                        await responseEventHandler(result)
                    }
                    return .success(results)
                case let .failure(error):
                    return .failure(error)
                }
            }

            return await client.streamPromptRetryingProviderCommandAuth(
                model: resolvedModel,
                instructions: nextPrompt.fullInstructions(for: modelFamily),
                prompt: nextPrompt,
                options: responseOptions,
                providerInfo: providerResolution.info,
                commandRunner: commandAuthRunner
            )
        },
        stopHookContext: stopHookContext,
        toolRouter: toolRouter
    )
    try recorder?.recordItems(loopResult.transcriptItems.map(RolloutRecordItem.responseItem))
    var completedTurnHistory: [ResponseItem] = []
    if let userPromptItem {
        completedTurnHistory.append(userPromptItem)
    }
    completedTurnHistory.append(contentsOf: hookAdditionalItems)
    completedTurnHistory.append(contentsOf: loopResult.transcriptItems)
    if !completedTurnHistory.isEmpty {
        await turnHistoryHandler?(completedTurnHistory)
    }

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
    if options.bypassHookTrust {
        stderrMessages.append(
            "`--dangerously-bypass-hook-trust` is enabled. Enabled hooks may run without review for this invocation."
        )
    }
    if !options.json {
        stderrMessages.append(configSummary)
    }
    stderrMessages.append(contentsOf: result.stderrMessages)

    return CodexCLI.CommandExecutionResult(
        exitCode: result.exitCode,
        stdoutMessage: result.stdoutMessage,
        stderrMessage: stderrMessages.isEmpty ? nil : stderrMessages.joined(separator: "\n"),
        threadID: conversationID.description
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
        if providerID == OSSProvider.legacyOllamaChatProviderID {
            throw ExecRuntimeError(description: OSSProvider.legacyOllamaChatRemovedMessage)
        }
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

private func readStdinData() throws -> Data {
    FileHandle.standardInput.readDataToEndOfFile()
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

private func resolveExecPermissionProfile(
    settings: CodexRuntimeConfig,
    arguments: [String],
    sandboxPolicy: SandboxPolicy,
    cwd: URL
) -> PermissionProfile {
    let hasLegacySandboxOverride = execHasFlag("--dangerously-bypass-approvals-and-sandbox", in: arguments)
        || execHasFlag("--yolo", in: arguments)
        || execHasFlag("--full-auto", in: arguments)
        || execOptionValue(short: "-s", long: "--sandbox", in: arguments) != nil
    if hasLegacySandboxOverride {
        return PermissionProfile.fromLegacySandboxPolicyForCwd(sandboxPolicy, cwd: cwd.path)
    }
    return settings.permissionProfile ?? PermissionProfile.fromLegacySandboxPolicyForCwd(sandboxPolicy, cwd: cwd.path)
}

private func sandboxPolicy(from mode: SandboxMode) -> SandboxPolicy {
    SandboxPolicy.fromSandboxMode(mode)
}

private func readModelInstructionsFile(_ path: String?, cwd: URL) throws -> String? {
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

private func execLongOptionValues(_ long: String, in arguments: [String]) -> [String] {
    var values: [String] = []
    var index = 0
    while index < arguments.count {
        let argument = arguments[index]
        if argument == long {
            if index + 1 < arguments.count {
                values.append(arguments[index + 1])
                index += 2
                continue
            }
            return values
        }
        if argument.hasPrefix("\(long)=") {
            values.append(String(argument.dropFirst(long.count + 1)))
        }
        index += 1
    }
    return values
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

    switch resolution {
    case let .session(session):
        let initialHistory = try RolloutRecorder.getRolloutHistory(path: URL(fileURLWithPath: session.path))
        let responseHistory = RolloutRecorder.reconstructResponseHistory(from: initialHistory.rolloutItems)
        return try await runLineModeInteractiveCommand(
            CodexCLI.InteractiveCommandRequest(
                prompt: nil,
                remote: request.remote,
                remoteAuthTokenEnv: request.remoteAuthTokenEnv,
                interactiveOptions: request.interactiveOptions,
                configOverrides: request.configOverrides,
                strictConfig: request.strictConfig
            ),
            conversationID: session.conversationID,
            initialHistory: responseHistory,
            resumedRolloutPath: URL(fileURLWithPath: session.path),
            forkedFromID: nil,
            initialHistoryForNewRollout: nil,
            firstTurnStartSource: .resume,
            initialThreadID: session.conversationID.description
        )
    case .picker:
        return CodexCLI.CommandExecutionResult(exitCode: 0, stdoutMessage: ResumeCommandFormatter.render(resolution))
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

    switch resolution {
    case let .session(session):
        let initialHistory = try RolloutRecorder.getRolloutHistory(path: URL(fileURLWithPath: session.path))
        let initialRolloutItems = RolloutRecorder.forkedRolloutItems(from: initialHistory)
        let responseHistory = RolloutRecorder.reconstructResponseHistory(from: initialRolloutItems)
        let conversationID = ConversationId()
        return try await runLineModeInteractiveCommand(
            CodexCLI.InteractiveCommandRequest(
                prompt: nil,
                remote: request.remote,
                remoteAuthTokenEnv: request.remoteAuthTokenEnv,
                interactiveOptions: request.interactiveOptions,
                configOverrides: request.configOverrides,
                strictConfig: request.strictConfig
            ),
            conversationID: conversationID,
            initialHistory: responseHistory,
            resumedRolloutPath: nil,
            forkedFromID: session.conversationID,
            initialHistoryForNewRollout: initialHistory,
            firstTurnStartSource: .startup,
            initialThreadID: conversationID.description
        )
    case .picker:
        return CodexCLI.CommandExecutionResult(exitCode: 0, stdoutMessage: ResumeCommandFormatter.render(resolution))
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
    case let .remote(baseURL, executorID, name, useAgentIdentityAuth):
        let authProvider = try await execServerRemoteAuthProvider(
            useAgentIdentityAuth: useAgentIdentityAuth,
            configProfileV2: request.configProfileV2,
            configOverrides: request.configOverrides
        )
        let config = try ExecServerRemoteExecutorConfiguration(
            baseURL: baseURL,
            executorID: executorID,
            name: name ?? "codex-exec-server",
            authProvider: authProvider
        )
        let executor = try ExecServerRemoteExecutor(config: config)
        try await executor.run()
        return CodexCLI.CommandExecutionResult(exitCode: 0)
    }
}

private func execServerRemoteAuthProvider(
    useAgentIdentityAuth: Bool,
    configProfileV2: String?,
    configOverrides: CliConfigOverrides,
    environment: [String: String] = ProcessInfo.processInfo.environment
) async throws -> StaticAPIAuthProvider {
    let codexHome = try CodexHome.find()
    let settings = try CodexConfigLoader.load(
        codexHome: codexHome,
        overrides: configOverrides,
        systemConfigFile: nil,
        managedConfigOverrides: profileV2LoaderOverrides(profile: configProfileV2, codexHome: codexHome)
    )

    if useAgentIdentityAuth {
        guard let accessToken = CodexAuthStorage.readCodexAccessTokenFromEnvironment(environment) else {
            throw CodexRuntimeError.fatal("CODEX_ACCESS_TOKEN is required when --use-agent-identity-auth is set")
        }
        let claims = try AgentIdentity.decodeJWTClaims(accessToken)
        let key = AgentIdentityKey(
            agentRuntimeID: claims.agentRuntimeID,
            privateKeyPKCS8Base64: claims.agentPrivateKey
        )
        let taskID = try await AgentIdentity.registerAgentTask(
            transport: URLSessionAPITransport(),
            chatGPTBaseURL: settings.chatgptBaseURL,
            key: key
        )
        let authorizationHeader = try AgentIdentity.authorizationHeaderForAgentTask(
            key: key,
            target: AgentTaskAuthorizationTarget(agentRuntimeID: claims.agentRuntimeID, taskID: taskID)
        )
        return StaticAPIAuthProvider(
            accountID: claims.accountID,
            authorizationHeader: authorizationHeader
        )
    }

    let storedAuth = try CodexAuthStorage.loadEffectiveAuthDotJSON(
        codexHome: codexHome,
        mode: settings.cliAuthCredentialsStoreMode
    )
    guard storedAuth?.openAIAPIKey == nil,
          storedAuth?.authMode != .agentIdentity
    else {
        throw CodexRuntimeError.fatal(
            "remote exec-server registration requires ChatGPT authentication; API key and Agent Identity auth are not supported"
        )
    }
    guard let tokens = try await CodexAuthStorage.loadFreshTokenData(
        codexHome: codexHome,
        mode: settings.cliAuthCredentialsStoreMode
    ) else {
        throw CodexRuntimeError.fatal(
            "remote exec-server registration requires ChatGPT authentication; run `codex login` first"
        )
    }

    return StaticAPIAuthProvider(
        bearerToken: tokens.accessToken,
        accountID: tokens.accountID
    )
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
    case let .add(plugin, marketplaceName):
        let result = try CodexAppServer.pluginAddCommandResult(
            plugin: plugin,
            marketplaceName: marketplaceName,
            configuration: configuration
        )
        let pluginName = result["pluginName"] as? String ?? plugin
        let marketplaceName = result["marketplaceName"] as? String ?? marketplaceName ?? ""
        var lines = ["Added plugin `\(pluginName)` from marketplace `\(marketplaceName)`."]
        if let installedPath = result["installedPath"] as? String {
            lines.append("Installed plugin root: \(installedPath)")
        }
        return CodexCLI.CommandExecutionResult(exitCode: 0, stdoutMessage: lines.joined(separator: "\n"))

    case let .list(marketplaceName):
        let result = try CodexAppServer.pluginListCommandResult(
            marketplaceName: marketplaceName,
            configuration: configuration
        )
        let marketplaces = result["marketplaces"] as? [[String: Any]] ?? []
        guard !marketplaces.isEmpty else {
            let message = marketplaceName.map { "No plugins found in marketplace `\($0)`." }
                ?? "No marketplace plugins found."
            return CodexCLI.CommandExecutionResult(exitCode: 0, stdoutMessage: message)
        }
        var lines: [String] = []
        for marketplace in marketplaces {
            let marketplaceName = marketplace["name"] as? String ?? ""
            lines.append("Marketplace `\(marketplaceName)`")
            if let path = marketplace["path"] as? String {
                lines.append("Path: \(path)")
            }
            let plugins = marketplace["plugins"] as? [[String: Any]] ?? []
            for plugin in plugins {
                let pluginID = plugin["id"] as? String ?? plugin["name"] as? String ?? ""
                let installed = plugin["installed"] as? Bool ?? false
                let enabled = plugin["enabled"] as? Bool ?? true
                let state = installed && enabled
                    ? "installed, enabled"
                    : installed ? "installed, disabled" : "not installed"
                lines.append("  \(pluginID) (\(state))")
            }
        }
        return CodexCLI.CommandExecutionResult(exitCode: 0, stdoutMessage: lines.joined(separator: "\n"))

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

    case .marketplaceList:
        let result = try CodexAppServer.marketplaceListCommandResult(configuration: configuration)
        let marketplaces = result["marketplaces"] as? [[String: String]] ?? []
        let ignored = result["ignored"] as? [[String: String]] ?? []
        let stdoutMessage: String
        if marketplaces.isEmpty {
            stdoutMessage = "No configured plugin marketplaces."
        } else {
            stdoutMessage = marketplaces.map { marketplace in
                "\(marketplace["marketplaceName"] ?? "")\t\(marketplace["root"] ?? "")"
            }.joined(separator: "\n")
        }
        let stderrMessage = ignored.isEmpty ? nil : ignored.map { ignored in
            "Ignoring invalid marketplace `\(ignored["marketplaceName"] ?? "")`: \(ignored["message"] ?? "")."
        }.joined(separator: "\n")
        return CodexCLI.CommandExecutionResult(
            exitCode: 0,
            stdoutMessage: stdoutMessage,
            stderrMessage: stderrMessage
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

    case let .remove(plugin, marketplaceName):
        let result = try CodexAppServer.pluginRemoveCommandResult(
            plugin: plugin,
            marketplaceName: marketplaceName,
            configuration: configuration
        )
        let pluginName = result["pluginName"] as? String ?? plugin
        let marketplaceName = result["marketplaceName"] as? String ?? marketplaceName ?? ""
        return CodexCLI.CommandExecutionResult(
            exitCode: 0,
            stdoutMessage: "Removed plugin `\(pluginName)` from marketplace `\(marketplaceName)`."
        )
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

private struct SecretReadResult {
    let exitCode: Int32
    let message: String
    let value: String?
}

private func readSecretFromStdin(
    terminalMessage: String,
    readingMessage: String,
    emptyMessage: String,
    invalidUTF8Message: String
) -> SecretReadResult {
    if isatty(STDIN_FILENO) != 0 {
        return SecretReadResult(
            exitCode: 1,
            message: terminalMessage,
            value: nil
        )
    }

    let data = FileHandle.standardInput.readDataToEndOfFile()
    guard let input = String(data: data, encoding: .utf8) else {
        return SecretReadResult(
            exitCode: 1,
            message: invalidUTF8Message,
            value: nil
        )
    }
    let apiKey = input.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !apiKey.isEmpty else {
        return SecretReadResult(exitCode: 1, message: emptyMessage, value: nil)
    }
    return SecretReadResult(exitCode: 0, message: readingMessage, value: apiKey)
}

private func safeFormatAPIKey(_ apiKey: String) -> String {
    guard apiKey.count > 13 else {
        return "***"
    }
    return "\(apiKey.prefix(8))***\(apiKey.suffix(5))"
}
