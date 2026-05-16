import XCTest
import CodexCore

final class ApprovalStoreTests: XCTestCase {
    func testApprovalStoreSerializesKeysLikeRust() {
        var store = ApprovalStore()
        let first = ShellCommandApprovalKey(
            command: ["/bin/bash", "-lc", "cargo test -p codex-core"],
            cwd: "/repo",
            sandboxPermissions: .useDefault,
            additionalPermissions: nil
        )
        let equivalent = ShellCommandApprovalKey(
            command: ["bash", "-lc", "cargo   test   -p codex-core"],
            cwd: "/repo",
            sandboxPermissions: .useDefault,
            additionalPermissions: nil
        )

        store.put(first, decision: .approvedForSession)

        XCTAssertEqual(store.get(equivalent), .approvedForSession)
    }

    func testApprovalCacheSkipsFetchWhenAllKeysApprovedForSessionLikeRust() async {
        var store = ApprovalStore()
        let key = ShellCommandApprovalKey(
            command: ["git", "status"],
            cwd: "/repo",
            sandboxPermissions: .useDefault,
            additionalPermissions: nil
        )
        store.put(key, decision: .approvedForSession)
        var cache = ApprovalCache(store: store)
        var fetched = false

        let decision = await cache.withCachedApproval(keys: [key]) {
            fetched = true
            return .approved
        }

        XCTAssertEqual(decision, .approvedForSession)
        XCTAssertFalse(fetched)
    }

    func testApprovalCacheStoresApprovedForSessionAcrossFutureSubsetsLikeRust() async {
        let first = ShellCommandApprovalKey(
            command: ["git", "status"],
            cwd: "/repo",
            sandboxPermissions: .useDefault,
            additionalPermissions: nil
        )
        let second = ShellCommandApprovalKey(
            command: ["git", "diff"],
            cwd: "/repo",
            sandboxPermissions: .useDefault,
            additionalPermissions: nil
        )
        var cache = ApprovalCache()
        var fetchCount = 0

        let firstDecision = await cache.withCachedApproval(keys: [first, second]) {
            fetchCount += 1
            return .approvedForSession
        }
        let secondDecision = await cache.withCachedApproval(keys: [second]) {
            fetchCount += 1
            return .approved
        }

        XCTAssertEqual(firstDecision, .approvedForSession)
        XCTAssertEqual(secondDecision, .approvedForSession)
        XCTAssertEqual(fetchCount, 1)
    }

    func testApprovalCacheDoesNotStoreSingleApprovalLikeRust() async {
        let key = ShellCommandApprovalKey(
            command: ["git", "status"],
            cwd: "/repo",
            sandboxPermissions: .useDefault,
            additionalPermissions: nil
        )
        var cache = ApprovalCache()
        var fetchCount = 0

        let firstDecision = await cache.withCachedApproval(keys: [key]) {
            fetchCount += 1
            return .approved
        }
        let secondDecision = await cache.withCachedApproval(keys: [key]) {
            fetchCount += 1
            return .approved
        }

        XCTAssertEqual(firstDecision, .approved)
        XCTAssertEqual(secondDecision, .approved)
        XCTAssertEqual(fetchCount, 2)
    }

    func testApprovalCacheEmptyKeysAlwaysFetchLikeRust() async {
        var cache = ApprovalCache()
        var fetchCount = 0

        let decision = await cache.withCachedApproval(keys: [ShellCommandApprovalKey]()) {
            fetchCount += 1
            return .approvedForSession
        }

        XCTAssertEqual(decision, .approvedForSession)
        XCTAssertEqual(fetchCount, 1)
    }

    func testUnifiedExecApprovalKeyCanonicalizesCommandAndPreservesTtyScopeLikeRust() {
        let ptyKey = UnifiedExecApprovalKey(
            command: ["/bin/zsh", "-lc", "python3 <<'PY'\nprint('hello')\nPY"],
            cwd: "/repo",
            tty: true,
            sandboxPermissions: .useDefault,
            additionalPermissions: nil
        )
        let nonPtyKey = UnifiedExecApprovalKey(
            command: ["zsh", "-lc", "python3 <<'PY'\nprint('hello')\nPY"],
            cwd: "/repo",
            tty: false,
            sandboxPermissions: .useDefault,
            additionalPermissions: nil
        )

        XCTAssertEqual(ptyKey.command, nonPtyKey.command)
        XCTAssertNotEqual(ptyKey, nonPtyKey)
    }
}
