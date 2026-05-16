import Foundation

public let codeModePragmaPrefix = "// @exec:"

public struct ParsedExecSource: Equatable, Sendable {
    public let code: String
    public let yieldTimeMS: Int?
    public let maxOutputTokens: Int?

    public init(code: String, yieldTimeMS: Int? = nil, maxOutputTokens: Int? = nil) {
        self.code = code
        self.yieldTimeMS = yieldTimeMS
        self.maxOutputTokens = maxOutputTokens
    }
}

public struct CodeModeParseError: Error, Equatable, CustomStringConvertible, Sendable {
    public let description: String

    public init(_ description: String) {
        self.description = description
    }
}

public enum CodeMode {
    private static let maxJSSafeInteger = 9_007_199_254_740_991

    public static func parseExecSource(_ input: String) -> Result<ParsedExecSource, CodeModeParseError> {
        if input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .failure(CodeModeParseError("exec expects raw JavaScript source text (non-empty). Provide JS only, optionally with first-line `// @exec: {\"yield_time_ms\": 10000, \"max_output_tokens\": 1000}`."))
        }

        var parsed = ParsedExecSource(code: input)
        let split = input.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        let firstLine = split.first.map(String.init) ?? ""
        let rest = split.count > 1 ? String(split[1]) : ""
        let trimmedFirstLine = firstLine.trimmingCharacters(in: .whitespaces)
        guard trimmedFirstLine.hasPrefix(codeModePragmaPrefix) else {
            return .success(parsed)
        }

        if rest.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .failure(CodeModeParseError("exec pragma must be followed by JavaScript source on subsequent lines"))
        }

        let directive = String(trimmedFirstLine.dropFirst(codeModePragmaPrefix.count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if directive.isEmpty {
            return .failure(CodeModeParseError("exec pragma must be a JSON object with supported fields `yield_time_ms` and `max_output_tokens`"))
        }

        let value: Any
        do {
            value = try JSONSerialization.jsonObject(with: Data(directive.utf8), options: [])
        } catch {
            return .failure(CodeModeParseError("exec pragma must be valid JSON with supported fields `yield_time_ms` and `max_output_tokens`: \(error.localizedDescription)"))
        }
        guard let object = value as? [String: Any] else {
            return .failure(CodeModeParseError("exec pragma must be a JSON object with supported fields `yield_time_ms` and `max_output_tokens`"))
        }

        for key in object.keys.sorted() {
            if key != "yield_time_ms" && key != "max_output_tokens" {
                return .failure(CodeModeParseError("exec pragma only supports `yield_time_ms` and `max_output_tokens`; got `\(key)`"))
            }
        }

        let yieldTimeMS: Int?
        if let value = object["yield_time_ms"] {
            guard let parsedValue = safeInteger(value) else {
                return .failure(CodeModeParseError("exec pragma field `yield_time_ms` must be a non-negative safe integer"))
            }
            yieldTimeMS = parsedValue
        } else {
            yieldTimeMS = nil
        }
        let maxOutputTokens: Int?
        if let value = object["max_output_tokens"] {
            guard let parsedValue = safeInteger(value) else {
                return .failure(CodeModeParseError("exec pragma field `max_output_tokens` must be a non-negative safe integer"))
            }
            maxOutputTokens = parsedValue
        } else {
            maxOutputTokens = nil
        }

        if let yieldTimeMS, yieldTimeMS > maxJSSafeInteger {
            return .failure(CodeModeParseError("exec pragma field `yield_time_ms` must be a non-negative safe integer"))
        }
        if let maxOutputTokens, maxOutputTokens > maxJSSafeInteger {
            return .failure(CodeModeParseError("exec pragma field `max_output_tokens` must be a non-negative safe integer"))
        }

        parsed = ParsedExecSource(code: rest, yieldTimeMS: yieldTimeMS, maxOutputTokens: maxOutputTokens)
        return .success(parsed)
    }

    public static func isCodeModeNestedTool(_ toolName: String) -> Bool {
        toolName != "exec" && toolName != "wait"
    }

    public static func normalizeCodeModeIdentifier(_ toolKey: String) -> String {
        var identifier = ""
        for (index, character) in toolKey.enumerated() {
            let isValid: Bool
            if index == 0 {
                isValid = character == "_" || character == "$" || character.isASCIIAlphabetic
            } else {
                isValid = character == "_" || character == "$" || character.isASCIIAlphaNumeric
            }
            identifier.append(isValid ? character : "_")
        }
        return identifier.isEmpty ? "_" : identifier
    }

    public static func responseInputToCodeModeResult(_ response: ResponseInputItem) -> JSONValue {
        switch response {
        case let .message(_, content, _):
            return contentItemsToCodeModeResult(content.map(functionOutputContentItem))
        case let .functionCallOutput(_, output),
             let .customToolCallOutput(_, _, output):
            if let contentItems = output.contentItems {
                return contentItemsToCodeModeResult(contentItems)
            }
            return .string(output.content)
        case let .toolSearchOutput(_, _, _, tools):
            return .array(tools)
        case let .mcpToolCallOutput(_, output):
            return encodeToJSONValue(output)
                ?? .string("failed to serialize mcp result")
        }
    }

    private static func safeInteger(_ value: Any) -> Int? {
        if value is NSNull {
            return nil
        }
        guard let number = value as? NSNumber else {
            return nil
        }
        if CFGetTypeID(number) == CFBooleanGetTypeID() {
            return nil
        }
        let doubleValue = number.doubleValue
        guard doubleValue.isFinite,
              doubleValue.rounded(.towardZero) == doubleValue,
              doubleValue >= 0,
              doubleValue <= Double(maxJSSafeInteger)
        else {
            return nil
        }
        return Int(doubleValue)
    }

    private static func functionOutputContentItem(_ item: ContentItem) -> FunctionCallOutputContentItem {
        switch item {
        case let .inputText(text),
             let .outputText(text):
            return .inputText(text: text)
        case let .inputImage(imageURL, detail):
            return .inputImage(imageURL: imageURL, detail: detail ?? defaultImageDetail)
        }
    }

    private static func contentItemsToCodeModeResult(_ items: [FunctionCallOutputContentItem]) -> JSONValue {
        let text = items.compactMap { item -> String? in
            switch item {
            case let .inputText(text):
                return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text
            case let .inputImage(imageURL, _):
                return imageURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : imageURL
            }
        }.joined(separator: "\n")
        return .string(text)
    }

    private static func encodeToJSONValue<T: Encodable>(_ value: T) -> JSONValue? {
        guard let data = try? JSONEncoder().encode(value) else {
            return nil
        }
        return try? JSONDecoder().decode(JSONValue.self, from: data)
    }
}

private extension Character {
    var isASCIIAlphabetic: Bool {
        guard let scalar = unicodeScalars.first, unicodeScalars.count == 1 else {
            return false
        }
        return (65...90).contains(Int(scalar.value)) || (97...122).contains(Int(scalar.value))
    }

    var isASCIIAlphaNumeric: Bool {
        guard let scalar = unicodeScalars.first, unicodeScalars.count == 1 else {
            return false
        }
        return isASCIIAlphabetic || (48...57).contains(Int(scalar.value))
    }
}
