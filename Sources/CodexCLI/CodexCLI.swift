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
        case deviceCode
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

    public struct FeaturesCommandRequest: Equatable, Sendable {
        public let configOverrides: CliConfigOverrides

        public init(configOverrides: CliConfigOverrides = CliConfigOverrides()) {
            self.configOverrides = configOverrides
        }
    }

    public struct StdioToUDSCommandRequest: Equatable, Sendable {
        public let socketPath: String

        public init(socketPath: String) {
            self.socketPath = socketPath
        }
    }

    public enum CloudCommandAction: Equatable, Sendable {
        case status(taskID: String)
        case diff(taskID: String, attempt: Int?)
        case apply(taskID: String, attempt: Int?)
    }

    public struct CloudCommandRequest: Equatable, Sendable {
        public let action: CloudCommandAction
        public let configOverrides: CliConfigOverrides

        public init(action: CloudCommandAction, configOverrides: CliConfigOverrides = CliConfigOverrides()) {
            self.action = action
            self.configOverrides = configOverrides
        }
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
    public typealias FeaturesCommandRunner = (FeaturesCommandRequest) async throws -> String
    public typealias StdioToUDSCommandRunner = (StdioToUDSCommandRequest) async throws -> CommandExecutionResult
    public typealias CloudCommandRunner = (CloudCommandRequest) async throws -> CommandExecutionResult

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
          --full-auto                       Use low-friction sandboxed automatic execution.
          --dangerously-bypass-approvals-and-sandbox
                                            Skip confirmations and sandboxing.
          -C, --cd <DIR>                    Working root for the session.
          --search                          Enable web search.
          --add-dir <DIR>                   Additional writable directory.
          -i, --image <FILE>                Attach image(s) to the initial prompt.
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
        stdioToUDSRunner: StdioToUDSCommandRunner? = nil,
        cloudRunner: CloudCommandRunner? = nil
    ) async -> Int32 {
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
        case let .command(spec, commandArguments) where spec.name == "features":
            guard let featuresRunner else {
                stderr("codex-swift: command '\(spec.name)' is registered but its runtime port is not complete yet.")
                return 78
            }
            guard commandArguments == ["list"] else {
                stderr("codex-swift: missing required subcommand for command 'features': list")
                return 64
            }
            do {
                let output = try await featuresRunner(FeaturesCommandRequest(
                    configOverrides: CliConfigOverrides(rawOverrides: try configOverrideTokens(arguments))
                ))
                stdout(output)
                return 0
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
            "--branch"
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

    private func configOverrideTokens(_ arguments: [String]) throws -> [String] {
        var overrides: [String] = []
        var featureToggles = FeatureToggles()
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
        }

        overrides.append(contentsOf: try featureToggles.toOverrides())
        return overrides
    }

    private func loginAction(arguments: [String], commandArguments: [String]) -> LoginCommandAction {
        if commandArguments.first == "status" {
            return .status
        }
        if arguments.contains("--device-auth") {
            return .deviceCode
        }
        if arguments.contains("--with-api-key") {
            return .withAPIKeyFromStdin
        }
        return .chatGPT
    }

    private func usesDeprecatedAPIKeyFlag(_ arguments: [String]) -> Bool {
        arguments.contains("--api-key") || arguments.contains { $0.hasPrefix("--api-key=") }
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
            return .failure("codex-swift: command 'cloud exec' runtime is not complete yet.", 78)
        default:
            return .failure("codex-swift: unsupported cloud subcommand: \(subcommand)", 64)
        }
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

    private func parseCloudAttempt(_ value: String) -> ParseResult<Int> {
        guard let attempt = Int(value) else {
            return .failure("attempts must be an integer between 1 and 4", 64)
        }
        guard (1...4).contains(attempt) else {
            return .failure("attempts must be between 1 and 4", 64)
        }
        return .success(attempt)
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
}
