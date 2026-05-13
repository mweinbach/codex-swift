import Foundation

public let memoryStageTwoModel = "gpt-5.4"
public let memoryStageTwoReasoningEffort: ReasoningEffort = .medium
public let memoryStageTwoJobLeaseSeconds: Int64 = 3_600
public let memoryStageTwoJobRetryDelaySeconds: Int64 = 3_600
public let memoryStageTwoJobHeartbeatSeconds: UInt64 = 90
public let memoryStageTwoAgentStatusPollSeconds: UInt64 = 1
public let memoryStageTwoAgentShutdownTimeoutSeconds: UInt64 = 10

public typealias MemoryPhaseTwoSleep = @Sendable (_ seconds: UInt64) async -> Void

public func memoryPhaseTwoSleep(seconds: UInt64) async {
    try? await Task.sleep(nanoseconds: seconds * 1_000_000_000)
}

public struct MemoryPhaseTwoClaim: Equatable, Sendable {
    public let token: String
    public let watermark: Int64

    public init(token: String, watermark: Int64) {
        self.token = token
        self.watermark = watermark
    }
}

public enum MemoryPhaseTwoClaimError: String, Error, Equatable, CustomStringConvertible, Sendable {
    case failedClaim = "failed_claim"
    case skippedRetryUnavailable = "skipped_retry_unavailable"
    case skippedCooldown = "skipped_cooldown"
    case skippedRunning = "skipped_running"

    public var description: String { rawValue }
}

/// Storage boundary used by the Phase 2 memory consolidation runner.
///
/// `SQLiteAgentGraphStore` is the production implementation; tests can provide in-memory actors.
/// Callers may rely on implementations preserving Rust's ownership-token semantics across
/// claim, failure, success, and selected-output snapshot updates.
public protocol MemoryPhaseTwoJobStore: Sendable {
    func getPhase2InputSelection(
        limit: Int,
        maxUnusedDays: Int64
    ) async throws -> [Stage1Output]

    func tryClaimGlobalPhase2Job(
        threadID: ThreadId,
        leaseSeconds: Int64
    ) async throws -> Phase2JobClaimOutcome

    func markGlobalPhase2JobFailed(
        ownershipToken: String,
        reason: String,
        retryDelaySeconds: Int64
    ) async throws -> Bool

    func markGlobalPhase2JobFailedIfUnowned(
        ownershipToken: String,
        reason: String,
        retryDelaySeconds: Int64
    ) async throws -> Bool

    func heartbeatGlobalPhase2Job(
        ownershipToken: String,
        leaseSeconds: Int64
    ) async throws -> Bool

    func markGlobalPhase2JobSucceeded(
        ownershipToken: String,
        completionWatermark: Int64,
        selectedOutputs: [Stage1Output]
    ) async throws -> Bool
}

extension SQLiteAgentGraphStore: MemoryPhaseTwoJobStore {
    public func tryClaimGlobalPhase2Job(
        threadID: ThreadId,
        leaseSeconds: Int64
    ) async throws -> Phase2JobClaimOutcome {
        try await tryClaimGlobalPhase2Job(workerID: threadID, leaseSeconds: leaseSeconds)
    }

    public func markGlobalPhase2JobFailed(
        ownershipToken: String,
        reason: String,
        retryDelaySeconds: Int64
    ) async throws -> Bool {
        try await markGlobalPhase2JobFailed(
            ownershipToken: ownershipToken,
            failureReason: reason,
            retryDelaySeconds: retryDelaySeconds
        )
    }

    public func markGlobalPhase2JobFailedIfUnowned(
        ownershipToken: String,
        reason: String,
        retryDelaySeconds: Int64
    ) async throws -> Bool {
        try await markGlobalPhase2JobFailedIfUnowned(
            ownershipToken: ownershipToken,
            failureReason: reason,
            retryDelaySeconds: retryDelaySeconds
        )
    }

    public func markGlobalPhase2JobSucceeded(
        ownershipToken: String,
        completionWatermark: Int64,
        selectedOutputs: [Stage1Output]
    ) async throws -> Bool {
        try await markGlobalPhase2JobSucceeded(
            ownershipToken: ownershipToken,
            completedWatermark: completionWatermark,
            selectedOutputs: selectedOutputs
        )
    }
}

public typealias MemoryWriteCounterRecorder = @Sendable (
    _ name: String,
    _ increment: Int64,
    _ labels: [(String, String)]
) -> Void

