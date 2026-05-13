@testable import CodexCore
import XCTest

final class MemoryWritePhaseTwoTests: XCTestCase {
    func testClaimMemoryPhaseTwoJobMapsRustOutcomesAndCounter() async throws {
        let threadID = try ThreadId(string: "00000000-0000-4000-8000-000000000101")
        let store = RecordingPhaseTwoJobStore(claimOutcome: .claimed(ownershipToken: "token-1", inputWatermark: 42))
        let recorder = CounterRecorder()

        let claim = try await claimMemoryPhaseTwoJob(
            threadID: threadID,
            store: store,
            recordCounter: recorder.record
        )

        XCTAssertEqual(claim, MemoryPhaseTwoClaim(token: "token-1", watermark: 42))
        let claimRequests = await store.recordedClaimRequests
        XCTAssertEqual(claimRequests, [
            RecordingPhaseTwoJobStore.ClaimRequest(threadID: threadID, leaseSeconds: memoryStageTwoJobLeaseSeconds)
        ])
        XCTAssertEqual(recorder.events, [
            CounterEvent(
                name: MemoryWriteMetrics.phaseTwoJobs,
                increment: 1,
                labels: [CounterLabel(name: "status", value: "claimed")]
            )
        ])

        let skippedStore = RecordingPhaseTwoJobStore(claimOutcome: .skippedCooldown)
        do {
            _ = try await claimMemoryPhaseTwoJob(threadID: threadID, store: skippedStore)
            XCTFail("expected skipped cooldown")
        } catch let error as MemoryPhaseTwoClaimError {
            XCTAssertEqual(error, .skippedCooldown)
            XCTAssertEqual(error.description, "skipped_cooldown")
        }

        let failingStore = RecordingPhaseTwoJobStore(claimOutcome: .skippedRunning, claimError: StoreError.failed)
        do {
            _ = try await claimMemoryPhaseTwoJob(threadID: threadID, store: failingStore)
            XCTFail("expected failed claim")
        } catch let error as MemoryPhaseTwoClaimError {
            XCTAssertEqual(error, .failedClaim)
            XCTAssertEqual(error.description, "failed_claim")
        }
    }

    func testMarkMemoryPhaseTwoJobFailedRecordsStatusAndFallsBackWhenLockIsLost() async throws {
        let store = RecordingPhaseTwoJobStore(
            claimOutcome: .skippedRunning,
            markFailedResult: false,
            markFailedIfUnownedResult: true
        )
        let recorder = CounterRecorder()

        let handled = try await markMemoryPhaseTwoJobFailed(
            store: store,
            claim: MemoryPhaseTwoClaim(token: "token-2", watermark: 9),
            reason: "failed_sync_workspace_inputs",
            recordCounter: recorder.record
        )

        XCTAssertTrue(handled)
        let failedRequests = await store.recordedFailedRequests
        XCTAssertEqual(failedRequests, [
            RecordingPhaseTwoJobStore.FailedRequest(
                ownershipToken: "token-2",
                reason: "failed_sync_workspace_inputs",
                retryDelaySeconds: memoryStageTwoJobRetryDelaySeconds,
                unownedFallback: false
            ),
            RecordingPhaseTwoJobStore.FailedRequest(
                ownershipToken: "token-2",
                reason: "failed_sync_workspace_inputs",
                retryDelaySeconds: memoryStageTwoJobRetryDelaySeconds,
                unownedFallback: true
            )
        ])
        XCTAssertEqual(recorder.events, [
            CounterEvent(
                name: MemoryWriteMetrics.phaseTwoJobs,
                increment: 1,
                labels: [CounterLabel(name: "status", value: "failed_sync_workspace_inputs")]
            )
        ])
    }

    func testMarkMemoryPhaseTwoJobSucceededRecordsRustStatusAndSelection() async throws {
        let selected = [stage1Output(suffix: 1, sourceUpdatedAt: Date(timeIntervalSince1970: 100))]
        let store = RecordingPhaseTwoJobStore(claimOutcome: .skippedRunning, markSucceededResult: true)
        let recorder = CounterRecorder()

        let succeeded = try await markMemoryPhaseTwoJobSucceeded(
            store: store,
            claim: MemoryPhaseTwoClaim(token: "token-3", watermark: 4),
            completionWatermark: 100,
            selectedOutputs: selected,
            reason: "succeeded",
            recordCounter: recorder.record
        )

        XCTAssertTrue(succeeded)
        let succeededRequests = await store.recordedSucceededRequests
        XCTAssertEqual(succeededRequests, [
            RecordingPhaseTwoJobStore.SucceededRequest(
                ownershipToken: "token-3",
                completionWatermark: 100,
                selectedOutputs: selected
            )
        ])
        XCTAssertEqual(recorder.events, [
            CounterEvent(
                name: MemoryWriteMetrics.phaseTwoJobs,
                increment: 1,
                labels: [CounterLabel(name: "status", value: "succeeded")]
            )
        ])
    }

    func testPhaseTwoWatermarkUsesLatestSourceUpdatedAtButNeverMovesBackward() {
        let older = stage1Output(suffix: 2, sourceUpdatedAt: Date(timeIntervalSince1970: 80))
        let newer = stage1Output(suffix: 3, sourceUpdatedAt: Date(timeIntervalSince1970: 120))

        XCTAssertEqual(phaseTwoWatermark(claimedWatermark: 90, latestMemories: [older, newer]), 120)
        XCTAssertEqual(phaseTwoWatermark(claimedWatermark: 150, latestMemories: [older, newer]), 150)
        XCTAssertEqual(phaseTwoWatermark(claimedWatermark: 150, latestMemories: []), 150)
    }

