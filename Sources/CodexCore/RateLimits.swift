import Foundation

public struct TokenCountEvent: Equatable, Codable, Sendable {
    public let info: TokenUsageInfo?
    public let rateLimits: RateLimitSnapshot?

    private enum CodingKeys: String, CodingKey {
        case info
        case rateLimits = "rate_limits"
    }

    public init(info: TokenUsageInfo?, rateLimits: RateLimitSnapshot?) {
        self.info = info
        self.rateLimits = rateLimits
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.info = try container.decodeIfPresent(TokenUsageInfo.self, forKey: .info)
        self.rateLimits = try container.decodeIfPresent(RateLimitSnapshot.self, forKey: .rateLimits)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresentOrNull(info, forKey: .info)
        try container.encodeIfPresentOrNull(rateLimits, forKey: .rateLimits)
    }
}

public struct RateLimitSnapshot: Equatable, Codable, Sendable {
    public var primary: RateLimitWindow?
    public var secondary: RateLimitWindow?
    public var credits: CreditsSnapshot?
    public var planType: PlanType?

    private enum CodingKeys: String, CodingKey {
        case primary
        case secondary
        case credits
        case planType = "plan_type"
    }

    public init(
        primary: RateLimitWindow?,
        secondary: RateLimitWindow?,
        credits: CreditsSnapshot?,
        planType: PlanType?
    ) {
        self.primary = primary
        self.secondary = secondary
        self.credits = credits
        self.planType = planType
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.primary = try container.decodeIfPresent(RateLimitWindow.self, forKey: .primary)
        self.secondary = try container.decodeIfPresent(RateLimitWindow.self, forKey: .secondary)
        self.credits = try container.decodeIfPresent(CreditsSnapshot.self, forKey: .credits)
        self.planType = try container.decodeIfPresent(PlanType.self, forKey: .planType)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresentOrNull(primary, forKey: .primary)
        try container.encodeIfPresentOrNull(secondary, forKey: .secondary)
        try container.encodeIfPresentOrNull(credits, forKey: .credits)
        try container.encodeIfPresentOrNull(planType, forKey: .planType)
    }

    public func mergingMissingFields(from previous: RateLimitSnapshot?) -> RateLimitSnapshot {
        var snapshot = self
        if snapshot.credits == nil {
            snapshot.credits = previous?.credits
        }
        if snapshot.planType == nil {
            snapshot.planType = previous?.planType
        }
        return snapshot
    }

    public static func mergeRateLimitFields(
        previous: RateLimitSnapshot?,
        snapshot: RateLimitSnapshot
    ) -> RateLimitSnapshot {
        snapshot.mergingMissingFields(from: previous)
    }

    public static func parseRateLimit(headers: [String: String]) -> RateLimitSnapshot? {
        RateLimitSnapshot(
            primary: parseRateLimitWindow(
                headers: headers,
                usedPercentHeader: "x-codex-primary-used-percent",
                windowMinutesHeader: "x-codex-primary-window-minutes",
                resetsAtHeader: "x-codex-primary-reset-at"
            ),
            secondary: parseRateLimitWindow(
                headers: headers,
                usedPercentHeader: "x-codex-secondary-used-percent",
                windowMinutesHeader: "x-codex-secondary-window-minutes",
                resetsAtHeader: "x-codex-secondary-reset-at"
            ),
            credits: parseCreditsSnapshot(headers: headers),
            planType: nil
        )
    }

    private static func parseRateLimitWindow(
        headers: [String: String],
        usedPercentHeader: String,
        windowMinutesHeader: String,
        resetsAtHeader: String
    ) -> RateLimitWindow? {
        guard let usedPercent = parseHeaderDouble(headers, usedPercentHeader) else {
            return nil
        }

        let windowMinutes = parseHeaderInt64(headers, windowMinutesHeader)
        let resetsAt = parseHeaderInt64(headers, resetsAtHeader)
        let hasData = usedPercent != 0.0
            || windowMinutes.map { $0 != 0 } == true
            || resetsAt != nil

        guard hasData else {
            return nil
        }

        return RateLimitWindow(
            usedPercent: usedPercent,
            windowMinutes: windowMinutes,
            resetsAt: resetsAt
        )
    }

