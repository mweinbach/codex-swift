import Foundation

/// Thread-safe store for extension-private values scoped to a session, thread, or turn.
///
/// Extension contributors use this store to share state across host-owned lifecycle callbacks.
/// Values are keyed by their concrete Swift type, so callers can rely on retrieving the same
/// type they inserted without exposing storage details to the host runtime.
public final class ExtensionData: @unchecked Sendable {
    public let id: String

    private let lock = NSLock()
    private var storage: [ObjectIdentifier: any Sendable] = [:]

    public init(id: String = UUID().uuidString) {
        self.id = id
    }

    public func insert<Value: Sendable>(_ value: Value) {
        let key = ObjectIdentifier(Value.self)
        lock.withLock {
            storage[key] = value
        }
    }

    public func get<Value: Sendable>(_ type: Value.Type = Value.self) -> Value? {
        let key = ObjectIdentifier(type)
        return lock.withLock {
            storage[key] as? Value
        }
    }

    public func remove<Value: Sendable>(_ type: Value.Type = Value.self) -> Value? {
        let key = ObjectIdentifier(type)
        return lock.withLock {
            storage.removeValue(forKey: key) as? Value
        }
    }
}

public struct ExtensionThreadStartInput: Sendable {
    public let threadID: ThreadId
    public let config: CodexRuntimeConfig
    public let sessionStore: ExtensionData
    public let threadStore: ExtensionData

    public init(
        threadID: ThreadId,
        config: CodexRuntimeConfig,
        sessionStore: ExtensionData,
        threadStore: ExtensionData
    ) {
        self.threadID = threadID
        self.config = config
        self.sessionStore = sessionStore
        self.threadStore = threadStore
    }
}

public struct ExtensionThreadResumeInput: Sendable {
    public let threadID: ThreadId
    public let sessionStore: ExtensionData
    public let threadStore: ExtensionData

    public init(threadID: ThreadId, sessionStore: ExtensionData, threadStore: ExtensionData) {
        self.threadID = threadID
        self.sessionStore = sessionStore
        self.threadStore = threadStore
    }
}

public struct ExtensionThreadStopInput: Sendable {
    public let threadID: ThreadId
    public let sessionStore: ExtensionData
    public let threadStore: ExtensionData

    public init(threadID: ThreadId, sessionStore: ExtensionData, threadStore: ExtensionData) {
        self.threadID = threadID
        self.sessionStore = sessionStore
        self.threadStore = threadStore
    }
}

public struct ExtensionTurnStartInput: Sendable {
    public let threadID: ThreadId
    public let turnID: String
    public let sessionStore: ExtensionData
    public let threadStore: ExtensionData
    public let turnStore: ExtensionData

    public init(
        threadID: ThreadId,
        turnID: String,
        sessionStore: ExtensionData,
        threadStore: ExtensionData,
        turnStore: ExtensionData
    ) {
        self.threadID = threadID
        self.turnID = turnID
        self.sessionStore = sessionStore
        self.threadStore = threadStore
        self.turnStore = turnStore
    }
}

public struct ExtensionTurnStopInput: Sendable {
    public let threadID: ThreadId
    public let turnID: String
    public let sessionStore: ExtensionData
    public let threadStore: ExtensionData
    public let turnStore: ExtensionData

    public init(
        threadID: ThreadId,
        turnID: String,
        sessionStore: ExtensionData,
        threadStore: ExtensionData,
        turnStore: ExtensionData
    ) {
        self.threadID = threadID
        self.turnID = turnID
        self.sessionStore = sessionStore
        self.threadStore = threadStore
        self.turnStore = turnStore
    }
}

public struct ExtensionTurnAbortInput: Sendable {
    public let threadID: ThreadId
    public let turnID: String
    public let reason: TurnAbortReason
    public let sessionStore: ExtensionData
    public let threadStore: ExtensionData
    public let turnStore: ExtensionData

    public init(
        threadID: ThreadId,
        turnID: String,
        reason: TurnAbortReason,
        sessionStore: ExtensionData,
        threadStore: ExtensionData,
        turnStore: ExtensionData
    ) {
        self.threadID = threadID
        self.turnID = turnID
        self.reason = reason
        self.sessionStore = sessionStore
        self.threadStore = threadStore
        self.turnStore = turnStore
    }
}

public struct ExtensionConfigChangedInput: Sendable {
    public let threadID: ThreadId
    public let sessionStore: ExtensionData
    public let threadStore: ExtensionData
    public let previousConfig: CodexRuntimeConfig
    public let newConfig: CodexRuntimeConfig

    public init(
        threadID: ThreadId,
        sessionStore: ExtensionData,
        threadStore: ExtensionData,
        previousConfig: CodexRuntimeConfig,
        newConfig: CodexRuntimeConfig
    ) {
        self.threadID = threadID
        self.sessionStore = sessionStore
        self.threadStore = threadStore
        self.previousConfig = previousConfig
        self.newConfig = newConfig
    }
}

