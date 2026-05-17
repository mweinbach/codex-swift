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
        let registry = builder.build()

        XCTAssertEqual(registry.threadLifecycleContributors.count, 1)
        XCTAssertEqual(registry.turnLifecycleContributors.count, 1)
        XCTAssertEqual(registry.configContributors.count, 1)
        XCTAssertEqual(registry.tokenUsageContributors.count, 1)
        XCTAssertTrue(ExtensionRegistry.empty.threadLifecycleContributors.isEmpty)
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
}
