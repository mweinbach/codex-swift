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

public func shlexJoin(_ tokens: [String]) -> String {
    tokens.map(shellQuote).joined(separator: " ")
}

public func parseCommand(_ command: [String]) -> [ParsedCommand] {
    dedupeParsed(parseCommandImpl(command))
}

private func dedupeParsed(_ parsed: [ParsedCommand]) -> [ParsedCommand] {
    var deduped: [ParsedCommand] = []
    for command in parsed {
        if deduped.last == command {
            continue
        }
        deduped.append(command)
    }
    return deduped
}

public enum CommandParser {
    public static func shlexJoin(_ tokens: [String]) -> String {
        tokens.map(shellQuote).joined(separator: " ")
    }

    public static func parseCommand(_ command: [String]) -> [ParsedCommand] {
        dedupeParsed(parseCommandImpl(command))
    }
}

private func parseCommandImpl(_ command: [String]) -> [ParsedCommand] {
    if let parsed = parseShellWrappedCommand(command) {
        return parsed
    }

    if let (_, script) = extractPowerShellCommand(command) {
        return [.unknown(cmd: script)]
    }

    let normalized = normalizeTokens(command)
    let parts = containsConnectors(normalized) ? splitOnConnectors(normalized) : [normalized]
    return simplify(parseTokenParts(parts))
}

private func parseShellWrappedCommand(_ command: [String]) -> [ParsedCommand]? {
    guard let (_, script) = extractShellCommand(command) else {
        return nil
    }

    guard !containsUnsupportedShellSyntax(script), let scriptTokens = shellSplit(script) else {
        return [.unknown(cmd: script)]
    }

    let hadConnectors = containsConnectors(scriptTokens)
    let parts = splitOnConnectors(scriptTokens).filter { !isSmallFormattingCommand($0) }
    guard !parts.isEmpty else {
        return [.unknown(cmd: script)]
    }

    var commands = simplify(parseTokenParts(parts))
    if commands.count == 1 {
        commands = commands.map { parsed in
            switch parsed {
            case let .read(_, name, path):
                if hadConnectors {
                    if scriptTokens.contains("|"), containsSedN(scriptTokens) {
                        return .read(cmd: script, name: name, path: path)
                    }
                    return parsed
                }
                return .read(cmd: shlexJoin(scriptTokens), name: name, path: path)
            case let .listFiles(cmd, path):
                return .listFiles(cmd: hadConnectors ? cmd : shlexJoin(scriptTokens), path: path)
            case let .search(cmd, query, path):
                return .search(cmd: hadConnectors ? cmd : shlexJoin(scriptTokens), query: query, path: path)
            case .unknown:
                return parsed
            }
        }
    }
    return commands
}

private func parseTokenParts(_ parts: [[String]]) -> [ParsedCommand] {
    var parsedCommands: [ParsedCommand] = []
    var cwd: String?

    for tokens in parts where !tokens.isEmpty {
        if tokens.first == "cd" {
            if let dir = tokens.dropFirst().first {
                cwd = isAbsoluteLike(dir) ? nil : (cwd.map { joinPaths($0, dir) } ?? dir)
            }
            continue
        }

        let parsed = summarizeMainTokens(tokens)
        if let cwd {
            switch parsed {
            case let .read(cmd, name, path):
                parsedCommands.append(.read(cmd: cmd, name: name, path: joinPaths(cwd, path)))
            case let .listFiles(cmd, path):
                parsedCommands.append(.listFiles(cmd: cmd, path: path.map { joinPaths(cwd, $0) }))
            case let .search(cmd, query, path):
                parsedCommands.append(.search(cmd: cmd, query: query, path: path.map { joinPaths(cwd, $0) }))
            case .unknown:
                parsedCommands.append(parsed)
            }
        } else {
            parsedCommands.append(parsed)
        }
    }

    return parsedCommands
}

private func simplify(_ commands: [ParsedCommand]) -> [ParsedCommand] {
    var current = commands
    while let next = simplifyOnce(current) {
        current = next
    }
    return current
}

