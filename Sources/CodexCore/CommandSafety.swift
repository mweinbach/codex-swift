import Foundation

public enum CommandSafety {
    public static func isKnownSafeCommand(_ command: [String]) -> Bool {
        let command = command.map { $0 == "zsh" ? "bash" : $0 }

        if isSafeCommandWindows(command) {
            return true
        }

        if isSafeToCallWithExec(command) {
            return true
        }

        if let allCommands = BashPlainCommandParser.parseShellLcPlainCommands(command),
           !allCommands.isEmpty,
           allCommands.allSatisfy(isSafeToCallWithExec)
        {
            return true
        }

        return false
    }

    public static func isSafeToCallWithExec(_ command: [String]) -> Bool {
        guard let commandName = command.first.flatMap(commandBasename) else {
            return false
        }

        #if os(Linux)
        if commandName == "numfmt" || commandName == "tac" {
            return true
        }
        #endif

        let alwaysSafe: Set<String> = [
            "cat",
            "cd",
            "cut",
            "echo",
            "expr",
            "false",
            "grep",
            "head",
            "id",
            "ls",
            "nl",
            "paste",
            "pwd",
            "rev",
            "seq",
            "stat",
            "tail",
            "tr",
            "true",
            "uname",
            "uniq",
            "wc",
            "which",
            "whoami"
        ]
        if alwaysSafe.contains(commandName) {
            return true
        }

        switch commandName {
        case "base64":
            return !command.dropFirst().contains { argument in
                argument == "-o"
                    || argument == "--output"
                    || argument.hasPrefix("--output=")
                    || (argument.hasPrefix("-o") && argument != "-o")
            }

        case "find":
            let unsafeOptions: Set<String> = [
                "-exec",
                "-execdir",
                "-ok",
                "-okdir",
                "-delete",
                "-fls",
                "-fprint",
                "-fprint0",
                "-fprintf"
            ]
            return !command.contains { unsafeOptions.contains($0) }

        case "rg":
            let unsafeWithoutArguments: Set<String> = ["--search-zip", "-z"]
            let unsafeWithArguments = ["--pre", "--hostname-bin"]
            return !command.contains { argument in
                unsafeWithoutArguments.contains(argument)
                    || unsafeWithArguments.contains { option in
                        argument == option || argument.hasPrefix("\(option)=")
                    }
            }

        case "git":
            switch command.dropFirst().first {
            case "branch", "status", "log", "diff", "show":
                return true
            default:
                return false
            }

        case "cargo":
            return command.dropFirst().first == "check"

        case "sed":
            return command.count <= 4
                && command.dropFirst().first == "-n"
                && isValidSedNArgument(command.dropFirst(2).first)

        default:
            return false
        }
    }

    public static func requiresInitialApproval(
        policy: AskForApproval,
        sandboxPolicy: SandboxPolicy,
        command: [String],
        sandboxPermissions: SandboxPermissions
    ) -> Bool {
        if isKnownSafeCommand(command) {
            return false
        }

        switch policy {
        case .never, .onFailure:
            return false
        case .onRequest:
            switch sandboxPolicy {
            case .dangerFullAccess, .externalSandbox:
                return commandMightBeDangerous(command)
            case .readOnly, .workspaceWrite:
                if sandboxPermissions.requiresEscalatedPermissions {
                    return true
                }
                return commandMightBeDangerous(command)
            }
        case .unlessTrusted:
            return !isKnownSafeCommand(command)
        }
    }

    public static func commandMightBeDangerous(_ command: [String]) -> Bool {
        if isDangerousCommandWindows(command) {
            return true
        }

        if isDangerousToCallWithExec(command) {
            return true
        }

        if let allCommands = BashPlainCommandParser.parseShellLcPlainCommands(command),
           allCommands.contains(where: isDangerousToCallWithExec)
        {
            return true
        }

        return false
    }

