import Foundation

public enum ParsedCommand: Equatable, Codable, Sendable {
    case read(cmd: String, name: String, path: String)
    case listFiles(cmd: String, path: String?)
    case search(cmd: String, query: String?, path: String?)
    case unknown(cmd: String)

    private enum CodingKeys: String, CodingKey {
        case type
        case cmd
        case name
        case path
        case query
    }

    private enum CommandType: String, Codable {
        case read
        case listFiles = "list_files"
        case search
        case unknown
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(CommandType.self, forKey: .type) {
        case .read:
            self = .read(
                cmd: try container.decode(String.self, forKey: .cmd),
                name: try container.decode(String.self, forKey: .name),
                path: try container.decode(String.self, forKey: .path)
            )
        case .listFiles:
            self = .listFiles(
                cmd: try container.decode(String.self, forKey: .cmd),
                path: try container.decodeIfPresent(String.self, forKey: .path)
            )
        case .search:
            self = .search(
                cmd: try container.decode(String.self, forKey: .cmd),
                query: try container.decodeIfPresent(String.self, forKey: .query),
                path: try container.decodeIfPresent(String.self, forKey: .path)
            )
        case .unknown:
            self = .unknown(cmd: try container.decode(String.self, forKey: .cmd))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .read(cmd, name, path):
            try container.encode(CommandType.read, forKey: .type)
            try container.encode(cmd, forKey: .cmd)
            try container.encode(name, forKey: .name)
            try container.encode(path, forKey: .path)
        case let .listFiles(cmd, path):
            try container.encode(CommandType.listFiles, forKey: .type)
            try container.encode(cmd, forKey: .cmd)
            try container.encodeIfPresent(path, forKey: .path)
        case let .search(cmd, query, path):
            try container.encode(CommandType.search, forKey: .type)
            try container.encode(cmd, forKey: .cmd)
            try container.encodeIfPresent(query, forKey: .query)
            try container.encodeIfPresent(path, forKey: .path)
        case let .unknown(cmd):
            try container.encode(CommandType.unknown, forKey: .type)
            try container.encode(cmd, forKey: .cmd)
        }
    }
}

public enum CommandParser {
    public static func shlexJoin(_ tokens: [String]) -> String {
        tokens.map(quoteIfNeeded).joined(separator: " ")
    }

    public static func parseCommand(_ command: [String]) -> [ParsedCommand] {
        let commandGroups: [[String]]
        if let script = extractShellScript(command) {
            commandGroups = tokenizeShellScript(script)
        } else {
            commandGroups = [command]
        }

        var basePath = ""
        var parsed: [ParsedCommand] = []
        for group in commandGroups where !group.isEmpty {
            if group.first == "cd", group.count >= 2 {
                basePath = joinPaths(base: basePath, relative: group[1])
                continue
            }
            if isSmallFormattingCommand(group) {
                continue
            }
            parsed.append(summarize(group, basePath: basePath))
        }

        var deduped: [ParsedCommand] = []
        for command in parsed {
            if deduped.last == command {
                continue
            }
            deduped.append(command)
        }
        return deduped
    }

    private static func extractShellScript(_ command: [String]) -> String? {
        guard let shell = command.first else { return nil }
        guard ["bash", "zsh", "sh"].contains(shell) else { return nil }
        for (index, token) in command.enumerated() where token == "-lc" || token == "-c" {
            let scriptIndex = index + 1
            guard command.indices.contains(scriptIndex) else { return nil }
            return command[scriptIndex]
        }
        return nil
    }

    private static func tokenizeShellScript(_ script: String) -> [[String]] {
        var tokens: [String] = []
        var current = String()
        var quote: Character?
        var previousWasBackslash = false
        var index = script.startIndex

        func flush() {
            if !current.isEmpty {
                tokens.append(current)
                current = ""
            }
        }

        while index < script.endIndex {
            let character = script[index]

            if let activeQuote = quote {
                if character == activeQuote && !previousWasBackslash {
                    quote = nil
                } else if character == "\\" && !previousWasBackslash {
                    previousWasBackslash = true
                } else {
                    current.append(character)
                    previousWasBackslash = false
                }
                index = script.index(after: index)
                continue
            }

            if character == "'" || character == "\"" {
                quote = character
                index = script.index(after: index)
                continue
            }

            if character.isWhitespace {
                flush()
                index = script.index(after: index)
                continue
            }

            let nextIndex = script.index(after: index)
            let next = nextIndex < script.endIndex ? script[nextIndex] : nil
            if character == "&", next == "&" {
                flush()
                tokens.append("&&")
                index = script.index(after: nextIndex)
                continue
            }
            if character == "|", next == "|" {
                flush()
                tokens.append("||")
                index = script.index(after: nextIndex)
                continue
            }
            if character == "|" || character == ";" {
                flush()
                tokens.append(String(character))
                index = nextIndex
                continue
            }

            current.append(character)
            index = nextIndex
        }
        flush()

        var groups: [[String]] = []
        var currentGroup: [String] = []
        for token in tokens {
            if token == "|" || token == "&&" || token == "||" || token == ";" {
                if !currentGroup.isEmpty {
                    groups.append(currentGroup)
                    currentGroup = []
                }
            } else {
                currentGroup.append(token)
            }
        }
        if !currentGroup.isEmpty {
            groups.append(currentGroup)
        }
        return groups
    }

