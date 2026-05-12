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
}
