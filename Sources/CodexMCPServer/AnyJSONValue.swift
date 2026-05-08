import Foundation

public indirect enum AnyJSONValue: Equatable, Sendable {
    case null
    case bool(Bool)
    case integer(Int64)
    case double(Double)
    case string(String)
    case array([AnyJSONValue])
    case object([String: AnyJSONValue])

    public static func fromJSONObject(_ value: Any) -> AnyJSONValue {
        switch value {
        case is NSNull:
            return .null
        case let value as Bool:
            return .bool(value)
        case let value as Int:
            return .integer(Int64(value))
        case let value as Int64:
            return .integer(value)
        case let value as Double:
            return .double(value)
        case let value as String:
            return .string(value)
        case let value as [Any]:
            return .array(value.map(fromJSONObject))
        case let value as [String: Any]:
            return .object(value.mapValues(fromJSONObject))
        default:
            return .string(String(describing: value))
        }
    }

    public var jsonObject: Any {
        switch self {
        case .null:
            return NSNull()
        case let .bool(value):
            return value
        case let .integer(value):
            return value
        case let .double(value):
            return value
        case let .string(value):
            return value
        case let .array(value):
            return value.map(\.jsonObject)
        case let .object(value):
            return value.mapValues(\.jsonObject)
        }
    }
}