    private static func summarize(_ tokens: [String], basePath: String) -> ParsedCommand {
        guard let head = tokens.first else {
            return .unknown(cmd: "")
        }
        let tail = Array(tokens.dropFirst())

        switch head {
        case "ls":
            let candidates = skipFlagValues(tail, flagsWithValues: [
                "-I", "-w", "--block-size", "--format", "--time-style", "--color", "--quoting-style"
            ])
            let path = candidates.first { !$0.hasPrefix("-") }.map(shortDisplayPath)
            return .listFiles(cmd: shlexJoin(tokens), path: path)

        case "rg":
            let hasFilesFlag = tail.contains("--files")
            let nonFlags = tail.filter { !$0.hasPrefix("-") }
            let query = hasFilesFlag ? nil : nonFlags.first
            let path = hasFilesFlag ? nonFlags.first.map(shortDisplayPath) : nonFlags.dropFirst().first.map(shortDisplayPath)
            return .search(cmd: shlexJoin(tokens), query: query, path: path)

        case "grep":
            let nonFlags = tail.filter { !$0.hasPrefix("-") }
            return .search(
                cmd: shlexJoin(tokens),
                query: nonFlags.first,
                path: nonFlags.dropFirst().first.map(shortDisplayPath)
            )

        case "cat":
            let effectiveTail = tail.first == "--" ? Array(tail.dropFirst()) : tail
            if effectiveTail.count == 1, let path = effectiveTail.first {
                let joinedPath = joinPaths(base: basePath, relative: path)
                return .read(cmd: shlexJoin(tokens), name: shortDisplayPath(path), path: joinedPath)
            }
            return .unknown(cmd: shlexJoin(tokens))

        case "head":
            if let path = readPathForHeadTail(tail, allowPlus: false) {
                return .read(cmd: shlexJoin(tokens), name: shortDisplayPath(path), path: joinPaths(base: basePath, relative: path))
            }
            return .unknown(cmd: shlexJoin(tokens))

        case "tail":
            if let path = readPathForHeadTail(tail, allowPlus: true) {
                return .read(cmd: shlexJoin(tokens), name: shortDisplayPath(path), path: joinPaths(base: basePath, relative: path))
            }
            return .unknown(cmd: shlexJoin(tokens))

        case "nl":
            let candidates = skipFlagValues(tail, flagsWithValues: ["-s", "-w", "-v", "-i", "-b"])
            if let path = candidates.first(where: { !$0.hasPrefix("-") }) {
                return .read(cmd: shlexJoin(tokens), name: shortDisplayPath(path), path: joinPaths(base: basePath, relative: path))
            }
            return .unknown(cmd: shlexJoin(tokens))

        case "sed":
            if tail.count >= 3, tail[0] == "-n", isValidSedRange(tail[1]) {
                let path = tail[2]
                return .read(cmd: shlexJoin(tokens), name: shortDisplayPath(path), path: joinPaths(base: basePath, relative: path))
            }
            return .unknown(cmd: shlexJoin(tokens))

        default:
            return .unknown(cmd: shlexJoin(tokens))
        }
    }

    private static func readPathForHeadTail(_ tail: [String], allowPlus: Bool) -> String? {
        guard !tail.isEmpty else { return nil }
        if tail.count == 1, !tail[0].hasPrefix("-") {
            return tail[0]
        }
        if tail.count >= 3, tail[0] == "-n", isNumericCount(tail[1], allowPlus: allowPlus) {
            return tail.dropFirst(2).first { !$0.hasPrefix("-") }
        }
        if tail.count >= 2, tail[0].hasPrefix("-n") {
            let count = String(tail[0].dropFirst(2))
            if isNumericCount(count, allowPlus: allowPlus) {
                return tail.dropFirst().first { !$0.hasPrefix("-") }
            }
        }
        return nil
    }

    private static func isSmallFormattingCommand(_ tokens: [String]) -> Bool {
        guard let cmd = tokens.first else { return false }
        switch cmd {
        case "wc", "tr", "cut", "sort", "uniq", "xargs", "tee", "column", "awk", "yes", "printf":
            return true
        case "head":
            return readPathForHeadTail(Array(tokens.dropFirst()), allowPlus: false) == nil
        case "tail":
            return readPathForHeadTail(Array(tokens.dropFirst()), allowPlus: true) == nil
        case "sed":
            let tail = Array(tokens.dropFirst())
            return !(tail.count >= 3 && tail[0] == "-n" && isValidSedRange(tail[1]))
        default:
            return false
        }
    }

    private static func skipFlagValues(_ args: [String], flagsWithValues: Set<String>) -> [String] {
        var output: [String] = []
        var skipNext = false
        for arg in args {
            if skipNext {
                skipNext = false
                continue
            }
            if arg == "--" {
                continue
            }
            if arg.hasPrefix("--"), arg.contains("=") {
                continue
            }
            if flagsWithValues.contains(arg) {
                skipNext = true
                continue
            }
            output.append(arg)
        }
        return output
    }

    private static func shortDisplayPath(_ path: String) -> String {
        let trimmed = path.replacingOccurrences(of: "\\", with: "/").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let parts = trimmed
            .split(separator: "/")
            .reversed()
            .map(String.init)
            .filter { !$0.isEmpty && !["build", "dist", "node_modules", "src"].contains($0) }
        return parts.first ?? trimmed
    }

    private static func joinPaths(base: String, relative: String) -> String {
        if relative.hasPrefix("/") || base.isEmpty {
            return relative
        }
        return base + "/" + relative
    }

    private static func isNumericCount(_ text: String, allowPlus: Bool) -> Bool {
        let value = allowPlus && text.hasPrefix("+") ? String(text.dropFirst()) : text
        return !value.isEmpty && value.allSatisfy(\.isNumber)
    }

    private static func isValidSedRange(_ text: String) -> Bool {
        text.hasSuffix("p") || text.contains(",")
    }

    private static func quoteIfNeeded(_ token: String) -> String {
        guard !token.isEmpty else { return "''" }
        let safe = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_./:@%+=,-")
        if token.unicodeScalars.allSatisfy({ safe.contains($0) }) {
            return token
        }
        return "'" + token.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
