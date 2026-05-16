import Foundation

private let approxBytesPerToken = 4

public enum TruncationPolicy: Equatable, Hashable, Sendable {
    case bytes(Int)
    case tokens(Int)

    private enum CodingKeys: String, CodingKey {
        case mode
        case limit
    }

    private enum Mode: String, Codable {
        case bytes
        case tokens
    }

    public func multiplied(by multiplier: Double) -> TruncationPolicy {
        switch self {
        case let .bytes(bytes):
            return .bytes(Int(ceil(Double(bytes) * multiplier)))
        case let .tokens(tokens):
            return .tokens(Int(ceil(Double(tokens) * multiplier)))
        }
    }

    public var tokenBudget: Int {
        switch self {
        case let .bytes(bytes):
            return Int(clamping: Truncation.approxTokensFromByteCount(max(0, bytes)))
        case let .tokens(tokens):
            return max(0, tokens)
        }
    }

    public var byteBudget: Int {
        switch self {
        case let .bytes(bytes):
            return max(0, bytes)
        case let .tokens(tokens):
            return Truncation.approxBytesForTokens(max(0, tokens))
        }
    }
}

extension TruncationPolicy: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let limit = try container.decode(Int.self, forKey: .limit)
        switch try container.decode(Mode.self, forKey: .mode) {
        case .bytes:
            self = .bytes(limit)
        case .tokens:
            self = .tokens(limit)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .bytes(limit):
            try container.encode(Mode.bytes, forKey: .mode)
            try container.encode(limit, forKey: .limit)
        case let .tokens(limit):
            try container.encode(Mode.tokens, forKey: .mode)
            try container.encode(limit, forKey: .limit)
        }
    }
}

public enum Truncation {
    public static func formattedTruncateText(_ content: String, policy: TruncationPolicy) -> String {
        if content.utf8.count <= policy.byteBudget {
            return content
        }
        let totalLines = rustLineCount(content)
        let result = truncateText(content, policy: policy)
        return "Total output lines: \(totalLines)\n\n\(result)"
    }

    public static func truncateText(_ content: String, policy: TruncationPolicy) -> String {
        switch policy {
        case .bytes:
            return truncateWithByteEstimate(content, policy: policy)
        case .tokens:
            return truncateWithTokenBudget(content, policy: policy).text
        }
    }

    public static func truncateFunctionOutputItems(
        _ items: [FunctionCallOutputContentItem],
        policy: TruncationPolicy
    ) -> [FunctionCallOutputContentItem] {
        var output: [FunctionCallOutputContentItem] = []
        output.reserveCapacity(items.count)
        var remainingBudget = switch policy {
        case .bytes:
            policy.byteBudget
        case .tokens:
            policy.tokenBudget
        }
        var omittedTextItems = 0

        for item in items {
            switch item {
            case let .inputText(text):
                if remainingBudget == 0 {
                    omittedTextItems += 1
                    continue
                }

                let cost = switch policy {
                case .bytes:
                    text.utf8.count
                case .tokens:
                    approxTokenCount(text)
                }

                if cost <= remainingBudget {
                    output.append(.inputText(text: text))
                    remainingBudget = max(0, remainingBudget - cost)
                } else {
                    let snippetPolicy: TruncationPolicy = switch policy {
                    case .bytes:
                        .bytes(remainingBudget)
                    case .tokens:
                        .tokens(remainingBudget)
                    }
                    let snippet = truncateText(text, policy: snippetPolicy)
                    if snippet.isEmpty {
                        omittedTextItems += 1
                    } else {
                        output.append(.inputText(text: snippet))
                    }
                    remainingBudget = 0
                }
            case let .inputImage(imageURL, detail):
                output.append(.inputImage(imageURL: imageURL, detail: detail))
            case let .inputAudio(inputAudio):
                output.append(.inputAudio(inputAudio: inputAudio))
            }
        }

        if omittedTextItems > 0 {
            output.append(.inputText(text: "[omitted \(omittedTextItems) text items ...]"))
        }

        return output
    }

    public static func truncateWithTokenBudget(
        _ text: String,
        policy: TruncationPolicy
    ) -> (text: String, originalTokenCount: UInt64?) {
        if text.isEmpty {
            return ("", nil)
        }

        let maxTokens = policy.tokenBudget
        if maxTokens > 0 && text.utf8.count <= approxBytesForTokens(maxTokens) {
            return (text, nil)
        }

        let truncated = truncateWithByteEstimate(text, policy: policy)
        let originalTokenCount = UInt64(approxTokenCount(text))
        if truncated == text {
            return (truncated, nil)
        }
        return (truncated, originalTokenCount)
    }