public typealias MemoryWriteHistogramRecorder = @Sendable (
    _ name: String,
    _ value: Int64,
    _ labels: [(String, String)]
) -> Void

public struct MemoryPhaseTwoConsolidationRequest: Equatable, Sendable {
    public let claim: MemoryPhaseTwoClaim
    public let completionWatermark: Int64
    public let selectedOutputs: [Stage1Output]
    public let agentConfig: CodexRuntimeConfig
    public let prompt: [UserInput]
    public let workspaceDiff: MemoryWorkspaceDiff

    public init(
        claim: MemoryPhaseTwoClaim,
        completionWatermark: Int64,
        selectedOutputs: [Stage1Output],
        agentConfig: CodexRuntimeConfig,
        prompt: [UserInput],
        workspaceDiff: MemoryWorkspaceDiff
    ) {
        self.claim = claim
        self.completionWatermark = completionWatermark
        self.selectedOutputs = selectedOutputs
        self.agentConfig = agentConfig
        self.prompt = prompt
        self.workspaceDiff = workspaceDiff
    }
}

public enum MemoryPhaseTwoPreparationOutcome: Equatable, Sendable {
    case skipped(String)
    case failed(String)
    case succeededNoWorkspaceChanges
    case readyToSpawn(MemoryPhaseTwoConsolidationRequest)
}

public enum MemoryPhaseTwoCompletionOutcome: Equatable, Sendable {
    case succeeded
    case failed(String)
    case lostOwnership
    case successRecordLost
}

public struct MemoryPhaseTwoConsolidationAgentShutdownTimeoutError: Error, Equatable,
    CustomStringConvertible, Sendable
{
    public let threadID: ThreadId

    public init(threadID: ThreadId) {
        self.threadID = threadID
    }

    public var description: String {
        "memory consolidation agent \(threadID) shutdown timed out"
    }
}

public enum MemoryPhaseTwoRunOutcome: Equatable, Sendable {
    case skipped(String)
    case failed(String)
    case succeededNoWorkspaceChanges
    case completed(MemoryPhaseTwoCompletionOutcome)
}

public enum MemoryPhaseTwoAgentLoopEvent: Equatable, Sendable {
    case statusPoll
    case heartbeat
    case sessionTerminated
}

public enum MemoryPhaseTwoAgentLoopWaitResult: Equatable, Sendable {
    case timerElapsed
    case sessionTerminated
}

public typealias MemoryPhaseTwoAgentLoopWait = @Sendable (
    _ seconds: UInt64,
    _ waitForSessionTermination: @escaping @Sendable () async -> Void,
    _ sleep: @escaping MemoryPhaseTwoSleep
) async -> MemoryPhaseTwoAgentLoopWaitResult

public func waitForMemoryPhaseTwoAgentLoopEvent(
    seconds: UInt64,
    waitForSessionTermination: @escaping @Sendable () async -> Void,
    sleep: @escaping MemoryPhaseTwoSleep = memoryPhaseTwoSleep
) async -> MemoryPhaseTwoAgentLoopWaitResult {
    await withTaskGroup(of: MemoryPhaseTwoAgentLoopWaitResult.self) { group in
        group.addTask {
            await waitForSessionTermination()
            return .sessionTerminated
        }
        group.addTask {
            await sleep(seconds)
            return .timerElapsed
        }

        let result = await group.next() ?? .timerElapsed
        group.cancelAll()
        return result
    }
}

public actor MemoryPhaseTwoAgentLoopEventSource {
    private let statusPollSeconds: UInt64
    private let heartbeatSeconds: UInt64
    private let waitForSessionTermination: @Sendable () async -> Void
    private let wait: MemoryPhaseTwoAgentLoopWait
    private let sleep: MemoryPhaseTwoSleep
    private var secondsUntilHeartbeat: UInt64

    public init(
        statusPollSeconds: UInt64 = memoryStageTwoAgentStatusPollSeconds,
        heartbeatSeconds: UInt64 = memoryStageTwoJobHeartbeatSeconds,
        waitForSessionTermination: @escaping @Sendable () async -> Void,
        wait: @escaping MemoryPhaseTwoAgentLoopWait = waitForMemoryPhaseTwoAgentLoopEvent,
        sleep: @escaping MemoryPhaseTwoSleep = memoryPhaseTwoSleep
    ) {
        self.statusPollSeconds = max(1, statusPollSeconds)
        self.heartbeatSeconds = max(1, heartbeatSeconds)
        self.waitForSessionTermination = waitForSessionTermination
        self.wait = wait
        self.sleep = sleep
        self.secondsUntilHeartbeat = max(1, heartbeatSeconds)
    }

    public func next() async -> MemoryPhaseTwoAgentLoopEvent {
        let waitSeconds = min(statusPollSeconds, secondsUntilHeartbeat)
        let result = await wait(waitSeconds, waitForSessionTermination, sleep)
        if result == .sessionTerminated {
            return .sessionTerminated
        }

        if secondsUntilHeartbeat <= statusPollSeconds {
            secondsUntilHeartbeat = heartbeatSeconds
            return .heartbeat
        }

        secondsUntilHeartbeat -= waitSeconds
        return .statusPoll
    }

    public nonisolated var nextEvent: @Sendable () async -> MemoryPhaseTwoAgentLoopEvent {
        { await self.next() }
    }
}

