import Foundation

public enum ImageGenerationArtifactError: Error, Equatable, CustomStringConvertible, Sendable {
    case invalidPayload

    public var description: String {
        switch self {
        case .invalidPayload:
            return "invalid image generation payload"
        }
    }
}

public enum StreamEventUtils {
    private static let generatedImageArtifactsDirectory = "generated_images"

    /// Mutates a parsed turn item before Swift derives visible assistant text,
    /// memory-citation metadata, and final-message facts.
    ///
    /// Extension runtimes implement this protocol to attach or rewrite
    /// metadata for non-tool response items. Callers may rely on contributors
    /// running before hidden assistant markup is stripped; if a contributor
    /// sets an agent message memory citation, Swift preserves that value rather
    /// than replacing it with the fallback citation parser result.
    public protocol TurnItemContributor: Sendable {
        func contribute(to item: inout TurnItem)
    }

    public struct HandledNonToolResponseItem: Equatable, Sendable {
        public let turnItem: TurnItem
        public let supplementalHistoryItems: [ResponseItem]

        public init(turnItem: TurnItem, supplementalHistoryItems: [ResponseItem] = []) {
            self.turnItem = turnItem
            self.supplementalHistoryItems = supplementalHistoryItems
        }
    }

    public static func handleNonToolResponseItem(
        _ item: ResponseItem,
        codexHome: URL? = nil,
        sessionID: String? = nil,
        planMode: Bool = false,
        contributors: [any TurnItemContributor] = []
    ) -> TurnItem? {
        handleNonToolResponseItemWithSupplementalHistory(
            item,
            codexHome: codexHome,
            sessionID: sessionID,
            planMode: planMode,
            contributors: contributors
        )?.turnItem
    }

    public static func handleNonToolResponseItemWithSupplementalHistory(
        _ item: ResponseItem,
        codexHome: URL? = nil,
        sessionID: String? = nil,
        planMode: Bool = false,
        contributors: [any TurnItemContributor] = []
    ) -> HandledNonToolResponseItem? {
        switch item {
        case .message,
             .reasoning,
             .webSearchCall,
             .imageGenerationCall:
            guard var turnItem = EventMapping.parseTurnItem(item) else {
                return nil
            }
            applyTurnItemContributors(contributors, to: &turnItem)
            if case let .agentMessage(agentMessage) = turnItem {
                let combined = agentMessage.content.map { content in
                    switch content {
                    case let .text(text):
                        return text
                    }
                }.joined()
                let (visibleText, memoryCitation) = stripHiddenAssistantMarkupAndParseMemoryCitation(
                    combined,
                    planMode: planMode
                )
                turnItem = .agentMessage(AgentMessageItem(
                    id: agentMessage.id,
                    content: [.text(visibleText)],
                    phase: agentMessage.phase,
                    memoryCitation: agentMessage.memoryCitation ?? memoryCitation
                ))
            }
            if case let .imageGeneration(imageItem) = turnItem,
               let codexHome,
               let sessionID,
               let savedPath = try? saveImageGenerationResult(
                   codexHome: codexHome,
                   sessionID: sessionID,
                   callID: imageItem.id,
                   result: imageItem.result
               )
            {
                turnItem = .imageGeneration(ImageGenerationItem(
                    id: imageItem.id,
                    status: imageItem.status,
                    revisedPrompt: imageItem.revisedPrompt,
                    result: imageItem.result,
                    savedPath: savedPath
                ))
                return HandledNonToolResponseItem(
                    turnItem: turnItem,
                    supplementalHistoryItems: [imageGenerationInstructionsItem(codexHome: codexHome, sessionID: sessionID)]
                )
            }
            return HandledNonToolResponseItem(turnItem: turnItem)
        case .functionCallOutput,
             .customToolCallOutput,
             .toolSearchCall,
             .toolSearchOutput,
             .localShellCall,
             .functionCall,
             .customToolCall,
             .ghostSnapshot,
             .compaction,
             .compactionTrigger,
             .contextCompaction,
             .knownPersisted,
             .other:
            return nil
        }
    }

