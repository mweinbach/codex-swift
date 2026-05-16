import Foundation

public struct TotalTokenUsageBreakdown: Equatable, Sendable {
    public var lastAPIResponseTotalTokens: Int64
    public var allHistoryItemsModelVisibleBytes: Int64
    public var estimatedTokensOfItemsAddedSinceLastSuccessfulAPIResponse: Int64
    public var estimatedBytesOfItemsAddedSinceLastSuccessfulAPIResponse: Int64

    public init(
        lastAPIResponseTotalTokens: Int64 = 0,
        allHistoryItemsModelVisibleBytes: Int64 = 0,
        estimatedTokensOfItemsAddedSinceLastSuccessfulAPIResponse: Int64 = 0,
        estimatedBytesOfItemsAddedSinceLastSuccessfulAPIResponse: Int64 = 0
    ) {
        self.lastAPIResponseTotalTokens = lastAPIResponseTotalTokens
        self.allHistoryItemsModelVisibleBytes = allHistoryItemsModelVisibleBytes
        self.estimatedTokensOfItemsAddedSinceLastSuccessfulAPIResponse =
            estimatedTokensOfItemsAddedSinceLastSuccessfulAPIResponse
        self.estimatedBytesOfItemsAddedSinceLastSuccessfulAPIResponse =
            estimatedBytesOfItemsAddedSinceLastSuccessfulAPIResponse
    }
}

public struct ContextManager: Equatable, Sendable {
    private var items: [ResponseItem]
    private var tokenInfo: TokenUsageInfo?
    private var referenceContextItem: TurnContextItem?
    public private(set) var historyVersion: UInt64

    public init(
        items: [ResponseItem] = [],
        tokenInfo: TokenUsageInfo? = TokenUsageInfo.newOrAppend(
            info: nil,
            last: nil,
            modelContextWindow: nil
        ),
        referenceContextItem: TurnContextItem? = nil,
        historyVersion: UInt64 = 0
    ) {
        self.items = items
        self.tokenInfo = tokenInfo
        self.referenceContextItem = referenceContextItem
        self.historyVersion = historyVersion
    }

    public var rawItems: [ResponseItem] {
        items
    }

    public func currentTokenInfo() -> TokenUsageInfo? {
        tokenInfo
    }

    public func currentReferenceContextItem() -> TurnContextItem? {
        referenceContextItem
    }

    public mutating func setTokenInfo(_ info: TokenUsageInfo?) {
        tokenInfo = info
    }

    public mutating func setReferenceContextItem(_ item: TurnContextItem?) {
        referenceContextItem = item
    }

    public mutating func setTokenUsageFull(contextWindow: Int64) {
        if tokenInfo == nil {
            tokenInfo = .fullContextWindow(contextWindow)
        } else {
            tokenInfo?.fillToContextWindow(contextWindow)
        }
    }

    public mutating func recordItems(
        _ newItems: [ResponseItem],
        policy: TruncationPolicy = .tokens(10_000)
    ) {
        for item in newItems where Self.isAPIMessage(item) {
            items.append(Self.processItem(item, policy: policy))
        }
    }

    public mutating func recordModelWarning(_ message: String) {
        items.append(.message(role: "user", content: [.inputText(text: "Warning: \(message)")]))
        historyVersion = historyVersion.addingSaturating(1)
    }

    public func forPrompt(inputModalities: [InputModality] = [.text, .image]) -> [ResponseItem] {
        var normalized = items
        ContextNormalization.normalizeHistory(&normalized)
        ContextNormalization.stripImagesWhenUnsupported(inputModalities: inputModalities, items: &normalized)
        return normalized
    }

    public mutating func removeFirstItem() {
        guard !items.isEmpty else {
            return
        }
        let removed = items.removeFirst()
        ContextNormalization.removeCorresponding(for: removed, from: &items)
    }

    @discardableResult
    public mutating func removeLastItem() -> Bool {
        guard let removed = items.popLast() else {
            return false
        }
        ContextNormalization.removeCorresponding(for: removed, from: &items)
        historyVersion = historyVersion.addingSaturating(1)
        return true
    }

    public mutating func replace(items newItems: [ResponseItem]) {
        items = newItems
        historyVersion = historyVersion.addingSaturating(1)
    }

    public mutating func dropLastUserTurns(count: UInt32) {
        guard count > 0 else {
            return
        }

        let snapshot = items
        let userPositions = snapshot.indices.filter { Self.isUserTurnBoundary(snapshot[$0]) }
        guard let firstInstructionTurnIndex = userPositions.first else {
            replace(items: snapshot)
            return
        }

        let nFromEnd = Int(clamping: count)
        var cutIndex = if nFromEnd >= userPositions.count {
            firstInstructionTurnIndex
        } else {
            userPositions[userPositions.count - nFromEnd]
        }
        cutIndex = trimPreTurnContextUpdates(
            snapshot: snapshot,
            firstInstructionTurnIndex: firstInstructionTurnIndex,
            cutIndex: cutIndex
        )

        replace(items: Array(snapshot[..<cutIndex]))
    }

