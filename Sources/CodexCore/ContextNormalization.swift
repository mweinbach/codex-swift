import Foundation

public enum ContextNormalization {
    public static let imageContentOmittedPlaceholder = "image content omitted because you do not support image input"
    public static let audioContentOmittedPlaceholder = "audio content omitted because you do not support audio input"

    public static func ensureCallOutputsPresent(_ items: inout [ResponseItem]) {
        var missingOutputsToInsert: [(index: Int, item: ResponseItem)] = []

        for (index, item) in items.enumerated() {
            switch item {
            case let .functionCall(_, _, _, _, callID):
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

            case let .toolSearchCall(_, callID, _, _, _):
                guard let callID else {
                    continue
                }

                let hasOutput = items.contains { candidate in
                    if case let .toolSearchOutput(existing?, _, _, _) = candidate {
                        return existing == callID
                    }
                    return false
                }

                if !hasOutput {
                    missingOutputsToInsert.append((
                        index,
                        .toolSearchOutput(callID: callID, status: "completed", execution: "client", tools: [])
                    ))
                }

            case let .customToolCall(_, _, callID, _, _):
                let hasOutput = items.contains { candidate in
                    if case let .customToolCallOutput(existing, _, _) = candidate {
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
                 .toolSearchOutput,
                 .webSearchCall,
                 .imageGenerationCall,
                 .ghostSnapshot,
                 .compaction,
                 .contextCompaction,
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
            if case let .functionCall(_, _, _, _, callID) = item {
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
        let toolSearchCallIDs = Set(items.compactMap { item -> String? in
            if case let .toolSearchCall(_, callID?, _, _, _) = item {
                return callID
            }
            return nil
        })

        items.removeAll { item in
            switch item {
            case let .functionCallOutput(callID, _):
                return !functionCallIDs.contains(callID) && !localShellCallIDs.contains(callID)
            case let .customToolCallOutput(callID, _, _):
                return !customToolCallIDs.contains(callID)
            case let .toolSearchOutput(callID, _, execution, _):
                guard execution != "server", let callID else {
                    return false
                }
                return !toolSearchCallIDs.contains(callID)
            default:
                return false
            }
        }
    }

    public static func removeCorresponding(for item: ResponseItem, from items: inout [ResponseItem]) {
        switch item {
        case let .functionCall(_, _, _, _, callID):
            removeFirstMatching(from: &items) { candidate in
                if case let .functionCallOutput(existing, _) = candidate {
                    return existing == callID
                }
                return false
            }

        case let .functionCallOutput(callID, _):
            if removeFirstMatching(from: &items, predicate: { candidate in
                if case let .functionCall(_, _, _, _, existing) = candidate {
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
                if case let .customToolCallOutput(existing, _, _) = candidate {
                    return existing == callID
                }
                return false
            }

        case let .customToolCallOutput(callID, _, _):
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

        case let .toolSearchCall(_, callID, _, _, _):
            guard let callID else {
                return
            }
            removeFirstMatching(from: &items) { candidate in
                if case let .toolSearchOutput(existing?, _, _, _) = candidate {
                    return existing == callID
                }
                return false
            }

        case let .toolSearchOutput(callID, _, _, _):
            guard let callID else {
                return
            }
            removeFirstMatching(from: &items) { candidate in
                if case let .toolSearchCall(_, existing?, _, _, _) = candidate {
                    return existing == callID
                }
                return false
            }

        case .message,
             .reasoning,
             .webSearchCall,
             .imageGenerationCall,
             .ghostSnapshot,
             .compaction,
             .contextCompaction,
             .knownPersisted,
             .other:
            return
        }
    }

    public static func normalizeHistory(_ items: inout [ResponseItem]) {
        ensureCallOutputsPresent(&items)
        removeOrphanOutputs(&items)
    }

    public static func stripImagesWhenUnsupported(
        inputModalities: [InputModality],
        items: inout [ResponseItem]
    ) {
        stripUnsupportedMediaContent(inputModalities: inputModalities, items: &items)
    }

    public static func stripUnsupportedMediaContent(
        inputModalities: [InputModality],
        items: inout [ResponseItem]
    ) {
        let supportsImages = inputModalities.contains(.image)
        let supportsAudio = inputModalities.contains(.audio)
        guard !supportsImages || !supportsAudio else {
            return
        }

        items = items.map { item in
            switch item {
            case let .message(id, role, content, phase):
                return .message(
                    id: id,
                    role: role,
                    content: content.map { Self.strippingMediaContent($0, supportsImages: supportsImages) },
                    phase: phase
                )

            case let .functionCallOutput(callID, output):
                return .functionCallOutput(
                    callID: callID,
                    output: Self.strippingMediaOutput(
                        from: output,
                        supportsImages: supportsImages,
                        supportsAudio: supportsAudio
                    )
                )

            case let .customToolCallOutput(callID, name, output):
                return .customToolCallOutput(
                    callID: callID,
                    name: name,
                    output: Self.strippingMediaOutput(
                        from: output,
                        supportsImages: supportsImages,
                        supportsAudio: supportsAudio
                    )
                )

            case let .imageGenerationCall(id, status, revisedPrompt, _) where !supportsImages:
                return .imageGenerationCall(
                    id: id,
                    status: status,
                    revisedPrompt: revisedPrompt,
                    result: ""
                )

            case .reasoning,
                 .localShellCall,
             .functionCall,
             .toolSearchCall,
             .customToolCall,
             .toolSearchOutput,
             .webSearchCall,
             .imageGenerationCall,
             .ghostSnapshot,
             .compaction,
             .contextCompaction,
                 .knownPersisted,
                 .other:
                return item
            }
        }
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

    private static func strippingMediaContent(_ item: ContentItem, supportsImages: Bool) -> ContentItem {
        switch item {
        case .inputImage where !supportsImages:
            return .inputText(text: imageContentOmittedPlaceholder)
        case .inputText,
             .inputImage,
             .outputText:
            return item
        }
    }

    private static func strippingMediaOutput(
        from output: FunctionCallOutputPayload,
        supportsImages: Bool,
        supportsAudio: Bool
    ) -> FunctionCallOutputPayload {
        guard let contentItems = output.contentItems else {
            return output
        }
        return FunctionCallOutputPayload(
            content: output.content,
            contentItems: contentItems.map {
                Self.strippingMediaOutputContent(
                    $0,
                    supportsImages: supportsImages,
                    supportsAudio: supportsAudio
                )
            },
            success: output.success
        )
    }

    private static func strippingMediaOutputContent(
        _ item: FunctionCallOutputContentItem,
        supportsImages: Bool,
        supportsAudio: Bool
    ) -> FunctionCallOutputContentItem {
        switch item {
        case .inputImage where !supportsImages:
            return .inputText(text: imageContentOmittedPlaceholder)
        case .inputAudio where !supportsAudio:
            return .inputText(text: audioContentOmittedPlaceholder)
        case .inputText,
             .inputImage,
             .inputAudio:
            return item
        }
    }
}
