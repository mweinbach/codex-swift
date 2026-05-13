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
