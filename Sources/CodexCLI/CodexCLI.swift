import CodexCore
import Darwin
import Foundation

public struct CodexCLI: Sendable {
    public static let version = CodexBuildMetadata.version
    private static let approvalPolicyOptionDisplay = "--ask-for-approval <APPROVAL_POLICY>"
    private static let dangerouslyBypassOptionDisplay = "--dangerously-bypass-approvals-and-sandbox"

    public init() {}

    public enum Invocation: Equatable, Sendable {
        case help
        case commandHelp(CommandSpec, arguments: [String])
        case version
        case commandVersion(CommandSpec)
        case commandUnsupportedVersion(CommandSpec, flag: String)
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
        case withAccessTokenFromStdin
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
        public let configProfileV2: String?
        public let removedFullAuto: Bool
        public let strictConfig: Bool
        public let bypassHookTrust: Bool

        public init(
            json: Bool = false,
            imagePaths: [String] = [],
            outputSchemaPath: String? = nil,
            lastMessageFile: String? = nil,
            skipGitRepoCheck: Bool = false,
            ephemeral: Bool = false,
            ignoreUserConfig: Bool = false,
            ignoreRules: Bool = false,
            configProfileV2: String? = nil,
            removedFullAuto: Bool = false,
            strictConfig: Bool = false,
            bypassHookTrust: Bool = false
        ) {
            self.json = json
            self.imagePaths = imagePaths
            self.outputSchemaPath = outputSchemaPath
            self.lastMessageFile = lastMessageFile
            self.skipGitRepoCheck = skipGitRepoCheck
            self.ephemeral = ephemeral
            self.ignoreUserConfig = ignoreUserConfig
            self.ignoreRules = ignoreRules
            self.configProfileV2 = configProfileV2
            self.removedFullAuto = removedFullAuto
            self.strictConfig = strictConfig
            self.bypassHookTrust = bypassHookTrust
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
        public let configProfileV2: String?
        public let configOverrides: CliConfigOverrides
        public let strictConfig: Bool

        public init(
            target: ReviewCommandTarget,
            configProfileV2: String? = nil,
            configOverrides: CliConfigOverrides = CliConfigOverrides(),
            strictConfig: Bool = false
        ) {
            self.target = target
            self.configProfileV2 = configProfileV2
            self.configOverrides = configOverrides
            self.strictConfig = strictConfig
        }
    }

    public struct InteractiveCommandOptions: Equatable, Sendable {
        public let imagePaths: [String]
        public let model: String?
        public let useOSSProvider: Bool
        public let localProvider: String?
        public let configProfile: String?
        public let configProfileV2: String?
        public let sandboxMode: String?
        public let dangerouslyBypassApprovalsAndSandbox: Bool
        public let cwd: String?
        public let additionalWritableRoots: [String]
        public let approvalPolicy: String?
        public let searchEnabled: Bool
        public let noAltScreen: Bool
        public let bypassHookTrust: Bool
        public let ephemeral: Bool
        public let ignoreUserConfig: Bool
        public let ignoreRules: Bool

        public init(
            imagePaths: [String] = [],
            model: String? = nil,
            useOSSProvider: Bool = false,
            localProvider: String? = nil,
            configProfile: String? = nil,
            configProfileV2: String? = nil,
            sandboxMode: String? = nil,
            dangerouslyBypassApprovalsAndSandbox: Bool = false,
            cwd: String? = nil,
            additionalWritableRoots: [String] = [],
            approvalPolicy: String? = nil,
            searchEnabled: Bool = false,
            noAltScreen: Bool = false,
            bypassHookTrust: Bool = false,
            ephemeral: Bool = false,
            ignoreUserConfig: Bool = false,
            ignoreRules: Bool = false
        ) {
            self.imagePaths = imagePaths
            self.model = model
            self.useOSSProvider = useOSSProvider
            self.localProvider = localProvider
            self.configProfile = configProfile
            self.configProfileV2 = configProfileV2
            self.sandboxMode = sandboxMode
            self.dangerouslyBypassApprovalsAndSandbox = dangerouslyBypassApprovalsAndSandbox
            self.cwd = cwd
            self.additionalWritableRoots = additionalWritableRoots
            self.approvalPolicy = approvalPolicy
            self.searchEnabled = searchEnabled
            self.noAltScreen = noAltScreen
            self.bypassHookTrust = bypassHookTrust
            self.ephemeral = ephemeral
            self.ignoreUserConfig = ignoreUserConfig
            self.ignoreRules = ignoreRules
        }
    }

    public struct InteractiveCommandRequest: Equatable, Sendable {
        public let prompt: String?
        public let remote: String?
        public let remoteAuthTokenEnv: String?
        public let interactiveOptions: InteractiveCommandOptions
        public let configOverrides: CliConfigOverrides
        public let strictConfig: Bool

        public init(
            prompt: String? = nil,
            remote: String? = nil,
            remoteAuthTokenEnv: String? = nil,
            interactiveOptions: InteractiveCommandOptions = InteractiveCommandOptions(),
            configOverrides: CliConfigOverrides = CliConfigOverrides(),
            strictConfig: Bool = false
        ) {
            self.prompt = prompt
            self.remote = remote
            self.remoteAuthTokenEnv = remoteAuthTokenEnv
            self.interactiveOptions = interactiveOptions
            self.configOverrides = configOverrides
            self.strictConfig = strictConfig
        }
    }

    public struct ResumeCommandRequest: Equatable, Sendable {
        public let sessionID: String?
        public let last: Bool
        public let all: Bool
        public let includeNonInteractive: Bool
        public let remote: String?
        public let remoteAuthTokenEnv: String?
        public let interactiveOptions: InteractiveCommandOptions
        public let configOverrides: CliConfigOverrides
        public let strictConfig: Bool

        public init(
            sessionID: String?,
            last: Bool,
            all: Bool,
            includeNonInteractive: Bool = false,
            remote: String? = nil,
            remoteAuthTokenEnv: String? = nil,
            interactiveOptions: InteractiveCommandOptions = InteractiveCommandOptions(),
            configOverrides: CliConfigOverrides = CliConfigOverrides(),
            strictConfig: Bool = false
        ) {
            self.sessionID = sessionID
            self.last = last
            self.all = all
            self.includeNonInteractive = includeNonInteractive
            self.remote = remote
            self.remoteAuthTokenEnv = remoteAuthTokenEnv
            self.interactiveOptions = interactiveOptions
            self.configOverrides = configOverrides
            self.strictConfig = strictConfig
        }
    }

    public struct ForkCommandRequest: Equatable, Sendable {
        public let sessionID: String?
        public let last: Bool
        public let all: Bool
        public let remote: String?
        public let remoteAuthTokenEnv: String?
        public let interactiveOptions: InteractiveCommandOptions
        public let configOverrides: CliConfigOverrides
        public let strictConfig: Bool

        public init(
            sessionID: String?,
            last: Bool,
            all: Bool,
            remote: String? = nil,
            remoteAuthTokenEnv: String? = nil,
            interactiveOptions: InteractiveCommandOptions = InteractiveCommandOptions(),
            configOverrides: CliConfigOverrides = CliConfigOverrides(),
            strictConfig: Bool = false
        ) {
            self.sessionID = sessionID
            self.last = last
            self.all = all
            self.remote = remote
            self.remoteAuthTokenEnv = remoteAuthTokenEnv
            self.interactiveOptions = interactiveOptions
            self.configOverrides = configOverrides
            self.strictConfig = strictConfig
        }
    }

    public enum ExecServerCommandAction: Equatable, Sendable {
        case listen(url: String)
        case remote(baseURL: String, executorID: String, name: String?, useAgentIdentityAuth: Bool)
    }

    public struct ExecServerCommandRequest: Equatable, Sendable {
        public let action: ExecServerCommandAction
        public let configProfileV2: String?
        public let configOverrides: CliConfigOverrides

        public init(
            action: ExecServerCommandAction,
            configProfileV2: String? = nil,
            configOverrides: CliConfigOverrides = CliConfigOverrides()
        ) {
            self.action = action
            self.configProfileV2 = configProfileV2
            self.configOverrides = configOverrides
        }
    }

    public struct McpServerCommandRequest: Equatable, Sendable {
        public let configOverrides: CliConfigOverrides
        public let strictConfig: Bool

        public init(
            configOverrides: CliConfigOverrides = CliConfigOverrides(),
            strictConfig: Bool = false
        ) {
            self.configOverrides = configOverrides
            self.strictConfig = strictConfig
        }
    }

    public enum AppServerCommandAction: Equatable, Sendable {
        case run
        case remoteControl
        case remoteControlStop
        case daemonStart
        case daemonRestart
        case daemonBootstrap(remoteControlEnabled: Bool)
        case daemonEnableRemoteControl
        case daemonDisableRemoteControl
        case daemonStop
        case daemonVersion
        case daemonPidUpdateLoop
        case proxy(socketPath: String?)
        case generateTS(outDir: String, prettier: String?, experimental: Bool)
        case generateJSONSchema(outDir: String, experimental: Bool)
        case generateInternalJSONSchema(outDir: String)
    }

    public struct AppServerCommandRequest: Equatable, Sendable {
        public let action: AppServerCommandAction
        public let listenTransport: AppServerListenTransport
        public let sessionSource: SessionSource
        public let analyticsDefaultEnabled: Bool
        public let remoteControlEnabled: Bool
        public let websocketAuth: AppServerWebsocketAuthArguments
        public let configOverrides: CliConfigOverrides
        public let strictConfig: Bool