    @discardableResult
    public mutating func replaceLastTurnImages(placeholder: String) -> Bool {
        guard let index = items.lastIndex(where: { item in
            if case .functionCallOutput = item {
                return true
            }
            return Self.isUserTurnBoundary(item)
        }) else {
            return false
        }

        guard case let .functionCallOutput(callID, output) = items[index],
              let contentItems = output.contentItems
        else {
            return false
        }

        var replaced = false
        let rewritten = contentItems.map { item in
            switch item {
            case .inputImage:
                replaced = true
                return FunctionCallOutputContentItem.inputText(text: placeholder)
            case .inputText:
                return item
            }
        }

        guard replaced else {
            return false
        }

        items[index] = .functionCallOutput(
            callID: callID,
            output: FunctionCallOutputPayload(
                content: output.content,
                contentItems: rewritten,
                success: output.success
            )
        )
        historyVersion = historyVersion.addingSaturating(1)
        return true
    }

    public mutating func updateTokenInfo(
        usage: TokenUsage,
        modelContextWindow: Int64?
    ) {
        tokenInfo = TokenUsageInfo.newOrAppend(
            info: tokenInfo,
            last: usage,
            modelContextWindow: modelContextWindow
        )
    }

    public func nonLastReasoningItemsTokens() -> Int64 {
        guard let lastUserIndex = items.lastIndex(where: Self.isUserTurnBoundary) else {
            return 0
        }

        return items[..<lastUserIndex].reduce(Int64(0)) { total, item in
            guard case .reasoning(_, _, _, .some) = item else {
                return total
            }
            return total.addingSaturating(Self.estimateItemTokenCount(item))
        }
    }

    public func itemsAfterLastModelGeneratedItem() -> [ResponseItem] {
        let start = items.lastIndex(where: Self.isModelGeneratedItem)
            .map { items.index(after: $0) }
            ?? items.endIndex
        return Array(items[start...])
    }

    public func totalTokenUsage(serverReasoningIncluded: Bool) -> Int64 {
        let lastTokens = tokenInfo?.lastTokenUsage.totalTokens ?? 0
        let tailTokens = itemsAfterLastModelGeneratedItem().reduce(Int64(0)) { total, item in
            total.addingSaturating(Self.estimateItemTokenCount(item))
        }

        if serverReasoningIncluded {
            return lastTokens.addingSaturating(tailTokens)
        }
        return lastTokens
            .addingSaturating(nonLastReasoningItemsTokens())
            .addingSaturating(tailTokens)
    }

    public func totalTokenUsageBreakdown() -> TotalTokenUsageBreakdown {
        let lastUsage = tokenInfo?.lastTokenUsage ?? TokenUsage()
        let tailItems = itemsAfterLastModelGeneratedItem()
        let allBytes = items.reduce(Int64(0)) { total, item in
            total.addingSaturating(Self.estimateItemModelVisibleBytes(item))
        }
        let tailBytes = tailItems.reduce(Int64(0)) { total, item in
            total.addingSaturating(Self.estimateItemModelVisibleBytes(item))
        }
        let tailTokens = tailItems.reduce(Int64(0)) { total, item in
            total.addingSaturating(Self.estimateItemTokenCount(item))
        }

        return TotalTokenUsageBreakdown(
            lastAPIResponseTotalTokens: lastUsage.totalTokens,
            allHistoryItemsModelVisibleBytes: allBytes,
            estimatedTokensOfItemsAddedSinceLastSuccessfulAPIResponse: tailTokens,
            estimatedBytesOfItemsAddedSinceLastSuccessfulAPIResponse: tailBytes
        )
    }

    public func estimateTokenCount(baseInstructionsText: String) -> Int64 {
        let baseTokens = Int64(clamping: Truncation.approxTokenCount(baseInstructionsText))
        let itemTokens = items.reduce(Int64(0)) { total, item in
            total.addingSaturating(Self.estimateItemTokenCount(item))
        }
        return baseTokens.addingSaturating(itemTokens)
    }

    public static func estimateItemTokenCount(_ item: ResponseItem) -> Int64 {
        let bytes = ContextTokenEstimator.estimateResponseItemModelVisibleBytes(item)
        return Int64(clamping: Truncation.approxTokensFromByteCount(bytes))
    }

    public static func isUserTurnBoundary(_ item: ResponseItem) -> Bool {
        guard case let .message(_, role, content, _) = item else {
            return false
        }

        if role == "assistant", InterAgentCommunication.isMessageContent(content) {
            return true
        }

        guard role == "user" else {
            return false
        }
        return !isContextualUserMessageContent(content)
    }

    public static func isModelGeneratedItem(_ item: ResponseItem) -> Bool {
        switch item {
        case let .message(_, role, _, _):
            return role == "assistant"
        case .reasoning,
             .localShellCall,
             .functionCall,
             .toolSearchCall,
             .customToolCall,
             .webSearchCall,
             .imageGenerationCall,
             .compaction,
             .contextCompaction:
            return true
        case .functionCallOutput,
             .customToolCallOutput,
             .toolSearchOutput,
             .ghostSnapshot,
             .knownPersisted,
             .other:
            return false
        }
    }

