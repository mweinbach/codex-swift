import CodexCore
import Darwin
import Foundation

public struct CodexCLI: Sendable {
    public static let version = "0.0.0"

    public init() {}

    public enum Invocation: Equatable, Sendable {
        case help
        case version
        case interactive(prompt: String?)
        case command(CommandSpec, arguments: [String])
        case unknown(String)
    }

    public struct ApplyCommandRequest: Equatable, Sendable {
        public let taskID: String
        public let configOverrides: CliConfigOverrides

        public init(taskID: String, configOverrides: CliConfigOverrides = CliConfigOverrides()) {
            self.taskID = taskID
            self.configOverrides = configOverrides
        }
    }

    public enum LoginCommandAction: Equatable, Sendable {
        case status
        case withAPIKeyFromStdin
        case chatGPT
        case deviceCode(issuerBaseURL: String?, clientID: String?)
    }

    public struct LoginCommandRequest: Equatable, Sendable {
        public let action: LoginCommandAction
        public let configOverrides: CliConfigOverrides

        public init(action: LoginCommandAction, configOverrides: CliConfigOverrides = CliConfigOverrides()) {
            self.action = action
            self.configOverrides = configOverrides
        }
    }

    public struct LogoutCommandRequest: Equatable, Sendable {
        public let configOverrides: CliConfigOverrides

        public init(configOverrides: CliConfigOverrides = CliConfigOverrides()) {
            self.configOverrides = configOverrides
        }
    }

    public enum FeaturesCommandAction: Equatable, Sendable {
        case list
        case enable(feature: String)
        case disable(feature: String)
    }

    public struct FeaturesCommandRequest: Equatable, Sendable {
        public let action: FeaturesCommandAction
        public let configProfile: String?
        public let configOverrides: CliConfigOverrides

        public init(
            action: FeaturesCommandAction = .list,
            configProfile: String? = nil,
            configOverrides: CliConfigOverrides = CliConfigOverrides()
        ) {
            self.action = action
            self.configProfile = configProfile
            self.configOverrides = configOverrides
        }
    }

    public enum ExecPolicyCommandAction: Equatable, Sendable {
        case check(rules: [String], pretty: Bool, command: [String])
    }

    public struct ExecPolicyCommandRequest: Equatable, Sendable {
        public let action: ExecPolicyCommandAction

        public init(action: ExecPolicyCommandAction) {
            self.action = action
        }
    }

    public struct ExecCommandRequest: Equatable, Sendable {
        public let arguments: [String]
        public let action: ExecCommandAction
        public let options: ExecCommandOptions
        public let configOverrides: CliConfigOverrides

        public init(
            arguments: [String],
            action: ExecCommandAction = .run(prompt: nil),
            options: ExecCommandOptions = ExecCommandOptions(),
            configOverrides: CliConfigOverrides = CliConfigOverrides()
        ) {
            self.arguments = arguments
            self.action = action
            self.options = options
            self.configOverrides = configOverrides
        }

        public func resolvedInitialOperation(
            stdinIsTerminal: Bool,
            readStdin: NonInteractiveInput.StdinReader,
            readFile: NonInteractiveInput.FileReader
        ) throws -> ResolvedExecInitialOperation {
            switch action {
            case let .run(promptArgument):
                let prompt = try NonInteractiveInput.resolvePrompt(
                    promptArgument,
                    stdinIsTerminal: stdinIsTerminal,
                    readStdin: readStdin
                )
                let outputSchema = try NonInteractiveInput.loadOutputSchema(
                    path: options.outputSchemaPath,
                    readFile: readFile
                )
                return .userTurn(prompt: prompt, outputSchema: outputSchema)

            case let .resume(resume):
                let prompt = try NonInteractiveInput.resolvePrompt(
                    resume.promptArgument,
                    stdinIsTerminal: stdinIsTerminal,
                    readStdin: readStdin
                )
                let outputSchema = try NonInteractiveInput.loadOutputSchema(
                    path: options.outputSchemaPath,
                    readFile: readFile
                )
                return .resume(
                    sessionID: resume.resumeSessionID,
                    last: resume.last,
                    all: resume.all,
                    prompt: prompt,
                    outputSchema: outputSchema
                )

            case let .review(target):
                return .review(try target.resolvedReviewRequest(
                    stdinIsTerminal: stdinIsTerminal,
                    readStdin: readStdin
                ))
            }
        }
    }

    public enum ExecCommandAction: Equatable, Sendable {
        case run(prompt: String?)
        case resume(ExecResumeCommand)
        case review(ReviewCommandTarget)
    }

    public struct ExecResumeCommand: Equatable, Sendable {
        public let sessionID: String?
        public let last: Bool
        public let all: Bool
        public let prompt: String?

        public init(sessionID: String?, last: Bool, all: Bool = false, prompt: String?) {
            self.sessionID = sessionID
            self.last = last
            self.all = all
            self.prompt = prompt
        }

        public var promptArgument: String? {
            prompt ?? (last ? sessionID : nil)
        }

        public var resumeSessionID: String? {
            last ? nil : sessionID
        }
    }

    public struct ExecCommandOptions: Equatable, Sendable {
        public static let removedFullAutoWarningMessage =
            "warning: `--full-auto` is deprecated; use `--sandbox workspace-write` instead."

        public let json: Bool
        public let imagePaths: [String]
        public let outputSchemaPath: String?
        public let lastMessageFile: String?
        public let skipGitRepoCheck: Bool
        public let ephemeral: Bool
        public let ignoreUserConfig: Bool
        public let ignoreRules: Bool
        public let removedFullAuto: Bool

        public init(
            json: Bool = false,
            imagePaths: [String] = [],
            outputSchemaPath: String? = nil,
            lastMessageFile: String? = nil,
            skipGitRepoCheck: Bool = false,
            ephemeral: Bool = false,
            ignoreUserConfig: Bool = false,
            ignoreRules: Bool = false,
            removedFullAuto: Bool = false
        ) {
            self.json = json
            self.imagePaths = imagePaths
            self.outputSchemaPath = outputSchemaPath
            self.lastMessageFile = lastMessageFile
            self.skipGitRepoCheck = skipGitRepoCheck
            self.ephemeral = ephemeral
            self.ignoreUserConfig = ignoreUserConfig
            self.ignoreRules = ignoreRules
            self.removedFullAuto = removedFullAuto
        }

        public var removedFullAutoWarning: String? {
            removedFullAuto ? Self.removedFullAutoWarningMessage : nil
        }
    }

    public enum ResolvedExecInitialOperation: Equatable, Sendable {
        case userTurn(prompt: NonInteractivePromptResolution, outputSchema: JSONValue?)
        case resume(
            sessionID: String?,
            last: Bool,
            all: Bool,
            prompt: NonInteractivePromptResolution,
            outputSchema: JSONValue?
        )
        case review(ReviewRequest)
    }

    public struct ComputerUseCommandRequest: Equatable, Sendable {
        public let arguments: [String]
        public let enableGUI: Bool
        public let configOverrides: CliConfigOverrides

        public init(
            arguments: [String],
            enableGUI: Bool,
            configOverrides: CliConfigOverrides = CliConfigOverrides()
        ) {
            self.arguments = arguments
            self.enableGUI = enableGUI
            self.configOverrides = configOverrides
        }
    }

    public enum ReviewCommandTarget: Equatable, Sendable {
        case uncommittedChanges
        case baseBranch(branch: String)
        case commit(sha: String, title: String?)
        case custom(instructions: String)
        case customFromStdin

        public var reviewRequest: ReviewRequest? {
            switch self {
            case .uncommittedChanges:
                return ReviewRequest(target: .uncommittedChanges)
            case let .baseBranch(branch):
                return ReviewRequest(target: .baseBranch(branch: branch))
            case let .commit(sha, title):
                return ReviewRequest(target: .commit(sha: sha, title: title))
            case let .custom(instructions):
                return ReviewRequest(target: .custom(instructions: instructions))
            case .customFromStdin:
                return nil
            }
        }

        public func resolvedReviewRequest(
            stdinIsTerminal: Bool,
            readStdin: NonInteractiveInput.StdinReader
        ) throws -> ReviewRequest {
            if let reviewRequest {
                return reviewRequest
            }

            let prompt = try NonInteractiveInput
                .resolvePrompt("-", stdinIsTerminal: stdinIsTerminal, readStdin: readStdin)
                .prompt
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return ReviewRequest(target: .custom(instructions: prompt))
        }
    }

    public struct ReviewCommandRequest: Equatable, Sendable {
        public let target: ReviewCommandTarget
        public let configOverrides: CliConfigOverrides

        public init(target: ReviewCommandTarget, configOverrides: CliConfigOverrides = CliConfigOverrides()) {
            self.target = target
            self.configOverrides = configOverrides
        }
    }

    public struct ResumeCommandRequest: Equatable, Sendable {
        public let sessionID: String?
        public let last: Bool
        public let all: Bool
        public let configOverrides: CliConfigOverrides

        public init(
            sessionID: String?,
            last: Bool,
            all: Bool,
            configOverrides: CliConfigOverrides = CliConfigOverrides()
        ) {
            self.sessionID = sessionID
            self.last = last
            self.all = all
            self.configOverrides = configOverrides
        }
    }

    public struct ForkCommandRequest: Equatable, Sendable {
        public let sessionID: String?
        public let last: Bool
        public let all: Bool
        public let remote: String?
        public let remoteAuthTokenEnv: String?
        public let configOverrides: CliConfigOverrides

        public init(
            sessionID: String?,
            last: Bool,
            all: Bool,
            remote: String? = nil,
            remoteAuthTokenEnv: String? = nil,
            configOverrides: CliConfigOverrides = CliConfigOverrides()
        ) {
            self.sessionID = sessionID
            self.last = last
            self.all = all
            self.remote = remote
            self.remoteAuthTokenEnv = remoteAuthTokenEnv
            self.configOverrides = configOverrides
        }
    }

    public enum ExecServerCommandAction: Equatable, Sendable {
        case listen(url: String)
        case remote(baseURL: String, executorID: String, name: String?)
    }

    public struct ExecServerCommandRequest: Equatable, Sendable {
        public let action: ExecServerCommandAction

        public init(action: ExecServerCommandAction) {
            self.action = action
        }
    }

    public struct McpServerCommandRequest: Equatable, Sendable {
        public let configOverrides: CliConfigOverrides

        public init(configOverrides: CliConfigOverrides = CliConfigOverrides()) {
            self.configOverrides = configOverrides
        }
    }

    public enum AppServerCommandAction: Equatable, Sendable {
        case run
        case remoteControl
        case proxy(socketPath: String?)
        case generateTS(outDir: String, prettier: String?, experimental: Bool)
        case generateJSONSchema(outDir: String, experimental: Bool)
        case generateInternalJSONSchema(outDir: String)
    }

    public struct AppServerCommandRequest: Equatable, Sendable {
        public let action: AppServerCommandAction
        public let configOverrides: CliConfigOverrides

        public init(
            action: AppServerCommandAction,
            configOverrides: CliConfigOverrides = CliConfigOverrides()
        ) {
            self.action = action
            self.configOverrides = configOverrides
        }
    }

    public struct AppCommandRequest: Equatable, Sendable {
        public let path: String
        public let downloadURLOverride: String?

        public init(path: String = ".", downloadURLOverride: String? = nil) {
            self.path = path
            self.downloadURLOverride = downloadURLOverride
        }
    }

    public struct SandboxProfileOptions: Equatable, Sendable {
        public let permissionsProfile: String?
        public let cwd: String?
        public let includeManagedConfig: Bool

        public init(
            permissionsProfile: String? = nil,
            cwd: String? = nil,
            includeManagedConfig: Bool = false
        ) {
            self.permissionsProfile = permissionsProfile
            self.cwd = cwd
            self.includeManagedConfig = includeManagedConfig
        }

        public enum Resolution: Equatable, Sendable {
            case resolved(SandboxPolicy)
            case customProfile(String)
            case unknownBuiltinProfile(String)
        }

        public func resolveBuiltInPolicy(defaultPolicy: SandboxPolicy) -> Resolution {
            guard let permissionsProfile else {
                return .resolved(defaultPolicy)
            }

            switch permissionsProfile {
            case ":read-only":
                return .resolved(.readOnly)
            case ":workspace":
                if case .workspaceWrite = defaultPolicy {
                    return .resolved(defaultPolicy)
                }
                return .resolved(.newWorkspaceWritePolicy())
            case ":danger-no-sandbox":
                return .resolved(.dangerFullAccess)
            default:
                if permissionsProfile.hasPrefix(":") {
                    return .unknownBuiltinProfile(permissionsProfile)
                }
                return .customProfile(permissionsProfile)
            }
        }
    }

    public enum SandboxCommandAction: Equatable, Sendable {
        case macos(profile: SandboxProfileOptions, allowUnixSockets: [String], logDenials: Bool, command: [String])
        case linux(profile: SandboxProfileOptions, command: [String])
        case windows(profile: SandboxProfileOptions, command: [String])
    }

    public struct SandboxCommandRequest: Equatable, Sendable {
        public let action: SandboxCommandAction
        public let configOverrides: CliConfigOverrides

        public init(action: SandboxCommandAction, configOverrides: CliConfigOverrides = CliConfigOverrides()) {
            self.action = action
            self.configOverrides = configOverrides
        }
    }

    public enum DebugCommandAction: Equatable, Sendable {
        case models(bundled: Bool)
        case appServerSendMessageV2(message: String)
        case promptInput(prompt: String?, imagePaths: [String])
        case traceReduce(traceBundle: String, output: String?)
        case clearMemories
    }

    public struct DebugCommandRequest: Equatable, Sendable {
        public let action: DebugCommandAction
        public let configOverrides: CliConfigOverrides

        public init(action: DebugCommandAction, configOverrides: CliConfigOverrides = CliConfigOverrides()) {
            self.action = action
            self.configOverrides = configOverrides
        }
    }

    public enum McpCommandAction: Equatable, Sendable {
        case list(json: Bool)
        case get(name: String, json: Bool)
        case add(name: String, transport: McpAddTransport)
        case remove(name: String)
        case login(name: String, scopes: [String])
        case logout(name: String)
    }

    public enum McpAddTransport: Equatable, Sendable {
        case stdio(command: [String], env: [McpEnvPair])
        case streamableHttp(url: String, bearerTokenEnvVar: String?)
    }

    public struct McpEnvPair: Equatable, Sendable {
        public let key: String
        public let value: String

        public init(key: String, value: String) {
            self.key = key
            self.value = value
        }
    }

    public struct McpCommandRequest: Equatable, Sendable {
        public let action: McpCommandAction
        public let configOverrides: CliConfigOverrides

        public init(action: McpCommandAction, configOverrides: CliConfigOverrides = CliConfigOverrides()) {
            self.action = action
            self.configOverrides = configOverrides
        }
    }

    public struct StdioToUDSCommandRequest: Equatable, Sendable {
        public let socketPath: String

        public init(socketPath: String) {
            self.socketPath = socketPath
        }
    }

    public enum PluginCommandAction: Equatable, Sendable {
        case marketplaceAdd(source: String, refName: String?, sparsePaths: [String])
        case marketplaceUpgrade(name: String?)
        case marketplaceRemove(name: String)
    }

    public struct PluginCommandRequest: Equatable, Sendable {
        public let action: PluginCommandAction
        public let configOverrides: CliConfigOverrides

        public init(action: PluginCommandAction, configOverrides: CliConfigOverrides = CliConfigOverrides()) {
            self.action = action
            self.configOverrides = configOverrides
        }
    }

