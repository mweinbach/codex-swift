import Foundation

public enum JSONToToml {
    /// Port of codex-rs/utils/json-to-toml/src/lib.rs.
    public static func convert(_ value: JSONValue) -> ConfigValue {
        switch value {
        case .null:
            return .string("")
        case let .bool(value):
            return .bool(value)
        case let .integer(value):
            return .integer(value)
        case let .double(value):
            return .double(value)
        case let .string(value):
            return .string(value)
        case let .array(values):
            return .array(values.map(convert))
        case let .object(values):
            return .table(values.mapValues(convert))
        }
    }
}
