import Foundation

public struct ConfigLayerLoaderOverrides: Equatable, Sendable {
    public var managedConfigPath: URL?
    public var managedPreferencesBase64: String?
    public var requirementsPath: URL?
    public var userConfigPath: URL?
    public var userConfigProfile: String?
    public var ignoreUserConfig: Bool
    public var ignoreUserAndProjectExecPolicyRules: Bool
    public var ignoreManagedRequirements: Bool

    public init(
        managedConfigPath: URL? = nil,
        managedPreferencesBase64: String? = nil,
        requirementsPath: URL? = nil,
        userConfigPath: URL? = nil,
        userConfigProfile: String? = nil,
        ignoreUserConfig: Bool = false,
        ignoreUserAndProjectExecPolicyRules: Bool = false,
        ignoreManagedRequirements: Bool = false
    ) {
        self.managedConfigPath = managedConfigPath
        self.managedPreferencesBase64 = managedPreferencesBase64
        self.requirementsPath = requirementsPath
        self.userConfigPath = userConfigPath
        self.userConfigProfile = userConfigProfile
        self.ignoreUserConfig = ignoreUserConfig
        self.ignoreUserAndProjectExecPolicyRules = ignoreUserAndProjectExecPolicyRules
        self.ignoreManagedRequirements = ignoreManagedRequirements
    }
}

public struct ManagedConfigFromFile: Equatable, Sendable {
    public var managedConfig: ConfigValue
    public var file: AbsolutePath

    public init(managedConfig: ConfigValue, file: AbsolutePath) {
        self.managedConfig = managedConfig
        self.file = file
    }
}

public struct LoadedConfigLayers: Equatable, Sendable {
    public var managedConfig: ManagedConfigFromFile?
    public var managedConfigFromMDM: ManagedConfigFromMDM?

    public init(managedConfig: ManagedConfigFromFile? = nil, managedConfigFromMDM: ManagedConfigFromMDM? = nil) {
        self.managedConfig = managedConfig
        self.managedConfigFromMDM = managedConfigFromMDM
    }
}

public struct ManagedConfigFromMDM: Equatable, Sendable {
    public var managedConfig: ConfigValue
    public var rawToml: String

    public init(managedConfig: ConfigValue, rawToml: String) {
        self.managedConfig = managedConfig
        self.rawToml = rawToml
    }
}

private struct LoadedProjectLayers: Equatable, Sendable {
    var layers: [ConfigLayerEntry]
    var startupWarnings: [String]
}

public enum ConfigLayerLoadError: Error, Equatable, CustomStringConvertible, Sendable {
    case invalidData(String)
    case readFailed(path: String, message: String)
    case parseFailed(path: String?, message: String)

    public var description: String {
        switch self {
        case let .invalidData(message):
            return message
        case let .readFailed(path, message):
            return "Failed to read \(path): \(message)"
        case let .parseFailed(path, message):
            if let path {
                return "Failed to parse \(path): \(message)"
            }
            return "Failed to parse managed preferences TOML: \(message)"
        }
    }
}

public enum CodexConfigLayerLoader {
    public static let managedConfigEnvironmentVariable = "CODEX_MANAGED_CONFIG_PATH"
    public static let managedPreferencesApplicationID = "com.openai.codex"
    public static let managedPreferencesConfigKey = "config_toml_base64"

    public static func defaultRequirementsTomlFile() -> URL? {
        #if os(Windows)
        return nil
        #else
        return URL(fileURLWithPath: "/etc/codex/requirements.toml", isDirectory: false)
        #endif
    }

