import Foundation

public struct TokenUsage: Equatable, Codable, Sendable {
    public var inputTokens: Int64
    public var cachedInputTokens: Int64
    public var outputTokens: Int64
    public var reasoningOutputTokens: Int64
    public var totalTokens: Int64

    public init(
        inputTokens: Int64 = 0,
        cachedInputTokens: Int64 = 0,
        outputTokens: Int64 = 0,
        reasoningOutputTokens: Int64 = 0,
        totalTokens: Int64 = 0
    ) {
        self.inputTokens = inputTokens
        self.cachedInputTokens = cachedInputTokens
        self.outputTokens = outputTokens
        self.reasoningOutputTokens = reasoningOutputTokens
        self.totalTokens = totalTokens
    }

    private enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case cachedInputTokens = "cached_input_tokens"
        case outputTokens = "output_tokens"
        case reasoningOutputTokens = "reasoning_output_tokens"
        case totalTokens = "total_tokens"
    }

    public var isZero: Bool {
        totalTokens == 0
    }

    public var cachedInput: Int64 {
        max(cachedInputTokens, 0)
    }

    public var nonCachedInput: Int64 {
        max(inputTokens - cachedInput, 0)
    }

    public var blendedTotal: Int64 {
        max(nonCachedInput + max(outputTokens, 0), 0)
    }

    public var tokensInContextWindow: Int64 {
        totalTokens
    }

    public func percentOfContextWindowRemaining(_ contextWindow: Int64) -> Int64 {
        let baselineTokens: Int64 = 12_000
        if contextWindow <= baselineTokens {
            return 0
        }

        let effectiveWindow = contextWindow - baselineTokens
        let used = max(tokensInContextWindow - baselineTokens, 0)
        let remaining = max(effectiveWindow - used, 0)
        let percentage = (Double(remaining) / Double(effectiveWindow) * 100.0)
            .clamped(to: 0.0...100.0)
            .rounded()
        return Int64(percentage)
    }

    public mutating func addAssign(_ other: TokenUsage) {
        inputTokens += other.inputTokens
        cachedInputTokens += other.cachedInputTokens
        outputTokens += other.outputTokens
        reasoningOutputTokens += other.reasoningOutputTokens
        totalTokens += other.totalTokens
    }
}

public struct TokenUsageInfo: Equatable, Codable, Sendable {
    public var totalTokenUsage: TokenUsage
    public var lastTokenUsage: TokenUsage
    public var modelContextWindow: Int64?

    public init(
        totalTokenUsage: TokenUsage,
        lastTokenUsage: TokenUsage,
        modelContextWindow: Int64? = nil
    ) {
        self.totalTokenUsage = totalTokenUsage
        self.lastTokenUsage = lastTokenUsage
        self.modelContextWindow = modelContextWindow
    }

    private enum CodingKeys: String, CodingKey {
        case totalTokenUsage = "total_token_usage"
        case lastTokenUsage = "last_token_usage"
        case modelContextWindow = "model_context_window"
    }

    public static func newOrAppend(
        info: TokenUsageInfo?,
        last: TokenUsage?,
        modelContextWindow: Int64?
    ) -> TokenUsageInfo? {
        if info == nil, last == nil {
            return nil
        }

        var result = info ?? TokenUsageInfo(
            totalTokenUsage: TokenUsage(),
            lastTokenUsage: TokenUsage(),
            modelContextWindow: modelContextWindow
        )
        if let last {
            result.appendLastUsage(last)
        }
        if let modelContextWindow {
            result.modelContextWindow = modelContextWindow
        }
        return result
    }

    public mutating func appendLastUsage(_ last: TokenUsage) {
        totalTokenUsage.addAssign(last)
        lastTokenUsage = last
    }

    public mutating func fillToContextWindow(_ contextWindow: Int64) {
        let previousTotal = totalTokenUsage.totalTokens
        let delta = max(contextWindow - previousTotal, 0)

        modelContextWindow = contextWindow
        totalTokenUsage = TokenUsage(totalTokens: contextWindow)
        lastTokenUsage = TokenUsage(totalTokens: delta)
    }

    public static func fullContextWindow(_ contextWindow: Int64) -> TokenUsageInfo {
        var info = TokenUsageInfo(
            totalTokenUsage: TokenUsage(),
            lastTokenUsage: TokenUsage(),
            modelContextWindow: contextWindow
        )
        info.fillToContextWindow(contextWindow)
        return info
    }
}

public struct FinalOutput: Equatable, Codable, CustomStringConvertible, Sendable {
    public var tokenUsage: TokenUsage

    public init(tokenUsage: TokenUsage) {
        self.tokenUsage = tokenUsage
    }

    public init(_ tokenUsage: TokenUsage) {
        self.tokenUsage = tokenUsage
    }

    private enum CodingKeys: String, CodingKey {
        case tokenUsage = "token_usage"
    }

    public var description: String {
        let cachedInputSuffix = if tokenUsage.cachedInput > 0 {
            " (+ \(NumberFormat.formatWithSeparators(tokenUsage.cachedInput)) cached)"
        } else {
            ""
        }
        let reasoningSuffix = if tokenUsage.reasoningOutputTokens > 0 {
            " (reasoning \(NumberFormat.formatWithSeparators(tokenUsage.reasoningOutputTokens)))"
        } else {
            ""
        }

        return "Token usage: total=\(NumberFormat.formatWithSeparators(tokenUsage.blendedTotal)) "
            + "input=\(NumberFormat.formatWithSeparators(tokenUsage.nonCachedInput))\(cachedInputSuffix) "
            + "output=\(NumberFormat.formatWithSeparators(tokenUsage.outputTokens))\(reasoningSuffix)"
    }
}

private extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        min(max(self, limits.lowerBound), limits.upperBound)
    }
}