/// Observes host-owned thread lifecycle gates for extension-private state.
///
/// Implementers seed, rehydrate, and flush thread-scoped state. The host owns
/// runtime scheduling and calls contributors with stable thread identifiers plus
/// session and thread stores.
public protocol ExtensionThreadLifecycleContributor: Sendable {
    func onThreadStart(_ input: ExtensionThreadStartInput)
    func onThreadResume(_ input: ExtensionThreadResumeInput)
    func onThreadStop(_ input: ExtensionThreadStopInput)
}

public extension ExtensionThreadLifecycleContributor {
    func onThreadStart(_ input: ExtensionThreadStartInput) {}
    func onThreadResume(_ input: ExtensionThreadResumeInput) {}
    func onThreadStop(_ input: ExtensionThreadStopInput) {}
}

/// Observes host-owned turn lifecycle gates for extension-private turn state.
///
/// Implementers should keep turn setup, completion, and abort cleanup behind
/// this protocol instead of depending on concrete runtime task types.
public protocol ExtensionTurnLifecycleContributor: Sendable {
    func onTurnStart(_ input: ExtensionTurnStartInput)
    func onTurnStop(_ input: ExtensionTurnStopInput)
    func onTurnAbort(_ input: ExtensionTurnAbortInput)
}

public extension ExtensionTurnLifecycleContributor {
    func onTurnStart(_ input: ExtensionTurnStartInput) {}
    func onTurnStop(_ input: ExtensionTurnStopInput) {}
    func onTurnAbort(_ input: ExtensionTurnAbortInput) {}
}

/// Observes committed effective configuration changes for a thread runtime.
///
/// Implementers receive immutable before/after snapshots and can update
/// extension-owned state without each config mutation path knowing about that
/// extension's internals.
public protocol ExtensionConfigContributor: Sendable {
    func onConfigChanged(_ input: ExtensionConfigChangedInput)
}

public extension ExtensionConfigContributor {
    func onConfigChanged(_ input: ExtensionConfigChangedInput) {}
}

/// Observes token usage checkpoints after the host updates cached token usage.
///
/// Implementers should keep this callback cheap; hosts call it before emitting
/// the corresponding client-facing token usage notification.
public protocol ExtensionTokenUsageContributor: Sendable {
    func onTokenUsage(
        sessionStore: ExtensionData,
        threadStore: ExtensionData,
        turnStore: ExtensionData,
        threadID: ThreadId,
        turnID: String,
        tokenUsage: TokenUsageInfo
    )
}

public extension ExtensionTokenUsageContributor {
    func onTokenUsage(
        sessionStore: ExtensionData,
        threadStore: ExtensionData,
        turnStore: ExtensionData,
        threadID: ThreadId,
        turnID: String,
        tokenUsage: TokenUsageInfo
    ) {}
}

public struct ExtensionRegistryBuilder: Sendable {
    private var threadLifecycleContributors: [any ExtensionThreadLifecycleContributor] = []
    private var turnLifecycleContributors: [any ExtensionTurnLifecycleContributor] = []
    private var configContributors: [any ExtensionConfigContributor] = []
    private var tokenUsageContributors: [any ExtensionTokenUsageContributor] = []

    public init() {}

    public mutating func threadLifecycleContributor(_ contributor: any ExtensionThreadLifecycleContributor) {
        threadLifecycleContributors.append(contributor)
    }

    public mutating func turnLifecycleContributor(_ contributor: any ExtensionTurnLifecycleContributor) {
        turnLifecycleContributors.append(contributor)
    }

    public mutating func configContributor(_ contributor: any ExtensionConfigContributor) {
        configContributors.append(contributor)
    }

    public mutating func tokenUsageContributor(_ contributor: any ExtensionTokenUsageContributor) {
        tokenUsageContributors.append(contributor)
    }

    public func build() -> ExtensionRegistry {
        ExtensionRegistry(
            threadLifecycleContributors: threadLifecycleContributors,
            turnLifecycleContributors: turnLifecycleContributors,
            configContributors: configContributors,
            tokenUsageContributors: tokenUsageContributors
        )
    }
}

public struct ExtensionRegistry: Sendable {
    public let threadLifecycleContributors: [any ExtensionThreadLifecycleContributor]
    public let turnLifecycleContributors: [any ExtensionTurnLifecycleContributor]
    public let configContributors: [any ExtensionConfigContributor]
    public let tokenUsageContributors: [any ExtensionTokenUsageContributor]

    public init(
        threadLifecycleContributors: [any ExtensionThreadLifecycleContributor] = [],
        turnLifecycleContributors: [any ExtensionTurnLifecycleContributor] = [],
        configContributors: [any ExtensionConfigContributor] = [],
        tokenUsageContributors: [any ExtensionTokenUsageContributor] = []
    ) {
        self.threadLifecycleContributors = threadLifecycleContributors
        self.turnLifecycleContributors = turnLifecycleContributors
        self.configContributors = configContributors
        self.tokenUsageContributors = tokenUsageContributors
    }

    public static var empty: ExtensionRegistry {
        ExtensionRegistry()
    }
}
