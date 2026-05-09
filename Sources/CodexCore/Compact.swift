import Foundation

public enum Compact {
    public static let compactUserMessageMaxTokens = 20_000

    public static let summarizationPrompt: String = {
        loadResource("compact_prompt", subdirectory: "Compact")
    }()

    public static let summaryPrefix: String = {
        loadResource("compact_summary_prefix", subdirectory: "Compact")
    }()

    public static func contentItemsToText(_ content: [ContentItem]) -> String? {
        let pieces = content.compactMap { item -> String? in
            switch item {
            case let .inputText(text), let .outputText(text):
                return text.isEmpty ? nil : text
            case .inputImage:
                return nil
            }
        }
        return pieces.isEmpty ? nil : pieces.joined(separator: "\n")
    }

    public static func collectUserMessages(_ items: [ResponseItem]) -> [String] {
        items.compactMap { item in
            guard case let .message(_, role, content, _) = item, role == "user" else {
                return nil
            }
            guard shouldKeepUserMessage(content) else {
                return nil
            }
            return contentItemsToText(content) ?? ""
        }.filter { !isSummaryMessage($0) }
    }

    public static func isSummaryMessage(_ message: String) -> Bool {
        message.hasPrefix("\(summaryPrefix)\n")
    }

    public static func buildCompactedHistory(
        initialContext: [ResponseItem],
        userMessages: [String],
        summaryText: String
    ) -> [ResponseItem] {
        buildCompactedHistory(
            initialContext: initialContext,
            userMessages: userMessages,
            summaryText: summaryText,
            maxTokens: compactUserMessageMaxTokens
        )
    }

    public static func buildCompactedHistory(
        initialContext: [ResponseItem],
        userMessages: [String],
        summaryText: String,
        maxTokens: Int
    ) -> [ResponseItem] {
        var history = initialContext
        var selectedMessages: [String] = []

        if maxTokens > 0 {
            var remaining = maxTokens
            for message in userMessages.reversed() {
                if remaining == 0 {
                    break
                }

                let tokens = Truncation.approxTokenCount(message)
                if tokens <= remaining {
                    selectedMessages.append(message)
                    remaining = max(0, remaining - tokens)
                } else {
                    selectedMessages.append(Truncation.truncateText(message, policy: .tokens(remaining)))
                    break
                }
            }
            selectedMessages.reverse()
        }

        for message in selectedMessages {
            history.append(.message(role: "user", content: [.inputText(text: message)]))
        }

        let finalSummary = summaryText.isEmpty ? "(no summary available)" : summaryText
        history.append(.message(role: "user", content: [.inputText(text: finalSummary)]))
        return history
    }

    public static func insertInitialContextBeforeLastRealUserOrSummary(
        compactedHistory: [ResponseItem],
        initialContext: [ResponseItem]
    ) -> [ResponseItem] {
        var lastUserOrSummaryIndex: Int?
        var lastRealUserIndex: Int?

        for index in compactedHistory.indices.reversed() {
            guard case let .message(_, role, content, _) = compactedHistory[index],
                  role == "user"
            else {
                continue
            }

            lastUserOrSummaryIndex = lastUserOrSummaryIndex ?? index
            let message = contentItemsToText(content) ?? ""
            if !isSummaryMessage(message) {
                lastRealUserIndex = index
                break
            }
        }

        let lastCompactionIndex = compactedHistory.indices.reversed().first { index in
            if case .compaction = compactedHistory[index] {
                return true
            }
            if case .contextCompaction = compactedHistory[index] {
                return true
            }
            return false
        }

        let insertionIndex = lastRealUserIndex ?? lastUserOrSummaryIndex ?? lastCompactionIndex
        var history = compactedHistory
        if let insertionIndex {
            history.insert(contentsOf: initialContext, at: insertionIndex)
        } else {
            history.append(contentsOf: initialContext)
        }
        return history
    }

    private static func shouldKeepUserMessage(_ content: [ContentItem]) -> Bool {
        if UserInstructions.isUserInstructions(message: content)
            || SkillInstructions.isSkillInstructions(message: content)
        {
            return false
        }

        for item in content {
            switch item {
            case let .inputText(text), let .outputText(text):
                if isSessionPrefix(text) || UserShellCommand.isUserShellCommandText(text) {
                    return false
                }
            case .inputImage:
                continue
            }
        }

        return true
    }

    private static func isSessionPrefix(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .hasPrefix("<environment_context>")
    }

    private static func loadResource(_ name: String, subdirectory: String) -> String {
        let url = Bundle.module.url(forResource: name, withExtension: "md", subdirectory: subdirectory)
            ?? Bundle.module.url(forResource: name, withExtension: "md")
        guard let url else {
            preconditionFailure("Missing bundled compact resource \(subdirectory)/\(name).md")
        }

        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            preconditionFailure("Unable to load compact resource \(subdirectory)/\(name).md: \(error)")
        }
    }
}