    func testFinalMemoryConsolidationAgentStatusMatchesRust() {
        XCTAssertFalse(isFinalMemoryConsolidationAgentStatus(.pendingInit))
        XCTAssertFalse(isFinalMemoryConsolidationAgentStatus(.running))
        XCTAssertFalse(isFinalMemoryConsolidationAgentStatus(.interrupted))
        XCTAssertTrue(isFinalMemoryConsolidationAgentStatus(.completed(nil)))
        XCTAssertTrue(isFinalMemoryConsolidationAgentStatus(.errored("boom")))
        XCTAssertTrue(isFinalMemoryConsolidationAgentStatus(.shutdown))
        XCTAssertTrue(isFinalMemoryConsolidationAgentStatus(.notFound))
    }

    func testPhaseTwoAgentLoopIntervalConstantsMatchRust() {
        XCTAssertEqual(memoryStageTwoAgentStatusPollSeconds, 1)
        XCTAssertEqual(memoryStageTwoJobHeartbeatSeconds, 90)
    }

    func testLoopMemoryPhaseTwoConsolidationAgentPollsUntilFinalLikeRust() async throws {
        let threadID = try phaseTwoThreadID(suffix: 501)
        let store = RecordingPhaseTwoJobStore(claimOutcome: .skippedRunning)
        let statuses = AgentStatusSequence([.running, .running, .completed("done")])
        let events = AgentLoopEventSequence([.statusPoll, .statusPoll])

        let finalStatus = await loopMemoryPhaseTwoConsolidationAgent(
            threadID: threadID,
            claim: MemoryPhaseTwoClaim(token: "token-loop", watermark: 1),
            store: store,
            status: { await statuses.next() },
            nextEvent: { await events.next() }
        )

        XCTAssertEqual(finalStatus, .completed("done"))
        let heartbeatRequests = await store.recordedHeartbeatRequests
        XCTAssertEqual(heartbeatRequests, [])
    }

    func testLoopMemoryPhaseTwoConsolidationAgentHeartbeatsWhileRunning() async throws {
        let threadID = try phaseTwoThreadID(suffix: 502)
        let store = RecordingPhaseTwoJobStore(
            claimOutcome: .skippedRunning,
            heartbeatResults: [.success(true)]
        )
        let statuses = AgentStatusSequence([.running, .running, .completed(nil)])
        let events = AgentLoopEventSequence([.heartbeat, .statusPoll])

        let finalStatus = await loopMemoryPhaseTwoConsolidationAgent(
            threadID: threadID,
            claim: MemoryPhaseTwoClaim(token: "token-heartbeat", watermark: 1),
            store: store,
            status: { await statuses.next() },
            nextEvent: { await events.next() }
        )

        XCTAssertEqual(finalStatus, .completed(nil))
        let heartbeatRequests = await store.recordedHeartbeatRequests
        XCTAssertEqual(heartbeatRequests, [
            RecordingPhaseTwoJobStore.HeartbeatRequest(
                ownershipToken: "token-heartbeat",
                leaseSeconds: memoryStageTwoJobLeaseSeconds
            )
        ])
    }

    func testLoopMemoryPhaseTwoConsolidationAgentErrorsWhenHeartbeatLosesOwnership() async throws {
        let threadID = try phaseTwoThreadID(suffix: 503)
        let store = RecordingPhaseTwoJobStore(
            claimOutcome: .skippedRunning,
            heartbeatResults: [.success(false)]
        )
        let statuses = AgentStatusSequence([.running])
        let events = AgentLoopEventSequence([.heartbeat])

        let finalStatus = await loopMemoryPhaseTwoConsolidationAgent(
            threadID: threadID,
            claim: MemoryPhaseTwoClaim(token: "token-lost-heartbeat", watermark: 1),
            store: store,
            status: { await statuses.next() },
            nextEvent: { await events.next() }
        )

        XCTAssertEqual(finalStatus, .errored("lost global phase-2 ownership during heartbeat"))
    }

    func testLoopMemoryPhaseTwoConsolidationAgentErrorsWhenHeartbeatThrows() async throws {
        let threadID = try phaseTwoThreadID(suffix: 504)
        let store = RecordingPhaseTwoJobStore(
            claimOutcome: .skippedRunning,
            heartbeatResults: [.failure(.failed)]
        )
        let statuses = AgentStatusSequence([.running])
        let events = AgentLoopEventSequence([.heartbeat])

        let finalStatus = await loopMemoryPhaseTwoConsolidationAgent(
            threadID: threadID,
            claim: MemoryPhaseTwoClaim(token: "token-failed-heartbeat", watermark: 1),
            store: store,
            status: { await statuses.next() },
            nextEvent: { await events.next() }
        )

        XCTAssertEqual(finalStatus, .errored("phase-2 heartbeat update failed: failed"))
    }

