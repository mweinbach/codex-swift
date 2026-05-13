@testable import CodexCore
import XCTest

final class MemoryWriteGuardTests: XCTestCase {
    func testStartupCheckUsesConfiguredRemainingThreshold() {
        let snapshot = rateLimitSnapshot(
            primaryUsedPercent: 89.9,
            secondaryUsedPercent: 50.0
        )

        XCTAssertTrue(
            memoryRateLimitSnapshotAllowsStartup(snapshot, minRemainingPercent: 10)
        )
        XCTAssertFalse(
            memoryRateLimitSnapshotAllowsStartup(snapshot, minRemainingPercent: 11)
        )
    }

    func testStartupCheckSkipsWhenPrimaryOrSecondaryIsTooLow() {
        XCTAssertFalse(
            memoryRateLimitSnapshotAllowsStartup(
                rateLimitSnapshot(primaryUsedPercent: 75.1, secondaryUsedPercent: 10.0),
                minRemainingPercent: 25
            )
        )
        XCTAssertFalse(
            memoryRateLimitSnapshotAllowsStartup(
                rateLimitSnapshot(primaryUsedPercent: 10.0, secondaryUsedPercent: 75.1),
                minRemainingPercent: 25
            )
        )
        XCTAssertTrue(
            memoryRateLimitSnapshotAllowsStartup(
                rateLimitSnapshot(primaryUsedPercent: 74.9, secondaryUsedPercent: 74.9),
                minRemainingPercent: 25
            )
        )
    }

    func testStartupCheckSkipsWhenLimitIsReached() {
        var snapshot = rateLimitSnapshot(primaryUsedPercent: 10.0, secondaryUsedPercent: 10.0)
        snapshot.rateLimitReachedType = .rateLimitReached

        XCTAssertFalse(
            memoryRateLimitSnapshotAllowsStartup(snapshot, minRemainingPercent: 25)
        )
    }

    func testStartupCheckTreatsMissingWindowsAsAllowedAndClampsThreshold() {
        XCTAssertTrue(
            memoryRateLimitSnapshotAllowsStartup(
                rateLimitSnapshot(primaryUsedPercent: nil, secondaryUsedPercent: nil),
                minRemainingPercent: -1
            )
        )
        XCTAssertFalse(
            memoryRateLimitSnapshotAllowsStartup(
                rateLimitSnapshot(primaryUsedPercent: 0.1, secondaryUsedPercent: nil),
                minRemainingPercent: 101
            )
        )
        XCTAssertTrue(
            memoryRateLimitSnapshotAllowsStartup(
                rateLimitSnapshot(primaryUsedPercent: 0.0, secondaryUsedPercent: nil),
                minRemainingPercent: 101
            )
        )
    }

    func testStartupCheckSelectsCodexLimitBeforeFirstSnapshot() {
        let fallback = rateLimitSnapshot(
            limitID: "other",
            primaryUsedPercent: 99.0,
            secondaryUsedPercent: nil
        )
        let codex = rateLimitSnapshot(
            limitID: memoryRateLimitID,
            primaryUsedPercent: 1.0,
            secondaryUsedPercent: nil
        )

        XCTAssertEqual(memoryStartupRateLimitSnapshot(from: [fallback, codex]), codex)
        XCTAssertTrue(memoryRateLimitsAllowStartup(snapshots: [fallback, codex], minRemainingPercent: 25))
    }

    func testStartupCheckUsesFirstSnapshotWhenCodexLimitIsMissingAndFailOpensWhenEmpty() {
        let fallback = rateLimitSnapshot(
            limitID: "other",
            primaryUsedPercent: 99.0,
            secondaryUsedPercent: nil
        )

        XCTAssertEqual(memoryStartupRateLimitSnapshot(from: [fallback])?.limitID, "other")
        XCTAssertFalse(memoryRateLimitsAllowStartup(snapshots: [fallback], minRemainingPercent: 25))
        XCTAssertNil(memoryStartupRateLimitSnapshot(from: []))
        XCTAssertTrue(memoryRateLimitsAllowStartup(snapshots: [], minRemainingPercent: 25))
    }

