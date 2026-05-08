import Foundation

public enum CodexConfigDefaults {
    public static let chatgptBaseURL = "https://chatgpt.com/backend-api/"
    public static let projectRootMarkers = [".git"]
    public static let projectDocMaxBytes = 32 * 1024
}

public struct CodexRuntimeConfig: Equatable, Sendable {
    public let chatgptBaseURL: String
    public let cliAuthCredentialsStoreMode: AuthCredentialsStoreMode
    public let forcedLoginMethod: ForcedLoginMethod?
    public let features: FeatureStates
    public let activeProfile: String?
    public let projectRootMarkers: [String]
    public let projectDocMaxBytes: Int
    public let projectDocFallbackFilenames: [String]

    public init(
        chatgptBaseURL: String = CodexConfigDefaults.chatgptBaseURL,
        cliAuthCredentialsStoreMode: AuthCredentialsStoreMode = .file,
        forcedLoginMethod: ForcedLoginMethod? = nil,
        features: FeatureStates = .withDefaults(),
        activeProfile: String? = nil,
        projectRootMarkers: [String] = CodexConfigDefaults.projectRootMarkers,
        projectDocMaxBytes: Int = CodexConfigDefaults.projectDocMaxBytes,
        projectDocFallbackFilenames: [String] = []
    ) {
        self.chatgptBaseURL = chatgptBaseURL
        self.cliAuthCredentialsStoreMode = cliAuthCredentialsStoreMode
        self.forcedLoginMethod = forcedLoginMethod
        self.features = features
        self.activeProfile = activeProfile
        self.projectRootMarkers = projectRootMarkers
        self.projectDocMaxBytes = projectDocMaxBytes
        self.projectDocFallbackFilenames = projectDocFallbackFilenames
    }
}

public enum CodexConfigLoadError: Error, Equatable, CustomStringConvertible, Sendable {
    case invalidStringValue(String)
    case invalidBoolValue(String)
    case invalidAuthCredentialsStoreMode
    case invalidForcedLoginMethod
    case invalidProjectRootMarkers
    case invalidConfigLine(String)
    case invalidTableHeader(String)
    case profileNotFound(String)

