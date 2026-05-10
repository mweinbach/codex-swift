public enum CommandCanonicalization {
    public static let canonicalShellScriptPrefix = "__codex_shell_script__"
    public static let canonicalPowerShellScriptPrefix = "__codex_powershell_script__"

    public static func canonicalizeCommandForApproval(_ command: [String]) -> [String] {
        if let commands = BashPlainCommandParser.parseShellLcPlainCommands(command),
           commands.count == 1,
           let singleCommand = commands.first {
            return singleCommand
        }

        if let (_, script) = BashPlainCommandParser.extractBashCommand(command) {
            let shellMode = command.indices.contains(1) ? command[1] : ""
            return [canonicalShellScriptPrefix, shellMode, script]
        }

        if let (_, script) = ShellResolver.extractPowerShellCommand(command) {
            return [canonicalPowerShellScriptPrefix, script]
        }

        return command
    }
}
