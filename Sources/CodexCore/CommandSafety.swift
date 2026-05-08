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

    private static func isDangerousCommandWindows(_: [String]) -> Bool {
        false
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
