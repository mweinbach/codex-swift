import Foundation

public enum MemoriesConfigDefaults {
    public static let maxRolloutsPerStartup = 2
    public static let maxRolloutAgeDays: Int64 = 10
    public static let minRolloutIdleHours: Int64 = 6
    public static let minRateLimitRemainingPercent: Int64 = 25
    public static let maxRawMemoriesForConsolidation = 256
    public static let maxUnusedDays: Int64 = 30
}

public struct MemoriesConfig: Equatable, Sendable {
    public var disableOnExternalContext: Bool
    public var generateMemories: Bool
    public var useMemories: Bool
    public var maxRawMemoriesForConsolidation: Int
    public var maxUnusedDays: Int64
    public var maxRolloutAgeDays: Int64
    public var maxRolloutsPerStartup: Int
    public var minRolloutIdleHours: Int64
    public var minRateLimitRemainingPercent: Int64
    public var extractModel: String?
    public var consolidationModel: String?

    public init(
        disableOnExternalContext: Bool = false,
        generateMemories: Bool = true,
        useMemories: Bool = true,
        maxRawMemoriesForConsolidation: Int = MemoriesConfigDefaults.maxRawMemoriesForConsolidation,
        maxUnusedDays: Int64 = MemoriesConfigDefaults.maxUnusedDays,
        maxRolloutAgeDays: Int64 = MemoriesConfigDefaults.maxRolloutAgeDays,
        maxRolloutsPerStartup: Int = MemoriesConfigDefaults.maxRolloutsPerStartup,
        minRolloutIdleHours: Int64 = MemoriesConfigDefaults.minRolloutIdleHours,
        minRateLimitRemainingPercent: Int64 = MemoriesConfigDefaults.minRateLimitRemainingPercent,
        extractModel: String? = nil,
        consolidationModel: String? = nil
    ) {
        self.disableOnExternalContext = disableOnExternalContext
        self.generateMemories = generateMemories
        self.useMemories = useMemories
        self.maxRawMemoriesForConsolidation = maxRawMemoriesForConsolidation
        self.maxUnusedDays = maxUnusedDays
        self.maxRolloutAgeDays = maxRolloutAgeDays
        self.maxRolloutsPerStartup = maxRolloutsPerStartup
        self.minRolloutIdleHours = minRolloutIdleHours
        self.minRateLimitRemainingPercent = minRateLimitRemainingPercent
        self.extractModel = extractModel
        self.consolidationModel = consolidationModel
    }
}
