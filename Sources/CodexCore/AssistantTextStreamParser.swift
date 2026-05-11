import Foundation

public struct AssistantTextChunk: Equatable, Sendable {
    public var visibleText: String
    public var citations: [String]
    public var planSegments: [ProposedPlanSegment]

    public init(
        visibleText: String = "",
        citations: [String] = [],
        planSegments: [ProposedPlanSegment] = []
    ) {
        self.visibleText = visibleText
        self.citations = citations
        self.planSegments = planSegments
    }

    public var isEmpty: Bool {
        visibleText.isEmpty && citations.isEmpty && planSegments.isEmpty
    }
}

public enum ProposedPlanSegment: Equatable, Sendable {
    case normal(String)
    case proposedPlanStart
    case proposedPlanDelta(String)
    case proposedPlanEnd
}

/// Streaming parser for assistant-only hidden markup.
///
/// Rust strips memory citations before optional plan-mode parsing, so plan
/// deltas never include citation bodies and visible text never includes either
/// hidden tag family.
public struct AssistantTextStreamParser: Sendable {
    private var planMode: Bool
    private var citations = CitationStreamParser()
    private var plan = ProposedPlanParser()

    public init(planMode: Bool) {
        self.planMode = planMode
    }

    public mutating func pushString(_ chunk: String) -> AssistantTextChunk {
        let citationChunk = citations.pushString(chunk)
        var output = parseVisibleText(citationChunk.visibleText)
        output.citations = citationChunk.extracted
        return output
    }

    public mutating func finish() -> AssistantTextChunk {
        let citationChunk = citations.finish()
        var output = parseVisibleText(citationChunk.visibleText)
        if planMode {
            let tail = plan.finish()
            if !tail.isEmpty {
                output.visibleText.append(tail.visibleText)
                output.planSegments.append(contentsOf: tail.extracted)
            }
        }
        output.citations = citationChunk.extracted
        return output
    }

    private mutating func parseVisibleText(_ visibleText: String) -> AssistantTextChunk {
        guard planMode else {
            return AssistantTextChunk(visibleText: visibleText)
        }

        let planChunk = plan.pushString(visibleText)
        return AssistantTextChunk(
            visibleText: planChunk.visibleText,
            planSegments: planChunk.extracted
        )
    }
}

public func stripAssistantCitations(_ text: String) -> (visibleText: String, citations: [String]) {
    var parser = CitationStreamParser()
    var output = parser.pushString(text)
    let tail = parser.finish()
    output.visibleText.append(tail.visibleText)
    output.extracted.append(contentsOf: tail.extracted)
    return (output.visibleText, output.extracted)
}

public func stripProposedPlanBlocks(_ text: String) -> String {
    var parser = ProposedPlanParser()
    var output = parser.pushString(text).visibleText
    output.append(parser.finish().visibleText)
    return output
}

public func extractProposedPlanText(_ text: String) -> String? {
    var parser = ProposedPlanParser()
    var planText = ""
    var sawPlanBlock = false
    for segment in parser.pushString(text).extracted + parser.finish().extracted {
        switch segment {
        case .proposedPlanStart:
            sawPlanBlock = true
            planText.removeAll(keepingCapacity: true)
        case let .proposedPlanDelta(delta):
            planText.append(delta)
        case .proposedPlanEnd,
             .normal:
            break
        }
    }
    return sawPlanBlock ? planText : nil
}

private struct StreamTextChunk<Extracted>: Sendable where Extracted: Sendable {
    var visibleText: String = ""
    var extracted: [Extracted] = []

    var isEmpty: Bool {
        visibleText.isEmpty && extracted.isEmpty
    }
}

private struct CitationStreamParser: Sendable {
    private static let openTag = "<oai-mem-citation>"
    private static let closeTag = "</oai-mem-citation>"

    private var pending = ""
    private var activeContent: String?

    mutating func pushString(_ chunk: String) -> StreamTextChunk<String> {
        pending.append(chunk)
        var output = StreamTextChunk<String>()

        while true {
            if var active = activeContent {
                if let closeRange = pending.range(of: Self.closeTag) {
                    active.append(contentsOf: pending[..<closeRange.lowerBound])
                    output.extracted.append(active)
                    pending.removeSubrange(pending.startIndex..<closeRange.upperBound)
                    activeContent = nil
                    continue
                }

                let keep = pending.longestSuffixPrefixLength(of: Self.closeTag)
                let split = pending.index(pending.endIndex, offsetBy: -keep)
                if split > pending.startIndex {
                    active.append(contentsOf: pending[..<split])
                    pending.removeSubrange(pending.startIndex..<split)
                }
                activeContent = active
                break
            }

            if let openRange = pending.range(of: Self.openTag) {
                output.visibleText.append(contentsOf: pending[..<openRange.lowerBound])
                pending.removeSubrange(pending.startIndex..<openRange.upperBound)
                activeContent = ""
                continue
            }

            let keep = pending.longestSuffixPrefixLength(of: Self.openTag)
            let split = pending.index(pending.endIndex, offsetBy: -keep)
            if split > pending.startIndex {
                output.visibleText.append(contentsOf: pending[..<split])
                pending.removeSubrange(pending.startIndex..<split)
            }
            break
        }

        return output
    }

