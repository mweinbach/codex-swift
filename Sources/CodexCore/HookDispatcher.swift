import Foundation

public struct ConfiguredHookHandler: Equatable, Sendable {
    public var eventName: HookEventName
    public var matcher: String?
    public var command: String
    public var timeoutSec: UInt64
    public var statusMessage: String?
    public var sourcePath: AbsolutePath
    public var source: HookSource
    public var displayOrder: Int64
    public var environment: [String: String]

    public init(
        eventName: HookEventName,
        matcher: String?,
        command: String,
        timeoutSec: UInt64,
        statusMessage: String? = nil,
        sourcePath: AbsolutePath,
        source: HookSource = .user,
        displayOrder: Int64,
        environment: [String: String] = [:]
    ) {
        self.eventName = eventName
        self.matcher = matcher
        self.command = command
        self.timeoutSec = timeoutSec
        self.statusMessage = statusMessage
        self.sourcePath = sourcePath
        self.source = source
        self.displayOrder = displayOrder
        self.environment = environment
    }

    public var runID: String {
        "\(eventName.hookRunLabel):\(displayOrder):\(sourcePath.path)"
    }
}

public struct HookCommandRunResult: Equatable, Sendable {
    public var startedAt: Int64
    public var completedAt: Int64
    public var durationMs: Int64

    public init(startedAt: Int64, completedAt: Int64, durationMs: Int64) {
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.durationMs = durationMs
    }
}

public enum HookDispatcher {
    public static func matcherPattern(for eventName: HookEventName, matcher: String?) -> String? {
        switch eventName {
        case .preToolUse, .permissionRequest, .postToolUse, .preCompact, .postCompact, .sessionStart:
            return matcher
        case .userPromptSubmit, .stop:
            return nil
        }
    }

    public static func validateMatcherPattern(_ matcher: String) -> Bool {
        if isMatchAllMatcher(matcher) || isExactMatcher(matcher) {
            return true
        }
        return (try? NSRegularExpression(pattern: matcher)) != nil
    }

    public static func matchesMatcher(_ matcher: String?, input: String?) -> Bool {
        guard let matcher else {
            return true
        }
        if isMatchAllMatcher(matcher) {
            return true
        }
        guard let input else {
            return false
        }
        if isExactMatcher(matcher) {
            return matcher.split(separator: "|").contains { $0 == input }
        }
        guard let regex = try? NSRegularExpression(pattern: matcher) else {
            return false
        }
        let range = NSRange(input.startIndex..<input.endIndex, in: input)
        return regex.firstMatch(in: input, range: range) != nil
    }

    public static func matcherInputs(toolName: String, matcherAliases: [String]) -> [String] {
        [toolName] + matcherAliases
    }

    public static func selectHandlers(
        _ handlers: [ConfiguredHookHandler],
        eventName: HookEventName,
        matcherInput: String?
    ) -> [ConfiguredHookHandler] {
        selectHandlers(handlers, eventName: eventName, matcherInputs: matcherInput.map { [$0] } ?? [])
    }

    public static func selectHandlers(
        _ handlers: [ConfiguredHookHandler],
        eventName: HookEventName,
        matcherInputs: [String]
    ) -> [ConfiguredHookHandler] {
        handlers.filter { handler in
            guard handler.eventName == eventName else {
                return false
            }

            switch eventName {
            case .preToolUse, .permissionRequest, .postToolUse, .preCompact, .postCompact, .sessionStart:
                if matcherInputs.isEmpty {
                    return matchesMatcher(handler.matcher, input: nil)
                }
                return matcherInputs.contains { matchesMatcher(handler.matcher, input: $0) }
            case .userPromptSubmit, .stop:
                return true
            }
        }
    }

    public static func runningSummary(
        handler: ConfiguredHookHandler,
        startedAt: Int64 = Int64(Date().timeIntervalSince1970)
    ) -> HookRunSummary {
        HookRunSummary(
            id: handler.runID,
            eventName: handler.eventName,
            handlerType: .command,
            executionMode: .sync,
            scope: scope(for: handler.eventName),
            sourcePath: handler.sourcePath,
            source: handler.source,
            displayOrder: handler.displayOrder,
            status: .running,
            statusMessage: handler.statusMessage,
            startedAt: startedAt,
            completedAt: nil,
            durationMs: nil,
            entries: []
        )
    }

    public static func completedSummary(
        handler: ConfiguredHookHandler,
        runResult: HookCommandRunResult,
        status: HookRunStatus,
        entries: [HookOutputEntry]
    ) -> HookRunSummary {
        HookRunSummary(
            id: handler.runID,
            eventName: handler.eventName,
            handlerType: .command,
            executionMode: .sync,
            scope: scope(for: handler.eventName),
            sourcePath: handler.sourcePath,
            source: handler.source,
            displayOrder: handler.displayOrder,
            status: status,
            statusMessage: handler.statusMessage,
            startedAt: runResult.startedAt,
            completedAt: runResult.completedAt,
            durationMs: runResult.durationMs,
            entries: entries
        )
    }

    public static func scope(for eventName: HookEventName) -> HookScope {
        switch eventName {
        case .sessionStart:
            return .thread
        case .preToolUse, .permissionRequest, .postToolUse, .preCompact, .postCompact, .userPromptSubmit, .stop:
            return .turn
        }
    }

    private static func isMatchAllMatcher(_ matcher: String) -> Bool {
        matcher.isEmpty || matcher == "*"
    }

    private static func isExactMatcher(_ matcher: String) -> Bool {
        matcher.unicodeScalars.allSatisfy { scalar in
            (scalar.value >= 48 && scalar.value <= 57)
                || (scalar.value >= 65 && scalar.value <= 90)
                || (scalar.value >= 97 && scalar.value <= 122)
                || scalar == "_"
                || scalar == "|"
        }
    }
}

extension HookEventName {
    public var hookRunLabel: String {
        switch self {
        case .preToolUse: return "pre-tool-use"
        case .permissionRequest: return "permission-request"
        case .postToolUse: return "post-tool-use"
        case .preCompact: return "pre-compact"
        case .postCompact: return "post-compact"
        case .sessionStart: return "session-start"
        case .userPromptSubmit: return "user-prompt-submit"
        case .stop: return "stop"
        }
    }
}