    public static func isDangerousToCallWithExec(_ command: [String]) -> Bool {
        guard let commandName = command.first else {
            return false
        }

        if commandName.hasSuffix("git") || commandName.hasSuffix("/git") {
            return command.dropFirst().first == "reset" || command.dropFirst().first == "rm"
        }

        if commandName == "rm" {
            return command.dropFirst().first == "-f" || command.dropFirst().first == "-rf"
        }

        if commandName == "sudo" {
            return isDangerousToCallWithExec(Array(command.dropFirst()))
        }

        return false
    }

    private static func isSafeCommandWindows(_: [String]) -> Bool {
        false
    }

    private static func isDangerousCommandWindows(_ command: [String]) -> Bool {
        if isDangerousPowerShell(command) {
            return true
        }

        if isDangerousCmd(command) {
            return true
        }

        return isDirectGUILaunch(command)
    }

    private static func isDangerousPowerShell(_ command: [String]) -> Bool {
        guard let executable = command.first,
              isPowerShellExecutable(executable),
              let parsed = parsePowerShellInvocation(Array(command.dropFirst()))
        else {
            return false
        }

        let normalizedTokens = parsed.map {
            $0.trimmingCharacters(in: CharacterSet(charactersIn: "'\"")).lowercased()
        }
        let hasURL = argsHaveURL(parsed)

        if hasURL,
           normalizedTokens.contains(where: { token in
               token == "start-process"
                   || token == "start"
                   || token == "saps"
                   || token == "invoke-item"
                   || token == "ii"
                   || token.contains("start-process")
                   || token.contains("invoke-item")
           })
        {
            return true
        }

        if hasURL,
           normalizedTokens.contains(where: { $0.contains("shellexecute") || $0.contains("shell.application") })
        {
            return true
        }

        guard let first = normalizedTokens.first else {
            return false
        }

        if first == "rundll32",
           normalizedTokens.contains(where: { $0.contains("url.dll,fileprotocolhandler") }),
           hasURL
        {
            return true
        }

        if first == "mshta", hasURL {
            return true
        }

        if isBrowserExecutable(first), hasURL {
            return true
        }

        if (first == "explorer" || first == "explorer.exe"), hasURL {
            return true
        }

        return false
    }

    private static func isDangerousCmd(_ command: [String]) -> Bool {
        guard let executable = command.first,
              let base = windowsExecutableBasename(executable),
              base == "cmd" || base == "cmd.exe"
        else {
            return false
        }

        let rest = Array(command.dropFirst())
        var index = 0
        while index < rest.count {
            let lower = rest[index].lowercased()
            if lower == "/c" || lower == "/r" || lower == "-c" {
                index += 1
                break
            }
            if lower.hasPrefix("/") {
                index += 1
                continue
            }
            return false
        }

        guard index < rest.count, rest[index].caseInsensitiveCompare("start") == .orderedSame else {
            return false
        }

        return argsHaveURL(Array(rest.dropFirst(index + 1)))
    }

    private static func isDirectGUILaunch(_ command: [String]) -> Bool {
        guard let executable = command.first,
              let base = windowsExecutableBasename(executable)
        else {
            return false
        }

        let rest = Array(command.dropFirst())
        if (base == "explorer" || base == "explorer.exe"), argsHaveURL(rest) {
            return true
        }
        if (base == "mshta" || base == "mshta.exe"), argsHaveURL(rest) {
            return true
        }
        if (base == "rundll32" || base == "rundll32.exe"),
           rest.contains(where: { $0.lowercased().contains("url.dll,fileprotocolhandler") }),
           argsHaveURL(rest)
        {
            return true
        }
        if isBrowserExecutable(base), argsHaveURL(rest) {
            return true
        }

        return false
    }

