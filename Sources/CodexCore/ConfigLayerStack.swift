import CryptoKit
import Foundation

public enum ConfigLayerError: Error, Equatable, CustomStringConvertible, Sendable {
    case invalidLayerOrder
    case multipleUserConfigLayers
    case projectLayerHasNoParentDirectory
    case projectLayersNotOrderedFromRootToCwd

    public var description: String {
        switch self {
        case .invalidLayerOrder:
            return "config layers are not in correct precedence order"
        case .multipleUserConfigLayers:
            return "multiple user config layers found"
        case .projectLayerHasNoParentDirectory:
            return "project layer has no parent directory"
        case .projectLayersNotOrderedFromRootToCwd:
            return "project layers are not ordered from root to cwd"
        }
    }
}

public enum ConfigLayerSource: Equatable, Hashable, Sendable {
    case mdm(domain: String, key: String)
    case system(file: AbsolutePath)
    case user(file: AbsolutePath)
    case project(dotCodexFolder: AbsolutePath)
    case sessionFlags
    case legacyManagedConfigTomlFromFile(file: AbsolutePath)
    case legacyManagedConfigTomlFromMdm

    public var precedence: Int {
        switch self {
        case .mdm:
            return 0
        case .system:
            return 10
        case .user:
            return 20
        case .project:
            return 25
        case .sessionFlags:
            return 30
        case .legacyManagedConfigTomlFromFile:
            return 40
        case .legacyManagedConfigTomlFromMdm:
            return 50
        }
    }
}

extension ConfigLayerSource: Comparable {
    public static func < (lhs: ConfigLayerSource, rhs: ConfigLayerSource) -> Bool {
        lhs.precedence < rhs.precedence
    }
}

extension ConfigLayerSource: Codable {
    private enum CodingKeys: String, CodingKey {
        case type
        case domain
        case key
        case file
        case dotCodexFolder
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "mdm":
            self = try .mdm(
                domain: container.decode(String.self, forKey: .domain),
                key: container.decode(String.self, forKey: .key)
            )
        case "system":
            self = try .system(file: container.decode(AbsolutePath.self, forKey: .file))
        case "user":
            self = try .user(file: container.decode(AbsolutePath.self, forKey: .file))
        case "project":
            self = try .project(dotCodexFolder: container.decode(AbsolutePath.self, forKey: .dotCodexFolder))
        case "sessionFlags":
            self = .sessionFlags
        case "legacyManagedConfigTomlFromFile":
            self = try .legacyManagedConfigTomlFromFile(file: container.decode(AbsolutePath.self, forKey: .file))
        case "legacyManagedConfigTomlFromMdm":
            self = .legacyManagedConfigTomlFromMdm
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown config layer source type: \(type)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .mdm(domain, key):
            try container.encode("mdm", forKey: .type)
            try container.encode(domain, forKey: .domain)
            try container.encode(key, forKey: .key)
        case let .system(file):
            try container.encode("system", forKey: .type)
            try container.encode(file, forKey: .file)
        case let .user(file):
            try container.encode("user", forKey: .type)
            try container.encode(file, forKey: .file)
        case let .project(dotCodexFolder):
            try container.encode("project", forKey: .type)
            try container.encode(dotCodexFolder, forKey: .dotCodexFolder)
        case .sessionFlags:
            try container.encode("sessionFlags", forKey: .type)
        case let .legacyManagedConfigTomlFromFile(file):
            try container.encode("legacyManagedConfigTomlFromFile", forKey: .type)
            try container.encode(file, forKey: .file)
        case .legacyManagedConfigTomlFromMdm:
            try container.encode("legacyManagedConfigTomlFromMdm", forKey: .type)
        }
    }
}

public struct ConfigLayerMetadata: Equatable, Codable, Sendable {
    public var name: ConfigLayerSource
    public var version: String

    public init(name: ConfigLayerSource, version: String) {
        self.name = name
        self.version = version
    }
}

public struct ConfigLayer: Equatable, Codable, Sendable {
    public var name: ConfigLayerSource
    public var version: String
    public var config: ConfigValue

    public init(name: ConfigLayerSource, version: String, config: ConfigValue) {
        self.name = name
        self.version = version
        self.config = config
    }
}

public struct ConfigLayerEntry: Equatable, Sendable {
    public var name: ConfigLayerSource
    public var config: ConfigValue
    public var version: String

