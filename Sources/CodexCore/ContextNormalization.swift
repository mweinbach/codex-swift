import Foundation

public enum ContextNormalization {
    public static func ensureCallOutputsPresent(_ items: inout [ResponseItem]) {
        var missingOutputsToInsert: [(index: Int, item: ResponseItem)] = []

        for (index, item) in items.enumerated() {
            switch item {
            case let .functionCall(_, _, _, callID):
                let hasOutput = items.contains { candidate in
                    if case let .functionCallOutput(existing, _) = candidate {
                        return existing == callID
                    }
                    return false
                }

                if !hasOutput {
                    missingOutputsToInsert.append((
                        index,
                        .functionCallOutput(callID: callID, output: FunctionCallOutputPayload(content: "aborted"))
                    ))
                }

            case let .customToolCall(_, _, callID, _, _):
                let hasOutput = items.contains { candidate in
                    if case let .customToolCallOutput(existing, _) = candidate {
                        return existing == callID
                    }
                    return false
                }

                if !hasOutput {
                    missingOutputsToInsert.append((
                        index,
                        .customToolCallOutput(callID: callID, output: "aborted")
                    ))
                }

            case let .localShellCall(_, callID, _, _):
                guard let callID else {
                    continue
                }

                let hasOutput = items.contains { candidate in
                    if case let .functionCallOutput(existing, _) = candidate {
                        return existing == callID
                    }
                    return false
                }

                if !hasOutput {
                    missingOutputsToInsert.append((
                        index,
                        .functionCallOutput(callID: callID, output: FunctionCallOutputPayload(content: "aborted"))
                    ))
                }

            case .message,
                 .reasoning,
                 .functionCallOutput,
                 .customToolCallOutput,
                 .webSearchCall,
                 .compaction,
                 .knownPersisted,
                 .other:
                continue
            }
        }

        for insertion in missingOutputsToInsert.reversed() {
            items.insert(insertion.item, at: insertion.index + 1)
        }
    }

    public static func removeOrphanOutputs(_ items: inout [ResponseItem]) {
        let functionCallIDs = Set(items.compactMap { item -> String? in
            if case let .functionCall(_, _, _, callID) = item {
                return callID
            }
            return nil
        })
        let localShellCallIDs = Set(items.compactMap { item -> String? in
            if case let .localShellCall(_, callID, _, _) = item {
                return callID
            }
            return nil
        })
        let customToolCallIDs = Set(items.compactMap { item -> String? in
            if case let .customToolCall(_, _, callID, _, _) = item {
                return callID
            }
            return nil
        })

        items.removeAll { item in
            switch item {
            case let .functionCallOutput(callID, _):
                return !functionCallIDs.contains(callID) && !localShellCallIDs.contains(callID)
            case let .customToolCallOutput(callID, _):
                return !customToolCallIDs.contains(callID)
            default:
                return false
            }
        }
    }

    public static func removeCorresponding(for item: ResponseItem, from items: inout [ResponseItem]) {
        switch item {
        case let .functionCall(_, _, _, callID):
            removeFirstMatching(from: &items) { candidate in
                if case let .functionCallOutput(existing, _) = candidate {
                    return existing == callID
                }
                return false
            }

        case let .functionCallOutput(callID, _):
            if removeFirstMatching(from: &items, predicate: { candidate in
                if case let .functionCall(_, _, _, existing) = candidate {
                    return existing == callID
                }
                return false
            }) {
                return
            }

            removeFirstMatching(from: &items) { candidate in
                if case let .localShellCall(_, existing, _, _) = candidate {
                    return existing == callID
                }
                return false
            }

        case let .customToolCall(_, _, callID, _, _):
            removeFirstMatching(from: &items) { candidate in
                if case let .customToolCallOutput(existing, _) = candidate {
                    return existing == callID
                }
                return false
            }

        case let .customToolCallOutput(callID, _):
            removeFirstMatching(from: &items) { candidate in
                if case let .customToolCall(_, _, existing, _, _) = candidate {
                    return existing == callID
                }
                return false
            }

        case let .localShellCall(_, callID, _, _):
            guard let callID else {
                return
            }
            removeFirstMatching(from: &items) { candidate in
                if case let .functionCallOutput(existing, _) = candidate {
                    return existing == callID
                }
                return false
            }

        case .message,
             .reasoning,
             .webSearchCall,
             .compaction,
             .knownPersisted,
             .other:
            return
        }
    }

    public static func normalizeHistory(_ items: inout [ResponseItem]) {
        ensureCallOutputsPresent(&items)
        removeOrphanOutputs(&items)
    }

    @discardableResult
    private static func removeFirstMatching(
        from items: inout [ResponseItem],
        predicate: (ResponseItem) -> Bool
    ) -> Bool {
        guard let index = items.firstIndex(where: predicate) else {
            return false
        }
        items.remove(at: index)
        return true
    }
}
