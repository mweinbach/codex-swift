@testable import CodexAppServer
import XCTest

final class RequestSerializationTests: XCTestCase {
    func testConfigFamilyReadMethodsUseSharedReadScopeLikeRust() {
        XCTAssertEqual(CodexAppServer.requestSerializationScope(forMethod: "config/read"), .globalSharedRead("config"))
        XCTAssertEqual(CodexAppServer.requestSerializationScope(forMethod: "skills/list"), .globalSharedRead("config"))

        XCTAssertEqual(CodexAppServer.requestSerializationScope(forMethod: "config/value/write"), .global("config"))
        XCTAssertEqual(CodexAppServer.requestSerializationScope(forMethod: "config/batchWrite"), .global("config"))
        XCTAssertEqual(CodexAppServer.requestSerializationScope(forMethod: "skills/config/write"), .global("config"))
    }

    func testRustRequestScopeTableCoversKeyedFamilies() {
        XCTAssertEqual(
            CodexAppServer.requestSerializationScope(forMethod: "thread/resume", params: ["threadId": "thread-1"]),
            .thread(threadID: "thread-1")
        )
        XCTAssertEqual(
            CodexAppServer.requestSerializationScope(forMethod: "thread/resume", params: ["threadId": "", "path": "/tmp/thread.jsonl"]),
            .threadPath("/tmp/thread.jsonl")
        )
        XCTAssertEqual(
            CodexAppServer.requestSerializationScope(forMethod: "thread/fork", params: [:]),
            .thread(threadID: "")
        )
        for method in [
            "thread/archive",
            "thread/unsubscribe",
            "thread/increment_elicitation",
            "thread/decrement_elicitation",
            "thread/name/set",
            "thread/goal/set",
            "thread/goal/get",
            "thread/goal/clear",
            "thread/metadata/update",
            "thread/memoryMode/set",
            "thread/unarchive",
            "thread/compact/start",
            "thread/shellCommand",
            "thread/approveGuardianDeniedAction",
            "thread/backgroundTerminals/clean",
            "thread/rollback",
            "thread/read",
            "thread/inject_items",
            "turn/start",
            "turn/steer",
            "turn/interrupt",
            "thread/realtime/start",
            "thread/realtime/appendAudio",
            "thread/realtime/appendText",
            "thread/realtime/stop",
            "review/start",
            "mcpServer/tool/call"
        ] {
            XCTAssertEqual(
                CodexAppServer.requestSerializationScope(forMethod: method, params: ["threadId": "thread-2"]),
                .thread(threadID: "thread-2"),
                method
            )
        }

        XCTAssertEqual(
            CodexAppServer.requestSerializationScope(forMethod: "mcpServer/resource/read", params: ["threadId": "thread-3"]),
            .thread(threadID: "thread-3")
        )
        XCTAssertNil(CodexAppServer.requestSerializationScope(forMethod: "mcpServer/resource/read", params: [:]))

        XCTAssertEqual(
            CodexAppServer.requestSerializationScope(forMethod: "command/exec", params: ["processId": "proc-1"]),
            .commandExecProcess(processID: "proc-1")
        )
        XCTAssertNil(CodexAppServer.requestSerializationScope(forMethod: "command/exec", params: [:]))
        XCTAssertEqual(
            CodexAppServer.requestSerializationScope(forMethod: "command/exec/write", params: ["processId": "proc-1"]),
            .commandExecProcess(processID: "proc-1")
        )
        XCTAssertEqual(
            CodexAppServer.requestSerializationScope(forMethod: "command/exec/terminate", params: ["processId": "proc-1"]),
            .commandExecProcess(processID: "proc-1")
        )
        XCTAssertEqual(
            CodexAppServer.requestSerializationScope(forMethod: "command/exec/resize", params: ["processId": "proc-1"]),
            .commandExecProcess(processID: "proc-1")
        )
        XCTAssertEqual(
            CodexAppServer.requestSerializationScope(forMethod: "process/spawn", params: ["processHandle": "handle-1"]),
            .process(processHandle: "handle-1")
        )
        XCTAssertEqual(
            CodexAppServer.requestSerializationScope(forMethod: "process/writeStdin", params: ["processHandle": "handle-1"]),
            .process(processHandle: "handle-1")
        )
        XCTAssertEqual(
            CodexAppServer.requestSerializationScope(forMethod: "process/kill", params: ["processHandle": "handle-1"]),
            .process(processHandle: "handle-1")
        )
        XCTAssertEqual(
            CodexAppServer.requestSerializationScope(forMethod: "process/resizePty", params: ["processHandle": "handle-1"]),
            .process(processHandle: "handle-1")
        )
        XCTAssertEqual(
            CodexAppServer.requestSerializationScope(forMethod: "fs/watch", params: ["watchId": "watch-1"]),
            .fsWatch(watchID: "watch-1")
        )
        XCTAssertEqual(
            CodexAppServer.requestSerializationScope(forMethod: "fs/unwatch", params: ["watchId": "watch-1"]),
            .fsWatch(watchID: "watch-1")
        )
        XCTAssertEqual(
            CodexAppServer.requestSerializationScope(forMethod: "fuzzyFileSearch/sessionStart", params: ["sessionId": "search-1"]),
            .fuzzyFileSearchSession(sessionID: "search-1")
        )
        XCTAssertEqual(
            CodexAppServer.requestSerializationScope(forMethod: "fuzzyFileSearch/sessionUpdate", params: ["sessionId": "search-1"]),
            .fuzzyFileSearchSession(sessionID: "search-1")
        )
        XCTAssertEqual(
            CodexAppServer.requestSerializationScope(forMethod: "fuzzyFileSearch/sessionStop", params: ["sessionId": "search-1"]),
            .fuzzyFileSearchSession(sessionID: "search-1")
        )
        XCTAssertEqual(
            CodexAppServer.requestSerializationScope(forMethod: "mcpServer/oauth/login", params: ["name": "server-a"]),
            .mcpOauth(serverName: "server-a")
        )
    }

