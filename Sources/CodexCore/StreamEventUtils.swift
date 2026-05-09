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
        sessionID: String? = nil
    ) -> TurnItem? {
        switch item {
        case .message,
             .reasoning,
             .webSearchCall,
             .imageGenerationCall:
            guard var turnItem = EventMapping.parseTurnItem(item) else {
                return nil
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
        guard case let .message(_, role, content, _) = item,
              role == "assistant"
        else {
            return nil
        }

        return content.reversed().compactMap { item -> String? in
            if case let .outputText(text) = item {
                return text
            }
            return nil
        }.first
    }

    public static func responseInputToResponseItem(_ input: ResponseInputItem) -> ResponseItem? {
        switch input {
        case let .functionCallOutput(callID, output):
            return .functionCallOutput(callID: callID, output: output)
        case let .customToolCallOutput(callID, output):
            return .customToolCallOutput(callID: callID, output: output)
        case let .toolSearchOutput(callID, status, execution, tools):
            return .toolSearchOutput(callID: callID, status: status, execution: execution, tools: tools)
        case let .mcpToolCallOutput(callID, result):
            let output: FunctionCallOutputPayload
            switch result {
            case let .ok(callToolResult):
                output = FunctionCallOutputPayload(callToolResult: callToolResult)
            case let .err(error):
                output = FunctionCallOutputPayload(content: error, success: false)
            }
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
}

public extension ResponseInputItem {
    func responseItem() -> ResponseItem {
        switch self {
        case let .message(role, content, phase):
            return .message(role: role, content: content, phase: phase)
        case let .functionCallOutput(callID, output):
            return .functionCallOutput(callID: callID, output: output)
        case let .customToolCallOutput(callID, output):
            return .customToolCallOutput(callID: callID, output: output)
        case let .toolSearchOutput(callID, status, execution, tools):
            return .toolSearchOutput(callID: callID, status: status, execution: execution, tools: tools)
        case let .mcpToolCallOutput(callID, result):
            let output: FunctionCallOutputPayload
            switch result {
            case let .ok(callToolResult):
                output = FunctionCallOutputPayload(callToolResult: callToolResult)
            case let .err(error):
                output = FunctionCallOutputPayload(content: "err: \(String(reflecting: error))", success: false)
            }
            return .functionCallOutput(callID: callID, output: output)
        }
    }
}