    public var description: String {
        switch self {
        case let .invalidStringValue(key):
            return "Invalid value for \(key): expected string"
        case let .invalidBoolValue(key):
            return "Invalid value for \(key): expected bool"
        case .invalidAuthCredentialsStoreMode:
            return "Invalid override value for cli_auth_credentials_store"
        case .invalidForcedLoginMethod:
            return "Invalid override value for forced_login_method"
        case .invalidProjectRootMarkers:
            return "project_root_markers must be an array of strings"
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
    public static func defaultSystemConfigFile() -> URL? {
        URL(fileURLWithPath: "/etc/codex/config.toml", isDirectory: false)
    }

    public static func load(
        codexHome: URL,
        cwd: URL? = nil,
        overrides: CliConfigOverrides = CliConfigOverrides(),
        fileManager: FileManager = .default,
        systemConfigFile: URL? = defaultSystemConfigFile()
    ) throws -> CodexRuntimeConfig {
        var parsed = ParsedCodexConfigToml()
        for configFile in baseConfigLayerFiles(
            codexHome: codexHome,
            systemConfigFile: systemConfigFile
        ) {
            if fileManager.fileExists(atPath: configFile.path) {
                let contents = try String(contentsOf: configFile, encoding: .utf8)
                parsed.merge(try ParsedCodexConfigToml.parse(contents))
            }
        }

        if let cwd {
            let projectRootMarkers = try parsed.projectRootMarkersForDiscovery()
            for configFile in projectConfigFiles(
                cwd: cwd,
                projectRootMarkers: projectRootMarkers,
                fileManager: fileManager
            ) {
                if fileManager.fileExists(atPath: configFile.path) {
                    let contents = try String(contentsOf: configFile, encoding: .utf8)
                    parsed.merge(try ParsedCodexConfigToml.parse(contents))
                }
            }
        }

        try parsed.apply(overrides: overrides)
        return try parsed.resolvedConfig()
    }

    private static func baseConfigLayerFiles(
        codexHome: URL,
        systemConfigFile: URL?
    ) -> [URL] {
        var files: [URL] = []
        if let systemConfigFile {
            files.append(systemConfigFile)
        }
        files.append(codexHome.appendingPathComponent("config.toml", isDirectory: false))
        return files
    }

    private static func projectConfigFiles(
        cwd: URL,
        projectRootMarkers: [String],
        fileManager: FileManager
    ) -> [URL] {
        let cwdPath = cwd.standardizedFileURL.path
        let cwdURL = URL(fileURLWithPath: cwdPath, isDirectory: true)
        let ancestors = ancestorDirectories(from: cwdURL)
        let projectRoot: URL
        if projectRootMarkers.isEmpty {
            projectRoot = cwdURL
        } else {
            projectRoot = ancestors.first { ancestor in
                projectRootMarkers.contains { marker in
                    fileManager.fileExists(atPath: ancestor.appendingPathComponent(marker).path)
                }
            } ?? cwdURL
        }

        guard let projectRootIndex = ancestors.firstIndex(of: projectRoot),
              let cwdIndex = ancestors.firstIndex(of: cwdURL)
        else {
            return []
        }

        let dirs = ancestors[cwdIndex...projectRootIndex].reversed()
        return dirs.compactMap { directory in
            let dotCodex = directory.appendingPathComponent(".codex", isDirectory: true)
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: dotCodex.path, isDirectory: &isDirectory),
                  isDirectory.boolValue
            else {
                return nil
            }
            return dotCodex.appendingPathComponent("config.toml", isDirectory: false)
        }
    }

    private static func ancestorDirectories(from url: URL) -> [URL] {
        var directories: [URL] = []
        var current = url.standardizedFileURL
        while true {
            directories.append(current)
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path {
                break
            }
            current = parent
        }
        return directories
    }
}

private struct ParsedCodexConfigToml {
    var topLevel: [String: ConfigValue] = [:]
    var profiles: [String: [String: ConfigValue]] = [:]
    var features: [String: Bool] = [:]
    var profileFeatures: [String: [String: Bool]] = [:]

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
                if case let .profileFeatures(name) = section {
                    if parsed.profiles[name] == nil {
                        parsed.profiles[name] = [:]
                    }
                }
                continue
            }

            guard let equalsIndex = firstEqualsIndex(in: line) else {
                if case .ignored = section {
                    continue
                }
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
            case .features:
                parsed.features[key] = try Self.boolValue(
                    ConfigValueParser.parseTomlLiteral(valueText),
                    key: "features.\(key)"
                )
            case let .profileFeatures(name):
                parsed.profileFeatures[name, default: [:]][key] = try Self.boolValue(
                    ConfigValueParser.parseTomlLiteral(valueText),
                    key: "profiles.\(name).features.\(key)"
                )
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

            if parts.count == 2, parts[0] == "features" {
                features[parts[1]] = try Self.boolValue(value, key: path)
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

            if parts.count == 4, parts[0] == "profiles", parts[2] == "features" {
                profileFeatures[parts[1], default: [:]][parts[3]] = try Self.boolValue(value, key: path)
            }
        }
    }

    mutating func merge(_ overlay: ParsedCodexConfigToml) {
        for (key, value) in overlay.topLevel {
            topLevel[key] = value
        }

        for (profileName, profileValues) in overlay.profiles {
            var mergedProfile = profiles[profileName] ?? [:]
            for (key, value) in profileValues {
                mergedProfile[key] = value
            }
            profiles[profileName] = mergedProfile
        }

        for (key, value) in overlay.features {
            features[key] = value
        }

        for (profileName, profileValues) in overlay.profileFeatures {
            var mergedProfile = profileFeatures[profileName] ?? [:]
            for (key, value) in profileValues {
                mergedProfile[key] = value
            }
            profileFeatures[profileName] = mergedProfile
        }
    }