private func simplifyOnce(_ commands: [ParsedCommand]) -> [ParsedCommand]? {
    guard commands.count > 1 else {
        return nil
    }

    if case let .unknown(cmd) = commands[0],
       shellSplit(cmd)?.first == "echo" {
        return Array(commands.dropFirst())
    }

    if let index = commands.firstIndex(where: { parsed in
        guard case let .unknown(cmd) = parsed else {
            return false
        }
        return shellSplit(cmd)?.first == "cd"
    }), commands.indices.contains(index + 1) {
        var out = commands
        out.remove(at: index)
        return out
    }

    if let index = commands.firstIndex(where: { parsed in
        if case .unknown("true") = parsed {
            return true
        }
        return false
    }) {
        var out = commands
        out.remove(at: index)
        return out
    }

    if let index = commands.firstIndex(where: { parsed in
        guard case let .unknown(cmd) = parsed, let tokens = shellSplit(cmd), tokens.first == "nl" else {
            return false
        }
        return tokens.dropFirst().allSatisfy { $0.hasPrefix("-") }
    }) {
        var out = commands
        out.remove(at: index)
        return out
    }

    return nil
}

private func summarizeMainTokens(_ mainCommand: [String]) -> ParsedCommand {
    guard let head = mainCommand.first else {
        return .unknown(cmd: "")
    }

    let tail = Array(mainCommand.dropFirst())
    switch head {
    case "ls":
        let candidates = skipFlagValues(
            tail,
            flagsWithValues: ["-I", "-w", "--block-size", "--format", "--time-style", "--color", "--quoting-style"]
        )
        let path = candidates.first(where: { !$0.hasPrefix("-") }).map(shortDisplayPath)
        return .listFiles(cmd: commandString(for: mainCommand), path: path)

    case "rg":
        let args = trimAtConnector(tail)
        let hasFilesFlag = args.contains("--files")
        let nonFlags = args.filter { !$0.hasPrefix("-") }
        let query: String?
        let path: String?
        if hasFilesFlag {
            query = nil
            path = nonFlags.first.map(shortDisplayPath)
        } else {
            query = nonFlags.first
            path = nonFlags.dropFirst().first.map(shortDisplayPath)
        }
        return .search(cmd: commandString(for: mainCommand), query: query, path: path)

    case "fd":
        let (query, path) = parseFDQueryAndPath(tail)
        return .search(cmd: commandString(for: mainCommand), query: query, path: path)

    case "find":
        let (query, path) = parseFindQueryAndPath(tail)
        return .search(cmd: commandString(for: mainCommand), query: query, path: path)

    case "grep":
        let args = trimAtConnector(tail)
        let nonFlags = args.filter { !$0.hasPrefix("-") }
        let query = nonFlags.first
        let path = nonFlags.dropFirst().first.map(shortDisplayPath)
        return .search(cmd: commandString(for: mainCommand), query: query, path: path)

    case "cat":
        let effectiveTail = tail.first == "--" ? Array(tail.dropFirst()) : tail
        if effectiveTail.count == 1, let path = effectiveTail.first {
            return .read(cmd: commandString(for: mainCommand), name: shortDisplayPath(path), path: path)
        }
        return .unknown(cmd: commandString(for: mainCommand))

    case "head":
        if let path = fileOperandForHead(tail) {
            return .read(cmd: commandString(for: mainCommand), name: shortDisplayPath(path), path: path)
        }
        return .unknown(cmd: commandString(for: mainCommand))

    case "tail":
        if let path = fileOperandForTail(tail) {
            return .read(cmd: commandString(for: mainCommand), name: shortDisplayPath(path), path: path)
        }
        return .unknown(cmd: commandString(for: mainCommand))

    case "nl":
        let candidates = skipFlagValues(tail, flagsWithValues: ["-s", "-w", "-v", "-i", "-b"])
        if let path = candidates.first(where: { !$0.hasPrefix("-") }) {
            return .read(cmd: commandString(for: mainCommand), name: shortDisplayPath(path), path: path)
        }
        return .unknown(cmd: commandString(for: mainCommand))

    case "sed":
        if tail.count >= 3, tail[0] == "-n", isValidSedNArg(tail[1]) {
            let path = tail[2]
            return .read(cmd: commandString(for: mainCommand), name: shortDisplayPath(path), path: path)
        }
        return .unknown(cmd: commandString(for: mainCommand))

    default:
        return .unknown(cmd: commandString(for: mainCommand))
    }
}

