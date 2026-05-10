import Foundation

public enum ContextUpdateBuilder {
    public static func buildSettingsUpdateItems(
        previous: TurnContextItem?,
        current: TurnContextItem,
        shell: Shell,
        includeEnvironmentContext: Bool = true,
        previousRealtimeActive: Bool? = nil,
        realtimeStartInstructions: String? = nil
    ) -> [ResponseItem] {
        var items: [ResponseItem] = []

        let developerSections = [
            buildRealtimeUpdateText(
                previous: previous,
                previousRealtimeActive: previousRealtimeActive,
                current: current,
                realtimeStartInstructions: realtimeStartInstructions
            )
        ].compactMap(\.self)

        if let developerMessage = buildTextMessage(role: "developer", textSections: developerSections) {
            items.append(developerMessage)
        }
        if includeEnvironmentContext,
           let environmentItem = buildEnvironmentUpdateItem(previous: previous, current: current, shell: shell)
        {
            items.append(environmentItem)
        }

        return items
    }

    public static func buildEnvironmentUpdateItem(
        previous: TurnContextItem?,
        current: TurnContextItem,
        shell: Shell
    ) -> ResponseItem? {
        guard let previous else {
            return environmentItem(from: current, shell: shell)
        }

        let previousEnvironment = PersistedEnvironmentContext(item: previous, shell: shell.name)
        let currentEnvironment = PersistedEnvironmentContext(item: current, shell: shell.name)
        guard !previousEnvironment.equalsExceptShell(currentEnvironment) else {
            return nil
        }

        return environmentItem(from: currentEnvironment.diff(from: previous))
    }

    public static func buildRealtimeUpdateText(
        previous: TurnContextItem?,
        previousRealtimeActive: Bool?,
        current: TurnContextItem,
        realtimeStartInstructions: String? = nil
    ) -> String? {
        switch (previous?.realtimeActive, current.realtimeActive ?? false) {
        case (.some(true), false):
            return renderRealtimeEndInstructions(reason: "inactive")
        case (.some(false), true), (.none, true):
            return renderRealtimeStartInstructions(realtimeStartInstructions)
        case (.some(true), true), (.some(false), false):
            return nil
        case (.none, false):
            guard previousRealtimeActive == true else {
                return nil
            }
            return renderRealtimeEndInstructions(reason: "inactive")
        }
    }

    public static func renderRealtimeStartInstructions(_ instructions: String? = nil) -> String {
        let body = instructions ?? defaultRealtimeStartInstructions
        return contextualFragment(
            openTag: "<realtime_conversation>",
            closeTag: "</realtime_conversation>",
            body: body
        )
    }

    public static func renderRealtimeEndInstructions(reason: String) -> String {
        contextualFragment(
            openTag: "<realtime_conversation>",
            closeTag: "</realtime_conversation>",
            body: "\(defaultRealtimeEndInstructions)\n\nReason: \(reason)"
        )
    }

    private static let defaultRealtimeStartInstructions = """
    Realtime conversation started.

    You are operating as a backend executor behind an intermediary. The user does not talk to you directly. Any response you produce will be consumed by the intermediary and may be summarized before the user sees it.

    When invoked, you receive the latest conversation transcript and any relevant mode or metadata. The intermediary may invoke you even when backend help is not actually needed. Use the transcript to decide whether you should do work. If backend help is unnecessary, avoid verbose responses that add user-visible latency.

    When user text is routed from realtime, treat it as a transcript. It may be unpunctuated or contain recognition errors.

    - Keep responses concise and action-oriented. Your updates should help the intermediary respond to the user.
    """

    private static let defaultRealtimeEndInstructions = """
    Realtime conversation ended.

    Subsequent user input will return to typed text rather than transcript-style text. Do not assume recognition errors or missing punctuation once realtime has ended. Resume normal chat behavior.
    """

    private static func environmentItem(from item: TurnContextItem, shell: Shell) -> ResponseItem {
        environmentItem(from: PersistedEnvironmentContext(item: item, shell: shell.name))
    }

    private static func environmentItem(from context: PersistedEnvironmentContext) -> ResponseItem {
        .message(role: "user", content: [.inputText(text: context.render())])
    }

    private static func buildTextMessage(role: String, textSections: [String]) -> ResponseItem? {
        guard !textSections.isEmpty else {
            return nil
        }
        return .message(role: role, content: textSections.map { .inputText(text: $0) })
    }

    private static func contextualFragment(openTag: String, closeTag: String, body: String) -> String {
        "\(openTag)\n\(body)\n\(closeTag)"
    }
}

private struct PersistedEnvironmentContext: Equatable {
    var cwd: String?
    var shell: String?
    var currentDate: String?
    var timezone: String?
    var network: TurnContextNetworkItem?

    init(
        cwd: String?,
        shell: String?,
        currentDate: String?,
        timezone: String?,
        network: TurnContextNetworkItem?
    ) {
        self.cwd = cwd
        self.shell = shell
        self.currentDate = currentDate
        self.timezone = timezone
        self.network = network
    }

    init(item: TurnContextItem, shell: String) {
        self.init(
            cwd: item.cwd,
            shell: shell,
            currentDate: item.currentDate,
            timezone: item.timezone,
            network: item.network
        )
    }

    func equalsExceptShell(_ other: PersistedEnvironmentContext) -> Bool {
        cwd == other.cwd
            && currentDate == other.currentDate
            && timezone == other.timezone
            && network == other.network
    }

    func diff(from previous: TurnContextItem) -> PersistedEnvironmentContext {
        PersistedEnvironmentContext(
            cwd: previous.cwd == cwd ? nil : cwd,
            shell: previous.cwd == cwd ? nil : shell,
            currentDate: currentDate,
            timezone: timezone,
            network: previous.network != network ? network : previous.network
        )
    }

    func render() -> String {
        var lines = [EnvironmentContext.openTag]
        if let cwd {
            lines.append("  <cwd>\(cwd)</cwd>")
            if let shell {
                lines.append("  <shell>\(shell)</shell>")
            }
        }
        if let currentDate {
            lines.append("  <current_date>\(currentDate)</current_date>")
        }
        if let timezone {
            lines.append("  <timezone>\(timezone)</timezone>")
        }
        if let network {
            lines.append("  <network enabled=\"true\">")
            for allowed in network.allowedDomains {
                lines.append("    <allowed>\(allowed)</allowed>")
            }
            for denied in network.deniedDomains {
                lines.append("    <denied>\(denied)</denied>")
            }
            lines.append("  </network>")
        }
        lines.append(EnvironmentContext.closeTag)
        return lines.joined(separator: "\n")
    }
}