    public static func managedConfigDefaultPath(
        codexHome: URL,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL {
        if let path = environment[managedConfigEnvironmentVariable] {
            return URL(fileURLWithPath: path, isDirectory: false)
        }

        #if os(Windows)
        return codexHome.appendingPathComponent("managed_config.toml", isDirectory: false)
        #else
        return URL(fileURLWithPath: "/etc/codex/managed_config.toml", isDirectory: false)
        #endif
    }

    public static func loadConfigLayers(
        codexHome: URL,
        overrides: ConfigLayerLoaderOverrides = ConfigLayerLoaderOverrides(),
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) throws -> LoadedConfigLayers {
        let managedConfigURL = overrides.managedConfigPath
            ?? managedConfigDefaultPath(codexHome: codexHome, environment: environment)
        let managedConfigPath = try AbsolutePath(absolutePath: managedConfigURL.standardizedFileURL.path)
        let managedConfig = try readConfig(from: managedConfigURL, fileManager: fileManager).map {
            ManagedConfigFromFile(managedConfig: $0, file: managedConfigPath)
        }

        let managedPreferences = try loadManagedAdminConfig(
            overrideBase64: overrides.managedPreferencesBase64
        )

        return LoadedConfigLayers(
            managedConfig: managedConfig,
            managedConfigFromMDM: managedPreferences
        )
    }

    public static func loadConfigLayerStack(
        codexHome: URL,
        cwd: URL? = nil,
        cliOverrides: CliConfigOverrides = CliConfigOverrides(),
        threadConfigSources: [ThreadConfigSource] = [],
        overrides: ConfigLayerLoaderOverrides = ConfigLayerLoaderOverrides(),
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default,
        systemConfigFile: URL? = CodexConfigLoader.defaultSystemConfigFile()
    ) throws -> ConfigLayerStack {
        let loadedConfigLayers = try loadConfigLayers(
            codexHome: codexHome,
            overrides: overrides,
            environment: environment,
            fileManager: fileManager
        )
        var requirementsToml = ConfigRequirementsToml()
        if !overrides.ignoreManagedRequirements {
            if let requirementsPath = overrides.requirementsPath ?? defaultRequirementsTomlFile() {
                try loadRequirementsToml(into: &requirementsToml, from: requirementsPath, fileManager: fileManager)
            }
            try loadRequirementsFromLegacyScheme(into: &requirementsToml, loadedConfigLayers: loadedConfigLayers)
        }

        var layers: [ConfigLayerEntry] = []
        var startupWarnings: [String] = []

        if let systemConfigFile {
            let systemPath = try AbsolutePath(absolutePath: systemConfigFile.standardizedFileURL.path)
            layers.append(try loadRequiredConfigLayer(
                configFile: systemConfigFile,
                source: .system(file: systemPath),
                fileManager: fileManager
            ))
        }

        let baseUserConfigFile = codexHome.appendingPathComponent("config.toml", isDirectory: false).standardizedFileURL
        let activeUserConfigFile = (overrides.userConfigPath ?? baseUserConfigFile).standardizedFileURL
        let activeUserPath = try AbsolutePath(absolutePath: activeUserConfigFile.path)
        if overrides.ignoreUserConfig {
            layers.append(ConfigLayerEntry(name: .user(file: activeUserPath), config: .table([:])))
        } else {
            let baseUserConfig = try readConfig(from: baseUserConfigFile, fileManager: fileManager) ?? .table([:])
            if let profile = overrides.userConfigProfile,
               hasLegacyProfile(named: profile, in: baseUserConfig)
            {
                throw ConfigLayerLoadError.invalidData(
                    "--profile-v2 `\(profile)` cannot be used while \(baseUserConfigFile.path) contains legacy `[profiles.\(profile)]` config; move those settings into \(activeUserConfigFile.path) or remove `[profiles.\(profile)]`"
                )
            }

            var userConfig = baseUserConfig
            if activeUserConfigFile != baseUserConfigFile {
                let activeUserConfig = try readConfig(from: activeUserConfigFile, fileManager: fileManager) ?? .table([:])
                userConfig.merge(overlay: activeUserConfig)
            }
            layers.append(ConfigLayerEntry(
                name: .user(file: activeUserPath),
                config: userConfig
            ))
        }

        if let cwd {
            let projectRootMarkers = try projectRootMarkers(from: mergedConfig(layers: layers))
                ?? CodexConfigDefaults.projectRootMarkers
            let cwdURL = cwd.standardizedFileURL
            let projectRoot = findProjectRoot(
                cwd: cwdURL,
                projectRootMarkers: projectRootMarkers,
                fileManager: fileManager
            )
            let projectLayers = try loadProjectLayers(
                codexHome: codexHome,
                cwd: cwdURL,
                projectRoot: projectRoot,
                fileManager: fileManager
            )
            layers.append(contentsOf: projectLayers.layers)
            startupWarnings.append(contentsOf: projectLayers.startupWarnings)
        }

        if !cliOverrides.rawOverrides.isEmpty {
            layers.append(ConfigLayerEntry(
                name: .sessionFlags,
                config: try cliOverrides.applying()
            ))
        }

        for source in threadConfigSources {
            if let layer = try source.configLayerEntry() {
                insertLayerByPrecedence(layer, into: &layers)
            }
        }

        if let managedConfig = loadedConfigLayers.managedConfig {
            layers.append(ConfigLayerEntry(
                name: .legacyManagedConfigTomlFromFile(file: managedConfig.file),
                config: managedConfig.managedConfig
            ))
        }

        if let managedConfigFromMDM = loadedConfigLayers.managedConfigFromMDM {
            let managedConfig = try resolveRelativePaths(
                in: managedConfigFromMDM.managedConfig,
                baseDirectory: codexHome
            )
            layers.append(ConfigLayerEntry(
                name: .legacyManagedConfigTomlFromMdm,
                config: managedConfig,
                rawToml: managedConfigFromMDM.rawToml
            ))
        }

        return try ConfigLayerStack(
            layers: layers,
            requirements: try requirementsToml.requirements(),
            requirementsToml: requirementsToml,
            ignoreUserAndProjectExecPolicyRules: overrides.ignoreUserAndProjectExecPolicyRules,
            startupWarnings: startupWarnings
        )
    }

    private static func insertLayerByPrecedence(_ layer: ConfigLayerEntry, into layers: inout [ConfigLayerEntry]) {
        if let index = layers.firstIndex(where: { $0.name.precedence > layer.name.precedence }) {
            layers.insert(layer, at: index)
        } else {
            layers.append(layer)
        }
    }

    public static func readConfig(
        from url: URL,
        logMissingAsInfo _: Bool = false,
        fileManager: FileManager = .default
    ) throws -> ConfigValue? {
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }

        let contents: String
        do {
            contents = try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw ConfigLayerLoadError.readFailed(path: url.path, message: String(describing: error))
        }

        do {
            let parsed = try ConfigTomlParser.parse(contents)
            return try resolveRelativePaths(in: parsed, baseDirectory: url.deletingLastPathComponent())
        } catch {
            throw ConfigLayerLoadError.parseFailed(path: url.path, message: String(describing: error))
        }
    }

