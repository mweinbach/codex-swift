import Foundation

public enum ContextUpdateBuilder {
    public static func buildSettingsUpdateItems(
        previous: TurnContextItem?,
        current: TurnContextItem,
        shell: Shell,
        includeEnvironmentContext: Bool = true,
        includePermissionsInstructions: Bool = true,
        approvalsReviewer: ApprovalsReviewer = .user,
        execPolicy: ExecPolicy = .empty(),
        execPermissionApprovalsEnabled: Bool = false,
        requestPermissionsToolEnabled: Bool = false,
        previousModel: String? = nil,
        currentModelInfo: ModelInfo? = nil,
        personalityFeatureEnabled: Bool = true,
        previousRealtimeActive: Bool? = nil,
        realtimeStartInstructions: String? = nil
    ) -> [ResponseItem] {
        var items: [ResponseItem] = []

        let developerSections = [
            buildModelInstructionsUpdateText(
                previousModel: previousModel,
                current: current,
                currentModelInfo: currentModelInfo
            ),
            buildPermissionsUpdateText(
                previous: previous,
                current: current,
                includePermissionsInstructions: includePermissionsInstructions,
                approvalsReviewer: approvalsReviewer,
                execPolicy: execPolicy,
                execPermissionApprovalsEnabled: execPermissionApprovalsEnabled,
                requestPermissionsToolEnabled: requestPermissionsToolEnabled
            ),
            buildCollaborationModeUpdateText(previous: previous, current: current),
            buildRealtimeUpdateText(
                previous: previous,
                previousRealtimeActive: previousRealtimeActive,
                current: current,
                realtimeStartInstructions: realtimeStartInstructions
            ),
            buildPersonalityUpdateText(
                previous: previous,
                current: current,
                currentModelInfo: currentModelInfo,
                personalityFeatureEnabled: personalityFeatureEnabled
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

    public static func buildPermissionsUpdateText(
        previous: TurnContextItem?,
        current: TurnContextItem,
        includePermissionsInstructions: Bool,
        approvalsReviewer: ApprovalsReviewer = .user,
        execPolicy: ExecPolicy = .empty(),
        execPermissionApprovalsEnabled: Bool = false,
        requestPermissionsToolEnabled: Bool = false
    ) -> String? {
        guard includePermissionsInstructions,
              let previous,
              previous.effectivePermissionProfile != current.effectivePermissionProfile
                || previous.approvalPolicy != current.approvalPolicy
        else {
            return nil
        }

        return PermissionsInstructions.fromPermissionProfile(
            current.effectivePermissionProfile,
            config: PermissionsPromptConfig(
                approvalPolicy: current.approvalPolicy,
                approvalsReviewer: approvalsReviewer,
                execPolicy: execPolicy,
                execPermissionApprovalsEnabled: execPermissionApprovalsEnabled,
                requestPermissionsToolEnabled: requestPermissionsToolEnabled
            ),
            cwd: current.cwd
        ).render()
    }

    public static func buildModelInstructionsUpdateText(
        previousModel: String?,
        current: TurnContextItem,
        currentModelInfo: ModelInfo?
    ) -> String? {
        guard let previousModel,
              let currentModelInfo,
              previousModel != current.model
        else {
            return nil
        }

        let modelInstructions = currentModelInfo.modelInstructions(personality: current.personality)
        guard !modelInstructions.isEmpty else {
            return nil
        }
        return renderModelSwitchInstructions(modelInstructions)
    }

    public static func buildCollaborationModeUpdateText(
        previous: TurnContextItem?,
        current: TurnContextItem
    ) -> String? {
        guard let previous,
              previous.collaborationMode != current.collaborationMode,
              let developerInstructions = current.collaborationMode?.settings.developerInstructions,
              !developerInstructions.isEmpty
        else {
            return nil
        }

        return renderCollaborationModeInstructions(developerInstructions)
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

    public static func buildPersonalityUpdateText(
        previous: TurnContextItem?,
        current: TurnContextItem,
        currentModelInfo: ModelInfo?,
        personalityFeatureEnabled: Bool
    ) -> String? {
        guard personalityFeatureEnabled,
              let previous,
              current.model == previous.model,
              let personality = current.personality,
              current.personality != previous.personality,
              let message = currentModelInfo?.personalityMessage(for: personality)
        else {
            return nil
        }

        return renderPersonalitySpecInstructions(message)
    }

    public static func renderModelSwitchInstructions(_ modelInstructions: String) -> String {
        contextualFragment(
            openTag: "<model_switch>",
            closeTag: "</model_switch>",
            body: "\nThe user was previously using a different model. Please continue the conversation according to the following instructions:\n\n\(modelInstructions)\n"
        )
    }

    public static func renderCollaborationModeInstructions(_ instructions: String) -> String {
        contextualFragment(
            openTag: "<collaboration_mode>",
            closeTag: "</collaboration_mode>",
            body: instructions
        )
    }

    public static func renderPersonalitySpecInstructions(_ spec: String) -> String {
        contextualFragment(
            openTag: "<personality_spec>",
            closeTag: "</personality_spec>",
            body: " The user has requested a new communication style. Future messages should adhere to the following personality: \n\(spec) "
        )
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

    public static func contextualFragment(openTag: String, closeTag: String, body: String) -> String {
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
