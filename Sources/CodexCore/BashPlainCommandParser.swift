import Foundation

public enum BashPlainCommandParser {
    public static func extractBashCommand(_ command: [String]) -> (shell: String, script: String)? {
        guard command.count == 3 else { return nil }
        let shell = command[0]
        let flag = command[1]
        guard flag == "-lc" || flag == "-c" else { return nil }
        guard let shellType = ShellResolver.detectShellType(shell),
              shellType == .zsh || shellType == .bash || shellType == .sh
        else {
            return nil
        }
        return (shell, command[2])
    }

    public static func parseShellLcPlainCommands(_ command: [String]) -> [[String]]? {
        guard let (_, script) = extractBashCommand(command) else { return nil }
        return parseWordOnlyCommandsSequence(script)
    }

    public static func parseWordOnlyCommandsSequence(_ source: String) -> [[String]]? {
        var commands: [[String]] = []
        var currentCommand: [String] = []
        var currentWord = ""
        var quote: Character?
        var justClosedQuote = false
        var expectingCommand = true
        var endedWithOperator = false
        var previousWasBackslash = false

        func finishWord() -> Bool {
            if !currentWord.isEmpty || justClosedQuote {
                if currentCommand.isEmpty, isAssignmentWord(currentWord) {
                    return false
                }
                currentCommand.append(currentWord)
                currentWord = ""
                justClosedQuote = false
                expectingCommand = false
            }
            return true
        }

        func finishCommand() -> Bool {
            guard finishWord() else { return false }
            guard !currentCommand.isEmpty else { return false }
            commands.append(currentCommand)
            currentCommand = []
            expectingCommand = true
            endedWithOperator = true
            return true
        }

        var index = source.startIndex
        while index < source.endIndex {
            let character = source[index]

            if let activeQuote = quote {
                if character == activeQuote && !previousWasBackslash {
                    quote = nil
                    justClosedQuote = true
                } else {
                    if activeQuote == "\"", character == "$" || character == "`" {
                        return nil
                    }
                    currentWord.append(character)
                }

                if activeQuote == "\"" {
                    previousWasBackslash = character == "\\" && !previousWasBackslash
                    if character != "\\" {
                        previousWasBackslash = false
                    }
                }
                index = source.index(after: index)
                continue
            }

            switch character {
            case " ", "\t", "\r", "\n":
                guard finishWord() else { return nil }

            case "'", "\"":
                quote = character
                endedWithOperator = false
                previousWasBackslash = false

            case ";":
                guard finishCommand() else { return nil }

            case "|":
                let nextIndex = source.index(after: index)
                if nextIndex < source.endIndex, source[nextIndex] == "|" {
                    guard finishCommand() else { return nil }
                    index = nextIndex
                } else {
                    guard finishCommand() else { return nil }
                }

            case "&":
                let nextIndex = source.index(after: index)
                guard nextIndex < source.endIndex, source[nextIndex] == "&" else { return nil }
                guard finishCommand() else { return nil }
                index = nextIndex

            case "(", ")", "{", "}", "<", ">", "`", "$":
                return nil

            default:
                currentWord.append(character)
                justClosedQuote = false
                expectingCommand = false
                endedWithOperator = false
            }

            index = source.index(after: index)
        }

        guard quote == nil else { return nil }
        guard !endedWithOperator else { return nil }
        guard finishWord() else { return nil }
        if expectingCommand, !currentCommand.isEmpty {
            return nil
        }
        if !currentCommand.isEmpty {
            commands.append(currentCommand)
        }
        return commands.isEmpty ? nil : commands
    }

    private static func isAssignmentWord(_ word: String) -> Bool {
        guard let equalsIndex = word.firstIndex(of: "="), equalsIndex != word.startIndex else {
            return false
        }
        let name = word[..<equalsIndex]
        guard let first = name.first, first == "_" || first.isASCIIAlpha else {
            return false
        }
        return name.dropFirst().allSatisfy { $0 == "_" || $0.isASCIIAlpha || $0.isNumber }
    }
}

private extension Character {
    var isASCIIAlpha: Bool {
        guard unicodeScalars.count == 1, let scalar = unicodeScalars.first else {
            return false
        }
        return (65...90).contains(Int(scalar.value)) || (97...122).contains(Int(scalar.value))
    }
}
