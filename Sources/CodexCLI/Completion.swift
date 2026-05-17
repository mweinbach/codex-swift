import Foundation

public enum CompletionShell: String, CaseIterable, Sendable {
    case bash
    case elvish
    case fish
    case powershell
    case zsh

    public static let defaultShell: CompletionShell = .bash
}

public enum CompletionError: Error, Equatable, CustomStringConvertible, Sendable {
    case unsupportedShell(String)
    case tooManyArguments([String])

    public var description: String {
        switch self {
        case let .unsupportedShell(shell):
            return "unsupported completion shell: \(shell)"
        case let .tooManyArguments(arguments):
            return "completion accepts at most one shell argument: \(arguments.joined(separator: " "))"
        }
    }
}

public enum CompletionGenerator {
    public static func render(arguments: [String], commands: [CommandSpec] = CodexCommandRegistry.commands) throws -> String {
        let shell = try parseShell(arguments)
        let visibleCommands = commands.filter { !$0.isHidden }
        switch shell {
        case .bash:
            return bash(commands: visibleCommands)
        case .elvish:
            return elvish(commands: visibleCommands)
        case .fish:
            return fish(commands: visibleCommands)
        case .powershell:
            return powershell(commands: visibleCommands)
        case .zsh:
            return zsh(commands: visibleCommands)
        }
    }

    private static func parseShell(_ arguments: [String]) throws -> CompletionShell {
        guard arguments.count <= 1 else {
            throw CompletionError.tooManyArguments(arguments)
        }
        guard let rawShell = arguments.first else {
            return CompletionShell.defaultShell
        }
        guard let shell = CompletionShell(rawValue: rawShell.lowercased()) else {
            throw CompletionError.unsupportedShell(rawShell)
        }
        return shell
    }

    private static func bash(commands: [CommandSpec]) -> String {
        let words = completionWords(commands: commands).joined(separator: " ")
        return """
        _codex() {
            local cur="${COMP_WORDS[COMP_CWORD]}"
            COMPREPLY=( $(compgen -W "\(words)" -- "$cur") )
        }
        complete -F _codex codex
        """
    }

    private static func elvish(commands: [CommandSpec]) -> String {
        let words = completionWords(commands: commands).map(elvishSingleQuoted).joined(separator: " ")
        return """
        set edit:completion:arg-completer[codex] = {|@words|
            put \(words)
        }
        """
    }

    private static func fish(commands: [CommandSpec]) -> String {
        var lines = ["complete -c codex -f"]
        for command in commands {
            lines.append("complete -c codex -n __fish_use_subcommand -a \(fishQuoted(command.name)) -d \(fishQuoted(command.summary))")
            for alias in command.aliases {
                lines.append("complete -c codex -n __fish_use_subcommand -a \(fishQuoted(alias)) -d \(fishQuoted(command.summary))")
            }
        }
        for option in rootOptions {
            lines.append("complete -c codex -n __fish_use_subcommand -l \(option.longName) -d \(fishQuoted(option.summary))")
            if let shortName = option.shortName {
                lines.append("complete -c codex -n __fish_use_subcommand -s \(shortName) -d \(fishQuoted(option.summary))")
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func powershell(commands: [CommandSpec]) -> String {
        let words = completionWords(commands: commands).map { "'\(powerShellSingleQuoted($0))'" }.joined(separator: ", ")
        return """
        Register-ArgumentCompleter -Native -CommandName codex -ScriptBlock {
            param($wordToComplete)
            @(\(words)) | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object {
                [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
            }
        }
        """
    }

    private static func zsh(commands: [CommandSpec]) -> String {
        let commandSpecs = commands.flatMap { command -> [String] in
            [command.name] + command.aliases
        }
        .map { "'\($0):command'" }
        .joined(separator: " ")

        let optionSpecs = rootOptions.map { option -> String in
            var spec = "--\(option.longName)[\(option.summary)]"
            if let shortName = option.shortName {
                spec = "{-\(shortName),\(spec)}"
            }
            if option.takesValue {
                spec += ":value:"
            }
            return shellSingleQuoted(spec)
        }
        .joined(separator: " ")

        return """
        #compdef codex
        _codex() {
            _arguments \(optionSpecs) "1:command:((\(commandSpecs)))" "*::arg:->args"
        }
        compdef _codex codex
        """
    }

    private static func completionWords(commands: [CommandSpec]) -> [String] {
        let commandWords = commands.flatMap { [$0.name] + $0.aliases }
        let optionWords = rootOptions.flatMap { option -> [String] in
            if let shortName = option.shortName {
                return ["-\(shortName)", "--\(option.longName)"]
            }
            return ["--\(option.longName)"]
        }
        return commandWords + optionWords
    }

    private static func shellSingleQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func elvishSingleQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "''") + "'"
    }

    private static func fishQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "\\'") + "'"
    }

    private static func powerShellSingleQuoted(_ value: String) -> String {
        value.replacingOccurrences(of: "'", with: "''")
    }

    private struct RootOption: Sendable {
        let longName: String
        let shortName: Character?
        let summary: String
        let takesValue: Bool
    }

    private static let rootOptions: [RootOption] = [
        RootOption(longName: "model", shortName: "m", summary: "Model the agent should use.", takesValue: true),
        RootOption(longName: "oss", shortName: nil, summary: "Select the local open source model provider.", takesValue: false),
        RootOption(longName: "local-provider", shortName: nil, summary: "Specify lmstudio or ollama.", takesValue: true),
        RootOption(longName: "profile", shortName: "p", summary: "Configuration profile from config.toml.", takesValue: true),
        RootOption(longName: "sandbox", shortName: "s", summary: "Sandbox policy for model-generated shell commands.", takesValue: true),
        RootOption(longName: "ask-for-approval", shortName: "a", summary: "Configure command approval policy.", takesValue: true),
        RootOption(longName: "dangerously-bypass-approvals-and-sandbox", shortName: nil, summary: "Skip confirmations and sandboxing.", takesValue: false),
        RootOption(longName: "dangerously-bypass-hook-trust", shortName: nil, summary: "Run enabled hooks without persisted trust.", takesValue: false),
        RootOption(longName: "cd", shortName: "C", summary: "Working root for the session.", takesValue: true),
        RootOption(longName: "search", shortName: nil, summary: "Enable web search.", takesValue: false),
        RootOption(longName: "add-dir", shortName: nil, summary: "Additional writable directory.", takesValue: true),
        RootOption(longName: "image", shortName: "i", summary: "Attach image(s) to the initial prompt.", takesValue: true),
        RootOption(longName: "ephemeral", shortName: nil, summary: "Run without persisting session files.", takesValue: false),
        RootOption(longName: "ignore-user-config", shortName: nil, summary: "Do not load $CODEX_HOME/config.toml.", takesValue: false),
        RootOption(longName: "ignore-rules", shortName: nil, summary: "Do not load user or project rules files.", takesValue: false),
        RootOption(longName: "help", shortName: "h", summary: "Print help.", takesValue: false),
        RootOption(longName: "version", shortName: "V", summary: "Print version.", takesValue: false)
    ]
}
