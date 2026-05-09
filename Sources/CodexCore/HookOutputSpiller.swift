import Foundation

public struct HookPromptFragment: Equatable, Codable, Sendable {
    public var text: String
    public var hookRunID: String

    private enum CodingKeys: String, CodingKey {
        case text
        case hookRunID = "hookRunId"
    }

    public init(text: String, hookRunID: String) {
        self.text = text
        self.hookRunID = hookRunID
    }

    public static func fromSingleHook(text: String, hookRunID: String) -> Self {
        Self(text: text, hookRunID: hookRunID)
    }

    public static func parseXML(_ text: String) -> Self? {
        HookPromptXML.parse(text)
    }

    public func serializedXML() -> String? {
        HookPromptXML.serialize(text: text, hookRunID: hookRunID)
    }
}

public enum HookPromptXML {
    public static func parse(_ text: String) -> HookPromptFragment? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("<hook_prompt"),
              trimmed.hasSuffix("</hook_prompt>"),
              let openingClose = trimmed.firstIndex(of: ">")
        else {
            return nil
        }

        let openingTag = String(trimmed[..<openingClose])
        guard let hookRunID = attributeValue(named: "hook_run_id", in: openingTag),
              !hookRunID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return nil
        }

        let bodyStart = trimmed.index(after: openingClose)
        let closingStart = trimmed.index(trimmed.endIndex, offsetBy: -"</hook_prompt>".count)
        guard bodyStart <= closingStart else {
            return nil
        }

        let body = String(trimmed[bodyStart..<closingStart])
        return HookPromptFragment(
            text: unescapeXML(body),
            hookRunID: unescapeXML(hookRunID)
        )
    }

    public static func serialize(text: String, hookRunID: String) -> String? {
        guard !hookRunID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        return #"<hook_prompt hook_run_id="\#(escapeXML(hookRunID))">\#(escapeXML(text))</hook_prompt>"#
    }

    private static func attributeValue(named name: String, in tag: String) -> String? {
        let pattern = #"(?<![\w:-])\#(NSRegularExpression.escapedPattern(for: name))\s*=\s*"([^"]*)""#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }
        let range = NSRange(tag.startIndex..<tag.endIndex, in: tag)
        guard let match = regex.firstMatch(in: tag, range: range),
              match.numberOfRanges == 2,
              let valueRange = Range(match.range(at: 1), in: tag)
        else {
            return nil
        }
        return String(tag[valueRange])
    }

    private static func escapeXML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func unescapeXML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
    }
}

public struct HookOutputSpiller: Sendable {
    public static let outputsDirectoryName = "hook_outputs"
    public static let outputTokenLimit = 2_500

    public var outputDirectory: URL

    public init(outputDirectory: URL = FileManager.default.temporaryDirectory.appendingPathComponent(outputsDirectoryName, isDirectory: true)) {
        self.outputDirectory = outputDirectory
    }

    public func maybeSpillText(threadID: ThreadId, text: String) -> String {
        if Truncation.approxTokenCount(text) <= Self.outputTokenLimit {
            return text
        }

        let path = hookOutputPath(threadID: threadID)
        do {
            try FileManager.default.createDirectory(
                at: path.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try text.write(to: path, atomically: true, encoding: .utf8)
            return Self.spilledHookOutputPreview(text: text, path: path)
        } catch {
            return Truncation.formattedTruncateText(text, policy: .tokens(Self.outputTokenLimit))
        }
    }

    public func maybeSpillTexts(threadID: ThreadId, texts: [String]) -> [String] {
        texts.map { maybeSpillText(threadID: threadID, text: $0) }
    }

    public func maybeSpillPromptFragments(
        threadID: ThreadId,
        fragments: [HookPromptFragment]
    ) -> [HookPromptFragment] {
        fragments.map { fragment in
            HookPromptFragment(
                text: maybeSpillText(threadID: threadID, text: fragment.text),
                hookRunID: fragment.hookRunID
            )
        }
    }

    private func hookOutputPath(threadID: ThreadId) -> URL {
        outputDirectory
            .appendingPathComponent(threadID.description, isDirectory: true)
            .appendingPathComponent("\(UUID().uuidString.lowercased()).txt", isDirectory: false)
    }

    private static func spilledHookOutputPreview(text: String, path: URL) -> String {
        let footer = "\n\nFull hook output saved to: \(path.path)"
        let budget = max(0, outputTokenLimit - Truncation.approxTokenCount(footer))
        return Truncation.formattedTruncateText(text, policy: .tokens(budget)) + footer
    }
}