        public init(
            action: AppServerCommandAction,
            listenTransport: AppServerListenTransport = .stdio,
            sessionSource: SessionSource = .vscode,
            analyticsDefaultEnabled: Bool = false,
            remoteControlEnabled: Bool = false,
            websocketAuth: AppServerWebsocketAuthArguments = AppServerWebsocketAuthArguments(),
            configOverrides: CliConfigOverrides = CliConfigOverrides(),
            strictConfig: Bool = false
        ) {
            self.action = action
            self.listenTransport = listenTransport
            self.sessionSource = sessionSource
            self.analyticsDefaultEnabled = analyticsDefaultEnabled
            self.remoteControlEnabled = remoteControlEnabled
            self.websocketAuth = websocketAuth
            self.configOverrides = configOverrides
            self.strictConfig = strictConfig
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
            case ":danger-full-access":
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
        public let configProfileV2: String?
        public let configOverrides: CliConfigOverrides

        public init(
            action: DebugCommandAction,
            configProfileV2: String? = nil,
            configOverrides: CliConfigOverrides = CliConfigOverrides()
        ) {
            self.action = action
            self.configProfileV2 = configProfileV2
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
        case add(plugin: String, marketplaceName: String?)
        case list(marketplaceName: String?)
        case marketplaceAdd(source: String, refName: String?, sparsePaths: [String])
        case marketplaceList
        case marketplaceUpgrade(name: String?)
        case marketplaceRemove(name: String)
        case remove(plugin: String, marketplaceName: String?)
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

    public struct DoctorCommandRequest: Equatable, Sendable {
        public let json: Bool
        public let summary: Bool
        public let all: Bool
        public let noColor: Bool
        public let ascii: Bool
        public let configOverrides: CliConfigOverrides

        public init(
            json: Bool = false,
            summary: Bool = false,
            all: Bool = false,
            noColor: Bool = false,
            ascii: Bool = false,
            configOverrides: CliConfigOverrides = CliConfigOverrides()
        ) {
            self.json = json
            self.summary = summary
            self.all = all
            self.noColor = noColor
            self.ascii = ascii
            self.configOverrides = configOverrides
        }
    }

    public struct CommandExecutionResult: Equatable, Sendable {
        public let exitCode: Int32
        public let stdoutMessage: String?
        public let stderrMessage: String?
        public let threadID: String?

        public init(exitCode: Int32, stdoutMessage: String? = nil, stderrMessage: String? = nil, threadID: String? = nil) {
            self.exitCode = exitCode
            self.stdoutMessage = stdoutMessage
            self.stderrMessage = stderrMessage
            self.threadID = threadID
        }
    }

    public typealias ApplyCommandRunner = (ApplyCommandRequest) async throws -> String?
    public typealias LoginCommandRunner = (LoginCommandRequest) async throws -> CommandExecutionResult
    public typealias LogoutCommandRunner = (LogoutCommandRequest) async throws -> CommandExecutionResult
    public typealias FeaturesCommandRunner = (FeaturesCommandRequest) async throws -> CommandExecutionResult
    public typealias ExecCommandRunner = (ExecCommandRequest) async throws -> CommandExecutionResult
    public typealias ComputerUseCommandRunner = (ComputerUseCommandRequest) async throws -> CommandExecutionResult
    public typealias ReviewCommandRunner = (ReviewCommandRequest) async throws -> CommandExecutionResult
    public typealias InteractiveCommandRunner = (InteractiveCommandRequest) async throws -> CommandExecutionResult
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
    public typealias DoctorCommandRunner = (DoctorCommandRequest) async throws -> CommandExecutionResult

    private enum ExplicitFlagTarget {
        case root
        case command(CommandSpec, arguments: [String])
    }

    public func parseInvocation(arguments: [String]) -> Invocation {
        if let helpTarget = explicitHelpTarget(arguments) {
            switch helpTarget {
            case .root:
                return .help
            case let .command(spec, arguments):
                return .commandHelp(spec, arguments: arguments)
            }
        }
        if let versionTarget = explicitVersionTarget(arguments) {
            switch versionTarget {
            case .root:
                return .version
            case let .command(spec, arguments):
                if spec.name == "exec" {
                    return .commandVersion(spec)
                }
                let flag = arguments.first(where: { $0 == "--version" || $0 == "-V" }) ?? "--version"
                return .commandUnsupportedVersion(spec, flag: flag)
            }
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

    private func explicitHelpTarget(_ arguments: [String]) -> ExplicitFlagTarget? {
        if arguments.first == "help" {
            let targetArguments = Array(arguments.dropFirst())
            if let commandToken = targetArguments.first,
               let spec = CodexCommandRegistry.command(matching: commandToken) {
                return .command(spec, arguments: Array(targetArguments.dropFirst()))
            }
            return .root
        }

        guard let helpIndex = arguments.firstIndex(where: { $0 == "--help" || $0 == "-h" }) else {
            return nil
        }
        guard let commandMatch = commandMatch(in: arguments), commandMatch.index < helpIndex else {
            return .root
        }
        return .command(commandMatch.spec, arguments: Array(arguments.dropFirst(commandMatch.index + 1)))
    }

    private func explicitVersionTarget(_ arguments: [String]) -> ExplicitFlagTarget? {
        guard let versionIndex = arguments.firstIndex(where: { $0 == "--version" || $0 == "-V" }) else {
            return nil
        }
        guard let commandMatch = commandMatch(in: arguments), commandMatch.index < versionIndex else {
            return .root
        }
        return .command(commandMatch.spec, arguments: Array(arguments.dropFirst(commandMatch.index + 1)))
    }

    private func commandMatch(in arguments: [String]) -> (index: Int, spec: CommandSpec)? {
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            if argument == "--" {
                return nil
            }
            if optionConsumesValue(argument) {
                index += 2
                continue
            }
            if argument.hasPrefix("-") {
                index += 1
                continue
            }
            if let spec = CodexCommandRegistry.command(matching: argument) {
                return (index, spec)
            }
            return nil
        }
        return nil
    }

    public func command(for arguments: [String]) -> CommandSpec? {
        if case let .command(spec, _) = parseInvocation(arguments: arguments) {
            return spec
        }
        return nil
    }

    public func renderHelp(for spec: CommandSpec, arguments: [String] = []) -> String {
        switch spec.name {
        case "exec":
            return renderExecHelp()
        case "review":
            return renderReviewHelp()
        case "login":
            return renderLoginHelp()
        case "logout":
            return renderLogoutHelp()
        case "mcp":
            if let childHelp = renderMcpChildHelp(arguments: arguments) {
                return childHelp
            }
            return renderMcpHelp()
        case "plugin":
            if let childHelp = renderPluginChildHelp(arguments: arguments) {
                return childHelp
            }
            return renderPluginHelp()
        case "mcp-server":
            return renderMcpServerHelp()
        case "app-server":
            return renderAppServerHelp()
        case "remote-control":
            return renderRemoteControlHelp()
        case "app":
            return renderAppHelp()
        case "completion":
            return renderCompletionHelp()
        case "update":
            return renderUpdateHelp()
        case "doctor":
            return renderDoctorHelp()
        case "sandbox":
            return renderSandboxHelp()
        case "debug":
            return renderDebugHelp()
        case "execpolicy":
            return renderExecPolicyHelp()
        case "apply":
            return renderApplyHelp()
        case "resume":
            return renderResumeHelp()
        case "fork":
            return renderForkHelp()
        case "cloud":
            return renderCloudHelp()
        case "responses-api-proxy":
            return renderResponsesAPIProxyHelp()
        case "stdio-to-uds":
            return renderStdioToUDSHelp()
        case "exec-server":
            return renderExecServerHelp()
        case "features":
            return renderFeaturesHelp()
        default:
            return renderHelp()
        }
    }

    public func renderHelp(includeHidden: Bool = false) -> String {
        guard includeHidden else {
            return """
            Codex CLI

            If no subcommand is specified, options will be forwarded to the interactive CLI.

            Usage: codex [OPTIONS] [PROMPT]
                   codex [OPTIONS] <COMMAND> [ARGS]

            Commands:
              exec            Run Codex non-interactively [aliases: e]
              review          Run a code review non-interactively
              login           Manage login
              logout          Remove stored authentication credentials
              mcp             Manage external MCP servers for Codex
              plugin          Manage Codex plugins
              mcp-server      Start Codex as an MCP server (stdio)
              app-server      [experimental] Run the app server or related tooling
              remote-control  [experimental] Manage the app-server daemon with remote control enabled
              app             Launch the Codex desktop app (opens the app installer if missing)
              completion      Generate shell completion scripts
              update          Update Codex to the latest version
              doctor          Diagnose local Codex installation, config, auth, and runtime health
              sandbox         Run commands within a Codex-provided sandbox
              debug           Debugging tools
              apply           Apply the latest diff produced by Codex agent as a `git apply` to your local
                              working tree [aliases: a]
              resume          Resume a previous interactive session (picker by default; use --last to continue
                              the most recent)
              fork            Fork a previous interactive session (picker by default; use --last to fork the
                              most recent)
              cloud           [EXPERIMENTAL] Browse tasks from Codex Cloud and apply changes locally
              exec-server     [EXPERIMENTAL] Run the standalone exec-server service
              features        Inspect feature flags
              help            Print this message or the help of the given subcommand(s)

            Arguments:
              [PROMPT]
                      Optional user prompt to start the session

            Options:
              -c, --config <key=value>
                      Override a configuration value that would otherwise be loaded from `~/.codex/config.toml`.
                      Use a dotted path (`foo.bar.baz`) to override nested values. The `value` portion is parsed
                      as TOML. If it fails to parse as TOML, the raw string is used as a literal.

                      Examples: - `-c model="o3"` - `-c 'sandbox_permissions=["disk-full-read-access"]'` - `-c
                      shell_environment_policy.inherit=all`

                  --enable <FEATURE>
                      Enable a feature (repeatable). Equivalent to `-c features.<name>=true`

                  --disable <FEATURE>
                      Disable a feature (repeatable). Equivalent to `-c features.<name>=false`

                  --remote <ADDR>
                      Connect the TUI to a remote app server endpoint.

                      Accepted forms: `ws://host:port`, `wss://host:port`, `unix://`, or `unix://PATH`.

                  --remote-auth-token-env <ENV_VAR>
                      Name of the environment variable containing the bearer token to send to a remote app
                      server websocket

                  --strict-config
                      Error out when config.toml contains fields that are not recognized by this version of
                      Codex

              -i, --image <FILE>...
                      Optional image(s) to attach to the initial prompt

              -m, --model <MODEL>
                      Model the agent should use

                  --oss
                      Use open-source provider

                  --local-provider <OSS_PROVIDER>
                      Specify which local provider to use (lmstudio or ollama). If not specified with --oss,
                      will use config default or show selection

              -p, --profile <CONFIG_PROFILE>
                      Configuration profile from config.toml to specify default options

                  --profile-v2 <CONFIG_PROFILE_V2>
                      Layer $CODEX_HOME/<name>.config.toml on top of the base user config

              -s, --sandbox <SANDBOX_MODE>
                      Select the sandbox policy to use when executing model-generated shell commands

                      [possible values: read-only, workspace-write, danger-full-access]

                  --dangerously-bypass-approvals-and-sandbox
                      Skip all confirmation prompts and execute commands without sandboxing. EXTREMELY
                      DANGEROUS. Intended solely for running in environments that are externally sandboxed

                  --dangerously-bypass-hook-trust
                      Run enabled hooks without requiring persisted hook trust for this invocation. DANGEROUS.
                      Intended only for automation that already vets hook sources

              -C, --cd <DIR>
                      Tell the agent to use the specified directory as its working root

                  --add-dir <DIR>
                      Additional directories that should be writable alongside the primary workspace

              -a, --ask-for-approval <APPROVAL_POLICY>
                      Configure when the model requires human approval before executing a command

                      Possible values:
                      - untrusted:  Only run "trusted" commands (e.g. ls, cat, sed) without asking for user
                        approval. Will escalate to the user if the model proposes a command that is not in the
                        "trusted" set
                      - on-failure: DEPRECATED: Run all commands without asking for user approval. Only asks for
                        approval if a command fails to execute, in which case it will escalate to the user to
                        ask for un-sandboxed execution. Prefer `on-request` for interactive runs or `never` for
                        non-interactive runs
                      - on-request: The model decides when to ask the user for approval
                      - never:      Never ask for user approval Execution failures are immediately returned to
                        the model

                  --search
                      Enable live web search. When enabled, the native Responses `web_search` tool is available
                      to the model (no per-call approval)

                  --no-alt-screen
                      Disable alternate screen mode

                      Runs the TUI in inline mode, preserving terminal scrollback history.

              -h, --help
                      Print help (see a summary with '-h')

              -V, --version
                      Print version
            """
        }

        let commandLines = CodexCommandRegistry.commands
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
          --profile-v2 <PROFILE>            Layer $CODEX_HOME/<PROFILE>.config.toml.
          -s, --sandbox <MODE>              Sandbox policy for model-generated shell commands.
          -a, --ask-for-approval <POLICY>   Configure command approval policy.
          --dangerously-bypass-approvals-and-sandbox
                                            Skip confirmations and sandboxing.
          --dangerously-bypass-hook-trust   Run enabled hooks without persisted trust.
          -C, --cd <DIR>                    Working root for the session.
          --search                          Enable web search.
          --add-dir <DIR>                   Additional writable directory.
          -i, --image <FILE>                Attach image(s) to the initial prompt.
          --ephemeral                       Run without persisting session files.
          --ignore-user-config              Do not load $CODEX_HOME/config.toml.
          --ignore-rules                    Do not load user or project rules files.
          --strict-config                   Fail when config files contain unknown fields.
          -h, --help                        Print help.
          -V, --version                     Print version.

        Commands:
        \(commandLines)
        """
    }

    public func renderVersion() -> String {
        "codex \(Self.version)"
    }

    public func renderVersion(for spec: CommandSpec) -> String {
        switch spec.name {
        case "exec":
            return "codex-cli-exec \(Self.version)"
        default:
            return "\(spec.name) \(Self.version)"
        }
    }

    public func renderUnsupportedVersionError(for spec: CommandSpec, flag: String) -> String {
        let tip = switch spec.name {
        case "review", "completion", "apply", "exec":
            "\n\n  tip: to pass '\(flag)' as a value, use '-- \(flag)'"
        default:
            ""
        }
        return """
        error: unexpected argument '\(flag)' found\(tip)

        Usage: \(usageLine(forUnsupportedVersion: spec))

        For more information, try '--help'.
        """
    }

    private func usageLine(forUnsupportedVersion spec: CommandSpec) -> String {
        switch spec.name {
        case "review":
            return "codex review [OPTIONS] [PROMPT]"
        case "completion":
            return "codex completion [OPTIONS] [SHELL]"
        case "mcp":
            return "codex mcp [OPTIONS] <COMMAND>"
        case "plugin":
            return "codex plugin [OPTIONS] <COMMAND>"
        case "app-server":
            return "codex app-server [OPTIONS] <COMMAND>"
        case "remote-control":
            return "codex remote-control [OPTIONS] <COMMAND>"
        case "features":
            return "codex features [OPTIONS] <COMMAND>"
        case "apply":
            return "codex apply [OPTIONS] [TASK_ID]"
        default:
            return "codex \(spec.name) [OPTIONS]"
        }
    }

    private func renderExecHelp() -> String {
        """
        Run Codex non-interactively

        Usage: codex exec [OPTIONS] [PROMPT]
               codex exec [OPTIONS] <COMMAND> [ARGS]

        Commands:
          resume  Resume a previous session by id or pick the most recent with --last
          review  Run a code review against the current repository
          help    Print this message or the help of the given subcommand(s)

        Arguments:
          [PROMPT]
                  Initial instructions for the agent. If not provided as an argument (or if `-` is used),
                  instructions are read from stdin. If stdin is piped and a prompt is also provided, stdin
                  is appended as a `<stdin>` block

        Options:
          -c, --config <key=value>
                  Override a configuration value that would otherwise be loaded from `~/.codex/config.toml`.
                  Use a dotted path (`foo.bar.baz`) to override nested values. The `value` portion is parsed
                  as TOML. If it fails to parse as TOML, the raw string is used as a literal.

                  Examples: - `-c model="o3"` - `-c 'sandbox_permissions=["disk-full-read-access"]'` - `-c
                  shell_environment_policy.inherit=all`

              --enable <FEATURE>
                  Enable a feature (repeatable). Equivalent to `-c features.<name>=true`

              --disable <FEATURE>
                  Disable a feature (repeatable). Equivalent to `-c features.<name>=false`

              --strict-config
                  Error out when config.toml contains fields that are not recognized by this version of
                  Codex

          -i, --image <FILE>...
                  Optional image(s) to attach to the initial prompt

          -m, --model <MODEL>
                  Model the agent should use

              --oss
                  Use open-source provider

              --local-provider <OSS_PROVIDER>
                  Specify which local provider to use (lmstudio or ollama). If not specified with --oss,
                  will use config default or show selection

          -p, --profile <CONFIG_PROFILE>
                  Configuration profile from config.toml to specify default options

              --profile-v2 <CONFIG_PROFILE_V2>
                  Layer $CODEX_HOME/<name>.config.toml on top of the base user config

          -s, --sandbox <SANDBOX_MODE>
                  Select the sandbox policy to use when executing model-generated shell commands

                  [possible values: read-only, workspace-write, danger-full-access]

              --dangerously-bypass-approvals-and-sandbox
                  Skip all confirmation prompts and execute commands without sandboxing. EXTREMELY
                  DANGEROUS. Intended solely for running in environments that are externally sandboxed

              --dangerously-bypass-hook-trust
                  Run enabled hooks without requiring persisted hook trust for this invocation. DANGEROUS.
                  Intended only for automation that already vets hook sources

          -C, --cd <DIR>
                  Tell the agent to use the specified directory as its working root

              --add-dir <DIR>
                  Additional directories that should be writable alongside the primary workspace

              --skip-git-repo-check
                  Allow running Codex outside a Git repository

              --ephemeral
                  Run without persisting session files to disk

              --ignore-user-config
                  Do not load `$CODEX_HOME/config.toml`; auth still uses `CODEX_HOME`

              --ignore-rules
                  Do not load user or project execpolicy `.rules` files

              --output-schema <FILE>
                  Path to a JSON Schema file describing the model's final response shape

              --color <COLOR>
                  Specifies color settings for use in the output

                  [default: auto]
                  [possible values: always, never, auto]

              --json
                  Print events to stdout as JSONL

          -o, --output-last-message <FILE>
                  Specifies file where the last message from the agent should be written

          -h, --help
                  Print help (see a summary with '-h')

          -V, --version
                  Print version
        """
    }

    private func renderReviewHelp() -> String {
        """
        Run a code review non-interactively

        Usage: codex review [OPTIONS] [PROMPT]

        Arguments:
          [PROMPT]
                  Custom review instructions. If `-` is used, read from stdin

        Options:
          -c, --config <key=value>
                  Override a configuration value that would otherwise be loaded from `~/.codex/config.toml`.
                  Use a dotted path (`foo.bar.baz`) to override nested values. The `value` portion is parsed
                  as TOML. If it fails to parse as TOML, the raw string is used as a literal.

                  Examples: - `-c model="o3"` - `-c 'sandbox_permissions=["disk-full-read-access"]'` - `-c
                  shell_environment_policy.inherit=all`

              --strict-config
                  Error out when config.toml contains fields that are not recognized by this version of
                  Codex

              --enable <FEATURE>
                  Enable a feature (repeatable). Equivalent to `-c features.<name>=true`

              --uncommitted
                  Review staged, unstaged, and untracked changes

              --base <BRANCH>
                  Review changes against the given base branch

              --disable <FEATURE>
                  Disable a feature (repeatable). Equivalent to `-c features.<name>=false`

              --commit <SHA>
                  Review the changes introduced by a commit

              --title <TITLE>
                  Optional commit title to display in the review summary

          -h, --help
                  Print help (see a summary with '-h')
        """
    }

    private func renderCompletionHelp() -> String {
        """
        Generate shell completion scripts

        Usage: codex completion [OPTIONS] [SHELL]

        Arguments:
          [SHELL]
                  Shell to generate completions for

                  [default: bash]
                  [possible values: bash, elvish, fish, powershell, zsh]

        Options:
          -c, --config <key=value>
                  Override a configuration value that would otherwise be loaded from `~/.codex/config.toml`.
                  Use a dotted path (`foo.bar.baz`) to override nested values. The `value` portion is parsed
                  as TOML. If it fails to parse as TOML, the raw string is used as a literal.

                  Examples: - `-c model="o3"` - `-c 'sandbox_permissions=["disk-full-read-access"]'` - `-c
                  shell_environment_policy.inherit=all`

              --enable <FEATURE>
                  Enable a feature (repeatable). Equivalent to `-c features.<name>=true`

              --disable <FEATURE>
                  Disable a feature (repeatable). Equivalent to `-c features.<name>=false`

          -h, --help
                  Print help (see a summary with '-h')
        """
    }

    private func renderLoginHelp() -> String {
        """
        Manage login

        Usage: codex login [OPTIONS] [COMMAND]

        Commands:
          status  Show login status
          help    Print this message or the help of the given subcommand(s)

        Options:
          -c, --config <key=value>
                  Override a configuration value that would otherwise be loaded from `~/.codex/config.toml`.
                  Use a dotted path (`foo.bar.baz`) to override nested values. The `value` portion is parsed
                  as TOML. If it fails to parse as TOML, the raw string is used as a literal.

                  Examples: - `-c model="o3"` - `-c 'sandbox_permissions=["disk-full-read-access"]'` - `-c
                  shell_environment_policy.inherit=all`

              --with-api-key
                  Read the API key from stdin (e.g. `printenv OPENAI_API_KEY | codex login --with-api-key`)

              --enable <FEATURE>
                  Enable a feature (repeatable). Equivalent to `-c features.<name>=true`

              --with-access-token
                  Read the access token from stdin (e.g. `printenv CODEX_ACCESS_TOKEN | codex login
                  --with-access-token`)

              --disable <FEATURE>
                  Disable a feature (repeatable). Equivalent to `-c features.<name>=false`

              --device-auth


          -h, --help
                  Print help (see a summary with '-h')
        """
    }

    private func renderLogoutHelp() -> String {
        """
        Remove stored authentication credentials

        Usage: codex logout [OPTIONS]

        Options:
          -c, --config <key=value>
                  Override a configuration value that would otherwise be loaded from `~/.codex/config.toml`.
                  Use a dotted path (`foo.bar.baz`) to override nested values. The `value` portion is parsed
                  as TOML. If it fails to parse as TOML, the raw string is used as a literal.

                  Examples: - `-c model="o3"` - `-c 'sandbox_permissions=["disk-full-read-access"]'` - `-c
                  shell_environment_policy.inherit=all`

              --enable <FEATURE>
                  Enable a feature (repeatable). Equivalent to `-c features.<name>=true`

              --disable <FEATURE>
                  Disable a feature (repeatable). Equivalent to `-c features.<name>=false`

          -h, --help
                  Print help (see a summary with '-h')
        """
    }

    private func renderMcpHelp() -> String {
        """
        Manage external MCP servers for Codex

        Usage: codex mcp [OPTIONS] <COMMAND>

        Commands:
          list
          get
          add
          remove
          login
          logout
          help    Print this message or the help of the given subcommand(s)

        Options:
          -c, --config <key=value>
                  Override a configuration value that would otherwise be loaded from `~/.codex/config.toml`.
                  Use a dotted path (`foo.bar.baz`) to override nested values. The `value` portion is parsed
                  as TOML. If it fails to parse as TOML, the raw string is used as a literal.

                  Examples: - `-c model="o3"` - `-c 'sandbox_permissions=["disk-full-read-access"]'` - `-c
                  shell_environment_policy.inherit=all`

              --enable <FEATURE>
                  Enable a feature (repeatable). Equivalent to `-c features.<name>=true`

              --disable <FEATURE>
                  Disable a feature (repeatable). Equivalent to `-c features.<name>=false`

          -h, --help
                  Print help (see a summary with '-h')
        """
    }

    private func renderMcpChildHelp(arguments: [String]) -> String? {
        guard let child = arguments.first, child != "--help", child != "-h" else {
            return nil
        }

        switch child {
        case "list":
            return """
            Usage: codex mcp list [OPTIONS]

            Options:
              -c, --config <key=value>
                      Override a configuration value that would otherwise be loaded from `~/.codex/config.toml`.
                      Use a dotted path (`foo.bar.baz`) to override nested values. The `value` portion is parsed
                      as TOML. If it fails to parse as TOML, the raw string is used as a literal.

                      Examples: - `-c model="o3"` - `-c 'sandbox_permissions=["disk-full-read-access"]'` - `-c
                      shell_environment_policy.inherit=all`

                  --json
                      Output the configured servers as JSON

                  --enable <FEATURE>
                      Enable a feature (repeatable). Equivalent to `-c features.<name>=true`

                  --disable <FEATURE>
                      Disable a feature (repeatable). Equivalent to `-c features.<name>=false`

              -h, --help
                      Print help (see a summary with '-h')
            """
        case "get":
            return """
            Usage: codex mcp get [OPTIONS] <NAME>

            Arguments:
              <NAME>
                      Name of the MCP server to display

            Options:
              -c, --config <key=value>
                      Override a configuration value that would otherwise be loaded from `~/.codex/config.toml`.
                      Use a dotted path (`foo.bar.baz`) to override nested values. The `value` portion is parsed
                      as TOML. If it fails to parse as TOML, the raw string is used as a literal.

                      Examples: - `-c model="o3"` - `-c 'sandbox_permissions=["disk-full-read-access"]'` - `-c
                      shell_environment_policy.inherit=all`

                  --json
                      Output the server configuration as JSON

                  --enable <FEATURE>
                      Enable a feature (repeatable). Equivalent to `-c features.<name>=true`

                  --disable <FEATURE>
                      Disable a feature (repeatable). Equivalent to `-c features.<name>=false`

              -h, --help
                      Print help (see a summary with '-h')
            """
        case "add":
            return """
            Usage: codex mcp add [OPTIONS] <NAME> (--url <URL> | -- <COMMAND>...)

            Arguments:
              <NAME>
                      Name for the MCP server configuration

              [COMMAND]...
                      Command to launch the MCP server. Use --url for a streamable HTTP server

            Options:
              -c, --config <key=value>
                      Override a configuration value that would otherwise be loaded from `~/.codex/config.toml`.
                      Use a dotted path (`foo.bar.baz`) to override nested values. The `value` portion is parsed
                      as TOML. If it fails to parse as TOML, the raw string is used as a literal.

                      Examples: - `-c model="o3"` - `-c 'sandbox_permissions=["disk-full-read-access"]'` - `-c
                      shell_environment_policy.inherit=all`

                  --env <KEY=VALUE>
                      Environment variables to set when launching the server. Only valid with stdio servers

                  --enable <FEATURE>
                      Enable a feature (repeatable). Equivalent to `-c features.<name>=true`

                  --url <URL>
                      URL for a streamable HTTP MCP server

                  --bearer-token-env-var <ENV_VAR>
                      Optional environment variable to read for a bearer token. Only valid with streamable HTTP
                      servers

                  --disable <FEATURE>
                      Disable a feature (repeatable). Equivalent to `-c features.<name>=false`

              -h, --help
                      Print help (see a summary with '-h')
            """
        case "remove":
            return """
            Usage: codex mcp remove [OPTIONS] <NAME>

            Arguments:
              <NAME>
                      Name of the MCP server configuration to remove

            Options:
              -c, --config <key=value>
                      Override a configuration value that would otherwise be loaded from `~/.codex/config.toml`.
                      Use a dotted path (`foo.bar.baz`) to override nested values. The `value` portion is parsed
                      as TOML. If it fails to parse as TOML, the raw string is used as a literal.

                      Examples: - `-c model="o3"` - `-c 'sandbox_permissions=["disk-full-read-access"]'` - `-c
                      shell_environment_policy.inherit=all`

                  --enable <FEATURE>
                      Enable a feature (repeatable). Equivalent to `-c features.<name>=true`

                  --disable <FEATURE>
                      Disable a feature (repeatable). Equivalent to `-c features.<name>=false`

              -h, --help
                      Print help (see a summary with '-h')
            """
        case "login":
            return """
            Usage: codex mcp login [OPTIONS] <NAME>

            Arguments:
              <NAME>
                      Name of the MCP server to authenticate with oauth

            Options:
              -c, --config <key=value>
                      Override a configuration value that would otherwise be loaded from `~/.codex/config.toml`.
                      Use a dotted path (`foo.bar.baz`) to override nested values. The `value` portion is parsed
                      as TOML. If it fails to parse as TOML, the raw string is used as a literal.

                      Examples: - `-c model="o3"` - `-c 'sandbox_permissions=["disk-full-read-access"]'` - `-c
                      shell_environment_policy.inherit=all`

                  --scopes <SCOPE,SCOPE>
                      Comma-separated list of OAuth scopes to request

                  --enable <FEATURE>
                      Enable a feature (repeatable). Equivalent to `-c features.<name>=true`

                  --disable <FEATURE>
                      Disable a feature (repeatable). Equivalent to `-c features.<name>=false`

              -h, --help
                      Print help (see a summary with '-h')
            """
        case "logout":
            return """
            Usage: codex mcp logout [OPTIONS] <NAME>

            Arguments:
              <NAME>
                      Name of the MCP server to deauthenticate

            Options:
              -c, --config <key=value>
                      Override a configuration value that would otherwise be loaded from `~/.codex/config.toml`.
                      Use a dotted path (`foo.bar.baz`) to override nested values. The `value` portion is parsed
                      as TOML. If it fails to parse as TOML, the raw string is used as a literal.

                      Examples: - `-c model="o3"` - `-c 'sandbox_permissions=["disk-full-read-access"]'` - `-c
                      shell_environment_policy.inherit=all`

                  --enable <FEATURE>
                      Enable a feature (repeatable). Equivalent to `-c features.<name>=true`

                  --disable <FEATURE>
                      Disable a feature (repeatable). Equivalent to `-c features.<name>=false`

              -h, --help
                      Print help (see a summary with '-h')
            """
        default:
            return nil
        }
    }

    private func renderPluginHelp() -> String {
        """
        Manage Codex plugins

        Usage: codex plugin [OPTIONS] <COMMAND>

        Commands:
          add          Install a plugin from a configured marketplace snapshot
          list         List plugins available from configured marketplace snapshots
          marketplace  Add, list, upgrade, or remove configured plugin marketplaces
          remove       Remove an installed plugin from local config and cache
          help         Print this message or the help of the given subcommand(s)

        Options:
          -c, --config <key=value>
                  Override a configuration value that would otherwise be loaded from `~/.codex/config.toml`.
                  Use a dotted path (`foo.bar.baz`) to override nested values. The `value` portion is parsed
                  as TOML. If it fails to parse as TOML, the raw string is used as a literal.

                  Examples: - `-c model="o3"` - `-c 'sandbox_permissions=["disk-full-read-access"]'` - `-c
                  shell_environment_policy.inherit=all`

              --enable <FEATURE>
                  Enable a feature (repeatable). Equivalent to `-c features.<name>=true`

              --disable <FEATURE>
                  Disable a feature (repeatable). Equivalent to `-c features.<name>=false`

          -h, --help
                  Print help (see a summary with '-h')
        """
    }

    private func renderPluginChildHelp(arguments: [String]) -> String? {
        guard let child = arguments.first, child != "--help", child != "-h" else {
            return nil
        }

        switch child {
        case "add":
            return """
            Install a plugin from a configured marketplace snapshot.

            Pass either `PLUGIN@MARKETPLACE` or pass `PLUGIN` with `--marketplace MARKETPLACE`.

            Usage: codex plugin add [OPTIONS] <PLUGIN[@MARKETPLACE]>

            Arguments:
              <PLUGIN[@MARKETPLACE]>
                      Plugin selector to install: either PLUGIN@MARKETPLACE or PLUGIN with --marketplace

            Options:
              -c, --config <key=value>
                      Override a configuration value that would otherwise be loaded from `~/.codex/config.toml`.
                      Use a dotted path (`foo.bar.baz`) to override nested values. The `value` portion is parsed
                      as TOML. If it fails to parse as TOML, the raw string is used as a literal.

                      Examples: - `-c model="o3"` - `-c 'sandbox_permissions=["disk-full-read-access"]'` - `-c
                      shell_environment_policy.inherit=all`

              -m, --marketplace <MARKETPLACE>
                      Configured marketplace name to use when PLUGIN does not include @MARKETPLACE

                  --enable <FEATURE>
                      Enable a feature (repeatable). Equivalent to `-c features.<name>=true`

                  --disable <FEATURE>
                      Disable a feature (repeatable). Equivalent to `-c features.<name>=false`

              -h, --help
                      Print help (see a summary with '-h')

            Examples:
              codex plugin add sample@debug
              codex plugin add sample --marketplace debug
            """
        case "list":
            return """
            List plugins available from configured marketplace snapshots

            Usage: codex plugin list [OPTIONS]

            Options:
              -c, --config <key=value>
                      Override a configuration value that would otherwise be loaded from `~/.codex/config.toml`.
                      Use a dotted path (`foo.bar.baz`) to override nested values. The `value` portion is parsed
                      as TOML. If it fails to parse as TOML, the raw string is used as a literal.

                      Examples: - `-c model="o3"` - `-c 'sandbox_permissions=["disk-full-read-access"]'` - `-c
                      shell_environment_policy.inherit=all`

              -m, --marketplace <MARKETPLACE>
                      Only list plugins from this configured marketplace name

                  --enable <FEATURE>
                      Enable a feature (repeatable). Equivalent to `-c features.<name>=true`

                  --disable <FEATURE>
                      Disable a feature (repeatable). Equivalent to `-c features.<name>=false`

              -h, --help
                      Print help (see a summary with '-h')

            Examples:
              codex plugin list
              codex plugin list --marketplace debug
            """
        case "remove":
            return """
            Remove an installed plugin from local config and cache.

            Pass either `PLUGIN@MARKETPLACE` or pass `PLUGIN` with `--marketplace MARKETPLACE`.

            Usage: codex plugin remove [OPTIONS] <PLUGIN[@MARKETPLACE]>

            Arguments:
              <PLUGIN[@MARKETPLACE]>
                      Plugin selector to remove: either PLUGIN@MARKETPLACE or PLUGIN with --marketplace

            Options:
              -c, --config <key=value>
                      Override a configuration value that would otherwise be loaded from `~/.codex/config.toml`.
                      Use a dotted path (`foo.bar.baz`) to override nested values. The `value` portion is parsed
                      as TOML. If it fails to parse as TOML, the raw string is used as a literal.

                      Examples: - `-c model="o3"` - `-c 'sandbox_permissions=["disk-full-read-access"]'` - `-c
                      shell_environment_policy.inherit=all`

              -m, --marketplace <MARKETPLACE>
                      Marketplace name to use when PLUGIN does not include @MARKETPLACE

                  --enable <FEATURE>
                      Enable a feature (repeatable). Equivalent to `-c features.<name>=true`

                  --disable <FEATURE>
                      Disable a feature (repeatable). Equivalent to `-c features.<name>=false`

              -h, --help
                      Print help (see a summary with '-h')

            Examples:
              codex plugin remove sample@debug
              codex plugin remove sample --marketplace debug
            """
        case "marketplace":
            return renderPluginMarketplaceHelp(arguments: Array(arguments.dropFirst()))
        default:
            return nil
        }
    }

    private func renderPluginMarketplaceHelp(arguments: [String]) -> String? {
        guard let child = arguments.first, child != "--help", child != "-h" else {
            return """
            Add, list, upgrade, or remove configured plugin marketplaces

            Usage: codex plugin marketplace [OPTIONS] <COMMAND>

            Commands:
              add      Add a local or Git marketplace to the configured marketplace sources
              list     List configured marketplace names and their local snapshot roots
              upgrade  Refresh configured Git marketplace snapshots
              remove   Remove a configured marketplace source by name
              help     Print this message or the help of the given subcommand(s)

            Options:
              -c, --config <key=value>
                      Override a configuration value that would otherwise be loaded from `~/.codex/config.toml`.
                      Use a dotted path (`foo.bar.baz`) to override nested values. The `value` portion is parsed
                      as TOML. If it fails to parse as TOML, the raw string is used as a literal.

                      Examples: - `-c model="o3"` - `-c 'sandbox_permissions=["disk-full-read-access"]'` - `-c
                      shell_environment_policy.inherit=all`

                  --enable <FEATURE>
                      Enable a feature (repeatable). Equivalent to `-c features.<name>=true`

                  --disable <FEATURE>
                      Disable a feature (repeatable). Equivalent to `-c features.<name>=false`

              -h, --help
                      Print help (see a summary with '-h')
            """
        }

        switch child {
        case "add":
            return """
            Add a local or Git marketplace to the configured marketplace sources

            Usage: codex plugin marketplace add [OPTIONS] <SOURCE>

            Arguments:
              <SOURCE>
                      Marketplace source: a local path, owner/repo[@ref], HTTPS Git URL, or SSH Git URL

            Options:
              -c, --config <key=value>
                      Override a configuration value that would otherwise be loaded from `~/.codex/config.toml`.
                      Use a dotted path (`foo.bar.baz`) to override nested values. The `value` portion is parsed
                      as TOML. If it fails to parse as TOML, the raw string is used as a literal.

                      Examples: - `-c model="o3"` - `-c 'sandbox_permissions=["disk-full-read-access"]'` - `-c
                      shell_environment_policy.inherit=all`

                  --ref <REF>
                      Git ref to fetch for Git marketplace sources

                  --enable <FEATURE>
                      Enable a feature (repeatable). Equivalent to `-c features.<name>=true`

                  --sparse <PATH>
                      Sparse checkout path for Git marketplace sources. Can be repeated

                  --disable <FEATURE>
                      Disable a feature (repeatable). Equivalent to `-c features.<name>=false`

              -h, --help
                      Print help (see a summary with '-h')

            Examples:
              codex plugin marketplace add ./path/to/marketplace
              codex plugin marketplace add owner/repo --ref main
              codex plugin marketplace add https://github.com/owner/repo --sparse plugins/foo
            """
        case "list":
            return """
            List configured marketplace names and their local snapshot roots

            Usage: codex plugin marketplace list [OPTIONS]

            Options:
              -c, --config <key=value>
                      Override a configuration value that would otherwise be loaded from `~/.codex/config.toml`.
                      Use a dotted path (`foo.bar.baz`) to override nested values. The `value` portion is parsed
                      as TOML. If it fails to parse as TOML, the raw string is used as a literal.

                      Examples: - `-c model="o3"` - `-c 'sandbox_permissions=["disk-full-read-access"]'` - `-c
                      shell_environment_policy.inherit=all`

                  --enable <FEATURE>
                      Enable a feature (repeatable). Equivalent to `-c features.<name>=true`

                  --disable <FEATURE>
                      Disable a feature (repeatable). Equivalent to `-c features.<name>=false`

              -h, --help
                      Print help (see a summary with '-h')
            """
        case "remove":
            return """
            Remove a configured marketplace source by name

            Usage: codex plugin marketplace remove [OPTIONS] <MARKETPLACE_NAME>

            Arguments:
              <MARKETPLACE_NAME>
                      Configured marketplace name to remove

            Options:
              -c, --config <key=value>
                      Override a configuration value that would otherwise be loaded from `~/.codex/config.toml`.
                      Use a dotted path (`foo.bar.baz`) to override nested values. The `value` portion is parsed
                      as TOML. If it fails to parse as TOML, the raw string is used as a literal.

                      Examples: - `-c model="o3"` - `-c 'sandbox_permissions=["disk-full-read-access"]'` - `-c
                      shell_environment_policy.inherit=all`

                  --enable <FEATURE>
                      Enable a feature (repeatable). Equivalent to `-c features.<name>=true`

                  --disable <FEATURE>
                      Disable a feature (repeatable). Equivalent to `-c features.<name>=false`

              -h, --help
                      Print help (see a summary with '-h')

            Example:
              codex plugin marketplace remove debug
            """
        case "upgrade":
            return """
            Refresh configured Git marketplace snapshots.

            Omit MARKETPLACE_NAME to upgrade all configured Git marketplaces.

            Usage: codex plugin marketplace upgrade [OPTIONS] [MARKETPLACE_NAME]

            Arguments:
              [MARKETPLACE_NAME]
                      Optional configured marketplace name to upgrade. Omit to upgrade all Git marketplaces

            Options:
              -c, --config <key=value>
                      Override a configuration value that would otherwise be loaded from `~/.codex/config.toml`.
                      Use a dotted path (`foo.bar.baz`) to override nested values. The `value` portion is parsed
                      as TOML. If it fails to parse as TOML, the raw string is used as a literal.

                      Examples: - `-c model="o3"` - `-c 'sandbox_permissions=["disk-full-read-access"]'` - `-c
                      shell_environment_policy.inherit=all`

                  --enable <FEATURE>
                      Enable a feature (repeatable). Equivalent to `-c features.<name>=true`

                  --disable <FEATURE>
                      Disable a feature (repeatable). Equivalent to `-c features.<name>=false`

              -h, --help
                      Print help (see a summary with '-h')

            Examples:
              codex plugin marketplace upgrade
              codex plugin marketplace upgrade debug
            """
        default:
            return nil
        }
    }

    private func renderMcpServerHelp() -> String {
        """
        Start Codex as an MCP server (stdio)

        Usage: codex mcp-server [OPTIONS]

        Options:
          -c, --config <key=value>
                  Override a configuration value that would otherwise be loaded from `~/.codex/config.toml`.
                  Use a dotted path (`foo.bar.baz`) to override nested values. The `value` portion is parsed
                  as TOML. If it fails to parse as TOML, the raw string is used as a literal.

                  Examples: - `-c model="o3"` - `-c 'sandbox_permissions=["disk-full-read-access"]'` - `-c
                  shell_environment_policy.inherit=all`

              --strict-config
                  Error out when config.toml contains fields that are not recognized by this version of
                  Codex

              --enable <FEATURE>
                  Enable a feature (repeatable). Equivalent to `-c features.<name>=true`

              --disable <FEATURE>
                  Disable a feature (repeatable). Equivalent to `-c features.<name>=false`

          -h, --help
                  Print help (see a summary with '-h')
        """
    }

    private func renderAppServerHelp() -> String {
        """
        [experimental] Run the app server or related tooling

        Usage: codex app-server [OPTIONS] [COMMAND]

        Commands:
          daemon                Manage the local app-server daemon
          proxy                 Proxy stdio bytes to the running app-server control socket
          generate-ts           [experimental] Generate TypeScript bindings for the app server protocol
          generate-json-schema  [experimental] Generate JSON Schema for the app server protocol
          help                  Print this message or the help of the given subcommand(s)

        Options:
          -c, --config <key=value>
                  Override a configuration value that would otherwise be loaded from `~/.codex/config.toml`.
                  Use a dotted path (`foo.bar.baz`) to override nested values. The `value` portion is parsed
                  as TOML. If it fails to parse as TOML, the raw string is used as a literal.

                  Examples: - `-c model="o3"` - `-c 'sandbox_permissions=["disk-full-read-access"]'` - `-c
                  shell_environment_policy.inherit=all`

              --enable <FEATURE>
                  Enable a feature (repeatable). Equivalent to `-c features.<name>=true`

              --disable <FEATURE>
                  Disable a feature (repeatable). Equivalent to `-c features.<name>=false`

              --strict-config
                  Error out when config.toml contains fields that are not recognized by this version of
                  Codex

              --listen <URL>
                  Transport endpoint URL. Supported values: `stdio://` (default), `unix://`, `unix://PATH`,
                  `ws://IP:PORT`, `off`

                  [default: stdio://]

              --analytics-default-enabled
                  Controls whether analytics are enabled by default.

                  Analytics are disabled by default for app-server. Users have to explicitly opt in via the
                  `analytics` section in the config.toml file.

                  However, for first-party use cases like the VSCode IDE extension, we default analytics to
                  be enabled by default by setting this flag. Users can still opt out by setting this in
                  their config.toml:

                  ```toml [analytics] enabled = false ```

                  See https://developers.openai.com/codex/config-advanced/#metrics for more details.

              --ws-auth <MODE>
                  Websocket auth mode for non-loopback listeners

                  [possible values: capability-token, signed-bearer-token]

              --ws-token-file <PATH>
                  Absolute path to the capability-token file

              --ws-token-sha256 <HEX>
                  Hex-encoded SHA-256 digest of the capability token

              --ws-shared-secret-file <PATH>
                  Absolute path to the shared secret file for signed JWT bearer tokens

              --ws-issuer <ISSUER>
                  Expected issuer for signed JWT bearer tokens

              --ws-audience <AUDIENCE>
                  Expected audience for signed JWT bearer tokens

              --ws-max-clock-skew-seconds <SECONDS>
                  Maximum clock skew when validating signed JWT bearer tokens

          -h, --help
                  Print help (see a summary with '-h')
        """
    }

    private func renderRemoteControlHelp() -> String {
        """
        [experimental] Manage the app-server daemon with remote control enabled

        Usage: codex remote-control [OPTIONS] [COMMAND]

        Commands:
          start  Start the app-server daemon with remote control enabled
          stop   Stop the app-server daemon
          help   Print this message or the help of the given subcommand(s)

        Options:
          -c, --config <key=value>
                  Override a configuration value that would otherwise be loaded from `~/.codex/config.toml`.
                  Use a dotted path (`foo.bar.baz`) to override nested values. The `value` portion is parsed
                  as TOML. If it fails to parse as TOML, the raw string is used as a literal.

                  Examples: - `-c model="o3"` - `-c 'sandbox_permissions=["disk-full-read-access"]'` - `-c
                  shell_environment_policy.inherit=all`

              --enable <FEATURE>
                  Enable a feature (repeatable). Equivalent to `-c features.<name>=true`

              --disable <FEATURE>
                  Disable a feature (repeatable). Equivalent to `-c features.<name>=false`

          -h, --help
                  Print help (see a summary with '-h')
        """
    }

    private func renderAppHelp() -> String {
        """
        Launch the Codex desktop app (opens the app installer if missing)

        Usage: codex app [OPTIONS] [PATH]

        Arguments:
          [PATH]
                  Workspace path to open in Codex Desktop

                  [default: .]

        Options:
          -c, --config <key=value>
                  Override a configuration value that would otherwise be loaded from `~/.codex/config.toml`.
                  Use a dotted path (`foo.bar.baz`) to override nested values. The `value` portion is parsed
                  as TOML. If it fails to parse as TOML, the raw string is used as a literal.

                  Examples: - `-c model="o3"` - `-c 'sandbox_permissions=["disk-full-read-access"]'` - `-c
                  shell_environment_policy.inherit=all`

              --download-url <DOWNLOAD_URL_OVERRIDE>
                  Override the app installer download URL (advanced)

              --enable <FEATURE>
                  Enable a feature (repeatable). Equivalent to `-c features.<name>=true`

              --disable <FEATURE>
                  Disable a feature (repeatable). Equivalent to `-c features.<name>=false`

          -h, --help
                  Print help (see a summary with '-h')
        """
    }

    private func renderUpdateHelp() -> String {
        """
        Update Codex to the latest version

        Usage: codex update [OPTIONS]

        Options:
          -c, --config <key=value>
                  Override a configuration value that would otherwise be loaded from `~/.codex/config.toml`.
                  Use a dotted path (`foo.bar.baz`) to override nested values. The `value` portion is parsed
                  as TOML. If it fails to parse as TOML, the raw string is used as a literal.

                  Examples: - `-c model="o3"` - `-c 'sandbox_permissions=["disk-full-read-access"]'` - `-c
                  shell_environment_policy.inherit=all`

              --enable <FEATURE>
                  Enable a feature (repeatable). Equivalent to `-c features.<name>=true`

              --disable <FEATURE>
                  Disable a feature (repeatable). Equivalent to `-c features.<name>=false`

          -h, --help
                  Print help (see a summary with '-h')
        """
    }

    private func renderDoctorHelp() -> String {
        """
        Diagnose local Codex installation, config, auth, and runtime health

        Usage: codex doctor [OPTIONS]

        Options:
          -c, --config <key=value>
                  Override a configuration value that would otherwise be loaded from `~/.codex/config.toml`.
                  Use a dotted path (`foo.bar.baz`) to override nested values. The `value` portion is parsed
                  as TOML. If it fails to parse as TOML, the raw string is used as a literal.

                  Examples: - `-c model="o3"` - `-c 'sandbox_permissions=["disk-full-read-access"]'` - `-c
                  shell_environment_policy.inherit=all`

              --json
                  Emit a redacted machine-readable report

              --enable <FEATURE>
                  Enable a feature (repeatable). Equivalent to `-c features.<name>=true`

              --summary
                  Only show grouped check rows and the final count summary

              --all
                  Expand long lists in detailed human output

              --disable <FEATURE>
                  Disable a feature (repeatable). Equivalent to `-c features.<name>=false`

              --no-color
                  Disable ANSI color in human output

              --ascii
                  Use ASCII status labels and separators in human output

          -h, --help
                  Print help (see a summary with '-h')
        """
    }

    private func renderSandboxHelp() -> String {
        """
        Run commands within a Codex-provided sandbox

        Usage: codex sandbox [OPTIONS] <COMMAND>

        Commands:
          macos    Run a command under Seatbelt (macOS only) [aliases: seatbelt]
          linux    Run a command under the Linux sandbox (bubblewrap by default) [aliases: landlock]
          windows  Run a command under Windows restricted token (Windows only)
          help     Print this message or the help of the given subcommand(s)

        Options:
          -c, --config <key=value>
                  Override a configuration value that would otherwise be loaded from `~/.codex/config.toml`.
                  Use a dotted path (`foo.bar.baz`) to override nested values. The `value` portion is parsed
                  as TOML. If it fails to parse as TOML, the raw string is used as a literal.

                  Examples: - `-c model="o3"` - `-c 'sandbox_permissions=["disk-full-read-access"]'` - `-c
                  shell_environment_policy.inherit=all`

              --enable <FEATURE>
                  Enable a feature (repeatable). Equivalent to `-c features.<name>=true`

              --disable <FEATURE>
                  Disable a feature (repeatable). Equivalent to `-c features.<name>=false`

          -h, --help
                  Print help (see a summary with '-h')
        """
    }

    private func renderApplyHelp() -> String {
        """
        Apply the latest diff produced by Codex agent as a `git apply` to your local working tree

        Usage: codex apply [OPTIONS] <TASK_ID>

        Arguments:
          <TASK_ID>


        Options:
          -c, --config <key=value>
                  Override a configuration value that would otherwise be loaded from `~/.codex/config.toml`.
                  Use a dotted path (`foo.bar.baz`) to override nested values. The `value` portion is parsed
                  as TOML. If it fails to parse as TOML, the raw string is used as a literal.

                  Examples: - `-c model="o3"` - `-c 'sandbox_permissions=["disk-full-read-access"]'` - `-c
                  shell_environment_policy.inherit=all`

              --enable <FEATURE>
                  Enable a feature (repeatable). Equivalent to `-c features.<name>=true`

              --disable <FEATURE>
                  Disable a feature (repeatable). Equivalent to `-c features.<name>=false`

          -h, --help
                  Print help (see a summary with '-h')
        """
    }

    private func renderDebugHelp() -> String {
        """
        Debugging tools

        Usage: codex debug [OPTIONS] <COMMAND>

        Commands:
          models        Render the raw model catalog as JSON
          app-server    Tooling: helps debug the app server
          prompt-input  Render the model-visible prompt input list as JSON
          help          Print this message or the help of the given subcommand(s)

        Options:
          -c, --config <key=value>
                  Override a configuration value that would otherwise be loaded from `~/.codex/config.toml`.
                  Use a dotted path (`foo.bar.baz`) to override nested values. The `value` portion is parsed
                  as TOML. If it fails to parse as TOML, the raw string is used as a literal.

                  Examples: - `-c model="o3"` - `-c 'sandbox_permissions=["disk-full-read-access"]'` - `-c
                  shell_environment_policy.inherit=all`

              --enable <FEATURE>
                  Enable a feature (repeatable). Equivalent to `-c features.<name>=true`

              --disable <FEATURE>
                  Disable a feature (repeatable). Equivalent to `-c features.<name>=false`

          -h, --help
                  Print help (see a summary with '-h')
        """
    }

    private func renderExecPolicyHelp() -> String {
        """
        Execpolicy tooling

        Usage: codex execpolicy [OPTIONS] <COMMAND>

        Commands:
          check  Check execpolicy files against a command
          help   Print this message or the help of the given subcommand(s)

        Options:
          -c, --config <key=value>
                  Override a configuration value that would otherwise be loaded from `~/.codex/config.toml`.
                  Use a dotted path (`foo.bar.baz`) to override nested values. The `value` portion is parsed
                  as TOML. If it fails to parse as TOML, the raw string is used as a literal.

                  Examples: - `-c model="o3"` - `-c 'sandbox_permissions=["disk-full-read-access"]'` - `-c
                  shell_environment_policy.inherit=all`

              --enable <FEATURE>
                  Enable a feature (repeatable). Equivalent to `-c features.<name>=true`

              --disable <FEATURE>
                  Disable a feature (repeatable). Equivalent to `-c features.<name>=false`

          -h, --help
                  Print help (see a summary with '-h')
        """
    }

    private func renderResumeHelp() -> String {
        """
        Resume a previous interactive session (picker by default; use --last to continue the most recent)

        Usage: codex resume [OPTIONS] [SESSION_ID] [PROMPT]

        Arguments:
          [SESSION_ID]
                  Conversation/session id (UUID) or thread name. UUIDs take precedence if it parses. If
                  omitted, use --last to pick the most recent recorded session

          [PROMPT]
                  Optional user prompt to start the session

        Options:
          -c, --config <key=value>
                  Override a configuration value that would otherwise be loaded from `~/.codex/config.toml`.
                  Use a dotted path (`foo.bar.baz`) to override nested values. The `value` portion is parsed
                  as TOML. If it fails to parse as TOML, the raw string is used as a literal.

                  Examples: - `-c model="o3"` - `-c 'sandbox_permissions=["disk-full-read-access"]'` - `-c
                  shell_environment_policy.inherit=all`

              --last
                  Continue the most recent session without showing the picker

              --all
                  Show all sessions (disables cwd filtering and shows CWD column)

              --enable <FEATURE>
                  Enable a feature (repeatable). Equivalent to `-c features.<name>=true`

              --disable <FEATURE>
                  Disable a feature (repeatable). Equivalent to `-c features.<name>=false`

              --include-non-interactive
                  Include non-interactive sessions in the resume picker and --last selection

              --remote <ADDR>
                  Connect the TUI to a remote app server endpoint.

                  Accepted forms: `ws://host:port`, `wss://host:port`, `unix://`, or `unix://PATH`.

              --remote-auth-token-env <ENV_VAR>
                  Name of the environment variable containing the bearer token to send to a remote app
                  server websocket

              --strict-config
                  Error out when config.toml contains fields that are not recognized by this version of
                  Codex

          -i, --image <FILE>...
                  Optional image(s) to attach to the initial prompt

          -m, --model <MODEL>
                  Model the agent should use

              --oss
                  Use open-source provider

              --local-provider <OSS_PROVIDER>
                  Specify which local provider to use (lmstudio or ollama). If not specified with --oss,
                  will use config default or show selection

          -p, --profile <CONFIG_PROFILE>
                  Configuration profile from config.toml to specify default options

              --profile-v2 <CONFIG_PROFILE_V2>
                  Layer $CODEX_HOME/<name>.config.toml on top of the base user config

          -s, --sandbox <SANDBOX_MODE>
                  Select the sandbox policy to use when executing model-generated shell commands

                  [possible values: read-only, workspace-write, danger-full-access]

              --dangerously-bypass-approvals-and-sandbox
                  Skip all confirmation prompts and execute commands without sandboxing. EXTREMELY
                  DANGEROUS. Intended solely for running in environments that are externally sandboxed

              --dangerously-bypass-hook-trust
                  Run enabled hooks without requiring persisted hook trust for this invocation. DANGEROUS.
                  Intended only for automation that already vets hook sources

          -C, --cd <DIR>
                  Tell the agent to use the specified directory as its working root

              --add-dir <DIR>
                  Additional directories that should be writable alongside the primary workspace

          -a, --ask-for-approval <APPROVAL_POLICY>
                  Configure when the model requires human approval before executing a command

                  Possible values:
                  - untrusted:  Only run "trusted" commands (e.g. ls, cat, sed) without asking for user
                    approval. Will escalate to the user if the model proposes a command that is not in the
                    "trusted" set
                  - on-failure: DEPRECATED: Run all commands without asking for user approval. Only asks for
                    approval if a command fails to execute, in which case it will escalate to the user to
                    ask for un-sandboxed execution. Prefer `on-request` for interactive runs or `never` for
                    non-interactive runs
                  - on-request: The model decides when to ask the user for approval
                  - never:      Never ask for user approval Execution failures are immediately returned to
                    the model

              --search
                  Enable live web search. When enabled, the native Responses `web_search` tool is available
                  to the model (no per-call approval)

              --no-alt-screen
                  Disable alternate screen mode

                  Runs the TUI in inline mode, preserving terminal scrollback history.

          -h, --help
                  Print help (see a summary with '-h')

          -V, --version
                  Print version
        """
    }

    private func renderForkHelp() -> String {
        """
        Fork a previous interactive session (picker by default; use --last to fork the most recent)

        Usage: codex fork [OPTIONS] [SESSION_ID] [PROMPT]

        Arguments:
          [SESSION_ID]
                  Conversation/session id (UUID). When provided, forks this session. If omitted, use --last
                  to pick the most recent recorded session

          [PROMPT]
                  Optional user prompt to start the session

        Options:
          -c, --config <key=value>
                  Override a configuration value that would otherwise be loaded from `~/.codex/config.toml`.
                  Use a dotted path (`foo.bar.baz`) to override nested values. The `value` portion is parsed
                  as TOML. If it fails to parse as TOML, the raw string is used as a literal.

                  Examples: - `-c model="o3"` - `-c 'sandbox_permissions=["disk-full-read-access"]'` - `-c
                  shell_environment_policy.inherit=all`

              --last
                  Fork the most recent session without showing the picker

              --all
                  Show all sessions (disables cwd filtering and shows CWD column)

              --enable <FEATURE>
                  Enable a feature (repeatable). Equivalent to `-c features.<name>=true`

              --disable <FEATURE>
                  Disable a feature (repeatable). Equivalent to `-c features.<name>=false`

              --remote <ADDR>
                  Connect the TUI to a remote app server endpoint.

                  Accepted forms: `ws://host:port`, `wss://host:port`, `unix://`, or `unix://PATH`.

              --remote-auth-token-env <ENV_VAR>
                  Name of the environment variable containing the bearer token to send to a remote app
                  server websocket

              --strict-config
                  Error out when config.toml contains fields that are not recognized by this version of
                  Codex

          -i, --image <FILE>...
                  Optional image(s) to attach to the initial prompt

          -m, --model <MODEL>
                  Model the agent should use

              --oss
                  Use open-source provider

              --local-provider <OSS_PROVIDER>
                  Specify which local provider to use (lmstudio or ollama). If not specified with --oss,
                  will use config default or show selection

          -p, --profile <CONFIG_PROFILE>
                  Configuration profile from config.toml to specify default options

              --profile-v2 <CONFIG_PROFILE_V2>
                  Layer $CODEX_HOME/<name>.config.toml on top of the base user config

          -s, --sandbox <SANDBOX_MODE>
                  Select the sandbox policy to use when executing model-generated shell commands

                  [possible values: read-only, workspace-write, danger-full-access]

              --dangerously-bypass-approvals-and-sandbox
                  Skip all confirmation prompts and execute commands without sandboxing. EXTREMELY
                  DANGEROUS. Intended solely for running in environments that are externally sandboxed

              --dangerously-bypass-hook-trust
                  Run enabled hooks without requiring persisted hook trust for this invocation. DANGEROUS.
                  Intended only for automation that already vets hook sources

          -C, --cd <DIR>
                  Tell the agent to use the specified directory as its working root

              --add-dir <DIR>
                  Additional directories that should be writable alongside the primary workspace

          -a, --ask-for-approval <APPROVAL_POLICY>
                  Configure when the model requires human approval before executing a command

                  Possible values:
                  - untrusted:  Only run "trusted" commands (e.g. ls, cat, sed) without asking for user
                    approval. Will escalate to the user if the model proposes a command that is not in the
                    "trusted" set
                  - on-failure: DEPRECATED: Run all commands without asking for user approval. Only asks for
                    approval if a command fails to execute, in which case it will escalate to the user to
                    ask for un-sandboxed execution. Prefer `on-request` for interactive runs or `never` for
                    non-interactive runs
                  - on-request: The model decides when to ask the user for approval
                  - never:      Never ask for user approval Execution failures are immediately returned to
                    the model

              --search
                  Enable live web search. When enabled, the native Responses `web_search` tool is available
                  to the model (no per-call approval)

              --no-alt-screen
                  Disable alternate screen mode

                  Runs the TUI in inline mode, preserving terminal scrollback history.

          -h, --help
                  Print help (see a summary with '-h')

          -V, --version
                  Print version
        """
    }

    private func renderCloudHelp() -> String {
        """
        [EXPERIMENTAL] Browse tasks from Codex Cloud and apply changes locally

        Usage: codex cloud [OPTIONS] [COMMAND]

        Commands:
          exec    Submit a new Codex Cloud task without launching the TUI
          status  Show the status of a Codex Cloud task
          list    List Codex Cloud tasks
          apply   Apply the diff for a Codex Cloud task locally
          diff    Show the unified diff for a Codex Cloud task
          help    Print this message or the help of the given subcommand(s)

        Options:
          -c, --config <key=value>
                  Override a configuration value that would otherwise be loaded from `~/.codex/config.toml`.
                  Use a dotted path (`foo.bar.baz`) to override nested values. The `value` portion is parsed
                  as TOML. If it fails to parse as TOML, the raw string is used as a literal.

                  Examples: - `-c model="o3"` - `-c 'sandbox_permissions=["disk-full-read-access"]'` - `-c
                  shell_environment_policy.inherit=all`

              --enable <FEATURE>
                  Enable a feature (repeatable). Equivalent to `-c features.<name>=true`

              --disable <FEATURE>
                  Disable a feature (repeatable). Equivalent to `-c features.<name>=false`

          -h, --help
                  Print help (see a summary with '-h')

          -V, --version
                  Print version
        """
    }

    private func renderResponsesAPIProxyHelp() -> String {
        """
        Internal: run the responses API proxy

        Usage: codex responses-api-proxy [OPTIONS]

        Options:
          -c, --config <key=value>
                  Override a configuration value that would otherwise be loaded from `~/.codex/config.toml`.
                  Use a dotted path (`foo.bar.baz`) to override nested values. The `value` portion is parsed
                  as TOML. If it fails to parse as TOML, the raw string is used as a literal.

                  Examples: - `-c model="o3"` - `-c 'sandbox_permissions=["disk-full-read-access"]'` - `-c
                  shell_environment_policy.inherit=all`

              --port <PORT>
                  Port to listen on. If not set, an ephemeral port is used

              --enable <FEATURE>
                  Enable a feature (repeatable). Equivalent to `-c features.<name>=true`

              --server-info <FILE>
                  Path to a JSON file to write startup info (single line). Includes {"port": <u16>}

              --disable <FEATURE>
                  Disable a feature (repeatable). Equivalent to `-c features.<name>=false`

              --http-shutdown
                  Enable HTTP shutdown endpoint at GET /shutdown

              --upstream-url <UPSTREAM_URL>
                  Absolute URL the proxy should forward requests to (defaults to OpenAI)

                  [default: https://api.openai.com/v1/responses]

              --dump-dir <DIR>
                  Directory where request/response dumps should be written as JSON

          -h, --help
                  Print help (see a summary with '-h')
        """
    }

    private func renderStdioToUDSHelp() -> String {
        """
        Internal: relay stdio to a Unix domain socket

        Usage: codex stdio-to-uds [OPTIONS] <SOCKET_PATH>

        Arguments:
          <SOCKET_PATH>
                  Path to the Unix domain socket to connect to

        Options:
          -c, --config <key=value>
                  Override a configuration value that would otherwise be loaded from `~/.codex/config.toml`.
                  Use a dotted path (`foo.bar.baz`) to override nested values. The `value` portion is parsed
                  as TOML. If it fails to parse as TOML, the raw string is used as a literal.

                  Examples: - `-c model="o3"` - `-c 'sandbox_permissions=["disk-full-read-access"]'` - `-c
                  shell_environment_policy.inherit=all`

              --enable <FEATURE>
                  Enable a feature (repeatable). Equivalent to `-c features.<name>=true`

              --disable <FEATURE>
                  Disable a feature (repeatable). Equivalent to `-c features.<name>=false`

          -h, --help
                  Print help (see a summary with '-h')
        """
    }

    private func renderExecServerHelp() -> String {
        """
        [EXPERIMENTAL] Run the standalone exec-server service

        Usage: codex exec-server [OPTIONS]

        Options:
          -c, --config <key=value>
                  Override a configuration value that would otherwise be loaded from `~/.codex/config.toml`.
                  Use a dotted path (`foo.bar.baz`) to override nested values. The `value` portion is parsed
                  as TOML. If it fails to parse as TOML, the raw string is used as a literal.

                  Examples: - `-c model="o3"` - `-c 'sandbox_permissions=["disk-full-read-access"]'` - `-c
                  shell_environment_policy.inherit=all`

              --listen <URL>
                  Transport endpoint URL. Supported values: `ws://IP:PORT` (default), `stdio`, `stdio://`

              --enable <FEATURE>
                  Enable a feature (repeatable). Equivalent to `-c features.<name>=true`

              --remote <URL>
                  Register this exec-server as a remote executor using the given base URL

              --disable <FEATURE>
                  Disable a feature (repeatable). Equivalent to `-c features.<name>=false`

              --executor-id <ID>
                  Executor id to attach to when registering remotely

              --name <NAME>
                  Human-readable executor name

              --use-agent-identity-auth
                  Use Agent Identity auth from CODEX_ACCESS_TOKEN for remote registration

          -h, --help
                  Print help (see a summary with '-h')
        """
    }

    private func renderFeaturesHelp() -> String {
        """
        Inspect feature flags

        Usage: codex features [OPTIONS] <COMMAND>

        Commands:
          list     List known features with their stage and effective state
          enable   Enable a feature in config.toml
          disable  Disable a feature in config.toml
          help     Print this message or the help of the given subcommand(s)

        Options:
          -c, --config <key=value>
                  Override a configuration value that would otherwise be loaded from `~/.codex/config.toml`.
                  Use a dotted path (`foo.bar.baz`) to override nested values. The `value` portion is parsed
                  as TOML. If it fails to parse as TOML, the raw string is used as a literal.

                  Examples: - `-c model="o3"` - `-c 'sandbox_permissions=["disk-full-read-access"]'` - `-c
                  shell_environment_policy.inherit=all`

              --enable <FEATURE>
                  Enable a feature (repeatable). Equivalent to `-c features.<name>=true`

              --disable <FEATURE>
                  Disable a feature (repeatable). Equivalent to `-c features.<name>=false`

          -h, --help
                  Print help (see a summary with '-h')
        """
    }

    public func run(arguments: [String], stdout: (String) -> Void = { print($0) }, stderr: (String) -> Void = { fputs($0 + "\n", Darwin.stderr) }) -> Int32 {
        switch parseInvocation(arguments: arguments) {
        case .version:
            stdout(renderVersion())
            return 0
        case let .commandVersion(spec):
            stdout(renderVersion(for: spec))
            return 0
        case let .commandUnsupportedVersion(spec, flag):
            stderr(renderUnsupportedVersionError(for: spec, flag: flag))
            return 2
        case .help:
            stdout(renderHelp())
            return 0
        case let .commandHelp(spec, arguments):
            stdout(renderHelp(for: spec, arguments: arguments))
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
        interactiveRunner: InteractiveCommandRunner? = nil,
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
        updateRunner: UpdateCommandRunner? = nil,
        doctorRunner: DoctorCommandRunner? = nil
    ) async -> Int32 {
        let invocation = parseInvocation(arguments: arguments)
        if let message = rootDuplicateSharedOptionRejectionMessage(invocation: invocation, arguments: arguments) {
            stderr(message)
            return 64
        }
        if let message = rootRemovedFullAutoRejectionMessage(invocation: invocation, arguments: arguments) {
            stderr(message)
            return 64
        }
        if let message = rootInteractivePermissionConflictRejectionMessage(
            invocation: invocation,
            arguments: arguments
        ) {
            stderr(message)
            return 64
        }
        if let message = rootProfileV2RejectionMessage(invocation: invocation, arguments: arguments) {
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
        if case let .command(spec, _) = invocation,
           let message = strictConfigRejectionMessage(
               spec: spec,
               arguments: arguments
           ) {
            stderr(message)
            return 64
        }

        switch invocation {
        case .version:
            stdout(renderVersion())
            return 0
        case let .commandVersion(spec):
            stdout(renderVersion(for: spec))
            return 0
        case let .commandUnsupportedVersion(spec, flag):
            stderr(renderUnsupportedVersionError(for: spec, flag: flag))
            return 2
        case .help:
            stdout(renderHelp())
            return 0
        case let .commandHelp(spec, arguments):
            stdout(renderHelp(for: spec, arguments: arguments))
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
            let action = loginAction(arguments: arguments, commandArguments: commandArguments)
            if action != .status {
                if usesAPIKeyStdinFlag(arguments), usesAccessTokenStdinFlag(arguments) {
                    stderr("Choose one login credential source: --with-api-key or --with-access-token.")
                    return 1
                }
                if usesDeprecatedAPIKeyFlag(arguments), !usesDeviceAuthFlag(arguments) {
                    stderr("The --api-key flag is no longer supported. Pipe the key instead, e.g. `printenv OPENAI_API_KEY | codex login --with-api-key`.")
                    return 1
                }
            }
            guard let loginRunner else {
                stderr("codex-swift: command '\(spec.name)' is registered but its runtime port is not complete yet.")
                return 78
            }
            do {
                let result = try await loginRunner(LoginCommandRequest(
                    action: action,
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
                        configProfileV2: rootProfileV2(beforeCommand: "debug", in: arguments),
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
        case let .command(spec, _) where spec.name == "doctor":
            guard let doctorRunner else {
                stderr("codex-swift: command '\(spec.name)' is registered but its runtime port is not complete yet.")
                return 78
            }
            let rawArguments = rawCommandArguments(after: spec, in: arguments)
            let configOverrides: CliConfigOverrides
            do {
                configOverrides = CliConfigOverrides(rawOverrides: try configOverrideTokens(arguments))
            } catch {
                stderr(describe(error))
                return 1
            }
            switch parseDoctorCommand(rawArguments, configOverrides: configOverrides) {
            case let .success(request):
                do {
                    let result = try await doctorRunner(request)
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
        case let .command(spec, commandArguments) where spec.name == "features":
            guard let featuresRunner else {
                stderr("codex-swift: command '\(spec.name)' is registered but its runtime port is not complete yet.")
                return 78
            }
            switch parseFeaturesCommandAction(commandArguments) {
            case let .success(action):
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
            case let .failure(message, exitCode):
                stderr(message)
                return exitCode
            }
        case let .command(spec, _):
            stderr("codex-swift: command '\(spec.name)' is registered but its runtime port is not complete yet.")
            return 78
        case .interactive:
            guard let interactiveRunner else {
                stderr("codex-swift: interactive TUI runtime is not complete yet.")
                return 78
            }
            switch parseInteractiveCommand(arguments) {
            case let .success(request):
                do {
                    let result = try await interactiveRunner(request)
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
            "--profile-v2",
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

    private func strictConfigEnabled(in arguments: [String]) -> Bool {
        arguments.contains("--strict-config")
    }

    private func strictConfigRejectionMessage(
        spec: CommandSpec,
        arguments: [String]
    ) -> String? {
        guard strictConfigEnabled(in: arguments) else {
            return nil
        }
        if spec.name == "app-server" {
            let rawArguments = rawCommandArguments(after: spec, in: arguments)
            guard case let .success((_, remainingArguments)) = parseAppServerOptions(rawArguments),
                  let subcommand = remainingArguments.first,
                  !subcommand.hasPrefix("-")
            else {
                return nil
            }
            return "`--strict-config` is not supported for `codex app-server \(subcommand)`"
        }
        if ["exec", "review", "resume", "fork", "mcp-server"].contains(spec.name) {
            return nil
        }
        return "`--strict-config` is not supported for `codex \(spec.name)`"
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

    private func parseDoctorCommand(
        _ arguments: [String],
        configOverrides: CliConfigOverrides
    ) -> ParseResult<DoctorCommandRequest> {
        var json = false
        var summary = false
        var all = false
        var noColor = false
        var ascii = false

        for argument in arguments {
            switch argument {
            case "--json":
                json = true
            case "--summary":
                summary = true
            case "--all":
                all = true
            case "--no-color":
                noColor = true
            case "--ascii":
                ascii = true
            default:
                if argument.hasPrefix("-") {
                    return .failure("codex-swift: unexpected option for command 'doctor': \(argument)", 64)
                }
                return .failure("codex-swift: unexpected argument for command 'doctor': \(argument)", 64)
            }
        }

        return .success(DoctorCommandRequest(
            json: json,
            summary: summary,
            all: all,
            noColor: noColor,
            ascii: ascii,
            configOverrides: configOverrides
        ))
    }

    private func parseFeaturesCommandAction(_ arguments: [String]) -> ParseResult<FeaturesCommandAction> {
        guard let subcommand = arguments.first else {
            return .failure(
                "codex-swift: missing required subcommand for command 'features': list, enable, or disable",
                64
            )
        }
        switch subcommand {
        case "list":
            guard arguments.count == 1 else {
                return .failure("codex-swift: unexpected argument for command 'features list': \(arguments[1])", 64)
            }
            return .success(.list)
        case "enable":
            guard arguments.count >= 2 else {
                return .failure(
                    "codex-swift: missing required argument for command 'features enable': <FEATURE>",
                    64
                )
            }
            guard arguments.count == 2 else {
                return .failure("codex-swift: unexpected argument for command 'features enable': \(arguments[2])", 64)
            }
            return .success(.enable(feature: arguments[1]))
        case "disable":
            guard arguments.count >= 2 else {
                return .failure(
                    "codex-swift: missing required argument for command 'features disable': <FEATURE>",
                    64
                )
            }
            guard arguments.count == 2 else {
                return .failure("codex-swift: unexpected argument for command 'features disable': \(arguments[2])", 64)
            }
            return .success(.disable(feature: arguments[1]))
        default:
            return .failure("codex-swift: unsupported features subcommand: \(subcommand)", 64)
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
        if usesAPIKeyStdinFlag(arguments) {
            return .withAPIKeyFromStdin
        }
        if usesAccessTokenStdinFlag(arguments) {
            return .withAccessTokenFromStdin
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

    private func usesAPIKeyStdinFlag(_ arguments: [String]) -> Bool {
        arguments.contains("--with-api-key")
    }

    private func usesAccessTokenStdinFlag(_ arguments: [String]) -> Bool {
        arguments.contains("--with-access-token")
    }

    private func usesDeviceAuthFlag(_ arguments: [String]) -> Bool {
        arguments.contains("--device-auth")
    }

    private func validateProfileV2Name(_ value: String) -> ParseResult<Void> {
        guard !value.isEmpty,
              value.utf8.allSatisfy({ byte in
                  (byte >= UInt8(ascii: "A") && byte <= UInt8(ascii: "Z")) ||
                      (byte >= UInt8(ascii: "a") && byte <= UInt8(ascii: "z")) ||
                      (byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9")) ||
                      byte == UInt8(ascii: "_") ||
                      byte == UInt8(ascii: "-")
              })
        else {
            return .failure("invalid --profile-v2 value `\(value)`; pass a plain name such as `work`", 64)
        }
        return .success(())
    }

    private func parseConfigOverrides(from arguments: [String]) -> ParseResult<CliConfigOverrides> {
        do {
            return .success(CliConfigOverrides(rawOverrides: try configOverrideTokens(arguments)))
        } catch {
            return .failure(describe(error), 1)
        }
    }

    private struct ParsedInteractiveCommandOptions {
        var remote: String?
        var remoteAuthTokenEnv: String?
        var imagePaths: [String] = []
        var model: String?
        var useOSSProvider = false
        var localProvider: String?
        var configProfile: String?
        var configProfileV2: String?
        var sandboxMode: String?
        var dangerouslyBypassApprovalsAndSandbox = false
        var selectedSandboxMode = false
        var cwd: String?
        var additionalWritableRoots: [String] = []
        var approvalPolicy: String?
        var approvalPolicyOption: String?
        var searchEnabled = false
        var noAltScreen = false
        var dangerouslyBypassOption: String?
        var strictConfig = false
        var bypassHookTrust = false
        var ephemeral = false
        var ignoreUserConfig = false
        var ignoreRules = false
    }

    private func parseRootInteractiveOptions(
        beforeCommand commandName: String,
        in arguments: [String]
    ) -> ParseResult<ParsedInteractiveCommandOptions> {
        var parsed = ParsedInteractiveCommandOptions()
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            if argument == commandName {
                return .success(parsed)
            }
            switch consumeInteractiveOption(
                argument,
                at: index,
                in: arguments,
                commandName: commandName,
                parsed: &parsed
            ) {
            case let .success(nextIndex):
                index = nextIndex ?? index + 1
            case let .failure(message, exitCode):
                return .failure(message, exitCode)
            }
        }
        return .success(parsed)
    }

    private func consumeInteractiveOption(
        _ argument: String,
        at index: Int,
        in arguments: [String],
        commandName: String,
        parsed: inout ParsedInteractiveCommandOptions
    ) -> ParseResult<Int?> {
        func value(after option: String) -> ParseResult<String> {
            guard index + 1 < arguments.count else {
                return .failure("codex-swift: missing value for \(option)", 64)
            }
            return .success(arguments[index + 1])
        }

        func compactValue(prefix: String) -> String {
            String(argument.dropFirst(prefix.count))
        }

        func setApprovalPolicy(_ approval: String) -> ParseResult<Void> {
            if let dangerouslyBypassOption = parsed.dangerouslyBypassOption {
                return .failure(interactivePermissionConflictMessage(
                    newOption: Self.approvalPolicyOptionDisplay,
                    existingOption: dangerouslyBypassOption
                ), 64)
            }
            parsed.approvalPolicy = approval
            parsed.approvalPolicyOption = Self.approvalPolicyOptionDisplay
            return .success(())
        }

        func setDangerouslyBypassApprovalsAndSandbox() -> ParseResult<Void> {
            if let approvalPolicyOption = parsed.approvalPolicyOption {
                return .failure(interactivePermissionConflictMessage(
                    newOption: Self.dangerouslyBypassOptionDisplay,
                    existingOption: approvalPolicyOption
                ), 64)
            }
            parsed.dangerouslyBypassApprovalsAndSandbox = true
            parsed.selectedSandboxMode = true
            parsed.dangerouslyBypassOption = Self.dangerouslyBypassOptionDisplay
            return .success(())
        }

        switch argument {
        case "--image", "-i":
            switch value(after: argument) {
            case let .success(paths):
                parsed.imagePaths.append(contentsOf: splitCommaDelimited(paths))
                return .success(index + 2)
            case let .failure(message, exitCode):
                return .failure(message, exitCode)
            }
        case "--model", "-m":
            switch value(after: argument) {
            case let .success(model):
                parsed.model = model
                return .success(index + 2)
            case let .failure(message, exitCode):
                return .failure(message, exitCode)
            }
        case "--local-provider":
            switch value(after: argument) {
            case let .success(provider):
                parsed.localProvider = provider
                return .success(index + 2)
            case let .failure(message, exitCode):
                return .failure(message, exitCode)
            }
        case "--profile", "-p":
            switch value(after: argument) {
            case let .success(profile):
                parsed.configProfile = profile
                return .success(index + 2)
            case let .failure(message, exitCode):
                return .failure(message, exitCode)
            }
        case "--profile-v2":
            switch value(after: argument) {
            case let .success(profile):
                switch validateProfileV2Name(profile) {
                case .success:
                    parsed.configProfileV2 = profile
                    return .success(index + 2)
                case let .failure(message, exitCode):
                    return .failure(message, exitCode)
                }
            case let .failure(message, exitCode):
                return .failure(message, exitCode)
            }
        case "--sandbox", "-s":
            switch value(after: argument) {
            case let .success(sandbox):
                parsed.sandboxMode = sandbox
                parsed.selectedSandboxMode = true
                return .success(index + 2)
            case let .failure(message, exitCode):
                return .failure(message, exitCode)
            }
        case "--ask-for-approval", "-a":
            switch value(after: argument) {
            case let .success(approval):
                switch setApprovalPolicy(approval) {
                case .success:
                    break
                case let .failure(message, exitCode):
                    return .failure(message, exitCode)
                }
                return .success(index + 2)
            case let .failure(message, exitCode):
                return .failure(message, exitCode)
            }
        case "--cd", "-C":
            switch value(after: argument) {
            case let .success(cwd):
                parsed.cwd = cwd
                return .success(index + 2)
            case let .failure(message, exitCode):
                return .failure(message, exitCode)
            }
        case "--add-dir":
            switch value(after: argument) {
            case let .success(root):
                parsed.additionalWritableRoots.append(root)
                return .success(index + 2)
            case let .failure(message, exitCode):
                return .failure(message, exitCode)
            }
        case "-c", "--config":
            switch value(after: argument) {
            case .success:
                return .success(index + 2)
            case let .failure(message, exitCode):
                return .failure(message, exitCode)
            }
        case "--remote":
            switch value(after: argument) {
            case let .success(remote):
                parsed.remote = remote
                return .success(index + 2)
            case let .failure(message, exitCode):
                return .failure(message, exitCode)
            }
        case "--remote-auth-token-env":
            switch value(after: argument) {
            case let .success(remoteAuthTokenEnv):
                parsed.remoteAuthTokenEnv = remoteAuthTokenEnv
                return .success(index + 2)
            case let .failure(message, exitCode):
                return .failure(message, exitCode)
            }
        case "--enable", "--disable", "--color":
            switch value(after: argument) {
            case .success:
                return .success(index + 2)
            case let .failure(message, exitCode):
                return .failure(message, exitCode)
            }
        case "--oss":
            parsed.useOSSProvider = true
            return .success(index + 1)
        case "--dangerously-bypass-approvals-and-sandbox", "--yolo":
            switch setDangerouslyBypassApprovalsAndSandbox() {
            case .success:
                break
            case let .failure(message, exitCode):
                return .failure(message, exitCode)
            }
            return .success(index + 1)
        case "--dangerously-bypass-hook-trust":
            parsed.bypassHookTrust = true
            return .success(index + 1)
        case "--ephemeral":
            parsed.ephemeral = true
            return .success(index + 1)
        case "--ignore-user-config":
            parsed.ignoreUserConfig = true
            return .success(index + 1)
        case "--ignore-rules":
            parsed.ignoreRules = true
            return .success(index + 1)
        case "--search":
            parsed.searchEnabled = true
            return .success(index + 1)
        case "--no-alt-screen":
            parsed.noAltScreen = true
            return .success(index + 1)
        case "--strict-config":
            parsed.strictConfig = true
            return .success(index + 1)
        default:
            break
        }

        if argument.hasPrefix("--image=") {
            parsed.imagePaths.append(contentsOf: splitCommaDelimited(compactValue(prefix: "--image=")))
            return .success(index + 1)
        }
        if argument.hasPrefix("-i"), argument.count > 2, !argument.hasPrefix("--") {
            parsed.imagePaths.append(contentsOf: splitCommaDelimited(compactValue(prefix: "-i")))
            return .success(index + 1)
        }
        if argument.hasPrefix("--model=") {
            parsed.model = compactValue(prefix: "--model=")
            return .success(index + 1)
        }
        if argument.hasPrefix("-m"), argument.count > 2, !argument.hasPrefix("--") {
            parsed.model = compactValue(prefix: "-m")
            return .success(index + 1)
        }
        if argument.hasPrefix("--local-provider=") {
            parsed.localProvider = compactValue(prefix: "--local-provider=")
            return .success(index + 1)
        }
        if argument.hasPrefix("--profile=") {
            parsed.configProfile = compactValue(prefix: "--profile=")
            return .success(index + 1)
        }
        if argument.hasPrefix("--profile-v2=") {
            let profile = compactValue(prefix: "--profile-v2=")
            switch validateProfileV2Name(profile) {
            case .success:
                parsed.configProfileV2 = profile
                return .success(index + 1)
            case let .failure(message, exitCode):
                return .failure(message, exitCode)
            }
        }
        if argument.hasPrefix("-p"), argument.count > 2, !argument.hasPrefix("--") {
            parsed.configProfile = compactValue(prefix: "-p")
            return .success(index + 1)
        }
        if argument.hasPrefix("--sandbox=") {
            parsed.sandboxMode = compactValue(prefix: "--sandbox=")
            parsed.selectedSandboxMode = true
            return .success(index + 1)
        }
        if argument.hasPrefix("-s"), argument.count > 2, !argument.hasPrefix("--") {
            parsed.sandboxMode = compactValue(prefix: "-s")
            parsed.selectedSandboxMode = true
            return .success(index + 1)
        }
        if argument.hasPrefix("--ask-for-approval=") {
            switch setApprovalPolicy(compactValue(prefix: "--ask-for-approval=")) {
            case .success:
                break
            case let .failure(message, exitCode):
                return .failure(message, exitCode)
            }
            return .success(index + 1)
        }
        if argument.hasPrefix("-a"), argument.count > 2, !argument.hasPrefix("--") {
            switch setApprovalPolicy(compactValue(prefix: "-a")) {
            case .success:
                break
            case let .failure(message, exitCode):
                return .failure(message, exitCode)
            }
            return .success(index + 1)
        }
        if argument.hasPrefix("--cd=") {
            parsed.cwd = compactValue(prefix: "--cd=")
            return .success(index + 1)
        }
        if argument.hasPrefix("-C"), argument.count > 2, !argument.hasPrefix("--") {
            parsed.cwd = compactValue(prefix: "-C")
            return .success(index + 1)
        }
        if argument.hasPrefix("--add-dir=") {
            parsed.additionalWritableRoots.append(compactValue(prefix: "--add-dir="))
            return .success(index + 1)
        }
        if argument.hasPrefix("-c=") {
            return .success(index + 1)
        }
        if argument.hasPrefix("--config=") {
            return .success(index + 1)
        }
        if argument.hasPrefix("--remote=") {
            parsed.remote = compactValue(prefix: "--remote=")
            return .success(index + 1)
        }
        if argument.hasPrefix("--remote-auth-token-env=") {
            parsed.remoteAuthTokenEnv = compactValue(prefix: "--remote-auth-token-env=")
            return .success(index + 1)
        }
        if argument.hasPrefix("--enable=") || argument.hasPrefix("--disable=") ||
            argument.hasPrefix("--color=") {
            return .success(index + 1)
        }

        return argument.hasPrefix("-")
            ? .failure("codex-swift: unsupported option for command '\(commandName)': \(argument)", 64)
            : .success(nil)
    }

    private func mergeInteractiveOptions(
        root: ParsedInteractiveCommandOptions,
        subcommand: ParsedInteractiveCommandOptions
    ) -> InteractiveCommandOptions {
        var sandboxMode = root.sandboxMode
        var dangerouslyBypass = root.dangerouslyBypassApprovalsAndSandbox
        if subcommand.selectedSandboxMode {
            sandboxMode = subcommand.sandboxMode
            dangerouslyBypass = subcommand.dangerouslyBypassApprovalsAndSandbox
        }

        return InteractiveCommandOptions(
            imagePaths: subcommand.imagePaths.isEmpty ? root.imagePaths : subcommand.imagePaths,
            model: subcommand.model ?? root.model,
            useOSSProvider: root.useOSSProvider || subcommand.useOSSProvider,
            localProvider: subcommand.localProvider ?? root.localProvider,
            configProfile: subcommand.configProfile ?? root.configProfile,
            configProfileV2: subcommand.configProfileV2 ?? root.configProfileV2,
            sandboxMode: sandboxMode,
            dangerouslyBypassApprovalsAndSandbox: dangerouslyBypass,
            cwd: subcommand.cwd ?? root.cwd,
            additionalWritableRoots: root.additionalWritableRoots + subcommand.additionalWritableRoots,
            approvalPolicy: subcommand.approvalPolicy ?? root.approvalPolicy,
            searchEnabled: root.searchEnabled || subcommand.searchEnabled,
            noAltScreen: root.noAltScreen || subcommand.noAltScreen,
            bypassHookTrust: root.bypassHookTrust || subcommand.bypassHookTrust,
            ephemeral: root.ephemeral || subcommand.ephemeral,
            ignoreUserConfig: root.ignoreUserConfig || subcommand.ignoreUserConfig,
            ignoreRules: root.ignoreRules || subcommand.ignoreRules
        )
    }

    private func parseInteractiveCommand(_ arguments: [String]) -> ParseResult<InteractiveCommandRequest> {
        var parsedOptions = ParsedInteractiveCommandOptions()
        var prompt: String?
        let configArguments = Array(arguments.prefix { $0 != "--" })
        var index = 0

        while index < arguments.count {
            let argument = arguments[index]
            if argument == "--" {
                let remaining = Array(arguments.dropFirst(index + 1))
                guard remaining.count <= 1 else {
                    return .failure("codex-swift: unexpected argument for interactive prompt: \(remaining[1])", 64)
                }
                prompt = remaining.first.map(normalizedInteractivePrompt)
                break
            }

            switch consumeInteractiveOption(
                argument,
                at: index,
                in: arguments,
                commandName: "interactive",
                parsed: &parsedOptions
            ) {
            case let .success(nextIndex):
                if let nextIndex {
                    index = nextIndex
                    continue
                }
            case let .failure(message, exitCode):
                return .failure(message, exitCode)
            }

            guard prompt == nil else {
                return .failure("codex-swift: unexpected argument for interactive prompt: \(argument)", 64)
            }
            prompt = normalizedInteractivePrompt(argument)
            index += 1
        }

        switch parseConfigOverrides(from: configArguments) {
        case let .success(configOverrides):
            return .success(InteractiveCommandRequest(
                prompt: prompt,
                remote: parsedOptions.remote,
                remoteAuthTokenEnv: parsedOptions.remoteAuthTokenEnv,
                interactiveOptions: mergeInteractiveOptions(
                    root: parsedOptions,
                    subcommand: ParsedInteractiveCommandOptions()
                ),
                configOverrides: configOverrides,
                strictConfig: parsedOptions.strictConfig
            ))
        case let .failure(message, exitCode):
            return .failure(message, exitCode)
        }
    }

    private func normalizedInteractivePrompt(_ prompt: String) -> String {
        prompt
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
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
        var configProfileV2: String?
        var removedFullAuto = false
        var strictConfig = strictConfigEnabled(in: rootArguments)
        var dangerouslyBypassApprovalsAndSandbox = rootDangerouslyBypassBeforeExec(in: rootArguments)
        var bypassHookTrust = rootBypassHookTrustBeforeExec(in: rootArguments)
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
            case "--profile-v2":
                switch value(after: argument, at: index) {
                case let .success(profile):
                    switch validateProfileV2Name(profile) {
                    case .success:
                        configProfileV2 = profile
                        index += 2
                        continue
                    case let .failure(message, exitCode):
                        return .failure(message, exitCode)
                    }
                case let .failure(message, exitCode):
                    return .failure(message, exitCode)
                }
            case "--full-auto":
                removedFullAuto = true
                index += 1
                continue
            case "--strict-config":
                strictConfig = true
                index += 1
                continue
            case "--dangerously-bypass-approvals-and-sandbox", "--yolo":
                dangerouslyBypassApprovalsAndSandbox = true
                index += 1
                continue
            case "--dangerously-bypass-hook-trust":
                bypassHookTrust = true
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
            if argument.hasPrefix("--profile-v2=") {
                let profile = String(argument.dropFirst("--profile-v2=".count))
                switch validateProfileV2Name(profile) {
                case .success:
                    configProfileV2 = profile
                    index += 1
                    continue
                case let .failure(message, exitCode):
                    return .failure(message, exitCode)
                }
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
                bypassHookTrust = bypassHookTrust || parsed.bypassHookTrust
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
                bypassHookTrust = bypassHookTrust || parsed.bypassHookTrust
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
                    configProfileV2: configProfileV2 ?? rootProfileV2(beforeCommands: ["exec", "e"], in: rootArguments),
                    removedFullAuto: removedFullAuto,
                    strictConfig: strictConfig,
                    bypassHookTrust: bypassHookTrust
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
        let bypassHookTrust: Bool
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
        var bypassHookTrust = false
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
            if argument == "--dangerously-bypass-hook-trust" {
                bypassHookTrust = true
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
            dangerouslyBypassApprovalsAndSandbox: dangerouslyBypassApprovalsAndSandbox,
            bypassHookTrust: bypassHookTrust
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
            "--profile-v2",
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
            "--dangerously-bypass-hook-trust",
            "--ephemeral",
            "--ignore-user-config",
            "--ignore-rules",
            "--skip-git-repo-check",
            "--json",
            "--experimental-json",
            "--strict-config"
        ].contains(argument)
    }

    private func execAssignmentOption(_ argument: String) -> Bool {
        [
            "--model=",
            "--local-provider=",
            "--profile=",
            "--profile-v2=",
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
        var strictConfig = strictConfigEnabled(in: rootArguments)
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
            if argument == "--strict-config" {
                strictConfig = true
                index += 1
                continue
            }
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
            return .success(ReviewCommandRequest(
                target: parsedTarget,
                configProfileV2: rootProfileV2(beforeCommand: "review", in: rootArguments),
                configOverrides: configOverrides,
                strictConfig: strictConfig
            ))
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
        var includeNonInteractive = false
        var remote: String?
        var remoteAuthTokenEnv: String?
        var subcommandOptions = ParsedInteractiveCommandOptions()
        var index = 0

        while index < arguments.count {
            let argument = arguments[index]
            if argument == "--last" {
                guard sessionID == nil else {
                    return .failure("codex-swift: argument conflict for command 'resume': --last conflicts with SESSION_ID", 64)
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
            if argument == "--include-non-interactive" {
                includeNonInteractive = true
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
            switch consumeInteractiveOption(
                argument,
                at: index,
                in: arguments,
                commandName: "resume",
                parsed: &subcommandOptions
            ) {
            case let .success(nextIndex):
                if let nextIndex {
                    index = nextIndex
                    continue
                }
            case let .failure(message, exitCode):
                return .failure(message, exitCode)
            }
            guard sessionID == nil else {
                return .failure("codex-swift: unexpected argument for command 'resume': \(argument)", 64)
            }
            guard !last else {
                return .failure("codex-swift: argument conflict for command 'resume': SESSION_ID conflicts with --last", 64)
            }
            sessionID = argument
            index += 1
        }

        let rootOptions: ParsedInteractiveCommandOptions
        switch parseRootInteractiveOptions(beforeCommand: "resume", in: rootArguments) {
        case let .success(options):
            rootOptions = options
        case let .failure(message, exitCode):
            return .failure(message, exitCode)
        }

        switch parseConfigOverrides(from: rootArguments) {
        case let .success(configOverrides):
            return .success(ResumeCommandRequest(
                sessionID: sessionID,
                last: last,
                all: all,
                includeNonInteractive: includeNonInteractive,
                remote: remote ?? rootRemoteFlagValue(named: "--remote", beforeCommand: "resume", in: rootArguments),
                remoteAuthTokenEnv: remoteAuthTokenEnv ?? rootRemoteFlagValue(
                    named: "--remote-auth-token-env",
                    beforeCommand: "resume",
                    in: rootArguments
                ),
                interactiveOptions: mergeInteractiveOptions(root: rootOptions, subcommand: subcommandOptions),
                configOverrides: configOverrides,
                strictConfig: rootOptions.strictConfig || subcommandOptions.strictConfig
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
        var subcommandOptions = ParsedInteractiveCommandOptions()
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
            switch consumeInteractiveOption(
                argument,
                at: index,
                in: arguments,
                commandName: "fork",
                parsed: &subcommandOptions
            ) {
            case let .success(nextIndex):
                if let nextIndex {
                    index = nextIndex
                    continue
                }
            case let .failure(message, exitCode):
                return .failure(message, exitCode)
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

        let rootOptions: ParsedInteractiveCommandOptions
        switch parseRootInteractiveOptions(beforeCommand: "fork", in: rootArguments) {
        case let .success(options):
            rootOptions = options
        case let .failure(message, exitCode):
            return .failure(message, exitCode)
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
                interactiveOptions: mergeInteractiveOptions(root: rootOptions, subcommand: subcommandOptions),
                configOverrides: configOverrides,
                strictConfig: rootOptions.strictConfig || subcommandOptions.strictConfig
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
        var useAgentIdentityAuth = false
        var seenSingleValueOptions = Set<String>()
        var index = 0

        func markSingleValueOption(_ option: String) -> ParseResult<Void> {
            guard seenSingleValueOptions.insert(option).inserted else {
                return .failure("codex-swift: duplicate option for command 'exec-server': \(option)", 64)
            }
            return .success(())
        }

        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--listen", "--remote", "--executor-id", "--name":
                switch markSingleValueOption(argument) {
                case .success:
                    break
                case let .failure(message, exitCode):
                    return .failure(message, exitCode)
                }
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
                    switch markSingleValueOption("--listen") {
                    case .success:
                        break
                    case let .failure(message, exitCode):
                        return .failure(message, exitCode)
                    }
                    guard remote == nil else {
                        return .failure("codex-swift: argument conflict for command 'exec-server': --listen conflicts with --remote", 64)
                    }
                    listen = String(argument.dropFirst("--listen=".count))
                    index += 1
                } else if argument.hasPrefix("--remote=") {
                    switch markSingleValueOption("--remote") {
                    case .success:
                        break
                    case let .failure(message, exitCode):
                        return .failure(message, exitCode)
                    }
                    guard listen == nil else {
                        return .failure("codex-swift: argument conflict for command 'exec-server': --remote conflicts with --listen", 64)
                    }
                    remote = String(argument.dropFirst("--remote=".count))
                    index += 1
                } else if argument.hasPrefix("--executor-id=") {
                    switch markSingleValueOption("--executor-id") {
                    case .success:
                        break
                    case let .failure(message, exitCode):
                        return .failure(message, exitCode)
                    }
                    executorID = String(argument.dropFirst("--executor-id=".count))
                    index += 1
                } else if argument.hasPrefix("--name=") {
                    switch markSingleValueOption("--name") {
                    case .success:
                        break
                    case let .failure(message, exitCode):
                        return .failure(message, exitCode)
                    }
                    name = String(argument.dropFirst("--name=".count))
                    index += 1
                } else if argument == "--use-agent-identity-auth" {
                    useAgentIdentityAuth = true
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
            let configOverrides: CliConfigOverrides
            switch parseConfigOverrides(from: rootArguments) {
            case let .success(overrides):
                configOverrides = overrides
            case let .failure(message, exitCode):
                return .failure(message, exitCode)
            }
            return .success(ExecServerCommandRequest(
                action: .remote(
                    baseURL: remote,
                    executorID: executorID,
                    name: name,
                    useAgentIdentityAuth: useAgentIdentityAuth
                ),
                configProfileV2: rootProfileV2(beforeCommand: "exec-server", in: rootArguments),
                configOverrides: configOverrides
            ))
        }

        if useAgentIdentityAuth {
            return .failure(
                "codex-swift: --use-agent-identity-auth requires --remote",
                64
            )
        }

        return .success(ExecServerCommandRequest(action: .listen(url: listen ?? defaultExecServerListenURL)))
    }

    private func parseMcpServerCommand(
        _ arguments: [String],
        rootArguments: [String]
    ) -> ParseResult<McpServerCommandRequest> {
        var strictConfig = strictConfigEnabled(in: rootArguments)
        for argument in arguments {
            if argument == "--strict-config" {
                strictConfig = true
                continue
            }
            if argument.hasPrefix("-") {
                return .failure("codex-swift: unsupported option for command 'mcp-server': \(argument)", 64)
            }
            return .failure("codex-swift: unexpected argument for command 'mcp-server': \(argument)", 64)
        }

        switch parseConfigOverrides(from: rootArguments) {
        case let .success(configOverrides):
            return .success(McpServerCommandRequest(
                configOverrides: configOverrides,
                strictConfig: strictConfig
            ))
        case let .failure(message, exitCode):
            return .failure(message, exitCode)
        }
    }

    private func parseAppServerCommand(
        _ arguments: [String],
        rootArguments: [String]
    ) -> ParseResult<AppServerCommandRequest> {
        let parsedOptions: ParsedAppServerOptions
        let commandArguments: [String]
        switch parseAppServerOptions(arguments) {
        case let .success(parsed):
            parsedOptions = parsed.options
            commandArguments = parsed.remainingArguments
        case let .failure(message, exitCode):
            return .failure(message, exitCode)
        }

        let action: AppServerCommandAction
        guard let subcommand = commandArguments.first else {
            action = .run
            return appServerRequest(action: action, options: parsedOptions, rootArguments: rootArguments)
        }

        switch subcommand {
        case "daemon":
            switch parseAppServerDaemon(Array(commandArguments.dropFirst())) {
            case let .success(parsed):
                action = parsed
            case let .failure(message, exitCode):
                return .failure(message, exitCode)
            }
        case "proxy":
            switch parseAppServerProxy(Array(commandArguments.dropFirst())) {
            case let .success(socketPath):
                action = .proxy(socketPath: socketPath)
            case let .failure(message, exitCode):
                return .failure(message, exitCode)
            }
        case "generate-ts":
            switch parseAppServerGenerateTS(Array(commandArguments.dropFirst())) {
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
            switch parseAppServerGenerateJSONSchema(Array(commandArguments.dropFirst())) {
            case let .success(parsed):
                action = .generateJSONSchema(outDir: parsed.outDir, experimental: parsed.experimental)
            case let .failure(message, exitCode):
                return .failure(message, exitCode)
            }
        case "generate-internal-json-schema":
            switch parseAppServerGenerateInternalJSONSchema(Array(commandArguments.dropFirst())) {
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

        return appServerRequest(action: action, options: parsedOptions, rootArguments: rootArguments)
    }

    private func parseAppServerDaemon(_ arguments: [String]) -> ParseResult<AppServerCommandAction> {
        guard let subcommand = arguments.first else {
            return .failure("codex-swift: missing app-server daemon subcommand", 64)
        }
        let remainder = Array(arguments.dropFirst())
        switch subcommand {
        case "start":
            return parseNoArguments(remainder, commandName: "app-server daemon start", action: .daemonStart)
        case "restart":
            return parseNoArguments(remainder, commandName: "app-server daemon restart", action: .daemonRestart)
        case "stop":
            return parseNoArguments(remainder, commandName: "app-server daemon stop", action: .daemonStop)
        case "version":
            return parseNoArguments(remainder, commandName: "app-server daemon version", action: .daemonVersion)
        case "pid-update-loop":
            return parseNoArguments(remainder, commandName: "app-server daemon pid-update-loop", action: .daemonPidUpdateLoop)
        case "enable-remote-control":
            return parseNoArguments(remainder, commandName: "app-server daemon enable-remote-control", action: .daemonEnableRemoteControl)
        case "disable-remote-control":
            return parseNoArguments(remainder, commandName: "app-server daemon disable-remote-control", action: .daemonDisableRemoteControl)
        case "bootstrap":
            return parseAppServerDaemonBootstrap(remainder)
        default:
            if subcommand.hasPrefix("-") {
                return .failure("codex-swift: unsupported option for command 'app-server daemon': \(subcommand)", 64)
            }
            return .failure("codex-swift: unsupported app-server daemon subcommand: \(subcommand)", 64)
        }
    }

    private func parseNoArguments(
        _ arguments: [String],
        commandName: String,
        action: AppServerCommandAction
    ) -> ParseResult<AppServerCommandAction> {
        guard arguments.isEmpty else {
            let argument = arguments[0]
            if argument.hasPrefix("-") {
                return .failure("codex-swift: unsupported option for command '\(commandName)': \(argument)", 64)
            }
            return .failure("codex-swift: unexpected argument for command '\(commandName)': \(argument)", 64)
        }
        return .success(action)
    }

    private func parseAppServerDaemonBootstrap(_ arguments: [String]) -> ParseResult<AppServerCommandAction> {
        var remoteControlEnabled = false
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            if argument == "--remote-control" {
                remoteControlEnabled = true
                index += 1
                continue
            }
            if argument.hasPrefix("-") {
                return .failure("codex-swift: unsupported option for command 'app-server daemon bootstrap': \(argument)", 64)
            }
            return .failure("codex-swift: unexpected argument for command 'app-server daemon bootstrap': \(argument)", 64)
        }
        return .success(.daemonBootstrap(remoteControlEnabled: remoteControlEnabled))
    }

    private func parseRemoteControlCommand(
        _ arguments: [String],
        rootArguments: [String]
    ) -> ParseResult<AppServerCommandRequest> {
        let rootSubcommand = commandArgument(after: "remote-control", in: rootArguments)
        let commandName: String
        let commandArguments: [String]
        let action: AppServerCommandAction
        let remoteControlEnabled: Bool
        if arguments.first == "start" || rootSubcommand == "start" {
            commandName = "remote-control start"
            commandArguments = arguments.first == "start" ? Array(arguments.dropFirst()) : arguments
            action = .remoteControl
            remoteControlEnabled = true
        } else if arguments.first == "stop" || rootSubcommand == "stop" {
            commandName = "remote-control stop"
            commandArguments = arguments.first == "stop" ? Array(arguments.dropFirst()) : arguments
            action = .remoteControlStop
            remoteControlEnabled = false
        } else {
            commandName = "remote-control"
            commandArguments = arguments
            action = .remoteControl
            remoteControlEnabled = true
        }
        if let remote = rootRemoteFlagValue(named: "--remote", beforeCommand: "remote-control", in: rootArguments) {
            return .failure(
                "`--remote \(remote)` is only supported for interactive TUI commands, not `codex \(commandName)`",
                1
            )
        }
        if rootRemoteFlagValue(named: "--remote-auth-token-env", beforeCommand: "remote-control", in: rootArguments) != nil {
            return .failure(
                "`--remote-auth-token-env` is only supported for interactive TUI commands, not `codex \(commandName)`",
                1
            )
        }
        guard commandArguments.isEmpty else {
            let argument = commandArguments[0]
            if argument.hasPrefix("-") {
                return .failure("codex-swift: unsupported option for command '\(commandName)': \(argument)", 64)
            }
            if commandName == "remote-control" {
                return .failure("codex-swift: unsupported remote-control subcommand: \(argument)", 64)
            }
            return .failure("codex-swift: unexpected argument for command '\(commandName)': \(argument)", 64)
        }
        switch parseConfigOverrides(from: rootArguments) {
        case let .success(configOverrides):
            return .success(AppServerCommandRequest(
                action: action,
                listenTransport: .off,
                remoteControlEnabled: remoteControlEnabled,
                configOverrides: configOverrides
            ))
        case let .failure(message, exitCode):
            return .failure(message, exitCode)
        }
    }

    private func rootRemoteFlagValue(named option: String, beforeCommand command: String, in arguments: [String]) -> String? {
        rootRemoteFlagValue(named: option, beforeCommands: [command], in: arguments)
    }

    private func rootProfileV2(beforeCommand command: String, in arguments: [String]) -> String? {
        rootOptionValue(named: "--profile-v2", beforeCommands: [command], in: arguments)
    }

    private func rootProfileV2(beforeCommands commands: [String], in arguments: [String]) -> String? {
        rootOptionValue(named: "--profile-v2", beforeCommands: commands, in: arguments)
    }

    private func commandArgument(after command: String, in arguments: [String]) -> String? {
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            if argument == command {
                return index + 1 < arguments.count ? arguments[index + 1] : nil
            }
            if optionConsumesValue(argument) {
                index += 2
            } else {
                index += 1
            }
        }
        return nil
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
        rootOptionValue(named: option, beforeCommands: commands, in: arguments)
    }

    private func rootOptionValue(named option: String, beforeCommands commands: [String], in arguments: [String]) -> String? {
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
        case let .command(spec, _),
             let .commandHelp(spec, _),
             let .commandVersion(spec),
             let .commandUnsupportedVersion(spec, _):
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

    private func rootProfileV2RejectionMessage(invocation: Invocation, arguments: [String]) -> String? {
        let commandNames: [String] = switch invocation {
        case let .command(spec, _),
             let .commandHelp(spec, _),
             let .commandVersion(spec),
             let .commandUnsupportedVersion(spec, _):
            [spec.name] + spec.aliases
        case .version, .help, .interactive, .unknown:
            []
        }
        guard let profile = rootOptionValue(named: "--profile-v2", beforeCommands: commandNames, in: arguments) else {
            return nil
        }
        if case let .failure(message, _) = validateProfileV2Name(profile) {
            return message
        }

        switch invocation {
        case .interactive:
            return nil
        case let .command(spec, commandArguments), let .commandHelp(spec, commandArguments):
            switch spec.name {
            case "exec", "review", "resume", "fork", "exec-server":
                return nil
            case "debug" where commandArguments.first == "prompt-input":
                return nil
            default:
                return "--profile-v2 only applies to runtime commands: `codex`, `codex exec`, `codex review`, `codex resume`, `codex fork`, `codex exec-server`, and `codex debug prompt-input`."
            }
        case .version, .commandVersion, .commandUnsupportedVersion, .help, .unknown:
            return nil
        }
    }

    private struct RootDuplicateOptionSpec {
        let displayName: String
        let longValueName: String?
        let shortValueName: String?
        let flagNames: Set<String>

        func matches(_ argument: String) -> Bool {
            if let longValueName,
               argument == longValueName || argument.hasPrefix("\(longValueName)=") {
                return true
            }
            if let shortValueName,
               argument == shortValueName ||
                argument.hasPrefix(shortValueName) && argument.count > shortValueName.count && !argument.hasPrefix("--") {
                return true
            }
            return flagNames.contains(argument)
        }

        func consumesSeparateValue(_ argument: String) -> Bool {
            argument == longValueName || argument == shortValueName
        }
    }

    private static let rootDuplicateOptionSpecs = [
        RootDuplicateOptionSpec(displayName: "--model", longValueName: "--model", shortValueName: "-m", flagNames: []),
        RootDuplicateOptionSpec(displayName: "--oss", longValueName: nil, shortValueName: nil, flagNames: ["--oss"]),
        RootDuplicateOptionSpec(displayName: "--profile", longValueName: "--profile", shortValueName: "-p", flagNames: []),
        RootDuplicateOptionSpec(displayName: "--profile-v2", longValueName: "--profile-v2", shortValueName: nil, flagNames: []),
        RootDuplicateOptionSpec(displayName: "--sandbox", longValueName: "--sandbox", shortValueName: "-s", flagNames: []),
        RootDuplicateOptionSpec(
            displayName: "--ask-for-approval",
            longValueName: "--ask-for-approval",
            shortValueName: "-a",
            flagNames: []
        ),
        RootDuplicateOptionSpec(displayName: "--search", longValueName: nil, shortValueName: nil, flagNames: ["--search"])
    ]

    private func rootDuplicateSharedOptionRejectionMessage(invocation: Invocation, arguments: [String]) -> String? {
        let commandNames: [String] = switch invocation {
        case let .command(spec, _),
             let .commandHelp(spec, _),
             let .commandVersion(spec),
             let .commandUnsupportedVersion(spec, _):
            [spec.name] + spec.aliases
        case .version, .help, .interactive, .unknown:
            []
        }

        var seenOptions = Set<String>()
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            if argument == "--" || commandNames.contains(argument) {
                return nil
            }

            if let spec = Self.rootDuplicateOptionSpecs.first(where: { $0.matches(argument) }) {
                guard !seenOptions.contains(spec.displayName) else {
                    return "codex-swift: duplicate option at top level: \(spec.displayName)"
                }
                seenOptions.insert(spec.displayName)
                index += spec.consumesSeparateValue(argument) ? 2 : 1
                continue
            }

            if optionConsumesValue(argument) {
                index += 2
            } else {
                index += 1
            }
        }

        return nil
    }

    private func rootInteractivePermissionConflictRejectionMessage(
        invocation: Invocation,
        arguments: [String]
    ) -> String? {
        switch invocation {
        case .version, .commandVersion, .commandUnsupportedVersion, .help:
            return nil
        case let .command(spec, _), let .commandHelp(spec, _):
            return rootInteractivePermissionConflictMessage(
                beforeCommands: [spec.name] + spec.aliases,
                in: arguments
            )
        case .interactive, .unknown:
            return rootInteractivePermissionConflictMessage(beforeCommands: [], in: arguments)
        }
    }

    private func rootInteractivePermissionConflictMessage(
        beforeCommands commands: [String],
        in arguments: [String]
    ) -> String? {
        var approvalPolicyOption: String?
        var dangerouslyBypassOption: String?
        var index = 0

        while index < arguments.count {
            let argument = arguments[index]
            if argument == "--" || commands.contains(argument) {
                return nil
            }

            if argument == "--ask-for-approval" || argument == "-a" ||
                argument.hasPrefix("--ask-for-approval=") ||
                argument.hasPrefix("-a") && argument.count > 2 && !argument.hasPrefix("--") {
                if let dangerouslyBypassOption {
                    return interactivePermissionConflictMessage(
                        newOption: Self.approvalPolicyOptionDisplay,
                        existingOption: dangerouslyBypassOption
                    )
                }
                approvalPolicyOption = Self.approvalPolicyOptionDisplay
                index += (argument == "--ask-for-approval" || argument == "-a") ? 2 : 1
                continue
            }

            if argument == "--dangerously-bypass-approvals-and-sandbox" || argument == "--yolo" {
                if let approvalPolicyOption {
                    return interactivePermissionConflictMessage(
                        newOption: Self.dangerouslyBypassOptionDisplay,
                        existingOption: approvalPolicyOption
                    )
                }
                dangerouslyBypassOption = Self.dangerouslyBypassOptionDisplay
                index += 1
                continue
            }

            if optionConsumesValue(argument) {
                index += 2
            } else {
                index += 1
            }
        }

        return nil
    }

    private func interactivePermissionConflictMessage(newOption: String, existingOption: String) -> String {
        "codex-swift: argument conflict: the argument '\(newOption)' cannot be used with '\(existingOption)'"
    }

    private func rootDangerouslyBypassBeforeExec(in arguments: [String]) -> Bool {
        let execCommands = ["exec", "e"]
        return rootFlagPresent(
            named: "--dangerously-bypass-approvals-and-sandbox",
            beforeCommands: execCommands,
            in: arguments
        ) || rootFlagPresent(named: "--yolo", beforeCommands: execCommands, in: arguments)
    }

    private func rootBypassHookTrustBeforeExec(in arguments: [String]) -> Bool {
        rootFlagPresent(
            named: "--dangerously-bypass-hook-trust",
            beforeCommands: ["exec", "e"],
            in: arguments
        )
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
        case "remote-control":
            switch commandArguments.first {
            case "start":
                return "remote-control start"
            case "stop":
                return "remote-control stop"
            default:
                return "remote-control"
            }
        case "exec", "computer-use", "review", "login", "logout", "mcp", "plugin",
             "mcp-server", "app", "completion", "update", "cloud",
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
        case "daemon":
            guard arguments.count > 1 else {
                return "app-server daemon"
            }
            switch arguments[1] {
            case "bootstrap":
                return "app-server daemon bootstrap"
            case "start":
                return "app-server daemon start"
            case "restart":
                return "app-server daemon restart"
            case "enable-remote-control":
                return "app-server daemon enable-remote-control"
            case "disable-remote-control":
                return "app-server daemon disable-remote-control"
            case "stop":
                return "app-server daemon stop"
            case "version":
                return "app-server daemon version"
            case "pid-update-loop":
                return "app-server daemon pid-update-loop"
            default:
                return "app-server daemon"
            }
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
        options: ParsedAppServerOptions = ParsedAppServerOptions(),
        rootArguments: [String]
    ) -> ParseResult<AppServerCommandRequest> {
        switch parseConfigOverrides(from: rootArguments) {
        case let .success(configOverrides):
            return .success(AppServerCommandRequest(
                action: action,
                listenTransport: options.listenTransport,
                sessionSource: options.sessionSource,
                analyticsDefaultEnabled: options.analyticsDefaultEnabled,
                remoteControlEnabled: options.remoteControlEnabled,
                websocketAuth: options.websocketAuth,
                configOverrides: configOverrides,
                strictConfig: options.strictConfig || strictConfigEnabled(in: rootArguments)
            ))
        case let .failure(message, exitCode):
            return .failure(message, exitCode)
        }
    }

    private struct ParsedAppServerOptions {
        var listenTransport: AppServerListenTransport = .stdio
        var sessionSource: SessionSource = .vscode
        var analyticsDefaultEnabled = false
        var remoteControlEnabled = false
        var websocketAuth = AppServerWebsocketAuthArguments()
        var strictConfig = false
    }

    private func parseAppServerOptions(
        _ arguments: [String]
    ) -> ParseResult<(options: ParsedAppServerOptions, remainingArguments: [String])> {
        var options = ParsedAppServerOptions()
        var websocketAuthMode: AppServerWebsocketAuthMode?
        var tokenFile: String?
        var tokenSHA256: String?
        var sharedSecretFile: String?
        var issuer: String?
        var audience: String?
        var maxClockSkewSeconds: UInt64?
        var seenSingleValueOptions = Set<String>()
        var index = 0

        func value(after option: String) -> ParseResult<String> {
            guard index + 1 < arguments.count else {
                return .failure("codex-swift: missing value for \(option)", 64)
            }
            return .success(arguments[index + 1])
        }

        func markSingleValueOption(_ option: String) -> ParseResult<Void> {
            guard seenSingleValueOptions.insert(option).inserted else {
                return .failure("codex-swift: duplicate option for command 'app-server': \(option)", 64)
            }
            return .success(())
        }

        while index < arguments.count {
            let argument = arguments[index]
            if argument == "--analytics-default-enabled" {
                options.analyticsDefaultEnabled = true
                index += 1
                continue
            }
            if argument == "--remote-control" {
                options.remoteControlEnabled = true
                index += 1
                continue
            }
            if argument == "--strict-config" {
                options.strictConfig = true
                index += 1
                continue
            }
            if argument == "--listen" {
                switch markSingleValueOption("--listen") {
                case .success:
                    break
                case let .failure(message, exitCode):
                    return .failure(message, exitCode)
                }
                switch value(after: argument) {
                case let .success(listenURL):
                    switch parseAppServerListenTransport(listenURL) {
                    case let .success(transport):
                        options.listenTransport = transport
                    case let .failure(message, exitCode):
                        return .failure(message, exitCode)
                    }
                case let .failure(message, exitCode):
                    return .failure(message, exitCode)
                }
                index += 2
                continue
            }
            if argument.hasPrefix("--listen=") {
                switch markSingleValueOption("--listen") {
                case .success:
                    break
                case let .failure(message, exitCode):
                    return .failure(message, exitCode)
                }
                let listenURL = String(argument.dropFirst("--listen=".count))
                switch parseAppServerListenTransport(listenURL) {
                case let .success(transport):
                    options.listenTransport = transport
                case let .failure(message, exitCode):
                    return .failure(message, exitCode)
                }
                index += 1
                continue
            }
            if argument == "--session-source" {
                switch markSingleValueOption("--session-source") {
                case .success:
                    break
                case let .failure(message, exitCode):
                    return .failure(message, exitCode)
                }
                switch value(after: argument) {
                case let .success(rawSource):
                    switch parseAppServerSessionSource(rawSource) {
                    case let .success(source):
                        options.sessionSource = source
                    case let .failure(message, exitCode):
                        return .failure(message, exitCode)
                    }
                case let .failure(message, exitCode):
                    return .failure(message, exitCode)
                }
                index += 2
                continue
            }
            if argument.hasPrefix("--session-source=") {
                switch markSingleValueOption("--session-source") {
                case .success:
                    break
                case let .failure(message, exitCode):
                    return .failure(message, exitCode)
                }
                let rawSource = String(argument.dropFirst("--session-source=".count))
                switch parseAppServerSessionSource(rawSource) {
                case let .success(source):
                    options.sessionSource = source
                case let .failure(message, exitCode):
                    return .failure(message, exitCode)
                }
                index += 1
                continue
            }
            if argument == "--ws-auth" {
                switch markSingleValueOption("--ws-auth") {
                case .success:
                    break
                case let .failure(message, exitCode):
                    return .failure(message, exitCode)
                }
                switch value(after: argument) {
                case let .success(mode):
                    switch parseAppServerWebsocketAuthMode(mode) {
                    case let .success(parsed):
                        websocketAuthMode = parsed
                    case let .failure(message, exitCode):
                        return .failure(message, exitCode)
                    }
                case let .failure(message, exitCode):
                    return .failure(message, exitCode)
                }
                index += 2
                continue
            }
            if argument.hasPrefix("--ws-auth=") {
                switch markSingleValueOption("--ws-auth") {
                case .success:
                    break
                case let .failure(message, exitCode):
                    return .failure(message, exitCode)
                }
                switch parseAppServerWebsocketAuthMode(String(argument.dropFirst("--ws-auth=".count))) {
                case let .success(parsed):
                    websocketAuthMode = parsed
                case let .failure(message, exitCode):
                    return .failure(message, exitCode)
                }
                index += 1
                continue
            }

            let stringOptions = [
                "--ws-token-file": { (value: String) in tokenFile = value },
                "--ws-token-sha256": { (value: String) in tokenSHA256 = value },
                "--ws-shared-secret-file": { (value: String) in sharedSecretFile = value },
                "--ws-issuer": { (value: String) in issuer = value },
                "--ws-audience": { (value: String) in audience = value }
            ]
            if let assign = stringOptions[argument] {
                switch markSingleValueOption(argument) {
                case .success:
                    break
                case let .failure(message, exitCode):
                    return .failure(message, exitCode)
                }
                switch value(after: argument) {
                case let .success(rawValue):
                    assign(rawValue)
                case let .failure(message, exitCode):
                    return .failure(message, exitCode)
                }
                index += 2
                continue
            }
            if let equalIndex = argument.firstIndex(of: "=") {
                let option = String(argument[..<equalIndex])
                if let assign = stringOptions[option] {
                    switch markSingleValueOption(option) {
                    case .success:
                        break
                    case let .failure(message, exitCode):
                        return .failure(message, exitCode)
                    }
                    assign(String(argument[argument.index(after: equalIndex)...]))
                    index += 1
                    continue
                }
            }
            if argument == "--ws-max-clock-skew-seconds" {
                switch markSingleValueOption("--ws-max-clock-skew-seconds") {
                case .success:
                    break
                case let .failure(message, exitCode):
                    return .failure(message, exitCode)
                }
                switch value(after: argument) {
                case let .success(rawValue):
                    switch parseUInt64Option(rawValue, option: argument, command: "app-server") {
                    case let .success(parsed):
                        maxClockSkewSeconds = parsed
                    case let .failure(message, exitCode):
                        return .failure(message, exitCode)
                    }
                case let .failure(message, exitCode):
                    return .failure(message, exitCode)
                }
                index += 2
                continue
            }
            if argument.hasPrefix("--ws-max-clock-skew-seconds=") {
                switch markSingleValueOption("--ws-max-clock-skew-seconds") {
                case .success:
                    break
                case let .failure(message, exitCode):
                    return .failure(message, exitCode)
                }
                let rawValue = String(argument.dropFirst("--ws-max-clock-skew-seconds=".count))
                switch parseUInt64Option(rawValue, option: "--ws-max-clock-skew-seconds", command: "app-server") {
                case let .success(parsed):
                    maxClockSkewSeconds = parsed
                case let .failure(message, exitCode):
                    return .failure(message, exitCode)
                }
                index += 1
                continue
            }

            return .success((
                options: ParsedAppServerOptions(
                    listenTransport: options.listenTransport,
                    sessionSource: options.sessionSource,
                    analyticsDefaultEnabled: options.analyticsDefaultEnabled,
                    remoteControlEnabled: options.remoteControlEnabled,
                    websocketAuth: AppServerWebsocketAuthArguments(
                        mode: websocketAuthMode,
                        tokenFile: tokenFile,
                        tokenSHA256: tokenSHA256,
                        sharedSecretFile: sharedSecretFile,
                        issuer: issuer,
                        audience: audience,
                        maxClockSkewSeconds: maxClockSkewSeconds
                    ),
                    strictConfig: options.strictConfig
                ),
                remainingArguments: Array(arguments[index...])
            ))
        }

        options.websocketAuth = AppServerWebsocketAuthArguments(
            mode: websocketAuthMode,
            tokenFile: tokenFile,
            tokenSHA256: tokenSHA256,
            sharedSecretFile: sharedSecretFile,
            issuer: issuer,
            audience: audience,
            maxClockSkewSeconds: maxClockSkewSeconds
        )
        return .success((options: options, remainingArguments: []))
    }

    private func parseAppServerSessionSource(_ rawValue: String) -> ParseResult<SessionSource> {
        do {
            return .success(try SessionSource.fromStartupArg(rawValue))
        } catch {
            return .failure("codex-swift: invalid value for --session-source: \(error)", 64)
        }
    }

    private func parseAppServerListenTransport(_ listenURL: String) -> ParseResult<AppServerListenTransport> {
        do {
            return .success(try AppServerListenURLParser.parse(listenURL))
        } catch {
            return .failure(String(describing: error), 64)
        }
    }

    private func parseAppServerWebsocketAuthMode(_ rawValue: String) -> ParseResult<AppServerWebsocketAuthMode> {
        switch rawValue {
        case "capability-token":
            return .success(.capabilityToken)
        case "signed-bearer-token":
            return .success(.signedBearerToken)
        default:
            return .failure("codex-swift: invalid value for --ws-auth: \(rawValue)", 64)
        }
    }

    private func parseUInt64Option(_ rawValue: String, option: String, command: String) -> ParseResult<UInt64> {
        guard let parsed = UInt64(rawValue) else {
            return .failure("codex-swift: invalid value for command '\(command)' \(option): \(rawValue)", 64)
        }
        return .success(parsed)
    }

    private func parseAppServerProxy(_ arguments: [String]) -> ParseResult<String?> {
        var socketPath: String?
        var seenSocketPath = false
        var index = 0

        while index < arguments.count {
            let argument = arguments[index]
            if argument == "--sock" {
                guard !seenSocketPath else {
                    return .failure("codex-swift: duplicate option for command 'app-server proxy': --sock", 64)
                }
                seenSocketPath = true
                guard index + 1 < arguments.count else {
                    return .failure("codex-swift: missing value for \(argument)", 64)
                }
                socketPath = normalizeAppServerProxySocketPath(arguments[index + 1])
                index += 2
                continue
            }
            if argument.hasPrefix("--sock=") {
                guard !seenSocketPath else {
                    return .failure("codex-swift: duplicate option for command 'app-server proxy': --sock", 64)
                }
                seenSocketPath = true
                socketPath = normalizeAppServerProxySocketPath(String(argument.dropFirst("--sock=".count)))
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

    private func normalizeAppServerProxySocketPath(_ rawPath: String) -> String {
        if rawPath.hasPrefix("/") {
            return rawPath
        }

        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent(rawPath)
            .standardizedFileURL
            .path
    }

    private func parseAppServerGenerateTS(
        _ arguments: [String]
    ) -> ParseResult<(outDir: String, prettier: String?, experimental: Bool)> {
        var outDir: String?
        var prettier: String?
        var experimental = false
        var seenOutDir = false
        var seenPrettier = false
        var index = 0

        while index < arguments.count {
            let argument = arguments[index]
            if argument == "--out" || argument == "-o" {
                guard !seenOutDir else {
                    return .failure("codex-swift: duplicate option for command 'app-server generate-ts': --out", 64)
                }
                seenOutDir = true
                guard index + 1 < arguments.count else {
                    return .failure("codex-swift: missing value for \(argument)", 64)
                }
                outDir = arguments[index + 1]
                index += 2
                continue
            }
            if argument.hasPrefix("--out=") {
                guard !seenOutDir else {
                    return .failure("codex-swift: duplicate option for command 'app-server generate-ts': --out", 64)
                }
                seenOutDir = true
                outDir = String(argument.dropFirst("--out=".count))
                index += 1
                continue
            }
            if argument.hasPrefix("-o"), argument.count > 2, !argument.hasPrefix("--") {
                guard !seenOutDir else {
                    return .failure("codex-swift: duplicate option for command 'app-server generate-ts': --out", 64)
                }
                seenOutDir = true
                outDir = String(argument.dropFirst(2))
                index += 1
                continue
            }
            if argument == "--prettier" || argument == "-p" {
                guard !seenPrettier else {
                    return .failure("codex-swift: duplicate option for command 'app-server generate-ts': --prettier", 64)
                }
                seenPrettier = true
                guard index + 1 < arguments.count else {
                    return .failure("codex-swift: missing value for \(argument)", 64)
                }
                prettier = arguments[index + 1]
                index += 2
                continue
            }
            if argument.hasPrefix("--prettier=") {
                guard !seenPrettier else {
                    return .failure("codex-swift: duplicate option for command 'app-server generate-ts': --prettier", 64)
                }
                seenPrettier = true
                prettier = String(argument.dropFirst("--prettier=".count))
                index += 1
                continue
            }
            if argument.hasPrefix("-p"), argument.count > 2, !argument.hasPrefix("--") {
                guard !seenPrettier else {
                    return .failure("codex-swift: duplicate option for command 'app-server generate-ts': --prettier", 64)
                }
                seenPrettier = true
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
        var seenOutDir = false
        var index = 0

        while index < arguments.count {
            let argument = arguments[index]
            if argument == "--out" || argument == "-o" {
                guard !seenOutDir else {
                    return .failure("codex-swift: duplicate option for command 'app-server generate-json-schema': --out", 64)
                }
                seenOutDir = true
                guard index + 1 < arguments.count else {
                    return .failure("codex-swift: missing value for \(argument)", 64)
                }
                outDir = arguments[index + 1]
                index += 2
                continue
            }
            if argument.hasPrefix("--out=") {
                guard !seenOutDir else {
                    return .failure("codex-swift: duplicate option for command 'app-server generate-json-schema': --out", 64)
                }
                seenOutDir = true
                outDir = String(argument.dropFirst("--out=".count))
                index += 1
                continue
            }
            if argument.hasPrefix("-o"), argument.count > 2, !argument.hasPrefix("--") {
                guard !seenOutDir else {
                    return .failure("codex-swift: duplicate option for command 'app-server generate-json-schema': --out", 64)
                }
                seenOutDir = true
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
        var seenOutDir = false
        var index = 0

        while index < arguments.count {
            let argument = arguments[index]
            if argument == "--out" || argument == "-o" {
                guard !seenOutDir else {
                    return .failure("codex-swift: duplicate option for command 'app-server generate-internal-json-schema': --out", 64)
                }
                seenOutDir = true
                guard index + 1 < arguments.count else {
                    return .failure("codex-swift: missing value for \(argument)", 64)
                }
                outDir = arguments[index + 1]
                index += 2
                continue
            }
            if argument.hasPrefix("--out=") {
                guard !seenOutDir else {
                    return .failure("codex-swift: duplicate option for command 'app-server generate-internal-json-schema': --out", 64)
                }
                seenOutDir = true
                outDir = String(argument.dropFirst("--out=".count))
                index += 1
                continue
            }
            if argument.hasPrefix("-o"), argument.count > 2, !argument.hasPrefix("--") {
                guard !seenOutDir else {
                    return .failure("codex-swift: duplicate option for command 'app-server generate-internal-json-schema': --out", 64)
                }
                seenOutDir = true
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
        var sawDownloadURL = false
        var positionals: [String] = []
        var index = 0

        func markDownloadURLOption() -> ParseResult<Void> {
            guard !sawDownloadURL else {
                return .failure("codex-swift: duplicate option for command 'app': --download-url", 64)
            }
            sawDownloadURL = true
            return .success(())
        }

        func value(after option: String, at index: Int) -> ParseResult<String> {
            guard index + 1 < arguments.count else {
                return .failure("codex-swift: missing value for \(option)", 64)
            }
            return .success(arguments[index + 1])
        }

        while index < arguments.count {
            let argument = arguments[index]
            if argument == "--download-url" {
                switch markDownloadURLOption() {
                case .success:
                    break
                case let .failure(message, exitCode):
                    return .failure(message, exitCode)
                }
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
                switch markDownloadURLOption() {
                case .success:
                    break
                case let .failure(message, exitCode):
                    return .failure(message, exitCode)
                }
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
        var sawOutput = false
        var index = 0

        func markOutputOption() -> ParseResult<Void> {
            guard !sawOutput else {
                return .failure("codex-swift: duplicate option for command 'debug trace-reduce': --output", 64)
            }
            sawOutput = true
            return .success(())
        }

        while index < arguments.count {
            let argument = arguments[index]
            if argument == "--output" || argument == "-o" {
                switch markOutputOption() {
                case .success:
                    break
                case let .failure(message, code):
                    return .failure(message, code)
                }
                guard index + 1 < arguments.count else {
                    return .failure("codex-swift: missing value for \(argument)", 64)
                }
                output = arguments[index + 1]
                index += 2
                continue
            }
            if argument.hasPrefix("--output=") {
                switch markOutputOption() {
                case .success:
                    break
                case let .failure(message, code):
                    return .failure(message, code)
                }
                output = String(argument.dropFirst("--output=".count))
                index += 1
                continue
            }
            if argument.hasPrefix("-o"), argument.count > 2, !argument.hasPrefix("--") {
                switch markOutputOption() {
                case .success:
                    break
                case let .failure(message, code):
                    return .failure(message, code)
                }
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
                guard url == nil else {
                    return .failure("codex-swift: duplicate option for command 'mcp add': --url", 64)
                }
                guard index + 1 < arguments.count else {
                    return .failure("codex-swift: missing value for --url", 64)
                }
                url = arguments[index + 1]
                index += 2
                continue
            }
            if argument.hasPrefix("--url=") {
                guard url == nil else {
                    return .failure("codex-swift: duplicate option for command 'mcp add': --url", 64)
                }
                url = String(argument.dropFirst("--url=".count))
                index += 1
                continue
            }
            if argument == "--bearer-token-env-var" {
                guard bearerTokenEnvVar == nil else {
                    return .failure(
                        "codex-swift: duplicate option for command 'mcp add': --bearer-token-env-var",
                        64
                    )
                }
                guard index + 1 < arguments.count else {
                    return .failure("codex-swift: missing value for --bearer-token-env-var", 64)
                }
                bearerTokenEnvVar = arguments[index + 1]
                index += 2
                continue
            }
            if argument.hasPrefix("--bearer-token-env-var=") {
                guard bearerTokenEnvVar == nil else {
                    return .failure(
                        "codex-swift: duplicate option for command 'mcp add': --bearer-token-env-var",
                        64
                    )
                }
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
            if argument == "--" {
                if let extra = iterator.next() {
                    return .failure("codex-swift: unexpected argument for command 'cloud list': \(extra)", 64)
                }
                break
            }
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
        var index = 0

        while index < arguments.count {
            let argument = arguments[index]
            if argument == "--" {
                let remaining = Array(arguments.dropFirst(index + 1))
                for positional in remaining {
                    if taskID != nil {
                        return .failure("codex-swift: unexpected argument for command 'cloud \(command)': \(positional)", 64)
                    }
                    taskID = positional
                }
                break
            }
            if argument.hasPrefix("-") {
                return .failure("codex-swift: unsupported option for command 'cloud \(command)': \(argument)", 64)
            }
            if taskID != nil {
                return .failure("codex-swift: unexpected argument for command 'cloud \(command)': \(argument)", 64)
            }
            taskID = argument
            index += 1
        }

        guard let taskID else {
            return .failure("codex-swift: missing required argument for command 'cloud \(command)': <TASK_ID>", 64)
        }
        return .success(taskID)
    }

    private func parseCloudTaskAndAttempt(_ arguments: [String], command: String) -> ParseResult<(taskID: String, attempt: Int?)> {
        var taskID: String?
        var attempt: Int?
        var index = 0

        while index < arguments.count {
            let argument = arguments[index]
            if argument == "--" {
                let remaining = Array(arguments.dropFirst(index + 1))
                for positional in remaining {
                    if taskID != nil {
                        return .failure("codex-swift: unexpected argument for command 'cloud \(command)': \(positional)", 64)
                    }
                    taskID = positional
                }
                break
            }
            if argument == "--attempt" {
                guard index + 1 < arguments.count else {
                    return .failure("codex-swift: missing value for --attempt", 64)
                }
                switch parseCloudAttempt(arguments[index + 1]) {
                case let .success(parsed):
                    attempt = parsed
                case let .failure(message, exitCode):
                    return .failure(message, exitCode)
                }
                index += 2
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
                index += 1
                continue
            }
            if argument.hasPrefix("-") {
                return .failure("codex-swift: unsupported option for command 'cloud \(command)': \(argument)", 64)
            }
            if taskID != nil {
                return .failure("codex-swift: unexpected argument for command 'cloud \(command)': \(argument)", 64)
            }
            taskID = argument
            index += 1
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
        var index = 0

        while index < arguments.count {
            let argument = arguments[index]
            if argument == "--" {
                let remaining = Array(arguments.dropFirst(index + 1))
                for positional in remaining {
                    if query != nil {
                        return .failure("codex-swift: unexpected argument for command 'cloud exec': \(positional)", 64)
                    }
                    query = positional
                }
                break
            }
            if argument == "--env" {
                guard index + 1 < arguments.count else {
                    return .failure("codex-swift: missing value for --env", 64)
                }
                environment = arguments[index + 1]
                index += 2
                continue
            }
            if argument.hasPrefix("--env=") {
                environment = String(argument.dropFirst("--env=".count))
                index += 1
                continue
            }
            if argument == "--branch" {
                guard index + 1 < arguments.count else {
                    return .failure("codex-swift: missing value for --branch", 64)
                }
                branch = arguments[index + 1]
                index += 2
                continue
            }
            if argument.hasPrefix("--branch=") {
                branch = String(argument.dropFirst("--branch=".count))
                index += 1
                continue
            }
            if argument == "--attempts" {
                guard index + 1 < arguments.count else {
                    return .failure("codex-swift: missing value for --attempts", 64)
                }
                switch parseCloudAttempt(arguments[index + 1]) {
                case let .success(parsed):
                    attempts = parsed
                case let .failure(message, exitCode):
                    return .failure(message, exitCode)
                }
                index += 2
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
                index += 1
                continue
            }
            if query != nil {
                return .failure("codex-swift: unexpected argument for command 'cloud exec': \(argument)", 64)
            }
            if argument.hasPrefix("-"), argument != "-" {
                return .failure("codex-swift: unsupported option for command 'cloud exec': \(argument)", 64)
            }
            query = argument
            index += 1
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
        guard let subcommand = arguments.first else {
            return .failure("codex-swift: missing required subcommand for command 'plugin': add|list|marketplace|remove", 64)
        }
        let rest = Array(arguments.dropFirst())
        switch subcommand {
        case "add":
            return parsePluginSelectionCommand(rest, commandName: "plugin add", action: PluginCommandAction.add)
        case "list":
            return parsePluginList(rest)
        case "marketplace":
            return parsePluginMarketplaceCommand(rest)
        case "remove":
            return parsePluginSelectionCommand(rest, commandName: "plugin remove", action: PluginCommandAction.remove)
        default:
            return .failure("codex-swift: unsupported plugin subcommand: \(subcommand)", 64)
        }
    }

    private func parsePluginSelectionCommand(
        _ arguments: [String],
        commandName: String,
        action: (String, String?) -> PluginCommandAction
    ) -> ParseResult<PluginCommandAction> {
        var plugin: String?
        var marketplaceName: String?
        var sawMarketplace = false
        var iterator = arguments.makeIterator()

        func markMarketplaceOption() -> ParseResult<Void> {
            guard !sawMarketplace else {
                return .failure("codex-swift: duplicate option for command '\(commandName)': --marketplace", 64)
            }
            sawMarketplace = true
            return .success(())
        }

        while let argument = iterator.next() {
            if argument == "--marketplace" || argument == "-m" {
                switch markMarketplaceOption() {
                case .success:
                    break
                case let .failure(message, code):
                    return .failure(message, code)
                }
                guard let value = iterator.next() else {
                    return .failure("codex-swift: missing value for --marketplace", 64)
                }
                marketplaceName = value
                continue
            }
            if argument.hasPrefix("--marketplace=") {
                switch markMarketplaceOption() {
                case .success:
                    break
                case let .failure(message, code):
                    return .failure(message, code)
                }
                marketplaceName = String(argument.dropFirst("--marketplace=".count))
                continue
            }
            if argument.hasPrefix("-") {
                return .failure("codex-swift: unsupported option for command '\(commandName)': \(argument)", 64)
            }
            if plugin != nil {
                return .failure("codex-swift: unexpected argument for command '\(commandName)': \(argument)", 64)
            }
            plugin = argument
        }

        guard let plugin else {
            return .failure("codex-swift: missing required argument for command '\(commandName)': <PLUGIN[@MARKETPLACE]>", 64)
        }
        return .success(action(plugin, marketplaceName))
    }

    private func parsePluginList(_ arguments: [String]) -> ParseResult<PluginCommandAction> {
        var marketplaceName: String?
        var sawMarketplace = false
        var iterator = arguments.makeIterator()

        func markMarketplaceOption() -> ParseResult<Void> {
            guard !sawMarketplace else {
                return .failure("codex-swift: duplicate option for command 'plugin list': --marketplace", 64)
            }
            sawMarketplace = true
            return .success(())
        }

        while let argument = iterator.next() {
            if argument == "--marketplace" || argument == "-m" {
                switch markMarketplaceOption() {
                case .success:
                    break
                case let .failure(message, code):
                    return .failure(message, code)
                }
                guard let value = iterator.next() else {
                    return .failure("codex-swift: missing value for --marketplace", 64)
                }
                marketplaceName = value
                continue
            }
            if argument.hasPrefix("--marketplace=") {
                switch markMarketplaceOption() {
                case .success:
                    break
                case let .failure(message, code):
                    return .failure(message, code)
                }
                marketplaceName = String(argument.dropFirst("--marketplace=".count))
                continue
            }
            if argument.hasPrefix("-") {
                return .failure("codex-swift: unsupported option for command 'plugin list': \(argument)", 64)
            }
            return .failure("codex-swift: unexpected argument for command 'plugin list': \(argument)", 64)
        }

        return .success(.list(marketplaceName: marketplaceName))
    }

    private func parsePluginMarketplaceCommand(_ arguments: [String]) -> ParseResult<PluginCommandAction> {
        guard let subcommand = arguments.first else {
            return .failure("codex-swift: missing required subcommand for command 'plugin marketplace': add|list|upgrade|remove", 64)
        }
        let rest = Array(arguments.dropFirst())
        switch subcommand {
        case "add":
            return parsePluginMarketplaceAdd(rest)
        case "list":
            return parsePluginMarketplaceList(rest)
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
        var sawRef = false
        var sparsePaths: [String] = []
        var iterator = arguments.makeIterator()

        func markRefOption() -> ParseResult<Void> {
            guard !sawRef else {
                return .failure("codex-swift: duplicate option for command 'plugin marketplace add': --ref", 64)
            }
            sawRef = true
            return .success(())
        }

        while let argument = iterator.next() {
            if argument == "--ref" {
                switch markRefOption() {
                case .success:
                    break
                case let .failure(message, code):
                    return .failure(message, code)
                }
                guard let value = iterator.next() else {
                    return .failure("codex-swift: missing value for --ref", 64)
                }
                refName = value
                continue
            }
            if argument.hasPrefix("--ref=") {
                switch markRefOption() {
                case .success:
                    break
                case let .failure(message, code):
                    return .failure(message, code)
                }
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

    private func parsePluginMarketplaceList(_ arguments: [String]) -> ParseResult<PluginCommandAction> {
        guard arguments.isEmpty else {
            let argument = arguments[0]
            if argument.hasPrefix("-") {
                return .failure("codex-swift: unsupported option for command 'plugin marketplace list': \(argument)", 64)
            }
            return .failure("codex-swift: unexpected argument for command 'plugin marketplace list': \(argument)", 64)
        }
        return .success(.marketplaceList)
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
