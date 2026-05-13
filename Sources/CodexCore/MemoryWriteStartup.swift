import Foundation

public enum MemoryStartupPipelineOutcome: Equatable, Sendable {
    case skippedIneligible
    case skippedMissingStateDatabase
    case skippedRateLimit
    case completed
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
