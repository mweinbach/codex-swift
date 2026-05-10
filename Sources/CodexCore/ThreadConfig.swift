import Foundation

public struct ThreadConfigContext: Equatable, Sendable {
    public var threadID: String?
    public var cwd: AbsolutePath?

    public init(threadID: String? = nil, cwd: AbsolutePath? = nil) {
        self.threadID = threadID
        self.cwd = cwd
    }
}

public struct SessionThreadConfig: Equatable, Sendable {
    public var modelProvider: String?
    public var modelProviders: [String: ModelProviderInfo]
    public var features: [String: Bool]

    public init(
        modelProvider: String? = nil,
        modelProviders: [String: ModelProviderInfo] = [:],
        features: [String: Bool] = [:]
    ) {
        self.modelProvider = modelProvider
        self.modelProviders = modelProviders
        self.features = features
    }
}

public struct UserThreadConfig: Equatable, Sendable {
    public init() {}
}

public enum ThreadConfigSource: Equatable, Sendable {
    case session(SessionThreadConfig)
    case user(UserThreadConfig)

    public func configLayerEntry() throws -> ConfigLayerEntry? {
        switch self {
        case let .session(config):
            let value = try config.configValue()
            guard !value.isEmptyTable else {
                return nil
            }
            return ConfigLayerEntry(name: .sessionFlags, config: value)
        case .user:
            return nil
        }
    }
}

private extension SessionThreadConfig {
    func configValue() throws -> ConfigValue {
        var table: [String: ConfigValue] = [:]

        if let modelProvider {
            table["model_provider"] = .string(modelProvider)
        }

        if !modelProviders.isEmpty {
            table["model_providers"] = try .table(modelProviders.mapValues(configValue))
        }

        if !features.isEmpty {
            table["features"] = .table(
                Dictionary(uniqueKeysWithValues: features.map { key, value in
                    (key, ConfigValue.bool(value))
                })
            )
        }

        return .table(table)
    }

    func configValue(for provider: ModelProviderInfo) throws -> ConfigValue {
        let data = try JSONEncoder().encode(provider)
        return try JSONDecoder().decode(ConfigValue.self, from: data)
            .removingNoneValues()
            .removingModelProviderThreadConfigDefaults()
    }
}

private extension ConfigValue {
    var isEmptyTable: Bool {
        guard case let .table(table) = self else {
            return false
        }
        return table.isEmpty
    }

    func removingNoneValues() -> ConfigValue {
        switch self {
        case .none:
            return .none
        case let .array(values):
            return .array(values.map { $0.removingNoneValues() })
        case let .table(table):
            return .table(table.compactMapValues { value in
                let normalized = value.removingNoneValues()
                if case .none = normalized {
                    return nil
                }
                return normalized
            })
        default:
            return self
        }
    }

    func removingModelProviderThreadConfigDefaults() -> ConfigValue {
        guard case var .table(table) = self else {
            return self
        }
        if case let .bool(value)? = table["supports_websockets"], value == false {
            table.removeValue(forKey: "supports_websockets")
        }
        return .table(table)
    }
}
