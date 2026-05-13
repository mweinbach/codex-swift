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

public typealias MemoryRateLimitSnapshotsFetcher = @Sendable (
    _ baseURL: String,
    _ accessToken: String,
    _ accountID: String
) async throws -> [RateLimitSnapshot]

public func memoryRateLimitsAllowStartup(
    auth: AuthDotJSON?,
    chatGPTBaseURL: String,
    minRemainingPercent: Int64,
    fetchSnapshots: MemoryRateLimitSnapshotsFetcher
) async -> Bool {
    guard memoryAuthUsesCodexBackend(auth),
          let tokens = auth?.tokens,
          let accountID = tokens.accountID
    else {
        return true
    }

    do {
        return memoryRateLimitsAllowStartup(
            snapshots: try await fetchSnapshots(chatGPTBaseURL, tokens.accessToken, accountID),
            minRemainingPercent: minRemainingPercent
        )
    } catch {
        return true
    }
}

public func memoryAuthUsesCodexBackend(_ auth: AuthDotJSON?) -> Bool {
    guard let auth,
          auth.openAIAPIKey == nil,
          auth.tokens != nil,
          auth.authMode != .apiKey
    else {
        return false
    }
    return true
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
