import CodexChatGPT
import CodexCLI
import CodexCore
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
    execPolicyRunner: runExecPolicyCommand,
    stdioToUDSRunner: runStdioToUDSCommand,
    cloudRunner: runCloudCommand
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
        let (_, settings) = try resolvedAuthSettings(overrides: request.configOverrides)
        if settings.forcedLoginMethod == .api {
            return CodexCLI.CommandExecutionResult(
                exitCode: 1,
                stderrMessage: "ChatGPT login is disabled. Use API key login instead."
            )
        }
        return CodexCLI.CommandExecutionResult(
            exitCode: 78,
            stderrMessage: "codex-swift: ChatGPT login runtime is not complete yet."
        )

    case .deviceCode:
        let (_, settings) = try resolvedAuthSettings(overrides: request.configOverrides)
        if settings.forcedLoginMethod == .api {
            return CodexCLI.CommandExecutionResult(
                exitCode: 1,
                stderrMessage: "ChatGPT login is disabled. Use API key login instead."
            )
        }
        return CodexCLI.CommandExecutionResult(
            exitCode: 78,
            stderrMessage: "codex-swift: device-code login runtime is not complete yet."
        )
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
