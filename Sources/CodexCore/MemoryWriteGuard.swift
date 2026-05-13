import Foundation

public let memoryRateLimitID = "codex"

public enum MemoryWriteMetrics {
    public static let startup = "codex.memory.startup"

    public static let phaseOneJobs = "codex.memory.phase1"
    public static let phaseOneE2EMS = "codex.memory.phase1.e2e_ms"
    public static let phaseOneOutput = "codex.memory.phase1.output"
    public static let phaseOneTokenUsage = "codex.memory.phase1.token_usage"

    public static let phaseTwoJobs = "codex.memory.phase2"
    public static let phaseTwoE2EMS = "codex.memory.phase2.e2e_ms"
    public static let phaseTwoInput = "codex.memory.phase2.input"
    public static let phaseTwoTokenUsage = "codex.memory.phase2.token_usage"
}

public func memoryRateLimitsAllowStartup(
    snapshots: [RateLimitSnapshot],
    minRemainingPercent: Int64
) -> Bool {
    guard let snapshot = memoryStartupRateLimitSnapshot(from: snapshots) else {
        return true
    }
    return memoryRateLimitSnapshotAllowsStartup(
        snapshot,
        minRemainingPercent: minRemainingPercent
    )
}

public func memoryStartupRateLimitSnapshot(from snapshots: [RateLimitSnapshot]) -> RateLimitSnapshot? {
    snapshots.first { $0.limitID == memoryRateLimitID } ?? snapshots.first
}

public func memoryRateLimitSnapshotAllowsStartup(
    _ snapshot: RateLimitSnapshot,
    minRemainingPercent: Int64
) -> Bool {
    if snapshot.rateLimitReachedType != nil {
        return false
    }

    let clampedMinimum = min(max(minRemainingPercent, 0), 100)
    let maxUsedPercent = 100.0 - Double(clampedMinimum)
    return memoryRateLimitWindowAllowsStartup(snapshot.primary, maxUsedPercent: maxUsedPercent)
        && memoryRateLimitWindowAllowsStartup(snapshot.secondary, maxUsedPercent: maxUsedPercent)
}

func memoryRateLimitWindowAllowsStartup(
    _ window: RateLimitWindow?,
    maxUsedPercent: Double
) -> Bool {
    guard let window else {
        return true
    }
    return window.usedPercent <= maxUsedPercent
}
