import Foundation

public enum ConfiguredEnvironmentLoadError: Error, Equatable, CustomStringConvertible, Sendable {
    case protocolError(String)

    public var description: String {
        switch self {
        case let .protocolError(message):
            return "exec-server protocol error: \(message)"
        }
    }
}

public struct StdioConfiguredEnvironmentCommand: Equatable, Sendable {
    public let program: String
    public let args: [String]
    public let env: [String: String]
    public let cwd: String?

    public init(
        program: String,
        args: [String] = [],
        env: [String: String] = [:],
        cwd: String? = nil
    ) {
        self.program = program
        self.args = args
        self.env = env
        self.cwd = cwd
    }
}

public enum ConfiguredEnvironmentTransport: Equatable, Sendable {
    case local
    case websocketURL(String)
    case stdio(StdioConfiguredEnvironmentCommand)
}

public struct ConfiguredEnvironmentEntry: Equatable, Sendable {
    public let id: String
    public let transport: ConfiguredEnvironmentTransport

    public init(id: String, transport: ConfiguredEnvironmentTransport) {
        self.id = id
        self.transport = transport
    }

    public var isRemote: Bool {
        transport != .local
    }

    public var execServerURL: String? {
        if case let .websocketURL(url) = transport {
            return url
        }
        return nil
    }
}

public enum ConfiguredEnvironmentDefault: Equatable, Sendable {
    case disabled
    case environmentID(String)
}

public struct ConfiguredEnvironmentSnapshot: Equatable, Sendable {
    public let environments: [ConfiguredEnvironmentEntry]
    public let defaultEnvironment: ConfiguredEnvironmentDefault

    public init(
        environments: [ConfiguredEnvironmentEntry],
        defaultEnvironment: ConfiguredEnvironmentDefault
    ) {
        self.environments = environments
        self.defaultEnvironment = defaultEnvironment
    }

    public func environment(id: String) -> ConfiguredEnvironmentEntry? {
        environments.first { $0.id == id }
    }

    public func defaultEnvironmentIDs() -> [String] {
        guard case let .environmentID(defaultID) = defaultEnvironment else {
            return []
        }

        var ids = [defaultID]
        ids.append(contentsOf: environments.map(\.id).filter { $0 != defaultID })
        return ids
    }

    public func defaultThreadEnvironmentSelections(cwd: String) -> [TurnEnvironmentSelection] {
        defaultEnvironmentIDs().map { TurnEnvironmentSelection(environmentID: $0, cwd: cwd) }
    }

    public func environmentContextEnvironments(cwd: String, shell: Shell) -> [EnvironmentContextEnvironment] {
        defaultThreadEnvironmentSelections(cwd: cwd).map { selection in
            EnvironmentContextEnvironment(
                id: selection.environmentID,
                cwd: selection.cwd,
                shell: shell.name
            )
        }
    }
}

public enum ConfiguredEnvironmentLoader {
    public static let environmentsFilename = "environments.toml"
    public static let codexExecServerURLEnvironmentVariable = "CODEX_EXEC_SERVER_URL"
    public static let localEnvironmentID = "local"
    public static let remoteEnvironmentID = "remote"
    public static let maxEnvironmentIDLength = 64

    public static func load(
        codexHome: URL,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) throws -> ConfiguredEnvironmentSnapshot {
        let configFile = codexHome.appendingPathComponent(environmentsFilename, isDirectory: false)
        guard try environmentConfigExists(configFile, fileManager: fileManager) else {
            return legacyEnvironmentSnapshot(environment: environment)
        }

        let contents: String
        do {
            contents = try String(contentsOf: configFile, encoding: .utf8)
        } catch {
            throw ConfiguredEnvironmentLoadError.protocolError(
                "failed to read environment config `\(configFile.path)`: \(error)"
            )
        }

        let config: EnvironmentsToml
        do {
            config = try parseEnvironmentsToml(contents)
        } catch let error as ConfiguredEnvironmentLoadError {
            throw ConfiguredEnvironmentLoadError.protocolError(
                "failed to parse environment config `\(configFile.path)`: \(error.message)"
            )
        }

        return try snapshot(
            from: config,
            configDirectory: codexHome
        )
    }