    func testStartupCheckFetchesLiveLimitsOnlyForChatGPTBackendAuth() async {
        let fetcher = RateLimitFetchRecorder(snapshots: [
            rateLimitSnapshot(limitID: memoryRateLimitID, primaryUsedPercent: 90, secondaryUsedPercent: nil)
        ])
        let auth = AuthDotJSON(
            authMode: .chatGPTAuthTokens,
            openAIAPIKey: nil,
            tokens: authTokens(accessToken: "access-token", accountID: "account-id"),
            lastRefresh: nil
        )

        let allowed = await memoryRateLimitsAllowStartup(
            auth: auth,
            chatGPTBaseURL: "https://chatgpt.example/backend-api/",
            minRemainingPercent: 25,
            fetchSnapshots: fetcher.fetch
        )

        XCTAssertFalse(allowed)
        let requests = await fetcher.requests
        XCTAssertEqual(requests, [
            RateLimitFetchRequest(
                baseURL: "https://chatgpt.example/backend-api/",
                accessToken: "access-token",
                accountID: "account-id"
            )
        ])
    }

    func testStartupCheckSkipsLiveFetchWithoutBackendAuth() async {
        let fetcher = RateLimitFetchRecorder(snapshots: [
            rateLimitSnapshot(limitID: memoryRateLimitID, primaryUsedPercent: 100, secondaryUsedPercent: nil)
        ])

        for auth in [
            Optional<AuthDotJSON>.none,
            AuthDotJSON(authMode: .apiKey, openAIAPIKey: "sk-test", tokens: nil, lastRefresh: nil),
            AuthDotJSON(
                authMode: .apiKey,
                openAIAPIKey: nil,
                tokens: authTokens(accessToken: "token", accountID: "account-id"),
                lastRefresh: nil
            ),
            AuthDotJSON(
                authMode: .chatGPTAuthTokens,
                openAIAPIKey: nil,
                tokens: authTokens(accessToken: "token", accountID: nil),
                lastRefresh: nil
            )
        ] {
            let allowed = await memoryRateLimitsAllowStartup(
                auth: auth,
                chatGPTBaseURL: "https://chatgpt.example/backend-api/",
                minRemainingPercent: 25,
                fetchSnapshots: fetcher.fetch
            )
            XCTAssertTrue(allowed)
        }

        let requests = await fetcher.requests
        XCTAssertEqual(requests, [])
    }

    func testStartupCheckFailsOpenWhenLiveFetchFailsOrReturnsNoSnapshots() async {
        let failingFetcher = RateLimitFetchRecorder(error: TestError("backend unavailable"))
        let emptyFetcher = RateLimitFetchRecorder(snapshots: [])
        let auth = AuthDotJSON(
            authMode: .chatGPTAuthTokens,
            openAIAPIKey: nil,
            tokens: authTokens(accessToken: "access-token", accountID: "account-id"),
            lastRefresh: nil
        )

        let failedOpenAfterError = await memoryRateLimitsAllowStartup(
            auth: auth,
            chatGPTBaseURL: "https://chatgpt.example/backend-api/",
            minRemainingPercent: 25,
            fetchSnapshots: failingFetcher.fetch
        )
        let failedOpenAfterEmptyResponse = await memoryRateLimitsAllowStartup(
            auth: auth,
            chatGPTBaseURL: "https://chatgpt.example/backend-api/",
            minRemainingPercent: 25,
            fetchSnapshots: emptyFetcher.fetch
        )
        let failingRequests = await failingFetcher.requests
        let emptyRequests = await emptyFetcher.requests

        XCTAssertTrue(failedOpenAfterError)
        XCTAssertTrue(failedOpenAfterEmptyResponse)
        XCTAssertEqual(failingRequests.count, 1)
        XCTAssertEqual(emptyRequests.count, 1)
    }

    func testRateLimitSnapshotsClientBuildsRustUsageEndpoints() {
        XCTAssertEqual(
            MemoryRateLimitSnapshotsClient<RecordingAPITransport>.usageEndpoint(for: "https://chatgpt.com/"),
            "https://chatgpt.com/backend-api/wham/usage"
        )
        XCTAssertEqual(
            MemoryRateLimitSnapshotsClient<RecordingAPITransport>.usageEndpoint(
                for: "https://chat.openai.com/backend-api/"
            ),
            "https://chat.openai.com/backend-api/wham/usage"
        )
        XCTAssertEqual(
            MemoryRateLimitSnapshotsClient<RecordingAPITransport>.usageEndpoint(for: "https://api.example.test/"),
            "https://api.example.test/api/codex/usage"
        )
    }