private func commandString(for tokens: [String]) -> String {
    shlexJoin(tokens)
}

private func extractShellCommand(_ command: [String]) -> (String, String)? {
    guard command.count == 3 else {
        return nil
    }
    let shell = command[0]
    let flag = command[1]
    guard flag == "-c" || flag == "-lc" else {
        return nil
    }
    guard ["bash", "zsh", "sh"].contains(executableName(shell)) else {
        return nil
    }
    return (shell, command[2])
}

private func extractPowerShellCommand(_ command: [String]) -> (String, String)? {
    guard command.count >= 3 else {
        return nil
    }
    guard ["powershell", "powershell.exe", "pwsh", "pwsh.exe"].contains(executableName(command[0]).lowercased()) else {
        return nil
    }

    var index = 1
    while index + 1 < command.count {
        let flag = command[index].lowercased()
        guard ["-nologo", "-noprofile", "-command", "-c"].contains(flag) else {
            return nil
        }
        if flag == "-command" || flag == "-c" {
            return (command[0], command[index + 1])
        }
        index += 1
    }
    return nil
}

private func executableName(_ path: String) -> String {
    path.replacingOccurrences(of: "\\", with: "/").split(separator: "/").last.map(String.init) ?? path
}

private func normalizeTokens(_ tokens: [String]) -> [String] {
    if tokens.count >= 3,
       ["yes", "y", "no", "n"].contains(tokens[0]),
       tokens[1] == "|" {
        return Array(tokens.dropFirst(2))
    }

    if tokens.count == 3,
       ["bash", "zsh"].contains(tokens[0]),
       ["-c", "-lc"].contains(tokens[1]),
       let split = shellSplit(tokens[2]) {
        return split
    }

    return tokens
}

private func containsConnectors(_ tokens: [String]) -> Bool {
    tokens.contains { $0 == "&&" || $0 == "||" || $0 == "|" || $0 == ";" }
}

private func splitOnConnectors(_ tokens: [String]) -> [[String]] {
    var output: [[String]] = []
    var current: [String] = []

    for token in tokens {
        if token == "&&" || token == "||" || token == "|" || token == ";" {
            if !current.isEmpty {
                output.append(current)
                current.removeAll(keepingCapacity: true)
            }
        } else {
            current.append(token)
        }
    }

    if !current.isEmpty {
        output.append(current)
    }
    return output
}

private func trimAtConnector(_ tokens: [String]) -> [String] {
    guard let index = tokens.firstIndex(where: { $0 == "|" || $0 == "&&" || $0 == "||" || $0 == ";" }) else {
        return tokens
    }
    return Array(tokens[..<index])
}

private func shortDisplayPath(_ path: String) -> String {
    let normalized = path.replacingOccurrences(of: "\\", with: "/")
    let trimmed = normalized.trimmingTrailingSlashes()
    let parts = trimmed.split(separator: "/", omittingEmptySubsequences: true).reversed()
    for part in parts {
        if part != "build", part != "dist", part != "node_modules", part != "src" {
            return String(part)
        }
    }
    return trimmed
}

private func skipFlagValues(_ args: [String], flagsWithValues: Set<String>) -> [String] {
    var output: [String] = []
    var skipNext = false
    var index = 0

    while index < args.count {
        let arg = args[index]
        if skipNext {
            skipNext = false
            index += 1
            continue
        }
        if arg == "--" {
            output.append(contentsOf: args.dropFirst(index + 1))
            break
        }
        if arg.hasPrefix("--"), arg.contains("=") {
            index += 1
            continue
        }
        if flagsWithValues.contains(arg) {
            if index + 1 < args.count {
                skipNext = true
            }
            index += 1
            continue
        }
        output.append(arg)
        index += 1
    }

    return output
}