    mutating func finish() -> StreamTextChunk<String> {
        var output = StreamTextChunk<String>()

        if var active = activeContent {
            active.append(pending)
            output.extracted.append(active)
            activeContent = nil
            pending.removeAll(keepingCapacity: true)
            return output
        }

        output.visibleText = pending
        pending.removeAll(keepingCapacity: true)
        return output
    }
}

private struct ProposedPlanParser: Sendable {
    private static let openTag = "<proposed_plan>"
    private static let closeTag = "</proposed_plan>"

    private var active = false
    private var detectTag = true
    private var lineBuffer = ""

    mutating func pushString(_ chunk: String) -> StreamTextChunk<ProposedPlanSegment> {
        var output = StreamTextChunk<ProposedPlanSegment>()
        var run = ""

        for character in chunk {
            if detectTag {
                if !run.isEmpty {
                    pushText(run, to: &output)
                    run.removeAll(keepingCapacity: true)
                }

                lineBuffer.append(character)
                if character == "\n" {
                    finishLine(to: &output)
                    continue
                }

                let slug = lineBuffer.trimmingLeadingWhitespace()
                if slug.isEmpty || isTagPrefix(slug) {
                    continue
                }

                let buffered = lineBuffer
                lineBuffer.removeAll(keepingCapacity: true)
                detectTag = false
                pushText(buffered, to: &output)
                continue
            }

            run.append(character)
            if character == "\n" {
                pushText(run, to: &output)
                run.removeAll(keepingCapacity: true)
                detectTag = true
            }
        }

        if !run.isEmpty {
            pushText(run, to: &output)
        }
        return output
    }

    mutating func finish() -> StreamTextChunk<ProposedPlanSegment> {
        var output = StreamTextChunk<ProposedPlanSegment>()

        if !lineBuffer.isEmpty {
            let buffered = lineBuffer
            lineBuffer.removeAll(keepingCapacity: true)
            let withoutNewline = buffered.hasSuffix("\n") ? String(buffered.dropLast()) : buffered
            let slug = withoutNewline
                .trimmingLeadingWhitespace()
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if slug == Self.openTag, !active {
                pushSegment(.proposedPlanStart, to: &output)
                active = true
            } else if slug == Self.closeTag, active {
                pushSegment(.proposedPlanEnd, to: &output)
                active = false
            } else {
                pushText(buffered, to: &output)
            }
        }

        if active {
            pushSegment(.proposedPlanEnd, to: &output)
            active = false
        }
        detectTag = true
        return output
    }

    private mutating func finishLine(to output: inout StreamTextChunk<ProposedPlanSegment>) {
        let line = lineBuffer
        lineBuffer.removeAll(keepingCapacity: true)
        let withoutNewline = line.hasSuffix("\n") ? String(line.dropLast()) : line
        let slug = withoutNewline
            .trimmingLeadingWhitespace()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if slug == Self.openTag, !active {
            pushSegment(.proposedPlanStart, to: &output)
            active = true
            detectTag = true
            return
        }

        if slug == Self.closeTag, active {
            pushSegment(.proposedPlanEnd, to: &output)
            active = false
            detectTag = true
            return
        }

        detectTag = true
        pushText(line, to: &output)
    }

    private func pushText(_ text: String, to output: inout StreamTextChunk<ProposedPlanSegment>) {
        if active {
            pushSegment(.proposedPlanDelta(text), to: &output)
        } else {
            pushSegment(.normal(text), to: &output)
        }
    }

    private func pushSegment(
        _ segment: ProposedPlanSegment,
        to output: inout StreamTextChunk<ProposedPlanSegment>
    ) {
        switch segment {
        case let .normal(text):
            guard !text.isEmpty else {
                return
            }
            output.visibleText.append(text)
            if case let .normal(existing)? = output.extracted.last {
                output.extracted.removeLast()
                output.extracted.append(.normal(existing + text))
            } else {
                output.extracted.append(segment)
            }

        case let .proposedPlanDelta(text):
            guard !text.isEmpty else {
                return
            }
            if case let .proposedPlanDelta(existing)? = output.extracted.last {
                output.extracted.removeLast()
                output.extracted.append(.proposedPlanDelta(existing + text))
            } else {
                output.extracted.append(segment)
            }

        case .proposedPlanStart,
             .proposedPlanEnd:
            output.extracted.append(segment)
        }
    }

    private func isTagPrefix(_ slug: String) -> Bool {
        let trimmed = slug.trimmingCharacters(in: .whitespacesAndNewlines)
        return Self.openTag.hasPrefix(trimmed) || Self.closeTag.hasPrefix(trimmed)
    }
}

private extension String {
    func longestSuffixPrefixLength(of needle: String) -> Int {
        let maxLength = Swift.min(count, needle.count - 1)
        guard maxLength > 0 else {
            return 0
        }

        for length in stride(from: maxLength, through: 1, by: -1) {
            if hasSuffix(String(needle.prefix(length))) {
                return length
            }
        }
        return 0
    }

    func trimmingLeadingWhitespace() -> String {
        String(drop(while: { $0.isWhitespace }))
    }
}
