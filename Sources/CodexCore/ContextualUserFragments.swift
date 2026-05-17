import Foundation

enum ContextualUserFragments {
    static let turnAbortedOpenTag = "<turn_aborted>"
    static let turnAbortedCloseTag = "</turn_aborted>"
    static let subagentNotificationOpenTag = "<subagent_notification>"
    static let subagentNotificationCloseTag = "</subagent_notification>"

    static func isStandardText(_ text: String) -> Bool {
        UserInstructions.matchesText(text)
            || EnvironmentContext.matchesText(text)
            || SkillInstructions.matchesText(text)
            || UserShellCommand.isUserShellCommandText(text)
            || matchesTurnAborted(text)
            || matchesSubagentNotification(text)
            || matchesLegacyUnifiedExecProcessLimitWarning(text)
            || matchesLegacyApplyPatchExecCommandWarning(text)
            || matchesLegacyModelMismatchWarning(text)
    }

    static func matchesTurnAborted(_ text: String) -> Bool {
        contextualFragmentMatches(
            text,
            startMarker: turnAbortedOpenTag,
            endMarker: turnAbortedCloseTag
        )
    }

    static func matchesSubagentNotification(_ text: String) -> Bool {
        contextualFragmentMatches(
            text,
            startMarker: subagentNotificationOpenTag,
            endMarker: subagentNotificationCloseTag
        )
    }

    static func matchesLegacyUnifiedExecProcessLimitWarning(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .hasPrefix("Warning: The maximum number of unified exec processes you can keep open is")
    }

    static func matchesLegacyApplyPatchExecCommandWarning(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("Warning: apply_patch was requested via ")
            && trimmed.hasSuffix("Use the apply_patch tool instead of exec_command.")
    }

    static func matchesLegacyModelMismatchWarning(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .hasPrefix("Warning: Your account was flagged for potentially high-risk cyber activity")
    }
}
