import Foundation

public enum ResponseEventAggregateMode: Equatable, Sendable {
    case aggregatedOnly
    case streaming
}

public struct ResponseEventAggregator: Sendable {
    private var cumulative = ""
    private var cumulativeReasoning = ""
    public let mode: ResponseEventAggregateMode

    public init(mode: ResponseEventAggregateMode = .aggregatedOnly) {
        self.mode = mode
    }

    public mutating func receive(_ result: Result<ResponseEvent, APIError>) -> [Result<ResponseEvent, APIError>] {
        switch result {
        case let .failure(error):
            return [.failure(error)]

        case let .success(event):
            return receive(event)
        }
    }

    public mutating func receive(_ event: ResponseEvent) -> [Result<ResponseEvent, APIError>] {
        switch event {
        case let .outputItemDone(item):
            guard item.isAssistantMessage else {
                return [.success(.outputItemDone(item))]
            }

            switch mode {
            case .aggregatedOnly:
                if cumulative.isEmpty, let text = item.firstOutputText {
                    cumulative.append(text)
                }
                return []

            case .streaming:
                if cumulative.isEmpty {
                    return [.success(.outputItemDone(item))]
                }
                return []
            }

        case let .rateLimits(snapshot):
            return [.success(.rateLimits(snapshot))]

        case let .serverModel(model):
            return [.success(.serverModel(model))]

        case let .modelVerifications(verifications):
            return [.success(.modelVerifications(verifications))]

        case let .serverReasoningIncluded(included):
            return [.success(.serverReasoningIncluded(included))]

        case let .modelsETag(etag):
            return [.success(.modelsETag(etag))]

        case let .toolCallInputDelta(itemID, callID, delta):
            return [.success(.toolCallInputDelta(itemID: itemID, callID: callID, delta: delta))]

        case let .completed(responseID, tokenUsage, endTurn):
            var events: [Result<ResponseEvent, APIError>] = []
            if !cumulativeReasoning.isEmpty {
                events.append(.success(.outputItemDone(.reasoning(
                    id: "",
                    summary: [],
                    content: [.reasoningText(text: cumulativeReasoning)],
                    encryptedContent: nil
                ))))
                cumulativeReasoning.removeAll(keepingCapacity: true)
            }

            if !cumulative.isEmpty {
                events.append(.success(.outputItemDone(.message(
                    role: "assistant",
                    content: [.outputText(text: cumulative)]
                ))))
                cumulative.removeAll(keepingCapacity: true)
            }

            events.append(.success(.completed(responseID: responseID, tokenUsage: tokenUsage, endTurn: endTurn)))
            return events

        case .created,
             .reasoningSummaryDelta,
             .reasoningSummaryPartAdded:
            return []

        case let .outputTextDelta(delta):
            cumulative.append(delta)
            if mode == .streaming {
                return [.success(.outputTextDelta(delta))]
            }
            return []

        case let .reasoningContentDelta(delta, contentIndex):
            cumulativeReasoning.append(delta)
            if mode == .streaming {
                return [.success(.reasoningContentDelta(delta: delta, contentIndex: contentIndex))]
            }
            return []

        case let .outputItemAdded(item):
            return [.success(.outputItemAdded(item))]
        }
    }

    public static func aggregate(
        _ results: [Result<ResponseEvent, APIError>],
        mode: ResponseEventAggregateMode = .aggregatedOnly
    ) -> [Result<ResponseEvent, APIError>] {
        var aggregator = ResponseEventAggregator(mode: mode)
        return results.flatMap { aggregator.receive($0) }
    }

    public static func aggregate(
        _ stream: ResponseEventStream,
        mode: ResponseEventAggregateMode = .aggregatedOnly
    ) -> ResponseEventStream {
        ResponseEventStream { continuation in
            let task = Task {
                var aggregator = ResponseEventAggregator(mode: mode)
                for await result in stream {
                    for event in aggregator.receive(result) {
                        continuation.yield(event)
                    }
                }
                continuation.finish()
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}

private extension ResponseItem {
    var isAssistantMessage: Bool {
        guard case let .message(_, role, _, _) = self else {
            return false
        }
        return role == "assistant"
    }

    var firstOutputText: String? {
        guard case let .message(_, _, content, _) = self else {
            return nil
        }

        return content.compactMap { item -> String? in
            if case let .outputText(text) = item {
                return text
            }
            return nil
        }.first
    }
}
