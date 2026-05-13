import Foundation

public enum MemoryStartupPipelineOutcome: Equatable, Sendable {
    case skippedIneligible
    case skippedMissingStateDatabase
    case skippedRateLimit
    case completed
}

public struct MemoryStartupPipelineResult: Equatable, Sendable {
    public let outcome: MemoryStartupPipelineOutcome
    public let phaseOneStats: MemoryPhaseOneStats?
    public let phaseTwoOutcome: MemoryPhaseTwoRunOutcome?

    public init(
        outcome: MemoryStartupPipelineOutcome,
        phaseOneStats: MemoryPhaseOneStats? = nil,
        phaseTwoOutcome: MemoryPhaseTwoRunOutcome? = nil
    ) {
        self.outcome = outcome
        self.phaseOneStats = phaseOneStats
        self.phaseTwoOutcome = phaseTwoOutcome
    }
}

public struct MemoryStartupPipelineOptions: Equatable, Sendable {
    public let isEphemeral: Bool
    public let source: SessionSource
    public let features: FeatureStates
    public let hasStateDatabase: Bool

    public init(
        isEphemeral: Bool,
        source: SessionSource,
        features: FeatureStates,
        hasStateDatabase: Bool
    ) {
        self.isEphemeral = isEphemeral
        self.source = source
        self.features = features
        self.hasStateDatabase = hasStateDatabase
    }
}

public func memoryStartupPipelineIsEligible(
    isEphemeral: Bool,
    source: SessionSource,
    features: FeatureStates
) -> Bool {
    !isEphemeral && features.isEnabled(.memoryTool) && !source.isNonRootAgent
}

public func runMemoryStartupPipeline(
    options: MemoryStartupPipelineOptions,
    seedExtensionInstructions: @Sendable () async throws -> Void,
    prunePhaseOneOutputs: @Sendable () async -> Void,
    rateLimitsAllowStartup: @Sendable () async -> Bool,
    runPhaseOne: @Sendable () async -> Void,
    runPhaseTwo: @Sendable () async -> Void,
    recordCounter: MemoryWriteCounterRecorder? = nil
) async -> MemoryStartupPipelineOutcome {
    guard memoryStartupPipelineIsEligible(
        isEphemeral: options.isEphemeral,
        source: options.source,
        features: options.features
    ) else {
        return .skippedIneligible
    }

    guard options.hasStateDatabase else {
        return .skippedMissingStateDatabase
    }

    try? await seedExtensionInstructions()
    await prunePhaseOneOutputs()

    guard await rateLimitsAllowStartup() else {
        recordCounter?(MemoryWriteMetrics.startup, 1, [("status", "skipped_rate_limit")])
        return .skippedRateLimit
    }

    await runPhaseOne()
    await runPhaseTwo()
    return .completed
}