private func isPathish(_ value: String) -> Bool {
    value == "."
        || value == ".."
        || value.hasPrefix("./")
        || value.hasPrefix("../")
        || value.contains("/")
        || value.contains("\\")
}

private func parseFDQueryAndPath(_ tail: [String]) -> (String?, String?) {
    let candidates = skipFlagValues(
        trimAtConnector(tail),
        flagsWithValues: ["-t", "--type", "-e", "--extension", "-E", "--exclude", "--search-path"]
    ).filter { !$0.hasPrefix("-") }

    switch candidates.count {
    case 1:
        let value = candidates[0]
        return isPathish(value) ? (nil, shortDisplayPath(value)) : (value, nil)
    case 2...:
        return (candidates[0], shortDisplayPath(candidates[1]))
    default:
        return (nil, nil)
    }
}

private func parseFindQueryAndPath(_ tail: [String]) -> (String?, String?) {
    let args = trimAtConnector(tail)
    let path = args.first { !$0.hasPrefix("-") && $0 != "!" && $0 != "(" && $0 != ")" }.map(shortDisplayPath)
    var query: String?

    for index in args.indices {
        if ["-name", "-iname", "-path", "-regex"].contains(args[index]), args.indices.contains(index + 1) {
            query = args[index + 1]
            break
        }
    }

    return (query, path)
}

