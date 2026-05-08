import CodexChatGPT
import CodexCLI
import CodexCore
import CodexResponsesAPIProxy
import CodexStdioToUDS
import Darwin
import Foundation

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
    execRunner: runExecCommand,
    resumeRunner: runResumeCommand,
    execPolicyRunner: runExecPolicyCommand,
    sandboxRunner: runSandboxCommand,
    mcpRunner: runMcpCommand,
    stdioToUDSRunner: runStdioToUDSCommand,
    cloudRunner: runCloudCommand,
    responsesAPIProxyRunner: runResponsesAPIProxyCommand
)
exit(exitCode)

private func resolvedAuthSettings(overrides: CliConfigOverrides) throws -> (codexHome: URL, settings: CodexRuntimeConfig) {
    let codexHome = try CodexHome.find()
    let settings = try CodexConfigLoader.load(
        codexHome: codexHome,
        cwd: URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true),
        overrides: overrides
    )
    return (codexHome, settings)
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

private func runFeaturesCommand(_ request: CodexCLI.FeaturesCommandRequest) async throws -> String {
    let (_, settings) = try resolvedAuthSettings(overrides: request.configOverrides)
    return FeatureRegistry.specs
        .map { spec in
            "\(spec.key)\t\(spec.stage.listName)\t\(settings.features.isEnabled(spec.id))"
        }
        .joined(separator: "\n")
}