    private static func parseCreditsSnapshot(headers: [String: String]) -> CreditsSnapshot? {
        guard let hasCredits = parseHeaderBool(headers, "x-codex-credits-has-credits"),
              let unlimited = parseHeaderBool(headers, "x-codex-credits-unlimited")
        else {
            return nil
        }

        let balance = parseHeaderString(headers, "x-codex-credits-balance")?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return CreditsSnapshot(
            hasCredits: hasCredits,
            unlimited: unlimited,
            balance: balance?.isEmpty == false ? balance : nil
        )
    }

    private static func parseHeaderDouble(_ headers: [String: String], _ name: String) -> Double? {
        guard let value = parseHeaderString(headers, name),
              let parsed = Double(value),
              parsed.isFinite
        else {
            return nil
        }
        return parsed
    }

    private static func parseHeaderInt64(_ headers: [String: String], _ name: String) -> Int64? {
        guard let value = parseHeaderString(headers, name) else {
            return nil
        }
        return Int64(value)
    }

    private static func parseHeaderBool(_ headers: [String: String], _ name: String) -> Bool? {
        guard let value = parseHeaderString(headers, name) else {
            return nil
        }
        if value.caseInsensitiveCompare("true") == .orderedSame || value == "1" {
            return true
        }
        if value.caseInsensitiveCompare("false") == .orderedSame || value == "0" {
            return false
        }
        return nil
    }

    private static func parseHeaderString(_ headers: [String: String], _ name: String) -> String? {
        for (headerName, value) in headers where headerName.caseInsensitiveCompare(name) == .orderedSame {
            return value
        }
        return nil
    }
}

public struct RateLimitWindow: Equatable, Codable, Sendable {
    public let usedPercent: Double
    public let windowMinutes: Int64?
    public let resetsAt: Int64?

    private enum CodingKeys: String, CodingKey {
        case usedPercent = "used_percent"
        case windowMinutes = "window_minutes"
        case resetsAt = "resets_at"
    }

    public init(usedPercent: Double, windowMinutes: Int64?, resetsAt: Int64?) {
        self.usedPercent = usedPercent
        self.windowMinutes = windowMinutes
        self.resetsAt = resetsAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.usedPercent = try container.decode(Double.self, forKey: .usedPercent)
        self.windowMinutes = try container.decodeIfPresent(Int64.self, forKey: .windowMinutes)
        self.resetsAt = try container.decodeIfPresent(Int64.self, forKey: .resetsAt)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(usedPercent, forKey: .usedPercent)
        try container.encodeIfPresentOrNull(windowMinutes, forKey: .windowMinutes)
        try container.encodeIfPresentOrNull(resetsAt, forKey: .resetsAt)
    }
}

public struct CreditsSnapshot: Equatable, Codable, Sendable {
    public let hasCredits: Bool
    public let unlimited: Bool
    public let balance: String?

    private enum CodingKeys: String, CodingKey {
        case hasCredits = "has_credits"
        case unlimited
        case balance
    }

    public init(hasCredits: Bool, unlimited: Bool, balance: String?) {
        self.hasCredits = hasCredits
        self.unlimited = unlimited
        self.balance = balance
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.hasCredits = try container.decode(Bool.self, forKey: .hasCredits)
        self.unlimited = try container.decode(Bool.self, forKey: .unlimited)
        self.balance = try container.decodeIfPresent(String.self, forKey: .balance)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(hasCredits, forKey: .hasCredits)
        try container.encode(unlimited, forKey: .unlimited)
        try container.encodeIfPresentOrNull(balance, forKey: .balance)
    }
}

private extension KeyedEncodingContainer {
    mutating func encodeIfPresentOrNull<T: Encodable>(_ value: T?, forKey key: Key) throws {
        if let value {
            try encode(value, forKey: key)
        } else {
            try encodeNil(forKey: key)
        }
    }
}
