import Foundation

public enum PermissionGrantScope: String, Codable, Equatable, Sendable {
    case turn
    case session
}

public struct RequestPermissionNetworkPermissions: Codable, Equatable, Sendable {
    public let enabled: Bool?

    public init(enabled: Bool? = nil) {
        self.enabled = enabled
    }
}

public struct RequestPermissionProfile: Codable, Equatable, Sendable {
    public let network: RequestPermissionNetworkPermissions?
    public let fileSystem: JSONValue?

    private enum CodingKeys: String, CodingKey {
        case network
        case fileSystem = "file_system"
    }

    public init(network: RequestPermissionNetworkPermissions? = nil, fileSystem: JSONValue? = nil) {
        self.network = network
        self.fileSystem = fileSystem
    }

    public var isEmpty: Bool {
        network == nil && fileSystem == nil
    }
}

public struct RequestPermissionsArgs: Codable, Equatable, Sendable {
    public let reason: String?
    public let permissions: RequestPermissionProfile

    public init(reason: String? = nil, permissions: RequestPermissionProfile) {
        self.reason = reason
        self.permissions = permissions
    }
}

public struct RequestPermissionsResponse: Codable, Equatable, Sendable {
    public let permissions: RequestPermissionProfile
    public let scope: PermissionGrantScope
    public let strictAutoReview: Bool

    private enum CodingKeys: String, CodingKey {
        case permissions
        case scope
        case strictAutoReview = "strict_auto_review"
    }

    public init(
        permissions: RequestPermissionProfile,
        scope: PermissionGrantScope = .turn,
        strictAutoReview: Bool = false
    ) {
        self.permissions = permissions
        self.scope = scope
        self.strictAutoReview = strictAutoReview
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        permissions = try container.decode(RequestPermissionProfile.self, forKey: .permissions)
        scope = try container.decodeIfPresent(PermissionGrantScope.self, forKey: .scope) ?? .turn
        strictAutoReview = try container.decodeIfPresent(Bool.self, forKey: .strictAutoReview) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(permissions, forKey: .permissions)
        try container.encode(scope, forKey: .scope)
        if strictAutoReview {
            try container.encode(strictAutoReview, forKey: .strictAutoReview)
        }
    }
}

public struct RequestPermissionsEvent: Codable, Equatable, Sendable {
    public let callID: String
    public let turnID: String
    public let startedAtMilliseconds: Int64
    public let reason: String?
    public let permissions: RequestPermissionProfile
    public let cwd: String?

    private enum CodingKeys: String, CodingKey {
        case callID = "call_id"
        case turnID = "turn_id"
        case startedAtMilliseconds = "started_at_ms"
        case reason
        case permissions
        case cwd
    }

    public init(
        callID: String,
        turnID: String = "",
        startedAtMilliseconds: Int64,
        reason: String? = nil,
        permissions: RequestPermissionProfile,
        cwd: String? = nil
    ) {
        self.callID = callID
        self.turnID = turnID
        self.startedAtMilliseconds = startedAtMilliseconds
        self.reason = reason
        self.permissions = permissions
        self.cwd = cwd
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        callID = try container.decode(String.self, forKey: .callID)
        turnID = try container.decodeIfPresent(String.self, forKey: .turnID) ?? ""
        startedAtMilliseconds = try container.decode(Int64.self, forKey: .startedAtMilliseconds)
        reason = try container.decodeIfPresent(String.self, forKey: .reason)
        permissions = try container.decode(RequestPermissionProfile.self, forKey: .permissions)
        cwd = try container.decodeIfPresent(String.self, forKey: .cwd)
    }
}