    public static func splitString(
        _ text: String,
        beginningBytes: Int,
        endBytes: Int
    ) -> (removedScalars: Int, prefix: String, suffix: String) {
        if text.isEmpty {
            return (0, "", "")
        }

        let scalars = Array(text.unicodeScalars)
        let totalBytes = text.utf8.count
        let leftBudget = max(0, beginningBytes)
        let rightBudget = max(0, endBytes)
        let tailStartTarget = max(0, totalBytes - rightBudget)
        var byteOffset = 0
        var prefixEnd = 0
        var suffixStart = scalars.count
        var suffixStarted = false
        var removedScalars = 0

        for (index, scalar) in scalars.enumerated() {
            let scalarEnd = byteOffset + scalar.utf8.count
            if scalarEnd <= leftBudget {
                prefixEnd = index + 1
                byteOffset = scalarEnd
                continue
            }

            if byteOffset >= tailStartTarget {
                if !suffixStarted {
                    suffixStart = index
                    suffixStarted = true
                }
                byteOffset = scalarEnd
                continue
            }

            removedScalars += 1
            byteOffset = scalarEnd
        }

        if suffixStart < prefixEnd {
            suffixStart = prefixEnd
        }

        return (
            removedScalars,
            makeString(from: scalars[..<prefixEnd]),
            makeString(from: scalars[suffixStart...])
        )
    }

    public static func approxTokenCount(_ text: String) -> Int {
        let length = text.utf8.count
        return (length + approxBytesPerToken - 1) / approxBytesPerToken
    }

    public static func approxBytesForTokens(_ tokens: Int) -> Int {
        let safeTokens = max(0, tokens)
        let result = safeTokens.multipliedReportingOverflow(by: approxBytesPerToken)
        return result.overflow ? Int.max : result.partialValue
    }

    public static func approxTokensFromByteCount(_ bytes: Int) -> UInt64 {
        let value = UInt64(max(0, bytes))
        return (value + UInt64(approxBytesPerToken - 1)) / UInt64(approxBytesPerToken)
    }

    private static func truncateWithByteEstimate(_ text: String, policy: TruncationPolicy) -> String {
        if text.isEmpty {
            return ""
        }

        let totalScalars = text.unicodeScalars.count
        let maxBytes = policy.byteBudget
        if maxBytes == 0 {
            return formatTruncationMarker(
                policy: policy,
                removedCount: removedUnitsForSource(
                    policy: policy,
                    removedBytes: text.utf8.count,
                    removedScalars: totalScalars
                )
            )
        }

        if text.utf8.count <= maxBytes {
            return text
        }

        let totalBytes = text.utf8.count
        let (leftBudget, rightBudget) = splitBudget(maxBytes)
        let (removedScalars, prefix, suffix) = splitString(
            text,
            beginningBytes: leftBudget,
            endBytes: rightBudget
        )
        let marker = formatTruncationMarker(
            policy: policy,
            removedCount: removedUnitsForSource(
                policy: policy,
                removedBytes: max(0, totalBytes - maxBytes),
                removedScalars: removedScalars
            )
        )
        return assembleTruncatedOutput(prefix: prefix, suffix: suffix, marker: marker)
    }

    private static func formatTruncationMarker(policy: TruncationPolicy, removedCount: UInt64) -> String {
        switch policy {
        case .tokens:
            return "…\(removedCount) tokens truncated…"
        case .bytes:
            return "…\(removedCount) chars truncated…"
        }
    }

    private static func splitBudget(_ budget: Int) -> (Int, Int) {
        let safeBudget = max(0, budget)
        let left = safeBudget / 2
        return (left, safeBudget - left)
    }

    private static func removedUnitsForSource(
        policy: TruncationPolicy,
        removedBytes: Int,
        removedScalars: Int
    ) -> UInt64 {
        switch policy {
        case .tokens:
            return approxTokensFromByteCount(removedBytes)
        case .bytes:
            return UInt64(max(0, removedScalars))
        }
    }

    private static func assembleTruncatedOutput(prefix: String, suffix: String, marker: String) -> String {
        "\(prefix)\(marker)\(suffix)"
    }

    private static func rustLineCount(_ text: String) -> Int {
        if text.isEmpty {
            return 0
        }
        var count = text.split(separator: "\n", omittingEmptySubsequences: false).count
        if text.hasSuffix("\n") {
            count -= 1
        }
        return count
    }

    private static func makeString<S: Sequence>(from scalars: S) -> String where S.Element == UnicodeScalar {
        var result = String()
        result.unicodeScalars.append(contentsOf: scalars)
        return result
    }
}
