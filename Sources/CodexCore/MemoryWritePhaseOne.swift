import Foundation

public let memoryStageOneModel = "gpt-5.4-mini"
public let memoryStageOneReasoningEffort: ReasoningEffort = .low
public let memoryStageOneConcurrencyLimit = 8
public let memoryStageOneJobLeaseSeconds: Int64 = 3_600
public let memoryStageOneJobRetryDelaySeconds: Int64 = 3_600
public let memoryStageOneThreadScanLimit = 5_000
public let memoryStageOnePruneBatchSize = 200
public let memoryStageOneSystemPrompt = loadMemoryStageOneResource(
    name: "stage_one_system",
    subdirectory: "MemoryWrite"
)

public struct MemoryStageOneOutput: Equatable, Decodable, Sendable {
    public var rawMemory: String
    public var rolloutSummary: String
    public var rolloutSlug: String?

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case rawMemory = "raw_memory"
        case rolloutSummary = "rollout_summary"
        case rolloutSlug = "rollout_slug"
    }

    public init(rawMemory: String, rolloutSummary: String, rolloutSlug: String?) {
        self.rawMemory = rawMemory
        self.rolloutSummary = rolloutSummary
        self.rolloutSlug = rolloutSlug
    }

    public init(from decoder: Decoder) throws {
        let dynamicContainer = try decoder.container(keyedBy: MemoryStageOneOutputDynamicCodingKey.self)
        let knownKeys = Set(CodingKeys.allCases.map(\.stringValue))
        let unknownKeys = Set(dynamicContainer.allKeys.map(\.stringValue)).subtracting(knownKeys)
        if let unknownKey = unknownKeys.sorted().first {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "unknown field `\(unknownKey)`"
                )
            )
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        rawMemory = try container.decode(String.self, forKey: .rawMemory)
        rolloutSummary = try container.decode(String.self, forKey: .rolloutSummary)
        rolloutSlug = try container.decodeIfPresent(String.self, forKey: .rolloutSlug)
    }
}

public struct MemoryStageOneRequestContext: Equatable, Sendable {
    public var modelInfo: ModelInfo
    public var reasoningEffort: ReasoningEffort?
    public var reasoningSummary: ReasoningSummary
    public var serviceTier: String?
    public var turnMetadataHeader: String?

    public init(
        modelInfo: ModelInfo,
        reasoningEffort: ReasoningEffort? = memoryStageOneReasoningEffort,
        reasoningSummary: ReasoningSummary,
        serviceTier: String? = nil,
        turnMetadataHeader: String? = nil
    ) {
        self.modelInfo = modelInfo
        self.reasoningEffort = reasoningEffort
        self.reasoningSummary = reasoningSummary
        self.serviceTier = serviceTier
        self.turnMetadataHeader = turnMetadataHeader
    }
}

public struct MemoryStageOneStreamResult: Equatable, Sendable {
    public var output: String
    public var tokenUsage: TokenUsage?

    public init(output: String, tokenUsage: TokenUsage?) {
        self.output = output
        self.tokenUsage = tokenUsage
    }
}

public func memoryStageOneModelName(config: CodexRuntimeConfig) -> String {
    config.memories.extractModel ?? memoryStageOneModel
}

public func buildMemoryStageOneRequestContext(
    config: CodexRuntimeConfig,
    modelInfo: ModelInfo,
    configSnapshotServiceTier: String?,
    turnMetadataHeader: String?
) -> MemoryStageOneRequestContext {
    MemoryStageOneRequestContext(
        modelInfo: modelInfo,
        reasoningEffort: memoryStageOneReasoningEffort,
        reasoningSummary: config.modelReasoningSummary ?? modelInfo.defaultReasoningSummary,
        serviceTier: configSnapshotServiceTier,
        turnMetadataHeader: turnMetadataHeader
    )
}

private struct MemoryStageOneOutputDynamicCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}

public enum MemoryWritePhaseOneError: Error, Equatable, CustomStringConvertible, Sendable {
    case serializeRolloutMemory(String)
    case streamStageOnePrompt(String)

    public var description: String {
        switch self {
        case let .serializeRolloutMemory(message):
            return "failed to serialize rollout memory: \(message)"
        case let .streamStageOnePrompt(message):
            return "failed to stream stage-1 memory prompt: \(message)"
        }
    }
}