    func testRustRequestScopeTableCoversGlobalFamilies() {
        for method in [
            "plugin/skill/read",
            "plugin/share/save",
            "plugin/share/updateTargets",
            "plugin/share/list",
            "plugin/share/delete",
            "plugin/install",
            "plugin/uninstall",
            "marketplace/add",
            "marketplace/remove",
            "marketplace/upgrade",
            "hooks/list",
            "experimentalFeature/list",
            "experimentalFeature/enablement/set",
            "externalAgentConfig/detect",
            "externalAgentConfig/import",
            "configRequirements/read",
            "windowsSandbox/readiness"
        ] {
            XCTAssertEqual(CodexAppServer.requestSerializationScope(forMethod: method), .global("config"), method)
        }

        XCTAssertEqual(CodexAppServer.requestSerializationScope(forMethod: "memory/reset"), .global("memory"))
        XCTAssertEqual(CodexAppServer.requestSerializationScope(forMethod: "config/mcpServer/reload"), .global("mcp-registry"))
        XCTAssertEqual(CodexAppServer.requestSerializationScope(forMethod: "mcpServerStatus/list"), .global("mcp-registry"))
        XCTAssertEqual(CodexAppServer.requestSerializationScope(forMethod: "windowsSandbox/setupStart"), .global("windows-sandbox-setup"))

        for method in [
            "account/login/start",
            "account/login/cancel",
            "account/logout",
            "account/read",
            "account/sendAddCreditsNudgeEmail",
            "getAuthStatus"
        ] {
            XCTAssertEqual(CodexAppServer.requestSerializationScope(forMethod: method), .global("account-auth"), method)
        }

        for method in [
            "initialize",
            "thread/start",
            "thread/list",
            "thread/loaded/list",
            "fs/readFile",
            "thread/turns/list",
            "thread/turns/items/list",
            "account/rateLimits/read",
            "fuzzyFileSearch"
        ] {
            XCTAssertNil(CodexAppServer.requestSerializationScope(forMethod: method), method)
        }
    }

    func testRustRequestScopeTableLeavesConcurrentFamiliesUnscoped() {
        for method in [
            "app/list",
            "fs/readFile",
            "fs/writeFile",
            "fs/createDirectory",
            "fs/getMetadata",
            "fs/readDirectory",
            "fs/remove",
            "fs/copy",
            "feedback/upload",
            "model/list",
            "modelProvider/capabilities/read",
            "collaborationMode/list",
            "mock/experimentalMethod",
            "plugin/list",
            "plugin/read",
            "thread/realtime/listVoices",
            "account/rateLimits/read"
        ] {
            XCTAssertNil(CodexAppServer.requestSerializationScope(forMethod: method), method)
        }

        XCTAssertNil(
            CodexAppServer.requestSerializationScope(forMethod: "command/exec", params: [:]),
            "command/exec only serializes when processId is present"
        )
        XCTAssertNil(
            CodexAppServer.requestSerializationScope(forMethod: "mcpServer/resource/read", params: [:]),
            "mcpServer/resource/read only serializes when threadId is present"
        )
    }

