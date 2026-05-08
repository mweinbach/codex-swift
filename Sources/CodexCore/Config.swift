import Foundation

public enum CodexConfigDefaults {
    public static let chatgptBaseURL = "https://chatgpt.com/backend-api/"
}

public struct CodexRuntimeConfig: Equatable, Sendable {
    public let chatgptBaseURL: String
    public let cliAuthCredentialsStoreMode: AuthCredentialsStoreMode
    public let activeProfile: String?

    public init(
        chatgptBaseURL: String = CodexConfigDefaults.chatgptBaseURL,
        cliAuthCredentialsStoreMode: AuthCredentialsStoreMode = .file,
        activeProfile: String? = nil
    ) {
        self.chatgptBaseURL = chatgptBaseURL
        self.cliAuthCredentialsStoreMode = cliAuthCredentialsStoreMode
        self.activeProfile = activeProfile
    }
}

public enum CodexConfigLoadError: Error, Equatable, CustomStringConvertible, Sendable {
    case invalidStringValue(String)
    case invalidAuthCredentialsStoreMode
    case invalidConfigLine(String)
    case invalidTableHeader(String)
    case profileNotFound(String)

    public var description: String {
        switch self {
        case let .invalidStringValue(key):
            return "Invalid value for \(key): expected string"
        case .invalidAuthCredentialsStoreMode:
            return "Invalid override value for cli_auth_credentials_store"
        case let .invalidConfigLine(line):
            return "Invalid config line: \(line)"
        case let .invalidTableHeader(header):
            return "Invalid TOML table header: \(header)"
        case let .profileNotFound(profile):
            return "config profile `\(profile)` not found"
        }
    }
}

public enum CodexConfigLoader {
    public static func load(
        codexHome: URL,
        overrides: CliConfigOverrides = CliConfigOverrides(),
        fileManager: FileManager = .default
    ) throws -> CodexRuntimeConfig {
        var parsed = ParsedCodexConfigToml()
        let configFile = codexHome.appendingPathComponent("config.toml", isDirectory: false)
        if fileManager.fileExists(atPath: configFile.path) {
            let contents = try String(contentsOf: configFile, encoding: .utf8)
            parsed = try ParsedCodexConfigToml.parse(contents)
        }

        try parsed.apply(overrides: overrides)
        return try parsed.resolvedConfig()
    }
}

private struct ParsedCodexConfigToml {
    var topLevel: [String: ConfigValue] = [:]
    var profiles: [String: [String: ConfigValue]] = [:]

