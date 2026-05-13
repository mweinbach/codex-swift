import Foundation

public let memoryStageTwoModel = "gpt-5.4"
public let memoryStageTwoReasoningEffort: ReasoningEffort = .medium
public let memoryStageTwoJobLeaseSeconds: Int64 = 3_600
public let memoryStageTwoJobRetryDelaySeconds: Int64 = 3_600
public let memoryStageTwoJobHeartbeatSeconds: UInt64 = 90

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

public protocol MemoryPhaseTwoJobStore: Sendable {
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