    func testLoopMemoryPhaseTwoConsolidationAgentRereadsFinalStatusAfterTermination() async throws {
        let threadID = try phaseTwoThreadID(suffix: 505)
        let store = RecordingPhaseTwoJobStore(claimOutcome: .skippedRunning)
        let statuses = AgentStatusSequence([.running, .completed("done")])
        let events = AgentLoopEventSequence([.sessionTerminated])

        let finalStatus = await loopMemoryPhaseTwoConsolidationAgent(
            threadID: threadID,
            claim: MemoryPhaseTwoClaim(token: "token-terminated-final", watermark: 1),
            store: store,
            status: { await statuses.next() },
            nextEvent: { await events.next() }
        )

        XCTAssertEqual(finalStatus, .completed("done"))
    }

    func testLoopMemoryPhaseTwoConsolidationAgentErrorsWhenTerminatedBeforeFinalStatus() async throws {
        let threadID = try phaseTwoThreadID(suffix: 506)
        let store = RecordingPhaseTwoJobStore(claimOutcome: .skippedRunning)
        let statuses = AgentStatusSequence([.running, .running])
        let events = AgentLoopEventSequence([.sessionTerminated])

        let finalStatus = await loopMemoryPhaseTwoConsolidationAgent(
            threadID: threadID,
            claim: MemoryPhaseTwoClaim(token: "token-terminated-running", watermark: 1),
            store: store,
            status: { await statuses.next() },
            nextEvent: { await events.next() }
        )

        XCTAssertEqual(
            finalStatus,
            .errored("memory consolidation agent exited before final status: Running")
        )
    }