    func testGlobalSharedReadScopeUsesSameQueueKeyWithSharedAccessLikeRust() {
        let shared = RequestSerializationQueueKey.from(scope: .globalSharedRead("config"))
        let exclusive = RequestSerializationQueueKey.from(scope: .global("config"))

        XCTAssertEqual(shared.0, .global("config"))
        XCTAssertEqual(shared.1, .sharedRead)
        XCTAssertEqual(exclusive.0, .global("config"))
        XCTAssertEqual(exclusive.1, .exclusive)
    }

    func testConnectionScopedRequestScopesAddConnectionIDWhenCreatingQueueKeyLikeRust() {
        let command = RequestSerializationQueueKey.from(
            scope: .commandExecProcess(processID: "proc-1"),
            connectionID: "connection-1"
        )
        XCTAssertEqual(command.0, .commandExecProcess(connectionID: "connection-1", processID: "proc-1"))
        XCTAssertEqual(command.1, .exclusive)

        let process = RequestSerializationQueueKey.from(
            scope: .process(processHandle: "handle-1"),
            connectionID: "connection-1"
        )
        XCTAssertEqual(process.0, .process(connectionID: "connection-1", processHandle: "handle-1"))
        XCTAssertEqual(process.1, .exclusive)

        let watch = RequestSerializationQueueKey.from(
            scope: .fsWatch(watchID: "watch-1"),
            connectionID: "connection-1"
        )
        XCTAssertEqual(watch.0, .fsWatch(connectionID: "connection-1", watchID: "watch-1"))
        XCTAssertEqual(watch.1, .exclusive)
    }

    func testSameKeySharedReadsRunConcurrentlyLikeRust() async throws {
        let queues = RequestSerializationQueues()
        let key = RequestSerializationQueueKey.global("test")
        let blockerStarted = AsyncSignal()
        let blockerRelease = AsyncSignal()
        let readStarts = AsyncValues<Int>()
        let readsRelease = AsyncSignal()

        await queues.enqueue(key: key, access: .exclusive) {
            await blockerStarted.signal()
            await blockerRelease.wait()
        }
        try await blockerStarted.waitWithTimeout()

        for value in [1, 2] {
            await queues.enqueue(key: key, access: .sharedRead) {
                await readStarts.append(value)
                await readsRelease.wait()
            }
        }

        await blockerRelease.signal()
        let started = try await readStarts.waitForCount(2)
        XCTAssertEqual(Set(started), [1, 2])
        await readsRelease.signal()
    }

    func testExclusiveWriteWaitsForRunningSharedReadsLikeRust() async throws {
        let queues = RequestSerializationQueues()
        let key = RequestSerializationQueueKey.global("test")
        let blockerStarted = AsyncSignal()
        let blockerRelease = AsyncSignal()
        let readStarts = AsyncValues<Int>()
        let readsRelease = AsyncSignal()
        let writeStarted = AsyncSignal()

        await queues.enqueue(key: key, access: .exclusive) {
            await blockerStarted.signal()
            await blockerRelease.wait()
        }
        try await blockerStarted.waitWithTimeout()

        for value in [1, 2] {
            await queues.enqueue(key: key, access: .sharedRead) {
                await readStarts.append(value)
                await readsRelease.wait()
            }
        }
        await queues.enqueue(key: key, access: .exclusive) {
            await writeStarted.signal()
        }

        await blockerRelease.signal()
        let started = try await readStarts.waitForCount(2)
        XCTAssertEqual(Set(started), [1, 2])
        let writeStartedEarly = await writeStarted.isSignaledWithinShortInterval()
        XCTAssertFalse(writeStartedEarly)

        await readsRelease.signal()
        try await writeStarted.waitWithTimeout()
    }