    private static func applyTurnItemContributors(
        _ contributors: [any TurnItemContributor],
        to turnItem: inout TurnItem
    ) {
        for contributor in contributors {
            contributor.contribute(to: &turnItem)
        }
    }

    public static func imageGenerationInstructionsItem(codexHome: URL, sessionID: String) -> ResponseItem {
        let imageOutputPath = try? imageGenerationArtifactPath(
            codexHome: codexHome,
            sessionID: sessionID,
            callID: "<image_id>"
        )
        let outputPath = imageOutputPath?.path ?? codexHome.standardizedFileURL.path
        let imageOutputDirectory = URL(fileURLWithPath: outputPath, isDirectory: false)
            .deletingLastPathComponent()
            .path
        return ImageGenerationInstructions(
            imageOutputDirectory: imageOutputDirectory,
            imageOutputPath: outputPath
        ).asResponseItem()
    }

    public static func lastAssistantMessage(from item: ResponseItem) -> String? {
        lastAssistantMessage(from: item, planMode: false)
    }

    public static func lastAssistantMessage(from item: ResponseItem, planMode: Bool) -> String? {
        guard case let .message(_, role, content, _) = item,
              role == "assistant"
        else {
            return nil
        }

        let combined = content.compactMap { item -> String? in
            guard case let .outputText(text) = item else {
                return nil
            }
            return text
        }.joined()
        guard !combined.isEmpty else {
            return nil
        }

        let stripped = stripHiddenAssistantMarkup(combined, planMode: planMode)
        guard !stripped.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return stripped
    }

    public static func responseInputToResponseItem(_ input: ResponseInputItem) -> ResponseItem {
        responseInputToResponseItem(input, supportsImageInput: true)
    }

    public static func responseInputToResponseItem(
        _ input: ResponseInputItem,
        supportsImageInput: Bool
    ) -> ResponseItem {
        input.responseItem(supportsImageInput: supportsImageInput)
    }

    public static func imageGenerationArtifactPath(
        codexHome: URL,
        sessionID: String,
        callID: String
    ) throws -> AbsolutePath {
        let path = codexHome
            .appendingPathComponent(generatedImageArtifactsDirectory, isDirectory: true)
            .appendingPathComponent(sanitizeImageArtifactComponent(sessionID), isDirectory: true)
            .appendingPathComponent("\(sanitizeImageArtifactComponent(callID)).png", isDirectory: false)
        return try AbsolutePath(absolutePath: path.standardizedFileURL.path)
    }

