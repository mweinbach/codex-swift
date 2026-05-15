import Foundation

extension AppServerProtocol {
    public struct ConfigReadParams: Codable, Equatable, Sendable {
        public let includeLayers: Bool
        public let cwd: String?

        private enum CodingKeys: String, CodingKey {
            case includeLayers
            case cwd
        }

        public init(includeLayers: Bool = false, cwd: String? = nil) {
            self.includeLayers = includeLayers
            self.cwd = cwd
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(includeLayers, forKey: .includeLayers)
            try container.encodeNilOrValue(cwd, forKey: .cwd)
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            includeLayers = try container.decodeIfPresent(Bool.self, forKey: .includeLayers) ?? false
            cwd = try container.decodeIfPresent(String.self, forKey: .cwd)
        }
    }

    public struct ConfigReadResponse: Codable, Equatable, Sendable {
        public let config: JSONValue
        public let origins: [String: ConfigLayerMetadata]
        public let layers: [ConfigLayer]?

        private enum CodingKeys: String, CodingKey {
            case config
            case origins
            case layers
        }

        public init(config: JSONValue, origins: [String: ConfigLayerMetadata], layers: [ConfigLayer]? = nil) {
            self.config = config
            self.origins = origins
            self.layers = layers
        }
    }

    public struct ConfigLayer: Codable, Equatable, Sendable {
        public let name: ConfigLayerSource
        public let version: String
        public let config: JSONValue
        public let disabledReason: String?

        private enum CodingKeys: String, CodingKey {
            case name
            case version
            case config
            case disabledReason
        }

        public init(name: ConfigLayerSource, version: String, config: JSONValue, disabledReason: String? = nil) {
            self.name = name
            self.version = version
            self.config = config
            self.disabledReason = disabledReason
        }
    }

    public struct ConfigRequirementsReadResponse: Codable, Equatable, Sendable {
        public let requirements: JSONValue?

        private enum CodingKeys: String, CodingKey {
            case requirements
        }

        public init(requirements: JSONValue?) {
            self.requirements = requirements
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encodeNilOrValue(requirements, forKey: .requirements)
        }
    }

    public enum ConfigMergeStrategy: String, Codable, Equatable, Sendable {
        case replace
        case upsert
    }

    public enum ConfigWriteStatus: String, Codable, Equatable, Sendable {
        case ok
        case okOverridden
    }

    public enum ConfigWriteErrorCode: String, Codable, Equatable, Sendable {
        case configLayerReadonly
        case configVersionConflict
        case configValidationError
        case configPathNotFound
        case configSchemaUnknownKey
        case userLayerNotFound
    }

    public struct OverriddenConfigMetadata: Codable, Equatable, Sendable {
        public let message: String
        public let overridingLayer: ConfigLayerMetadata
        public let effectiveValue: JSONValue

        public init(message: String, overridingLayer: ConfigLayerMetadata, effectiveValue: JSONValue) {
            self.message = message
            self.overridingLayer = overridingLayer
            self.effectiveValue = effectiveValue
        }
    }

    public struct ConfigWriteResponse: Codable, Equatable, Sendable {
        public let status: ConfigWriteStatus
        public let version: String
        public let filePath: AbsolutePath
        public let overriddenMetadata: OverriddenConfigMetadata?

        private enum CodingKeys: String, CodingKey {
            case status
            case version
            case filePath
            case overriddenMetadata
        }

        public init(
            status: ConfigWriteStatus,
            version: String,
            filePath: AbsolutePath,
            overriddenMetadata: OverriddenConfigMetadata? = nil
        ) {
            self.status = status
            self.version = version
            self.filePath = filePath
            self.overriddenMetadata = overriddenMetadata
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(status, forKey: .status)
            try container.encode(version, forKey: .version)
            try container.encode(filePath, forKey: .filePath)
            try container.encodeNilOrValue(overriddenMetadata, forKey: .overriddenMetadata)
        }
    }

    public struct ConfigValueWriteParams: Codable, Equatable, Sendable {
        public let keyPath: String
        public let value: JSONValue
        public let mergeStrategy: ConfigMergeStrategy
        public let filePath: String?
        public let expectedVersion: String?

        private enum CodingKeys: String, CodingKey {
            case keyPath
            case value
            case mergeStrategy
            case filePath
            case expectedVersion
        }

        public init(
            keyPath: String,
            value: JSONValue,
            mergeStrategy: ConfigMergeStrategy,
            filePath: String? = nil,
            expectedVersion: String? = nil
        ) {
            self.keyPath = keyPath
            self.value = value
            self.mergeStrategy = mergeStrategy
            self.filePath = filePath
            self.expectedVersion = expectedVersion
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(keyPath, forKey: .keyPath)
            try container.encode(value, forKey: .value)
            try container.encode(mergeStrategy, forKey: .mergeStrategy)
            try container.encodeNilOrValue(filePath, forKey: .filePath)
            try container.encodeNilOrValue(expectedVersion, forKey: .expectedVersion)
        }
    }

    public struct ConfigBatchWriteParams: Codable, Equatable, Sendable {
        public let edits: [ConfigEdit]
        public let filePath: String?
        public let expectedVersion: String?
        public let reloadUserConfig: Bool

        private enum CodingKeys: String, CodingKey {
            case edits
            case filePath
            case expectedVersion
            case reloadUserConfig
        }

        public init(
            edits: [ConfigEdit],
            filePath: String? = nil,
            expectedVersion: String? = nil,
            reloadUserConfig: Bool = false
        ) {
            self.edits = edits
            self.filePath = filePath
            self.expectedVersion = expectedVersion
            self.reloadUserConfig = reloadUserConfig
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(edits, forKey: .edits)
            try container.encodeNilOrValue(filePath, forKey: .filePath)
            try container.encodeNilOrValue(expectedVersion, forKey: .expectedVersion)
            if reloadUserConfig {
                try container.encode(reloadUserConfig, forKey: .reloadUserConfig)
            }
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            edits = try container.decode([ConfigEdit].self, forKey: .edits)
            filePath = try container.decodeIfPresent(String.self, forKey: .filePath)
            expectedVersion = try container.decodeIfPresent(String.self, forKey: .expectedVersion)
            reloadUserConfig = try container.contains(.reloadUserConfig)
                ? container.decode(Bool.self, forKey: .reloadUserConfig)
                : false
        }
    }

    public struct ConfigEdit: Codable, Equatable, Sendable {
        public let keyPath: String
        public let value: JSONValue
        public let mergeStrategy: ConfigMergeStrategy

        public init(keyPath: String, value: JSONValue, mergeStrategy: ConfigMergeStrategy) {
            self.keyPath = keyPath
            self.value = value
            self.mergeStrategy = mergeStrategy
        }
    }
}

private extension KeyedEncodingContainer {
    mutating func encodeNilOrValue<Value: Encodable>(_ value: Value?, forKey key: Key) throws {
        if let value {
            try encode(value, forKey: key)
        } else {
            try encodeNil(forKey: key)
        }
    }
}