    public static func legacyEnvironmentSnapshot(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> ConfiguredEnvironmentSnapshot {
        var entries = [
            ConfiguredEnvironmentEntry(id: localEnvironmentID, transport: .local)
        ]
        let normalized = normalizeExecServerURL(environment[codexExecServerURLEnvironmentVariable])
        if let url = normalized.url {
            entries.append(ConfiguredEnvironmentEntry(id: remoteEnvironmentID, transport: .websocketURL(url)))
        }

        let defaultEnvironment: ConfiguredEnvironmentDefault
        if normalized.disabled {
            defaultEnvironment = .disabled
        } else if normalized.url != nil {
            defaultEnvironment = .environmentID(remoteEnvironmentID)
        } else {
            defaultEnvironment = .environmentID(localEnvironmentID)
        }

        return ConfiguredEnvironmentSnapshot(
            environments: entries,
            defaultEnvironment: defaultEnvironment
        )
    }

    public static func snapshot(
        fromToml contents: String,
        configDirectory: URL? = nil
    ) throws -> ConfiguredEnvironmentSnapshot {
        try snapshot(
            from: parseEnvironmentsToml(contents),
            configDirectory: configDirectory
        )
    }

    public static func defaultThreadEnvironmentSelections(
        codexHome: URL,
        cwd: String,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) throws -> [TurnEnvironmentSelection] {
        try load(
            codexHome: codexHome,
            environment: environment,
            fileManager: fileManager
        ).defaultThreadEnvironmentSelections(cwd: cwd)
    }
}

private struct EnvironmentsToml {
    var defaultID: String?
    var environments: [EnvironmentToml]
}

private struct EnvironmentToml {
    var id = ""
    var url: String?
    var program: String?
    var args: [String]?
    var env: [String: String]?
    var cwd: String?
    var seenFields = Set<String>()
    var envKeys = Set<String>()

    mutating func recordField(_ key: String) throws {
        guard seenFields.insert(key).inserted else {
            throw ConfiguredEnvironmentLoadError.protocolError("duplicate key `\(key)`")
        }
    }

    mutating func openEnvTable() throws {
        try recordField("env")
        env = env ?? [:]
    }

    mutating func recordEnvValue(key: String, value: String) throws {
        guard envKeys.insert(key).inserted else {
            throw ConfiguredEnvironmentLoadError.protocolError("duplicate key `\(key)`")
        }
        var env = env ?? [:]
        env[key] = value
        self.env = env
    }
}

private extension ConfiguredEnvironmentLoader {
    enum Section {
        case topLevel
        case environment
        case environmentEnv
    }

    static func snapshot(
        from config: EnvironmentsToml,
        configDirectory: URL?
    ) throws -> ConfiguredEnvironmentSnapshot {
        var ids = Set([localEnvironmentID])
        var entries = [
            ConfiguredEnvironmentEntry(id: localEnvironmentID, transport: .local)
        ]

        for environment in config.environments {
            let entry = try parseEnvironment(environment, configDirectory: configDirectory)
            guard ids.insert(entry.id).inserted else {
                throw ConfiguredEnvironmentLoadError.protocolError(
                    "environment id `\(entry.id)` is duplicated"
                )
            }
            entries.append(entry)
        }

        return ConfiguredEnvironmentSnapshot(
            environments: entries,
            defaultEnvironment: try normalizeDefaultEnvironmentID(config.defaultID, ids: ids)
        )
    }

    static func parseEnvironment(
        _ environment: EnvironmentToml,
        configDirectory: URL?
    ) throws -> ConfiguredEnvironmentEntry {
        try validateEnvironmentID(environment.id)
        if environment.program == nil,
           environment.args != nil || environment.env != nil || environment.cwd != nil {
            throw ConfiguredEnvironmentLoadError.protocolError(
                "environment `\(environment.id)` args, env, and cwd require program"
            )
        }

        let transport: ConfiguredEnvironmentTransport
        switch (environment.url, environment.program) {
        case let (url?, nil):
            transport = .websocketURL(try validateWebsocketURL(url))

        case let (nil, program?):
            let trimmedProgram = program.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedProgram.isEmpty else {
                throw ConfiguredEnvironmentLoadError.protocolError(
                    "environment `\(environment.id)` program cannot be empty"
                )
            }

            transport = .stdio(StdioConfiguredEnvironmentCommand(
                program: trimmedProgram,
                args: environment.args ?? [],
                env: environment.env ?? [:],
                cwd: try normalizeStdioCwd(
                    environment.cwd,
                    id: environment.id,
                    configDirectory: configDirectory
                )
            ))

        case (nil, nil), (.some, .some):
            throw ConfiguredEnvironmentLoadError.protocolError(
                "environment `\(environment.id)` must set exactly one of url or program"
            )
        }

        return ConfiguredEnvironmentEntry(id: environment.id, transport: transport)
    }