    static func parse(_ contents: String) throws -> ParsedCodexConfigToml {
        var parsed = ParsedCodexConfigToml()
        var section = ConfigSection.topLevel

        for rawLine in contents.split(whereSeparator: \.isNewline) {
            let line = stripComment(from: String(rawLine)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            if line.hasPrefix("[") {
                section = try parseSectionHeader(line)
                if case let .profile(name) = section {
                    if parsed.profiles[name] == nil {
                        parsed.profiles[name] = [:]
                    }
                }
                continue
            }

            guard let equalsIndex = firstEqualsIndex(in: line) else {
                throw CodexConfigLoadError.invalidConfigLine(line)
            }

            let key = String(line[..<equalsIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            let valueStart = line.index(after: equalsIndex)
            let valueText = String(line[valueStart...]).trimmingCharacters(in: .whitespacesAndNewlines)

            switch section {
            case .topLevel:
                guard isRelevantTopLevelKey(key) else { continue }
                parsed.topLevel[key] = try ConfigValueParser.parseTomlLiteral(valueText)
            case let .profile(name):
                guard isRelevantProfileKey(key) else { continue }
                parsed.profiles[name, default: [:]][key] = try ConfigValueParser.parseTomlLiteral(valueText)
            case .ignored:
                continue
            }
        }

        return parsed
    }

    mutating func apply(overrides: CliConfigOverrides) throws {
        for (path, value) in try overrides.parseOverrides() {
            let parts = try Self.parseDottedKey(path)
            guard let first = parts.first else { continue }

            if parts.count == 1, Self.isRelevantTopLevelKey(first) {
                topLevel[first] = value
                continue
            }

            if parts.count >= 2, parts[0] == "profiles" {
                if profiles[parts[1]] == nil {
                    profiles[parts[1]] = [:]
                }
            }

            if parts.count == 3, parts[0] == "profiles", Self.isRelevantProfileKey(parts[2]) {
                profiles[parts[1], default: [:]][parts[2]] = value
            }
        }
    }

    func resolvedConfig() throws -> CodexRuntimeConfig {
        var config = CodexRuntimeConfig()

        if let baseURL = topLevel["chatgpt_base_url"] {
            config = CodexRuntimeConfig(
                chatgptBaseURL: try Self.stringValue(baseURL, key: "chatgpt_base_url"),
                cliAuthCredentialsStoreMode: config.cliAuthCredentialsStoreMode,
                activeProfile: config.activeProfile
            )
        }

        if let authStore = topLevel["cli_auth_credentials_store"] {
            let rawMode = try Self.stringValue(authStore, key: "cli_auth_credentials_store")
            guard let mode = AuthCredentialsStoreMode(rawValue: rawMode) else {
                throw CodexConfigLoadError.invalidAuthCredentialsStoreMode
            }
            config = CodexRuntimeConfig(
                chatgptBaseURL: config.chatgptBaseURL,
                cliAuthCredentialsStoreMode: mode,
                activeProfile: config.activeProfile
            )
        }

        let activeProfile = try topLevel["profile"].map { try Self.stringValue($0, key: "profile") }
        if let activeProfile {
            guard let profile = profiles[activeProfile] else {
                throw CodexConfigLoadError.profileNotFound(activeProfile)
            }

            if let baseURL = profile["chatgpt_base_url"] {
                config = CodexRuntimeConfig(
                    chatgptBaseURL: try Self.stringValue(baseURL, key: "profiles.\(activeProfile).chatgpt_base_url"),
                    cliAuthCredentialsStoreMode: config.cliAuthCredentialsStoreMode,
                    activeProfile: activeProfile
                )
            } else {
                config = CodexRuntimeConfig(
                    chatgptBaseURL: config.chatgptBaseURL,
                    cliAuthCredentialsStoreMode: config.cliAuthCredentialsStoreMode,
                    activeProfile: activeProfile
                )
            }
        }

        return config
    }

    private static func isRelevantTopLevelKey(_ key: String) -> Bool {
        key == "chatgpt_base_url" || key == "cli_auth_credentials_store" || key == "profile"
    }

    private static func isRelevantProfileKey(_ key: String) -> Bool {
        key == "chatgpt_base_url"
    }

    private static func stringValue(_ value: ConfigValue, key: String) throws -> String {
        guard case let .string(string) = value else {
            throw CodexConfigLoadError.invalidStringValue(key)
        }
        return string
    }

    private static func parseSectionHeader(_ line: String) throws -> ConfigSection {
        guard line.hasSuffix("]") else {
            throw CodexConfigLoadError.invalidTableHeader(line)
        }
        let body = String(line.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = try parseDottedKey(body)
        if parts.count == 2, parts[0] == "profiles" {
            return .profile(parts[1])
        }
        return .ignored
    }

    private static func parseDottedKey(_ raw: String) throws -> [String] {
        var parts: [String] = []
        var current = String()
        var quote: Character?
        var previousWasBackslash = false

        for character in raw {
            if let activeQuote = quote {
                current.append(character)
                if character == activeQuote && !previousWasBackslash {
                    quote = nil
                }
                previousWasBackslash = character == "\\" && !previousWasBackslash
                if character != "\\" {
                    previousWasBackslash = false
                }
                continue
            }

            switch character {
            case "\"", "'":
                quote = character
                current.append(character)
            case ".":
                parts.append(try parseKeySegment(current))
                current = ""
            default:
                current.append(character)
            }
        }

        if quote != nil {
            throw CodexConfigLoadError.invalidConfigLine(raw)
        }

        parts.append(try parseKeySegment(current))
        return parts
    }

    private static func parseKeySegment(_ raw: String) throws -> String {
        let segment = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !segment.isEmpty else {
            throw CodexConfigLoadError.invalidConfigLine(raw)
        }
        if segment.hasPrefix("\"") || segment.hasPrefix("'") {
            guard case let .string(value) = try ConfigValueParser.parseTomlLiteral(segment) else {
                throw CodexConfigLoadError.invalidConfigLine(raw)
            }
            return value
        }
        return segment
    }

    private static func stripComment(from line: String) -> String {
        var result = String()
        var quote: Character?
        var previousWasBackslash = false

        for character in line {
            if let activeQuote = quote {
                result.append(character)
                if character == activeQuote && !previousWasBackslash {
                    quote = nil
                }
                previousWasBackslash = character == "\\" && !previousWasBackslash
                if character != "\\" {
                    previousWasBackslash = false
                }
                continue
            }

            switch character {
            case "\"", "'":
                quote = character
                result.append(character)
            case "#":
                return result
            default:
                result.append(character)
            }
        }

        return result
    }

    private static func firstEqualsIndex(in line: String) -> String.Index? {
        var quote: Character?
        var squareDepth = 0
        var braceDepth = 0
        var previousWasBackslash = false

        for index in line.indices {
            let character = line[index]
            if let activeQuote = quote {
                if character == activeQuote && !previousWasBackslash {
                    quote = nil
                }
                previousWasBackslash = character == "\\" && !previousWasBackslash
                if character != "\\" {
                    previousWasBackslash = false
                }
                continue
            }

            switch character {
            case "\"", "'":
                quote = character
            case "[":
                squareDepth += 1
            case "]":
                squareDepth -= 1
            case "{":
                braceDepth += 1
            case "}":
                braceDepth -= 1
            case "=" where squareDepth == 0 && braceDepth == 0:
                return index
            default:
                continue
            }
        }

        return nil
    }
}

private enum ConfigSection {
    case topLevel
    case profile(String)
    case ignored
}
