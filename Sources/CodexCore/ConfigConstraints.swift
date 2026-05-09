import Foundation

public enum ConstraintError: Error, Equatable, CustomStringConvertible, Sendable {
    case invalidValue(candidate: String, allowed: String)
    case emptyField(fieldName: String)
    case invalidRequirementsExecPolicy(reason: String)

    public static func invalidValue(_ candidate: some StringProtocol, _ allowed: some StringProtocol) -> ConstraintError {
        .invalidValue(candidate: String(candidate), allowed: String(allowed))
    }

    public static func emptyField(_ fieldName: some StringProtocol) -> ConstraintError {
        .emptyField(fieldName: String(fieldName))
    }

    public var description: String {
        switch self {
        case let .invalidValue(candidate, allowed):
            return "value `\(candidate)` is not in the allowed set \(allowed)"
        case let .emptyField(fieldName):
            return "field `\(fieldName)` cannot be empty"
        case let .invalidRequirementsExecPolicy(reason):
            return "invalid rules in requirements: \(reason)"
        }
    }
}

public typealias ConstraintResult<T> = Result<T, ConstraintError>

public protocol DefaultValue {
    static var defaultValue: Self { get }
}

extension Int: DefaultValue {
    public static var defaultValue: Int { 0 }
}

extension AskForApproval: DefaultValue {
    public static var defaultValue: AskForApproval { .unlessTrusted }
}

public struct Constrained<T: Sendable>: Sendable {
    public private(set) var value: T

    private let validator: @Sendable (T) -> ConstraintResult<Void>

    public init(
        _ initialValue: T,
        validator: @escaping @Sendable (T) -> ConstraintResult<Void>
    ) throws {
        switch validator(initialValue) {
        case .success:
            self.value = initialValue
            self.validator = validator
        case let .failure(error):
            throw error
        }
    }

    public static func allowAny(_ initialValue: T) -> Constrained<T> {
        Constrained<T>(unchecked: initialValue) { _ in .success(()) }
    }

    public static func allowAnyFromDefault() -> Constrained<T> where T: DefaultValue {
        .allowAny(T.defaultValue)
    }

    public static func allowOnly(
        _ allowedValue: T,
        debugDescription: @escaping @Sendable (T) -> String = { String(describing: $0) }
    ) -> Constrained<T> where T: Equatable {
        Constrained<T>(unchecked: allowedValue) { candidate in
            if candidate == allowedValue {
                return .success(())
            }
            return .failure(.invalidValue(debugDescription(candidate), debugDescription(allowedValue)))
        }
    }

    public static func allowValues(
        _ initialValue: T,
        allowed: [T],
        debugDescription: @escaping @Sendable (T) -> String = { String(describing: $0) }
    ) throws -> Constrained<T> where T: Equatable {
        try Constrained<T>(initialValue) { candidate in
            if allowed.contains(candidate) {
                return .success(())
            }
            let allowedDescription = "[" + allowed.map(debugDescription).joined(separator: ", ") + "]"
            return .failure(.invalidValue(debugDescription(candidate), allowedDescription))
        }
    }

    public func get() -> T {
        value
    }

    public func canSet(_ candidate: T) -> ConstraintResult<Void> {
        validator(candidate)
    }

    public mutating func set(_ newValue: T) throws {
        switch validator(newValue) {
        case .success:
            value = newValue
        case let .failure(error):
            throw error
        }
    }

    private init(
        unchecked value: T,
        validator: @escaping @Sendable (T) -> ConstraintResult<Void>
    ) {
        self.value = value
        self.validator = validator
    }
}

extension Constrained: Equatable where T: Equatable {
    public static func == (lhs: Constrained<T>, rhs: Constrained<T>) -> Bool {
        lhs.value == rhs.value
    }
}

extension Constrained: CustomDebugStringConvertible where T: CustomDebugStringConvertible {
    public var debugDescription: String {
        "Constrained(value: \(value.debugDescription))"
    }
}