    public init(name: ConfigLayerSource, config: ConfigValue) {
        self.name = name
        self.config = config
        version = ConfigFingerprint.version(for: config)
    }

    public init(name: ConfigLayerSource, config: ConfigValue, version: String) {
        self.name = name
        self.config = config
        self.version = version
    }

    public func metadata() -> ConfigLayerMetadata {
        ConfigLayerMetadata(name: name, version: version)
    }

    public func asLayer() -> ConfigLayer {
        ConfigLayer(name: name, version: version, config: config)
    }

    public func configFolder() -> AbsolutePath? {
        switch name {
        case .mdm:
            return nil
        case let .system(file):
            return file.parent
        case let .user(file):
            return file.parent
        case let .project(dotCodexFolder):
            return dotCodexFolder
        case .sessionFlags:
            return nil
        case .legacyManagedConfigTomlFromFile:
            return nil
        case .legacyManagedConfigTomlFromMdm:
            return nil
        }
    }
}

public enum ConfigLayerStackOrdering: Equatable, Sendable {
    case lowestPrecedenceFirst
    case highestPrecedenceFirst
}

public struct ConfigLayerStack: Equatable, Sendable {
    public private(set) var layers: [ConfigLayerEntry]
    public private(set) var userLayerIndex: Int?
    public var requirements: ConfigRequirements
    public var requirementsToml: ConfigRequirementsToml
    public var ignoreUserAndProjectExecPolicyRules: Bool

    public init(
        layers: [ConfigLayerEntry],
        requirements: ConfigRequirements = .default,
        requirementsToml: ConfigRequirementsToml = ConfigRequirementsToml(),
        ignoreUserAndProjectExecPolicyRules: Bool = false
    ) throws {
        self.layers = layers
        self.userLayerIndex = try Self.verifyLayerOrdering(layers)
        self.requirements = requirements
        self.requirementsToml = requirementsToml
        self.ignoreUserAndProjectExecPolicyRules = ignoreUserAndProjectExecPolicyRules
    }

    private init(
        validatedLayers layers: [ConfigLayerEntry],
        userLayerIndex: Int?,
        requirements: ConfigRequirements,
        requirementsToml: ConfigRequirementsToml,
        ignoreUserAndProjectExecPolicyRules: Bool
    ) {
        self.layers = layers
        self.userLayerIndex = userLayerIndex
        self.requirements = requirements
        self.requirementsToml = requirementsToml
        self.ignoreUserAndProjectExecPolicyRules = ignoreUserAndProjectExecPolicyRules
    }

    public func getUserLayer() -> ConfigLayerEntry? {
        guard let userLayerIndex, layers.indices.contains(userLayerIndex) else {
            return nil
        }
        return layers[userLayerIndex]
    }

    public func withUserConfig(configToml: AbsolutePath, userConfig: ConfigValue) -> ConfigLayerStack {
        let userLayer = ConfigLayerEntry(
            name: .user(file: configToml),
            config: userConfig
        )
        var nextLayers = layers

        if let userLayerIndex {
            nextLayers[userLayerIndex] = userLayer
            return ConfigLayerStack(
                validatedLayers: nextLayers,
                userLayerIndex: userLayerIndex,
                requirements: requirements,
                requirementsToml: requirementsToml,
                ignoreUserAndProjectExecPolicyRules: ignoreUserAndProjectExecPolicyRules
            )
        }

        if let insertionIndex = nextLayers.firstIndex(where: { $0.name.precedence > userLayer.name.precedence }) {
            nextLayers.insert(userLayer, at: insertionIndex)
            return ConfigLayerStack(
                validatedLayers: nextLayers,
                userLayerIndex: insertionIndex,
                requirements: requirements,
                requirementsToml: requirementsToml,
                ignoreUserAndProjectExecPolicyRules: ignoreUserAndProjectExecPolicyRules
            )
        }

        nextLayers.append(userLayer)
        return ConfigLayerStack(
            validatedLayers: nextLayers,
            userLayerIndex: nextLayers.count - 1,
            requirements: requirements,
            requirementsToml: requirementsToml,
            ignoreUserAndProjectExecPolicyRules: ignoreUserAndProjectExecPolicyRules
        )
    }

    public func effectiveConfig() -> ConfigValue {
        var merged = ConfigValue.table([:])
        for layer in layers {
            merged.merge(overlay: layer.config)
        }
        return merged
    }

