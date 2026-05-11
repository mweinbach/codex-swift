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

    public static func handleNonToolResponseItem(
        _ item: ResponseItem,
        codexHome: URL? = nil,
        sessionID: String? = nil,
        planMode: Bool = false
    ) -> TurnItem? {
        switch item {
        case .message,
             .reasoning,
             .webSearchCall,
             .imageGenerationCall:
            guard var turnItem = EventMapping.parseTurnItem(item) else {
                return nil
            }
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
                    memoryCitation: memoryCitation
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
            }
            return turnItem
        case .functionCallOutput,
             .customToolCallOutput,
             .toolSearchCall,
             .toolSearchOutput,
             .localShellCall,
             .functionCall,
             .customToolCall,
             .ghostSnapshot,
             .compaction,
             .contextCompaction,
             .knownPersisted,
             .other:
            return nil
        }
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

    public static func responseInputToResponseItem(_ input: ResponseInputItem) -> ResponseItem? {
        switch input {
        case let .functionCallOutput(callID, output):
            return .functionCallOutput(callID: callID, output: output)
        case let .customToolCallOutput(callID, name, output):
            return .customToolCallOutput(callID: callID, name: name, output: output)
        case let .toolSearchOutput(callID, status, execution, tools):
            return .toolSearchOutput(callID: callID, status: status, execution: execution, tools: tools)
        case let .mcpToolCallOutput(callID, result):
            let output = FunctionCallOutputPayload(callToolResult: result)
            return .functionCallOutput(callID: callID, output: output)
        case .message:
            return nil
        }
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
            let output = FunctionCallOutputPayload(callToolResult: result)
            return .functionCallOutput(callID: callID, output: output)
        }
    }
}