public enum MemoryPhaseOneJobOutcome: Equatable, Sendable {
    case succeededWithOutput
    case succeededNoOutput
    case failed
}

public struct MemoryPhaseOneJobResult: Equatable, Sendable {
    public let outcome: MemoryPhaseOneJobOutcome
    public let tokenUsage: TokenUsage?

    public init(outcome: MemoryPhaseOneJobOutcome, tokenUsage: TokenUsage?) {
        self.outcome = outcome
        self.tokenUsage = tokenUsage
    }
}

public struct MemoryPhaseOneStats: Equatable, Sendable {
    public let claimed: Int
    public let succeededWithOutput: Int
    public let succeededNoOutput: Int
    public let failed: Int
    public let totalTokenUsage: TokenUsage?

    public init(
        claimed: Int,
        succeededWithOutput: Int,
        succeededNoOutput: Int,
        failed: Int,
        totalTokenUsage: TokenUsage?
    ) {
        self.claimed = claimed
        self.succeededWithOutput = succeededWithOutput
        self.succeededNoOutput = succeededNoOutput
        self.failed = failed
        self.totalTokenUsage = totalTokenUsage
    }
}

/// Storage boundary used by the Phase 1 memory extraction runner.
///
/// `SQLiteAgentGraphStore` is the production implementation. Callers may rely on
/// implementations preserving Rust's ownership-token checks for startup claims,
/// success, no-output success, and retryable failure transitions.
public protocol MemoryPhaseOneJobStore: Sendable {
    func claimStage1JobsForStartup(
        currentThreadID: ThreadId,
        params: Stage1StartupClaimParams
    ) async throws -> [Stage1JobClaim]

    func markStage1JobSucceeded(
        threadID: ThreadId,
        ownershipToken: String,
        sourceUpdatedAt: Int64,
        rawMemory: String,
        rolloutSummary: String,
        rolloutSlug: String?
    ) async throws -> Bool

    func markStage1JobSucceededNoOutput(
        threadID: ThreadId,
        ownershipToken: String
    ) async throws -> Bool

    func markStage1JobFailed(
        threadID: ThreadId,
        ownershipToken: String,
        reason: String,
        retryDelaySeconds: Int64
    ) async throws -> Bool
}

/// Storage boundary for Phase 1 output retention pruning during memory startup.
///
/// Production storage removes stale, unused stage-1 outputs in bounded batches before
/// any model-backed memory extraction runs.
public protocol MemoryPhaseOneRetentionStore: Sendable {
    func pruneStage1OutputsForRetention(maxUnusedDays: Int64, limit: Int) async throws -> Int
}

extension SQLiteAgentGraphStore: MemoryPhaseOneJobStore {
    public func markStage1JobFailed(
        threadID: ThreadId,
        ownershipToken: String,
        reason: String,
        retryDelaySeconds: Int64
    ) async throws -> Bool {
        try await markStage1JobFailed(
            threadID: threadID,
            ownershipToken: ownershipToken,
            failureReason: reason,
            retryDelaySeconds: retryDelaySeconds
        )
    }
}

extension SQLiteAgentGraphStore: MemoryPhaseOneRetentionStore {}

public func memoryStageOneOutputSchema() -> JSONValue {
    .object([
        "type": .string("object"),
        "properties": .object([
            "rollout_summary": .object(["type": .string("string")]),
            "rollout_slug": .object(["type": .array([.string("string"), .string("null")])]),
            "raw_memory": .object(["type": .string("string")])
        ]),
        "required": .array([
            .string("rollout_summary"),
            .string("rollout_slug"),
            .string("raw_memory")
        ]),
        "additionalProperties": .bool(false)
    ])
}

public func loadMemoryStageOneRolloutItems(rolloutPath: URL) throws -> [RolloutItem] {
    try RolloutRecorder.getRolloutHistory(path: rolloutPath)
        .rolloutItems
        .map(memoryRolloutItem)
}

public func buildMemoryStageOnePrompt(
    modelInfo: ModelInfo,
    rolloutPath: URL,
    rolloutCwd: URL,
    rolloutItems: [RolloutItem]
) throws -> Prompt {
    let rolloutContents = try serializeFilteredRolloutResponseItemsForMemories(rolloutItems)
    return Prompt(
        input: [
            .message(
                role: "user",
                content: [
                    .inputText(text: buildStageOneInputMessage(
                        modelInfo: modelInfo,
                        rolloutPath: rolloutPath,
                        rolloutCwd: rolloutCwd,
                        rolloutContents: rolloutContents
                    ))
                ]
            )
        ],
        baseInstructionsOverride: memoryStageOneSystemPrompt,
        outputSchema: memoryStageOneOutputSchema()
    )
}

