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
        case command(CommandSpec)
        case unknown(String)
    }

    public func parseInvocation(arguments: [String]) -> Invocation {
        if arguments.contains("--version") || arguments.contains("-V") {
            return .version
        }
        if arguments.contains("--help") || arguments.contains("-h") {
            return .help
        }

        let positionals = positionalTokens(arguments)
        if let commandToken = positionals.first, let spec = CodexCommandRegistry.command(matching: commandToken) {
            return .command(spec)
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
        if case let .command(spec) = parseInvocation(arguments: arguments) {
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
        case let .command(spec):
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
            "--disable"
        ].contains(argument)
    }
}
