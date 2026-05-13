import Foundation

public struct MemoryRateLimitSnapshotsClient<Transport: APITransport>: Sendable {
    public let transport: Transport

    public init(transport: Transport) {
        self.transport = transport
    }

    public func fetchSnapshots(
        baseURL: String,
        accessToken: String,
        accountID: String
    ) async throws -> [RateLimitSnapshot] {
        let endpoint = Self.usageEndpoint(for: baseURL)
        let request = APIRequest(method: .get, url: endpoint)
            .addingAuthHeaders(from: StaticAPIAuthProvider(
                bearerToken: accessToken,
                accountID: accountID
            ))

        switch await transport.execute(request) {
        case let .success(response):
            do {
                let payload = try JSONDecoder().decode(MemoryRateLimitsUsagePayload.self, from: response.body)
                return payload.snapshots()
            } catch {
                throw MemoryRateLimitSnapshotsClientError.decode(String(describing: error))
            }
        case let .failure(error):
            throw MemoryRateLimitSnapshotsClientError.transport(error.description)
        }
    }

    public var fetcher: MemoryRateLimitSnapshotsFetcher {
        { baseURL, accessToken, accountID in
            try await fetchSnapshots(
                baseURL: baseURL,
                accessToken: accessToken,
                accountID: accountID
            )
        }
    }

    static func usageEndpoint(for baseURL: String) -> String {
        let normalized = normalizedBaseURL(baseURL)
        switch pathStyle(for: normalized) {
        case .chatGPTAPI:
            return "\(normalized)/wham/usage"
        case .codexAPI:
            return "\(normalized)/api/codex/usage"
        }
    }

    private static func normalizedBaseURL(_ baseURL: String) -> String {
        var normalized = baseURL
        while normalized.hasSuffix("/") {
            normalized.removeLast()
        }

        let lowercased = normalized.lowercased()
        if (lowercased == "https://chatgpt.com" || lowercased == "https://chat.openai.com")
            && !lowercased.contains("/backend-api")
        {
            normalized += "/backend-api"
        }
        return normalized
    }

    private static func pathStyle(for normalizedBaseURL: String) -> PathStyle {
        normalizedBaseURL.lowercased().contains("/backend-api") ? .chatGPTAPI : .codexAPI
    }

    private enum PathStyle {
        case chatGPTAPI
        case codexAPI
    }
}

public extension MemoryRateLimitSnapshotsClient where Transport == URLSessionAPITransport {
    init() {
        self.init(transport: URLSessionAPITransport())
    }
}

private enum MemoryRateLimitSnapshotsClientError: Error, CustomStringConvertible {
    case transport(String)
    case decode(String)

    var description: String {
        switch self {
        case let .transport(message):
            return message
        case let .decode(message):
            return "failed to decode rate limits usage response: \(message)"
        }
    }
}

private struct MemoryRateLimitsUsagePayload: Decodable {
    let planType: PlanType?
    let rateLimit: MemoryRateLimitsDetails?
    let credits: MemoryRateLimitsCreditsPayload?
    let rateLimitReachedType: MemoryRateLimitReachedTypePayload?
    let additionalRateLimits: [MemoryRateLimitsAdditionalPayload]

    private enum CodingKeys: String, CodingKey {
        case planType = "plan_type"
        case rateLimit = "rate_limit"
        case credits
        case rateLimitReachedType = "rate_limit_reached_type"
        case additionalRateLimits = "additional_rate_limits"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.planType = try container.decodeIfPresent(PlanType.self, forKey: .planType)
        self.rateLimit = try container.decodeIfPresent(MemoryRateLimitsDetails.self, forKey: .rateLimit)
        self.credits = try container.decodeIfPresent(MemoryRateLimitsCreditsPayload.self, forKey: .credits)
        self.rateLimitReachedType = try container.decodeIfPresent(
            MemoryRateLimitReachedTypePayload.self,
            forKey: .rateLimitReachedType
        )
        self.additionalRateLimits = try container.decodeIfPresent(
            [MemoryRateLimitsAdditionalPayload].self,
            forKey: .additionalRateLimits
        ) ?? []
    }

    func snapshots() -> [RateLimitSnapshot] {
        var snapshots = [
            RateLimitSnapshot(
                limitID: memoryRateLimitID,
                limitName: nil,
                primary: rateLimit?.primaryWindow?.snapshot,
                secondary: rateLimit?.secondaryWindow?.snapshot,
                credits: credits?.snapshot,
                planType: planType,
                rateLimitReachedType: rateLimitReachedType?.snapshot
            )
        ]

        snapshots.append(contentsOf: additionalRateLimits.map { additional in
            RateLimitSnapshot(
                limitID: additional.meteredFeature,
                limitName: additional.limitName,
                primary: additional.rateLimit?.primaryWindow?.snapshot,
                secondary: additional.rateLimit?.secondaryWindow?.snapshot,
                credits: nil,
                planType: planType,
                rateLimitReachedType: nil
            )
        })
        return snapshots
    }
}

private struct MemoryRateLimitsAdditionalPayload: Decodable {
    let limitName: String?
    let meteredFeature: String?
    let rateLimit: MemoryRateLimitsDetails?

    private enum CodingKeys: String, CodingKey {
        case limitName = "limit_name"
        case meteredFeature = "metered_feature"
        case rateLimit = "rate_limit"
    }
}

private struct MemoryRateLimitsDetails: Decodable {
    let primaryWindow: MemoryRateLimitsWindowPayload?
    let secondaryWindow: MemoryRateLimitsWindowPayload?

    private enum CodingKeys: String, CodingKey {
        case primaryWindow = "primary_window"
        case secondaryWindow = "secondary_window"
    }
}

private struct MemoryRateLimitsWindowPayload: Decodable {
    let usedPercent: Double
    let limitWindowSeconds: Int64?
    let resetAt: Int64?

    private enum CodingKeys: String, CodingKey {
        case usedPercent = "used_percent"
        case limitWindowSeconds = "limit_window_seconds"
        case resetAt = "reset_at"
    }

    var snapshot: RateLimitWindow {
        RateLimitWindow(
            usedPercent: usedPercent,
            windowMinutes: limitWindowSeconds.flatMap(Self.windowMinutes),
            resetsAt: resetAt
        )
    }

    private static func windowMinutes(from seconds: Int64) -> Int64? {
        guard seconds > 0 else {
            return nil
        }
        return (seconds + 59) / 60
    }
}

private struct MemoryRateLimitsCreditsPayload: Decodable {
    let hasCredits: Bool
    let unlimited: Bool
    let balance: String?

    private enum CodingKeys: String, CodingKey {
        case hasCredits = "has_credits"
        case unlimited
        case balance
    }

    var snapshot: CreditsSnapshot {
        CreditsSnapshot(
            hasCredits: hasCredits,
            unlimited: unlimited,
            balance: balance
        )
    }
}

private struct MemoryRateLimitReachedTypePayload: Decodable {
    let type: String?

    var snapshot: RateLimitReachedType? {
        type.flatMap(RateLimitReachedType.init(rawValue:))
    }
}