    public static func loadManagedAdminConfigLayer(overrideBase64: String?) throws -> ConfigValue? {
        try loadManagedAdminConfig(overrideBase64: overrideBase64)?.managedConfig
    }

    public static func loadManagedAdminConfig(overrideBase64: String?) throws -> ManagedConfigFromMDM? {
        if let overrideBase64 {
            let trimmed = overrideBase64.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : try parseManagedPreferencesBase64Layer(trimmed)
        }

        guard let encoded = UserDefaults(suiteName: managedPreferencesApplicationID)?
            .string(forKey: managedPreferencesConfigKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !encoded.isEmpty
        else {
            return nil
        }
        return try parseManagedPreferencesBase64Layer(encoded)
    }

    public static func parseManagedPreferencesBase64(_ encoded: String) throws -> ConfigValue {
        try parseManagedPreferencesBase64Layer(encoded).managedConfig
    }

    public static func parseManagedPreferencesBase64Layer(_ encoded: String) throws -> ManagedConfigFromMDM {
        guard let decoded = Data(base64Encoded: encoded) else {
            throw ConfigLayerLoadError.invalidData("Failed to decode managed preferences as base64")
        }
        guard let decodedString = String(data: decoded, encoding: .utf8) else {
            throw ConfigLayerLoadError.invalidData("Managed preferences base64 contents were not valid UTF-8")
        }

        let value: ConfigValue
        do {
            value = try ConfigTomlParser.parse(decodedString)
        } catch {
            throw ConfigLayerLoadError.parseFailed(path: nil, message: String(describing: error))
        }

        guard case .table = value else {
            throw ConfigLayerLoadError.invalidData("managed preferences root must be a table")
        }
        return ManagedConfigFromMDM(managedConfig: value, rawToml: decodedString)
    }

    public static func loadRequirementsToml(
        into requirementsToml: inout ConfigRequirementsToml,
        from url: URL,
        fileManager: FileManager = .default
    ) throws {
        guard fileManager.fileExists(atPath: url.path) else {
            return
        }

        let contents: String
        do {
            contents = try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw ConfigLayerLoadError.readFailed(path: url.path, message: String(describing: error))
        }

        do {
            var parsed = try ConfigRequirementsToml.parse(contents)
            parsed.applyRemoteSandboxConfig(hostname: ProcessInfo.processInfo.hostName)
            if parsed.hooks != nil {
                parsed.hooksSource = .system
                parsed.hooksSourceDescription = url.standardizedFileURL.path
            }
            if parsed.mcpServers != nil {
                parsed.mcpServersSourceDescription = url.standardizedFileURL.path
            }
            requirementsToml.mergeUnsetFields(from: parsed)
        } catch {
            throw ConfigLayerLoadError.parseFailed(path: url.path, message: String(describing: error))
        }
    }

    public static func loadRequirementsFromLegacyScheme(
        into requirementsToml: inout ConfigRequirementsToml,
        loadedConfigLayers: LoadedConfigLayers
    ) throws {
        for config in [
            loadedConfigLayers.managedConfigFromMDM?.managedConfig,
            loadedConfigLayers.managedConfig.map(\.managedConfig)
        ].compactMap({ $0 }) {
            requirementsToml.mergeUnsetFields(from: try legacyRequirements(from: config))
        }
    }

    public static func resolveRelativePaths(in value: ConfigValue, baseDirectory: URL) throws -> ConfigValue {
        switch value {
        case let .array(values):
            return .array(try values.map { try resolveRelativePaths(in: $0, baseDirectory: baseDirectory) })
        case let .table(table):
            var resolved: [String: ConfigValue] = [:]
            for (key, child) in table {
                if Self.configPathKeys.contains(key), case let .string(path) = child {
                    resolved[key] = try .string(resolveConfigPath(path, baseDirectory: baseDirectory))
                } else {
                    resolved[key] = try resolveRelativePaths(in: child, baseDirectory: baseDirectory)
                }
            }
            return .table(resolved)
        default:
            return value
        }
    }

    private static func loadRequiredConfigLayer(
        configFile: URL,
        source: ConfigLayerSource,
        fileManager: FileManager
    ) throws -> ConfigLayerEntry {
        let config = try readConfig(from: configFile, fileManager: fileManager) ?? .table([:])
        return ConfigLayerEntry(name: source, config: config)
    }

    private static func hasLegacyProfile(named profile: String, in config: ConfigValue) -> Bool {
        guard case let .table(table) = config,
              case let .table(profiles)? = table["profiles"]
        else {
            return false
        }
        return profiles[profile] != nil
    }

    private static let configPathKeys: Set<String> = [
        "model_instructions_file",
        "experimental_compact_prompt_file"
    ]

    private static func resolveConfigPath(_ path: String, baseDirectory: URL) throws -> String {
        if path.hasPrefix("/") || path.hasPrefix("~/") {
            return try AbsolutePath(absolutePath: path).path
        }
        return try AbsolutePath.resolve(path, against: baseDirectory.standardizedFileURL.path).path
    }

    private static func legacyRequirements(from config: ConfigValue) throws -> ConfigRequirementsToml {
        guard case let .table(table) = config else {
            return ConfigRequirementsToml()
        }

        var requirements = ConfigRequirementsToml()
        if let approvalValue = table["approval_policy"] {
            guard case let .string(rawApproval) = approvalValue,
                  let approvalPolicy = AskForApproval(rawValue: rawApproval)
            else {
                throw ConfigLayerLoadError.invalidData(
                    "Failed to parse config requirements as TOML: invalid approval_policy"
                )
            }
            requirements.allowedApprovalPolicies = [approvalPolicy]
        }

        if let sandboxValue = table["sandbox_mode"] {
            guard case let .string(rawSandboxMode) = sandboxValue,
                  let sandboxMode = SandboxMode(rawValue: rawSandboxMode)
            else {
                throw ConfigLayerLoadError.invalidData(
                    "Failed to parse config requirements as TOML: invalid sandbox_mode"
                )
            }
            let requirement = SandboxModeRequirement(sandboxMode: sandboxMode)
            requirements.allowedSandboxModes = requirement == .readOnly ? [.readOnly] : [.readOnly, requirement]
        }

        return requirements
    }

    private static func mergedConfig(layers: [ConfigLayerEntry]) -> ConfigValue {
        var merged = ConfigValue.table([:])
        for layer in layers {
            merged.merge(overlay: layer.config)
        }
        return merged
    }

    private static func projectRootMarkers(from config: ConfigValue) throws -> [String]? {
        guard case let .table(table) = config,
              let value = table["project_root_markers"]
        else {
            return nil
        }

        guard case let .array(entries) = value else {
            throw CodexConfigLoadError.invalidProjectRootMarkers
        }
        return try entries.map { entry in
            guard case let .string(marker) = entry else {
                throw CodexConfigLoadError.invalidProjectRootMarkers
            }
            return marker
        }
    }

    private static func findProjectRoot(
        cwd: URL,
        projectRootMarkers: [String],
        fileManager: FileManager
    ) -> URL {
        guard !projectRootMarkers.isEmpty else {
            return cwd
        }

        for ancestor in ancestorDirectories(from: cwd) {
            if projectRootMarkers.contains(where: { marker in
                fileManager.fileExists(atPath: ancestor.appendingPathComponent(marker).path)
            }) {
                return ancestor
            }
        }
        return cwd
    }

    private static func loadProjectLayers(
        codexHome: URL,
        cwd: URL,
        projectRoot: URL,
        fileManager: FileManager
    ) throws -> LoadedProjectLayers {
        guard let cwdIndex = ancestorDirectories(from: cwd).firstIndex(of: projectRoot) else {
            return LoadedProjectLayers(layers: [], startupWarnings: [])
        }

        let dirs = Array(ancestorDirectories(from: cwd)[0...cwdIndex].reversed())
        var layers: [ConfigLayerEntry] = []
        var startupWarnings: [String] = []
        let normalizedCodexHome = normalizedPath(codexHome)
        for directory in dirs {
            let dotCodex = directory.appendingPathComponent(".codex", isDirectory: true)
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: dotCodex.path, isDirectory: &isDirectory),
                  isDirectory.boolValue
            else {
                continue
            }
            guard normalizedPath(dotCodex) != normalizedCodexHome else {
                continue
            }

            let dotCodexPath = try AbsolutePath(absolutePath: dotCodex.standardizedFileURL.path)
            let configFile = dotCodex.appendingPathComponent("config.toml", isDirectory: false)
            let rawConfig = try readConfig(from: configFile, fileManager: fileManager) ?? .table([:])
            let (config, ignoredKeys) = sanitizeProjectConfig(rawConfig)
            if !ignoredKeys.isEmpty {
                startupWarnings.append(projectIgnoredConfigKeysWarning(
                    dotCodexFolder: dotCodexPath,
                    ignoredKeys: ignoredKeys
                ))
            }
            layers.append(ConfigLayerEntry(
                name: .project(dotCodexFolder: dotCodexPath),
                config: config
            ))
        }
        return LoadedProjectLayers(layers: layers, startupWarnings: startupWarnings)
    }

