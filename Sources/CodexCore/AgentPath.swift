import Foundation

public struct AgentPath: RawRepresentable, Codable, Comparable, Hashable, Sendable, CustomStringConvertible {
    public static let rootValue = "/root"
    public static let morpheusValue = "/morpheus"

    private static let rootSegment = "root"

    public let rawValue: String

    public static var root: AgentPath {
        AgentPath(unchecked: rootValue)
    }

    public static var morpheus: AgentPath {
        AgentPath(unchecked: morpheusValue)
    }

    public init(rawValue: String) {
        do {
            self = try AgentPath(validating: rawValue)
        } catch {
            preconditionFailure(String(describing: error))
        }
    }

    public init(validating rawValue: String) throws {
        try Self.validateAbsolutePath(rawValue)
        self.rawValue = rawValue
    }

    private init(unchecked rawValue: String) {
        self.rawValue = rawValue
    }

    public var description: String {
        rawValue
    }

    public var isRoot: Bool {
        rawValue == Self.rootValue
    }

    public var name: String {
        if isRoot {
            return Self.rootSegment
        }
        return rawValue.split(separator: "/").last.map(String.init) ?? Self.rootSegment
    }

    public func join(_ agentName: String) throws -> AgentPath {
        try Self.validateAgentName(agentName)
        return try AgentPath(validating: "\(rawValue)/\(agentName)")
    }

    public func resolve(_ reference: String) throws -> AgentPath {
        if reference.isEmpty {
            throw AgentPathError("agent path must not be empty")
        }
        if reference == Self.rootValue {
            return .root
        }
        if reference.hasPrefix("/") {
            return try AgentPath(validating: reference)
        }

        try Self.validateRelativeReference(reference)
        return try AgentPath(validating: "\(rawValue)/\(reference)")
    }

    public static func < (lhs: AgentPath, rhs: AgentPath) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        do {
            self = try AgentPath(validating: value)
        } catch {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: String(describing: error)
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    private static func validateAgentName(_ agentName: String) throws {
        if agentName.isEmpty {
            throw AgentPathError("agent_name must not be empty")
        }
        if agentName == rootSegment {
            throw AgentPathError("agent_name `root` is reserved")
        }
        if agentName == "." || agentName == ".." {
            throw AgentPathError("agent_name `\(agentName)` is reserved")
        }
        if agentName.contains("/") {
            throw AgentPathError("agent_name must not contain `/`")
        }
        let allowed = agentName.unicodeScalars.allSatisfy { scalar in
            scalar.value >= UnicodeScalar("a").value && scalar.value <= UnicodeScalar("z").value
                || scalar.value >= UnicodeScalar("0").value && scalar.value <= UnicodeScalar("9").value
                || scalar == "_"
        }
        if !allowed {
            throw AgentPathError("agent_name must use only lowercase letters, digits, and underscores")
        }
    }

    private static func validateAbsolutePath(_ path: String) throws {
        if path == morpheusValue {
            return
        }
        guard path.hasPrefix("/") else {
            throw AgentPathError("absolute agent paths must start with `/root` or be `/morpheus`")
        }

        let stripped = String(path.dropFirst())
        let segments = stripped.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard let root = segments.first else {
            throw AgentPathError("absolute agent path must not be empty")
        }
        if root != rootSegment {
            throw AgentPathError("absolute agent paths must start with `/root` or be `/morpheus`")
        }
        if stripped.hasSuffix("/") {
            throw AgentPathError("absolute agent path must not end with `/`")
        }
        for segment in segments.dropFirst() {
            try validateAgentName(segment)
        }
    }

    private static func validateRelativeReference(_ reference: String) throws {
        if reference.hasSuffix("/") {
            throw AgentPathError("relative agent path must not end with `/`")
        }
        for segment in reference.split(separator: "/", omittingEmptySubsequences: false) {
            try validateAgentName(String(segment))
        }
    }
}

public struct AgentPathError: Error, Equatable, CustomStringConvertible, Sendable {
    public let description: String

    public init(_ description: String) {
        self.description = description
    }
}