public func memoryStageOneInstructions(
    prompt: Prompt,
    context: MemoryStageOneRequestContext
) -> String {
    prompt.baseInstructionsOverride ?? context.modelInfo.modelInstructions(personality: nil)
}

public func memoryStageOneResponsesOptions(
    context: MemoryStageOneRequestContext,
    prompt: Prompt,
    verbosity: Verbosity? = nil
) -> ResponsesOptions {
    ResponsesOptions(
        reasoning: ResponsesAPIReasoning(
            effort: context.reasoningEffort,
            summary: context.reasoningSummary
        ),
        serviceTier: context.serviceTier,
        text: ResponsesAPITextControls.createForRequest(
            verbosity: verbosity ?? context.modelInfo.defaultVerbosity,
            outputSchema: prompt.outputSchema
        ),
        inputModalities: context.modelInfo.inputModalities,
        turnMetadataHeader: context.turnMetadataHeader
    )
}

public func collectMemoryStageOneStreamResult(
    _ results: ResponseEventResults
) throws -> MemoryStageOneStreamResult {
    var output = ""
    var tokenUsage: TokenUsage?

    for result in results {
        let event = try result.get()
        switch event {
        case let .outputTextDelta(delta):
            output.append(delta)
        case let .outputItemDone(item):
            guard output.isEmpty,
                  case let .message(_, _, content, _) = item,
                  let text = Compact.contentItemsToText(content)
            else {
                continue
            }
            output.append(text)
        case let .completed(_, usage, _):
            tokenUsage = usage
            return MemoryStageOneStreamResult(output: output, tokenUsage: tokenUsage)
        default:
            continue
        }
    }

    return MemoryStageOneStreamResult(output: output, tokenUsage: tokenUsage)
}

public typealias MemoryStageOnePromptStreamer = @Sendable (
    _ model: String,
    _ instructions: String,
    _ prompt: Prompt,
    _ options: ResponsesOptions
) async -> Result<ResponseEventResults, APIError>

public func streamMemoryStageOnePrompt(
    prompt: Prompt,
    context: MemoryStageOneRequestContext,
    verbosity: Verbosity? = nil,
    streamPrompt: MemoryStageOnePromptStreamer
) async throws -> (String, TokenUsage?) {
    let result = await streamPrompt(
        context.modelInfo.slug,
        memoryStageOneInstructions(prompt: prompt, context: context),
        prompt,
        memoryStageOneResponsesOptions(context: context, prompt: prompt, verbosity: verbosity)
    )

    let events = try result.get()
    let streamResult = try collectMemoryStageOneStreamResult(events)
    return (streamResult.output, streamResult.tokenUsage)
}

public func streamMemoryStageOnePrompt<Transport: APITransport, Auth: APIAuthProvider>(
    prompt: Prompt,
    context: MemoryStageOneRequestContext,
    verbosity: Verbosity? = nil,
    responsesClient: ResponsesClient<Transport, Auth>
) async throws -> (String, TokenUsage?) {
    let result = await responsesClient.streamPrompt(
        model: context.modelInfo.slug,
        instructions: memoryStageOneInstructions(prompt: prompt, context: context),
        prompt: prompt,
        options: memoryStageOneResponsesOptions(context: context, prompt: prompt, verbosity: verbosity)
    )
    let events = try result.get()
    let streamResult = try collectMemoryStageOneStreamResult(events)
    return (streamResult.output, streamResult.tokenUsage)
}