    func testSyncPhaseTwoWorkspaceInputsRebuildsFilesAndPrunesExtensions() throws {
        let root = try temporaryDirectory().appendingPathComponent("memories", isDirectory: true)
        let staleDate = Date(timeIntervalSince1970: 1_700_000_000)
        let now = staleDate.addingTimeInterval(TimeInterval((memoryExtensionResourceRetentionDays + 1) * 24 * 60 * 60))
        let extensionResources = memoryExtensionsRoot(root: root)
            .appendingPathComponent("notes", isDirectory: true)
            .appendingPathComponent(memoryExtensionResourcesSubdirectory, isDirectory: true)
        try FileManager.default.createDirectory(at: extensionResources, withIntermediateDirectories: true)
        try "rules".write(
            to: extensionResources.deletingLastPathComponent()
                .appendingPathComponent(memoryExtensionInstructionsFilename, isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        let staleResource = extensionResources.appendingPathComponent("2023-11-14T22-13-20-old.md", isDirectory: false)
        try "old".write(to: staleResource, atomically: true, encoding: .utf8)

        let memory = stage1Output(
            suffix: 4,
            sourceUpdatedAt: Date(timeIntervalSince1970: 200),
            rawMemory: "\nraw memory\n",
            rolloutSummary: "summary"
        )

        try syncPhaseTwoWorkspaceInputs(root: root, rawMemories: [memory], now: now)

        let rawMemories = try String(contentsOf: rawMemoriesFile(root: root), encoding: .utf8)
        XCTAssertTrue(rawMemories.contains("## Thread `\(memory.threadID)`"))
        XCTAssertTrue(rawMemories.contains("raw memory"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: staleResource.path))
        let summaries = try FileManager.default.contentsOfDirectory(
            at: rolloutSummariesDirectory(root: root),
            includingPropertiesForKeys: nil
        )
        XCTAssertEqual(summaries.count, 1)
    }

    func testBuildMemoryConsolidationAgentConfigLocksDownRuntimeLikeRust() throws {
        let codexHome = try temporaryDirectory()
        var features = FeatureStates.withDefaults()
        for feature in [
            FeatureKey.spawnCsv,
            .collab,
            .memoryTool,
            .apps,
            .plugins,
            .skillMcpDependencyInstall
        ] {
            features.set(feature, enabled: true)
        }
        let source = CodexRuntimeConfig(
            model: "parent-model",
            approvalPolicy: .onRequest,
            sandboxMode: .dangerFullAccess,
            sandboxPolicy: .dangerFullAccess,
            features: features,
            memories: MemoriesConfig(consolidationModel: "custom-consolidator"),
            mcpServers: ["docs": McpServerConfig(transport: .stdio(command: "docs", args: [], env: nil, envVars: [], cwd: nil))]
        )

        let config = try buildMemoryConsolidationAgentConfig(from: source, codexHome: codexHome)
        let rootPath = try AbsolutePath(absolutePath: memoryRoot(codexHome: codexHome).path)

        XCTAssertEqual(config.model, "custom-consolidator")
        XCTAssertEqual(config.modelReasoningEffort, memoryStageTwoReasoningEffort)
        XCTAssertEqual(config.approvalPolicy, .never)
        XCTAssertEqual(config.sandboxPolicy, .workspaceWrite(
            writableRoots: [rootPath],
            networkAccess: false,
            excludeTmpdirEnvVar: true,
            excludeSlashTmp: true
        ))
        XCTAssertEqual(config.permissionProfile, .fromLegacySandboxPolicy(try XCTUnwrap(config.sandboxPolicy)))
        XCTAssertEqual(config.activePermissionProfile, ActivePermissionProfile(id: ":workspace"))
        XCTAssertFalse(config.memories.generateMemories)
        XCTAssertFalse(config.memories.useMemories)
        XCTAssertFalse(config.includeAppsInstructions)
        XCTAssertEqual(config.mcpServers, [:])
        XCTAssertFalse(config.features.isEnabled(.spawnCsv))
        XCTAssertFalse(config.features.isEnabled(.collab))
        XCTAssertFalse(config.features.isEnabled(.memoryTool))
        XCTAssertFalse(config.features.isEnabled(.apps))
        XCTAssertFalse(config.features.isEnabled(.plugins))
        XCTAssertFalse(config.features.isEnabled(.skillMcpDependencyInstall))
    }

    func testBuildMemoryConsolidationAgentPromptWrapsConsolidationPromptAsUserText() throws {
        let root = try temporaryDirectory().appendingPathComponent("memories", isDirectory: true)

        let prompt = buildMemoryConsolidationAgentPrompt(memoryRoot: root)

        XCTAssertEqual(prompt.count, 1)
        XCTAssertEqual(prompt.first, .text(buildConsolidationPrompt(memoryRoot: root)))
    }

    func testPrepareMemoryPhaseTwoConsolidationReturnsSpawnRequestAfterWritingDiff() async throws {
        let codexHome = try temporaryDirectory()
        let threadID = try ThreadId(string: "00000000-0000-4000-8000-000000000201")
        let memory = stage1Output(
            suffix: 201,
            sourceUpdatedAt: Date(timeIntervalSince1970: 500),
            rawMemory: "fresh memory",
            rolloutSummary: "fresh summary"
        )
        let store = RecordingPhaseTwoJobStore(
            claimOutcome: .claimed(ownershipToken: "token-spawn", inputWatermark: 400),
            phase2InputSelection: [memory]
        )
        let recorder = CounterRecorder()
        let config = CodexRuntimeConfig(
            model: "parent-model",
            memories: MemoriesConfig(maxRawMemoriesForConsolidation: 8, maxUnusedDays: 45)
        )

        let outcome = await prepareMemoryPhaseTwoConsolidation(
            threadID: threadID,
            store: store,
            config: config,
            codexHome: codexHome,
            now: Date(timeIntervalSince1970: 600),
            recordCounter: recorder.record
        )

        guard case let .readyToSpawn(request) = outcome else {
            return XCTFail("expected ready-to-spawn outcome, got \(outcome)")
        }
        XCTAssertEqual(request.claim, MemoryPhaseTwoClaim(token: "token-spawn", watermark: 400))
        XCTAssertEqual(request.completionWatermark, 500)
        XCTAssertEqual(request.selectedOutputs, [memory])
        XCTAssertTrue(request.workspaceDiff.hasChanges)
        XCTAssertTrue(request.workspaceDiff.changes.contains(MemoryWorkspaceChange(status: .added, path: "raw_memories.md")))
        XCTAssertEqual(request.agentConfig.model, memoryStageTwoModel)
        XCTAssertEqual(request.prompt, buildMemoryConsolidationAgentPrompt(memoryRoot: memoryRoot(codexHome: codexHome)))

        let selectionRequests = await store.recordedSelectionRequests
        XCTAssertEqual(selectionRequests, [
            RecordingPhaseTwoJobStore.SelectionRequest(limit: 8, maxUnusedDays: 45)
        ])
        let diffFile = memoryRoot(codexHome: codexHome)
            .appendingPathComponent(memoryWorkspaceDiffFilename, isDirectory: false)
        let diffText = try String(contentsOf: diffFile, encoding: .utf8)
        XCTAssertTrue(diffText.contains("Generated by Codex before Phase 2 memory consolidation"))
        XCTAssertTrue(diffText.contains("raw_memories.md"))
        XCTAssertEqual(recorder.events, [
            CounterEvent(
                name: MemoryWriteMetrics.phaseTwoJobs,
                increment: 1,
                labels: [CounterLabel(name: "status", value: "claimed")]
            )
        ])
    }

    func testPrepareMemoryPhaseTwoConsolidationSucceedsWithoutSpawnWhenWorkspaceUnchanged() async throws {
        let codexHome = try temporaryDirectory()
        let root = memoryRoot(codexHome: codexHome)
        let threadID = try ThreadId(string: "00000000-0000-4000-8000-000000000202")
        let memory = stage1Output(
            suffix: 202,
            sourceUpdatedAt: Date(timeIntervalSince1970: 700),
            rawMemory: "stable memory",
            rolloutSummary: "stable summary"
        )
        try prepareMemoryWorkspace(root: root)
        try syncPhaseTwoWorkspaceInputs(root: root, rawMemories: [memory], now: Date(timeIntervalSince1970: 800))
        try resetMemoryWorkspaceBaseline(root: root)

        let store = RecordingPhaseTwoJobStore(
            claimOutcome: .claimed(ownershipToken: "token-no-change", inputWatermark: 650),
            phase2InputSelection: [memory]
        )
        let recorder = CounterRecorder()

        let outcome = await prepareMemoryPhaseTwoConsolidation(
            threadID: threadID,
            store: store,
            config: CodexRuntimeConfig(),
            codexHome: codexHome,
            now: Date(timeIntervalSince1970: 900),
            recordCounter: recorder.record
        )

        XCTAssertEqual(outcome, .succeededNoWorkspaceChanges)
        let succeededRequests = await store.recordedSucceededRequests
        XCTAssertEqual(succeededRequests, [
            RecordingPhaseTwoJobStore.SucceededRequest(
                ownershipToken: "token-no-change",
                completionWatermark: 700,
                selectedOutputs: [memory]
            )
        ])
        let diffFile = root.appendingPathComponent(memoryWorkspaceDiffFilename, isDirectory: false)
        XCTAssertFalse(FileManager.default.fileExists(atPath: diffFile.path))
        XCTAssertEqual(recorder.events, [
            CounterEvent(
                name: MemoryWriteMetrics.phaseTwoJobs,
                increment: 1,
                labels: [CounterLabel(name: "status", value: "claimed")]
            ),
            CounterEvent(
                name: MemoryWriteMetrics.phaseTwoJobs,
                increment: 1,
                labels: [CounterLabel(name: "status", value: "succeeded_no_workspace_changes")]
            )
        ])
    }

    func testPrepareMemoryPhaseTwoConsolidationMarksLoadFailureLikeRust() async throws {
        let codexHome = try temporaryDirectory()
        let threadID = try ThreadId(string: "00000000-0000-4000-8000-000000000203")
        let store = RecordingPhaseTwoJobStore(
            claimOutcome: .claimed(ownershipToken: "token-load-fail", inputWatermark: 10),
            phase2InputError: StoreError.failed
        )
        let recorder = CounterRecorder()

        let outcome = await prepareMemoryPhaseTwoConsolidation(
            threadID: threadID,
            store: store,
            config: CodexRuntimeConfig(),
            codexHome: codexHome,
            recordCounter: recorder.record
        )

        XCTAssertEqual(outcome, .failed("failed_load_stage1_outputs"))
        let failedRequests = await store.recordedFailedRequests
        XCTAssertEqual(failedRequests, [
            RecordingPhaseTwoJobStore.FailedRequest(
                ownershipToken: "token-load-fail",
                reason: "failed_load_stage1_outputs",
                retryDelaySeconds: memoryStageTwoJobRetryDelaySeconds,
                unownedFallback: false
            )
        ])
        XCTAssertEqual(recorder.events, [
            CounterEvent(
                name: MemoryWriteMetrics.phaseTwoJobs,
                increment: 1,
                labels: [CounterLabel(name: "status", value: "claimed")]
            ),
            CounterEvent(
                name: MemoryWriteMetrics.phaseTwoJobs,
                increment: 1,
                labels: [CounterLabel(name: "status", value: "failed_load_stage1_outputs")]
            )
        ])
    }

    func testPrepareMemoryPhaseTwoConsolidationRecordsSkippedClaimLikeRustRun() async throws {
        let codexHome = try temporaryDirectory()
        let threadID = try ThreadId(string: "00000000-0000-4000-8000-000000000204")
        let store = RecordingPhaseTwoJobStore(claimOutcome: .skippedRetryUnavailable)
        let recorder = CounterRecorder()

        let outcome = await prepareMemoryPhaseTwoConsolidation(
            threadID: threadID,
            store: store,
            config: CodexRuntimeConfig(),
            codexHome: codexHome,
            recordCounter: recorder.record
        )

        XCTAssertEqual(outcome, .skipped("skipped_retry_unavailable"))
        XCTAssertEqual(recorder.events, [
            CounterEvent(
                name: MemoryWriteMetrics.phaseTwoJobs,
                increment: 1,
                labels: [CounterLabel(name: "status", value: "skipped_retry_unavailable")]
            )
        ])
    }

    func testRecordMemoryPhaseTwoAgentSpawnedEmitsRustDispatchMetrics() {
        let recorder = CounterRecorder()

        recordMemoryPhaseTwoAgentSpawned(rawMemoryCount: 3, recordCounter: recorder.record)

        XCTAssertEqual(recorder.events, [
            CounterEvent(name: MemoryWriteMetrics.phaseTwoInput, increment: 3, labels: []),
            CounterEvent(
                name: MemoryWriteMetrics.phaseTwoJobs,
                increment: 1,
                labels: [CounterLabel(name: "status", value: "agent_spawned")]
            )
        ])
    }

    func testCompleteMemoryPhaseTwoConsolidationResetsBaselineAndMarksSuccess() async throws {
        let root = try temporaryDirectory().appendingPathComponent("memories", isDirectory: true)
        let memory = stage1Output(suffix: 205, sourceUpdatedAt: Date(timeIntervalSince1970: 900))
        let request = phaseTwoRequest(
            claim: MemoryPhaseTwoClaim(token: "token-complete", watermark: 800),
            completionWatermark: 900,
            selectedOutputs: [memory]
        )
        let store = RecordingPhaseTwoJobStore(
            claimOutcome: .skippedRunning,
            heartbeatResults: [.success(true)]
        )
        let recorder = CounterRecorder()
        let histograms = HistogramRecorder()
        let resetRecorder = ResetRecorder()

        let outcome = await completeMemoryPhaseTwoConsolidation(
            finalStatus: .completed("done"),
            request: request,
            store: store,
            memoryRoot: root,
            tokenUsage: TokenUsage(
                inputTokens: 10,
                cachedInputTokens: 3,
                outputTokens: 4,
                reasoningOutputTokens: 2,
                totalTokens: 14
            ),
            resetBaseline: { try resetRecorder.reset(root: $0) },
            recordCounter: recorder.record,
            recordHistogram: histograms.record
        )

        XCTAssertEqual(outcome, .succeeded)
        let heartbeatRequests = await store.recordedHeartbeatRequests
        XCTAssertEqual(heartbeatRequests, [
            RecordingPhaseTwoJobStore.HeartbeatRequest(
                ownershipToken: "token-complete",
                leaseSeconds: memoryStageTwoJobLeaseSeconds
            )
        ])
        XCTAssertEqual(resetRecorder.roots, [root])
        let succeededRequests = await store.recordedSucceededRequests
        XCTAssertEqual(succeededRequests, [
            RecordingPhaseTwoJobStore.SucceededRequest(
                ownershipToken: "token-complete",
                completionWatermark: 900,
                selectedOutputs: [memory]
            )
        ])
        XCTAssertEqual(recorder.events, [
            CounterEvent(
                name: MemoryWriteMetrics.phaseTwoJobs,
                increment: 1,
                labels: [CounterLabel(name: "status", value: "succeeded")]
            )
        ])
        XCTAssertEqual(histograms.events, [
            HistogramEvent(
                name: MemoryWriteMetrics.phaseTwoTokenUsage,
                value: 14,
                labels: [CounterLabel(name: "token_type", value: "total")]
            ),
            HistogramEvent(
                name: MemoryWriteMetrics.phaseTwoTokenUsage,
                value: 10,
                labels: [CounterLabel(name: "token_type", value: "input")]
            ),
            HistogramEvent(
                name: MemoryWriteMetrics.phaseTwoTokenUsage,
                value: 3,
                labels: [CounterLabel(name: "token_type", value: "cached_input")]
            ),
            HistogramEvent(
                name: MemoryWriteMetrics.phaseTwoTokenUsage,
                value: 4,
                labels: [CounterLabel(name: "token_type", value: "output")]
            ),
            HistogramEvent(
                name: MemoryWriteMetrics.phaseTwoTokenUsage,
                value: 2,
                labels: [CounterLabel(name: "token_type", value: "reasoning_output")]
            )
        ])
    }

    func testCompleteMemoryPhaseTwoConsolidationDoesNotResetWhenOwnershipIsLost() async throws {
        let root = try temporaryDirectory().appendingPathComponent("memories", isDirectory: true)
        let request = phaseTwoRequest(claim: MemoryPhaseTwoClaim(token: "token-lost", watermark: 1))
        let store = RecordingPhaseTwoJobStore(
            claimOutcome: .skippedRunning,
            heartbeatResults: [.success(false)]
        )
        let recorder = CounterRecorder()
        let resetRecorder = ResetRecorder()

        let outcome = await completeMemoryPhaseTwoConsolidation(
            finalStatus: .completed(nil),
            request: request,
            store: store,
            memoryRoot: root,
            resetBaseline: { try resetRecorder.reset(root: $0) },
            recordCounter: recorder.record
        )

        XCTAssertEqual(outcome, .lostOwnership)
        XCTAssertEqual(resetRecorder.roots, [])
        let failedRequests = await store.recordedFailedRequests
        let succeededRequests = await store.recordedSucceededRequests
        XCTAssertEqual(failedRequests, [])
        XCTAssertEqual(succeededRequests, [])
        XCTAssertEqual(recorder.events, [])
    }

    func testCompleteMemoryPhaseTwoConsolidationMarksConfirmOwnershipFailure() async throws {
        let root = try temporaryDirectory().appendingPathComponent("memories", isDirectory: true)
        let request = phaseTwoRequest(claim: MemoryPhaseTwoClaim(token: "token-confirm", watermark: 1))
        let store = RecordingPhaseTwoJobStore(
            claimOutcome: .skippedRunning,
            heartbeatResults: [.failure(StoreError.failed)]
        )
        let recorder = CounterRecorder()

        let outcome = await completeMemoryPhaseTwoConsolidation(
            finalStatus: .completed(nil),
            request: request,
            store: store,
            memoryRoot: root,
            recordCounter: recorder.record
        )

        XCTAssertEqual(outcome, .failed("failed_confirm_ownership"))
        let failedRequests = await store.recordedFailedRequests
        XCTAssertEqual(failedRequests, [
            RecordingPhaseTwoJobStore.FailedRequest(
                ownershipToken: "token-confirm",
                reason: "failed_confirm_ownership",
                retryDelaySeconds: memoryStageTwoJobRetryDelaySeconds,
                unownedFallback: false
            )
        ])
        XCTAssertEqual(recorder.events, [
            CounterEvent(
                name: MemoryWriteMetrics.phaseTwoJobs,
                increment: 1,
                labels: [CounterLabel(name: "status", value: "failed_confirm_ownership")]
            )
        ])
    }

    func testCompleteMemoryPhaseTwoConsolidationMarksWorkspaceCommitFailure() async throws {
        let root = try temporaryDirectory().appendingPathComponent("memories", isDirectory: true)
        let request = phaseTwoRequest(claim: MemoryPhaseTwoClaim(token: "token-reset", watermark: 1))
        let store = RecordingPhaseTwoJobStore(
            claimOutcome: .skippedRunning,
            heartbeatResults: [.success(true)]
        )
        let recorder = CounterRecorder()

        let outcome = await completeMemoryPhaseTwoConsolidation(
            finalStatus: .completed(nil),
            request: request,
            store: store,
            memoryRoot: root,
            resetBaseline: { _ in throw StoreError.failed },
            recordCounter: recorder.record
        )

        XCTAssertEqual(outcome, .failed("failed_workspace_commit"))
        let failedRequests = await store.recordedFailedRequests
        XCTAssertEqual(failedRequests, [
            RecordingPhaseTwoJobStore.FailedRequest(
                ownershipToken: "token-reset",
                reason: "failed_workspace_commit",
                retryDelaySeconds: memoryStageTwoJobRetryDelaySeconds,
                unownedFallback: false
            )
        ])
    }

    func testCompleteMemoryPhaseTwoConsolidationMarksFailedAgentForNonCompletedStatus() async throws {
        let root = try temporaryDirectory().appendingPathComponent("memories", isDirectory: true)
        let request = phaseTwoRequest(claim: MemoryPhaseTwoClaim(token: "token-agent", watermark: 1))
        let store = RecordingPhaseTwoJobStore(claimOutcome: .skippedRunning)
        let recorder = CounterRecorder()
        let resetRecorder = ResetRecorder()

        let outcome = await completeMemoryPhaseTwoConsolidation(
            finalStatus: .errored("boom"),
            request: request,
            store: store,
            memoryRoot: root,
            resetBaseline: { try resetRecorder.reset(root: $0) },
            recordCounter: recorder.record
        )

        XCTAssertEqual(outcome, .failed("failed_agent"))
        XCTAssertEqual(resetRecorder.roots, [])
        let failedRequests = await store.recordedFailedRequests
        XCTAssertEqual(failedRequests, [
            RecordingPhaseTwoJobStore.FailedRequest(
                ownershipToken: "token-agent",
                reason: "failed_agent",
                retryDelaySeconds: memoryStageTwoJobRetryDelaySeconds,
                unownedFallback: false
            )
        ])
    }

    func testRecordMemoryPhaseTwoTokenUsageClampsNegativeValuesLikeRustMetrics() {
        let histograms = HistogramRecorder()

        recordMemoryPhaseTwoTokenUsage(
            TokenUsage(
                inputTokens: -1,
                cachedInputTokens: -2,
                outputTokens: -3,
                reasoningOutputTokens: -4,
                totalTokens: -5
            ),
            recordHistogram: histograms.record
        )

        XCTAssertEqual(histograms.events.map(\.value), [0, 0, 0, 0, 0])
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-swift-memory-phase-two-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

private final class CounterRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [CounterEvent] = []

    var events: [CounterEvent] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func record(name: String, increment: Int64, labels: [(String, String)]) {
        lock.lock()
        storage.append(CounterEvent(name: name, increment: increment, labels: labels.map {
            CounterLabel(name: $0.0, value: $0.1)
        }))
        lock.unlock()
    }
}

private struct CounterLabel: Equatable, Sendable {
    var name: String
    var value: String
}

private struct CounterEvent: Equatable, Sendable {
    var name: String
    var increment: Int64
    var labels: [CounterLabel]
}

private final class HistogramRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [HistogramEvent] = []

    var events: [HistogramEvent] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func record(name: String, value: Int64, labels: [(String, String)]) {
        lock.lock()
        storage.append(HistogramEvent(name: name, value: value, labels: labels.map {
            CounterLabel(name: $0.0, value: $0.1)
        }))
        lock.unlock()
    }
}

private struct HistogramEvent: Equatable, Sendable {
    var name: String
    var value: Int64
    var labels: [CounterLabel]
}

private final class ResetRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [URL] = []

    var roots: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func reset(root: URL) throws {
        lock.lock()
        storage.append(root)
        lock.unlock()
    }
}

private actor AgentStatusSequence {
    private var statuses: [AgentStatus]
    private var index = 0

    init(_ statuses: [AgentStatus]) {
        self.statuses = statuses
    }

    func next() -> AgentStatus {
        guard !statuses.isEmpty else {
            return .running
        }
        if index >= statuses.count {
            return statuses[statuses.count - 1]
        }
        defer { index += 1 }
        return statuses[index]
    }
}

private actor AgentLoopEventSequence {
    private var events: [MemoryPhaseTwoAgentLoopEvent]

    init(_ events: [MemoryPhaseTwoAgentLoopEvent]) {
        self.events = events
    }

    func next() -> MemoryPhaseTwoAgentLoopEvent {
        guard !events.isEmpty else {
            return .statusPoll
        }
        return events.removeFirst()
    }
}

private enum StoreError: Error, CustomStringConvertible {
    case failed