    public func origins() -> [String: ConfigLayerMetadata] {
        var origins: [String: ConfigLayerMetadata] = [:]
        var path: [String] = []

        for layer in layers {
            Self.recordOrigins(
                value: layer.config,
                metadata: layer.metadata(),
                path: &path,
                origins: &origins
            )
        }

        return origins
    }

    public func layersHighToLow() -> [ConfigLayerEntry] {
        getLayers(ordering: .highestPrecedenceFirst)
    }

    public func getLayers(ordering: ConfigLayerStackOrdering) -> [ConfigLayerEntry] {
        switch ordering {
        case .highestPrecedenceFirst:
            return layers.reversed()
        case .lowestPrecedenceFirst:
            return layers
        }
    }

    private static func verifyLayerOrdering(_ layers: [ConfigLayerEntry]) throws -> Int? {
        for index in layers.indices.dropFirst() {
            if layers[index - 1].name.precedence > layers[index].name.precedence {
                throw ConfigLayerError.invalidLayerOrder
            }
        }

        var userLayerIndex: Int?
        var previousProjectDotCodexFolder: AbsolutePath?
        for (index, layer) in layers.enumerated() {
            if case .user = layer.name {
                if userLayerIndex != nil {
                    throw ConfigLayerError.multipleUserConfigLayers
                }
                userLayerIndex = index
            }

            if case let .project(currentProjectDotCodexFolder) = layer.name {
                if let previousProjectDotCodexFolder {
                    guard let previousParent = previousProjectDotCodexFolder.parent else {
                        throw ConfigLayerError.projectLayerHasNoParentDirectory
                    }
                    if previousProjectDotCodexFolder == currentProjectDotCodexFolder
                        || !currentProjectDotCodexFolder.ancestors.contains(previousParent)
                    {
                        throw ConfigLayerError.projectLayersNotOrderedFromRootToCwd
                    }
                }
                previousProjectDotCodexFolder = currentProjectDotCodexFolder
            }
        }

        return userLayerIndex
    }

    private static func recordOrigins(
        value: ConfigValue,
        metadata: ConfigLayerMetadata,
        path: inout [String],
        origins: inout [String: ConfigLayerMetadata]
    ) {
        switch value {
        case let .table(table):
            for (key, nestedValue) in table {
                path.append(key)
                recordOrigins(value: nestedValue, metadata: metadata, path: &path, origins: &origins)
                path.removeLast()
            }
        case let .array(items):
            for (index, nestedValue) in items.enumerated() {
                path.append(String(index))
                recordOrigins(value: nestedValue, metadata: metadata, path: &path, origins: &origins)
                path.removeLast()
            }
        case .string, .integer, .double, .bool, .none:
            if !path.isEmpty {
                origins[path.joined(separator: ".")] = metadata
            }
        }
    }
}

public enum ConfigFingerprint {
    public static func version(for value: ConfigValue) -> String {
        let data = (try? canonicalJSONData(for: value)) ?? Data("null".utf8)
        let hash = SHA256.hash(data: data)
        let hex = hash
            .map { String(format: "%02x", $0) }
            .joined()
        return "sha256:\(hex)"
    }

    private static func canonicalJSONData(for value: ConfigValue) throws -> Data {
        Data(try canonicalJSONString(for: value).utf8)
    }

    private static func canonicalJSONString(for value: ConfigValue) throws -> String {
        switch value {
        case .none:
            return "null"
        case let .string(string):
            return try jsonFragment(string)
        case let .integer(integer):
            return String(integer)
        case let .double(double):
            return try jsonFragment(double)
        case let .bool(bool):
            return bool ? "true" : "false"
        case let .array(items):
            let entries = try items.map { try canonicalJSONString(for: $0) }
            return "[" + entries.joined(separator: ",") + "]"
        case let .table(table):
            let entries = try table.keys.sorted().map { key in
                let encodedKey = try jsonFragment(key)
                let encodedValue = try canonicalJSONString(for: table[key]!)
                return "\(encodedKey):\(encodedValue)"
            }
            return "{" + entries.joined(separator: ",") + "}"
        }
    }

    private static func jsonFragment<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        let data = try encoder.encode(value)
        return String(decoding: data, as: UTF8.self)
    }
}

private extension AbsolutePath {
    var ancestors: [AbsolutePath] {
        var values: [AbsolutePath] = []
        var current: AbsolutePath? = self
        while let path = current {
            values.append(path)
            current = path.parent
        }
        return values
    }
}
