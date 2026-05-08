import Foundation

public enum OllamaHelpers {
    public static func isOpenAICompatibleBaseURL(_ baseURL: String) -> Bool {
        trimTrailingSlashes(baseURL).hasSuffix("/v1")
    }

    public static func baseURLToHostRoot(_ baseURL: String) -> String {
        let trimmed = trimTrailingSlashes(baseURL)
        guard trimmed.hasSuffix("/v1") else {
            return trimmed
        }

        let withoutV1 = String(trimmed.dropLast(3))
        return trimTrailingSlashes(withoutV1)
    }

    public static func pullEvents(from update: OllamaPullUpdate) -> [OllamaPullEvent] {
        var events: [OllamaPullEvent] = []
        if let status = update.status {
            events.append(.status(status))
            if status == "success" {
                events.append(.success)
            }
        }

        if update.total != nil || update.completed != nil {
            events.append(.chunkProgress(
                digest: update.digest ?? "",
                total: update.total,
                completed: update.completed
            ))
        }
        return events
    }

    public static func pullEvents(fromJSONData data: Data) throws -> [OllamaPullEvent] {
        try pullEvents(from: JSONDecoder().decode(OllamaPullUpdate.self, from: data))
    }

    private static func trimTrailingSlashes(_ value: String) -> String {
        var result = value
        while result.hasSuffix("/") {
            result.removeLast()
        }
        return result
    }
}

public struct OllamaPullUpdate: Equatable, Decodable, Sendable {
    public let status: String?
    public let digest: String?
    public let total: UInt64?
    public let completed: UInt64?

    public init(status: String? = nil, digest: String? = nil, total: UInt64? = nil, completed: UInt64? = nil) {
        self.status = status
        self.digest = digest
        self.total = total
        self.completed = completed
    }
}

public enum OllamaPullEvent: Equatable, Sendable {
    case status(String)
    case chunkProgress(digest: String, total: UInt64?, completed: UInt64?)
    case success
    case error(String)
}