    func resolvedConfig() throws -> CodexRuntimeConfig {
        var config = CodexRuntimeConfig()

        if let baseURL = topLevel["chatgpt_base_url"] {
            config = CodexRuntimeConfig(
                chatgptBaseURL: try Self.stringValue(baseURL, key: "chatgpt_base_url"),
                cliAuthCredentialsStoreMode: config.cliAuthCredentialsStoreMode,
                forcedLoginMethod: config.forcedLoginMethod,
                features: config.features,
                activeProfile: config.activeProfile,
                projectRootMarkers: config.projectRootMarkers,
                projectDocMaxBytes: config.projectDocMaxBytes,
                projectDocFallbackFilenames: config.projectDocFallbackFilenames
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
                forcedLoginMethod: config.forcedLoginMethod,
                features: config.features,
                activeProfile: config.activeProfile,
                projectRootMarkers: config.projectRootMarkers,
                projectDocMaxBytes: config.projectDocMaxBytes,
                projectDocFallbackFilenames: config.projectDocFallbackFilenames
            )
        }

        if let forcedLoginMethod = topLevel["forced_login_method"] {
            let rawMethod = try Self.stringValue(forcedLoginMethod, key: "forced_login_method")
            guard let method = ForcedLoginMethod(rawValue: rawMethod) else {
                throw CodexConfigLoadError.invalidForcedLoginMethod
            }
            config = CodexRuntimeConfig(
                chatgptBaseURL: config.chatgptBaseURL,
                cliAuthCredentialsStoreMode: config.cliAuthCredentialsStoreMode,
                forcedLoginMethod: method,
                features: config.features,
                activeProfile: config.activeProfile,
                projectRootMarkers: config.projectRootMarkers,
                projectDocMaxBytes: config.projectDocMaxBytes,
                projectDocFallbackFilenames: config.projectDocFallbackFilenames
            )
        }

        if let projectRootMarkers = topLevel["project_root_markers"] {
            config = CodexRuntimeConfig(
                chatgptBaseURL: config.chatgptBaseURL,
                cliAuthCredentialsStoreMode: config.cliAuthCredentialsStoreMode,
                forcedLoginMethod: config.forcedLoginMethod,
                features: config.features,
                activeProfile: config.activeProfile,
                projectRootMarkers: try Self.stringArrayValue(projectRootMarkers, key: "project_root_markers"),
                projectDocMaxBytes: config.projectDocMaxBytes,
                projectDocFallbackFilenames: config.projectDocFallbackFilenames
            )
        }

        if let projectDocMaxBytes = topLevel["project_doc_max_bytes"] {
            config = CodexRuntimeConfig(
                chatgptBaseURL: config.chatgptBaseURL,
                cliAuthCredentialsStoreMode: config.cliAuthCredentialsStoreMode,
                forcedLoginMethod: config.forcedLoginMethod,
                features: config.features,
                activeProfile: config.activeProfile,
                projectRootMarkers: config.projectRootMarkers,
                projectDocMaxBytes: try Self.nonNegativeIntValue(projectDocMaxBytes, key: "project_doc_max_bytes"),
                projectDocFallbackFilenames: config.projectDocFallbackFilenames
            )
        }

        if let fallbackFilenames = topLevel["project_doc_fallback_filenames"] {
            config = CodexRuntimeConfig(
                chatgptBaseURL: config.chatgptBaseURL,
                cliAuthCredentialsStoreMode: config.cliAuthCredentialsStoreMode,
                forcedLoginMethod: config.forcedLoginMethod,
                features: config.features,
                activeProfile: config.activeProfile,
                projectRootMarkers: config.projectRootMarkers,
                projectDocMaxBytes: config.projectDocMaxBytes,
                projectDocFallbackFilenames: try Self.stringArrayValue(
                    fallbackFilenames,
                    key: "project_doc_fallback_filenames"
                )
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
                    forcedLoginMethod: config.forcedLoginMethod,
                    features: config.features,
                    activeProfile: activeProfile,
                    projectRootMarkers: config.projectRootMarkers,
                    projectDocMaxBytes: config.projectDocMaxBytes,
                    projectDocFallbackFilenames: config.projectDocFallbackFilenames
                )
            } else {
                config = CodexRuntimeConfig(
                    chatgptBaseURL: config.chatgptBaseURL,
                    cliAuthCredentialsStoreMode: config.cliAuthCredentialsStoreMode,
                    forcedLoginMethod: config.forcedLoginMethod,
                    features: config.features,
                    activeProfile: activeProfile,
                    projectRootMarkers: config.projectRootMarkers,
                    projectDocMaxBytes: config.projectDocMaxBytes,
                    projectDocFallbackFilenames: config.projectDocFallbackFilenames
                )
            }
        }