    private static let projectLocalConfigDenylist: [String] = [
        "openai_base_url",
        "chatgpt_base_url",
        "model_provider",
        "model_providers",
        "notify",
        "profile",
        "profiles",
        "experimental_realtime_ws_base_url",
        "otel"
    ]

    private static func sanitizeProjectConfig(_ config: ConfigValue) -> (ConfigValue, [String]) {
        guard case var .table(table) = config else {
            return (config, [])
        }
        var ignoredKeys: [String] = []
        for key in projectLocalConfigDenylist where table.removeValue(forKey: key) != nil {
            ignoredKeys.append(key)
        }
        return (.table(table), ignoredKeys)
    }

    private static func projectIgnoredConfigKeysWarning(
        dotCodexFolder: AbsolutePath,
        ignoredKeys: [String]
    ) -> String {
        "Ignored unsupported project-local config keys in \(dotCodexFolder.path)/config.toml: \(ignoredKeys.joined(separator: ", ")). If you want these settings to apply, manually set them in your user-level config.toml."
    }

    private static func normalizedPath(_ url: URL) -> String {
        (url.standardizedFileURL.path as NSString).standardizingPath
    }

    private static func ancestorDirectories(from url: URL) -> [URL] {
        var directories: [URL] = []
        var currentPath = (url.standardizedFileURL.path as NSString).standardizingPath
        while true {
            directories.append(URL(fileURLWithPath: currentPath, isDirectory: true))
            let parent = (currentPath as NSString).deletingLastPathComponent
            let parentPath = parent.isEmpty ? "/" : parent
            if parentPath == currentPath {
                break
            }
            currentPath = parentPath
        }
        return directories
    }
}