    func testRateLimitSnapshotsClientMapsRustUsagePayloadAndAuthHeaders() async throws {
        let capture = APIRequestCapture()
        let client = MemoryRateLimitSnapshotsClient(transport: RecordingAPITransport(
            capture: capture,
            response: APIResponse(statusCode: 200, body: Data(rateLimitsUsageJSON.utf8))
        ))

        let snapshots = try await client.fetchSnapshots(
            baseURL: "https://chatgpt.example/backend-api/",
            accessToken: "access-token",
            accountID: "account-id"
        )

        let requests = await capture.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.method, .get)
        XCTAssertEqual(requests.first?.url, "https://chatgpt.example/backend-api/wham/usage")
        XCTAssertEqual(requests.first?.headers[APIAuthHeaders.authorization], "Bearer access-token")
        XCTAssertEqual(requests.first?.headers[APIAuthHeaders.chatGPTAccountID], "account-id")
        XCTAssertEqual(requests.first?.body, nil)

        XCTAssertEqual(snapshots.count, 2)
        XCTAssertEqual(snapshots[0].limitID, memoryRateLimitID)
        XCTAssertNil(snapshots[0].limitName)
        XCTAssertEqual(
            snapshots[0].primary,
            RateLimitWindow(usedPercent: 42, windowMinutes: 2, resetsAt: 1_737_000_000)
        )
        XCTAssertEqual(
            snapshots[0].secondary,
            RateLimitWindow(usedPercent: 5, windowMinutes: nil, resetsAt: 1_737_043_200)
        )
        XCTAssertEqual(
            snapshots[0].credits,
            CreditsSnapshot(hasCredits: true, unlimited: false, balance: "9.99")
        )
        XCTAssertEqual(snapshots[0].planType, .pro)
        XCTAssertEqual(snapshots[0].rateLimitReachedType, .workspaceMemberUsageLimitReached)