    static func parseEnvironmentsToml(_ contents: String) throws -> EnvironmentsToml {
        var defaultID: String?
        var environments: [EnvironmentToml] = []
        var currentEnvironment: EnvironmentToml?
        var seenTopLevelKeys = Set<String>()
        var section = Section.topLevel

        func finishCurrentEnvironment() {
            if let currentEnvironment {
                environments.append(currentEnvironment)
            }
            currentEnvironment = nil
        }

        for rawLine in contents.split(whereSeparator: \.isNewline) {
            let line = stripComment(from: String(rawLine)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            if line == "[[environments]]" {
                finishCurrentEnvironment()
                currentEnvironment = EnvironmentToml()
                section = .environment
                continue
            }

            if line == "[environments.env]" {
                guard currentEnvironment != nil else {
                    throw ConfiguredEnvironmentLoadError.protocolError("environment env table requires environment")
                }
                try currentEnvironment!.openEnvTable()
                section = .environmentEnv
                continue
            }

            if line.hasPrefix("[") {
                throw ConfiguredEnvironmentLoadError.protocolError("unknown field `\(tableName(fromHeader: line))`")
            }

            guard let equalsIndex = line.firstIndex(of: "=") else {
                throw ConfiguredEnvironmentLoadError.protocolError("invalid TOML line: \(line)")
            }

            let key = String(line[..<equalsIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            let valueStart = line.index(after: equalsIndex)
            let valueText = String(line[valueStart...]).trimmingCharacters(in: .whitespacesAndNewlines)

            switch section {
            case .topLevel:
                guard key == "default" else {
                    throw ConfiguredEnvironmentLoadError.protocolError("unknown field `\(key)`")
                }
                guard seenTopLevelKeys.insert(key).inserted else {
                    throw ConfiguredEnvironmentLoadError.protocolError("duplicate key `\(key)`")
                }
                defaultID = try stringValue(valueText, key: key)

            case .environment:
                guard currentEnvironment != nil else {
                    throw ConfiguredEnvironmentLoadError.protocolError("environment field outside environment table")
                }
                try applyEnvironmentField(key: key, valueText: valueText, to: &currentEnvironment!)

            case .environmentEnv:
                guard currentEnvironment != nil else {
                    throw ConfiguredEnvironmentLoadError.protocolError("environment env field outside environment table")
                }
                try currentEnvironment!.recordEnvValue(
                    key: key,
                    value: try stringValue(valueText, key: key)
                )
            }
        }

        finishCurrentEnvironment()
        return EnvironmentsToml(defaultID: defaultID, environments: environments)
    }

    static func environmentConfigExists(
        _ configFile: URL,
        fileManager: FileManager
    ) throws -> Bool {
        do {
            _ = try fileManager.attributesOfItem(atPath: configFile.path)
            return true
        } catch let error as NSError {
            if error.isMissingFile {
                return false
            }
            throw ConfiguredEnvironmentLoadError.protocolError(
                "failed to inspect environment config `\(configFile.path)`: \(error)"
            )
        }
    }

    static func applyEnvironmentField(
        key: String,
        valueText: String,
        to environment: inout EnvironmentToml
    ) throws {
        try environment.recordField(key)
        switch key {
        case "id":
            environment.id = try stringValue(valueText, key: key)
        case "url":
            environment.url = try stringValue(valueText, key: key)
        case "program":
            environment.program = try stringValue(valueText, key: key)
        case "args":
            environment.args = try stringArrayValue(valueText, key: key)
        case "env":
            environment.env = try stringStringTableValue(valueText, key: key)
        case "cwd":
            environment.cwd = try stringValue(valueText, key: key)
        default:
            throw ConfiguredEnvironmentLoadError.protocolError("unknown field `\(key)`")
        }
    }

    static func validateEnvironmentID(_ id: String) throws {
        let trimmedID = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedID.isEmpty else {
            throw ConfiguredEnvironmentLoadError.protocolError("environment id cannot be empty")
        }
        guard trimmedID == id else {
            throw ConfiguredEnvironmentLoadError.protocolError(
                "environment id `\(id)` must not contain surrounding whitespace"
            )
        }
        guard id != localEnvironmentID, !id.caseInsensitiveCompare("none").isOrderedSame else {
            throw ConfiguredEnvironmentLoadError.protocolError("environment id `\(id)` is reserved")
        }
        guard id.count <= maxEnvironmentIDLength else {
            throw ConfiguredEnvironmentLoadError.protocolError(
                "environment id `\(id)` cannot be longer than \(maxEnvironmentIDLength) characters"
            )
        }
        guard id.unicodeScalars.allSatisfy({ scalar in
            scalar.isASCII
                && (CharacterSet.alphanumerics.contains(scalar)
                    || scalar == "-"
                    || scalar == "_")
        }) else {
            throw ConfiguredEnvironmentLoadError.protocolError(
                "environment id `\(id)` must contain only ASCII letters, numbers, '-' or '_'"
            )
        }
    }

    static func normalizeDefaultEnvironmentID(
        _ defaultID: String?,
        ids: Set<String>
    ) throws -> ConfiguredEnvironmentDefault {
        guard let defaultID = defaultID?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return .environmentID(localEnvironmentID)
        }
        guard !defaultID.isEmpty else {
            throw ConfiguredEnvironmentLoadError.protocolError("default environment id cannot be empty")
        }
        if defaultID.caseInsensitiveCompare("none").isOrderedSame {
            return .disabled
        }
        guard ids.contains(defaultID) else {
            throw ConfiguredEnvironmentLoadError.protocolError(
                "default environment `\(defaultID)` is not configured"
            )
        }
        return .environmentID(defaultID)
    }

    static func validateWebsocketURL(_ rawURL: String) throws -> String {
        let url = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else {
            throw ConfiguredEnvironmentLoadError.protocolError("environment url cannot be empty")
        }
        guard url.hasPrefix("ws://") || url.hasPrefix("wss://") else {
            throw ConfiguredEnvironmentLoadError.protocolError(
                "environment url `\(url)` must use ws:// or wss://"
            )
        }
        guard let components = URLComponents(string: url),
              (components.scheme == "ws" || components.scheme == "wss"),
              components.host?.isEmpty == false,
              components.port.map({ (0...65_535).contains($0) }) ?? true
        else {
            throw ConfiguredEnvironmentLoadError.protocolError("environment url `\(url)` is invalid")
        }
        return url
    }

    static func normalizeStdioCwd(
        _ rawCwd: String?,
        id: String,
        configDirectory: URL?
    ) throws -> String? {
        guard let rawCwd else {
            return nil
        }
        let cwd = URL(fileURLWithPath: rawCwd, isDirectory: true)
        if cwd.path == rawCwd, rawCwd.hasPrefix("/") {
            return rawCwd
        }
        guard let configDirectory else {
            throw ConfiguredEnvironmentLoadError.protocolError("environment `\(id)` cwd must be absolute")
        }
        return configDirectory.appendingPathComponent(rawCwd, isDirectory: true).standardizedFileURL.path
    }

    static func normalizeExecServerURL(_ rawValue: String?) -> (url: String?, disabled: Bool) {
        guard let value = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty
        else {
            return (nil, false)
        }
        if value.caseInsensitiveCompare("none").isOrderedSame {
            return (nil, true)
        }
        return (value, false)
    }

    static func stringValue(_ valueText: String, key: String) throws -> String {
        guard case let .string(value) = try ConfigValueParser.parseTomlLiteral(valueText) else {
            throw ConfiguredEnvironmentLoadError.protocolError("invalid value for `\(key)`: expected string")
        }
        return value
    }

    static func stringArrayValue(_ valueText: String, key: String) throws -> [String] {
        guard case let .array(values) = try ConfigValueParser.parseTomlLiteral(valueText) else {
            throw ConfiguredEnvironmentLoadError.protocolError("invalid value for `\(key)`: expected string array")
        }
        return try values.map { value in
            guard case let .string(string) = value else {
                throw ConfiguredEnvironmentLoadError.protocolError("invalid value for `\(key)`: expected string array")
            }
            return string
        }
    }

    static func stringStringTableValue(_ valueText: String, key: String) throws -> [String: String] {
        guard case let .table(values) = try ConfigValueParser.parseTomlLiteral(valueText) else {
            throw ConfiguredEnvironmentLoadError.protocolError("invalid value for `\(key)`: expected string table")
        }
        return try values.mapValues { value in
            guard case let .string(string) = value else {
                throw ConfiguredEnvironmentLoadError.protocolError("invalid value for `\(key)`: expected string table")
            }
            return string
        }
    }

    static func stripComment(from raw: String) -> String {
        var quote: Character?
        var previousWasBackslash = false
        for (index, character) in raw.enumerated() {
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
            if character == "\"" || character == "'" {
                quote = character
                continue
            }
            if character == "#" {
                return String(raw.prefix(index))
            }
        }
        return raw
    }

    static func tableName(fromHeader header: String) -> String {
        header
            .trimmingCharacters(in: CharacterSet(charactersIn: "[]").union(.whitespacesAndNewlines))
    }
}

private extension ConfiguredEnvironmentLoadError {
    var message: String {
        switch self {
        case let .protocolError(message):
            return message
        }
    }
}

private extension ComparisonResult {
    var isOrderedSame: Bool {
        self == .orderedSame
    }
}

private extension NSError {
    var isMissingFile: Bool {
        if domain == NSCocoaErrorDomain, code == NSFileReadNoSuchFileError {
            return true
        }
        let underlying = userInfo[NSUnderlyingErrorKey] as? NSError
        return underlying.map { $0.domain == NSPOSIXErrorDomain && $0.code == ENOENT } ?? false
    }
}