public func sampleMemoryPhaseOneOutput(
    modelInfo: ModelInfo,
    rolloutPath: URL,
    rolloutCwd: URL,
    loadRolloutItems: @Sendable (URL) async throws -> [RolloutItem] = { url in
        try loadMemoryStageOneRolloutItems(rolloutPath: url)
    },
    streamPrompt: @Sendable (Prompt) async throws -> (String, TokenUsage?)
) async throws -> (MemoryStageOneOutput, TokenUsage?) {
    let rolloutItems = try await loadRolloutItems(rolloutPath)
    let prompt = try buildMemoryStageOnePrompt(
        modelInfo: modelInfo,
        rolloutPath: rolloutPath,
        rolloutCwd: rolloutCwd,
        rolloutItems: rolloutItems
    )
    let result: String
    let tokenUsage: TokenUsage?
    do {
        (result, tokenUsage) = try await streamPrompt(prompt)
    } catch {
        throw MemoryWritePhaseOneError.streamStageOnePrompt(String(describing: error))
    }

    var output = try JSONDecoder().decode(MemoryStageOneOutput.self, from: Data(result.utf8))
    output.rawMemory = redactSecretsForMemories(output.rawMemory)
    output.rolloutSummary = redactSecretsForMemories(output.rolloutSummary)
    output.rolloutSlug = output.rolloutSlug.map(redactSecretsForMemories)
    return (output, tokenUsage)
}

public func claimMemoryPhaseOneStartupJobs(
    currentThreadID: ThreadId,
    maxRolloutsPerStartup: Int,
    maxRolloutAgeDays: Int64,
    minRolloutIdleHours: Int64,
    allowedSources: [String],
    store: MemoryPhaseOneJobStore,
    recordCounter: MemoryWriteCounterRecorder? = nil
) async -> [Stage1JobClaim]? {
    do {
        let claims = try await store.claimStage1JobsForStartup(
            currentThreadID: currentThreadID,
            params: Stage1StartupClaimParams(
                scanLimit: memoryStageOneThreadScanLimit,
                maxClaimed: maxRolloutsPerStartup,
                maxAgeDays: maxRolloutAgeDays,
                minRolloutIdleHours: minRolloutIdleHours,
                allowedSources: allowedSources,
                leaseSeconds: memoryStageOneJobLeaseSeconds
            )
        )
        if claims.isEmpty {
            recordCounter?(MemoryWriteMetrics.phaseOneJobs, 1, [("status", "skipped_no_candidates")])
        }
        return claims
    } catch {
        return nil
    }
}

public func pruneMemoryPhaseOneOutputsForStartup(
    store: MemoryPhaseOneRetentionStore,
    maxUnusedDays: Int64
) async -> Int? {
    do {
        return try await store.pruneStage1OutputsForRetention(
            maxUnusedDays: maxUnusedDays,
            limit: memoryStageOnePruneBatchSize
        )
    } catch {
        return nil
    }
}

public func runMemoryPhaseOneExtraction(
    currentThreadID: ThreadId,
    memoriesConfig: MemoriesConfig,
    allowedSources: [String],
    store: MemoryPhaseOneJobStore,
    sample: @Sendable @escaping (Stage1JobClaim) async throws -> (MemoryStageOneOutput, TokenUsage?),
    recordCounter: MemoryWriteCounterRecorder? = nil,
    recordHistogram: MemoryWriteHistogramRecorder? = nil
) async -> MemoryPhaseOneStats? {
    guard let claims = await claimMemoryPhaseOneStartupJobs(
        currentThreadID: currentThreadID,
        maxRolloutsPerStartup: memoriesConfig.maxRolloutsPerStartup,
        maxRolloutAgeDays: memoriesConfig.maxRolloutAgeDays,
        minRolloutIdleHours: memoriesConfig.minRolloutIdleHours,
        allowedSources: allowedSources,
        store: store,
        recordCounter: recordCounter
    ) else {
        return nil
    }

    guard !claims.isEmpty else {
        let stats = MemoryPhaseOneStats(
            claimed: 0,
            succeededWithOutput: 0,
            succeededNoOutput: 0,
            failed: 0,
            totalTokenUsage: nil
        )
        emitMemoryPhaseOneMetrics(stats, recordCounter: recordCounter, recordHistogram: recordHistogram)
        return stats
    }

    let results = await runMemoryPhaseOneJobs(claims: claims, store: store, sample: sample)
    let stats = aggregateMemoryPhaseOneStats(results)
    emitMemoryPhaseOneMetrics(stats, recordCounter: recordCounter, recordHistogram: recordHistogram)
    return stats
}