    public enum CloudCommandAction: Equatable, Sendable {
        case status(taskID: String)
        case list(environment: String?, limit: Int, cursor: String?, json: Bool)
        case diff(taskID: String, attempt: Int?)
        case apply(taskID: String, attempt: Int?)
        case exec(query: String?, environment: String, branch: String?, attempts: Int)
    }

    public struct CloudCommandRequest: Equatable, Sendable {
        public let action: CloudCommandAction
        public let configOverrides: CliConfigOverrides

        public init(action: CloudCommandAction, configOverrides: CliConfigOverrides = CliConfigOverrides()) {
            self.action = action
            self.configOverrides = configOverrides
        }
    }

    public struct ResponsesAPIProxyCommandRequest: Equatable, Sendable {
        public let port: UInt16?
        public let serverInfoPath: String?
        public let httpShutdown: Bool
        public let upstreamURL: String
        public let dumpDir: String?

        public init(
            port: UInt16? = nil,
            serverInfoPath: String? = nil,
            httpShutdown: Bool = false,
            upstreamURL: String = "https://api.openai.com/v1/responses",
            dumpDir: String? = nil
        ) {
            self.port = port
            self.serverInfoPath = serverInfoPath
            self.httpShutdown = httpShutdown
            self.upstreamURL = upstreamURL
            self.dumpDir = dumpDir
        }
    }

    public struct UpdateCommandRequest: Equatable, Sendable {
        public init() {}
    }

    public struct CommandExecutionResult: Equatable, Sendable {
        public let exitCode: Int32
        public let stdoutMessage: String?
        public let stderrMessage: String?

        public init(exitCode: Int32, stdoutMessage: String? = nil, stderrMessage: String? = nil) {
            self.exitCode = exitCode
            self.stdoutMessage = stdoutMessage
            self.stderrMessage = stderrMessage
        }
    }

    public typealias ApplyCommandRunner = (ApplyCommandRequest) async throws -> String?
    public typealias LoginCommandRunner = (LoginCommandRequest) async throws -> CommandExecutionResult
    public typealias LogoutCommandRunner = (LogoutCommandRequest) async throws -> CommandExecutionResult
    public typealias FeaturesCommandRunner = (FeaturesCommandRequest) async throws -> CommandExecutionResult
    public typealias ExecCommandRunner = (ExecCommandRequest) async throws -> CommandExecutionResult
    public typealias ComputerUseCommandRunner = (ComputerUseCommandRequest) async throws -> CommandExecutionResult
    public typealias ReviewCommandRunner = (ReviewCommandRequest) async throws -> CommandExecutionResult
    public typealias ResumeCommandRunner = (ResumeCommandRequest) async throws -> CommandExecutionResult
    public typealias ForkCommandRunner = (ForkCommandRequest) async throws -> CommandExecutionResult
    public typealias ExecServerCommandRunner = (ExecServerCommandRequest) async throws -> CommandExecutionResult
    public typealias McpServerCommandRunner = (McpServerCommandRequest) async throws -> CommandExecutionResult
    public typealias AppServerCommandRunner = (AppServerCommandRequest) async throws -> CommandExecutionResult
    public typealias AppCommandRunner = (AppCommandRequest) async throws -> CommandExecutionResult
    public typealias ExecPolicyCommandRunner = (ExecPolicyCommandRequest) async throws -> CommandExecutionResult
    public typealias SandboxCommandRunner = (SandboxCommandRequest) async throws -> CommandExecutionResult
    public typealias DebugCommandRunner = (DebugCommandRequest) async throws -> CommandExecutionResult
    public typealias McpCommandRunner = (McpCommandRequest) async throws -> CommandExecutionResult
    public typealias StdioToUDSCommandRunner = (StdioToUDSCommandRequest) async throws -> CommandExecutionResult
    public typealias PluginCommandRunner = (PluginCommandRequest) async throws -> CommandExecutionResult
    public typealias CloudCommandRunner = (CloudCommandRequest) async throws -> CommandExecutionResult
    public typealias ResponsesAPIProxyCommandRunner = (ResponsesAPIProxyCommandRequest) async throws -> CommandExecutionResult
    public typealias UpdateCommandRunner = (UpdateCommandRequest) async throws -> CommandExecutionResult

    public func parseInvocation(arguments: [String]) -> Invocation {
        if arguments.contains("--version") || arguments.contains("-V") {
            return .version
        }
        if arguments.contains("--help") || arguments.contains("-h") {
            return .help
        }

        let positionals = positionalTokens(arguments)
        if let commandToken = positionals.first, let spec = CodexCommandRegistry.command(matching: commandToken) {
            return .command(spec, arguments: Array(positionals.dropFirst()))
        }

        if let first = positionals.first {
            return .interactive(prompt: first)
        }
        if arguments.contains(where: { $0.hasPrefix("-") }) {
            return .interactive(prompt: nil)
        }
        return .interactive(prompt: nil)
    }

    public func command(for arguments: [String]) -> CommandSpec? {
        if case let .command(spec, _) = parseInvocation(arguments: arguments) {
            return spec
        }
        return nil
    }

    public func renderHelp(includeHidden: Bool = false) -> String {
        let visibleCommands = CodexCommandRegistry.commands.filter { includeHidden || !$0.isHidden }
        let commandLines = visibleCommands
            .map { spec -> String in
                let aliasText = spec.aliases.isEmpty ? "" : " [alias: \(spec.aliases.joined(separator: ", "))]"
                return "  \(spec.name)\(aliasText)\n      \(spec.summary)"
            }
            .joined(separator: "\n")

        return """
        Codex CLI

        Usage:
          codex [OPTIONS] [PROMPT]
          codex [OPTIONS] <COMMAND> [ARGS]

        Options:
          -m, --model <MODEL>                Model the agent should use.
          --oss                             Select the local open source model provider.
          --local-provider <PROVIDER>       Specify lmstudio or ollama.
          -p, --profile <PROFILE>           Configuration profile from config.toml.
          -s, --sandbox <MODE>              Sandbox policy for model-generated shell commands.
          -a, --ask-for-approval <POLICY>   Configure command approval policy.
          --dangerously-bypass-approvals-and-sandbox
                                            Skip confirmations and sandboxing.
          -C, --cd <DIR>                    Working root for the session.
          --search                          Enable web search.
          --add-dir <DIR>                   Additional writable directory.
          -i, --image <FILE>                Attach image(s) to the initial prompt.
          --ephemeral                       Run without persisting session files.
          --ignore-user-config              Do not load $CODEX_HOME/config.toml.
          --ignore-rules                    Do not load user or project rules files.
          -h, --help                        Print help.
          -V, --version                     Print version.

        Commands:
        \(commandLines)
        """
    }

    public func renderVersion() -> String {
        "codex \(Self.version)"
    }

    public func run(arguments: [String], stdout: (String) -> Void = { print($0) }, stderr: (String) -> Void = { fputs($0 + "\n", Darwin.stderr) }) -> Int32 {
        switch parseInvocation(arguments: arguments) {
        case .version:
            stdout(renderVersion())
            return 0
        case .help:
            stdout(renderHelp())
            return 0
        case let .command(spec, commandArguments) where spec.name == "completion":
            do {
                stdout(try CompletionGenerator.render(arguments: commandArguments))
                return 0
            } catch {
                stderr(describe(error))
                return 64
            }
        case let .command(spec, _):
            stderr("codex-swift: command '\(spec.name)' is registered but its runtime port is not complete yet.")
            return 78
        case .interactive:
            stderr("codex-swift: interactive TUI runtime is not complete yet.")
            return 78
        case let .unknown(argument):
            stderr("codex-swift: unknown command or unsupported argument: \(argument)")
            return 64
        }
    }

