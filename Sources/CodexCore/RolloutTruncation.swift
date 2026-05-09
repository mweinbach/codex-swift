import Foundation

public enum RolloutTruncation {
    public static func initialHistoryHasPriorUserTurns(_ history: InitialHistory) -> Bool {
        history.rolloutItems.contains(where: isUserTurnBoundary)
    }

    public static func userMessagePositions(in items: [RolloutRecordItem]) -> [Int] {
        var userPositions: [Int] = []
        for (index, item) in items.enumerated() {
            switch item {
            case let .responseItem(responseItem) where isRealUserMessageBoundary(responseItem):
                userPositions.append(index)
            case let .eventMsg(.threadRolledBack(rollback)):
                let count = Int(rollback.numTurns)
                userPositions.removeLast(min(count, userPositions.count))
            default:
                break
            }
        }
        return userPositions
    }

    public static func forkTurnPositions(in items: [RolloutRecordItem]) -> [Int] {
        var rollbackTurnPositions: [Int] = []
        var forkTurnPositions: [Int] = []
        for (index, item) in items.enumerated() {
            switch item {
            case let .responseItem(responseItem):
                if isUserTurnBoundary(responseItem) {
                    rollbackTurnPositions.append(index)
                }
                if isRealUserMessageBoundary(responseItem) || isTriggerTurnBoundary(responseItem) {
                    forkTurnPositions.append(index)
                }
            case let .eventMsg(.threadRolledBack(rollback)):
                let count = Int(rollback.numTurns)
                guard count > 0 else {
                    continue
                }
                guard let rollbackStartIndex = rollbackStartIndex(
                    rollbackTurnPositions: rollbackTurnPositions,
                    count: count
                ) else {
                    continue
                }
                rollbackTurnPositions.removeLast(min(count, rollbackTurnPositions.count))
                forkTurnPositions.removeAll { $0 >= rollbackStartIndex }
            default:
                break
            }
        }
        return forkTurnPositions
    }

    public static func truncateBeforeNthUserMessageFromStart(
        _ items: [RolloutRecordItem],
        nFromStart: Int
    ) -> [RolloutRecordItem] {
        if nFromStart == Int.max {
            return items
        }
        let positions = userMessagePositions(in: items)
        guard positions.count > nFromStart else {
            return items
        }
        return Array(items[..<positions[nFromStart]])
    }

    public static func truncateToLastNForkTurns(
        _ items: [RolloutRecordItem],
        nFromEnd: Int
    ) -> [RolloutRecordItem] {
        if nFromEnd == 0 {
            return []
        }
        let positions = forkTurnPositions(in: items)
        guard positions.count > nFromEnd else {
            return items
        }
        return Array(items[positions[positions.count - nFromEnd]...])
    }

    private static func rollbackStartIndex(rollbackTurnPositions: [Int], count: Int) -> Int? {
        if rollbackTurnPositions.count >= count {
            return rollbackTurnPositions[rollbackTurnPositions.count - count]
        }
        return rollbackTurnPositions.first
    }

    private static func isUserTurnBoundary(_ item: RolloutRecordItem) -> Bool {
        guard case let .responseItem(responseItem) = item else {
            return false
        }
        return isUserTurnBoundary(responseItem)
    }

    private static func isUserTurnBoundary(_ item: ResponseItem) -> Bool {
        switch item {
        case let .message(_, role, content, _):
            return isRealUserMessageBoundary(item)
                || (role == "assistant" && InterAgentCommunication.isMessageContent(content))
        default:
            return false
        }
    }

    private static func isRealUserMessageBoundary(_ item: ResponseItem) -> Bool {
        guard case .userMessage = EventMapping.parseTurnItem(item) else {
            return false
        }
        return true
    }

    private static func isTriggerTurnBoundary(_ item: ResponseItem) -> Bool {
        guard case let .message(_, role, content, _) = item, role == "assistant" else {
            return false
        }
        return InterAgentCommunication.fromMessageContent(content)?.triggerTurn == true
    }
}
