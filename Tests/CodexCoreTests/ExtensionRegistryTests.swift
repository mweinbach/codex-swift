import CodexCore
import XCTest

final class ExtensionRegistryTests: XCTestCase {
    private struct SessionMarker: Sendable, Equatable {
        let value: String
    }

    private struct ThreadMarker: Sendable, Equatable {
        let value: String
    }

    private struct TurnMarker: Sendable, Equatable {
        let value: String
    }

    private struct ContextRecorder: ExtensionContextContributor {
        func contribute(
            sessionStore: ExtensionData,
            threadStore: ExtensionData
        ) async -> [ExtensionPromptFragment] {
            [
                .developerPolicy(sessionStore.get(SessionMarker.self)?.value ?? "missing-session"),
                .developerCapability(threadStore.get(ThreadMarker.self)?.value ?? "missing-thread"),
                .contextualUser("context"),
                .separateDeveloper("separate")
            ]
        }
    }

    private struct ToolRecorder: ExtensionToolContributor {
        func tools(sessionStore: ExtensionData, threadStore: ExtensionData) -> [ExtensionTool] {
            [
                ExtensionTool(
                    spec: .function(ResponsesAPITool(
                        name: "extension/echo",
                        description: "Echo through extension",
                        parameters: .object(
                            properties: [:],
                            required: [],
                            additionalProperties: .boolean(false)
                        )
                    )),
                    supportsParallelToolCalls: true,
                    executor: { item in
                        switch item {
                        case let .functionCall(_, _, _, arguments, _),
                             let .customToolCall(_, _, _, _, arguments):
                            return JSONToolOutput(.object(["arguments": .string(arguments)]))
                        default:
                            return JSONToolOutput(.string("ok"))
                        }
                    }
                )
            ]
        }
    }

    private struct ApprovalRecorder: ExtensionApprovalReviewContributor {
        let decision: ReviewDecision?

        func contribute(
            sessionStore: ExtensionData,
            threadStore: ExtensionData,
            prompt: String
        ) async -> ReviewDecision? {
            prompt.contains("claim") ? decision : nil
        }
    }

    private struct TurnItemRecorder: ExtensionTurnItemContributor {
        func contribute(
            threadStore: ExtensionData,
            turnStore: ExtensionData,
            item: TurnItem
        ) async throws -> TurnItem {
            guard case let .agentMessage(message) = item else {
                return item
            }
            let suffix = turnStore.get(TurnMarker.self)?.value ?? "missing-turn"
            return .agentMessage(AgentMessageItem(
                id: message.id,
                content: message.content + [.text(" \(suffix)")],
                phase: message.phase,
                memoryCitation: message.memoryCitation
            ))
        }
    }

    private final class Recorder:
        ExtensionThreadLifecycleContributor,
        ExtensionTurnLifecycleContributor,
        ExtensionConfigContributor,
        ExtensionTokenUsageContributor,
        @unchecked Sendable
    {
        private let lock = NSLock()
        private var values: [String] = []

        var records: [String] {
            lock.withLock { values }
        }

        func onThreadStart(_ input: ExtensionThreadStartInput) {
            append("thread-start:\(input.threadID):\(input.config.model ?? "nil")")
        }

        func onThreadResume(_ input: ExtensionThreadResumeInput) {
            append("thread-resume:\(input.sessionStore.get(SessionMarker.self)?.value ?? "missing")")
        }

        func onThreadStop(_ input: ExtensionThreadStopInput) {
            append("thread-stop:\(input.threadStore.get(ThreadMarker.self)?.value ?? "missing")")
        }

        func onTurnStart(_ input: ExtensionTurnStartInput) {
            append("turn-start:\(input.turnID):\(input.turnStore.get(TurnMarker.self)?.value ?? "missing")")
        }

        func onTurnStop(_ input: ExtensionTurnStopInput) {
            append("turn-stop:\(input.turnID)")
        }

        func onTurnAbort(_ input: ExtensionTurnAbortInput) {
            append("turn-abort:\(input.turnID):\(input.reason.rawValue)")
        }

        func onConfigChanged(_ input: ExtensionConfigChangedInput) {
            append("config:\(input.previousConfig.model ?? "nil")->\(input.newConfig.model ?? "nil")")
        }

        func onTokenUsage(
            sessionStore: ExtensionData,
            threadStore: ExtensionData,
            turnStore: ExtensionData,
            threadID: ThreadId,
            turnID: String,
            tokenUsage: TokenUsageInfo
        ) {
            append("tokens:\(turnID):\(tokenUsage.totalTokenUsage.totalTokens)")
        }

        private func append(_ value: String) {
            lock.withLock {
                values.append(value)
            }
        }
    }