    public func runAsync(
        arguments: [String],
        stdout: (String) -> Void = { print($0) },
        stderr: (String) -> Void = { fputs($0 + "\n", Darwin.stderr) },
        applyRunner: ApplyCommandRunner? = nil,
        loginRunner: LoginCommandRunner? = nil,
        logoutRunner: LogoutCommandRunner? = nil,
        featuresRunner: FeaturesCommandRunner? = nil,
        execRunner: ExecCommandRunner? = nil,
        computerUseRunner: ComputerUseCommandRunner? = nil,
        reviewRunner: ReviewCommandRunner? = nil,
        resumeRunner: ResumeCommandRunner? = nil,
        forkRunner: ForkCommandRunner? = nil,
        execServerRunner: ExecServerCommandRunner? = nil,
        mcpServerRunner: McpServerCommandRunner? = nil,
        appServerRunner: AppServerCommandRunner? = nil,
        appRunner: AppCommandRunner? = nil,
        execPolicyRunner: ExecPolicyCommandRunner? = nil,
        sandboxRunner: SandboxCommandRunner? = nil,
        debugRunner: DebugCommandRunner? = nil,
        mcpRunner: McpCommandRunner? = nil,
        stdioToUDSRunner: StdioToUDSCommandRunner? = nil,
        pluginRunner: PluginCommandRunner? = nil,
        cloudRunner: CloudCommandRunner? = nil,
        responsesAPIProxyRunner: ResponsesAPIProxyCommandRunner? = nil,
        updateRunner: UpdateCommandRunner? = nil
    ) async -> Int32 {
        let invocation = parseInvocation(arguments: arguments)
        if let message = rootRemovedFullAutoRejectionMessage(invocation: invocation, arguments: arguments) {
            stderr(message)
            return 64
        }
        if case let .command(spec, commandArguments) = invocation,
           let message = rootRemoteModeRejectionMessage(
               spec: spec,
               commandArguments: commandArguments,
               arguments: arguments
           ) {
            stderr(message)
            return 1
        }

        switch invocation {
        case .version:
            stdout(renderVersion())
            return 0
        case .help:
            stdout(renderHelp())
            return 0
        case let .command(spec, commandArguments) where spec.name == "completion":
            do {
                stdout(try CompletionGenerator.render(arguments: commandArguments))
                return 0
            } catch {
                stderr(describe(error))
                return 64
            }
        case let .command(spec, commandArguments) where spec.name == "apply":
            guard let applyRunner else {
                stderr("codex-swift: command '\(spec.name)' is registered but its runtime port is not complete yet.")
                return 78
            }
            guard commandArguments.count == 1, let taskID = commandArguments.first else {
                stderr("codex-swift: missing required argument for command 'apply': <TASK_ID>")
                return 64
            }
            do {
                if let message = try await applyRunner(ApplyCommandRequest(
                    taskID: taskID,
                    configOverrides: CliConfigOverrides(rawOverrides: try configOverrideTokens(arguments))
                )) {
                    stdout(message)
                }
                return 0
            } catch {
                stderr(describe(error))
                return 1
            }
        case let .command(spec, commandArguments) where spec.name == "login":
            if usesDeprecatedAPIKeyFlag(arguments) {
                stderr("The --api-key flag is no longer supported. Pipe the key instead, e.g. `printenv OPENAI_API_KEY | codex login --with-api-key`.")
                return 1
            }
            guard let loginRunner else {
                stderr("codex-swift: command '\(spec.name)' is registered but its runtime port is not complete yet.")
                return 78
            }
            do {
                let result = try await loginRunner(LoginCommandRequest(
                    action: loginAction(arguments: arguments, commandArguments: commandArguments),
                    configOverrides: CliConfigOverrides(rawOverrides: try configOverrideTokens(arguments))
                ))
                emit(result, stdout: stdout, stderr: stderr)
                return result.exitCode
            } catch {
                stderr(describe(error))
                return 1
            }
        case let .command(spec, _) where spec.name == "logout":
            guard let logoutRunner else {
                stderr("codex-swift: command '\(spec.name)' is registered but its runtime port is not complete yet.")
                return 78
            }
            do {
                let result = try await logoutRunner(LogoutCommandRequest(
                    configOverrides: CliConfigOverrides(rawOverrides: try configOverrideTokens(arguments))
                ))
                emit(result, stdout: stdout, stderr: stderr)
                return result.exitCode
            } catch {
                stderr(describe(error))
                return 1
            }
        case let .command(spec, _) where spec.name == "exec":
            guard let execRunner else {
                stderr("codex-swift: command '\(spec.name)' is registered but its runtime port is not complete yet.")
                return 78
            }
            let rawArguments = rawCommandArguments(after: spec, in: arguments)
            switch parseExecCommand(rawArguments, rootArguments: arguments) {
            case let .success(request):
                do {
                    if let warning = request.options.removedFullAutoWarning {
                        stderr(warning)
                    }
                    let result = try await execRunner(request)
                    emit(result, stdout: stdout, stderr: stderr)
                    return result.exitCode
                } catch {
                    stderr(describe(error))
                    return 1
                }
            case let .failure(message, exitCode):
                stderr(message)
                return exitCode
            }
        case let .command(spec, _) where spec.name == "computer-use":
            guard let computerUseRunner else {
                stderr("codex-swift: command '\(spec.name)' is registered but its runtime port is not complete yet.")
                return 78
            }
            let rawArguments = rawCommandArguments(after: spec, in: arguments)
            switch parseComputerUseCommand(rawArguments, rootArguments: arguments) {
            case let .success(request):
                do {
                    let result = try await computerUseRunner(request)
                    emit(result, stdout: stdout, stderr: stderr)
                    return result.exitCode
                } catch {
                    stderr(describe(error))
                    return 1
                }
            case let .failure(message, exitCode):
                stderr(message)
                return exitCode
            }
        case let .command(spec, _) where spec.name == "review":
            guard let reviewRunner else {
                stderr("codex-swift: command '\(spec.name)' is registered but its runtime port is not complete yet.")
                return 78
            }
            let rawArguments = rawCommandArguments(after: spec, in: arguments)
            switch parseReviewCommand(rawArguments, rootArguments: arguments) {
            case let .success(request):
                do {
                    let result = try await reviewRunner(request)
                    emit(result, stdout: stdout, stderr: stderr)
                    return result.exitCode
                } catch {
                    stderr(describe(error))
                    return 1
                }
            case let .failure(message, exitCode):
                stderr(message)
                return exitCode
            }
        case let .command(spec, _) where spec.name == "resume":
            guard let resumeRunner else {
                stderr("codex-swift: command '\(spec.name)' is registered but its runtime port is not complete yet.")
                return 78
            }
            let rawArguments = rawCommandArguments(after: spec, in: arguments)
            switch parseResumeCommand(rawArguments, rootArguments: arguments) {
            case let .success(request):
                do {
                    let result = try await resumeRunner(request)
                    emit(result, stdout: stdout, stderr: stderr)
                    return result.exitCode
                } catch {
                    stderr(describe(error))
                    return 1
                }
            case let .failure(message, exitCode):
                stderr(message)
                return exitCode
            }
        case let .command(spec, _) where spec.name == "fork":
            guard let forkRunner else {
                stderr("codex-swift: command '\(spec.name)' is registered but its runtime port is not complete yet.")
                return 78
            }
            let rawArguments = rawCommandArguments(after: spec, in: arguments)
            switch parseForkCommand(rawArguments, rootArguments: arguments) {
            case let .success(request):
                do {
                    let result = try await forkRunner(request)
                    emit(result, stdout: stdout, stderr: stderr)
                    return result.exitCode
                } catch {
                    stderr(describe(error))
                    return 1
                }
            case let .failure(message, exitCode):
                stderr(message)
                return exitCode
            }
        case let .command(spec, _) where spec.name == "exec-server":
            guard let execServerRunner else {
                stderr("codex-swift: command '\(spec.name)' is registered but its runtime port is not complete yet.")
                return 78
            }
            let rawArguments = rawCommandArguments(after: spec, in: arguments)
            switch parseExecServerCommand(rawArguments, rootArguments: arguments) {
            case let .success(request):
                do {
                    let result = try await execServerRunner(request)
                    emit(result, stdout: stdout, stderr: stderr)
                    return result.exitCode
                } catch {
                    stderr(describe(error))
                    return 1
                }
            case let .failure(message, exitCode):
                stderr(message)
                return exitCode
            }
        case let .command(spec, _) where spec.name == "mcp-server":
            guard let mcpServerRunner else {
                stderr("codex-swift: command '\(spec.name)' is registered but its runtime port is not complete yet.")
                return 78
            }
            let rawArguments = rawCommandArguments(after: spec, in: arguments)
            switch parseMcpServerCommand(rawArguments, rootArguments: arguments) {
            case let .success(request):
                do {
                    let result = try await mcpServerRunner(request)
                    emit(result, stdout: stdout, stderr: stderr)
                    return result.exitCode
                } catch {
                    stderr(describe(error))
                    return 1
                }
            case let .failure(message, exitCode):
                stderr(message)
                return exitCode
            }
        case let .command(spec, _) where spec.name == "app-server":
            guard let appServerRunner else {
                stderr("codex-swift: command '\(spec.name)' is registered but its runtime port is not complete yet.")
                return 78
            }
            let rawArguments = rawCommandArguments(after: spec, in: arguments)
            switch parseAppServerCommand(rawArguments, rootArguments: arguments) {
            case let .success(request):
                do {
                    let result = try await appServerRunner(request)
                    emit(result, stdout: stdout, stderr: stderr)
                    return result.exitCode
                } catch {
                    stderr(describe(error))
                    return 1
                }
            case let .failure(message, exitCode):
                stderr(message)
                return exitCode
            }
        case let .command(spec, _) where spec.name == "remote-control":
            guard let appServerRunner else {
                stderr("codex-swift: command '\(spec.name)' is registered but its runtime port is not complete yet.")
                return 78
            }
            let rawArguments = rawCommandArguments(after: spec, in: arguments)
            switch parseRemoteControlCommand(rawArguments, rootArguments: arguments) {
            case let .success(request):
                do {
                    let result = try await appServerRunner(request)
                    emit(result, stdout: stdout, stderr: stderr)
                    return result.exitCode
                } catch {
                    stderr(describe(error))
                    return 1
                }
            case let .failure(message, exitCode):
                stderr(message)
                return exitCode
            }
        case let .command(spec, _) where spec.name == "app":
            guard let appRunner else {
                stderr("codex-swift: command '\(spec.name)' is registered but its runtime port is not complete yet.")
                return 78
            }
            let rawArguments = rawCommandArguments(after: spec, in: arguments)
            switch parseAppCommand(rawArguments) {
            case let .success(request):
                do {
                    let result = try await appRunner(request)
                    emit(result, stdout: stdout, stderr: stderr)
                    return result.exitCode
                } catch {
                    stderr(describe(error))
                    return 1
                }
            case let .failure(message, exitCode):
                stderr(message)
                return exitCode
            }
        case let .command(spec, _) where spec.name == "execpolicy":
            guard let execPolicyRunner else {
                stderr("codex-swift: command '\(spec.name)' is registered but its runtime port is not complete yet.")
                return 78
            }
            let rawArguments = rawCommandArguments(after: spec, in: arguments)
            switch parseExecPolicyCommandAction(rawArguments) {
            case let .success(action):
                do {
                    let result = try await execPolicyRunner(ExecPolicyCommandRequest(action: action))
                    emit(result, stdout: stdout, stderr: stderr)
                    return result.exitCode
                } catch {
                    stderr(describe(error))
                    return 1
                }
            case let .failure(message, exitCode):
                stderr(message)
                return exitCode
            }
        case let .command(spec, _) where spec.name == "sandbox":
            guard let sandboxRunner else {
                stderr("codex-swift: command '\(spec.name)' is registered but its runtime port is not complete yet.")
                return 78
            }
            let rawArguments = rawCommandArguments(after: spec, in: arguments)
            switch parseSandboxCommandAction(rawArguments) {
            case let .success(action):
                do {
                    let result = try await sandboxRunner(SandboxCommandRequest(
                        action: action,
                        configOverrides: CliConfigOverrides(rawOverrides: try configOverrideTokens(arguments))
                    ))
                    emit(result, stdout: stdout, stderr: stderr)
                    return result.exitCode
                } catch {
                    stderr(describe(error))
                    return 1
                }
            case let .failure(message, exitCode):
                stderr(message)
                return exitCode
            }
        case let .command(spec, _) where spec.name == "debug":
            guard let debugRunner else {
                stderr("codex-swift: command '\(spec.name)' is registered but its runtime port is not complete yet.")
                return 78
            }
            let rawArguments = rawCommandArguments(after: spec, in: arguments)
            switch parseDebugCommandAction(rawArguments) {
            case let .success(action):
                let mergedAction = debugAction(
                    action,
                    prependingRootImagePaths: rootImagePaths(before: spec, in: arguments)
                )
                do {
                    let result = try await debugRunner(DebugCommandRequest(
                        action: mergedAction,
                        configOverrides: CliConfigOverrides(rawOverrides: try configOverrideTokens(arguments))
                    ))
                    emit(result, stdout: stdout, stderr: stderr)
                    return result.exitCode
                } catch {
                    stderr(describe(error))
                    return 1
                }
            case let .failure(message, exitCode):
                stderr(message)
                return exitCode
            }
        case let .command(spec, _) where spec.name == "mcp":
            guard let mcpRunner else {
                stderr("codex-swift: command '\(spec.name)' is registered but its runtime port is not complete yet.")
                return 78
            }
            let rawArguments = rawCommandArguments(after: spec, in: arguments)
            switch parseMcpCommandAction(rawArguments) {
            case let .success(action):
                do {
                    let result = try await mcpRunner(McpCommandRequest(
                        action: action,
                        configOverrides: CliConfigOverrides(rawOverrides: try configOverrideTokens(arguments))
                    ))
                    emit(result, stdout: stdout, stderr: stderr)
                    return result.exitCode
                } catch {
                    stderr(describe(error))
                    return 1
                }
            case let .failure(message, exitCode):
                stderr(message)
                return exitCode
            }
        case let .command(spec, _) where spec.name == "plugin":
            guard let pluginRunner else {
                stderr("codex-swift: command '\(spec.name)' is registered but its runtime port is not complete yet.")
                return 78
            }
            let rawArguments = rawCommandArguments(after: spec, in: arguments)
            switch parsePluginCommandAction(rawArguments) {
            case let .success(action):
                do {
                    let result = try await pluginRunner(PluginCommandRequest(
                        action: action,
                        configOverrides: CliConfigOverrides(rawOverrides: try configOverrideTokens(arguments))
                    ))
                    emit(result, stdout: stdout, stderr: stderr)
                    return result.exitCode
                } catch {
                    stderr(describe(error))
                    return 1
                }
            case let .failure(message, exitCode):
                stderr(message)
                return exitCode
            }
        case let .command(spec, commandArguments) where spec.name == "stdio-to-uds":
            guard let stdioToUDSRunner else {
                stderr("codex-swift: command '\(spec.name)' is registered but its runtime port is not complete yet.")
                return 78
            }
            guard commandArguments.count == 1, let socketPath = commandArguments.first else {
                stderr("codex-swift: missing required argument for command 'stdio-to-uds': <SOCKET_PATH>")
                return 64
            }
            do {
                let result = try await stdioToUDSRunner(StdioToUDSCommandRequest(socketPath: socketPath))
                emit(result, stdout: stdout, stderr: stderr)
                return result.exitCode
            } catch {
                stderr(describe(error))
                return 1
            }
        case let .command(spec, _) where spec.name == "cloud":
            guard let cloudRunner else {
                stderr("codex-swift: command '\(spec.name)' is registered but its runtime port is not complete yet.")
                return 78
            }
            let rawArguments = rawCommandArguments(after: spec, in: arguments)
            guard !rawArguments.isEmpty else {
                stderr("codex-swift: command 'cloud' TUI runtime is not complete yet.")
                return 78
            }
            switch parseCloudCommandAction(rawArguments) {
            case let .success(action):
                do {
                    let result = try await cloudRunner(CloudCommandRequest(
                        action: action,
                        configOverrides: CliConfigOverrides(rawOverrides: try configOverrideTokens(arguments))
                    ))
                    emit(result, stdout: stdout, stderr: stderr)
                    return result.exitCode
                } catch {
                    stderr(describe(error))
                    return 1
                }
            case let .failure(message, exitCode):
                stderr(message)
                return exitCode
            }
        case let .command(spec, _) where spec.name == "responses-api-proxy":
            guard let responsesAPIProxyRunner else {
                stderr("codex-swift: command '\(spec.name)' is registered but its runtime port is not complete yet.")
                return 78
            }
            let rawArguments = rawCommandArguments(after: spec, in: arguments)
            switch parseResponsesAPIProxyCommand(rawArguments) {
            case let .success(request):
                do {
                    let result = try await responsesAPIProxyRunner(request)
                    emit(result, stdout: stdout, stderr: stderr)
                    return result.exitCode
                } catch {
                    stderr(describe(error))
                    return 1
                }
            case let .failure(message, exitCode):
                stderr(message)
                return exitCode
            }
        case let .command(spec, commandArguments) where spec.name == "update":
            guard let updateRunner else {
                stderr("codex-swift: command '\(spec.name)' is registered but its runtime port is not complete yet.")
                return 78
            }
            guard commandArguments.isEmpty else {
                stderr("codex-swift: unexpected argument for command 'update': \(commandArguments[0])")
                return 64
            }
            do {
                let result = try await updateRunner(UpdateCommandRequest())
                emit(result, stdout: stdout, stderr: stderr)
                return result.exitCode
            } catch {
                stderr(describe(error))
                return 1
            }
        case let .command(spec, commandArguments) where spec.name == "features":
            guard let featuresRunner else {
                stderr("codex-swift: command '\(spec.name)' is registered but its runtime port is not complete yet.")
                return 78
            }
            guard let action = parseFeaturesCommandAction(commandArguments) else {
                stderr("codex-swift: missing required subcommand for command 'features': list, enable, or disable")
                return 64
            }
            do {
                let result = try await featuresRunner(FeaturesCommandRequest(
                    action: action,
                    configProfile: configProfileToken(arguments),
                    configOverrides: CliConfigOverrides(rawOverrides: try configOverrideTokens(arguments))
                ))
                emit(result, stdout: stdout, stderr: stderr)
                return result.exitCode
            } catch {
                stderr(describe(error))
                return 1
            }
        case let .command(spec, _):
            stderr("codex-swift: command '\(spec.name)' is registered but its runtime port is not complete yet.")
            return 78
        case .interactive:
            stderr("codex-swift: interactive TUI runtime is not complete yet.")
            return 78
        case let .unknown(argument):
            stderr("codex-swift: unknown command or unsupported argument: \(argument)")
            return 64
        }
    }

    private func positionalTokens(_ arguments: [String]) -> [String] {
        var positionals: [String] = []
        var iterator = arguments.makeIterator()

        while let argument = iterator.next() {
            if argument == "--" {
                positionals.append(contentsOf: iterator.map { $0 })
                break
            }

            if optionConsumesValue(argument) {
                _ = iterator.next()
                continue
            }

            if argument.hasPrefix("-") {
                continue
            }

            positionals.append(argument)
        }

        return positionals
    }

    private func optionConsumesValue(_ argument: String) -> Bool {
        if argument.contains("=") {
            return false
        }
        return [
            "-m",
            "--model",
            "--local-provider",
            "-p",
            "--profile",
            "-s",
            "--sandbox",
            "-a",
            "--ask-for-approval",
            "-C",
            "--cd",
            "--add-dir",
            "-i",
            "--image",
            "-c",
            "--config",
            "--enable",
            "--disable",
            "--attempt",
            "--attempts",
            "--env",
            "--branch",
            "--base",
            "--commit",
            "--title",
            "--out",
            "-o",
            "--prettier",
            "--remote",
            "--remote-auth-token-env",
            "--output-schema",
            "--output-last-message",
            "--color",
            "--url",
            "--bearer-token-env-var",
            "--scopes",
            "--rules",
            "-r",
            "--ref",
            "--sparse",
            "--listen",
            "--executor-id",
            "--name"
        ].contains(argument)
    }

