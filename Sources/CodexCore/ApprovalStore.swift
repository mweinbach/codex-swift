import Foundation

public struct ApprovalStore: Sendable {
    private var decisionsBySerializedKey: [String: ReviewDecision]

    public init() {
        self.decisionsBySerializedKey = [:]
    }

    public func get<Key: Encodable>(_ key: Key) -> ReviewDecision? {
        guard let serialized = Self.serializedKey(key) else {
            return nil
        }
        return decisionsBySerializedKey[serialized]
    }

    public mutating func put<Key: Encodable>(_ key: Key, decision: ReviewDecision) {
        guard let serialized = Self.serializedKey(key) else {
            return
        }
        decisionsBySerializedKey[serialized] = decision
    }

    private static func serializedKey<Key: Encodable>(_ key: Key) -> String? {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(key) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
}

public struct ApprovalCache: Sendable {
    private var store: ApprovalStore

    public init(store: ApprovalStore = ApprovalStore()) {
        self.store = store
    }

    public mutating func withCachedApproval<Key: Encodable>(
        keys: [Key],
        fetch: () async -> ReviewDecision
    ) async -> ReviewDecision {
        guard !keys.isEmpty else {
            return await fetch()
        }

        let alreadyApproved = keys.allSatisfy {
            store.get($0) == .approvedForSession
        }
        if alreadyApproved {
            return .approvedForSession
        }

        let decision = await fetch()
        if decision == .approvedForSession {
            for key in keys {
                store.put(key, decision: .approvedForSession)
            }
        }
        return decision
    }

    public func get<Key: Encodable>(_ key: Key) -> ReviewDecision? {
        store.get(key)
    }
}

public struct ShellCommandApprovalKey: Codable, Equatable, Sendable {
    public var command: [String]
    public var cwd: String
    public var sandboxPermissions: SandboxPermissions
    public var additionalPermissions: RequestPermissionProfile?

    public init(
        command: [String],
        cwd: String,
        sandboxPermissions: SandboxPermissions,
        additionalPermissions: RequestPermissionProfile?
    ) {
        self.command = CommandCanonicalization.canonicalizeCommandForApproval(command)
        self.cwd = cwd
        self.sandboxPermissions = sandboxPermissions
        self.additionalPermissions = additionalPermissions
    }

    private enum CodingKeys: String, CodingKey {
        case command
        case cwd
        case sandboxPermissions = "sandbox_permissions"
        case additionalPermissions = "additional_permissions"
    }
}

public struct UnifiedExecApprovalKey: Codable, Equatable, Sendable {
    public var command: [String]
    public var cwd: String
    public var tty: Bool
    public var sandboxPermissions: SandboxPermissions
    public var additionalPermissions: RequestPermissionProfile?

    public init(
        command: [String],
        cwd: String,
        tty: Bool,
        sandboxPermissions: SandboxPermissions,
        additionalPermissions: RequestPermissionProfile?
    ) {
        self.command = CommandCanonicalization.canonicalizeCommandForApproval(command)
        self.cwd = cwd
        self.tty = tty
        self.sandboxPermissions = sandboxPermissions
        self.additionalPermissions = additionalPermissions
    }

    private enum CodingKeys: String, CodingKey {
        case command
        case cwd
        case tty
        case sandboxPermissions = "sandbox_permissions"
        case additionalPermissions = "additional_permissions"
    }
}