        XCTAssertEqual(snapshots[1].limitID, "codex_other")
        XCTAssertEqual(snapshots[1].limitName, "Other Codex")
        XCTAssertEqual(
            snapshots[1].primary,
            RateLimitWindow(usedPercent: 88, windowMinutes: 30, resetsAt: 1_735_693_200)
        )
        XCTAssertNil(snapshots[1].secondary)
        XCTAssertNil(snapshots[1].credits)
        XCTAssertEqual(snapshots[1].planType, .pro)
        XCTAssertNil(snapshots[1].rateLimitReachedType)
    }

    func testStartupCheckCanUseMemoryRateLimitSnapshotsClientFetcher() async {
        let capture = APIRequestCapture()
        let client = MemoryRateLimitSnapshotsClient(transport: RecordingAPITransport(
            capture: capture,
            response: APIResponse(statusCode: 200, body: Data(rateLimitsUsageJSON.utf8))
        ))
        let auth = AuthDotJSON(
            authMode: .chatGPTAuthTokens,
            openAIAPIKey: nil,
            tokens: authTokens(accessToken: "access-token", accountID: "account-id"),
            lastRefresh: nil
        )

        let allowed = await memoryRateLimitsAllowStartup(
            auth: auth,
            chatGPTBaseURL: "https://api.example.test/",
            minRemainingPercent: 25,
            fetchSnapshots: client.fetcher
        )

        XCTAssertFalse(allowed)
        let requests = await capture.requests
        XCTAssertEqual(requests.map(\.url), ["https://api.example.test/api/codex/usage"])
    }

    func testMetricNamesMatchRustMemoryWriteConstants() {
        XCTAssertEqual(MemoryWriteMetrics.startup, "codex.memory.startup")
        XCTAssertEqual(MemoryWriteMetrics.phaseOneJobs, "codex.memory.phase1")
        XCTAssertEqual(MemoryWriteMetrics.phaseOneE2EMS, "codex.memory.phase1.e2e_ms")
        XCTAssertEqual(MemoryWriteMetrics.phaseOneOutput, "codex.memory.phase1.output")
        XCTAssertEqual(MemoryWriteMetrics.phaseOneTokenUsage, "codex.memory.phase1.token_usage")
        XCTAssertEqual(MemoryWriteMetrics.phaseTwoJobs, "codex.memory.phase2")
        XCTAssertEqual(MemoryWriteMetrics.phaseTwoE2EMS, "codex.memory.phase2.e2e_ms")
        XCTAssertEqual(MemoryWriteMetrics.phaseTwoInput, "codex.memory.phase2.input")
        XCTAssertEqual(MemoryWriteMetrics.phaseTwoTokenUsage, "codex.memory.phase2.token_usage")
    }

    func testStartupPipelineEligibilityMatchesRustSkips() {
        let enabled = memoryFeatureStates(enabled: true)
        let disabled = memoryFeatureStates(enabled: false)

        XCTAssertTrue(memoryStartupPipelineIsEligible(
            isEphemeral: false,
            source: .cli,
            features: enabled
        ))
        XCTAssertFalse(memoryStartupPipelineIsEligible(
            isEphemeral: true,
            source: .cli,
            features: enabled
        ))
        XCTAssertFalse(memoryStartupPipelineIsEligible(
            isEphemeral: false,
            source: .cli,
            features: disabled
        ))
        XCTAssertFalse(memoryStartupPipelineIsEligible(
            isEphemeral: false,
            source: .subagent(.memoryConsolidation),
            features: enabled
        ))
    }

    func testStartupPipelineSkipsBeforeSideEffectsWhenIneligibleOrMissingStateDB() async {
        let events = StartupEventLog()

        let ineligible = await runMemoryStartupPipeline(
            options: MemoryStartupPipelineOptions(
                isEphemeral: true,
                source: .cli,
                features: memoryFeatureStates(enabled: true),
                hasStateDatabase: true
            ),
            seedExtensionInstructions: { await events.append("seed") },
            prunePhaseOneOutputs: { await events.append("prune") },
            rateLimitsAllowStartup: { await events.append("guard"); return true },
            runPhaseOne: { await events.append("phase1") },
            runPhaseTwo: { await events.append("phase2") }
        )

        XCTAssertEqual(ineligible, .skippedIneligible)
        let afterIneligible = await events.values
        XCTAssertEqual(afterIneligible, [])

        let missingState = await runMemoryStartupPipeline(
            options: MemoryStartupPipelineOptions(
                isEphemeral: false,
                source: .cli,
                features: memoryFeatureStates(enabled: true),
                hasStateDatabase: false
            ),
            seedExtensionInstructions: { await events.append("seed") },
            prunePhaseOneOutputs: { await events.append("prune") },
            rateLimitsAllowStartup: { await events.append("guard"); return true },
            runPhaseOne: { await events.append("phase1") },
            runPhaseTwo: { await events.append("phase2") }
        )

        XCTAssertEqual(missingState, .skippedMissingStateDatabase)
        let afterMissingState = await events.values
        XCTAssertEqual(afterMissingState, [])
    }

    func testStartupPipelineOrdersSeedPruneGuardPhaseOneAndPhaseTwo() async {
        let events = StartupEventLog()

        let outcome = await runMemoryStartupPipeline(
            options: MemoryStartupPipelineOptions(
                isEphemeral: false,
                source: .vscode,
                features: memoryFeatureStates(enabled: true),
                hasStateDatabase: true
            ),
            seedExtensionInstructions: { await events.append("seed") },
            prunePhaseOneOutputs: { await events.append("prune") },
            rateLimitsAllowStartup: { await events.append("guard"); return true },
            runPhaseOne: { await events.append("phase1") },
            runPhaseTwo: { await events.append("phase2") }
        )

        XCTAssertEqual(outcome, .completed)
        let values = await events.values
        XCTAssertEqual(values, ["seed", "prune", "guard", "phase1", "phase2"])
    }

    func testStartupPipelineRecordsRateLimitSkipAfterSeedAndPrune() async {
        let events = StartupEventLog()
        let recorder = CounterRecorder()

        let outcome = await runMemoryStartupPipeline(
            options: MemoryStartupPipelineOptions(
                isEphemeral: false,
                source: .mcp,
                features: memoryFeatureStates(enabled: true),
                hasStateDatabase: true
            ),
            seedExtensionInstructions: { await events.append("seed") },
            prunePhaseOneOutputs: { await events.append("prune") },
            rateLimitsAllowStartup: { await events.append("guard"); return false },
            runPhaseOne: { await events.append("phase1") },
            runPhaseTwo: { await events.append("phase2") },
            recordCounter: recorder.record
        )

        XCTAssertEqual(outcome, .skippedRateLimit)
        let values = await events.values
        XCTAssertEqual(values, ["seed", "prune", "guard"])
        XCTAssertEqual(recorder.events, [
            CounterEvent(
                name: MemoryWriteMetrics.startup,
                increment: 1,
                labels: [CounterLabel(name: "status", value: "skipped_rate_limit")]
            )
        ])
    }

    func testLiveStartupPipelineAssemblesRustStartupPhases() async throws {
        let threadID = try ThreadId(string: "00000000-0000-4000-8000-000000000301")
        let claim = stage1Claim(suffix: 302)
        let store = RecordingMemoryStartupStore(
            recorder: StartupPipelineRecorder(),
            claims: [claim],
            phaseTwoClaimOutcome: .skippedRetryUnavailable
        )
        let recorder = store.recorder
        let counters = CounterRecorder()
        var config = CodexRuntimeConfig()
        config.memories.maxRolloutsPerStartup = 3
        config.memories.maxRolloutAgeDays = 11
        config.memories.minRolloutIdleHours = 7
        config.memories.maxUnusedDays = 45
        config.chatgptBaseURL = "https://chatgpt.example/backend-api/"
        let auth = AuthDotJSON(
            authMode: .chatGPTAuthTokens,
            openAIAPIKey: nil,
            tokens: authTokens(accessToken: "access-token", accountID: "account-id"),
            lastRefresh: nil
        )

        let result = await runMemoryStartupPipeline(
            options: MemoryStartupPipelineOptions(
                isEphemeral: false,
                source: .cli,
                features: memoryFeatureStates(enabled: true),
                hasStateDatabase: true
            ),
            threadID: threadID,
            config: config,
            codexHome: URL(fileURLWithPath: "/tmp/codex-home", isDirectory: true),
            auth: auth,
            allowedSources: ["cli"],
            stageOneModelInfo: startupModelInfo(),
            stageOneServiceTier: "flex",
            stageOneTurnMetadataHeader: "turn-meta",
            stateStore: store,
            fetchRateLimitSnapshots: { baseURL, accessToken, accountID in
                recorder.record("quota:\(baseURL):\(accessToken):\(accountID)")
                return [
                    RateLimitSnapshot(
                        limitID: memoryRateLimitID,
                        primary: RateLimitWindow(usedPercent: 1, windowMinutes: nil, resetsAt: nil),
                        secondary: nil,
                        credits: nil,
                        planType: nil
                    )
                ]
            },
            sampleStageOneOutput: { sampledClaim, context in
                recorder.record(
                    "sample:\(sampledClaim.thread.id):\(context.modelInfo.slug):"
                        + "\(context.serviceTier ?? "nil"):\(context.turnMetadataHeader ?? "nil")"
                )
                return (
                    MemoryStageOneOutput(
                        rawMemory: "remember this",
                        rolloutSummary: "summary",
                        rolloutSlug: "slug"
                    ),
                    TokenUsage(
                        inputTokens: 2,
                        cachedInputTokens: 1,
                        outputTokens: 3,
                        reasoningOutputTokens: 0,
                        totalTokens: 5
                    )
                )
            },
            startPhaseTwoAgent: { _ in
                XCTFail("phase two should not spawn when the store reports skipped_retry_unavailable")
                throw TestError("unexpected spawn")
            },
            seedExtensionInstructions: { _ in recorder.record("seed") },
            resetBaseline: { _ in recorder.record("reset") },
            recordCounter: counters.record
        )

        XCTAssertEqual(result.outcome, .completed)
        XCTAssertEqual(result.phaseOneStats?.claimed, 1)
        XCTAssertEqual(result.phaseOneStats?.succeededWithOutput, 1)
        XCTAssertEqual(result.phaseTwoOutcome, .skipped("skipped_retry_unavailable"))
        XCTAssertEqual(recorder.events, [
            "seed",
            "prune:45:200",
            "quota:https://chatgpt.example/backend-api/:access-token:account-id",
            "claim:\(threadID):5000:3:11:7:cli:3600",
            "sample:\(claim.thread.id):gpt-5.4-mini:flex:turn-meta",
            "stage1-success:\(claim.thread.id):token-302:123:remember this:summary:slug",
            "phase2-claim:\(threadID):3600"
        ])
    }

    private func rateLimitSnapshot(
        limitID: String? = memoryRateLimitID,
        primaryUsedPercent: Double?,
        secondaryUsedPercent: Double?
    ) -> RateLimitSnapshot {
        RateLimitSnapshot(
            limitID: limitID,
            primary: primaryUsedPercent.map(rateLimitWindow),
            secondary: secondaryUsedPercent.map(rateLimitWindow),
            credits: nil,
            planType: nil
        )
    }

    private func rateLimitWindow(usedPercent: Double) -> RateLimitWindow {
        RateLimitWindow(usedPercent: usedPercent, windowMinutes: nil, resetsAt: nil)
    }

    private func memoryFeatureStates(enabled: Bool) -> FeatureStates {
        var features = FeatureStates()
        features.set(.memoryTool, enabled: enabled)
        return features
    }

    private func authTokens(accessToken: String, accountID: String?) -> AuthTokenData {
        AuthTokenData(
            idToken: IdTokenInfo(rawJWT: "id-token"),
            accessToken: accessToken,
            refreshToken: "refresh-token",
            accountID: accountID
        )
    }

    private func startupModelInfo() -> ModelInfo {
        ModelInfo(
            slug: "gpt-5.4-mini",
            displayName: "GPT-5.4 Mini",
            supportedReasoningLevels: [],
            shellType: .default,
            visibility: .list,
            supportedInAPI: true,
            priority: 0,
            supportsReasoningSummaries: false,
            defaultReasoningSummary: .auto,
            supportVerbosity: false,
            defaultVerbosity: nil,
            truncationPolicy: .tokens(10_000),
            supportsParallelToolCalls: true,
            contextWindow: 10_000,
            experimentalSupportedTools: [],
            inputModalities: [.text]
        )
    }

    private func stage1Claim(suffix: Int) -> Stage1JobClaim {
        Stage1JobClaim(
            thread: ThreadMetadata(
                id: ThreadId(uuid: UUID(uuidString: "00000000-0000-7000-8000-\(String(format: "%012d", suffix))")!),
                rolloutPath: "/tmp/rollout-\(suffix).jsonl",
                createdAt: Date(timeIntervalSince1970: 1),
                updatedAt: Date(timeIntervalSince1970: 123),
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

    private var rateLimitsUsageJSON: String {
        """
        {
          "plan_type": "pro",
          "rate_limit": {
            "allowed": true,
            "limit_reached": false,
            "primary_window": {
              "used_percent": 42,
              "limit_window_seconds": 61,
              "reset_at": 1737000000
            },
            "secondary_window": {
              "used_percent": 5,
              "limit_window_seconds": 0,
              "reset_at": 1737043200
            }
          },
          "credits": {
            "has_credits": true,
            "unlimited": false,
            "balance": "9.99"
          },
          "rate_limit_reached_type": {
            "type": "workspace_member_usage_limit_reached"
          },
          "additional_rate_limits": [
            {
              "limit_name": "Other Codex",
              "metered_feature": "codex_other",
              "rate_limit": {
                "allowed": true,
                "limit_reached": false,
                "primary_window": {
                  "used_percent": 88,
                  "limit_window_seconds": 1800,
                  "reset_at": 1735693200
                }
              }
            }
          ]
        }
        """
    }
}

private actor StartupEventLog {
    private(set) var values: [String] = []

    func append(_ value: String) {
        values.append(value)
    }
}

private struct RateLimitFetchRequest: Equatable {
    let baseURL: String
    let accessToken: String
    let accountID: String
}

private actor RateLimitFetchRecorder {
    private(set) var requests: [RateLimitFetchRequest] = []
    private let snapshots: [RateLimitSnapshot]
    private let error: Error?

    init(snapshots: [RateLimitSnapshot] = [], error: Error? = nil) {
        self.snapshots = snapshots
        self.error = error
    }

    func fetch(baseURL: String, accessToken: String, accountID: String) async throws -> [RateLimitSnapshot] {
        requests.append(RateLimitFetchRequest(baseURL: baseURL, accessToken: accessToken, accountID: accountID))
        if let error {
            throw error
        }
        return snapshots
    }
}

private actor APIRequestCapture {
    private(set) var requests: [APIRequest] = []

    func append(_ request: APIRequest) {
        requests.append(request)
    }
}

private struct RecordingAPITransport: APITransport {
    let capture: APIRequestCapture
    let response: APIResponse

    func execute(_ request: APIRequest) async -> Result<APIResponse, TransportError> {
        await capture.append(request)
        return .success(response)
    }

    func stream(_ request: APIRequest) async -> Result<APIStreamResponse, TransportError> {
        await capture.append(request)
        return .success(APIStreamResponse(statusCode: response.statusCode, sseText: ""))
    }
}

private final class StartupPipelineRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    var events: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func record(_ event: String) {
        lock.lock()
        storage.append(event)
        lock.unlock()
    }
}

private actor RecordingMemoryStartupStore: MemoryPhaseOneJobStore, MemoryPhaseOneRetentionStore, MemoryPhaseTwoJobStore {
    let recorder: StartupPipelineRecorder
    private let claims: [Stage1JobClaim]
    private let phaseTwoClaimOutcome: Phase2JobClaimOutcome

    init(
        recorder: StartupPipelineRecorder,
        claims: [Stage1JobClaim] = [],
        phaseTwoClaimOutcome: Phase2JobClaimOutcome = .skippedRunning
    ) {
        self.recorder = recorder
        self.claims = claims
        self.phaseTwoClaimOutcome = phaseTwoClaimOutcome
    }

    func pruneStage1OutputsForRetention(maxUnusedDays: Int64, limit: Int) async throws -> Int {
        recorder.record("prune:\(maxUnusedDays):\(limit)")
        return 0
    }

    func claimStage1JobsForStartup(
        currentThreadID: ThreadId,
        params: Stage1StartupClaimParams
    ) async throws -> [Stage1JobClaim] {
        recorder.record(
            "claim:\(currentThreadID):\(params.scanLimit):\(params.maxClaimed):"
                + "\(params.maxAgeDays):\(params.minRolloutIdleHours):"
                + "\(params.allowedSources.joined(separator: ",")):\(params.leaseSeconds)"
        )
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
        recorder.record(
            "stage1-success:\(threadID):\(ownershipToken):\(sourceUpdatedAt):"
                + "\(rawMemory):\(rolloutSummary):\(rolloutSlug ?? "nil")"
        )
        return true
    }

    func markStage1JobSucceededNoOutput(threadID: ThreadId, ownershipToken: String) async throws -> Bool {
        recorder.record("stage1-no-output:\(threadID):\(ownershipToken)")
        return true
    }

    func markStage1JobFailed(
        threadID: ThreadId,
        ownershipToken: String,
        reason: String,
        retryDelaySeconds: Int64
    ) async throws -> Bool {
        recorder.record("stage1-failed:\(threadID):\(ownershipToken):\(reason):\(retryDelaySeconds)")
        return true
    }

    func getPhase2InputSelection(limit: Int, maxUnusedDays: Int64) async throws -> [Stage1Output] {
        recorder.record("phase2-selection:\(limit):\(maxUnusedDays)")
        return []
    }

    func tryClaimGlobalPhase2Job(threadID: ThreadId, leaseSeconds: Int64) async throws -> Phase2JobClaimOutcome {
        recorder.record("phase2-claim:\(threadID):\(leaseSeconds)")
        return phaseTwoClaimOutcome
    }

    func markGlobalPhase2JobFailed(
        ownershipToken: String,
        reason: String,
        retryDelaySeconds: Int64
    ) async throws -> Bool {
        recorder.record("phase2-failed:\(ownershipToken):\(reason):\(retryDelaySeconds)")
        return true
    }

    func markGlobalPhase2JobFailedIfUnowned(
        ownershipToken: String,
        reason: String,
        retryDelaySeconds: Int64
    ) async throws -> Bool {
        recorder.record("phase2-unowned-failed:\(ownershipToken):\(reason):\(retryDelaySeconds)")
        return true
    }

    func heartbeatGlobalPhase2Job(ownershipToken: String, leaseSeconds: Int64) async throws -> Bool {
        recorder.record("phase2-heartbeat:\(ownershipToken):\(leaseSeconds)")
        return true
    }

    func markGlobalPhase2JobSucceeded(
        ownershipToken: String,
        completionWatermark: Int64,
        selectedOutputs: [Stage1Output]
    ) async throws -> Bool {
        recorder.record("phase2-success:\(ownershipToken):\(completionWatermark):\(selectedOutputs.count)")
        return true
    }
}

private struct TestError: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}

private struct CounterLabel: Hashable, Sendable {
    let name: String
    let value: String
}

private struct CounterEvent: Hashable, Sendable {
    let name: String
    let increment: Int64
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