    private func rawCommandArguments(after spec: CommandSpec, in arguments: [String]) -> [String] {
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            if argument == "--" {
                index += 1
                continue
            }
            if optionConsumesValue(argument) {
                index += 2
                continue
            }
            if argument.hasPrefix("-") {
                index += 1
                continue
            }
            if spec.matches(argument) {
                return Array(arguments.dropFirst(index + 1))
            }
            index += 1
        }
        return []
    }

    private func rootImagePaths(before spec: CommandSpec, in arguments: [String]) -> [String] {
        var imagePaths: [String] = []
        var index = 0

        while index < arguments.count {
            let argument = arguments[index]
            if argument == "--" {
                break
            }
            if spec.matches(argument) {
                return imagePaths
            }
            if argument == "--image" || argument == "-i" {
                if index + 1 < arguments.count {
                    imagePaths.append(contentsOf: splitCommaDelimited(arguments[index + 1]))
                }
                index += 2
                continue
            }
            if argument.hasPrefix("--image=") {
                imagePaths.append(contentsOf: splitCommaDelimited(String(argument.dropFirst("--image=".count))))
                index += 1
                continue
            }
            if argument.hasPrefix("-i"), argument.count > 2, !argument.hasPrefix("--") {
                imagePaths.append(contentsOf: splitCommaDelimited(String(argument.dropFirst(2))))
                index += 1
                continue
            }
            if optionConsumesValue(argument) {
                index += 2
            } else {
                index += 1
            }
        }

        return imagePaths
    }

    private func debugAction(
        _ action: DebugCommandAction,
        prependingRootImagePaths rootImagePaths: [String]
    ) -> DebugCommandAction {
        guard !rootImagePaths.isEmpty else {
            return action
        }
        switch action {
        case let .promptInput(prompt, imagePaths):
            return .promptInput(prompt: prompt, imagePaths: rootImagePaths + imagePaths)
        case .models, .appServerSendMessageV2, .traceReduce, .clearMemories:
            return action
        }
    }

    private func configOverrideTokens(_ arguments: [String]) throws -> [String] {
        var overrides: [String] = []
        var featureToggles = FeatureToggles()
        var searchEnabled = false
        var iterator = arguments.makeIterator()

        while let argument = iterator.next() {
            if argument == "-c" || argument == "--config" {
                if let value = iterator.next() {
                    overrides.append(value)
                }
                continue
            }
            if argument.hasPrefix("-c=") {
                overrides.append(String(argument.dropFirst(3)))
                continue
            }
            if argument.hasPrefix("--config=") {
                overrides.append(String(argument.dropFirst("--config=".count)))
                continue
            }
            if argument == "--enable" {
                if let value = iterator.next() {
                    featureToggles.enable.append(value)
                }
                continue
            }
            if argument.hasPrefix("--enable=") {
                featureToggles.enable.append(String(argument.dropFirst("--enable=".count)))
                continue
            }
            if argument == "--disable" {
                if let value = iterator.next() {
                    featureToggles.disable.append(value)
                }
                continue
            }
            if argument.hasPrefix("--disable=") {
                featureToggles.disable.append(String(argument.dropFirst("--disable=".count)))
                continue
            }
            if argument == "--search" {
                searchEnabled = true
                continue
            }
        }

        if let profile = configProfileToken(arguments) {
            overrides.append("profile=\(tomlString(profile))")
        }
        overrides.append(contentsOf: try featureToggles.toOverrides())
        if searchEnabled {
            overrides.append(#"web_search="live""#)
        }
        return overrides
    }

    private func configProfileToken(_ arguments: [String]) -> String? {
        var iterator = arguments.makeIterator()
        while let argument = iterator.next() {
            if argument == "-p" || argument == "--profile" {
                return iterator.next()
            }
            if argument.hasPrefix("--profile=") {
                return String(argument.dropFirst("--profile=".count))
            }
            if argument.hasPrefix("-p"), argument.count > 2, !argument.hasPrefix("--") {
                return String(argument.dropFirst(2))
            }
        }
        return nil
    }

    private func parseFeaturesCommandAction(_ arguments: [String]) -> FeaturesCommandAction? {
        guard let subcommand = arguments.first else {
            return nil
        }
        switch subcommand {
        case "list":
            return arguments.count == 1 ? .list : nil
        case "enable":
            guard arguments.count == 2 else { return nil }
            return .enable(feature: arguments[1])
        case "disable":
            guard arguments.count == 2 else { return nil }
            return .disable(feature: arguments[1])
        default:
            return nil
        }
    }

    private func tomlString(_ value: String) -> String {
        #""\#(value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))""#
    }

    private func loginAction(arguments: [String], commandArguments: [String]) -> LoginCommandAction {
        if commandArguments.first == "status" {
            return .status
        }
        if arguments.contains("--device-auth") {
            return .deviceCode(
                issuerBaseURL: optionValue(named: "--experimental_issuer", in: arguments),
                clientID: optionValue(named: "--experimental_client-id", in: arguments)
            )
        }
        if arguments.contains("--with-api-key") {
            return .withAPIKeyFromStdin
        }
        return .chatGPT
    }

    private func optionValue(named option: String, in arguments: [String]) -> String? {
        var iterator = arguments.makeIterator()
        while let argument = iterator.next() {
            if argument == option {
                return iterator.next()
            }
            if argument.hasPrefix("\(option)=") {
                return String(argument.dropFirst(option.count + 1))
            }
        }
        return nil
    }

    private func usesDeprecatedAPIKeyFlag(_ arguments: [String]) -> Bool {
        arguments.contains("--api-key") || arguments.contains { $0.hasPrefix("--api-key=") }
    }

    private func parseConfigOverrides(from arguments: [String]) -> ParseResult<CliConfigOverrides> {
        do {
            return .success(CliConfigOverrides(rawOverrides: try configOverrideTokens(arguments)))
        } catch {
            return .failure(describe(error), 1)
        }
    }

    private func parseExecCommand(
        _ arguments: [String],
        rootArguments: [String]
    ) -> ParseResult<ExecCommandRequest> {
        var json = false
        var imagePaths: [String] = []
        var outputSchemaPath: String?
        var lastMessageFile: String?
        var skipGitRepoCheck = false
        var ephemeral = false
        var ignoreUserConfig = false
        var ignoreRules = false
        var removedFullAuto = false
        var dangerouslyBypassApprovalsAndSandbox = rootDangerouslyBypassBeforeExec(in: rootArguments)
        var actionTokens: [String] = []
        var index = 0

        func value(after option: String, at index: Int) -> ParseResult<String> {
            guard index + 1 < arguments.count else {
                return .failure("codex-swift: missing value for \(option)", 64)
            }
            return .success(arguments[index + 1])
        }

        while index < arguments.count {
            let argument = arguments[index]
            if argument == "--" {
                actionTokens = Array(arguments.dropFirst(index + 1))
                break
            }

            switch argument {
            case "--json", "--experimental-json":
                json = true
                index += 1
                continue
            case "--skip-git-repo-check":
                skipGitRepoCheck = true
                index += 1
                continue
            case "--ephemeral":
                ephemeral = true
                index += 1
                continue
            case "--ignore-user-config":
                ignoreUserConfig = true
                index += 1
                continue
            case "--ignore-rules":
                ignoreRules = true
                index += 1
                continue
            case "--full-auto":
                removedFullAuto = true
                index += 1
                continue
            case "--dangerously-bypass-approvals-and-sandbox", "--yolo":
                dangerouslyBypassApprovalsAndSandbox = true
                index += 1
                continue
            case "--output-schema":
                switch value(after: argument, at: index) {
                case let .success(path):
                    outputSchemaPath = path
                    index += 2
                    continue
                case let .failure(message, exitCode):
                    return .failure(message, exitCode)
                }
            case "--output-last-message", "-o":
                switch value(after: argument, at: index) {
                case let .success(path):
                    lastMessageFile = path
                    index += 2
                    continue
                case let .failure(message, exitCode):
                    return .failure(message, exitCode)
                }
            case "--image", "-i":
                switch value(after: argument, at: index) {
                case let .success(paths):
                    imagePaths.append(contentsOf: splitCommaDelimited(paths))
                    index += 2
                    continue
                case let .failure(message, exitCode):
                    return .failure(message, exitCode)
                }
            default:
                break
            }

            if argument.hasPrefix("--output-schema=") {
                outputSchemaPath = String(argument.dropFirst("--output-schema=".count))
                index += 1
                continue
            }
            if argument.hasPrefix("--output-last-message=") {
                lastMessageFile = String(argument.dropFirst("--output-last-message=".count))
                index += 1
                continue
            }
            if argument.hasPrefix("-o"), argument.count > 2, !argument.hasPrefix("--") {
                lastMessageFile = String(argument.dropFirst(2))
                index += 1
                continue
            }
            if argument.hasPrefix("--image=") {
                imagePaths.append(contentsOf: splitCommaDelimited(String(argument.dropFirst("--image=".count))))
                index += 1
                continue
            }
            if argument.hasPrefix("-i"), argument.count > 2, !argument.hasPrefix("--") {
                imagePaths.append(contentsOf: splitCommaDelimited(String(argument.dropFirst(2))))
                index += 1
                continue
            }

            if execOptionConsumesValue(argument) {
                guard index + 1 < arguments.count else {
                    return .failure("codex-swift: missing value for \(argument)", 64)
                }
                index += 2
                continue
            }
            if execFlagWithoutValue(argument) || argument.contains("=") && execAssignmentOption(argument) {
                index += 1
                continue
            }
            if argument.hasPrefix("-") {
                return .failure("codex-swift: unsupported option for command 'exec': \(argument)", 64)
            }

            actionTokens = Array(arguments.dropFirst(index))
            break
        }

        let action: ExecCommandAction
        if actionTokens.first == "review" {
            switch parseReviewCommand(Array(actionTokens.dropFirst()), rootArguments: rootArguments) {
            case let .success(request):
                action = .review(request.target)
            case let .failure(message, exitCode):
                return .failure(message, exitCode)
            }
        } else if actionTokens.first == "resume" {
            switch parseExecResumeCommand(Array(actionTokens.dropFirst()), rootPrompt: nil) {
            case let .success(parsed):
                imagePaths.append(contentsOf: parsed.imagePaths)
                json = json || parsed.json
                lastMessageFile = parsed.lastMessageFile ?? lastMessageFile
                skipGitRepoCheck = skipGitRepoCheck || parsed.skipGitRepoCheck
                ephemeral = ephemeral || parsed.ephemeral
                ignoreUserConfig = ignoreUserConfig || parsed.ignoreUserConfig
                ignoreRules = ignoreRules || parsed.ignoreRules
                removedFullAuto = removedFullAuto || parsed.removedFullAuto
                dangerouslyBypassApprovalsAndSandbox =
                    dangerouslyBypassApprovalsAndSandbox || parsed.dangerouslyBypassApprovalsAndSandbox
                action = .resume(parsed.command)
            case let .failure(message, exitCode):
                return .failure(message, exitCode)
            }
        } else if actionTokens.count >= 2, actionTokens[1] == "resume" {
            switch parseExecResumeCommand(Array(actionTokens.dropFirst(2)), rootPrompt: actionTokens[0]) {
            case let .success(parsed):
                imagePaths.append(contentsOf: parsed.imagePaths)
                json = json || parsed.json
                lastMessageFile = parsed.lastMessageFile ?? lastMessageFile
                skipGitRepoCheck = skipGitRepoCheck || parsed.skipGitRepoCheck
                ephemeral = ephemeral || parsed.ephemeral
                ignoreUserConfig = ignoreUserConfig || parsed.ignoreUserConfig
                ignoreRules = ignoreRules || parsed.ignoreRules
                removedFullAuto = removedFullAuto || parsed.removedFullAuto
                dangerouslyBypassApprovalsAndSandbox =
                    dangerouslyBypassApprovalsAndSandbox || parsed.dangerouslyBypassApprovalsAndSandbox
                action = .resume(parsed.command)
            case let .failure(message, exitCode):
                return .failure(message, exitCode)
            }
        } else {
            switch parseExecRunPrompt(actionTokens) {
            case let .success(prompt):
                action = .run(prompt: prompt)
            case let .failure(message, exitCode):
                return .failure(message, exitCode)
            }
        }

        if removedFullAuto, dangerouslyBypassApprovalsAndSandbox {
            return .failure(
                "codex-swift: argument conflict for command 'exec': --full-auto conflicts with --dangerously-bypass-approvals-and-sandbox",
                64
            )
        }

        switch parseConfigOverrides(from: rootArguments) {
        case let .success(configOverrides):
            return .success(ExecCommandRequest(
                arguments: arguments,
                action: action,
                options: ExecCommandOptions(
                    json: json,
                    imagePaths: imagePaths,
                    outputSchemaPath: outputSchemaPath,
                    lastMessageFile: lastMessageFile,
                    skipGitRepoCheck: skipGitRepoCheck,
                    ephemeral: ephemeral,
                    ignoreUserConfig: ignoreUserConfig,
                    ignoreRules: ignoreRules,
                    removedFullAuto: removedFullAuto
                ),
                configOverrides: configOverrides
            ))
        case let .failure(message, exitCode):
            return .failure(message, exitCode)
        }
    }

    private func parseExecRunPrompt(_ tokens: [String]) -> ParseResult<String?> {
        if tokens.isEmpty {
            return .success(nil)
        }
        guard tokens.count == 1 else {
            return .failure("codex-swift: unexpected argument for command 'exec': \(tokens[1])", 64)
        }
        return .success(tokens[0])
    }

    private struct ParsedExecResume {
        let command: ExecResumeCommand
        let imagePaths: [String]
        let json: Bool
        let lastMessageFile: String?
        let skipGitRepoCheck: Bool
        let ephemeral: Bool
        let ignoreUserConfig: Bool
        let ignoreRules: Bool
        let removedFullAuto: Bool
        let dangerouslyBypassApprovalsAndSandbox: Bool
    }

    private func parseExecResumeCommand(
        _ arguments: [String],
        rootPrompt: String?
    ) -> ParseResult<ParsedExecResume> {
        var last = false
        var all = false
        var imagePaths: [String] = []
        var json = false
        var lastMessageFile: String?
        var skipGitRepoCheck = false
        var ephemeral = false
        var ignoreUserConfig = false
        var ignoreRules = false
        var removedFullAuto = false
        var dangerouslyBypassApprovalsAndSandbox = false
        var positionals: [String] = []
        var index = 0

        func value(after option: String, at index: Int) -> ParseResult<String> {
            guard index + 1 < arguments.count else {
                return .failure("codex-swift: missing value for \(option)", 64)
            }
            return .success(arguments[index + 1])
        }

        while index < arguments.count {
            let argument = arguments[index]
            if argument == "--last" {
                last = true
                index += 1
                continue
            }
            if argument == "--all" {
                all = true
                index += 1
                continue
            }
            if argument == "--json" || argument == "--experimental-json" {
                json = true
                index += 1
                continue
            }
            if argument == "--skip-git-repo-check" {
                skipGitRepoCheck = true
                index += 1
                continue
            }
            if argument == "--ephemeral" {
                ephemeral = true
                index += 1
                continue
            }
            if argument == "--ignore-user-config" {
                ignoreUserConfig = true
                index += 1
                continue
            }
            if argument == "--ignore-rules" {
                ignoreRules = true
                index += 1
                continue
            }
            if argument == "--full-auto" {
                removedFullAuto = true
                index += 1
                continue
            }
            if argument == "--dangerously-bypass-approvals-and-sandbox" || argument == "--yolo" {
                dangerouslyBypassApprovalsAndSandbox = true
                index += 1
                continue
            }
            if argument == "--output-last-message" || argument == "-o" {
                switch value(after: argument, at: index) {
                case let .success(path):
                    lastMessageFile = path
                    index += 2
                    continue
                case let .failure(message, exitCode):
                    return .failure(message, exitCode)
                }
            }
            if argument == "--image" || argument == "-i" {
                switch value(after: argument, at: index) {
                case let .success(paths):
                    imagePaths.append(contentsOf: splitCommaDelimited(paths))
                    index += 2
                    continue
                case let .failure(message, exitCode):
                    return .failure(message, exitCode)
                }
            }
            if argument.hasPrefix("--image=") {
                imagePaths.append(contentsOf: splitCommaDelimited(String(argument.dropFirst("--image=".count))))
                index += 1
                continue
            }
            if argument.hasPrefix("--output-last-message=") {
                lastMessageFile = String(argument.dropFirst("--output-last-message=".count))
                index += 1
                continue
            }
            if argument.hasPrefix("-o"), argument.count > 2, !argument.hasPrefix("--") {
                lastMessageFile = String(argument.dropFirst(2))
                index += 1
                continue
            }
            if argument.hasPrefix("-i"), argument.count > 2, !argument.hasPrefix("--") {
                imagePaths.append(contentsOf: splitCommaDelimited(String(argument.dropFirst(2))))
                index += 1
                continue
            }
            if execOptionConsumesValue(argument) {
                guard index + 1 < arguments.count else {
                    return .failure("codex-swift: missing value for \(argument)", 64)
                }
                index += 2
                continue
            }
            if execFlagWithoutValue(argument) || argument.contains("=") && execAssignmentOption(argument) {
                index += 1
                continue
            }
            if argument.hasPrefix("-") {
                return .failure("codex-swift: unsupported option for command 'exec resume': \(argument)", 64)
            }
            positionals.append(argument)
            index += 1
        }

        guard positionals.count <= 2 else {
            return .failure("codex-swift: unexpected argument for command 'exec resume': \(positionals[2])", 64)
        }

        let prompt: String?
        if positionals.count > 1 {
            prompt = positionals[1]
        } else if positionals.isEmpty || !last {
            prompt = rootPrompt
        } else {
            prompt = nil
        }

        return .success(ParsedExecResume(
            command: ExecResumeCommand(
                sessionID: positionals.first,
                last: last,
                all: all,
                prompt: prompt
            ),
            imagePaths: imagePaths,
            json: json,
            lastMessageFile: lastMessageFile,
            skipGitRepoCheck: skipGitRepoCheck,
            ephemeral: ephemeral,
            ignoreUserConfig: ignoreUserConfig,
            ignoreRules: ignoreRules,
            removedFullAuto: removedFullAuto,
            dangerouslyBypassApprovalsAndSandbox: dangerouslyBypassApprovalsAndSandbox
        ))
    }

    private func splitCommaDelimited(_ value: String) -> [String] {
        value
            .split(separator: ",", omittingEmptySubsequences: true)
            .map(String.init)
    }

    private func execOptionConsumesValue(_ argument: String) -> Bool {
        if argument.contains("=") {
            return false
        }
        return [
            "-m",
            "--model",
            "--local-provider",
            "-p",
            "--profile",
            "-s",
            "--sandbox",
            "-a",
            "--ask-for-approval",
            "-C",
            "--cd",
            "--add-dir",
            "-c",
            "--config",
            "--color"
        ].contains(argument)
    }

    private func execFlagWithoutValue(_ argument: String) -> Bool {
        [
            "--oss",
            "--full-auto",
            "--dangerously-bypass-approvals-and-sandbox",
            "--yolo",
            "--ephemeral",
            "--ignore-user-config",
            "--ignore-rules",
            "--skip-git-repo-check",
            "--json",
            "--experimental-json"
        ].contains(argument)
    }

    private func execAssignmentOption(_ argument: String) -> Bool {
        [
            "--model=",
            "--local-provider=",
            "--profile=",
            "--sandbox=",
            "--ask-for-approval=",
            "--cd=",
            "--add-dir=",
            "-c=",
            "--config=",
            "--color="
        ].contains { argument.hasPrefix($0) }
    }

    private func parseComputerUseCommand(
        _ arguments: [String],
        rootArguments: [String]
    ) -> ParseResult<ComputerUseCommandRequest> {
        var enableGUI = false
        var headless = false
        var execArguments: [String] = []

        for argument in arguments {
            if argument == "--gui" {
                guard !headless else {
                    return .failure("codex-swift: argument conflict for command 'computer-use': --gui conflicts with --headless", 64)
                }
                enableGUI = true
                continue
            }
            if argument == "--headless" {
                guard !enableGUI else {
                    return .failure("codex-swift: argument conflict for command 'computer-use': --headless conflicts with --gui", 64)
                }
                headless = true
                continue
            }
            execArguments.append(argument)
        }

        switch parseConfigOverrides(from: rootArguments) {
        case let .success(configOverrides):
            var rawOverrides = configOverrides.rawOverrides
            rawOverrides.append("features.computer_use=\(enableGUI)")
            return .success(ComputerUseCommandRequest(
                arguments: execArguments,
                enableGUI: enableGUI,
                configOverrides: CliConfigOverrides(rawOverrides: rawOverrides)
            ))
        case let .failure(message, exitCode):
            return .failure(message, exitCode)
        }
    }

    private func parseReviewCommand(
        _ arguments: [String],
        rootArguments: [String]
    ) -> ParseResult<ReviewCommandRequest> {
        var target: ReviewCommandTarget?
        var commitTitle: String?
        var index = 0

        func setTarget(_ next: ReviewCommandTarget, option: String) -> ParseResult<Void> {
            guard target == nil else {
                return .failure("codex-swift: argument conflict for command 'review': \(option) cannot be used with another review target", 64)
            }
            target = next
            return .success(())
        }

        func parseReviewValue(option: String, at index: Int) -> ParseResult<String> {
            guard index + 1 < arguments.count else {
                return .failure("codex-swift: missing value for \(option)", 64)
            }
            return .success(arguments[index + 1])
        }

        while index < arguments.count {
            let argument = arguments[index]
            if argument == "--uncommitted" {
                switch setTarget(.uncommittedChanges, option: argument) {
                case .success:
                    index += 1
                    continue
                case let .failure(message, exitCode):
                    return .failure(message, exitCode)
                }
            }
            if argument == "--base" {
                switch parseReviewValue(option: argument, at: index) {
                case let .success(branch):
                    switch setTarget(.baseBranch(branch: branch), option: argument) {
                    case .success:
                        index += 2
                        continue
                    case let .failure(message, exitCode):
                        return .failure(message, exitCode)
                    }
                case let .failure(message, exitCode):
                    return .failure(message, exitCode)
                }
            }
            if argument.hasPrefix("--base=") {
                switch setTarget(.baseBranch(branch: String(argument.dropFirst("--base=".count))), option: "--base") {
                case .success:
                    index += 1
                    continue
                case let .failure(message, exitCode):
                    return .failure(message, exitCode)
                }
            }
            if argument == "--commit" {
                switch parseReviewValue(option: argument, at: index) {
                case let .success(sha):
                    switch setTarget(.commit(sha: sha, title: nil), option: argument) {
                    case .success:
                        index += 2
                        continue
                    case let .failure(message, exitCode):
                        return .failure(message, exitCode)
                    }
                case let .failure(message, exitCode):
                    return .failure(message, exitCode)
                }
            }
            if argument.hasPrefix("--commit=") {
                switch setTarget(.commit(sha: String(argument.dropFirst("--commit=".count)), title: nil), option: "--commit") {
                case .success:
                    index += 1
                    continue
                case let .failure(message, exitCode):
                    return .failure(message, exitCode)
                }
            }
            if argument == "--title" {
                switch parseReviewValue(option: argument, at: index) {
                case let .success(title):
                    commitTitle = title
                    index += 2
                    continue
                case let .failure(message, exitCode):
                    return .failure(message, exitCode)
                }
            }
            if argument.hasPrefix("--title=") {
                commitTitle = String(argument.dropFirst("--title=".count))
                index += 1
                continue
            }
            if argument == "-" {
                switch setTarget(.customFromStdin, option: "PROMPT") {
                case .success:
                    index += 1
                    continue
                case let .failure(message, exitCode):
                    return .failure(message, exitCode)
                }
            }
            if argument.hasPrefix("-") {
                return .failure("codex-swift: unsupported option for command 'review': \(argument)", 64)
            }

            let trimmed = argument.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                return .failure("Review prompt cannot be empty", 64)
            }
            switch setTarget(.custom(instructions: trimmed), option: "PROMPT") {
            case .success:
                index += 1
                continue
            case let .failure(message, exitCode):
                return .failure(message, exitCode)
            }
        }

        if let commitTitle {
            guard case let .commit(sha, _) = target else {
                return .failure("codex-swift: --title requires --commit", 64)
            }
            target = .commit(sha: sha, title: commitTitle)
        }
        guard let parsedTarget = target else {
            return .failure("Specify --uncommitted, --base, --commit, or provide custom review instructions", 64)
        }

        switch parseConfigOverrides(from: rootArguments) {
        case let .success(configOverrides):
            return .success(ReviewCommandRequest(target: parsedTarget, configOverrides: configOverrides))
        case let .failure(message, exitCode):
            return .failure(message, exitCode)
        }
    }

    private func parseResumeCommand(
        _ arguments: [String],
        rootArguments: [String]
    ) -> ParseResult<ResumeCommandRequest> {
        var sessionID: String?
        var last = false
        var all = false

        for argument in arguments {
            if argument == "--last" {
                guard sessionID == nil else {
                    return .failure("codex-swift: argument conflict for command 'resume': --last conflicts with SESSION_ID", 64)
                }
                last = true
                continue
            }
            if argument == "--all" {
                all = true
                continue
            }
            if argument.hasPrefix("-") {
                return .failure("codex-swift: unsupported option for command 'resume': \(argument)", 64)
            }
            guard sessionID == nil else {
                return .failure("codex-swift: unexpected argument for command 'resume': \(argument)", 64)
            }
            guard !last else {
                return .failure("codex-swift: argument conflict for command 'resume': SESSION_ID conflicts with --last", 64)
            }
            sessionID = argument
        }

        switch parseConfigOverrides(from: rootArguments) {
        case let .success(configOverrides):
            return .success(ResumeCommandRequest(
                sessionID: sessionID,
                last: last,
                all: all,
                configOverrides: configOverrides
            ))
        case let .failure(message, exitCode):
            return .failure(message, exitCode)
        }
    }

    private func parseForkCommand(
        _ arguments: [String],
        rootArguments: [String]
    ) -> ParseResult<ForkCommandRequest> {
        var sessionID: String?
        var last = false
        var all = false
        var remote: String?
        var remoteAuthTokenEnv: String?
        var index = 0

        while index < arguments.count {
            let argument = arguments[index]
            if argument == "--last" {
                guard sessionID == nil else {
                    return .failure("codex-swift: argument conflict for command 'fork': --last conflicts with SESSION_ID", 64)
                }
                last = true
                index += 1
                continue
            }
            if argument == "--all" {
                all = true
                index += 1
                continue
            }
            if argument == "--remote" || argument == "--remote-auth-token-env" {
                guard index + 1 < arguments.count else {
                    return .failure("codex-swift: missing value for \(argument)", 64)
                }
                if argument == "--remote" {
                    remote = arguments[index + 1]
                } else {
                    remoteAuthTokenEnv = arguments[index + 1]
                }
                index += 2
                continue
            }
            if argument.hasPrefix("--remote=") {
                remote = String(argument.dropFirst("--remote=".count))
                index += 1
                continue
            }
            if argument.hasPrefix("--remote-auth-token-env=") {
                remoteAuthTokenEnv = String(argument.dropFirst("--remote-auth-token-env=".count))
                index += 1
                continue
            }
            if argument.hasPrefix("-") {
                return .failure("codex-swift: unsupported option for command 'fork': \(argument)", 64)
            }
            guard sessionID == nil else {
                return .failure("codex-swift: unexpected argument for command 'fork': \(argument)", 64)
            }
            guard !last else {
                return .failure("codex-swift: argument conflict for command 'fork': SESSION_ID conflicts with --last", 64)
            }
            sessionID = argument
            index += 1
        }

        switch parseConfigOverrides(from: rootArguments) {
        case let .success(configOverrides):
            return .success(ForkCommandRequest(
                sessionID: sessionID,
                last: last,
                all: all,
                remote: remote ?? rootRemoteFlagValue(named: "--remote", beforeCommand: "fork", in: rootArguments),
                remoteAuthTokenEnv: remoteAuthTokenEnv ?? rootRemoteFlagValue(
                    named: "--remote-auth-token-env",
                    beforeCommand: "fork",
                    in: rootArguments
                ),
                configOverrides: configOverrides
            ))
        case let .failure(message, exitCode):
            return .failure(message, exitCode)
        }
    }

    private func parseExecServerCommand(
        _ arguments: [String],
        rootArguments: [String]
    ) -> ParseResult<ExecServerCommandRequest> {
        if let remote = rootRemoteFlagValue(named: "--remote", beforeCommand: "exec-server", in: rootArguments) {
            return .failure(
                "`--remote \(remote)` is only supported for interactive TUI commands, not `codex exec-server`",
                1
            )
        }
        if rootRemoteFlagValue(named: "--remote-auth-token-env", beforeCommand: "exec-server", in: rootArguments) != nil {
            return .failure(
                "`--remote-auth-token-env` is only supported for interactive TUI commands, not `codex exec-server`",
                1
            )
        }

        var listen: String?
        var remote: String?
        var executorID: String?
        var name: String?
        var index = 0

        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--listen", "--remote", "--executor-id", "--name":
                guard index + 1 < arguments.count else {
                    return .failure("codex-swift: missing value for \(argument)", 64)
                }
                let value = arguments[index + 1]
                switch argument {
                case "--listen":
                    guard remote == nil else {
                        return .failure("codex-swift: argument conflict for command 'exec-server': --listen conflicts with --remote", 64)
                    }
                    listen = value
                case "--remote":
                    guard listen == nil else {
                        return .failure("codex-swift: argument conflict for command 'exec-server': --remote conflicts with --listen", 64)
                    }
                    remote = value
                case "--executor-id":
                    executorID = value
                case "--name":
                    name = value
                default:
                    break
                }
                index += 2
            default:
                if argument.hasPrefix("--listen=") {
                    guard remote == nil else {
                        return .failure("codex-swift: argument conflict for command 'exec-server': --listen conflicts with --remote", 64)
                    }
                    listen = String(argument.dropFirst("--listen=".count))
                    index += 1
                } else if argument.hasPrefix("--remote=") {
                    guard listen == nil else {
                        return .failure("codex-swift: argument conflict for command 'exec-server': --remote conflicts with --listen", 64)
                    }
                    remote = String(argument.dropFirst("--remote=".count))
                    index += 1
                } else if argument.hasPrefix("--executor-id=") {
                    executorID = String(argument.dropFirst("--executor-id=".count))
                    index += 1
                } else if argument.hasPrefix("--name=") {
                    name = String(argument.dropFirst("--name=".count))
                    index += 1
                } else if argument.hasPrefix("-") {
                    return .failure("codex-swift: unsupported option for command 'exec-server': \(argument)", 64)
                } else {
                    return .failure("codex-swift: unexpected argument for command 'exec-server': \(argument)", 64)
                }
            }
        }

        if let remote {
            guard let executorID else {
                return .failure("codex-swift: --executor-id is required when --remote is set", 64)
            }
            return .success(ExecServerCommandRequest(action: .remote(
                baseURL: remote,
                executorID: executorID,
                name: name
            )))
        }

        return .success(ExecServerCommandRequest(action: .listen(
            url: listen ?? defaultExecServerListenURL
        )))
    }

    private func parseMcpServerCommand(
        _ arguments: [String],
        rootArguments: [String]
    ) -> ParseResult<McpServerCommandRequest> {
        for argument in arguments {
            if argument.hasPrefix("-") {
                return .failure("codex-swift: unsupported option for command 'mcp-server': \(argument)", 64)
            }
            return .failure("codex-swift: unexpected argument for command 'mcp-server': \(argument)", 64)
        }

        switch parseConfigOverrides(from: rootArguments) {
        case let .success(configOverrides):
            return .success(McpServerCommandRequest(configOverrides: configOverrides))
        case let .failure(message, exitCode):
            return .failure(message, exitCode)
        }
    }

    private func parseAppServerCommand(
        _ arguments: [String],
        rootArguments: [String]
    ) -> ParseResult<AppServerCommandRequest> {
        let action: AppServerCommandAction
        guard let subcommand = arguments.first else {
            action = .run
            return appServerRequest(action: action, rootArguments: rootArguments)
        }

        switch subcommand {
        case "proxy":
            switch parseAppServerProxy(Array(arguments.dropFirst())) {
            case let .success(socketPath):
                action = .proxy(socketPath: socketPath)
            case let .failure(message, exitCode):
                return .failure(message, exitCode)
            }
        case "generate-ts":
            switch parseAppServerGenerateTS(Array(arguments.dropFirst())) {
            case let .success(parsed):
                action = .generateTS(
                    outDir: parsed.outDir,
                    prettier: parsed.prettier,
                    experimental: parsed.experimental
                )
            case let .failure(message, exitCode):
                return .failure(message, exitCode)
            }
        case "generate-json-schema":
            switch parseAppServerGenerateJSONSchema(Array(arguments.dropFirst())) {
            case let .success(parsed):
                action = .generateJSONSchema(outDir: parsed.outDir, experimental: parsed.experimental)
            case let .failure(message, exitCode):
                return .failure(message, exitCode)
            }
        case "generate-internal-json-schema":
            switch parseAppServerGenerateInternalJSONSchema(Array(arguments.dropFirst())) {
            case let .success(outDir):
                action = .generateInternalJSONSchema(outDir: outDir)
            case let .failure(message, exitCode):
                return .failure(message, exitCode)
            }
        default:
            if subcommand.hasPrefix("-") {
                return .failure("codex-swift: unsupported option for command 'app-server': \(subcommand)", 64)
            }
            return .failure("codex-swift: unsupported app-server subcommand: \(subcommand)", 64)
        }

        return appServerRequest(action: action, rootArguments: rootArguments)
    }

    private func parseRemoteControlCommand(
        _ arguments: [String],
        rootArguments: [String]
    ) -> ParseResult<AppServerCommandRequest> {
        if let remote = rootRemoteFlagValue(named: "--remote", beforeCommand: "remote-control", in: rootArguments) {
            return .failure(
                "`--remote \(remote)` is only supported for interactive TUI commands, not `codex remote-control`",
                1
            )
        }
        if rootRemoteFlagValue(named: "--remote-auth-token-env", beforeCommand: "remote-control", in: rootArguments) != nil {
            return .failure(
                "`--remote-auth-token-env` is only supported for interactive TUI commands, not `codex remote-control`",
                1
            )
        }
        guard arguments.isEmpty else {
            let argument = arguments[0]
            if argument.hasPrefix("-") {
                return .failure("codex-swift: unsupported option for command 'remote-control': \(argument)", 64)
            }
            return .failure("codex-swift: unexpected argument for command 'remote-control': \(argument)", 64)
        }
        switch parseConfigOverrides(from: rootArguments) {
        case let .success(configOverrides):
            var rawOverrides = configOverrides.rawOverrides
            rawOverrides.append("features.remote_control=true")
            return .success(AppServerCommandRequest(
                action: .remoteControl,
                configOverrides: CliConfigOverrides(rawOverrides: rawOverrides)
            ))
        case let .failure(message, exitCode):
            return .failure(message, exitCode)
        }
    }

    private func rootRemoteFlagValue(named option: String, beforeCommand command: String, in arguments: [String]) -> String? {
        rootRemoteFlagValue(named: option, beforeCommands: [command], in: arguments)
    }

    private func rootRemoteFlagValue(named option: String, beforeCommand spec: CommandSpec, in arguments: [String]) -> String? {
        rootRemoteFlagValue(named: option, beforeCommands: [spec.name] + spec.aliases, in: arguments)
    }

    private func rootFlagPresent(named option: String, beforeCommands commands: [String], in arguments: [String]) -> Bool {
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            if commands.contains(argument) {
                return false
            }
            if argument == option {
                return true
            }
            if optionConsumesValue(argument) {
                index += 2
            } else {
                index += 1
            }
        }
        return false
    }

    private func rootRemoteFlagValue(named option: String, beforeCommands commands: [String], in arguments: [String]) -> String? {
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            if commands.contains(argument) {
                return nil
            }
            if argument == option {
                return index + 1 < arguments.count ? arguments[index + 1] : ""
            }
            if argument.hasPrefix("\(option)=") {
                return String(argument.dropFirst(option.count + 1))
            }
            if optionConsumesValue(argument) {
                index += 2
            } else {
                index += 1
            }
        }
        return nil
    }

    private func rootRemovedFullAutoRejectionMessage(invocation: Invocation, arguments: [String]) -> String? {
        switch invocation {
        case let .command(spec, _):
            if rootFlagPresent(named: "--full-auto", beforeCommands: [spec.name] + spec.aliases, in: arguments) {
                return "codex-swift: unsupported option at top level: --full-auto"
            }
            return nil
        case .version, .help:
            return nil
        case .interactive, .unknown:
            return arguments.contains("--full-auto")
                ? "codex-swift: unsupported option at top level: --full-auto"
                : nil
        }
    }

    private func rootDangerouslyBypassBeforeExec(in arguments: [String]) -> Bool {
        let execCommands = ["exec", "e"]
        return rootFlagPresent(
            named: "--dangerously-bypass-approvals-and-sandbox",
            beforeCommands: execCommands,
            in: arguments
        ) || rootFlagPresent(named: "--yolo", beforeCommands: execCommands, in: arguments)
    }

    private func rootRemoteModeRejectionMessage(
        spec: CommandSpec,
        commandArguments: [String],
        arguments: [String]
    ) -> String? {
        guard let subcommand = rootRemoteRejectedSubcommandName(
            spec: spec,
            commandArguments: commandArguments
        ) else {
            return nil
        }
        if let remote = rootRemoteFlagValue(named: "--remote", beforeCommand: spec, in: arguments) {
            return "`--remote \(remote)` is only supported for interactive TUI commands, not `codex \(subcommand)`"
        }
        if rootRemoteFlagValue(named: "--remote-auth-token-env", beforeCommand: spec, in: arguments) != nil {
            return "`--remote-auth-token-env` is only supported for interactive TUI commands, not `codex \(subcommand)`"
        }
        return nil
    }

    private func rootRemoteRejectedSubcommandName(
        spec: CommandSpec,
        commandArguments: [String]
    ) -> String? {
        switch spec.name {
        case "resume", "fork":
            return nil
        case "app-server":
            return appServerRemoteRejectionSubcommand(commandArguments)
        case "sandbox":
            return sandboxRemoteRejectionSubcommand(commandArguments)
        case "debug":
            return debugRemoteRejectionSubcommand(commandArguments)
        case "execpolicy":
            return commandArguments.first == "check" ? "execpolicy check" : nil
        case "features":
            switch commandArguments.first {
            case "list":
                return "features list"
            case "enable":
                return "features enable"
            case "disable":
                return "features disable"
            default:
                return nil
            }
        case "exec", "computer-use", "review", "login", "logout", "mcp", "plugin",
             "mcp-server", "remote-control", "app", "completion", "update", "cloud",
             "apply", "responses-api-proxy", "stdio-to-uds", "exec-server":
            return spec.name
        default:
            return nil
        }
    }

    private func appServerRemoteRejectionSubcommand(_ arguments: [String]) -> String? {
        guard let subcommand = arguments.first else {
            return "app-server"
        }
        switch subcommand {
        case "proxy":
            return "app-server proxy"
        case "generate-ts":
            return "app-server generate-ts"
        case "generate-json-schema":
            return "app-server generate-json-schema"
        case "generate-internal-json-schema":
            return "app-server generate-internal-json-schema"
        default:
            return nil
        }
    }

    private func sandboxRemoteRejectionSubcommand(_ arguments: [String]) -> String? {
        switch arguments.first {
        case "macos":
            return "sandbox macos"
        case "linux":
            return "sandbox linux"
        case "windows":
            return "sandbox windows"
        default:
            return nil
        }
    }

    private func debugRemoteRejectionSubcommand(_ arguments: [String]) -> String? {
        switch arguments.first {
        case "models":
            return "debug models"
        case "app-server":
            return "debug app-server"
        case "prompt-input":
            return "debug prompt-input"
        case "trace-reduce":
            return "debug trace-reduce"
        case "clear-memories":
            return "debug clear-memories"
        default:
            return nil
        }
    }

    private func appServerRequest(
        action: AppServerCommandAction,
        rootArguments: [String]
    ) -> ParseResult<AppServerCommandRequest> {
        switch parseConfigOverrides(from: rootArguments) {
        case let .success(configOverrides):
            return .success(AppServerCommandRequest(action: action, configOverrides: configOverrides))
        case let .failure(message, exitCode):
            return .failure(message, exitCode)
        }
    }

    private func parseAppServerProxy(_ arguments: [String]) -> ParseResult<String?> {
        var socketPath: String?
        var index = 0

        while index < arguments.count {
            let argument = arguments[index]
            if argument == "--sock" {
                guard index + 1 < arguments.count else {
                    return .failure("codex-swift: missing value for \(argument)", 64)
                }
                socketPath = arguments[index + 1]
                index += 2
                continue
            }
            if argument.hasPrefix("--sock=") {
                socketPath = String(argument.dropFirst("--sock=".count))
                index += 1
                continue
            }
            if argument.hasPrefix("-") {
                return .failure("codex-swift: unsupported option for command 'app-server proxy': \(argument)", 64)
            }
            return .failure("codex-swift: unexpected argument for command 'app-server proxy': \(argument)", 64)
        }

        return .success(socketPath)
    }

    private func parseAppServerGenerateTS(
        _ arguments: [String]
    ) -> ParseResult<(outDir: String, prettier: String?, experimental: Bool)> {
        var outDir: String?
        var prettier: String?
        var experimental = false
        var index = 0

        while index < arguments.count {
            let argument = arguments[index]
            if argument == "--out" || argument == "-o" {
                guard index + 1 < arguments.count else {
                    return .failure("codex-swift: missing value for \(argument)", 64)
                }
                outDir = arguments[index + 1]
                index += 2
                continue
            }
            if argument.hasPrefix("--out=") {
                outDir = String(argument.dropFirst("--out=".count))
                index += 1
                continue
            }
            if argument.hasPrefix("-o"), argument.count > 2, !argument.hasPrefix("--") {
                outDir = String(argument.dropFirst(2))
                index += 1
                continue
            }
            if argument == "--prettier" || argument == "-p" {
                guard index + 1 < arguments.count else {
                    return .failure("codex-swift: missing value for \(argument)", 64)
                }
                prettier = arguments[index + 1]
                index += 2
                continue
            }
            if argument.hasPrefix("--prettier=") {
                prettier = String(argument.dropFirst("--prettier=".count))
                index += 1
                continue
            }
            if argument.hasPrefix("-p"), argument.count > 2, !argument.hasPrefix("--") {
                prettier = String(argument.dropFirst(2))
                index += 1
                continue
            }
            if argument == "--experimental" {
                experimental = true
                index += 1
                continue
            }
            if argument.hasPrefix("-") {
                return .failure("codex-swift: unsupported option for command 'app-server generate-ts': \(argument)", 64)
            }
            return .failure("codex-swift: unexpected argument for command 'app-server generate-ts': \(argument)", 64)
        }

        guard let outDir else {
            return .failure("codex-swift: missing required option for command 'app-server generate-ts': --out <DIR>", 64)
        }
        return .success((outDir: outDir, prettier: prettier, experimental: experimental))
    }

    private func parseAppServerGenerateJSONSchema(_ arguments: [String]) -> ParseResult<(outDir: String, experimental: Bool)> {
        var outDir: String?
        var experimental = false
        var index = 0

        while index < arguments.count {
            let argument = arguments[index]
            if argument == "--out" || argument == "-o" {
                guard index + 1 < arguments.count else {
                    return .failure("codex-swift: missing value for \(argument)", 64)
                }
                outDir = arguments[index + 1]
                index += 2
                continue
            }
            if argument.hasPrefix("--out=") {
                outDir = String(argument.dropFirst("--out=".count))
                index += 1
                continue
            }
            if argument.hasPrefix("-o"), argument.count > 2, !argument.hasPrefix("--") {
                outDir = String(argument.dropFirst(2))
                index += 1
                continue
            }
            if argument == "--experimental" {
                experimental = true
                index += 1
                continue
            }
            if argument.hasPrefix("-") {
                return .failure("codex-swift: unsupported option for command 'app-server generate-json-schema': \(argument)", 64)
            }
            return .failure("codex-swift: unexpected argument for command 'app-server generate-json-schema': \(argument)", 64)
        }

        guard let outDir else {
            return .failure("codex-swift: missing required option for command 'app-server generate-json-schema': --out <DIR>", 64)
        }
        return .success((outDir: outDir, experimental: experimental))
    }

    private func parseAppServerGenerateInternalJSONSchema(_ arguments: [String]) -> ParseResult<String> {
        var outDir: String?
        var index = 0

        while index < arguments.count {
            let argument = arguments[index]
            if argument == "--out" || argument == "-o" {
                guard index + 1 < arguments.count else {
                    return .failure("codex-swift: missing value for \(argument)", 64)
                }
                outDir = arguments[index + 1]
                index += 2
                continue
            }
            if argument.hasPrefix("--out=") {
                outDir = String(argument.dropFirst("--out=".count))
                index += 1
                continue
            }
            if argument.hasPrefix("-o"), argument.count > 2, !argument.hasPrefix("--") {
                outDir = String(argument.dropFirst(2))
                index += 1
                continue
            }
            if argument.hasPrefix("-") {
                return .failure("codex-swift: unsupported option for command 'app-server generate-internal-json-schema': \(argument)", 64)
            }
            return .failure("codex-swift: unexpected argument for command 'app-server generate-internal-json-schema': \(argument)", 64)
        }

        guard let outDir else {
            return .failure("codex-swift: missing required option for command 'app-server generate-internal-json-schema': --out <DIR>", 64)
        }
        return .success(outDir)
    }

    private func parseAppCommand(_ arguments: [String]) -> ParseResult<AppCommandRequest> {
        var downloadURLOverride: String?
        var positionals: [String] = []
        var index = 0

        func value(after option: String, at index: Int) -> ParseResult<String> {
            guard index + 1 < arguments.count else {
                return .failure("codex-swift: missing value for \(option)", 64)
            }
            return .success(arguments[index + 1])
        }

        while index < arguments.count {
            let argument = arguments[index]
            if argument == "--download-url" {
                switch value(after: argument, at: index) {
                case let .success(url):
                    downloadURLOverride = url
                    index += 2
                    continue
                case let .failure(message, exitCode):
                    return .failure(message, exitCode)
                }
            }
            if argument.hasPrefix("--download-url=") {
                downloadURLOverride = String(argument.dropFirst("--download-url=".count))
                index += 1
                continue
            }
            if argument.hasPrefix("-") {
                return .failure("codex-swift: unsupported option for command 'app': \(argument)", 64)
            }
            positionals.append(argument)
            index += 1
        }

        guard positionals.count <= 1 else {
            return .failure("codex-swift: unexpected argument for command 'app': \(positionals[1])", 64)
        }
        return .success(AppCommandRequest(
            path: positionals.first ?? ".",
            downloadURLOverride: downloadURLOverride
        ))
    }

    private func parseExecPolicyCommandAction(_ arguments: [String]) -> ParseResult<ExecPolicyCommandAction> {
        guard let subcommand = arguments.first else {
            return .failure("codex-swift: missing required subcommand for command 'execpolicy': check", 64)
        }
        guard subcommand == "check" else {
            return .failure("codex-swift: unsupported execpolicy subcommand: \(subcommand)", 64)
        }
        return parseExecPolicyCheck(Array(arguments.dropFirst()))
    }

    private func parseExecPolicyCheck(_ arguments: [String]) -> ParseResult<ExecPolicyCommandAction> {
        var rules: [String] = []
        var pretty = false
        var command: [String] = []
        var index = 0

        while index < arguments.count {
            let argument = arguments[index]
            if argument == "--" {
                command.append(contentsOf: arguments.dropFirst(index + 1))
                break
            }
            if argument == "--rules" || argument == "-r" {
                guard index + 1 < arguments.count else {
                    return .failure("codex-swift: missing value for \(argument)", 64)
                }
                rules.append(arguments[index + 1])
                index += 2
                continue
            }
            if argument.hasPrefix("--rules=") {
                rules.append(String(argument.dropFirst("--rules=".count)))
                index += 1
                continue
            }
            if argument == "--pretty" {
                pretty = true
                index += 1
                continue
            }
            if argument.hasPrefix("-r"), argument.count > 2, !argument.hasPrefix("--") {
                rules.append(String(argument.dropFirst(2)))
                index += 1
                continue
            }

            command.append(argument)
            command.append(contentsOf: arguments.dropFirst(index + 1))
            break
        }

        guard !rules.isEmpty else {
            return .failure("codex-swift: missing required option for command 'execpolicy check': --rules <PATH>", 64)
        }
        guard !command.isEmpty else {
            return .failure("codex-swift: missing required argument for command 'execpolicy check': <COMMAND>", 64)
        }
        return .success(.check(rules: rules, pretty: pretty, command: command))
    }

    private func parseSandboxCommandAction(_ arguments: [String]) -> ParseResult<SandboxCommandAction> {
        guard let subcommand = arguments.first else {
            return .failure("codex-swift: missing required subcommand for command 'sandbox': macos|linux|windows", 64)
        }

        let subcommandArguments = Array(arguments.dropFirst())
        switch subcommand {
        case "macos", "seatbelt":
            switch parseSandboxSubcommand(subcommandArguments, commandName: "macos", supportsLogDenials: true) {
            case let .success(parsed):
                return .success(.macos(
                    profile: parsed.profile,
                    allowUnixSockets: parsed.allowUnixSockets,
                    logDenials: parsed.logDenials,
                    command: parsed.command
                ))
            case let .failure(message, exitCode):
                return .failure(message, exitCode)
            }
        case "linux", "landlock":
            switch parseSandboxSubcommand(subcommandArguments, commandName: "linux", supportsLogDenials: false) {
            case let .success(parsed):
                return .success(.linux(profile: parsed.profile, command: parsed.command))
            case let .failure(message, exitCode):
                return .failure(message, exitCode)
            }
        case "windows":
            switch parseSandboxSubcommand(subcommandArguments, commandName: "windows", supportsLogDenials: false) {
            case let .success(parsed):
                return .success(.windows(profile: parsed.profile, command: parsed.command))
            case let .failure(message, exitCode):
                return .failure(message, exitCode)
            }
        default:
            return .failure("codex-swift: unsupported sandbox subcommand: \(subcommand)", 64)
        }
    }

    private struct ParsedSandboxSubcommand {
        let profile: SandboxProfileOptions
        let allowUnixSockets: [String]
        let logDenials: Bool
        let command: [String]
    }

    private func parseSandboxSubcommand(
        _ arguments: [String],
        commandName: String,
        supportsLogDenials: Bool
    ) -> ParseResult<ParsedSandboxSubcommand> {
        var permissionsProfile: String?
        var cwd: String?
        var includeManagedConfig = false
        var allowUnixSockets: [String] = []
        var logDenials = false
        var command: [String] = []
        var index = 0

        while index < arguments.count {
            let argument = arguments[index]
            if argument == "--" {
                command.append(contentsOf: arguments.dropFirst(index + 1))
                break
            }
            if argument == "--log-denials" {
                guard supportsLogDenials else {
                    return .failure("codex-swift: unsupported option for command 'sandbox \(commandName)': --log-denials", 64)
                }
                logDenials = true
                index += 1
                continue
            }
            if argument == "--include-managed-config" {
                includeManagedConfig = true
                index += 1
                continue
            }
            if argument == "--permissions-profile" {
                guard index + 1 < arguments.count else {
                    return .failure("codex-swift: missing value for option '--permissions-profile'", 64)
                }
                permissionsProfile = arguments[index + 1]
                index += 2
                continue
            }
            if argument.hasPrefix("--permissions-profile=") {
                permissionsProfile = String(argument.dropFirst("--permissions-profile=".count))
                index += 1
                continue
            }
            if argument == "-C" || argument == "--cd" {
                guard index + 1 < arguments.count else {
                    return .failure("codex-swift: missing value for option '\(argument)'", 64)
                }
                cwd = arguments[index + 1]
                index += 2
                continue
            }
            if argument.hasPrefix("--cd=") {
                cwd = String(argument.dropFirst("--cd=".count))
                index += 1
                continue
            }
            if argument == "--allow-unix-socket" {
                guard supportsLogDenials else {
                    return .failure("codex-swift: unsupported option for command 'sandbox \(commandName)': --allow-unix-socket", 64)
                }
                guard index + 1 < arguments.count else {
                    return .failure("codex-swift: missing value for option '--allow-unix-socket'", 64)
                }
                allowUnixSockets.append(arguments[index + 1])
                index += 2
                continue
            }
            if argument.hasPrefix("--allow-unix-socket=") {
                guard supportsLogDenials else {
                    return .failure("codex-swift: unsupported option for command 'sandbox \(commandName)': --allow-unix-socket", 64)
                }
                allowUnixSockets.append(String(argument.dropFirst("--allow-unix-socket=".count)))
                index += 1
                continue
            }
            if argument.hasPrefix("-") {
                return .failure("codex-swift: unsupported option for command 'sandbox \(commandName)': \(argument)", 64)
            }

            command.append(argument)
            command.append(contentsOf: arguments.dropFirst(index + 1))
            break
        }

        guard !command.isEmpty else {
            return .failure("codex-swift: missing required argument for command 'sandbox \(commandName)': <COMMAND>", 64)
        }

        guard permissionsProfile != nil || (cwd == nil && !includeManagedConfig) else {
            return .failure("codex-swift: --cd and --include-managed-config require --permissions-profile", 64)
        }

        return .success(ParsedSandboxSubcommand(
            profile: SandboxProfileOptions(
                permissionsProfile: permissionsProfile,
                cwd: cwd,
                includeManagedConfig: includeManagedConfig
            ),
            allowUnixSockets: allowUnixSockets,
            logDenials: logDenials,
            command: command
        ))
    }

    private func parseDebugCommandAction(_ arguments: [String]) -> ParseResult<DebugCommandAction> {
        guard let subcommand = arguments.first else {
            return .failure(
                "codex-swift: missing required subcommand for command 'debug': models|app-server|prompt-input|trace-reduce|clear-memories",
                64
            )
        }

        let rest = Array(arguments.dropFirst())
        switch subcommand {
        case "models":
            return parseDebugModels(rest)
        case "app-server":
            return parseDebugAppServer(rest)
        case "prompt-input":
            return parseDebugPromptInput(rest)
        case "trace-reduce":
            return parseDebugTraceReduce(rest)
        case "clear-memories":
            return parseNoArgumentDebugAction(rest, subcommand: subcommand, action: .clearMemories)
        default:
            return .failure("codex-swift: unsupported debug subcommand: \(subcommand)", 64)
        }
    }

    private func parseDebugModels(_ arguments: [String]) -> ParseResult<DebugCommandAction> {
        var bundled = false
        for argument in arguments {
            if argument == "--bundled" {
                bundled = true
                continue
            }
            if argument.hasPrefix("-") {
                return .failure("codex-swift: unsupported option for command 'debug models': \(argument)", 64)
            }
            return .failure("codex-swift: unexpected argument for command 'debug models': \(argument)", 64)
        }
        return .success(.models(bundled: bundled))
    }

    private func parseDebugAppServer(_ arguments: [String]) -> ParseResult<DebugCommandAction> {
        guard let subcommand = arguments.first else {
            return .failure("codex-swift: missing required subcommand for command 'debug app-server': send-message-v2", 64)
        }
        guard subcommand == "send-message-v2" else {
            return .failure("codex-swift: unsupported debug app-server subcommand: \(subcommand)", 64)
        }
        let rest = Array(arguments.dropFirst())
        guard let message = rest.first else {
            return .failure("codex-swift: missing required argument for command 'debug app-server send-message-v2': <USER_MESSAGE>", 64)
        }
        if message.hasPrefix("-") {
            return .failure("codex-swift: unsupported option for command 'debug app-server send-message-v2': \(message)", 64)
        }
        guard rest.count == 1 else {
            return .failure("codex-swift: unexpected argument for command 'debug app-server send-message-v2': \(rest[1])", 64)
        }
        return .success(.appServerSendMessageV2(message: message))
    }

    private func parseDebugPromptInput(_ arguments: [String]) -> ParseResult<DebugCommandAction> {
        var prompt: String?
        var imagePaths: [String] = []
        var index = 0

        while index < arguments.count {
            let argument = arguments[index]
            if argument == "--image" || argument == "-i" {
                guard index + 1 < arguments.count else {
                    return .failure("codex-swift: missing value for \(argument)", 64)
                }
                imagePaths.append(contentsOf: splitCommaDelimited(arguments[index + 1]))
                index += 2
                continue
            }
            if argument.hasPrefix("--image=") {
                imagePaths.append(contentsOf: splitCommaDelimited(String(argument.dropFirst("--image=".count))))
                index += 1
                continue
            }
            if argument.hasPrefix("-i"), argument.count > 2, !argument.hasPrefix("--") {
                imagePaths.append(contentsOf: splitCommaDelimited(String(argument.dropFirst(2))))
                index += 1
                continue
            }
            if argument.hasPrefix("-") {
                return .failure("codex-swift: unsupported option for command 'debug prompt-input': \(argument)", 64)
            }
            if prompt != nil {
                return .failure("codex-swift: unexpected argument for command 'debug prompt-input': \(argument)", 64)
            }
            prompt = argument
            index += 1
        }

        return .success(.promptInput(prompt: prompt, imagePaths: imagePaths))
    }

    private func parseDebugTraceReduce(_ arguments: [String]) -> ParseResult<DebugCommandAction> {
        var traceBundle: String?
        var output: String?
        var index = 0

        while index < arguments.count {
            let argument = arguments[index]
            if argument == "--output" || argument == "-o" {
                guard index + 1 < arguments.count else {
                    return .failure("codex-swift: missing value for \(argument)", 64)
                }
                output = arguments[index + 1]
                index += 2
                continue
            }
            if argument.hasPrefix("--output=") {
                output = String(argument.dropFirst("--output=".count))
                index += 1
                continue
            }
            if argument.hasPrefix("-o"), argument.count > 2, !argument.hasPrefix("--") {
                output = String(argument.dropFirst(2))
                index += 1
                continue
            }
            if argument.hasPrefix("-") {
                return .failure("codex-swift: unsupported option for command 'debug trace-reduce': \(argument)", 64)
            }
            if traceBundle != nil {
                return .failure("codex-swift: unexpected argument for command 'debug trace-reduce': \(argument)", 64)
            }
            traceBundle = argument
            index += 1
        }

        guard let traceBundle else {
            return .failure("codex-swift: missing required argument for command 'debug trace-reduce': <TRACE_BUNDLE>", 64)
        }
        return .success(.traceReduce(traceBundle: traceBundle, output: output))
    }

    private func parseNoArgumentDebugAction(
        _ arguments: [String],
        subcommand: String,
        action: DebugCommandAction
    ) -> ParseResult<DebugCommandAction> {
        guard let argument = arguments.first else {
            return .success(action)
        }
        if argument.hasPrefix("-") {
            return .failure("codex-swift: unsupported option for command 'debug \(subcommand)': \(argument)", 64)
        }
        return .failure("codex-swift: unexpected argument for command 'debug \(subcommand)': \(argument)", 64)
    }

    private func parseMcpCommandAction(_ arguments: [String]) -> ParseResult<McpCommandAction> {
        guard let subcommand = arguments.first else {
            return .failure("codex-swift: missing required subcommand for command 'mcp': list|get|add|remove|login|logout", 64)
        }

        let rest = Array(arguments.dropFirst())
        switch subcommand {
        case "list":
            return parseMcpList(rest)
        case "get":
            return parseMcpGet(rest)
        case "add":
            return parseMcpAdd(rest)
        case "remove":
            return parseMcpNameOnly(rest, subcommand: "remove").map { .remove(name: $0) }
        case "login":
            return parseMcpLogin(rest)
        case "logout":
            return parseMcpNameOnly(rest, subcommand: "logout").map { .logout(name: $0) }
        default:
            return .failure("codex-swift: unsupported mcp subcommand: \(subcommand)", 64)
        }
    }

    private func parseMcpList(_ arguments: [String]) -> ParseResult<McpCommandAction> {
        var json = false
        for argument in arguments {
            if argument == "--json" {
                json = true
                continue
            }
            if argument.hasPrefix("-") {
                return .failure("codex-swift: unsupported option for command 'mcp list': \(argument)", 64)
            }
            return .failure("codex-swift: unexpected argument for command 'mcp list': \(argument)", 64)
        }
        return .success(.list(json: json))
    }

    private func parseMcpGet(_ arguments: [String]) -> ParseResult<McpCommandAction> {
        var name: String?
        var json = false
        for argument in arguments {
            if argument == "--json" {
                json = true
                continue
            }
            if argument.hasPrefix("-") {
                return .failure("codex-swift: unsupported option for command 'mcp get': \(argument)", 64)
            }
            if name != nil {
                return .failure("codex-swift: unexpected argument for command 'mcp get': \(argument)", 64)
            }
            name = argument
        }
        guard let name else {
            return .failure("codex-swift: missing required argument for command 'mcp get': <NAME>", 64)
        }
        return .success(.get(name: name, json: json))
    }

    private func parseMcpAdd(_ arguments: [String]) -> ParseResult<McpCommandAction> {
        guard let name = arguments.first, !name.hasPrefix("-") else {
            return .failure("codex-swift: missing required argument for command 'mcp add': <NAME>", 64)
        }

        var env: [McpEnvPair] = []
        var url: String?
        var bearerTokenEnvVar: String?
        var command: [String] = []
        var index = 1

        while index < arguments.count {
            let argument = arguments[index]
            if argument == "--" {
                command.append(contentsOf: arguments.dropFirst(index + 1))
                break
            }
            if argument == "--env" {
                guard index + 1 < arguments.count else {
                    return .failure("codex-swift: missing value for --env", 64)
                }
                switch parseMcpEnvPair(arguments[index + 1]) {
                case let .success(pair):
                    env.append(pair)
                case let .failure(message, exitCode):
                    return .failure(message, exitCode)
                }
                index += 2
                continue
            }
            if argument.hasPrefix("--env=") {
                switch parseMcpEnvPair(String(argument.dropFirst("--env=".count))) {
                case let .success(pair):
                    env.append(pair)
                case let .failure(message, exitCode):
                    return .failure(message, exitCode)
                }
                index += 1
                continue
            }
            if argument == "--url" {
                guard index + 1 < arguments.count else {
                    return .failure("codex-swift: missing value for --url", 64)
                }
                url = arguments[index + 1]
                index += 2
                continue
            }
            if argument.hasPrefix("--url=") {
                url = String(argument.dropFirst("--url=".count))
                index += 1
                continue
            }
            if argument == "--bearer-token-env-var" {
                guard index + 1 < arguments.count else {
                    return .failure("codex-swift: missing value for --bearer-token-env-var", 64)
                }
                bearerTokenEnvVar = arguments[index + 1]
                index += 2
                continue
            }
            if argument.hasPrefix("--bearer-token-env-var=") {
                bearerTokenEnvVar = String(argument.dropFirst("--bearer-token-env-var=".count))
                index += 1
                continue
            }
            if argument.hasPrefix("-") {
                return .failure("codex-swift: unsupported option for command 'mcp add': \(argument)", 64)
            }

            command.append(argument)
            command.append(contentsOf: arguments.dropFirst(index + 1))
            break
        }

        if let url {
            guard command.isEmpty else {
                return .failure("codex-swift: exactly one of command or --url must be provided", 64)
            }
            guard env.isEmpty else {
                return .failure("codex-swift: --env is only valid with stdio MCP servers", 64)
            }
            return .success(.add(name: name, transport: .streamableHttp(
                url: url,
                bearerTokenEnvVar: bearerTokenEnvVar
            )))
        }

        guard bearerTokenEnvVar == nil else {
            return .failure("codex-swift: --bearer-token-env-var requires --url", 64)
        }
        guard !command.isEmpty else {
            return .failure("codex-swift: missing required argument for command 'mcp add': <COMMAND>", 64)
        }
        return .success(.add(name: name, transport: .stdio(command: command, env: env)))
    }

    private func parseMcpLogin(_ arguments: [String]) -> ParseResult<McpCommandAction> {
        var name: String?
        var scopes: [String] = []
        var iterator = arguments.makeIterator()

        while let argument = iterator.next() {
            if argument == "--scopes" {
                guard let value = iterator.next() else {
                    return .failure("codex-swift: missing value for --scopes", 64)
                }
                scopes.append(contentsOf: value.split(separator: ",").map(String.init))
                continue
            }
            if argument.hasPrefix("--scopes=") {
                let value = String(argument.dropFirst("--scopes=".count))
                scopes.append(contentsOf: value.split(separator: ",").map(String.init))
                continue
            }
            if argument.hasPrefix("-") {
                return .failure("codex-swift: unsupported option for command 'mcp login': \(argument)", 64)
            }
            if name != nil {
                return .failure("codex-swift: unexpected argument for command 'mcp login': \(argument)", 64)
            }
            name = argument
        }

        guard let name else {
            return .failure("codex-swift: missing required argument for command 'mcp login': <NAME>", 64)
        }
        return .success(.login(name: name, scopes: scopes))
    }

    private func parseMcpNameOnly(_ arguments: [String], subcommand: String) -> ParseResult<String> {
        var name: String?
        for argument in arguments {
            if argument.hasPrefix("-") {
                return .failure("codex-swift: unsupported option for command 'mcp \(subcommand)': \(argument)", 64)
            }
            if name != nil {
                return .failure("codex-swift: unexpected argument for command 'mcp \(subcommand)': \(argument)", 64)
            }
            name = argument
        }
        guard let name else {
            return .failure("codex-swift: missing required argument for command 'mcp \(subcommand)': <NAME>", 64)
        }
        return .success(name)
    }

    private func parseMcpEnvPair(_ value: String) -> ParseResult<McpEnvPair> {
        guard let equalsIndex = value.firstIndex(of: "=") else {
            return .failure("environment entries must be in KEY=VALUE form", 64)
        }
        let key = value[..<equalsIndex].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            return .failure("environment entries must be in KEY=VALUE form", 64)
        }
        let rawValue = value[value.index(after: equalsIndex)...]
        return .success(McpEnvPair(key: String(key), value: String(rawValue)))
    }

    private func parseCloudCommandAction(_ arguments: [String]) -> ParseResult<CloudCommandAction> {
        guard let subcommand = arguments.first else {
            return .failure("codex-swift: command 'cloud' TUI runtime is not complete yet.", 78)
        }

        switch subcommand {
        case "status":
            switch parseCloudRequiredTaskID(Array(arguments.dropFirst()), command: subcommand) {
            case let .success(taskID):
                return .success(.status(taskID: taskID))
            case let .failure(message, exitCode):
                return .failure(message, exitCode)
            }
        case "list":
            return parseCloudList(Array(arguments.dropFirst()))
        case "diff", "apply":
            switch parseCloudTaskAndAttempt(Array(arguments.dropFirst()), command: subcommand) {
            case let .success(parsed):
                if subcommand == "diff" {
                    return .success(.diff(taskID: parsed.taskID, attempt: parsed.attempt))
                }
                return .success(.apply(taskID: parsed.taskID, attempt: parsed.attempt))
            case let .failure(message, exitCode):
                return .failure(message, exitCode)
            }
        case "exec":
            return parseCloudExec(Array(arguments.dropFirst()))
        default:
            return .failure("codex-swift: unsupported cloud subcommand: \(subcommand)", 64)
        }
    }

    private func parseCloudList(_ arguments: [String]) -> ParseResult<CloudCommandAction> {
        var environment: String?
        var limit = 20
        var cursor: String?
        var json = false
        var iterator = arguments.makeIterator()

        while let argument = iterator.next() {
            if argument == "--env" {
                guard let value = iterator.next() else {
                    return .failure("codex-swift: missing value for --env", 64)
                }
                environment = value
                continue
            }
            if argument.hasPrefix("--env=") {
                environment = String(argument.dropFirst("--env=".count))
                continue
            }
            if argument == "--limit" {
                guard let value = iterator.next() else {
                    return .failure("codex-swift: missing value for --limit", 64)
                }
                switch parseCloudListLimit(value) {
                case let .success(parsed):
                    limit = parsed
                case let .failure(message, exitCode):
                    return .failure(message, exitCode)
                }
                continue
            }
            if argument.hasPrefix("--limit=") {
                let value = String(argument.dropFirst("--limit=".count))
                switch parseCloudListLimit(value) {
                case let .success(parsed):
                    limit = parsed
                case let .failure(message, exitCode):
                    return .failure(message, exitCode)
                }
                continue
            }
            if argument == "--cursor" {
                guard let value = iterator.next() else {
                    return .failure("codex-swift: missing value for --cursor", 64)
                }
                cursor = value
                continue
            }
            if argument.hasPrefix("--cursor=") {
                cursor = String(argument.dropFirst("--cursor=".count))
                continue
            }
            if argument == "--json" {
                json = true
                continue
            }
            if argument.hasPrefix("-") {
                return .failure("codex-swift: unsupported option for command 'cloud list': \(argument)", 64)
            }
            return .failure("codex-swift: unexpected argument for command 'cloud list': \(argument)", 64)
        }

        return .success(.list(environment: environment, limit: limit, cursor: cursor, json: json))
    }

    private func parseCloudRequiredTaskID(_ arguments: [String], command: String) -> ParseResult<String> {
        var taskID: String?

        for argument in arguments {
            if argument.hasPrefix("-") {
                return .failure("codex-swift: unsupported option for command 'cloud \(command)': \(argument)", 64)
            }
            if taskID != nil {
                return .failure("codex-swift: unexpected argument for command 'cloud \(command)': \(argument)", 64)
            }
            taskID = argument
        }

        guard let taskID else {
            return .failure("codex-swift: missing required argument for command 'cloud \(command)': <TASK_ID>", 64)
        }
        return .success(taskID)
    }

    private func parseCloudTaskAndAttempt(_ arguments: [String], command: String) -> ParseResult<(taskID: String, attempt: Int?)> {
        var taskID: String?
        var attempt: Int?
        var iterator = arguments.makeIterator()

        while let argument = iterator.next() {
            if argument == "--attempt" {
                guard let value = iterator.next() else {
                    return .failure("codex-swift: missing value for --attempt", 64)
                }
                switch parseCloudAttempt(value) {
                case let .success(parsed):
                    attempt = parsed
                case let .failure(message, exitCode):
                    return .failure(message, exitCode)
                }
                continue
            }
            if argument.hasPrefix("--attempt=") {
                let value = String(argument.dropFirst("--attempt=".count))
                switch parseCloudAttempt(value) {
                case let .success(parsed):
                    attempt = parsed
                case let .failure(message, exitCode):
                    return .failure(message, exitCode)
                }
                continue
            }
            if argument.hasPrefix("-") {
                return .failure("codex-swift: unsupported option for command 'cloud \(command)': \(argument)", 64)
            }
            if taskID != nil {
                return .failure("codex-swift: unexpected argument for command 'cloud \(command)': \(argument)", 64)
            }
            taskID = argument
        }

        guard let taskID else {
            return .failure("codex-swift: missing required argument for command 'cloud \(command)': <TASK_ID>", 64)
        }
        return .success((taskID: taskID, attempt: attempt))
    }

    private func parseCloudExec(_ arguments: [String]) -> ParseResult<CloudCommandAction> {
        var query: String?
        var environment: String?
        var branch: String?
        var attempts = 1
        var iterator = arguments.makeIterator()

        while let argument = iterator.next() {
            if argument == "--env" {
                guard let value = iterator.next() else {
                    return .failure("codex-swift: missing value for --env", 64)
                }
                environment = value
                continue
            }
            if argument.hasPrefix("--env=") {
                environment = String(argument.dropFirst("--env=".count))
                continue
            }
            if argument == "--branch" {
                guard let value = iterator.next() else {
                    return .failure("codex-swift: missing value for --branch", 64)
                }
                branch = value
                continue
            }
            if argument.hasPrefix("--branch=") {
                branch = String(argument.dropFirst("--branch=".count))
                continue
            }
            if argument == "--attempts" {
                guard let value = iterator.next() else {
                    return .failure("codex-swift: missing value for --attempts", 64)
                }
                switch parseCloudAttempt(value) {
                case let .success(parsed):
                    attempts = parsed
                case let .failure(message, exitCode):
                    return .failure(message, exitCode)
                }
                continue
            }
            if argument.hasPrefix("--attempts=") {
                let value = String(argument.dropFirst("--attempts=".count))
                switch parseCloudAttempt(value) {
                case let .success(parsed):
                    attempts = parsed
                case let .failure(message, exitCode):
                    return .failure(message, exitCode)
                }
                continue
            }
            if argument.hasPrefix("-") {
                return .failure("codex-swift: unsupported option for command 'cloud exec': \(argument)", 64)
            }
            if query != nil {
                return .failure("codex-swift: unexpected argument for command 'cloud exec': \(argument)", 64)
            }
            query = argument
        }

        guard let environment else {
            return .failure("codex-swift: missing required option for command 'cloud exec': --env <ENV_ID>", 64)
        }
        return .success(.exec(query: query, environment: environment, branch: branch, attempts: attempts))
    }

    private func parseCloudAttempt(_ value: String) -> ParseResult<Int> {
        guard let attempt = Int(value) else {
            return .failure("attempts must be an integer between 1 and 4", 64)
        }
        guard (1...4).contains(attempt) else {
            return .failure("attempts must be between 1 and 4", 64)
        }
        return .success(attempt)
    }

    private func parseCloudListLimit(_ value: String) -> ParseResult<Int> {
        guard let limit = Int(value) else {
            return .failure("limit must be an integer between 1 and 20", 64)
        }
        guard (1...20).contains(limit) else {
            return .failure("limit must be between 1 and 20", 64)
        }
        return .success(limit)
    }

    private func parsePluginCommandAction(_ arguments: [String]) -> ParseResult<PluginCommandAction> {
        guard let namespace = arguments.first else {
            return .failure("codex-swift: missing required subcommand for command 'plugin': marketplace", 64)
        }
        guard namespace == "marketplace" else {
            return .failure("codex-swift: unsupported plugin subcommand: \(namespace)", 64)
        }
        return parsePluginMarketplaceCommand(Array(arguments.dropFirst()))
    }

    private func parsePluginMarketplaceCommand(_ arguments: [String]) -> ParseResult<PluginCommandAction> {
        guard let subcommand = arguments.first else {
            return .failure("codex-swift: missing required subcommand for command 'plugin marketplace': add|upgrade|remove", 64)
        }
        let rest = Array(arguments.dropFirst())
        switch subcommand {
        case "add":
            return parsePluginMarketplaceAdd(rest)
        case "upgrade":
            return parsePluginMarketplaceUpgrade(rest)
        case "remove":
            return parsePluginMarketplaceRemove(rest)
        default:
            return .failure("codex-swift: unsupported plugin marketplace subcommand: \(subcommand)", 64)
        }
    }

    private func parsePluginMarketplaceAdd(_ arguments: [String]) -> ParseResult<PluginCommandAction> {
        var source: String?
        var refName: String?
        var sparsePaths: [String] = []
        var iterator = arguments.makeIterator()

        while let argument = iterator.next() {
            if argument == "--ref" {
                guard let value = iterator.next() else {
                    return .failure("codex-swift: missing value for --ref", 64)
                }
                refName = value
                continue
            }
            if argument.hasPrefix("--ref=") {
                refName = String(argument.dropFirst("--ref=".count))
                continue
            }
            if argument == "--sparse" {
                guard let value = iterator.next() else {
                    return .failure("codex-swift: missing value for --sparse", 64)
                }
                sparsePaths.append(value)
                continue
            }
            if argument.hasPrefix("--sparse=") {
                sparsePaths.append(String(argument.dropFirst("--sparse=".count)))
                continue
            }
            if argument.hasPrefix("-") {
                return .failure("codex-swift: unsupported option for command 'plugin marketplace add': \(argument)", 64)
            }
            if source != nil {
                return .failure("codex-swift: unexpected argument for command 'plugin marketplace add': \(argument)", 64)
            }
            source = argument
        }

        guard let source else {
            return .failure("codex-swift: missing required argument for command 'plugin marketplace add': <SOURCE>", 64)
        }
        return .success(.marketplaceAdd(source: source, refName: refName, sparsePaths: sparsePaths))
    }

    private func parsePluginMarketplaceUpgrade(_ arguments: [String]) -> ParseResult<PluginCommandAction> {
        var name: String?
        for argument in arguments {
            if argument.hasPrefix("-") {
                return .failure("codex-swift: unsupported option for command 'plugin marketplace upgrade': \(argument)", 64)
            }
            if name != nil {
                return .failure("codex-swift: unexpected argument for command 'plugin marketplace upgrade': \(argument)", 64)
            }
            name = argument
        }
        return .success(.marketplaceUpgrade(name: name))
    }

    private func parsePluginMarketplaceRemove(_ arguments: [String]) -> ParseResult<PluginCommandAction> {
        var name: String?
        for argument in arguments {
            if argument.hasPrefix("-") {
                return .failure("codex-swift: unsupported option for command 'plugin marketplace remove': \(argument)", 64)
            }
            if name != nil {
                return .failure("codex-swift: unexpected argument for command 'plugin marketplace remove': \(argument)", 64)
            }
            name = argument
        }
        guard let name else {
            return .failure("codex-swift: missing required argument for command 'plugin marketplace remove': <NAME>", 64)
        }
        return .success(.marketplaceRemove(name: name))
    }

    private func parseResponsesAPIProxyCommand(_ arguments: [String]) -> ParseResult<ResponsesAPIProxyCommandRequest> {
        var port: UInt16?
        var serverInfoPath: String?
        var httpShutdown = false
        var upstreamURL = "https://api.openai.com/v1/responses"
        var dumpDir: String?
        var iterator = arguments.makeIterator()

        while let argument = iterator.next() {
            if argument == "--port" {
                guard let value = iterator.next() else {
                    return .failure("codex-swift: missing value for --port", 64)
                }
                switch parseProxyPort(value) {
                case let .success(parsed):
                    port = parsed
                case let .failure(message, exitCode):
                    return .failure(message, exitCode)
                }
                continue
            }
            if argument.hasPrefix("--port=") {
                let value = String(argument.dropFirst("--port=".count))
                switch parseProxyPort(value) {
                case let .success(parsed):
                    port = parsed
                case let .failure(message, exitCode):
                    return .failure(message, exitCode)
                }
                continue
            }
            if argument == "--server-info" {
                guard let value = iterator.next() else {
                    return .failure("codex-swift: missing value for --server-info", 64)
                }
                serverInfoPath = value
                continue
            }
            if argument.hasPrefix("--server-info=") {
                serverInfoPath = String(argument.dropFirst("--server-info=".count))
                continue
            }
            if argument == "--http-shutdown" {
                httpShutdown = true
                continue
            }
            if argument == "--upstream-url" {
                guard let value = iterator.next() else {
                    return .failure("codex-swift: missing value for --upstream-url", 64)
                }
                upstreamURL = value
                continue
            }
            if argument.hasPrefix("--upstream-url=") {
                upstreamURL = String(argument.dropFirst("--upstream-url=".count))
                continue
            }
            if argument == "--dump-dir" {
                guard let value = iterator.next() else {
                    return .failure("codex-swift: missing value for --dump-dir", 64)
                }
                dumpDir = value
                continue
            }
            if argument.hasPrefix("--dump-dir=") {
                dumpDir = String(argument.dropFirst("--dump-dir=".count))
                continue
            }
            if argument.hasPrefix("-") {
                return .failure("codex-swift: unsupported option for command 'responses-api-proxy': \(argument)", 64)
            }
            return .failure("codex-swift: unexpected argument for command 'responses-api-proxy': \(argument)", 64)
        }

        return .success(ResponsesAPIProxyCommandRequest(
            port: port,
            serverInfoPath: serverInfoPath,
            httpShutdown: httpShutdown,
            upstreamURL: upstreamURL,
            dumpDir: dumpDir
        ))
    }

    private func parseProxyPort(_ value: String) -> ParseResult<UInt16> {
        guard let parsed = UInt16(value) else {
            return .failure("codex-swift: invalid value for --port: \(value)", 64)
        }
        return .success(parsed)
    }

    private func emit(_ result: CommandExecutionResult, stdout: (String) -> Void, stderr: (String) -> Void) {
        if let message = result.stdoutMessage {
            stdout(message)
        }
        if let message = result.stderrMessage {
            stderr(message)
        }
    }

    private func describe(_ error: Error) -> String {
        return String(describing: error)
    }
}

private enum ParseResult<Success> {
    case success(Success)
    case failure(String, Int32)

    func map<Next>(_ transform: (Success) -> Next) -> ParseResult<Next> {
        switch self {
        case let .success(value):
            return .success(transform(value))
        case let .failure(message, exitCode):
            return .failure(message, exitCode)
        }
    }
}