private func runExecCommand(_ request: CodexCLI.ExecCommandRequest) async throws -> CodexCLI.CommandExecutionResult {
    guard case .run = request.action else {
        return CodexCLI.CommandExecutionResult(
            exitCode: 78,
            stderrMessage: "codex-swift: exec resume/review runtime is not complete yet."
        )
    }

    let operation = try request.resolvedInitialOperation(
        stdinIsTerminal: isatty(STDIN_FILENO) != 0,
        readStdin: readUTF8FromStdin,
        readFile: { path in
            try Data(contentsOf: URL(fileURLWithPath: path))
        }
    )
    guard case let .userTurn(promptResolution, outputSchema) = operation else {
        return CodexCLI.CommandExecutionResult(
            exitCode: 78,
            stderrMessage: "codex-swift: exec resume/review runtime is not complete yet."
        )
    }

    let cwd = resolveExecWorkingDirectory(from: request.arguments)
    try NonInteractiveInput.enforceGitRepository(
        cwd: cwd,
        skipGitRepoCheck: request.options.skipGitRepoCheck
    )

    let (codexHome, settings) = try resolvedAuthSettings(overrides: request.configOverrides)
    let environment = ProcessInfo.processInfo.environment
    try await CodexAuthStorage.enforceLoginRestrictions(
        codexHome: codexHome,
        config: settings,
        environment: environment
    )

    let providerResolution = try resolveExecModelProvider(settings: settings, environment: environment)
    guard providerResolution.info.wireAPI == .responses else {
        return CodexCLI.CommandExecutionResult(
            exitCode: 78,
            stderrMessage: "codex-swift: exec currently supports Responses API model providers only."
        )
    }

    let authResolution = try await resolveExecAuth(
        codexHome: codexHome,
        settings: settings,
        providerInfo: providerResolution.info,
        environment: environment
    )
    let provider = providerResolution.info.toAPIProvider(
        authMode: authResolution.authMode,
        environment: environment
    )
    let model = execOptionValue(short: "-m", long: "--model", in: request.arguments)
        ?? settings.model
        ?? (authResolution.authMode == .chatGPT
            ? ModelsManager.openAIDefaultChatGPTModel
            : ModelsManager.openAIDefaultAPIModel)
    let modelFamily = ModelsManager.constructModelFamilyOffline(model: model)
    let approvalPolicy = resolveExecApprovalPolicy(settings: settings, arguments: request.arguments)
    let sandboxPolicy = resolveExecSandboxPolicy(settings: settings, arguments: request.arguments)
    let shell = ShellResolver.defaultUserShell()
    var prompt = NonInteractiveExec.makePrompt(
        prompt: promptResolution.prompt,
        imagePaths: request.options.imagePaths,
        outputSchema: outputSchema,
        cwd: cwd,
        approvalPolicy: approvalPolicy,
        sandboxPolicy: sandboxPolicy,
        shell: shell
    )
    prompt.baseInstructionsOverride = try readExperimentalInstructionsFile(
        settings.experimentalInstructionsFile,
        cwd: cwd
    )

    let conversationID = ConversationId()
    let client = ResponsesClient(
        transport: URLSessionAPITransport(),
        provider: provider,
        auth: authResolution.auth
    )
    let streamResult = await client.streamPrompt(
        model: model,
        instructions: prompt.fullInstructions(for: modelFamily),
        prompt: prompt,
        options: NonInteractiveExec.responsesOptions(
            conversationID: conversationID,
            modelFamily: modelFamily,
            reasoningEffort: settings.modelReasoningEffort,
            reasoningSummary: settings.modelReasoningSummary,
            verbosity: settings.modelVerbosity,
            outputSchema: outputSchema
        )
    )

    let events: ResponseEventResults
    switch streamResult {
    case let .success(results):
        events = results
    case let .failure(error):
        events = [.failure(error)]
    }

    let result = NonInteractiveExec.finish(
        responseEvents: events,
        outputMode: request.options.json ? .jsonLines : .human,
        conversationID: conversationID,
        lastMessageFile: request.options.lastMessageFile
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

private struct ExecModelProviderResolution {
    let id: String
    let info: ModelProviderInfo
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
    environment: [String: String]
) throws -> ExecModelProviderResolution {
    var providers = settings.modelProviders
    let versionedOpenAI = ModelProviderInfo.createOpenAIProvider(
        environment: environment,
        packageVersion: CodexCLI.version
    )
    providers["openai"] = versionedOpenAI
    providers["openai-responses"] = versionedOpenAI

    let providerID = settings.modelProvider ?? "openai"
    guard let provider = providers[providerID] else {
        throw ExecRuntimeError(description: "Unknown model provider '\(providerID)'")
    }
    return ExecModelProviderResolution(id: providerID, info: provider)
}

private func resolveExecAuth(
    codexHome: URL,
    settings: CodexRuntimeConfig,
    providerInfo: ModelProviderInfo,
    environment: [String: String]
) async throws -> ExecAuthResolution {
    if let apiKey = CodexAuthStorage.readCodexAPIKeyFromEnvironment(environment) {
        return ExecAuthResolution(auth: StaticAPIAuthProvider(bearerToken: apiKey), authMode: .apiKey)
    }

    let storedAuth = try CodexAuthStorage.loadAuthDotJSON(
        codexHome: codexHome,
        mode: settings.cliAuthCredentialsStoreMode
    )

    if providerInfo.envKey != nil || providerInfo.experimentalBearerToken != nil {
        let auth = try APIAuthResolver.authProvider(
            auth: storedAuth,
            provider: providerInfo,
            environment: environment
        )
        return ExecAuthResolution(
            auth: auth,
            authMode: auth.accountID == nil ? .apiKey : .chatGPT
        )
    }

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
        ?? settings.sandboxMode
        ?? .readOnly
    return sandboxPolicy(from: mode)
}

private func sandboxPolicy(from mode: SandboxMode) -> SandboxPolicy {
    switch mode {
    case .readOnly:
        return .readOnly
    case .workspaceWrite:
        return SandboxPolicy.newWorkspaceWritePolicy()
    case .dangerFullAccess:
        return .dangerFullAccess
    }
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
    case let .macos(fullAuto, logDenials, command):
        let exitCode = try SeatbeltSandbox.run(
            command: command,
            fullAuto: fullAuto,
            cwd: URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true),
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

private func runMcpCommand(_ request: CodexCLI.McpCommandRequest) async throws -> CodexCLI.CommandExecutionResult {
    let codexHome = try CodexHome.find()

    switch request.action {
    case let .list(json):
        let (_, settings) = try resolvedAuthSettings(overrides: request.configOverrides)
        let servers = settings.mcpServers
        return CodexCLI.CommandExecutionResult(
            exitCode: 0,
            stdoutMessage: try McpCommandFormatter.list(
                servers: servers,
                json: json,
                authStatuses: await McpAuthStatusResolver.authStatuses(
                    for: servers,
                    codexHome: codexHome,
                    storeMode: settings.mcpOAuthCredentialsStoreMode,
                    environment: ProcessInfo.processInfo.environment
                )
            )
        )

    case let .get(name, json):
        let (_, settings) = try resolvedAuthSettings(overrides: request.configOverrides)
        guard let server = settings.mcpServers[name] else {
            return CodexCLI.CommandExecutionResult(
                exitCode: 1,
                stderrMessage: "No MCP server named '\(name)' found."
            )
        }
        return CodexCLI.CommandExecutionResult(
            exitCode: 0,
            stdoutMessage: try McpCommandFormatter.get(name: name, server: server, json: json)
        )

    case let .add(name, transport):
        try McpServerName.validate(name)
        var servers = try McpConfigStore.loadGlobalMcpServers(codexHome: codexHome)
        let serverTransport: McpServerTransportConfig
        switch transport {
        case let .stdio(command, envPairs):
            guard let commandBin = command.first else {
                return CodexCLI.CommandExecutionResult(exitCode: 1, stderrMessage: "command is required")
            }
            let env = envPairs.isEmpty ? nil : Dictionary(uniqueKeysWithValues: envPairs.map { ($0.key, $0.value) })
            serverTransport = .stdio(
                command: commandBin,
                args: Array(command.dropFirst()),
                env: env,
                envVars: [],
                cwd: nil
            )
        case let .streamableHttp(url, bearerTokenEnvVar):
            serverTransport = .streamableHttp(
                url: url,
                bearerTokenEnvVar: bearerTokenEnvVar,
                httpHeaders: nil,
                envHttpHeaders: nil
            )
        }
        servers[name] = McpServerConfig(transport: serverTransport)
        try McpConfigStore.replaceGlobalMcpServers(codexHome: codexHome, servers: servers)
        let addedMessage = "Added global MCP server '\(name)'."

        if case let .streamableHttp(url, nil, httpHeaders, envHttpHeaders) = serverTransport {
            let (_, settings) = try resolvedAuthSettings(overrides: request.configOverrides)
            do {
                if try await McpOAuthDiscovery.supportsOAuthLogin(
                    url: url,
                    httpHeaders: httpHeaders,
                    envHttpHeaders: envHttpHeaders,
                    environment: ProcessInfo.processInfo.environment
                ) {
                    print(addedMessage)
                    print("Detected OAuth support. Starting OAuth flow…")
                    try await runMcpOAuthLogin(
                        serverName: name,
                        serverURL: url,
                        codexHome: codexHome,
                        settings: settings,
                        httpHeaders: httpHeaders,
                        envHttpHeaders: envHttpHeaders,
                        scopes: []
                    )
                    return CodexCLI.CommandExecutionResult(
                        exitCode: 0,
                        stdoutMessage: "Successfully logged in."
                    )
                }
            } catch {
                return CodexCLI.CommandExecutionResult(
                    exitCode: 0,
                    stdoutMessage: "\(addedMessage)\nMCP server may or may not require login. Run `codex mcp login \(name)` to login."
                )
            }
        }

        return CodexCLI.CommandExecutionResult(exitCode: 0, stdoutMessage: addedMessage)

    case let .remove(name):
        try McpServerName.validate(name)
        var servers = try McpConfigStore.loadGlobalMcpServers(codexHome: codexHome)
        let removed = servers.removeValue(forKey: name) != nil
        if removed {
            try McpConfigStore.replaceGlobalMcpServers(codexHome: codexHome, servers: servers)
            return CodexCLI.CommandExecutionResult(
                exitCode: 0,
                stdoutMessage: "Removed global MCP server '\(name)'."
            )
        }
        return CodexCLI.CommandExecutionResult(
            exitCode: 0,
            stdoutMessage: "No MCP server named '\(name)' found."
        )

    case let .login(name, scopes):
        let (codexHome, settings) = try resolvedAuthSettings(overrides: request.configOverrides)
        guard let server = settings.mcpServers[name] else {
            return CodexCLI.CommandExecutionResult(
                exitCode: 1,
                stderrMessage: "No MCP server named '\(name)' found."
            )
        }
        guard case let .streamableHttp(url, _, httpHeaders, envHttpHeaders) = server.transport else {
            return CodexCLI.CommandExecutionResult(
                exitCode: 1,
                stderrMessage: "OAuth login is only supported for streamable HTTP servers."
            )
        }
        try await runMcpOAuthLogin(
            serverName: name,
            serverURL: url,
            codexHome: codexHome,
            settings: settings,
            httpHeaders: httpHeaders,
            envHttpHeaders: envHttpHeaders,
            scopes: scopes
        )
        return CodexCLI.CommandExecutionResult(
            exitCode: 0,
            stdoutMessage: "Successfully logged in to MCP server '\(name)'."
        )

    case let .logout(name):
        let (codexHome, settings) = try resolvedAuthSettings(overrides: request.configOverrides)
        guard let server = settings.mcpServers[name] else {
            return CodexCLI.CommandExecutionResult(
                exitCode: 1,
                stderrMessage: "No MCP server named '\(name)' found in configuration."
            )
        }
        guard case let .streamableHttp(url, _, _, _) = server.transport else {
            return CodexCLI.CommandExecutionResult(
                exitCode: 1,
                stderrMessage: "OAuth logout is only supported for streamable_http transports."
            )
        }
        do {
            let removed = try McpOAuthCredentialStore.deleteOAuthTokens(
                serverName: name,
                url: url,
                codexHome: codexHome,
                mode: settings.mcpOAuthCredentialsStoreMode
            )
            return CodexCLI.CommandExecutionResult(
                exitCode: 0,
                stdoutMessage: removed
                    ? "Removed OAuth credentials for '\(name)'."
                    : "No OAuth credentials stored for '\(name)'."
            )
        } catch {
            return CodexCLI.CommandExecutionResult(
                exitCode: 1,
                stderrMessage: "failed to delete OAuth credentials: \(String(describing: error))"
            )
        }
    }
}

private func runMcpOAuthLogin(
    serverName: String,
    serverURL: String,
    codexHome: URL,
    settings: CodexRuntimeConfig,
    httpHeaders: [String: String]?,
    envHttpHeaders: [String: String]?,
    scopes: [String]
) async throws {
    try await McpOAuthLogin.perform(
        request: McpOAuthLoginRequest(
            serverName: serverName,
            serverURL: serverURL,
            codexHome: codexHome,
            storeMode: settings.mcpOAuthCredentialsStoreMode,
            httpHeaders: httpHeaders,
            envHttpHeaders: envHttpHeaders,
            environment: ProcessInfo.processInfo.environment,
            scopes: scopes
        ),
        messageSink: { message in
            switch message {
            case let .authorizationURL(serverName, authURL):
                print("Authorize `\(serverName)` by opening this URL in your browser:\n\(authURL)\n")
            case .browserLaunchFailed:
                print("(Browser launch failed; please copy the URL above manually.)")
            }
        }
    )
}

private func runStdioToUDSCommand(_ request: CodexCLI.StdioToUDSCommandRequest) async throws -> CodexCLI.CommandExecutionResult {
    try StdioToUDS.run(socketPath: request.socketPath)
    return CodexCLI.CommandExecutionResult(exitCode: 0)
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
        let prompt = try readCloudExecPrompt(query: query)
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
        upstreamURL: request.upstreamURL
    ))
    return CodexCLI.CommandExecutionResult(exitCode: 1, stderrMessage: "server stopped unexpectedly")
}

private struct CloudExecPrompt {
    let prompt: String
    let stderrMessage: String?
}

private struct CloudExecPromptError: Error, CustomStringConvertible {
    let description: String
}

private func readCloudExecPrompt(query: String?) throws -> CloudExecPrompt {
    if let query, query != "-" {
        return CloudExecPrompt(prompt: query, stderrMessage: nil)
    }

    let forceStdin = query == "-"
    if isatty(STDIN_FILENO) != 0, !forceStdin {
        throw CloudExecPromptError(description: "no query provided. Pass one as an argument or pipe it via stdin.")
    }

    let stderrMessage = forceStdin ? nil : "Reading query from stdin..."
    let data = FileHandle.standardInput.readDataToEndOfFile()
    guard let input = String(data: data, encoding: .utf8) else {
        throw CloudExecPromptError(description: "failed to read query from stdin: stream did not contain valid UTF-8")
    }
    guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw CloudExecPromptError(description: "no query provided via stdin (received empty input).")
    }
    return CloudExecPrompt(prompt: input, stderrMessage: stderrMessage)
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
