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

public enum ExtensionPromptSlot: String, Sendable {
    case developerPolicy
    case developerCapabilities
    case contextualUser
    case separateDeveloper
}

public struct ExtensionPromptFragment: Equatable, Sendable {
    public let slot: ExtensionPromptSlot
    public let text: String

    public init(slot: ExtensionPromptSlot, text: String) {
        self.slot = slot
        self.text = text
    }

    public static func developerPolicy(_ text: String) -> Self {
        Self(slot: .developerPolicy, text: text)
    }

    public static func developerCapability(_ text: String) -> Self {
        Self(slot: .developerCapabilities, text: text)
    }

    public static func contextualUser(_ text: String) -> Self {
        Self(slot: .contextualUser, text: text)
    }

    public static func separateDeveloper(_ text: String) -> Self {
        Self(slot: .separateDeveloper, text: text)
    }
}

public struct ExtensionTool: Sendable {
    public let spec: ToolSpec
    public let supportsParallelToolCalls: Bool
    private let executor: @Sendable (ResponseItem) async throws -> any ExtensionToolOutput

    public init(
        spec: ToolSpec,
        supportsParallelToolCalls: Bool = false,
        executor: @escaping @Sendable (ResponseItem) async throws -> any ExtensionToolOutput
    ) {
        self.spec = spec
        self.supportsParallelToolCalls = supportsParallelToolCalls
        self.executor = executor
    }

    public func execute(_ item: ResponseItem) async throws -> NonInteractiveExec.FunctionCallExecutionResult {
        let output = try await executor(item)
        let context = Self.callContext(from: item)
        return NonInteractiveExec.FunctionCallExecutionResult(
            output: output.toResponseItem(
                callID: context.callID,
                isCustomToolCall: context.isCustomToolCall,
                customToolName: context.customToolName
            )
        )
    }

    public func executeForOutput(_ item: ResponseItem) async throws -> any ExtensionToolOutput {
        try await executor(item)
    }

    public func matches(_ item: ResponseItem) -> Bool {
        switch item {
        case let .functionCall(_, name, namespace, _, _):
            let flatName = namespace.map { "\($0)\(name)" } ?? name
            switch spec {
            case let .function(tool):
                return tool.name == flatName
            case let .namespace(toolNamespace):
                return namespace == toolNamespace.name
                    && toolNamespace.tools.contains { namespaceTool in
                        if case let .function(tool) = namespaceTool {
                            return tool.name == name
                        }
                        return false
                    }
            default:
                return false
            }
        case let .customToolCall(_, _, _, name, _):
            if case let .function(tool) = spec {
                return tool.name == name
            }
            return false
        default:
            return false
        }
    }

