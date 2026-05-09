import Foundation

public struct HookPromptFragment: Equatable, Sendable {
    public var text: String
    public var hookRunID: String

    public init(text: String, hookRunID: String) {
        self.text = text
        self.hookRunID = hookRunID
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
