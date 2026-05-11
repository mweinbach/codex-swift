import Foundation

private let modelKey = "model"
private let reasoningEffortKey = "reasoning_effort"
private let turnStartedAtUnixMsKey = "turn_started_at_unix_ms"

public struct McpTurnMetadataContext: Equatable, Sendable {
    public let model: String
    public let reasoningEffort: ReasoningEffort?

    public init(model: String, reasoningEffort: ReasoningEffort? = nil) {
        self.model = model
        self.reasoningEffort = reasoningEffort
    }
}

/// Mutable per-turn metadata shared across request builders; all mutable fields are guarded by
/// `lock`, so callers can read or update the header state across concurrency domains.
public final class TurnMetadataState: @unchecked Sendable {
    private let baseHeader: String
    private let lock = NSLock()
    private var turnStartedAtUnixMs: Int64?
    private var responsesAPIClientMetadata: [String: String]?

    public init(
        sessionID: String,
        threadID: String,
        threadSource: ThreadSource?,
        turnID: String,
        sandbox: String? = nil
    ) {
        var metadata: [String: Any] = [
            "session_id": sessionID,
            "thread_id": threadID,
            "turn_id": turnID
        ]
        if let threadSource {
            metadata["thread_source"] = threadSource.rawValue
        }
        if let sandbox {
            metadata["sandbox"] = sandbox
        }
        baseHeader = Self.asciiJSONString(metadata) ?? "{}"
    }

    public func currentHeaderValue() -> String? {
        let startedAt: Int64?
        let clientMetadata: [String: String]?
        lock.lock()
        startedAt = turnStartedAtUnixMs
        clientMetadata = responsesAPIClientMetadata
        lock.unlock()
        return Self.mergingTurnMetadata(
            header: baseHeader,
            turnStartedAtUnixMs: startedAt,
            responsesAPIClientMetadata: clientMetadata
        ) ?? baseHeader
    }

    public func currentMetaValueForMcpRequest(context: McpTurnMetadataContext) -> JSONValue? {
        guard let header = currentHeaderValue(),
              var metadata = Self.jsonObject(from: header)
        else {
            return nil
        }
        metadata[modelKey] = context.model
        if let reasoningEffort = context.reasoningEffort {
            metadata[reasoningEffortKey] = reasoningEffort.rawValue
        } else {
            metadata.removeValue(forKey: reasoningEffortKey)
        }
        guard let data = try? JSONSerialization.data(withJSONObject: metadata, options: [.sortedKeys]) else {
            return nil
        }
        return try? JSONDecoder().decode(JSONValue.self, from: data)
    }

    public func setResponsesAPIClientMetadata(_ metadata: [String: String]) {
        lock.lock()
        responsesAPIClientMetadata = metadata
        lock.unlock()
    }

    public func setTurnStartedAtUnixMs(_ value: Int64) {
        lock.lock()
        turnStartedAtUnixMs = value
        lock.unlock()
    }

    private static func mergingTurnMetadata(
        header: String,
        turnStartedAtUnixMs: Int64?,
        responsesAPIClientMetadata: [String: String]?
    ) -> String? {
        guard turnStartedAtUnixMs != nil || responsesAPIClientMetadata != nil,
              var metadata = jsonObject(from: header)
        else {
            return nil
        }
        if let turnStartedAtUnixMs {
            metadata[turnStartedAtUnixMsKey] = turnStartedAtUnixMs
        }
        if let responsesAPIClientMetadata {
            for (key, value) in responsesAPIClientMetadata where key != turnStartedAtUnixMsKey {
                if metadata[key] == nil {
                    metadata[key] = value
                }
            }
        }
        return asciiJSONString(metadata)
    }

    private static func jsonObject(from string: String) -> [String: Any]? {
        guard let data = string.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }
        return object
    }

    private static func asciiJSONString(_ object: [String: Any]) -> String? {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8)
        else {
            return nil
        }
        return json.unicodeScalars.map(asciiEscaped).joined()
    }

    private static func asciiEscaped(_ scalar: UnicodeScalar) -> String {
        switch scalar.value {
        case 0x00...0x7F:
            return String(scalar)
        case 0x80...0xFFFF:
            return String(format: "\\u%04X", scalar.value)
        default:
            let value = scalar.value - 0x10000
            let high = 0xD800 + (value >> 10)
            let low = 0xDC00 + (value & 0x3FF)
            return String(format: "\\u%04X\\u%04X", high, low)
        }
    }
}