public struct MemoryPhaseTwoConsolidationThreadStartOptions: Equatable, Sendable {
    public let config: CodexRuntimeConfig
    public let initialHistory: InitialHistory
    public let sessionSource: SessionSource
    public let threadSource: ThreadSource
    public let dynamicTools: [DynamicToolSpec]
    public let persistExtendedHistory: Bool
    public let metricsServiceName: String?

    public init(
        config: CodexRuntimeConfig,
        initialHistory: InitialHistory = .new,
        sessionSource: SessionSource = .internal(.memoryConsolidation),
        threadSource: ThreadSource = .memoryConsolidation,
        dynamicTools: [DynamicToolSpec] = [],
        persistExtendedHistory: Bool = false,
        metricsServiceName: String? = nil
    ) {
        self.config = config
        self.initialHistory = initialHistory
        self.sessionSource = sessionSource
        self.threadSource = threadSource
        self.dynamicTools = dynamicTools
        self.persistExtendedHistory = persistExtendedHistory
        self.metricsServiceName = metricsServiceName
    }
}

public struct MemoryPhaseTwoSpawnedConsolidationAgent: Sendable {
    public let threadID: ThreadId
    public let status: @Sendable () async -> AgentStatus
    public let tokenUsage: @Sendable () async -> TokenUsage?
    public let nextEvent: @Sendable () async -> MemoryPhaseTwoAgentLoopEvent
    public let shutdown: @Sendable () async throws -> Void

    public init(
        threadID: ThreadId,
        status: @escaping @Sendable () async -> AgentStatus,
        tokenUsage: @escaping @Sendable () async -> TokenUsage? = { nil },
        nextEvent: @escaping @Sendable () async -> MemoryPhaseTwoAgentLoopEvent,
        shutdown: @escaping @Sendable () async throws -> Void = {}
    ) {
        self.threadID = threadID
        self.status = status
        self.tokenUsage = tokenUsage
        self.nextEvent = nextEvent
        self.shutdown = shutdown
    }
}

public struct MemoryPhaseTwoStartedConsolidationAgent: Sendable {
    public let threadID: ThreadId
    public let status: @Sendable () async -> AgentStatus
    public let tokenUsage: @Sendable () async -> TokenUsage?
    public let nextEvent: @Sendable () async -> MemoryPhaseTwoAgentLoopEvent
    public let submit: @Sendable (Op) async throws -> Void
    public let shutdown: @Sendable () async throws -> Void

    public init(
        threadID: ThreadId,
        status: @escaping @Sendable () async -> AgentStatus,
        tokenUsage: @escaping @Sendable () async -> TokenUsage? = { nil },
        nextEvent: @escaping @Sendable () async -> MemoryPhaseTwoAgentLoopEvent,
        submit: @escaping @Sendable (Op) async throws -> Void,
        shutdown: @escaping @Sendable () async throws -> Void = {}
    ) {
        self.threadID = threadID
        self.status = status
        self.tokenUsage = tokenUsage
        self.nextEvent = nextEvent
        self.submit = submit
        self.shutdown = shutdown
    }
}

public typealias MemoryPhaseTwoConsolidationAgentStarter = @Sendable (
    _ options: MemoryPhaseTwoConsolidationThreadStartOptions
) async throws -> MemoryPhaseTwoStartedConsolidationAgent

public func memoryRoot(codexHome: URL) -> URL {
    codexHome.appendingPathComponent("memories", isDirectory: true)
}