enum ConfigTomlParser {
    static func parse(_ contents: String) throws -> ConfigValue {
        var root: [String: ConfigValue] = [:]
        var context = ConfigTomlContext.table([])

        for rawLine in contents.split(whereSeparator: \.isNewline) {
            let line = stripComment(from: String(rawLine)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            if line.hasPrefix("[") {
                guard line.hasSuffix("]") else {
                    throw CodexConfigLoadError.invalidTableHeader(line)
                }
                if line.hasPrefix("[["), line.hasSuffix("]]") {
                    let body = String(line.dropFirst(2).dropLast(2)).trimmingCharacters(in: .whitespacesAndNewlines)
                    let path = try parseDottedKey(body)
                    let index = appendTableArrayEntry(at: path, in: &root)
                    context = .arrayTable(path, index)
                } else {
                    let body = String(line.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
                    let path = try parseDottedKey(body)
                    ensureTable(at: path, in: &root)
                    context = .table(path)
                }
                continue
            }

            guard let equalsIndex = firstEqualsIndex(in: line) else {
                throw CodexConfigLoadError.invalidConfigLine(line)
            }

            let key = String(line[..<equalsIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            let valueStart = line.index(after: equalsIndex)
            let valueText = String(line[valueStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
            let keyPath = try parseDottedKey(key)
            let value = try ConfigValueParser.parseTomlLiteral(valueText)
            switch context {
            case let .table(tablePath):
                set(value, at: tablePath + keyPath, in: &root)
            case let .arrayTable(tablePath, index):
                setInArrayTable(value, keyPath: keyPath, tablePath: tablePath, index: index, in: &root)
            }
        }

        return .table(root)
    }

    private static func ensureTable(at path: [String], in root: inout [String: ConfigValue]) {
        guard !path.isEmpty else { return }
        set(.table([:]), at: path, in: &root, preserveExistingTable: true)
    }

    private static func appendTableArrayEntry(at path: [String], in root: inout [String: ConfigValue]) -> Int {
        guard let first = path.first else { return 0 }
        if path.count == 1 {
            var array: [ConfigValue]
            if case let .array(existing) = root[first] {
                array = existing
            } else {
                array = []
            }
            array.append(.table([:]))
            root[first] = .array(array)
            return array.count - 1
        }

        var childTable: [String: ConfigValue]
        if case let .table(existing) = root[first] {
            childTable = existing
        } else if case var .array(existing) = root[first],
                  let lastIndex = existing.indices.last,
                  case var .table(lastTable) = existing[lastIndex] {
            let index = appendTableArrayEntry(at: Array(path.dropFirst()), in: &lastTable)
            existing[lastIndex] = .table(lastTable)
            root[first] = .array(existing)
            return index
        } else {
            childTable = [:]
        }
        let index = appendTableArrayEntry(at: Array(path.dropFirst()), in: &childTable)
        root[first] = .table(childTable)
        return index
    }

    private static func setInArrayTable(
        _ value: ConfigValue,
        keyPath: [String],
        tablePath: [String],
        index: Int,
        in root: inout [String: ConfigValue]
    ) {
        guard let first = tablePath.first else { return }
        if tablePath.count == 1 {
            guard case var .array(array) = root[first],
                  array.indices.contains(index)
            else {
                return
            }
            var table: [String: ConfigValue]
            if case let .table(existing) = array[index] {
                table = existing
            } else {
                table = [:]
            }
            set(value, at: keyPath, in: &table)
            array[index] = .table(table)
            root[first] = .array(array)
            return
        }

        var childTable: [String: ConfigValue]
        if case let .table(existing) = root[first] {
            childTable = existing
        } else if case var .array(existing) = root[first],
                  let lastIndex = existing.indices.last,
                  case var .table(lastTable) = existing[lastIndex] {
            setInArrayTable(
                value,
                keyPath: keyPath,
                tablePath: Array(tablePath.dropFirst()),
                index: index,
                in: &lastTable
            )
            existing[lastIndex] = .table(lastTable)
            root[first] = .array(existing)
            return
        } else {
            childTable = [:]
        }
        setInArrayTable(value, keyPath: keyPath, tablePath: Array(tablePath.dropFirst()), index: index, in: &childTable)
        root[first] = .table(childTable)
    }

    private static func set(
        _ value: ConfigValue,
        at path: [String],
        in root: inout [String: ConfigValue],
        preserveExistingTable: Bool = false
    ) {
        guard let first = path.first else { return }
        if path.count == 1 {
            if preserveExistingTable, case .table = root[first] {
                return
            }
            root[first] = value
            return
        }

        var childTable: [String: ConfigValue]
        if case let .table(existing) = root[first] {
            childTable = existing
        } else {
            childTable = [:]
        }
        set(value, at: Array(path.dropFirst()), in: &childTable, preserveExistingTable: preserveExistingTable)
        root[first] = .table(childTable)
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

    private enum ConfigTomlContext {
        case table([String])
        case arrayTable([String], Int)
    }
}
