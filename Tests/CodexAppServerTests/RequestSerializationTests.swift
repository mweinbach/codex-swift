@testable import CodexAppServer
import XCTest

final class RequestSerializationTests: XCTestCase {
    func testConfigFamilyReadMethodsUseSharedReadScopeLikeRust() {
        XCTAssertEqual(CodexAppServer.requestSerializationScope(forMethod: "config/read"), .globalSharedRead("config"))
        XCTAssertEqual(CodexAppServer.requestSerializationScope(forMethod: "plugin/list"), .globalSharedRead("config"))
        XCTAssertEqual(CodexAppServer.requestSerializationScope(forMethod: "skills/list"), .globalSharedRead("config"))

        XCTAssertEqual(CodexAppServer.requestSerializationScope(forMethod: "config/value/write"), .global("config"))
        XCTAssertEqual(CodexAppServer.requestSerializationScope(forMethod: "config/batchWrite"), .global("config"))
        XCTAssertEqual(CodexAppServer.requestSerializationScope(forMethod: "skills/config/write"), .global("config"))
    }

    func testGlobalSharedReadScopeUsesSameQueueKeyWithSharedAccessLikeRust() {
        let shared = RequestSerializationQueueKey.from(scope: .globalSharedRead("config"))
        let exclusive = RequestSerializationQueueKey.from(scope: .global("config"))

        XCTAssertEqual(shared.0, .global("config"))
        XCTAssertEqual(shared.1, .sharedRead)
        XCTAssertEqual(exclusive.0, .global("config"))
        XCTAssertEqual(exclusive.1, .exclusive)
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
        XCTAssertEqual(started, [1, 2])
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
        XCTAssertEqual(started, [1, 2])
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
