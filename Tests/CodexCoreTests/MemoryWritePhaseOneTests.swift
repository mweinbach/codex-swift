@testable import CodexCore
import XCTest

final class MemoryWritePhaseOneTests: XCTestCase {
    func testStageOneConstantsMirrorRust() {
        XCTAssertEqual(memoryStageOneModel, "gpt-5.4-mini")
        XCTAssertEqual(memoryStageOneReasoningEffort, .low)
        XCTAssertEqual(memoryStageOneConcurrencyLimit, 8)
        XCTAssertEqual(memoryStageOneJobLeaseSeconds, 3_600)
        XCTAssertEqual(memoryStageOneJobRetryDelaySeconds, 3_600)
        XCTAssertEqual(memoryStageOneThreadScanLimit, 5_000)
        XCTAssertEqual(memoryStageOnePruneBatchSize, 200)
    }

    func testOutputSchemaRequiresRolloutSlugAndKeepsItNullableLikeRust() throws {
        try XCTAssertJSONObjectEqual(memoryStageOneOutputSchema(), [
            "type": "object",
            "properties": [
                "rollout_summary": ["type": "string"],
                "rollout_slug": ["type": ["string", "null"]],
                "raw_memory": ["type": "string"]
            ],
            "required": ["rollout_summary", "rollout_slug", "raw_memory"],
            "additionalProperties": false
        ])
    }