public func claimMemoryPhaseTwoJob(
    threadID: ThreadId,
    store: MemoryPhaseTwoJobStore,
    recordCounter: MemoryWriteCounterRecorder? = nil
) async throws -> MemoryPhaseTwoClaim {
    let outcome: Phase2JobClaimOutcome
    do {
        outcome = try await store.tryClaimGlobalPhase2Job(
            threadID: threadID,
            leaseSeconds: memoryStageTwoJobLeaseSeconds
        )
    } catch {
        throw MemoryPhaseTwoClaimError.failedClaim
    }

    switch outcome {
    case let .claimed(ownershipToken, inputWatermark):
        recordCounter?(MemoryWriteMetrics.phaseTwoJobs, 1, [("status", "claimed")])
        return MemoryPhaseTwoClaim(token: ownershipToken, watermark: inputWatermark)
    case .skippedRetryUnavailable:
        throw MemoryPhaseTwoClaimError.skippedRetryUnavailable
    case .skippedCooldown:
        throw MemoryPhaseTwoClaimError.skippedCooldown
    case .skippedRunning:
        throw MemoryPhaseTwoClaimError.skippedRunning
    }
}

@discardableResult
public func markMemoryPhaseTwoJobFailed(
    store: MemoryPhaseTwoJobStore,
    claim: MemoryPhaseTwoClaim,
    reason: String,
    recordCounter: MemoryWriteCounterRecorder? = nil
) async throws -> Bool {
    recordCounter?(MemoryWriteMetrics.phaseTwoJobs, 1, [("status", reason)])
    let owned = try await store.markGlobalPhase2JobFailed(
        ownershipToken: claim.token,
        reason: reason,
        retryDelaySeconds: memoryStageTwoJobRetryDelaySeconds
    )
    if owned {
        return true
    }
    return try await store.markGlobalPhase2JobFailedIfUnowned(
        ownershipToken: claim.token,
        reason: reason,
        retryDelaySeconds: memoryStageTwoJobRetryDelaySeconds
    )
}

@discardableResult
public func markMemoryPhaseTwoJobSucceeded(
    store: MemoryPhaseTwoJobStore,
    claim: MemoryPhaseTwoClaim,
    completionWatermark: Int64,
    selectedOutputs: [Stage1Output],
    reason: String,
    recordCounter: MemoryWriteCounterRecorder? = nil
) async throws -> Bool {
    recordCounter?(MemoryWriteMetrics.phaseTwoJobs, 1, [("status", reason)])
    return try await store.markGlobalPhase2JobSucceeded(
        ownershipToken: claim.token,
        completionWatermark: completionWatermark,
        selectedOutputs: selectedOutputs
    )
}

public func phaseTwoWatermark(
    claimedWatermark: Int64,
    latestMemories: [Stage1Output]
) -> Int64 {
    let latest = latestMemories
        .map { Int64(floor($0.sourceUpdatedAt.timeIntervalSince1970)) }
        .max() ?? claimedWatermark
    return max(claimedWatermark, latest)
}

public func isFinalMemoryConsolidationAgentStatus(_ status: AgentStatus) -> Bool {
    switch status {
    case .pendingInit, .running, .interrupted:
        return false
    case .completed, .errored, .shutdown, .notFound:
        return true
    }
}

private enum MemoryPhaseTwoConsolidationAgentShutdownRaceResult: Sendable {
    case shutdownCompleted
    case timedOut
}

public func shutdownMemoryPhaseTwoConsolidationAgent(
    threadID: ThreadId,
    timeoutSeconds: UInt64 = memoryStageTwoAgentShutdownTimeoutSeconds,
    shutdownAndWait: @escaping @Sendable () async throws -> Void,
    sleep: @escaping MemoryPhaseTwoSleep = memoryPhaseTwoSleep
) async throws {
    try await withThrowingTaskGroup(
        of: MemoryPhaseTwoConsolidationAgentShutdownRaceResult.self
    ) { group in
        group.addTask {
            try await shutdownAndWait()
            return .shutdownCompleted
        }
        group.addTask {
            await sleep(timeoutSeconds)
            return .timedOut
        }

        defer { group.cancelAll() }

        switch try await group.next() {
        case .shutdownCompleted?:
            return
        case .timedOut?:
            throw MemoryPhaseTwoConsolidationAgentShutdownTimeoutError(threadID: threadID)
        case nil:
            return
        }
    }
}

