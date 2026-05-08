import CodexCore
import Darwin
import Foundation

public struct CodexCLI: Sendable {
    public static let version = "0.0.0"

    public init() {}

    public func command(for arguments: [String]) -> CommandSpec? {
        guard let firstCommand = arguments.first(where: { !$0.hasPrefix("-") }) else {
            return nil
        }
        return CodexCommandRegistry.command(matching: firstCommand)
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
        if arguments.contains("--version") || arguments.contains("-V") {
            stdout(renderVersion())
            return 0
        }

        if arguments.isEmpty || arguments.contains("--help") || arguments.contains("-h") {
            stdout(renderHelp())
            return 0
        }

        if let spec = command(for: arguments) {
            stderr("codex-swift: command '\(spec.name)' is registered but its runtime port is not complete yet.")
            return 78
        }

        stderr("codex-swift: unknown command or unsupported argument: \(arguments.joined(separator: " "))")
        return 64
    }
}