private func isValidSedNArg(_ argument: String?) -> Bool {
    guard let argument, argument.hasSuffix("p") else {
        return false
    }

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

private func isSmallFormattingCommand(_ tokens: [String]) -> Bool {
    guard let command = tokens.first else {
        return false
    }

    switch command {
    case "wc", "tr", "cut", "sort", "uniq", "xargs", "tee", "column", "awk", "yes", "printf":
        return true
    case "head":
        switch tokens.count {
        case 1:
            return true
        case 2:
            return tokens[1].hasPrefix("-")
        case 3:
            return ["-n", "-c"].contains(tokens[1]) && tokens[2].allSatisfy(\.isNumber)
        default:
            return false
        }
    case "tail":
        switch tokens.count {
        case 1:
            return true
        case 2:
            return tokens[1].hasPrefix("-")
        case 3:
            return ["-n", "-c"].contains(tokens[1]) && isNumericOrPositiveOffset(tokens[2])
        default:
            return false
        }
    case "sed":
        return tokens.count < 4 || !(tokens[1] == "-n" && isValidSedNArg(tokens[safe: 2]))
    default:
        return false
    }
}

private func fileOperandForHead(_ tail: [String]) -> String? {
    guard !tail.isEmpty else {
        return nil
    }

    if tail[0] == "-n", tail.indices.contains(1), tail[1].allSatisfy(\.isNumber) {
        return tail.dropFirst(2).first { !$0.hasPrefix("-") }
    }

    if tail[0].hasPrefix("-n") {
        let count = tail[0].dropFirst(2)
        if !count.isEmpty, count.allSatisfy(\.isNumber) {
            return tail.dropFirst().first { !$0.hasPrefix("-") }
        }
    }

    if tail.count == 1, let path = tail.first, !path.hasPrefix("-") {
        return path
    }

    return nil
}

private func fileOperandForTail(_ tail: [String]) -> String? {
    guard !tail.isEmpty else {
        return nil
    }

    if tail[0] == "-n", tail.indices.contains(1), isNumericOrPositiveOffset(tail[1]) {
        return tail.dropFirst(2).first { !$0.hasPrefix("-") }
    }

    if tail[0].hasPrefix("-n") {
        let count = String(tail[0].dropFirst(2))
        if isNumericOrPositiveOffset(count) {
            return tail.dropFirst().first { !$0.hasPrefix("-") }
        }
    }

    if tail.count == 1, let path = tail.first, !path.hasPrefix("-") {
        return path
    }

    return nil
}

private func isNumericOrPositiveOffset(_ value: String) -> Bool {
    let trimmed = value.hasPrefix("+") ? String(value.dropFirst()) : value
    return !trimmed.isEmpty && trimmed.allSatisfy(\.isNumber)
}

private func containsSedN(_ tokens: [String]) -> Bool {
    tokens.indices.contains(where: { index in
        tokens[index] == "sed" && tokens.indices.contains(index + 1) && tokens[index + 1] == "-n"
    })
}

private func joinPaths(_ base: String, _ child: String) -> String {
    if isAbsoluteLike(child) {
        return child
    }
    if base.hasSuffix("/") || base.hasSuffix("\\") {
        return base + child
    }
    return base + "/" + child
}

private func isAbsoluteLike(_ path: String) -> Bool {
    if path.hasPrefix("/") || path.hasPrefix("\\\\") {
        return true
    }
    let chars = Array(path)
    return chars.count >= 3 && chars[1] == ":" && chars[2] == "\\" && chars[0].isLetter
}

private func containsUnsupportedShellSyntax(_ script: String) -> Bool {
    var singleQuoted = false
    var doubleQuoted = false
    var escaped = false

    for char in script {
        if escaped {
            escaped = false
            continue
        }
        if char == "\\" {
            escaped = true
            continue
        }
        if char == "'", !doubleQuoted {
            singleQuoted.toggle()
            continue
        }
        if char == "\"", !singleQuoted {
            doubleQuoted.toggle()
            continue
        }
        if !singleQuoted, !doubleQuoted, char == ">" || char == "<" || char == "`" {
            return true
        }
    }

    return false
}

private func shellSplit(_ input: String) -> [String]? {
    var tokens: [String] = []
    var current = ""
    var singleQuoted = false
    var doubleQuoted = false
    var escaped = false

    func flushCurrent() {
        if !current.isEmpty {
            tokens.append(current)
            current.removeAll(keepingCapacity: true)
        }
    }

    var index = input.startIndex
    while index < input.endIndex {
        let char = input[index]

        if escaped {
            current.append(char)
            escaped = false
            index = input.index(after: index)
            continue
        }

        if char == "\\", !singleQuoted {
            escaped = true
            index = input.index(after: index)
            continue
        }

        if char == "'", !doubleQuoted {
            singleQuoted.toggle()
            index = input.index(after: index)
            continue
        }

        if char == "\"", !singleQuoted {
            doubleQuoted.toggle()
            index = input.index(after: index)
            continue
        }

        if !singleQuoted, !doubleQuoted {
            if char.isWhitespace {
                flushCurrent()
                index = input.index(after: index)
                continue
            }

            let next = input.index(after: index)
            if char == "&", next < input.endIndex, input[next] == "&" {
                flushCurrent()
                tokens.append("&&")
                index = input.index(after: next)
                continue
            }
            if char == "|", next < input.endIndex, input[next] == "|" {
                flushCurrent()
                tokens.append("||")
                index = input.index(after: next)
                continue
            }
            if char == "|" || char == ";" {
                flushCurrent()
                tokens.append(String(char))
                index = next
                continue
            }
        }

        current.append(char)
        index = input.index(after: index)
    }

    guard !singleQuoted, !doubleQuoted, !escaped else {
        return nil
    }
    flushCurrent()
    return tokens
}

private func shellQuote(_ token: String) -> String {
    if token.isEmpty {
        return "''"
    }

    if token.allSatisfy(isUnquotedShellCharacter) {
        return token
    }

    if !token.contains("'") {
        return "'\(token)'"
    }

    return "'" + token.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

private func isUnquotedShellCharacter(_ character: Character) -> Bool {
    character.isLetter
        || character.isNumber
        || character == "_"
        || character == "."
        || character == "/"
        || character == ":"
        || character == "@"
        || character == "%"
        || character == "+"
        || character == "-"
}

private extension String {
    func trimmingTrailingSlashes() -> String {
        var output = self
        while output.count > 1, output.last == "/" {
            output.removeLast()
        }
        return output
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