public func syncPhaseTwoWorkspaceInputs(
    root: URL,
    rawMemories: [Stage1Output],
    now: Date = Date()
) throws {
    let rawMemoryCount = rawMemories.count
    try syncRolloutSummariesFromMemories(
        root: root,
        memories: rawMemories,
        maxRawMemoriesForConsolidation: rawMemoryCount
    )
    try rebuildRawMemoriesFileFromMemories(
        root: root,
        memories: rawMemories,
        maxRawMemoriesForConsolidation: rawMemoryCount
    )
    pruneOldMemoryExtensionResources(root: root, now: now)
}

public func buildMemoryConsolidationAgentConfig(
    from config: CodexRuntimeConfig,
    codexHome: URL
) throws -> CodexRuntimeConfig {
    let root = memoryRoot(codexHome: codexHome)
    let rootPath = try AbsolutePath(absolutePath: root.path)
    var agentConfig = config

    agentConfig.memories.generateMemories = false
    agentConfig.memories.useMemories = false
    agentConfig.includeAppsInstructions = false
    agentConfig.mcpServers = [:]
    agentConfig.approvalPolicy = .never
    agentConfig.model = config.memories.consolidationModel ?? memoryStageTwoModel
    agentConfig.modelReasoningEffort = memoryStageTwoReasoningEffort

    agentConfig.features.set(.spawnCsv, enabled: false)
    agentConfig.features.set(.collab, enabled: false)
    agentConfig.features.set(.memoryTool, enabled: false)
    agentConfig.features.set(.apps, enabled: false)
    agentConfig.features.set(.plugins, enabled: false)
    agentConfig.features.set(.skillMcpDependencyInstall, enabled: false)

    let sandboxPolicy = SandboxPolicy.workspaceWrite(
        writableRoots: [rootPath],
        networkAccess: false,
        excludeTmpdirEnvVar: true,
        excludeSlashTmp: true
    )
    agentConfig.sandboxPolicy = sandboxPolicy
    agentConfig.sandboxMode = nil
    agentConfig.permissionProfile = .fromLegacySandboxPolicy(sandboxPolicy)
    agentConfig.activePermissionProfile = ActivePermissionProfile(id: ":workspace")

    return agentConfig
}

public func buildMemoryConsolidationAgentPrompt(memoryRoot root: URL) -> [UserInput] {
    [.text(buildConsolidationPrompt(memoryRoot: root))]
}

public func memoryPhaseTwoConsolidationStartOptions(
    for request: MemoryPhaseTwoConsolidationRequest
) -> MemoryPhaseTwoConsolidationThreadStartOptions {
    MemoryPhaseTwoConsolidationThreadStartOptions(config: request.agentConfig)
}

public func memoryPhaseTwoConsolidationSubmitOperation(prompt: [UserInput]) -> Op {
    .userInput(
        items: prompt,
        environments: nil,
        finalOutputJSONSchema: nil,
        responsesAPIClientMetadata: nil
    )
}

public func spawnMemoryPhaseTwoConsolidationAgent(
    request: MemoryPhaseTwoConsolidationRequest,
    startAgent: MemoryPhaseTwoConsolidationAgentStarter
) async throws -> MemoryPhaseTwoSpawnedConsolidationAgent {
    let startedAgent = try await startAgent(memoryPhaseTwoConsolidationStartOptions(for: request))
    do {
        try await startedAgent.submit(memoryPhaseTwoConsolidationSubmitOperation(prompt: request.prompt))
    } catch {
        try? await startedAgent.shutdown()
        throw error
    }

    return MemoryPhaseTwoSpawnedConsolidationAgent(
        threadID: startedAgent.threadID,
        status: startedAgent.status,
        tokenUsage: startedAgent.tokenUsage,
        nextEvent: startedAgent.nextEvent,
        shutdown: startedAgent.shutdown
    )
}