    func testExtensionDataStoresValuesByConcreteTypeLikeRust() {
        let data = ExtensionData(id: "turn-1")

        data.insert(SessionMarker(value: "session"))
        data.insert(ThreadMarker(value: "thread"))

        XCTAssertEqual(data.id, "turn-1")
        XCTAssertEqual(data.get(SessionMarker.self), SessionMarker(value: "session"))
        XCTAssertEqual(data.get(ThreadMarker.self), ThreadMarker(value: "thread"))
        XCTAssertNil(data.get(TurnMarker.self))
        XCTAssertEqual(data.remove(SessionMarker.self), SessionMarker(value: "session"))
        XCTAssertNil(data.get(SessionMarker.self))
    }

    func testRegistryBuilderPreservesContributorFamiliesLikeRustExtensionAPI() {
        let recorder = Recorder()
        var builder = ExtensionRegistryBuilder()

        builder.threadLifecycleContributor(recorder)
        builder.turnLifecycleContributor(recorder)
        builder.configContributor(recorder)
        builder.tokenUsageContributor(recorder)
        builder.promptContributor(ContextRecorder())
        builder.toolContributor(ToolRecorder())
        builder.approvalReviewContributor(ApprovalRecorder(decision: .approved))
        builder.turnItemContributor(TurnItemRecorder())
        let registry = builder.build()

        XCTAssertEqual(registry.threadLifecycleContributors.count, 1)
        XCTAssertEqual(registry.turnLifecycleContributors.count, 1)
        XCTAssertEqual(registry.configContributors.count, 1)
        XCTAssertEqual(registry.tokenUsageContributors.count, 1)
        XCTAssertEqual(registry.contextContributors.count, 1)
        XCTAssertEqual(registry.toolContributors.count, 1)
        XCTAssertEqual(registry.approvalReviewContributors.count, 1)
        XCTAssertEqual(registry.turnItemContributors.count, 1)
        XCTAssertTrue(ExtensionRegistry.empty.threadLifecycleContributors.isEmpty)
        XCTAssertTrue(ExtensionRegistry.empty.contextContributors.isEmpty)
    }

    func testContributorInputsCarryStableStoresAndSnapshotsLikeRust() {
        let threadID = ThreadId(uuid: UUID(uuidString: "123e4567-e89b-12d3-a456-426614174000")!)
        let sessionStore = ExtensionData(id: "session")
        let threadStore = ExtensionData(id: "thread")
        let turnStore = ExtensionData(id: "turn")
        sessionStore.insert(SessionMarker(value: "session-ok"))
        threadStore.insert(ThreadMarker(value: "thread-ok"))
        turnStore.insert(TurnMarker(value: "turn-ok"))

        var previousConfig = CodexRuntimeConfig()
        previousConfig.model = "gpt-before"
        var newConfig = previousConfig
        newConfig.model = "gpt-after"
        let recorder = Recorder()
        var builder = ExtensionRegistryBuilder()
        builder.threadLifecycleContributor(recorder)
        builder.turnLifecycleContributor(recorder)
        builder.configContributor(recorder)
        builder.tokenUsageContributor(recorder)
        let registry = builder.build()

        registry.threadLifecycleContributors.forEach {
            $0.onThreadStart(ExtensionThreadStartInput(
                threadID: threadID,
                config: previousConfig,
                sessionStore: sessionStore,
                threadStore: threadStore
            ))
            $0.onThreadResume(ExtensionThreadResumeInput(
                threadID: threadID,
                sessionStore: sessionStore,
                threadStore: threadStore
            ))
            $0.onThreadStop(ExtensionThreadStopInput(
                threadID: threadID,
                sessionStore: sessionStore,
                threadStore: threadStore
            ))
        }
        registry.turnLifecycleContributors.forEach {
            $0.onTurnStart(ExtensionTurnStartInput(
                threadID: threadID,
                turnID: "turn-1",
                sessionStore: sessionStore,
                threadStore: threadStore,
                turnStore: turnStore
            ))
            $0.onTurnStop(ExtensionTurnStopInput(
                threadID: threadID,
                turnID: "turn-1",
                sessionStore: sessionStore,
                threadStore: threadStore,
                turnStore: turnStore
            ))
            $0.onTurnAbort(ExtensionTurnAbortInput(
                threadID: threadID,
                turnID: "turn-2",
                reason: .interrupted,
                sessionStore: sessionStore,
                threadStore: threadStore,
                turnStore: turnStore
            ))
        }
        registry.configContributors.forEach {
            $0.onConfigChanged(ExtensionConfigChangedInput(
                threadID: threadID,
                sessionStore: sessionStore,
                threadStore: threadStore,
                previousConfig: previousConfig,
                newConfig: newConfig
            ))
        }
        registry.tokenUsageContributors.forEach {
            $0.onTokenUsage(
                sessionStore: sessionStore,
                threadStore: threadStore,
                turnStore: turnStore,
                threadID: threadID,
                turnID: "turn-1",
                tokenUsage: TokenUsageInfo(
                    totalTokenUsage: TokenUsage(totalTokens: 42),
                    lastTokenUsage: TokenUsage(totalTokens: 42)
                )
            )
        }

        XCTAssertEqual(recorder.records, [
            "thread-start:\(threadID):gpt-before",
            "thread-resume:session-ok",
            "thread-stop:thread-ok",
            "turn-start:turn-1:turn-ok",
            "turn-stop:turn-1",
            "turn-abort:turn-2:interrupted",
            "config:gpt-before->gpt-after",
            "tokens:turn-1:42"
        ])
    }