    private static func parsePowerShellInvocation(_ arguments: [String]) -> [String]? {
        guard !arguments.isEmpty else {
            return nil
        }

        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            let lower = argument.lowercased()

            switch lower {
            case "-command", "/command", "-c":
                guard arguments.indices.contains(index + 1), index + 2 == arguments.count else {
                    return nil
                }
                return shellLikeSplit(arguments[index + 1])

            case _ where lower.hasPrefix("-command:") || lower.hasPrefix("/command:"):
                guard index + 1 == arguments.count,
                      let separator = argument.firstIndex(of: ":")
                else {
                    return nil
                }
                return shellLikeSplit(String(argument[argument.index(after: separator)...]))

            case "-nologo", "-noprofile", "-noninteractive", "-mta", "-sta":
                index += 1

            case _ where lower.hasPrefix("-"):
                index += 1

            default:
                return Array(arguments[index...])
            }
        }

        return nil
    }

    private static func argsHaveURL(_ arguments: [String]) -> Bool {
        arguments.contains(where: looksLikeURL)
    }

    private static func looksLikeURL(_ token: String) -> Bool {
        let lower = token.lowercased()
        guard let range = lower.range(of: "https://") ?? lower.range(of: "http://") else {
            return false
        }

        let urlish = token[range.lowerBound...]
        let trimmed = urlish.trimmingCharacters(in: CharacterSet(charactersIn: " \"'();\t\r\n"))
        guard let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased()
        else {
            return false
        }

        return (scheme == "http" || scheme == "https") && components.host != nil
    }

    private static func isPowerShellExecutable(_ executable: String) -> Bool {
        switch windowsExecutableBasename(executable) {
        case "powershell", "powershell.exe", "pwsh", "pwsh.exe":
            return true
        default:
            return false
        }
    }

    private static func isBrowserExecutable(_ executable: String) -> Bool {
        switch executable {
        case "chrome", "chrome.exe",
             "msedge", "msedge.exe",
             "firefox", "firefox.exe",
             "iexplore", "iexplore.exe":
            return true
        default:
            return false
        }
    }

    private static func windowsExecutableBasename(_ executable: String) -> String? {
        let normalized = executable.replacingOccurrences(of: "\\", with: "/")
        return normalized.split(separator: "/", omittingEmptySubsequences: true).last.map { $0.lowercased() }
            ?? (executable.isEmpty ? nil : executable.lowercased())
    }

    private static func shellLikeSplit(_ input: String) -> [String]? {
        var tokens: [String] = []
        var current = ""
        var quote: Character?
        var escaped = false

        func flushCurrent() {
            if !current.isEmpty {
                tokens.append(current)
                current.removeAll(keepingCapacity: true)
            }
        }

        for character in input {
            if escaped {
                current.append(character)
                escaped = false
                continue
            }

            if character == "\\" {
                escaped = true
                continue
            }

            if let activeQuote = quote {
                if character == activeQuote {
                    quote = nil
                } else {
                    current.append(character)
                }
                continue
            }

            if character == "'" || character == "\"" {
                quote = character
                continue
            }

            if character.isWhitespace {
                flushCurrent()
                continue
            }

            current.append(character)
        }

        guard quote == nil, !escaped else {
            return nil
        }
        flushCurrent()
        return tokens
    }

    private static func commandBasename(_ command: String) -> String? {
        let parts = command.split(separator: "/", omittingEmptySubsequences: true)
        return parts.last.map(String.init) ?? (command.isEmpty ? nil : command)
    }

    private static func isValidSedNArgument(_ argument: String?) -> Bool {
        guard let argument, argument.hasSuffix("p") else { return false }
        let core = argument.dropLast()
        let parts = core.split(separator: ",", omittingEmptySubsequences: false)
        switch parts.count {
        case 1:
            return !parts[0].isEmpty && parts[0].allSatisfy(\.isNumber)
        case 2:
            return !parts[0].isEmpty
                && !parts[1].isEmpty
                && parts[0].allSatisfy(\.isNumber)
                && parts[1].allSatisfy(\.isNumber)
        default:
            return false
        }
    }
}