public func prepareMemoryPhaseTwoConsolidation(
    threadID: ThreadId,
    store: MemoryPhaseTwoJobStore,
    config: CodexRuntimeConfig,
    codexHome: URL,
    now: Date = Date(),
    recordCounter: MemoryWriteCounterRecorder? = nil
) async -> MemoryPhaseTwoPreparationOutcome {
    let root = memoryRoot(codexHome: codexHome)
    let claim: MemoryPhaseTwoClaim
    do {
        claim = try await claimMemoryPhaseTwoJob(
            threadID: threadID,
            store: store,
            recordCounter: recordCounter
        )
    } catch let error as MemoryPhaseTwoClaimError {
        recordCounter?(MemoryWriteMetrics.phaseTwoJobs, 1, [("status", error.description)])
        return .skipped(error.description)
    } catch {
        recordCounter?(MemoryWriteMetrics.phaseTwoJobs, 1, [("status", MemoryPhaseTwoClaimError.failedClaim.description)])
        return .skipped(MemoryPhaseTwoClaimError.failedClaim.description)
    }

    do {
        try prepareMemoryWorkspace(root: root)
    } catch {
        await recordMemoryPhaseTwoPreparationFailure(
            store: store,
            claim: claim,
            reason: "failed_prepare_workspace",
            recordCounter: recordCounter
        )
        return .failed("failed_prepare_workspace")
    }

    let agentConfig: CodexRuntimeConfig
    do {
        agentConfig = try buildMemoryConsolidationAgentConfig(from: config, codexHome: codexHome)
    } catch {
        await recordMemoryPhaseTwoPreparationFailure(
            store: store,
            claim: claim,
            reason: "failed_sandbox_policy",
            recordCounter: recordCounter
        )
        return .failed("failed_sandbox_policy")
    }

    let rawMemories: [Stage1Output]
    do {
        rawMemories = try await store.getPhase2InputSelection(
            limit: config.memories.maxRawMemoriesForConsolidation,
            maxUnusedDays: config.memories.maxUnusedDays
        )
    } catch {
        await recordMemoryPhaseTwoPreparationFailure(
            store: store,
            claim: claim,
            reason: "failed_load_stage1_outputs",
            recordCounter: recordCounter
        )
        return .failed("failed_load_stage1_outputs")
    }
    let completionWatermark = phaseTwoWatermark(claimedWatermark: claim.watermark, latestMemories: rawMemories)

    do {
        try syncPhaseTwoWorkspaceInputs(root: root, rawMemories: rawMemories, now: now)
    } catch {
        await recordMemoryPhaseTwoPreparationFailure(
            store: store,
            claim: claim,
            reason: "failed_sync_workspace_inputs",
            recordCounter: recordCounter
        )
        return .failed("failed_sync_workspace_inputs")
    }

    let diff: MemoryWorkspaceDiff
    do {
        diff = try memoryWorkspaceDiff(root: root)
    } catch {
        await recordMemoryPhaseTwoPreparationFailure(
            store: store,
            claim: claim,
            reason: "failed_workspace_status",
            recordCounter: recordCounter
        )
        return .failed("failed_workspace_status")
    }

    guard diff.hasChanges else {
        do {
            _ = try await markMemoryPhaseTwoJobSucceeded(
                store: store,
                claim: claim,
                completionWatermark: completionWatermark,
                selectedOutputs: rawMemories,
                reason: "succeeded_no_workspace_changes",
                recordCounter: recordCounter
            )
        } catch {
            return .failed("succeeded_no_workspace_changes")
        }
        return .succeededNoWorkspaceChanges
    }

    do {
        try writeMemoryWorkspaceDiff(root: root, diff: diff)
    } catch {
        await recordMemoryPhaseTwoPreparationFailure(
            store: store,
            claim: claim,
            reason: "failed_workspace_diff_file",
            recordCounter: recordCounter
        )
        return .failed("failed_workspace_diff_file")
    }

    return .readyToSpawn(MemoryPhaseTwoConsolidationRequest(
        claim: claim,
        completionWatermark: completionWatermark,
        selectedOutputs: rawMemories,
        agentConfig: agentConfig,
        prompt: buildMemoryConsolidationAgentPrompt(memoryRoot: root),
        workspaceDiff: diff
    ))
}

public func recordMemoryPhaseTwoAgentSpawned(
    rawMemoryCount: Int,
    recordCounter: MemoryWriteCounterRecorder? = nil
) {
    if rawMemoryCount > 0 {
        recordCounter?(MemoryWriteMetrics.phaseTwoInput, Int64(rawMemoryCount), [])
    }
    recordCounter?(MemoryWriteMetrics.phaseTwoJobs, 1, [("status", "agent_spawned")])
}

