import Foundation

public enum ResponseEvent: Equatable, Sendable {
    case created
    case outputItemDone(ResponseItem)
    case outputItemAdded(ResponseItem)
    case completed(responseID: String, tokenUsage: TokenUsage?)
    case outputTextDelta(String)
    case reasoningSummaryDelta(delta: String, summaryIndex: Int64)
    case reasoningContentDelta(delta: String, contentIndex: Int64)
    case reasoningSummaryPartAdded(summaryIndex: Int64)
    case rateLimits(RateLimitSnapshot)
}

public struct ResponsesSSEParser: Sendable {
    private var responseCompleted: ResponseCompleted?
    private var responseError: APIError?

    public init() {}

    public mutating func receive(data: String) -> [ResponseEvent] {
        guard let event = try? JSONDecoder().decode(SSEEvent.self, from: Data(data.utf8)) else {
            return []
        }

        switch event.kind {
        case "response.output_item.done":
            guard let item = event.item.flatMap({ decodeJSONValue($0, as: ResponseItem.self) }) else {
                return []
            }
            return [.outputItemDone(item)]

        case "response.output_text.delta":
            guard let delta = event.delta else {
                return []
            }
            return [.outputTextDelta(delta)]

        case "response.reasoning_summary_text.delta":
            guard let delta = event.delta, let summaryIndex = event.summaryIndex else {
                return []
            }
            return [.reasoningSummaryDelta(delta: delta, summaryIndex: summaryIndex)]

        case "response.reasoning_text.delta":
            guard let delta = event.delta, let contentIndex = event.contentIndex else {
                return []
            }
            return [.reasoningContentDelta(delta: delta, contentIndex: contentIndex)]

        case "response.created":
            return event.response == nil ? [] : [.created]

        case "response.failed":
            receiveFailedResponse(event.response)
            return []

        case "response.completed":
            receiveCompletedResponse(event.response)
            return []

        case "response.output_item.added":
            guard let item = event.item.flatMap({ decodeJSONValue($0, as: ResponseItem.self) }) else {
                return []
            }
            return [.outputItemAdded(item)]

        case "response.reasoning_summary_part.added":
            guard let summaryIndex = event.summaryIndex else {
                return []
            }
            return [.reasoningSummaryPartAdded(summaryIndex: summaryIndex)]

        default:
            return []
        }
    }

    public mutating func finish() -> Result<ResponseEvent, APIError> {
        if let responseCompleted {
            return .success(.completed(
                responseID: responseCompleted.id,
                tokenUsage: responseCompleted.usage?.tokenUsage
            ))
        }

        return .failure(responseError ?? .stream("stream closed before response.completed"))
    }

    public static func collectEvents(fromSSEText text: String) -> [Result<ResponseEvent, APIError>] {
        var parser = ResponsesSSEParser()
        var results: [Result<ResponseEvent, APIError>] = []

        for frame in dataFrames(fromSSEText: text) {
            results.append(contentsOf: parser.receive(data: frame).map(Result.success))
        }
        results.append(parser.finish())
        return results
    }

    public static func dataFrames(fromSSEText text: String) -> [String] {
        SSEDataFrameDecoder.dataFrames(from: text)
    }

    private mutating func receiveFailedResponse(_ response: JSONValue?) {
        guard let response else {
            return
        }

        responseError = .stream("response.failed event received")
        guard case let .object(responseObject) = response,
              let errorValue = responseObject["error"],
              let error = decodeJSONValue(errorValue, as: ResponseFailedError.self)
        else {
            return
        }

        switch error.code {
        case "context_length_exceeded":
            responseError = .contextWindowExceeded
        case "insufficient_quota":
            responseError = .quotaExceeded
        case "usage_not_included":
            responseError = .usageNotIncluded
        default:
            responseError = .retryable(
                message: error.message ?? "",
                delay: Self.retryDelay(for: error)
            )
        }
    }

    private mutating func receiveCompletedResponse(_ response: JSONValue?) {
        guard let response else {
            return
        }

        if let completed = decodeJSONValue(response, as: ResponseCompleted.self) {
            responseCompleted = completed
        } else {
            responseError = .stream("failed to parse ResponseCompleted")
        }
    }

    private static func retryDelay(for error: ResponseFailedError) -> Duration? {
        guard error.code == "rate_limit_exceeded", let message = error.message else {
            return nil
        }

        let pattern = #"try again in\s*(\d+(?:\.\d+)?)\s*(s|ms|seconds?)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(message.startIndex..<message.endIndex, in: message)
        guard let match = regex.firstMatch(in: message, range: range),
              match.numberOfRanges >= 3,
              let valueRange = Range(match.range(at: 1), in: message),
              let unitRange = Range(match.range(at: 2), in: message),
              let value = Double(message[valueRange])
        else {
            return nil
        }

        let unit = message[unitRange].lowercased()
        if unit == "ms" {
            return .milliseconds(Int64(value.rounded(.towardZero)))
        }
        if unit == "s" || unit.hasPrefix("second") {
            return .milliseconds(Int64((value * 1_000).rounded(.towardZero)))
        }
        return nil
    }
}

private struct SSEEvent: Decodable {
    let kind: String
    let response: JSONValue?
    let item: JSONValue?
    let delta: String?
    let summaryIndex: Int64?
    let contentIndex: Int64?

    private enum CodingKeys: String, CodingKey {
        case kind = "type"
        case response
        case item
        case delta
        case summaryIndex = "summary_index"
        case contentIndex = "content_index"
    }
}

private struct ResponseFailedError: Decodable {
    let type: String?
    let code: String?
    let message: String?
    let planType: String?
    let resetsAt: Int64?

    private enum CodingKeys: String, CodingKey {
        case type
        case code
        case message
        case planType = "plan_type"
        case resetsAt = "resets_at"
    }
}

private struct ResponseCompleted: Decodable, Sendable {
    let id: String
    let usage: ResponseCompletedUsage?
}

private struct ResponseCompletedUsage: Decodable, Sendable {
    let inputTokens: Int64
    let inputTokensDetails: ResponseCompletedInputTokensDetails?
    let outputTokens: Int64
    let outputTokensDetails: ResponseCompletedOutputTokensDetails?
    let totalTokens: Int64

    var tokenUsage: TokenUsage {
        TokenUsage(
            inputTokens: inputTokens,
            cachedInputTokens: inputTokensDetails?.cachedTokens ?? 0,
            outputTokens: outputTokens,
            reasoningOutputTokens: outputTokensDetails?.reasoningTokens ?? 0,
            totalTokens: totalTokens
        )
    }

    private enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case inputTokensDetails = "input_tokens_details"
        case outputTokens = "output_tokens"
        case outputTokensDetails = "output_tokens_details"
        case totalTokens = "total_tokens"
    }
}

private struct ResponseCompletedInputTokensDetails: Decodable, Sendable {
    let cachedTokens: Int64

    private enum CodingKeys: String, CodingKey {
        case cachedTokens = "cached_tokens"
    }
}

private struct ResponseCompletedOutputTokensDetails: Decodable, Sendable {
    let reasoningTokens: Int64

    private enum CodingKeys: String, CodingKey {
        case reasoningTokens = "reasoning_tokens"
    }
}

private func decodeJSONValue<T: Decodable>(_ value: JSONValue, as type: T.Type) -> T? {
    guard let data = try? JSONEncoder().encode(value) else {
        return nil
    }
    return try? JSONDecoder().decode(type, from: data)
}