    private static func callContext(from item: ResponseItem) -> (
        callID: String,
        isCustomToolCall: Bool,
        customToolName: String?
    ) {
        switch item {
        case let .functionCall(_, name, namespace, _, callID):
            return (callID, false, namespace.map { "\($0)/\(name)" } ?? name)
        case let .customToolCall(_, _, callID, name, _):
            return (callID, true, name)
        case let .functionCallOutput(callID, _):
            return (callID, false, nil)
        case let .customToolCallOutput(callID, name, _):
            return (callID, true, name)
        default:
            return ("", false, nil)
        }
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

/// Contributes prompt fragments during model-input assembly.
///
/// Implementers return model-visible text for explicit prompt slots while using
/// only the stable session and thread stores exposed by the host.
public protocol ExtensionContextContributor: Sendable {
    func contribute(
        sessionStore: ExtensionData,
        threadStore: ExtensionData
    ) async -> [ExtensionPromptFragment]
}

public extension ExtensionContextContributor {
    func contribute(
        sessionStore: ExtensionData,
        threadStore: ExtensionData
    ) async -> [ExtensionPromptFragment] {
        []
    }
}

/// Exposes extension-owned native tools for the current session and thread.
///
/// Implementers provide both tool specs and executors so hosts can keep
/// extension tool registration separate from built-in tool dispatch.
public protocol ExtensionToolContributor: Sendable {
    func tools(sessionStore: ExtensionData, threadStore: ExtensionData) -> [ExtensionTool]
}

public extension ExtensionToolContributor {
    func tools(sessionStore: ExtensionData, threadStore: ExtensionData) -> [ExtensionTool] {
        []
    }
}

/// Reviews rendered approval prompts before the host asks the user.
///
/// Implementers may claim a prompt by returning a decision, or return nil to
/// leave the prompt available for later contributors and the normal host flow.
public protocol ExtensionApprovalReviewContributor: Sendable {
    func contribute(
        sessionStore: ExtensionData,
        threadStore: ExtensionData,
        prompt: String
    ) async -> ReviewDecision?
}

public extension ExtensionApprovalReviewContributor {
    func contribute(
        sessionStore: ExtensionData,
        threadStore: ExtensionData,
        prompt: String
    ) async -> ReviewDecision? {
        nil
    }
}

/// Rewrites or annotates parsed turn items before the host emits them.
///
/// Implementers receive only thread- and turn-scoped stores plus the parsed item,
/// and return the item that should continue through the stream pipeline.
public protocol ExtensionTurnItemContributor: Sendable {
    func contribute(
        threadStore: ExtensionData,
        turnStore: ExtensionData,
        item: TurnItem
    ) async throws -> TurnItem
}

public extension ExtensionTurnItemContributor {
    func contribute(
        threadStore: ExtensionData,
        turnStore: ExtensionData,
        item: TurnItem
    ) async throws -> TurnItem {
        item
    }
}

public struct ExtensionRegistryBuilder: Sendable {
    private var threadLifecycleContributors: [any ExtensionThreadLifecycleContributor] = []
    private var turnLifecycleContributors: [any ExtensionTurnLifecycleContributor] = []
    private var configContributors: [any ExtensionConfigContributor] = []
    private var tokenUsageContributors: [any ExtensionTokenUsageContributor] = []
    private var contextContributors: [any ExtensionContextContributor] = []
    private var toolContributors: [any ExtensionToolContributor] = []
    private var approvalReviewContributors: [any ExtensionApprovalReviewContributor] = []
    private var turnItemContributors: [any ExtensionTurnItemContributor] = []

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

    public mutating func promptContributor(_ contributor: any ExtensionContextContributor) {
        contextContributors.append(contributor)
    }

    public mutating func toolContributor(_ contributor: any ExtensionToolContributor) {
        toolContributors.append(contributor)
    }

    public mutating func approvalReviewContributor(_ contributor: any ExtensionApprovalReviewContributor) {
        approvalReviewContributors.append(contributor)
    }

    public mutating func turnItemContributor(_ contributor: any ExtensionTurnItemContributor) {
        turnItemContributors.append(contributor)
    }

    public func build() -> ExtensionRegistry {
        ExtensionRegistry(
            threadLifecycleContributors: threadLifecycleContributors,
            turnLifecycleContributors: turnLifecycleContributors,
            configContributors: configContributors,
            tokenUsageContributors: tokenUsageContributors,
            contextContributors: contextContributors,
            toolContributors: toolContributors,
            approvalReviewContributors: approvalReviewContributors,
            turnItemContributors: turnItemContributors
        )
    }
}

public struct ExtensionRegistry: Sendable {
    public let threadLifecycleContributors: [any ExtensionThreadLifecycleContributor]
    public let turnLifecycleContributors: [any ExtensionTurnLifecycleContributor]
    public let configContributors: [any ExtensionConfigContributor]
    public let tokenUsageContributors: [any ExtensionTokenUsageContributor]
    public let contextContributors: [any ExtensionContextContributor]
    public let toolContributors: [any ExtensionToolContributor]
    public let approvalReviewContributors: [any ExtensionApprovalReviewContributor]
    public let turnItemContributors: [any ExtensionTurnItemContributor]

    public init(
        threadLifecycleContributors: [any ExtensionThreadLifecycleContributor] = [],
        turnLifecycleContributors: [any ExtensionTurnLifecycleContributor] = [],
        configContributors: [any ExtensionConfigContributor] = [],
        tokenUsageContributors: [any ExtensionTokenUsageContributor] = [],
        contextContributors: [any ExtensionContextContributor] = [],
        toolContributors: [any ExtensionToolContributor] = [],
        approvalReviewContributors: [any ExtensionApprovalReviewContributor] = [],
        turnItemContributors: [any ExtensionTurnItemContributor] = []
    ) {
        self.threadLifecycleContributors = threadLifecycleContributors
        self.turnLifecycleContributors = turnLifecycleContributors
        self.configContributors = configContributors
        self.tokenUsageContributors = tokenUsageContributors
        self.contextContributors = contextContributors
        self.toolContributors = toolContributors
        self.approvalReviewContributors = approvalReviewContributors
        self.turnItemContributors = turnItemContributors
    }

    public static var empty: ExtensionRegistry {
        ExtensionRegistry()
    }

    public func tools(sessionStore: ExtensionData, threadStore: ExtensionData) -> [ExtensionTool] {
        toolContributors.flatMap {
            $0.tools(sessionStore: sessionStore, threadStore: threadStore)
        }
    }

    public func configuredToolSpecs(
        sessionStore: ExtensionData,
        threadStore: ExtensionData
    ) -> [ConfiguredToolSpec] {
        tools(sessionStore: sessionStore, threadStore: threadStore).map {
            ConfiguredToolSpec(spec: $0.spec, supportsParallelToolCalls: $0.supportsParallelToolCalls)
        }
    }

    public func registeredToolExecutor(
        sessionStore: ExtensionData,
        threadStore: ExtensionData
    ) -> NonInteractiveExec.RegisteredToolExecutor? {
        let tools = tools(sessionStore: sessionStore, threadStore: threadStore)
        guard !tools.isEmpty else {
            return nil
        }
        return { item in
            guard let tool = tools.first(where: { $0.matches(item) }) else {
                return nil
            }
            do {
                return try await tool.execute(item)
            } catch {
                return NonInteractiveExec.FunctionCallExecutionResult(
                    output: ExtensionRegistry.errorOutput(for: item, message: String(describing: error))
                )
            }
        }
    }

    public func emitThreadStart(_ input: ExtensionThreadStartInput) {
        for contributor in threadLifecycleContributors {
            contributor.onThreadStart(input)
        }
    }

    public func emitThreadResume(_ input: ExtensionThreadResumeInput) {
        for contributor in threadLifecycleContributors {
            contributor.onThreadResume(input)
        }
    }

    public func emitThreadStop(_ input: ExtensionThreadStopInput) {
        for contributor in threadLifecycleContributors {
            contributor.onThreadStop(input)
        }
    }

    public func emitTurnStart(_ input: ExtensionTurnStartInput) {
        for contributor in turnLifecycleContributors {
            contributor.onTurnStart(input)
        }
    }

    public func emitTurnStop(_ input: ExtensionTurnStopInput) {
        for contributor in turnLifecycleContributors {
            contributor.onTurnStop(input)
        }
    }

    public func emitTurnAbort(_ input: ExtensionTurnAbortInput) {
        for contributor in turnLifecycleContributors {
            contributor.onTurnAbort(input)
        }
    }

    public func emitConfigChanged(_ input: ExtensionConfigChangedInput) {
        for contributor in configContributors {
            contributor.onConfigChanged(input)
        }
    }

    public func emitTokenUsage(
        sessionStore: ExtensionData,
        threadStore: ExtensionData,
        turnStore: ExtensionData,
        threadID: ThreadId,
        turnID: String,
        tokenUsage: TokenUsageInfo
    ) {
        for contributor in tokenUsageContributors {
            contributor.onTokenUsage(
                sessionStore: sessionStore,
                threadStore: threadStore,
                turnStore: turnStore,
                threadID: threadID,
                turnID: turnID,
                tokenUsage: tokenUsage
            )
        }
    }

    public func contributeTurnItem(
        threadStore: ExtensionData,
        turnStore: ExtensionData,
        item: TurnItem
    ) async throws -> TurnItem {
        var current = item
        for contributor in turnItemContributors {
            current = try await contributor.contribute(
                threadStore: threadStore,
                turnStore: turnStore,
                item: current
            )
        }
        return current
    }

    public func approvalReview(
        sessionStore: ExtensionData,
        threadStore: ExtensionData,
        prompt: String
    ) async -> ReviewDecision? {
        for contributor in approvalReviewContributors {
            if let decision = await contributor.contribute(
                sessionStore: sessionStore,
                threadStore: threadStore,
                prompt: prompt
            ) {
                return decision
            }
        }
        return nil
    }

    private static func errorOutput(for item: ResponseItem, message: String) -> ResponseItem {
        let output = FunctionCallOutputPayload(content: message, success: false)
        switch item {
        case let .functionCall(_, _, _, _, callID):
            return .functionCallOutput(callID: callID, output: output)
        case let .customToolCall(_, _, callID, name, _):
            return .customToolCallOutput(callID: callID, name: name, output: output)
        default:
            return .functionCallOutput(callID: "", output: output)
        }
    }
}

/// Host-owned extension state for one running session.
///
/// Runtime owners use this coordinator to share a single session store across
/// thread runtimes, keep each thread's store stable for the lifetime of that
/// thread, and keep turn stores alive through completion or abort callbacks.
public final class ExtensionRuntimeState: @unchecked Sendable {
    public let registry: ExtensionRegistry
    public let sessionStore: ExtensionData

    private let lock = NSLock()
    private var threadStores: [ThreadId: ExtensionData] = [:]
    private var turnStores: [TurnKey: ExtensionData] = [:]

    public init(registry: ExtensionRegistry = .empty, sessionStore: ExtensionData = ExtensionData(id: "session")) {
        self.registry = registry
        self.sessionStore = sessionStore
    }

    public func threadStore(for threadID: ThreadId) -> ExtensionData {
        lock.withLock {
            if let store = threadStores[threadID] {
                return store
            }
            let store = ExtensionData(id: threadID.description)
            threadStores[threadID] = store
            return store
        }
    }

    public func existingThreadStore(for threadID: ThreadId) -> ExtensionData? {
        lock.withLock {
            threadStores[threadID]
        }
    }

    public func turnStore(threadID: ThreadId, turnID: String) -> ExtensionData {
        let key = TurnKey(threadID: threadID, turnID: turnID)
        return lock.withLock {
            if let store = turnStores[key] {
                return store
            }
            let store = ExtensionData(id: turnID)
            turnStores[key] = store
            return store
        }
    }

    public func existingTurnStore(threadID: ThreadId, turnID: String) -> ExtensionData? {
        lock.withLock {
            turnStores[TurnKey(threadID: threadID, turnID: turnID)]
        }
    }

    @discardableResult
    public func removeThreadStore(for threadID: ThreadId) -> ExtensionData? {
        lock.withLock {
            turnStores = turnStores.filter { $0.key.threadID != threadID }
            return threadStores.removeValue(forKey: threadID)
        }
    }

    @discardableResult
    public func removeTurnStore(threadID: ThreadId, turnID: String) -> ExtensionData? {
        lock.withLock {
            turnStores.removeValue(forKey: TurnKey(threadID: threadID, turnID: turnID))
        }
    }

    @discardableResult
    public func emitThreadStart(threadID: ThreadId, config: CodexRuntimeConfig) -> ExtensionData {
        let threadStore = threadStore(for: threadID)
        registry.emitThreadStart(ExtensionThreadStartInput(
            threadID: threadID,
            config: config,
            sessionStore: sessionStore,
            threadStore: threadStore
        ))
        return threadStore
    }

    @discardableResult
    public func emitThreadResume(threadID: ThreadId) -> ExtensionData {
        let threadStore = threadStore(for: threadID)
        registry.emitThreadResume(ExtensionThreadResumeInput(
            threadID: threadID,
            sessionStore: sessionStore,
            threadStore: threadStore
        ))
        return threadStore
    }

    public func emitThreadStop(threadID: ThreadId) {
        let threadStore = threadStore(for: threadID)
        registry.emitThreadStop(ExtensionThreadStopInput(
            threadID: threadID,
            sessionStore: sessionStore,
            threadStore: threadStore
        ))
        removeThreadStore(for: threadID)
    }

    @discardableResult
    public func emitTurnStart(threadID: ThreadId, turnID: String) -> ExtensionData {
        let threadStore = threadStore(for: threadID)
        let turnStore = turnStore(threadID: threadID, turnID: turnID)
        registry.emitTurnStart(ExtensionTurnStartInput(
            threadID: threadID,
            turnID: turnID,
            sessionStore: sessionStore,
            threadStore: threadStore,
            turnStore: turnStore
        ))
        return turnStore
    }

    public func emitTurnStop(threadID: ThreadId, turnID: String) {
        let threadStore = threadStore(for: threadID)
        let turnStore = turnStore(threadID: threadID, turnID: turnID)
        registry.emitTurnStop(ExtensionTurnStopInput(
            threadID: threadID,
            turnID: turnID,
            sessionStore: sessionStore,
            threadStore: threadStore,
            turnStore: turnStore
        ))
        removeTurnStore(threadID: threadID, turnID: turnID)
    }

    public func emitTurnAbort(threadID: ThreadId, turnID: String, reason: TurnAbortReason) {
        let threadStore = threadStore(for: threadID)
        let turnStore = turnStore(threadID: threadID, turnID: turnID)
        registry.emitTurnAbort(ExtensionTurnAbortInput(
            threadID: threadID,
            turnID: turnID,
            reason: reason,
            sessionStore: sessionStore,
            threadStore: threadStore,
            turnStore: turnStore
        ))
        removeTurnStore(threadID: threadID, turnID: turnID)
    }

    public func emitConfigChanged(
        threadID: ThreadId,
        previousConfig: CodexRuntimeConfig,
        newConfig: CodexRuntimeConfig
    ) {
        let threadStore = threadStore(for: threadID)
        registry.emitConfigChanged(ExtensionConfigChangedInput(
            threadID: threadID,
            sessionStore: sessionStore,
            threadStore: threadStore,
            previousConfig: previousConfig,
            newConfig: newConfig
        ))
    }

    public func emitTokenUsage(
        threadID: ThreadId,
        turnID: String,
        tokenUsage: TokenUsageInfo
    ) {
        let threadStore = threadStore(for: threadID)
        let turnStore = turnStore(threadID: threadID, turnID: turnID)
        registry.emitTokenUsage(
            sessionStore: sessionStore,
            threadStore: threadStore,
            turnStore: turnStore,
            threadID: threadID,
            turnID: turnID,
            tokenUsage: tokenUsage
        )
    }

    public func configuredToolSpecs(threadID: ThreadId) -> [ConfiguredToolSpec] {
        registry.configuredToolSpecs(sessionStore: sessionStore, threadStore: threadStore(for: threadID))
    }

    public func registeredToolExecutor(threadID: ThreadId) -> NonInteractiveExec.RegisteredToolExecutor? {
        registry.registeredToolExecutor(sessionStore: sessionStore, threadStore: threadStore(for: threadID))
    }

    public func approvalReview(threadID: ThreadId, prompt: String) async -> ReviewDecision? {
        await registry.approvalReview(
            sessionStore: sessionStore,
            threadStore: threadStore(for: threadID),
            prompt: prompt
        )
    }

    public func contributeTurnItem(threadID: ThreadId, turnID: String, item: TurnItem) async throws -> TurnItem {
        try await registry.contributeTurnItem(
            threadStore: threadStore(for: threadID),
            turnStore: turnStore(threadID: threadID, turnID: turnID),
            item: item
        )
    }

    private struct TurnKey: Hashable {
        let threadID: ThreadId
        let turnID: String
    }
}