public func runMemoryPhaseTwoConsolidation(
    threadID: ThreadId,
    store: MemoryPhaseTwoJobStore,
    config: CodexRuntimeConfig,
    codexHome: URL,
    now: Date = Date(),
    spawnAgent: @escaping @Sendable (
        _ request: MemoryPhaseTwoConsolidationRequest
    ) async throws -> MemoryPhaseTwoSpawnedConsolidationAgent,
    resetBaseline: @Sendable (URL) throws -> Void = { root in
        try resetMemoryWorkspaceBaseline(root: root)
    },
    recordCounter: MemoryWriteCounterRecorder? = nil,
    recordHistogram: MemoryWriteHistogramRecorder? = nil
) async -> MemoryPhaseTwoRunOutcome {
    let preparation = await prepareMemoryPhaseTwoConsolidation(
        threadID: threadID,
        store: store,
        config: config,
        codexHome: codexHome,
        now: now,
        recordCounter: recordCounter
    )

    let request: MemoryPhaseTwoConsolidationRequest
    switch preparation {
    case let .skipped(reason):
        return .skipped(reason)
    case let .failed(reason):
        return .failed(reason)
    case .succeededNoWorkspaceChanges:
        return .succeededNoWorkspaceChanges
    case let .readyToSpawn(spawnRequest):
        request = spawnRequest
    }

    let spawnedAgent: MemoryPhaseTwoSpawnedConsolidationAgent
    do {
        spawnedAgent = try await spawnAgent(request)
    } catch {
        await recordMemoryPhaseTwoPreparationFailure(
            store: store,
            claim: request.claim,
            reason: "failed_spawn_agent",
            recordCounter: recordCounter
        )
        return .failed("failed_spawn_agent")
    }

    recordMemoryPhaseTwoAgentSpawned(
        rawMemoryCount: request.selectedOutputs.count,
        recordCounter: recordCounter
    )

    let finalStatus = await loopMemoryPhaseTwoConsolidationAgent(
        threadID: spawnedAgent.threadID,
        claim: request.claim,
        store: store,
        status: spawnedAgent.status,
        nextEvent: spawnedAgent.nextEvent
    )
    let tokenUsage: TokenUsage? = if case .completed = finalStatus {
        await spawnedAgent.tokenUsage()
    } else {
        nil
    }
    let completion = await completeMemoryPhaseTwoConsolidation(
        finalStatus: finalStatus,
        request: request,
        store: store,
        memoryRoot: memoryRoot(codexHome: codexHome),
        tokenUsage: tokenUsage,
        resetBaseline: resetBaseline,
        recordCounter: recordCounter,
        recordHistogram: recordHistogram
    )
    try? await spawnedAgent.shutdown()
    return .completed(completion)
}

public func runMemoryPhaseTwoConsolidation(
    threadID: ThreadId,
    store: MemoryPhaseTwoJobStore,
    config: CodexRuntimeConfig,
    codexHome: URL,
    now: Date = Date(),
    startAgent: @escaping MemoryPhaseTwoConsolidationAgentStarter,
    resetBaseline: @Sendable (URL) throws -> Void = { root in
        try resetMemoryWorkspaceBaseline(root: root)
    },
    recordCounter: MemoryWriteCounterRecorder? = nil,
    recordHistogram: MemoryWriteHistogramRecorder? = nil
) async -> MemoryPhaseTwoRunOutcome {
    await runMemoryPhaseTwoConsolidation(
        threadID: threadID,
        store: store,
        config: config,
        codexHome: codexHome,
        now: now,
        spawnAgent: { request in
            try await spawnMemoryPhaseTwoConsolidationAgent(request: request, startAgent: startAgent)
        },
        resetBaseline: resetBaseline,
        recordCounter: recordCounter,
        recordHistogram: recordHistogram
    )
}

public func loopMemoryPhaseTwoConsolidationAgent(
    threadID: ThreadId,
    claim: MemoryPhaseTwoClaim,
    store: MemoryPhaseTwoJobStore,
    status: @escaping @Sendable () async -> AgentStatus,
    nextEvent: @escaping @Sendable () async -> MemoryPhaseTwoAgentLoopEvent
) async -> AgentStatus {
    while true {
        let currentStatus = await status()
        if isFinalMemoryConsolidationAgentStatus(currentStatus) {
            return currentStatus
        }

        switch await nextEvent() {
        case .statusPoll:
            continue
        case .sessionTerminated:
            let terminationStatus = await status()
            if isFinalMemoryConsolidationAgentStatus(terminationStatus) {
                return terminationStatus
            }
            return .errored(
                "memory consolidation agent exited before final status: "
                    + terminationStatus.rustDebugDescription
            )
        case .heartbeat:
            do {
                let stillOwnsLock = try await store.heartbeatGlobalPhase2Job(
                    ownershipToken: claim.token,
                    leaseSeconds: memoryStageTwoJobLeaseSeconds
                )
                if !stillOwnsLock {
                    return .errored("lost global phase-2 ownership during heartbeat")
                }
            } catch {
                return .errored("phase-2 heartbeat update failed: \(error)")
            }
        }
    }
}