public func runMemoryStartupPipeline(
    options: MemoryStartupPipelineOptions,
    threadID: ThreadId,
    config: CodexRuntimeConfig,
    codexHome: URL,
    auth: AuthDotJSON?,
    allowedSources: [String],
    stageOneModelInfo: ModelInfo,
    stageOneServiceTier: String?,
    stageOneTurnMetadataHeader: String?,
    stateStore: (any MemoryPhaseOneJobStore & MemoryPhaseOneRetentionStore & MemoryPhaseTwoJobStore)?,
    fetchRateLimitSnapshots: @escaping MemoryRateLimitSnapshotsFetcher,
    sampleStageOneOutput: @escaping @Sendable (
        _ claim: Stage1JobClaim,
        _ context: MemoryStageOneRequestContext
    ) async throws -> (MemoryStageOneOutput, TokenUsage?),
    startPhaseTwoAgent: @escaping MemoryPhaseTwoConsolidationAgentStarter,
    seedExtensionInstructions: @Sendable (URL) throws -> Void = { root in
        try seedAdHocMemoryExtensionInstructions(root: root)
    },
    resetBaseline: @Sendable (URL) throws -> Void = { root in
        try resetMemoryWorkspaceBaseline(root: root)
    },
    recordCounter: MemoryWriteCounterRecorder? = nil,
    recordHistogram: MemoryWriteHistogramRecorder? = nil
) async -> MemoryStartupPipelineResult {
    guard memoryStartupPipelineIsEligible(
        isEphemeral: options.isEphemeral,
        source: options.source,
        features: options.features
    ) else {
        return MemoryStartupPipelineResult(outcome: .skippedIneligible)
    }

    guard options.hasStateDatabase, let stateStore else {
        return MemoryStartupPipelineResult(outcome: .skippedMissingStateDatabase)
    }

    let root = memoryRoot(codexHome: codexHome)
    try? seedExtensionInstructions(root)
    _ = await pruneMemoryPhaseOneOutputsForStartup(
        store: stateStore,
        maxUnusedDays: config.memories.maxUnusedDays
    )

    let rateLimitsAllowed = await memoryRateLimitsAllowStartup(
        auth: auth,
        chatGPTBaseURL: config.chatgptBaseURL,
        minRemainingPercent: config.memories.minRateLimitRemainingPercent,
        fetchSnapshots: fetchRateLimitSnapshots
    )
    guard rateLimitsAllowed else {
        recordCounter?(MemoryWriteMetrics.startup, 1, [("status", "skipped_rate_limit")])
        return MemoryStartupPipelineResult(outcome: .skippedRateLimit)
    }

    let stageOneContext = buildMemoryStageOneRequestContext(
        config: config,
        modelInfo: stageOneModelInfo,
        configSnapshotServiceTier: stageOneServiceTier,
        turnMetadataHeader: stageOneTurnMetadataHeader
    )
    let phaseOneStats = await runMemoryPhaseOneExtraction(
        currentThreadID: threadID,
        memoriesConfig: config.memories,
        allowedSources: allowedSources,
        store: stateStore,
        sample: { claim in
            try await sampleStageOneOutput(claim, stageOneContext)
        },
        recordCounter: recordCounter,
        recordHistogram: recordHistogram
    )
    let phaseTwoOutcome = await runMemoryPhaseTwoConsolidation(
        threadID: threadID,
        store: stateStore,
        config: config,
        codexHome: codexHome,
        startAgent: startPhaseTwoAgent,
        resetBaseline: resetBaseline,
        recordCounter: recordCounter,
        recordHistogram: recordHistogram
    )
    return MemoryStartupPipelineResult(
        outcome: .completed,
        phaseOneStats: phaseOneStats,
        phaseTwoOutcome: phaseTwoOutcome
    )
}

public func runMemoryStartupPipeline(
    options: MemoryStartupPipelineOptions,
    threadID: ThreadId,
    config: CodexRuntimeConfig,
    codexHome: URL,
    auth: AuthDotJSON?,
    allowedSources: [String],
    stageOneModelInfo: ModelInfo,
    stageOneServiceTier: String?,
    stageOneTurnMetadataHeader: String?,
    stateStore: (any MemoryPhaseOneJobStore & MemoryPhaseOneRetentionStore & MemoryPhaseTwoJobStore)?,
    fetchRateLimitSnapshots: @escaping MemoryRateLimitSnapshotsFetcher,
    streamStageOnePrompt: @escaping @Sendable (
        _ prompt: Prompt,
        _ context: MemoryStageOneRequestContext
    ) async throws -> (String, TokenUsage?),
    startPhaseTwoAgent: @escaping MemoryPhaseTwoConsolidationAgentStarter,
    seedExtensionInstructions: @Sendable (URL) throws -> Void = { root in
        try seedAdHocMemoryExtensionInstructions(root: root)
    },
    resetBaseline: @Sendable (URL) throws -> Void = { root in
        try resetMemoryWorkspaceBaseline(root: root)
    },
    recordCounter: MemoryWriteCounterRecorder? = nil,
    recordHistogram: MemoryWriteHistogramRecorder? = nil
) async -> MemoryStartupPipelineResult {
    await runMemoryStartupPipeline(
        options: options,
        threadID: threadID,
        config: config,
        codexHome: codexHome,
        auth: auth,
        allowedSources: allowedSources,
        stageOneModelInfo: stageOneModelInfo,
        stageOneServiceTier: stageOneServiceTier,
        stageOneTurnMetadataHeader: stageOneTurnMetadataHeader,
        stateStore: stateStore,
        fetchRateLimitSnapshots: fetchRateLimitSnapshots,
        sampleStageOneOutput: { claim, context in
            try await sampleMemoryPhaseOneOutput(
                modelInfo: context.modelInfo,
                rolloutPath: URL(fileURLWithPath: claim.thread.rolloutPath, isDirectory: false),
                rolloutCwd: URL(fileURLWithPath: claim.thread.cwd, isDirectory: true),
                streamPrompt: { prompt in
                    try await streamStageOnePrompt(prompt, context)
                }
            )
        },
        startPhaseTwoAgent: startPhaseTwoAgent,
        seedExtensionInstructions: seedExtensionInstructions,
        resetBaseline: resetBaseline,
        recordCounter: recordCounter,
        recordHistogram: recordHistogram
    )
}
