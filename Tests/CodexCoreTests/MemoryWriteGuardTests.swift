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
}