public func completeMemoryPhaseTwoConsolidation(
    finalStatus: AgentStatus,
    request: MemoryPhaseTwoConsolidationRequest,
    store: MemoryPhaseTwoJobStore,
    memoryRoot root: URL,
    tokenUsage: TokenUsage? = nil,
    resetBaseline: @Sendable (URL) throws -> Void = { root in
        try resetMemoryWorkspaceBaseline(root: root)
    },
    recordCounter: MemoryWriteCounterRecorder? = nil,
    recordHistogram: MemoryWriteHistogramRecorder? = nil
) async -> MemoryPhaseTwoCompletionOutcome {
    guard case .completed = finalStatus else {
        await recordMemoryPhaseTwoPreparationFailure(
            store: store,
            claim: request.claim,
            reason: "failed_agent",
            recordCounter: recordCounter
        )
        return .failed("failed_agent")
    }

    if let tokenUsage {
        recordMemoryPhaseTwoTokenUsage(tokenUsage, recordHistogram: recordHistogram)
    }

    let stillOwnsLock: Bool
    do {
        stillOwnsLock = try await store.heartbeatGlobalPhase2Job(
            ownershipToken: request.claim.token,
            leaseSeconds: memoryStageTwoJobLeaseSeconds
        )
    } catch {
        await recordMemoryPhaseTwoPreparationFailure(
            store: store,
            claim: request.claim,
            reason: "failed_confirm_ownership",
            recordCounter: recordCounter
        )
        return .failed("failed_confirm_ownership")
    }

    guard stillOwnsLock else {
        return .lostOwnership
    }

    do {
        try resetBaseline(root)
    } catch {
        await recordMemoryPhaseTwoPreparationFailure(
            store: store,
            claim: request.claim,
            reason: "failed_workspace_commit",
            recordCounter: recordCounter
        )
        return .failed("failed_workspace_commit")
    }

    do {
        let recorded = try await markMemoryPhaseTwoJobSucceeded(
            store: store,
            claim: request.claim,
            completionWatermark: request.completionWatermark,
            selectedOutputs: request.selectedOutputs,
            reason: "succeeded",
            recordCounter: recordCounter
        )
        return recorded ? .succeeded : .successRecordLost
    } catch {
        return .successRecordLost
    }
}

public func recordMemoryPhaseTwoTokenUsage(
    _ tokenUsage: TokenUsage,
    recordHistogram: MemoryWriteHistogramRecorder? = nil
) {
    recordHistogram?(
        MemoryWriteMetrics.phaseTwoTokenUsage,
        max(tokenUsage.totalTokens, 0),
        [("token_type", "total")]
    )
    recordHistogram?(
        MemoryWriteMetrics.phaseTwoTokenUsage,
        max(tokenUsage.inputTokens, 0),
        [("token_type", "input")]
    )
    recordHistogram?(
        MemoryWriteMetrics.phaseTwoTokenUsage,
        tokenUsage.cachedInput,
        [("token_type", "cached_input")]
    )
    recordHistogram?(
        MemoryWriteMetrics.phaseTwoTokenUsage,
        max(tokenUsage.outputTokens, 0),
        [("token_type", "output")]
    )
    recordHistogram?(
        MemoryWriteMetrics.phaseTwoTokenUsage,
        max(tokenUsage.reasoningOutputTokens, 0),
        [("token_type", "reasoning_output")]
    )
}

private func recordMemoryPhaseTwoPreparationFailure(
    store: MemoryPhaseTwoJobStore,
    claim: MemoryPhaseTwoClaim,
    reason: String,
    recordCounter: MemoryWriteCounterRecorder?
) async {
    _ = try? await markMemoryPhaseTwoJobFailed(
        store: store,
        claim: claim,
        reason: reason,
        recordCounter: recordCounter
    )
}

private extension AgentStatus {
    var rustDebugDescription: String {
        switch self {
        case .pendingInit:
            return "PendingInit"
        case .running:
            return "Running"
        case .interrupted:
            return "Interrupted"
        case let .completed(message):
            return if let message {
                "Completed(\(String(reflecting: message)))"
            } else {
                "Completed(None)"
            }
        case let .errored(message):
            return "Errored(\(String(reflecting: message)))"
        case .shutdown:
            return "Shutdown"
        case .notFound:
            return "NotFound"
        }
    }
}