    func testLaterSharedReadDoesNotJumpAheadOfQueuedWriteLikeRust() async throws {
        let queues = RequestSerializationQueues()
        let key = RequestSerializationQueueKey.global("test")
        let blockerStarted = AsyncSignal()
        let blockerRelease = AsyncSignal()
        let firstReadStarted = AsyncSignal()
        let firstReadRelease = AsyncSignal()
        let writeStarted = AsyncSignal()
        let writeRelease = AsyncSignal()
        let laterReadStarted = AsyncSignal()

        await queues.enqueue(key: key, access: .exclusive) {
            await blockerStarted.signal()
            await blockerRelease.wait()
        }
        try await blockerStarted.waitWithTimeout()

        await queues.enqueue(key: key, access: .sharedRead) {
            await firstReadStarted.signal()
            await firstReadRelease.wait()
        }
        await queues.enqueue(key: key, access: .exclusive) {
            await writeStarted.signal()
            await writeRelease.wait()
        }
        await queues.enqueue(key: key, access: .sharedRead) {
            await laterReadStarted.signal()
        }

        await blockerRelease.signal()
        try await firstReadStarted.waitWithTimeout()
        let writeStartedBeforeFirstReadFinishes = await writeStarted.isSignaledWithinShortInterval()
        XCTAssertFalse(writeStartedBeforeFirstReadFinishes)
        let laterReadStartedBeforeWrite = await laterReadStarted.isSignaledWithinShortInterval()
        XCTAssertFalse(laterReadStartedBeforeWrite)

        await firstReadRelease.signal()
        try await writeStarted.waitWithTimeout()
        let laterReadStartedWhileWriteRuns = await laterReadStarted.isSignaledWithinShortInterval()
        XCTAssertFalse(laterReadStartedWhileWriteRuns)

        await writeRelease.signal()
        try await laterReadStarted.waitWithTimeout()
    }
}

private actor AsyncSignal {
    private var isSignaled = false
    private var waiters: [UUID: CheckedContinuation<Bool, Never>] = [:]

    func signal() {
        isSignaled = true
        let continuations = waiters
        waiters.removeAll()
        for continuation in continuations.values {
            continuation.resume(returning: true)
        }
    }

    func wait() async {
        _ = await waitResult()
    }

    func waitWithTimeout(
        nanoseconds: UInt64 = 1_000_000_000,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let completed = await waitResult(nanoseconds: nanoseconds)
        XCTAssertTrue(completed, file: file, line: line)
    }

    func isSignaledWithinShortInterval(nanoseconds: UInt64 = 50_000_000) async -> Bool {
        await waitResult(nanoseconds: nanoseconds)
    }

    private func waitResult(nanoseconds: UInt64? = nil) async -> Bool {
        if isSignaled {
            return true
        }
        let id = UUID()
        return await withCheckedContinuation { continuation in
            waiters[id] = continuation
            if let nanoseconds {
                Task.detached {
                    try? await Task.sleep(nanoseconds: nanoseconds)
                    await self.timeoutWaiter(id: id)
                }
            }
        }
    }

    private func timeoutWaiter(id: UUID) {
        guard let continuation = waiters.removeValue(forKey: id) else {
            return
        }
        continuation.resume(returning: false)
    }
}

private actor AsyncValues<Value: Equatable & Sendable> {
    private var values: [Value] = []
    private var waiters: [UUID: (count: Int, continuation: CheckedContinuation<[Value]?, Never>)] = [:]

    func append(_ value: Value) {
        values.append(value)
        resumeReadyWaiters()
    }

    func waitForCount(
        _ count: Int,
        nanoseconds: UInt64 = 1_000_000_000,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws -> [Value] {
        let result = await values(count: count, nanoseconds: nanoseconds) ?? []
        XCTAssertGreaterThanOrEqual(result.count, count, file: file, line: line)
        return result
    }

    private func values(count: Int, nanoseconds: UInt64) async -> [Value]? {
        if values.count >= count {
            return values
        }
        let id = UUID()
        return await withCheckedContinuation { continuation in
            waiters[id] = (count, continuation)
            Task.detached {
                try? await Task.sleep(nanoseconds: nanoseconds)
                await self.timeoutWaiter(id: id)
            }
            resumeReadyWaiters()
        }
    }

    private func resumeReadyWaiters() {
        for (id, waiter) in waiters {
            if values.count >= waiter.count {
                waiters.removeValue(forKey: id)
                waiter.continuation.resume(returning: values)
            }
        }
    }

    private func timeoutWaiter(id: UUID) {
        guard let waiter = waiters.removeValue(forKey: id) else {
            return
        }
        waiter.continuation.resume(returning: nil)
    }
}