    var description: String { "failed" }
}

private actor RecordingPhaseTwoJobStore: MemoryPhaseTwoJobStore {
    struct ClaimRequest: Equatable, Sendable {
        var threadID: ThreadId
        var leaseSeconds: Int64
    }

    struct FailedRequest: Equatable, Sendable {
        var ownershipToken: String
        var reason: String
        var retryDelaySeconds: Int64
        var unownedFallback: Bool
    }

    struct SucceededRequest: Equatable, Sendable {
        var ownershipToken: String
        var completionWatermark: Int64
        var selectedOutputs: [Stage1Output]
    }

    struct SelectionRequest: Equatable, Sendable {
        var limit: Int
        var maxUnusedDays: Int64
    }

    struct HeartbeatRequest: Equatable, Sendable {
        var ownershipToken: String
        var leaseSeconds: Int64
    }

    enum HeartbeatResult: Sendable {
        case success(Bool)
        case failure(StoreError)
    }

    private let claimOutcome: Phase2JobClaimOutcome
    private let claimError: Error?
    private let phase2InputSelection: [Stage1Output]
    private let phase2InputError: Error?
    private var heartbeatResults: [HeartbeatResult]
    private let markFailedResult: Bool
    private let markFailedIfUnownedResult: Bool
    private let markSucceededResult: Bool
    private(set) var claimRequests: [ClaimRequest] = []
    private(set) var failedRequests: [FailedRequest] = []
    private(set) var succeededRequests: [SucceededRequest] = []
    private(set) var selectionRequests: [SelectionRequest] = []
    private(set) var heartbeatRequests: [HeartbeatRequest] = []

    var recordedClaimRequests: [ClaimRequest] { claimRequests }
    var recordedFailedRequests: [FailedRequest] { failedRequests }
    var recordedSucceededRequests: [SucceededRequest] { succeededRequests }
    var recordedSelectionRequests: [SelectionRequest] { selectionRequests }
    var recordedHeartbeatRequests: [HeartbeatRequest] { heartbeatRequests }

    init(
        claimOutcome: Phase2JobClaimOutcome,
        claimError: Error? = nil,
        phase2InputSelection: [Stage1Output] = [],
        phase2InputError: Error? = nil,
        heartbeatResults: [HeartbeatResult] = [],
        markFailedResult: Bool = true,
        markFailedIfUnownedResult: Bool = false,
        markSucceededResult: Bool = true
    ) {
        self.claimOutcome = claimOutcome
        self.claimError = claimError
        self.phase2InputSelection = phase2InputSelection
        self.phase2InputError = phase2InputError
        self.heartbeatResults = heartbeatResults
        self.markFailedResult = markFailedResult
        self.markFailedIfUnownedResult = markFailedIfUnownedResult
        self.markSucceededResult = markSucceededResult
    }

    func getPhase2InputSelection(
        limit: Int,
        maxUnusedDays: Int64
    ) async throws -> [Stage1Output] {
        selectionRequests.append(SelectionRequest(limit: limit, maxUnusedDays: maxUnusedDays))
        if let phase2InputError {
            throw phase2InputError
        }
        return phase2InputSelection
    }

    func tryClaimGlobalPhase2Job(
        threadID: ThreadId,
        leaseSeconds: Int64
    ) async throws -> Phase2JobClaimOutcome {
        claimRequests.append(ClaimRequest(threadID: threadID, leaseSeconds: leaseSeconds))
        if let claimError {
            throw claimError
        }
        return claimOutcome
    }

    func markGlobalPhase2JobFailed(
        ownershipToken: String,
        reason: String,
        retryDelaySeconds: Int64
    ) async throws -> Bool {
        failedRequests.append(FailedRequest(
            ownershipToken: ownershipToken,
            reason: reason,
            retryDelaySeconds: retryDelaySeconds,
            unownedFallback: false
        ))
        return markFailedResult
    }

    func markGlobalPhase2JobFailedIfUnowned(
        ownershipToken: String,
        reason: String,
        retryDelaySeconds: Int64
    ) async throws -> Bool {
        failedRequests.append(FailedRequest(
            ownershipToken: ownershipToken,
            reason: reason,
            retryDelaySeconds: retryDelaySeconds,
            unownedFallback: true
        ))
        return markFailedIfUnownedResult
    }

    func heartbeatGlobalPhase2Job(
        ownershipToken: String,
        leaseSeconds: Int64
    ) async throws -> Bool {
        heartbeatRequests.append(HeartbeatRequest(ownershipToken: ownershipToken, leaseSeconds: leaseSeconds))
        guard !heartbeatResults.isEmpty else {
            return true
        }
        switch heartbeatResults.removeFirst() {
        case let .success(stillOwnsLock):
            return stillOwnsLock
        case let .failure(error):
            throw error
        }
    }

    func markGlobalPhase2JobSucceeded(
        ownershipToken: String,
        completionWatermark: Int64,
        selectedOutputs: [Stage1Output]
    ) async throws -> Bool {
        succeededRequests.append(SucceededRequest(
            ownershipToken: ownershipToken,
            completionWatermark: completionWatermark,
            selectedOutputs: selectedOutputs
        ))
        return markSucceededResult
    }
}

private func phaseTwoRequest(
    claim: MemoryPhaseTwoClaim,
    completionWatermark: Int64 = 1,
    selectedOutputs: [Stage1Output] = []
) -> MemoryPhaseTwoConsolidationRequest {
    MemoryPhaseTwoConsolidationRequest(
        claim: claim,
        completionWatermark: completionWatermark,
        selectedOutputs: selectedOutputs,
        agentConfig: CodexRuntimeConfig(),
        prompt: [],
        workspaceDiff: MemoryWorkspaceDiff(changes: [], unifiedDiff: "")
    )
}

private func phaseTwoThreadID(suffix: Int) throws -> ThreadId {
    try ThreadId(string: String(format: "00000000-0000-4000-8000-%012d", suffix))
}

private func stage1Output(
    suffix: Int,
    sourceUpdatedAt: Date,
    rawMemory: String = "raw",
    rolloutSummary: String = "summary"
) -> Stage1Output {
    Stage1Output(
        threadID: try! phaseTwoThreadID(suffix: suffix),
        rolloutPath: "/tmp/rollout-\(suffix).jsonl",
        sourceUpdatedAt: sourceUpdatedAt,
        rawMemory: rawMemory,
        rolloutSummary: rolloutSummary,
        rolloutSlug: "slug-\(suffix)",
        cwd: "/tmp/project-\(suffix)",
        generatedAt: sourceUpdatedAt.addingTimeInterval(1)
    )
}