    func testPromptToolApprovalAndTurnItemContributorsMatchRustRegistryFamilies() async throws {
        let sessionStore = ExtensionData(id: "session")
        let threadStore = ExtensionData(id: "thread")
        let turnStore = ExtensionData(id: "turn")
        sessionStore.insert(SessionMarker(value: "session-prompt"))
        threadStore.insert(ThreadMarker(value: "thread-prompt"))
        turnStore.insert(TurnMarker(value: "turn-item"))

        var builder = ExtensionRegistryBuilder()
        builder.promptContributor(ContextRecorder())
        builder.toolContributor(ToolRecorder())
        builder.approvalReviewContributor(ApprovalRecorder(decision: nil))
        builder.approvalReviewContributor(ApprovalRecorder(decision: .approvedForSession))
        builder.turnItemContributor(TurnItemRecorder())
        let registry = builder.build()

        let fragments = await registry.contextContributors[0].contribute(
            sessionStore: sessionStore,
            threadStore: threadStore
        )
        XCTAssertEqual(fragments, [
            ExtensionPromptFragment(slot: .developerPolicy, text: "session-prompt"),
            ExtensionPromptFragment(slot: .developerCapabilities, text: "thread-prompt"),
            ExtensionPromptFragment(slot: .contextualUser, text: "context"),
            ExtensionPromptFragment(slot: .separateDeveloper, text: "separate")
        ])

        let tools = registry.toolContributors.flatMap {
            $0.tools(sessionStore: sessionStore, threadStore: threadStore)
        }
        XCTAssertEqual(tools.map(\.spec.name), ["extension/echo"])
        XCTAssertEqual(tools.map(\.supportsParallelToolCalls), [true])
        let executed = try await tools[0].execute(.functionCallOutput(
            callID: "call-1",
            output: FunctionCallOutputPayload(content: "ok")
        ))
        XCTAssertEqual(
            executed.output,
            .functionCallOutput(callID: "call-1", output: FunctionCallOutputPayload(content: #""ok""#, success: true))
        )

        let approval = await registry.approvalReview(
            sessionStore: sessionStore,
            threadStore: threadStore,
            prompt: "please claim this"
        )
        XCTAssertEqual(approval, .approvedForSession)

        var item = TurnItem.agentMessage(AgentMessageItem(
            id: "msg-1",
            content: [.text("hello")],
            phase: nil,
            memoryCitation: nil
        ))
        for contributor in registry.turnItemContributors {
            item = try await contributor.contribute(
                threadStore: threadStore,
                turnStore: turnStore,
                item: item
            )
        }
        guard case let .agentMessage(message) = item else {
            return XCTFail("expected agent message")
        }
        XCTAssertEqual(message.text, "hello turn-item")
    }

    func testJSONToolOutputMatchesRustToolOutputContract() {
        let output = JSONToolOutput(.object(["ok": .bool(true)]), success: nil)

        XCTAssertEqual(output.logPreview(), #"{"ok":true}"#)
        XCTAssertTrue(output.successForLogging())
        XCTAssertEqual(output.postToolUseResponse(callID: "call-1", for: .other), .object(["ok": .bool(true)]))
        XCTAssertEqual(output.codeModeResult(isCustomToolCall: false), .object(["ok": .bool(true)]))
        XCTAssertEqual(
            output.toResponseItem(callID: "call-1", isCustomToolCall: false, customToolName: nil),
            .functionCallOutput(
                callID: "call-1",
                output: FunctionCallOutputPayload(content: #"{"ok":true}"#, success: nil)
            )
        )
        XCTAssertEqual(
            output.toResponseItem(callID: "custom-1", isCustomToolCall: true, customToolName: "extension/echo"),
            .customToolCallOutput(
                callID: "custom-1",
                name: "extension/echo",
                output: FunctionCallOutputPayload(content: #"{"ok":true}"#, success: nil)
            )
        )
    }

    func testToolOutputTelemetryPreviewUsesRustLimits() {
        let longLine = String(repeating: "é", count: 2_000)
        let bytePreview = JSONToolOutput.telemetryPreview(longLine)
        XCTAssertTrue(bytePreview.hasSuffix("[... telemetry preview truncated ...]"))
        XCTAssertLessThanOrEqual(bytePreview.utf8.count, 2_100)
        XCTAssertFalse(bytePreview.contains("\u{FFFD}"))

        let manyLines = (0..<70).map { "line-\($0)" }.joined(separator: "\n")
        let linePreview = JSONToolOutput.telemetryPreview(manyLines)
        XCTAssertTrue(linePreview.contains("line-63\n[... telemetry preview truncated ...]"))
        XCTAssertFalse(linePreview.contains("line-64"))
    }

    func testMemoriesExtensionOwnsPromptStateAcrossThreadStartAndConfigChangeLikeRust() async throws {
        let codexHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-swift-memories-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: codexHome) }

        let memories = codexHome.appendingPathComponent("memories", isDirectory: true)
        try FileManager.default.createDirectory(at: memories, withIntermediateDirectories: true)
        try "Remember extension-owned prompt state.".write(
            to: memories.appendingPathComponent("memory_summary.md", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )

        var builder = ExtensionRegistryBuilder()
        installMemoriesExtension(into: &builder, codexHome: codexHome)
        let registry = builder.build()
        XCTAssertEqual(registry.threadLifecycleContributors.count, 1)
        XCTAssertEqual(registry.configContributors.count, 1)
        XCTAssertEqual(registry.contextContributors.count, 1)
        XCTAssertTrue(registry.toolContributors.isEmpty)

        let sessionStore = ExtensionData(id: "session")
        let threadStore = ExtensionData(id: "thread")
        let threadID = ThreadId(uuid: UUID(uuidString: "123e4567-e89b-12d3-a456-426614174001")!)
        let enabledConfig = memoryConfig(enabled: true, useMemories: true)
        registry.threadLifecycleContributors[0].onThreadStart(ExtensionThreadStartInput(
            threadID: threadID,
            config: enabledConfig,
            sessionStore: sessionStore,
            threadStore: threadStore
        ))

        var fragments = await registry.contextContributors[0].contribute(
            sessionStore: sessionStore,
            threadStore: threadStore
        )
        XCTAssertEqual(fragments.count, 1)
        XCTAssertEqual(fragments[0].slot, .developerPolicy)
        XCTAssertTrue(fragments[0].text.contains("Remember extension-owned prompt state."))

        let disabledConfig = memoryConfig(enabled: true, useMemories: false)
        registry.configContributors[0].onConfigChanged(ExtensionConfigChangedInput(
            threadID: threadID,
            sessionStore: sessionStore,
            threadStore: threadStore,
            previousConfig: enabledConfig,
            newConfig: disabledConfig
        ))
        fragments = await registry.contextContributors[0].contribute(
            sessionStore: sessionStore,
            threadStore: threadStore
        )
        XCTAssertTrue(fragments.isEmpty)

        registry.configContributors[0].onConfigChanged(ExtensionConfigChangedInput(
            threadID: threadID,
            sessionStore: sessionStore,
            threadStore: threadStore,
            previousConfig: disabledConfig,
            newConfig: enabledConfig
        ))
        fragments = await registry.contextContributors[0].contribute(
            sessionStore: sessionStore,
            threadStore: threadStore
        )
        XCTAssertEqual(fragments.count, 1)
        XCTAssertEqual(threadStore.get(MemoriesExtensionConfig.self), .fromRuntimeConfig(
            enabledConfig,
            codexHome: codexHome
        ))
    }

    private func memoryConfig(enabled: Bool, useMemories: Bool) -> CodexRuntimeConfig {
        var features = FeatureStates.withDefaults()
        features.set(.memoryTool, enabled: enabled)
        return CodexRuntimeConfig(
            modelProvider: "test-provider",
            features: features,
            memories: MemoriesConfig(useMemories: useMemories),
            projectDocMaxBytes: 0
        )
    }
}