public func runMemoryPhaseOneJob(
    claim: Stage1JobClaim,
    store: MemoryPhaseOneJobStore,
    sample: @Sendable (Stage1JobClaim) async throws -> (MemoryStageOneOutput, TokenUsage?)
) async -> MemoryPhaseOneJobResult {
    let stageOneOutput: MemoryStageOneOutput
    let tokenUsage: TokenUsage?
    do {
        (stageOneOutput, tokenUsage) = try await sample(claim)
    } catch {
        _ = try? await store.markStage1JobFailed(
            threadID: claim.thread.id,
            ownershipToken: claim.ownershipToken,
            reason: String(describing: error),
            retryDelaySeconds: memoryStageOneJobRetryDelaySeconds
        )
        return MemoryPhaseOneJobResult(outcome: .failed, tokenUsage: nil)
    }

    if stageOneOutput.rawMemory.isEmpty || stageOneOutput.rolloutSummary.isEmpty {
        let succeeded = (try? await store.markStage1JobSucceededNoOutput(
            threadID: claim.thread.id,
            ownershipToken: claim.ownershipToken
        )) ?? false
        return MemoryPhaseOneJobResult(
            outcome: succeeded ? .succeededNoOutput : .failed,
            tokenUsage: tokenUsage
        )
    }

    let succeeded = (try? await store.markStage1JobSucceeded(
        threadID: claim.thread.id,
        ownershipToken: claim.ownershipToken,
        sourceUpdatedAt: Int64(claim.thread.updatedAt.timeIntervalSince1970),
        rawMemory: stageOneOutput.rawMemory,
        rolloutSummary: stageOneOutput.rolloutSummary,
        rolloutSlug: stageOneOutput.rolloutSlug
    )) ?? false
    return MemoryPhaseOneJobResult(
        outcome: succeeded ? .succeededWithOutput : .failed,
        tokenUsage: tokenUsage
    )
}

private func runMemoryPhaseOneJobs(
    claims: [Stage1JobClaim],
    store: MemoryPhaseOneJobStore,
    sample: @Sendable @escaping (Stage1JobClaim) async throws -> (MemoryStageOneOutput, TokenUsage?)
) async -> [MemoryPhaseOneJobResult] {
    await withTaskGroup(of: MemoryPhaseOneJobResult.self) { group in
        var iterator = claims.makeIterator()
        var submitted = 0
        let limit = max(1, memoryStageOneConcurrencyLimit)

        while submitted < limit, let claim = iterator.next() {
            submitted += 1
            group.addTask {
                await runMemoryPhaseOneJob(claim: claim, store: store, sample: sample)
            }
        }

        var results: [MemoryPhaseOneJobResult] = []
        while let result = await group.next() {
            results.append(result)
            if let claim = iterator.next() {
                group.addTask {
                    await runMemoryPhaseOneJob(claim: claim, store: store, sample: sample)
                }
            }
        }

        return results
    }
}

public func aggregateMemoryPhaseOneStats(_ results: [MemoryPhaseOneJobResult]) -> MemoryPhaseOneStats {
    var succeededWithOutput = 0
    var succeededNoOutput = 0
    var failed = 0
    var totalTokenUsage = TokenUsage()
    var hasTokenUsage = false

    for result in results {
        switch result.outcome {
        case .succeededWithOutput:
            succeededWithOutput += 1
        case .succeededNoOutput:
            succeededNoOutput += 1
        case .failed:
            failed += 1
        }

        if let tokenUsage = result.tokenUsage {
            totalTokenUsage.addAssign(tokenUsage)
            hasTokenUsage = true
        }
    }

    return MemoryPhaseOneStats(
        claimed: results.count,
        succeededWithOutput: succeededWithOutput,
        succeededNoOutput: succeededNoOutput,
        failed: failed,
        totalTokenUsage: hasTokenUsage ? totalTokenUsage : nil
    )
}

public func emitMemoryPhaseOneMetrics(
    _ stats: MemoryPhaseOneStats,
    recordCounter: MemoryWriteCounterRecorder? = nil,
    recordHistogram: MemoryWriteHistogramRecorder? = nil
) {
    if stats.claimed > 0 {
        recordCounter?(MemoryWriteMetrics.phaseOneJobs, Int64(stats.claimed), [("status", "claimed")])
    }
    if stats.succeededWithOutput > 0 {
        recordCounter?(MemoryWriteMetrics.phaseOneJobs, Int64(stats.succeededWithOutput), [("status", "succeeded")])
        recordCounter?(MemoryWriteMetrics.phaseOneOutput, Int64(stats.succeededWithOutput), [])
    }
    if stats.succeededNoOutput > 0 {
        recordCounter?(
            MemoryWriteMetrics.phaseOneJobs,
            Int64(stats.succeededNoOutput),
            [("status", "succeeded_no_output")]
        )
    }
    if stats.failed > 0 {
        recordCounter?(MemoryWriteMetrics.phaseOneJobs, Int64(stats.failed), [("status", "failed")])
    }
    if let tokenUsage = stats.totalTokenUsage {
        recordMemoryPhaseOneTokenUsage(tokenUsage, recordHistogram: recordHistogram)
    }
}

