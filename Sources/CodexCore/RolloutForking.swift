public enum RolloutForking {
    public static func filteredForkHistory(
        _ items: [RolloutRecordItem],
        usageHintTextsToFilter: [String] = []
    ) -> [RolloutRecordItem] {
        items.filter { item in
            if isFilteredUsageHint(item, usageHintTextsToFilter: usageHintTextsToFilter) {
                return false
            }
            return keepForkedRolloutItem(item)
        }
    }

    public static func keepForkedRolloutItem(_ item: RolloutRecordItem) -> Bool {
        switch item {
        case let .responseItem(.message(_, role, _, phase)):
            switch role {
            case "system", "developer", "user":
                return true
            case "assistant":
                return phase == .finalAnswer
            default:
                return false
            }
        case .responseItem:
            return false
        case .turnContext:
            return false
        case .compacted, .eventMsg, .sessionMeta:
            return true
        }
    }

    private static func isFilteredUsageHint(
        _ item: RolloutRecordItem,
        usageHintTextsToFilter: [String]
    ) -> Bool {
        guard !usageHintTextsToFilter.isEmpty,
              case let .responseItem(.message(_, role, content, _)) = item,
              role == "developer",
              content.count == 1,
              case let .inputText(text) = content[0]
        else {
            return false
        }
        return usageHintTextsToFilter.contains(text)
    }
}