    func testStageOneOutputDecodesMissingSlugAsNilAndRejectsUnknownFields() throws {
        let output = try JSONDecoder().decode(MemoryStageOneOutput.self, from: Data(#"""
        {
          "raw_memory": "details",
          "rollout_summary": "summary"
        }
        """#.utf8))
        XCTAssertEqual(output, MemoryStageOneOutput(rawMemory: "details", rolloutSummary: "summary", rolloutSlug: nil))

        XCTAssertThrowsError(try JSONDecoder().decode(MemoryStageOneOutput.self, from: Data(#"""
        {
          "raw_memory": "details",
          "rollout_summary": "summary",
          "rollout_slug": null,
          "extra": true
        }
        """#.utf8)))
    }

    func testStageOneSystemPromptLoadsBundledRustTemplate() {
        XCTAssertTrue(memoryStageOneSystemPrompt.hasPrefix("## Memory Writing Agent: Phase 1 (Single Rollout)"))
        XCTAssertTrue(memoryStageOneSystemPrompt.contains("Return exactly one JSON object with required keys:"))
        XCTAssertTrue(memoryStageOneSystemPrompt.contains("No prose outside JSON."))
    }

    func testBuildMemoryStageOnePromptWrapsFilteredRolloutWithSchemaAndSystemPrompt() throws {
        let prompt = try buildMemoryStageOnePrompt(
            modelInfo: minimalModelInfo(),
            rolloutPath: URL(fileURLWithPath: "/tmp/rollout.jsonl"),
            rolloutCwd: URL(fileURLWithPath: "/repo"),
            rolloutItems: [
                .sessionMeta,
                .responseItem(.message(role: "developer", content: [.inputText(text: "drop")])),
                .responseItem(.message(role: "user", content: [.inputText(text: "keep")]))
            ]
        )

        XCTAssertEqual(prompt.baseInstructionsOverride, memoryStageOneSystemPrompt)
        XCTAssertEqual(prompt.outputSchema, memoryStageOneOutputSchema())
        XCTAssertEqual(prompt.tools, [])
        XCTAssertFalse(prompt.parallelToolCalls)
        XCTAssertEqual(prompt.input.count, 1)
        guard case let .message(_, role, content, _) = prompt.input[0],
              case let .inputText(text) = content.first else {
            return XCTFail("expected single user text message")
        }
        XCTAssertEqual(role, "user")
        XCTAssertTrue(text.contains("rollout_path: /tmp/rollout.jsonl"))
        XCTAssertTrue(text.contains("rollout_cwd: /repo"))
        XCTAssertTrue(text.contains(#""role":"user""#))
        XCTAssertTrue(text.contains("keep"))
        XCTAssertFalse(text.contains("drop"))
    }

    func testSampleMemoryPhaseOneOutputStreamsDecodesAndRedactsLikeRust() async throws {
        let secret = "sk-" + String(repeating: "B", count: 20)
        let usage = TokenUsage(inputTokens: 3, outputTokens: 4, totalTokens: 7)
        let streamedPrompts = PromptRecorder()

        let (output, tokenUsage) = try await sampleMemoryPhaseOneOutput(
            modelInfo: minimalModelInfo(),
            rolloutPath: URL(fileURLWithPath: "/tmp/rollout.jsonl"),
            rolloutCwd: URL(fileURLWithPath: "/repo"),
            loadRolloutItems: { path in
                XCTAssertEqual(path.path, "/tmp/rollout.jsonl")
                return [
                    .responseItem(.message(role: "user", content: [.inputText(text: "please remember")]))
                ]
            },
            streamPrompt: { prompt in
                await streamedPrompts.append(prompt)
                return (#"""
                {
                  "raw_memory": "raw \#(secret)",
                  "rollout_summary": "summary \#(secret)",
                  "rollout_slug": "slug-\#(secret)"
                }
                """#, usage)
            }
        )

        XCTAssertEqual(output, MemoryStageOneOutput(
            rawMemory: "raw [REDACTED_SECRET]",
            rolloutSummary: "summary [REDACTED_SECRET]",
            rolloutSlug: "slug-[REDACTED_SECRET]"
        ))
        XCTAssertEqual(tokenUsage, usage)
        let prompts = await streamedPrompts.prompts
        XCTAssertEqual(prompts.count, 1)
        XCTAssertEqual(prompts.first?.baseInstructionsOverride, memoryStageOneSystemPrompt)
    }

    func testSampleMemoryPhaseOneOutputWrapsStreamErrorsWithRustContext() async throws {
        do {
            _ = try await sampleMemoryPhaseOneOutput(
                modelInfo: minimalModelInfo(),
                rolloutPath: URL(fileURLWithPath: "/tmp/rollout.jsonl"),
                rolloutCwd: URL(fileURLWithPath: "/repo"),
                loadRolloutItems: { _ in [] },
                streamPrompt: { _ in throw TestError("network down") }
            )
            XCTFail("expected error")
        } catch {
            XCTAssertEqual(
                String(describing: error),
                "failed to stream stage-1 memory prompt: network down"
            )
        }
    }

    func testLoadMemoryStageOneRolloutItemsReadsRecorderHistoryForSampling() throws {
        let temp = try temporaryDirectory()
        let recorder = try RolloutRecorder.create(
            codexHome: temp,
            cwd: URL(fileURLWithPath: "/repo"),
            conversationID: ConversationId(),
            source: .default,
            originator: "codex",
            cliVersion: "0.1.0",
            modelProvider: "openai"
        )
        try recorder.recordItems([
            .responseItem(.message(role: "user", content: [.inputText(text: "persist me")])),
            .responseItem(.message(role: "developer", content: [.inputText(text: "later filtered")]))
        ])
        try recorder.shutdown()

        let items = try loadMemoryStageOneRolloutItems(rolloutPath: recorder.rolloutPath)

        XCTAssertEqual(items, [
            .sessionMeta,
            .responseItem(.message(role: "user", content: [.inputText(text: "persist me")])),
            .responseItem(.message(role: "developer", content: [.inputText(text: "later filtered")]))
        ])
    }

    func testClassifiesMemoryExcludedFragmentsLikeRust() {
        XCTAssertTrue(isMemoryExcludedContextualUserFragment(.inputText(text: """
        # AGENTS.md instructions for /repo

        <INSTRUCTIONS>
        Follow project rules.
        </INSTRUCTIONS>
        """)))
        XCTAssertTrue(isMemoryExcludedContextualUserFragment(.inputText(text: """
        <SKILL>
        <name>example</name>
        </skill>
        """)))
        XCTAssertFalse(isMemoryExcludedContextualUserFragment(.inputText(text: """
        <environment_context>
        <cwd>/repo</cwd>
        </environment_context>
        """)))
        XCTAssertFalse(isMemoryExcludedContextualUserFragment(.inputText(text: "<subagent_notification>done</subagent_notification>")))
    }

    func testClaimStartupJobsUsesRustParamsAndRecordsNoCandidateSkip() async throws {
        let currentThreadID = ThreadId()
        let expectedClaim = stage1Claim(suffix: 1)
        let store = RecordingPhaseOneJobStore(claims: [expectedClaim])
        let recorder = CounterRecorder()

        let claims = await claimMemoryPhaseOneStartupJobs(
            currentThreadID: currentThreadID,
            maxRolloutsPerStartup: 4,
            maxRolloutAgeDays: 30,
            minRolloutIdleHours: 2,
            allowedSources: ["cli", "vscode"],
            store: store,
            recordCounter: recorder.record
        )

        XCTAssertEqual(claims, [expectedClaim])
        let claimRequests = await store.claimRequests
        XCTAssertEqual(claimRequests, [
            PhaseOneClaimRequest(
                currentThreadID: currentThreadID,
                params: Stage1StartupClaimParams(
                    scanLimit: memoryStageOneThreadScanLimit,
                    maxClaimed: 4,
                    maxAgeDays: 30,
                    minRolloutIdleHours: 2,
                    allowedSources: ["cli", "vscode"],
                    leaseSeconds: memoryStageOneJobLeaseSeconds
                )
            )
        ])
        XCTAssertEqual(recorder.events, [])

        await store.setClaims([])
        let skipped = await claimMemoryPhaseOneStartupJobs(
            currentThreadID: currentThreadID,
            maxRolloutsPerStartup: 4,
            maxRolloutAgeDays: 30,
            minRolloutIdleHours: 2,
            allowedSources: ["cli"],
            store: store,
            recordCounter: recorder.record
        )

        XCTAssertEqual(skipped, [])
        XCTAssertEqual(recorder.events, [
            CounterEvent(
                name: MemoryWriteMetrics.phaseOneJobs,
                increment: 1,
                labels: [CounterLabel(name: "status", value: "skipped_no_candidates")]
            )
        ])
    }

    func testClaimStartupJobsReturnsNilWhenStoreClaimFailsLikeRustSkip() async throws {
        let store = RecordingPhaseOneJobStore(claimError: TestError("db unavailable"))

        let claims = await claimMemoryPhaseOneStartupJobs(
            currentThreadID: ThreadId(),
            maxRolloutsPerStartup: 1,
            maxRolloutAgeDays: 30,
            minRolloutIdleHours: 2,
            allowedSources: ["cli"],
            store: store
        )

        XCTAssertNil(claims)
    }

    func testRunPhaseOneJobMarksSuccessWithOutputUsingSourceUpdatedAt() async throws {
        let claim = stage1Claim(suffix: 2, updatedAt: Date(timeIntervalSince1970: 456.9))
        let store = RecordingPhaseOneJobStore()
        let usage = TokenUsage(
            inputTokens: 10,
            cachedInputTokens: 4,
            outputTokens: 5,
            reasoningOutputTokens: 1,
            totalTokens: 15
        )

        let result = await runMemoryPhaseOneJob(claim: claim, store: store) { receivedClaim in
            XCTAssertEqual(receivedClaim, claim)
            return (MemoryStageOneOutput(rawMemory: "raw", rolloutSummary: "summary", rolloutSlug: "slug"), usage)
        }

        XCTAssertEqual(result, MemoryPhaseOneJobResult(outcome: .succeededWithOutput, tokenUsage: usage))
        let successes = await store.successes
        XCTAssertEqual(successes, [
            PhaseOneSuccessRequest(
                threadID: claim.thread.id,
                ownershipToken: claim.ownershipToken,
                sourceUpdatedAt: 456,
                rawMemory: "raw",
                rolloutSummary: "summary",
                rolloutSlug: "slug"
            )
        ])
    }

    func testRunPhaseOneJobMarksNoOutputWhenEitherRequiredOutputFieldIsEmpty() async throws {
        let claim = stage1Claim(suffix: 3)
        let store = RecordingPhaseOneJobStore()
        let usage = TokenUsage(totalTokens: 7)

        let result = await runMemoryPhaseOneJob(claim: claim, store: store) { _ in
            (MemoryStageOneOutput(rawMemory: "raw", rolloutSummary: "", rolloutSlug: nil), usage)
        }

        XCTAssertEqual(result, MemoryPhaseOneJobResult(outcome: .succeededNoOutput, tokenUsage: usage))
        let noOutputSuccesses = await store.noOutputSuccesses
        let successes = await store.successes
        XCTAssertEqual(noOutputSuccesses, [
            PhaseOneNoOutputRequest(threadID: claim.thread.id, ownershipToken: claim.ownershipToken)
        ])
        XCTAssertEqual(successes, [])
    }

    func testRunPhaseOneJobMarksFailureWithRetryDelayWhenSamplingThrows() async throws {
        let claim = stage1Claim(suffix: 4)
        let store = RecordingPhaseOneJobStore()

        let result = await runMemoryPhaseOneJob(claim: claim, store: store) { _ in
            throw TestError("sample failed")
        }

        XCTAssertEqual(result, MemoryPhaseOneJobResult(outcome: .failed, tokenUsage: nil))
        let failures = await store.failures
        XCTAssertEqual(failures, [
            PhaseOneFailureRequest(
                threadID: claim.thread.id,
                ownershipToken: claim.ownershipToken,
                reason: "sample failed",
                retryDelaySeconds: memoryStageOneJobRetryDelaySeconds
            )
        ])
    }

    func testRunPhaseOneJobReportsFailedWhenStoreLosesOwnership() async throws {
        let claim = stage1Claim(suffix: 5)
        let store = RecordingPhaseOneJobStore(markSuccessResult: false)

        let result = await runMemoryPhaseOneJob(claim: claim, store: store) { _ in
            (MemoryStageOneOutput(rawMemory: "raw", rolloutSummary: "summary", rolloutSlug: nil), nil)
        }

        XCTAssertEqual(result, MemoryPhaseOneJobResult(outcome: .failed, tokenUsage: nil))
    }

    func testAggregatesAndEmitsPhaseOneStatsLikeRust() async throws {
        let results = [
            MemoryPhaseOneJobResult(
                outcome: .succeededWithOutput,
                tokenUsage: TokenUsage(
                    inputTokens: 10,
                    cachedInputTokens: 4,
                    outputTokens: 3,
                    reasoningOutputTokens: 1,
                    totalTokens: 13
                )
            ),
            MemoryPhaseOneJobResult(
                outcome: .succeededNoOutput,
                tokenUsage: TokenUsage(
                    inputTokens: 2,
                    cachedInputTokens: 1,
                    outputTokens: 5,
                    reasoningOutputTokens: 0,
                    totalTokens: 7
                )
            ),
            MemoryPhaseOneJobResult(outcome: .failed, tokenUsage: nil)
        ]
        let stats = aggregateMemoryPhaseOneStats(results)
        let counter = CounterRecorder()
        let histogram = HistogramRecorder()

        emitMemoryPhaseOneMetrics(stats, recordCounter: counter.record, recordHistogram: histogram.record)

        XCTAssertEqual(stats, MemoryPhaseOneStats(
            claimed: 3,
            succeededWithOutput: 1,
            succeededNoOutput: 1,
            failed: 1,
            totalTokenUsage: TokenUsage(
                inputTokens: 12,
                cachedInputTokens: 5,
                outputTokens: 8,
                reasoningOutputTokens: 1,
                totalTokens: 20
            )
        ))
        XCTAssertEqual(counter.events, [
            CounterEvent(
                name: MemoryWriteMetrics.phaseOneJobs,
                increment: 3,
                labels: [CounterLabel(name: "status", value: "claimed")]
            ),
            CounterEvent(
                name: MemoryWriteMetrics.phaseOneJobs,
                increment: 1,
                labels: [CounterLabel(name: "status", value: "succeeded")]
            ),
            CounterEvent(name: MemoryWriteMetrics.phaseOneOutput, increment: 1, labels: []),
            CounterEvent(
                name: MemoryWriteMetrics.phaseOneJobs,
                increment: 1,
                labels: [CounterLabel(name: "status", value: "succeeded_no_output")]
            ),
            CounterEvent(
                name: MemoryWriteMetrics.phaseOneJobs,
                increment: 1,
                labels: [CounterLabel(name: "status", value: "failed")]
            )
        ])
        XCTAssertEqual(histogram.events, [
            HistogramEvent(
                name: MemoryWriteMetrics.phaseOneTokenUsage,
                value: 20,
                labels: [CounterLabel(name: "token_type", value: "total")]
            ),
            HistogramEvent(
                name: MemoryWriteMetrics.phaseOneTokenUsage,
                value: 12,
                labels: [CounterLabel(name: "token_type", value: "input")]
            ),
            HistogramEvent(
                name: MemoryWriteMetrics.phaseOneTokenUsage,
                value: 5,
                labels: [CounterLabel(name: "token_type", value: "cached_input")]
            ),
            HistogramEvent(
                name: MemoryWriteMetrics.phaseOneTokenUsage,
                value: 8,
                labels: [CounterLabel(name: "token_type", value: "output")]
            ),
            HistogramEvent(
                name: MemoryWriteMetrics.phaseOneTokenUsage,
                value: 1,
                labels: [CounterLabel(name: "token_type", value: "reasoning_output")]
            )
        ])
    }

    func testSerializeFilteredRolloutResponseItemsDropsDeveloperAndContextualUserFragments() throws {
        let items: [RolloutItem] = [
            .sessionMeta,
            .responseItem(.message(role: "developer", content: [.inputText(text: "repo rules")])),
            .responseItem(.message(role: "user", content: [
                .inputText(text: "keep this"),
                .inputText(text: UserInstructions(directory: "/repo", text: "do not persist").intoText()),
                .inputText(text: SkillInstructions(name: "build", path: "/skills/build", contents: "do not persist").asTextForTest()),
                .inputImage(imageURL: "data:image/png;base64,abc")
            ])),
            .responseItem(.message(role: "assistant", content: [.outputText(text: "assistant output")])),
            .responseItem(.reasoning(id: "rs-1", summary: [])),
            .responseItem(.functionCall(name: "exec", arguments: #"{"cmd":"echo ok"}"#, callID: "call-1"))
        ]

        let json = try serializeFilteredRolloutResponseItemsForMemories(items)
        let decoded = try JSONDecoder().decode([ResponseItem].self, from: Data(json.utf8))

        XCTAssertEqual(decoded, [
            .message(role: "user", content: [
                .inputText(text: "keep this"),
                .inputImage(imageURL: "data:image/png;base64,abc")
            ]),
            .message(role: "assistant", content: [.outputText(text: "assistant output")]),
            .functionCall(name: "exec", arguments: #"{"cmd":"echo ok"}"#, callID: "call-1")
        ])
    }

    func testSerializeFilteredRolloutResponseItemsDropsUserMessageWhenOnlyExcludedFragments() throws {
        let items: [RolloutItem] = [
            .responseItem(.message(role: "user", content: [
                .inputText(text: UserInstructions(directory: "/repo", text: "do not persist").intoText())
            ]))
        ]

        let json = try serializeFilteredRolloutResponseItemsForMemories(items)

        XCTAssertEqual(json, "[]")
    }

    func testSerializeFilteredRolloutResponseItemsRedactsSecretsAfterEncodingLikeRust() throws {
        let secret = "sk-" + String(repeating: "A", count: 20)
        let json = try serializeFilteredRolloutResponseItemsForMemories([
            .responseItem(.message(role: "user", content: [.inputText(text: "token \(secret)")]))
        ])

        XCTAssertFalse(json.contains(secret))
        XCTAssertTrue(json.contains("[REDACTED_SECRET]"))
    }
}

private struct CounterLabel: Equatable, Sendable {
    let name: String
    let value: String
}

private struct CounterEvent: Equatable, Sendable {
    let name: String
    let increment: Int64
    let labels: [CounterLabel]
}

private struct HistogramEvent: Equatable, Sendable {
    let name: String
    let value: Int64
    let labels: [CounterLabel]
}

private final class CounterRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [CounterEvent] = []

    var events: [CounterEvent] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func record(_ name: String, _ increment: Int64, _ labels: [(String, String)]) {
        lock.lock()
        storage.append(CounterEvent(
            name: name,
            increment: increment,
            labels: labels.map { CounterLabel(name: $0.0, value: $0.1) }
        ))
        lock.unlock()
    }
}

private final class HistogramRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [HistogramEvent] = []

    var events: [HistogramEvent] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func record(_ name: String, _ value: Int64, _ labels: [(String, String)]) {
        lock.lock()
        storage.append(HistogramEvent(
            name: name,
            value: value,
            labels: labels.map { CounterLabel(name: $0.0, value: $0.1) }
        ))
        lock.unlock()
    }
}

private struct PhaseOneClaimRequest: Equatable {
    let currentThreadID: ThreadId
    let params: Stage1StartupClaimParams
}

private struct PhaseOneSuccessRequest: Equatable {
    let threadID: ThreadId
    let ownershipToken: String
    let sourceUpdatedAt: Int64
    let rawMemory: String
    let rolloutSummary: String
    let rolloutSlug: String?
}

private struct PhaseOneNoOutputRequest: Equatable {
    let threadID: ThreadId
    let ownershipToken: String
}

private struct PhaseOneFailureRequest: Equatable {
    let threadID: ThreadId
    let ownershipToken: String
    let reason: String
    let retryDelaySeconds: Int64
}

private actor RecordingPhaseOneJobStore: MemoryPhaseOneJobStore {
    private(set) var claimRequests: [PhaseOneClaimRequest] = []
    private(set) var successes: [PhaseOneSuccessRequest] = []
    private(set) var noOutputSuccesses: [PhaseOneNoOutputRequest] = []
    private(set) var failures: [PhaseOneFailureRequest] = []
    private var claims: [Stage1JobClaim]
    private let claimError: Error?
    private let markSuccessResult: Bool
    private let markNoOutputResult: Bool
    private let markFailureResult: Bool

    init(
        claims: [Stage1JobClaim] = [],
        claimError: Error? = nil,
        markSuccessResult: Bool = true,
        markNoOutputResult: Bool = true,
        markFailureResult: Bool = true
    ) {
        self.claims = claims
        self.claimError = claimError
        self.markSuccessResult = markSuccessResult
        self.markNoOutputResult = markNoOutputResult
        self.markFailureResult = markFailureResult
    }

    func setClaims(_ claims: [Stage1JobClaim]) {
        self.claims = claims
    }

    func claimStage1JobsForStartup(
        currentThreadID: ThreadId,
        params: Stage1StartupClaimParams
    ) async throws -> [Stage1JobClaim] {
        claimRequests.append(PhaseOneClaimRequest(currentThreadID: currentThreadID, params: params))
        if let claimError {
            throw claimError
        }
        return claims
    }

    func markStage1JobSucceeded(
        threadID: ThreadId,
        ownershipToken: String,
        sourceUpdatedAt: Int64,
        rawMemory: String,
        rolloutSummary: String,
        rolloutSlug: String?
    ) async throws -> Bool {
        successes.append(PhaseOneSuccessRequest(
            threadID: threadID,
            ownershipToken: ownershipToken,
            sourceUpdatedAt: sourceUpdatedAt,
            rawMemory: rawMemory,
            rolloutSummary: rolloutSummary,
            rolloutSlug: rolloutSlug
        ))
        return markSuccessResult
    }

    func markStage1JobSucceededNoOutput(
        threadID: ThreadId,
        ownershipToken: String
    ) async throws -> Bool {
        noOutputSuccesses.append(PhaseOneNoOutputRequest(threadID: threadID, ownershipToken: ownershipToken))
        return markNoOutputResult
    }

    func markStage1JobFailed(
        threadID: ThreadId,
        ownershipToken: String,
        reason: String,
        retryDelaySeconds: Int64
    ) async throws -> Bool {
        failures.append(PhaseOneFailureRequest(
            threadID: threadID,
            ownershipToken: ownershipToken,
            reason: reason,
            retryDelaySeconds: retryDelaySeconds
        ))
        return markFailureResult
    }
}

private struct TestError: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}

private actor PromptRecorder {
    private(set) var prompts: [Prompt] = []

    func append(_ prompt: Prompt) {
        prompts.append(prompt)
    }
}

private func minimalModelInfo(
    contextWindow: Int64? = 10_000,
    maxContextWindow: Int64? = nil,
    effectiveContextWindowPercent: Int64 = 95
) -> ModelInfo {
    ModelInfo(
        slug: "gpt-5.4-mini",
        displayName: "GPT-5.4 Mini",
        supportedReasoningLevels: [],
        shellType: .default,
        visibility: .list,
        supportedInAPI: true,
        priority: 0,
        supportsReasoningSummaries: false,
        supportVerbosity: false,
        truncationPolicy: .tokens(10_000),
        supportsParallelToolCalls: true,
        contextWindow: contextWindow,
        maxContextWindow: maxContextWindow,
        effectiveContextWindowPercent: effectiveContextWindowPercent,
        experimentalSupportedTools: []
    )
}

private func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("memory-phase-one-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func stage1Claim(
    suffix: Int,
    updatedAt: Date = Date(timeIntervalSince1970: 123)
) -> Stage1JobClaim {
    Stage1JobClaim(
        thread: ThreadMetadata(
            id: ThreadId(uuid: UUID(uuidString: "00000000-0000-7000-8000-\(String(format: "%012d", suffix))")!),
            rolloutPath: "/tmp/rollout-\(suffix).jsonl",
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: updatedAt,
            source: "cli",
            modelProvider: "openai",
            model: "gpt-5.4",
            cwd: "/repo",
            cliVersion: "0.1.0",
            title: "thread \(suffix)",
            sandboxPolicy: "workspace-write",
            approvalMode: "on-request",
            tokensUsed: 0,
            firstUserMessage: "hello",
            gitBranch: "main"
        ),
        ownershipToken: "token-\(suffix)"
    )
}

private extension SkillInstructions {
    func asTextForTest() -> String {
        guard case let .message(_, _, content, _) = asResponseItem(),
              case let .inputText(text) = content[0] else {
            return ""
        }
        return text
    }
}