public func recordMemoryPhaseOneTokenUsage(
    _ tokenUsage: TokenUsage,
    recordHistogram: MemoryWriteHistogramRecorder? = nil
) {
    recordHistogram?(
        MemoryWriteMetrics.phaseOneTokenUsage,
        max(tokenUsage.totalTokens, 0),
        [("token_type", "total")]
    )
    recordHistogram?(
        MemoryWriteMetrics.phaseOneTokenUsage,
        max(tokenUsage.inputTokens, 0),
        [("token_type", "input")]
    )
    recordHistogram?(
        MemoryWriteMetrics.phaseOneTokenUsage,
        tokenUsage.cachedInput,
        [("token_type", "cached_input")]
    )
    recordHistogram?(
        MemoryWriteMetrics.phaseOneTokenUsage,
        max(tokenUsage.outputTokens, 0),
        [("token_type", "output")]
    )
    recordHistogram?(
        MemoryWriteMetrics.phaseOneTokenUsage,
        max(tokenUsage.reasoningOutputTokens, 0),
        [("token_type", "reasoning_output")]
    )
}

public func serializeFilteredRolloutResponseItemsForMemories(_ items: [RolloutItem]) throws -> String {
    let filtered = items.compactMap { item -> ResponseItem? in
        guard case let .responseItem(responseItem) = item else {
            return nil
        }
        return sanitizeResponseItemForMemories(responseItem)
    }

    do {
        let data = try JSONEncoder().encode(filtered)
        guard let json = String(data: data, encoding: .utf8) else {
            throw EncodingError.invalidValue(
                filtered,
                EncodingError.Context(
                    codingPath: [],
                    debugDescription: "encoded rollout memory was not valid UTF-8"
                )
            )
        }
        return redactSecretsForMemories(json)
    } catch {
        throw MemoryWritePhaseOneError.serializeRolloutMemory(String(describing: error))
    }
}

func sanitizeResponseItemForMemories(_ item: ResponseItem) -> ResponseItem? {
    switch item {
    case let .message(id, role, content, phase):
        if role == "developer" {
            return nil
        }
        if role != "user" {
            return item
        }

        let filteredContent = content.filter { !isMemoryExcludedContextualUserFragment($0) }
        if filteredContent.isEmpty {
            return nil
        }
        return .message(id: id, role: role, content: filteredContent, phase: phase)

    default:
        return RolloutPolicy.shouldPersistResponseItemForMemories(item) ? item : nil
    }
}

func isMemoryExcludedContextualUserFragment(_ item: ContentItem) -> Bool {
    guard case let .inputText(text) = item else {
        return false
    }
    return UserInstructions.matchesText(text) || SkillInstructions.matchesText(text)
}

private func redactSecretsForMemories(_ input: String) -> String {
    input.replacing(
        /sk-[A-Za-z0-9]{20,}/,
        with: "[REDACTED_SECRET]"
    )
}

private func memoryRolloutItem(_ item: RolloutRecordItem) -> RolloutItem {
    switch item {
    case .sessionMeta:
        return .sessionMeta
    case let .responseItem(responseItem):
        return .responseItem(responseItem)
    case .compacted:
        return .compacted
    case .turnContext:
        return .turnContext
    case let .eventMsg(event):
        return .eventMessage(RolloutPolicy.eventKind(for: event))
    }
}

private func loadMemoryStageOneResource(name: String, subdirectory: String) -> String {
    let url = Bundle.module.url(forResource: name, withExtension: "md", subdirectory: subdirectory)
        ?? Bundle.module.url(forResource: name, withExtension: "md")
    guard let url else {
        preconditionFailure("Missing bundled memory write resource \(subdirectory)/\(name).md")
    }
    do {
        return try String(contentsOf: url, encoding: .utf8)
    } catch {
        preconditionFailure("Unable to read bundled memory write resource \(url.path): \(error)")
    }
}