    @discardableResult
    public static func saveImageGenerationResult(
        codexHome: URL,
        sessionID: String,
        callID: String,
        result: String,
        fileManager: FileManager = .default
    ) throws -> AbsolutePath {
        let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = Data(base64Encoded: trimmed, options: []) else {
            throw ImageGenerationArtifactError.invalidPayload
        }

        let path = try imageGenerationArtifactPath(codexHome: codexHome, sessionID: sessionID, callID: callID)
        let url = URL(fileURLWithPath: path.path, isDirectory: false)
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url)
        return path
    }

    private static func sanitizeImageArtifactComponent(_ value: String) -> String {
        let sanitized = String(value.map { character in
            if character.isASCII,
               character.isLetter || character.isNumber || character == "-" || character == "_"
            {
                return character
            }
            return "_"
        })
        return sanitized.isEmpty ? "generated_image" : sanitized
    }

    private static func stripHiddenAssistantMarkup(_ text: String, planMode: Bool) -> String {
        let (withoutCitations, _) = stripAssistantCitations(text)
        guard planMode else {
            return withoutCitations
        }
        return stripProposedPlanBlocks(withoutCitations)
    }

    private static func stripHiddenAssistantMarkupAndParseMemoryCitation(
        _ text: String,
        planMode: Bool
    ) -> (String, MemoryCitation?) {
        let (withoutCitations, citations) = stripAssistantCitations(text)
        let visibleText: String
        if planMode {
            visibleText = stripProposedPlanBlocks(withoutCitations)
        } else {
            visibleText = withoutCitations
        }
        return (visibleText, parseMemoryCitation(citations))
    }

    private static func parseMemoryCitation(_ citations: [String]) -> MemoryCitation? {
        var entries: [MemoryCitationEntry] = []
        var rolloutIDs: [String] = []
        var seenRolloutIDs: Set<String> = []

        for citation in citations {
            if let entriesBlock = extractBlock(
                citation,
                openTag: "<citation_entries>",
                closeTag: "</citation_entries>"
            ) {
                entries.append(contentsOf: entriesBlock
                    .split(whereSeparator: \.isNewline)
                    .compactMap { parseMemoryCitationEntry(String($0)) })
            }

            let idsBlock = extractBlock(
                citation,
                openTag: "<rollout_ids>",
                closeTag: "</rollout_ids>"
            ) ?? extractBlock(
                citation,
                openTag: "<thread_ids>",
                closeTag: "</thread_ids>"
            )
            if let idsBlock {
                for id in idsBlock.split(whereSeparator: \.isNewline).map({ String($0).trimmingCharacters(in: .whitespacesAndNewlines) })
                    where !id.isEmpty && seenRolloutIDs.insert(id).inserted
                {
                    rolloutIDs.append(id)
                }
            }
        }

        guard !entries.isEmpty || !rolloutIDs.isEmpty else {
            return nil
        }
        return MemoryCitation(entries: entries, rolloutIDs: rolloutIDs)
    }

    private static func parseMemoryCitationEntry(_ line: String) -> MemoryCitationEntry? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let noteRange = trimmed.range(of: "|note=[", options: .backwards),
              trimmed.hasSuffix("]")
        else {
            return nil
        }

        let location = String(trimmed[..<noteRange.lowerBound])
        let noteStart = noteRange.upperBound
        let noteEnd = trimmed.index(before: trimmed.endIndex)
        let note = String(trimmed[noteStart ..< noteEnd]).trimmingCharacters(in: .whitespacesAndNewlines)

        guard let pathRange = location.range(of: ":", options: .backwards),
              let lineRangeSeparator = location[pathRange.upperBound...].firstIndex(of: "-")
        else {
            return nil
        }

        let path = String(location[..<pathRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        let lineStartText = String(location[pathRange.upperBound ..< lineRangeSeparator])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let lineEndText = String(location[location.index(after: lineRangeSeparator)...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let lineStart = UInt32(lineStartText),
              let lineEnd = UInt32(lineEndText)
        else {
            return nil
        }

        return MemoryCitationEntry(path: path, lineStart: lineStart, lineEnd: lineEnd, note: note)
    }

    private static func extractBlock(_ text: String, openTag: String, closeTag: String) -> String? {
        guard let openRange = text.range(of: openTag),
              let closeRange = text.range(of: closeTag, range: openRange.upperBound ..< text.endIndex)
        else {
            return nil
        }
        return String(text[openRange.upperBound ..< closeRange.lowerBound])
    }
}

public extension ResponseInputItem {
    func responseItem() -> ResponseItem {
        responseItem(supportsImageInput: true)
    }

    func responseItem(supportsImageInput: Bool) -> ResponseItem {
        switch self {
        case let .message(role, content, phase):
            return .message(role: role, content: content, phase: phase)
        case let .functionCallOutput(callID, output):
            return .functionCallOutput(callID: callID, output: output)
        case let .customToolCallOutput(callID, name, output):
            return .customToolCallOutput(callID: callID, name: name, output: output)
        case let .toolSearchOutput(callID, status, execution, tools):
            return .toolSearchOutput(callID: callID, status: status, execution: execution, tools: tools)
        case let .mcpToolCallOutput(callID, result):
            let output = FunctionCallOutputPayload(
                callToolResult: result,
                supportsImageInput: supportsImageInput
            )
            return .functionCallOutput(callID: callID, output: output)
        }
    }
}