    public static func isCodexGeneratedItem(_ item: ResponseItem) -> Bool {
        switch item {
        case let .message(_, role, _, _):
            return role == "developer"
        case .functionCallOutput,
             .customToolCallOutput,
             .toolSearchOutput:
            return true
        case .reasoning,
             .localShellCall,
             .functionCall,
             .toolSearchCall,
             .customToolCall,
             .webSearchCall,
             .imageGenerationCall,
             .compaction,
             .contextCompaction,
             .ghostSnapshot,
             .knownPersisted,
             .other:
            return false
        }
    }

    private static func processItem(_ item: ResponseItem, policy: TruncationPolicy) -> ResponseItem {
        let policyWithSerializationBudget = policy.multiplied(by: 1.2)
        switch item {
        case let .functionCallOutput(callID, output):
            return .functionCallOutput(
                callID: callID,
                output: truncateFunctionOutputPayload(output, policy: policyWithSerializationBudget)
            )

        case let .customToolCallOutput(callID, name, output):
            return .customToolCallOutput(
                callID: callID,
                name: name,
                output: truncateFunctionOutputPayload(output, policy: policyWithSerializationBudget)
            )

        case .message,
             .reasoning,
             .localShellCall,
             .functionCall,
             .toolSearchCall,
             .toolSearchOutput,
             .webSearchCall,
             .imageGenerationCall,
             .customToolCall,
             .ghostSnapshot,
             .compaction,
             .contextCompaction,
             .knownPersisted,
             .other:
            return item
        }
    }

    private static func truncateFunctionOutputPayload(
        _ output: FunctionCallOutputPayload,
        policy: TruncationPolicy
    ) -> FunctionCallOutputPayload {
        if let contentItems = output.contentItems {
            return FunctionCallOutputPayload(
                content: output.content,
                contentItems: Truncation.truncateFunctionOutputItems(contentItems, policy: policy),
                success: output.success
            )
        }
        return FunctionCallOutputPayload(
            content: Truncation.truncateText(output.content, policy: policy),
            success: output.success
        )
    }

    private static func isAPIMessage(_ item: ResponseItem) -> Bool {
        switch item {
        case let .message(_, role, _, _):
            return role != "system"
        case .reasoning,
             .localShellCall,
             .functionCall,
             .toolSearchCall,
             .functionCallOutput,
             .customToolCall,
             .customToolCallOutput,
             .toolSearchOutput,
             .webSearchCall,
             .imageGenerationCall,
             .ghostSnapshot,
             .compaction,
             .contextCompaction,
             .knownPersisted:
            return true
        case .other:
            return false
        }
    }

    private static func estimateItemModelVisibleBytes(_ item: ResponseItem) -> Int64 {
        Int64(clamping: ContextTokenEstimator.estimateResponseItemModelVisibleBytes(item))
    }

    private mutating func trimPreTurnContextUpdates(
        snapshot: [ResponseItem],
        firstInstructionTurnIndex: Int,
        cutIndex: Int
    ) -> Int {
        var index = cutIndex
        while index > firstInstructionTurnIndex {
            switch snapshot[index - 1] {
            case let .message(_, "developer", content, _) where Self.isContextualDeveloperMessageContent(content):
                if Self.hasNonContextualDeveloperMessageContent(content) {
                    referenceContextItem = nil
                }
                index -= 1

            case let .message(_, "user", content, _) where Self.isContextualUserMessageContent(content):
                index -= 1

            default:
                return index
            }
        }
        return index
    }

    private static func isContextualUserMessageContent(_ content: [ContentItem]) -> Bool {
        content.contains(where: isContextualUserFragment)
    }

    private static func isContextualUserFragment(_ item: ContentItem) -> Bool {
        guard case let .inputText(text) = item else {
            return false
        }
        if HookPromptFragment.parseXML(text) != nil {
            return true
        }
        return ContextualUserFragments.isStandardText(text)
    }

    private static func isContextualDeveloperMessageContent(_ content: [ContentItem]) -> Bool {
        content.contains(where: isContextualDeveloperFragment)
    }

    private static func hasNonContextualDeveloperMessageContent(_ content: [ContentItem]) -> Bool {
        content.contains { !isContextualDeveloperFragment($0) }
    }

    private static func isContextualDeveloperFragment(_ item: ContentItem) -> Bool {
        guard case let .inputText(text) = item else {
            return false
        }
        let lowercased = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return [
            "<permissions instructions>",
            "<model_switch>",
            "<collaboration_mode>",
            "<realtime_conversation>",
            "<personality_spec>"
        ].contains { lowercased.hasPrefix($0) }
    }
}

private extension Int64 {
    func addingSaturating(_ other: Int64) -> Int64 {
        let (result, overflow) = addingReportingOverflow(other)
        return overflow ? Int64.max : result
    }
}

private extension UInt64 {
    func addingSaturating(_ other: UInt64) -> UInt64 {
        let (result, overflow) = addingReportingOverflow(other)
        return overflow ? UInt64.max : result
    }
}