        var featureStates = FeatureStates.withDefaults()
        featureStates.apply(featureValues: features)
        if let activeProfile = config.activeProfile {
            featureStates.apply(featureValues: profileFeatures[activeProfile] ?? [:])
        }
        config = CodexRuntimeConfig(
            chatgptBaseURL: config.chatgptBaseURL,
            cliAuthCredentialsStoreMode: config.cliAuthCredentialsStoreMode,
            forcedLoginMethod: config.forcedLoginMethod,
            features: featureStates,
            activeProfile: config.activeProfile,
            projectRootMarkers: config.projectRootMarkers,
            projectDocMaxBytes: config.projectDocMaxBytes,
            projectDocFallbackFilenames: config.projectDocFallbackFilenames
        )

        return config
    }

    func projectRootMarkersForDiscovery() throws -> [String] {
        guard let value = topLevel["project_root_markers"] else {
            return CodexConfigDefaults.projectRootMarkers
        }
        return try Self.stringArrayValue(value, key: "project_root_markers")
    }

    private static func isRelevantTopLevelKey(_ key: String) -> Bool {
        key == "chatgpt_base_url"
            || key == "cli_auth_credentials_store"
            || key == "forced_login_method"
            || key == "profile"
            || key == "project_root_markers"
            || key == "project_doc_max_bytes"
            || key == "project_doc_fallback_filenames"
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

    private static func boolValue(_ value: ConfigValue, key: String) throws -> Bool {
        guard case let .bool(bool) = value else {
            throw CodexConfigLoadError.invalidBoolValue(key)
        }
        return bool
    }

    private static func stringArrayValue(_ value: ConfigValue, key: String) throws -> [String] {
        guard case let .array(values) = value else {
            if key == "project_root_markers" {
                throw CodexConfigLoadError.invalidProjectRootMarkers
            }
            throw CodexConfigLoadError.invalidStringValue(key)
        }

        var strings: [String] = []
        for value in values {
            guard case let .string(string) = value else {
                if key == "project_root_markers" {
                    throw CodexConfigLoadError.invalidProjectRootMarkers
                }
                throw CodexConfigLoadError.invalidStringValue(key)
            }
            strings.append(string)
        }
        return strings
    }

    private static func nonNegativeIntValue(_ value: ConfigValue, key: String) throws -> Int {
        guard case let .integer(integer) = value, integer >= 0 else {
            throw CodexConfigLoadError.invalidStringValue(key)
        }
        return Int(integer)
    }

    private static func parseSectionHeader(_ line: String) throws -> ConfigSection {
        guard line.hasSuffix("]") else {
            throw CodexConfigLoadError.invalidTableHeader(line)
        }
        let body = String(line.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = try parseDottedKey(body)
        if parts.count == 1, parts[0] == "features" {
            return .features
        }
        if parts.count == 2, parts[0] == "profiles" {
            return .profile(parts[1])
        }
        if parts.count == 3, parts[0] == "profiles", parts[2] == "features" {
            return .profileFeatures(parts[1])
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
    case features
    case profileFeatures(String)
    case ignored
}
