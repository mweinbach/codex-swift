import Foundation

public enum SlashCommand: String, CaseIterable, Equatable, Sendable {
    // Presentation order matches codex-rs/tui/src/slash_command.rs.
    case model
    case ide
    case permissions
    case keymap
    case vim
    case setupDefaultSandbox = "setup-default-sandbox"
    case sandboxAddReadDir = "sandbox-add-read-dir"
    case experimental
    case autoReview = "approve"
    case memories
    case skills
    case hooks
    case review
    case rename
    case new
    case resume
    case fork
    case `init` = "init"
    case compact
    case plan
    case goal
    case agent
    case side
    case copy
    case raw
    case diff
    case mention
    case status
    case debugConfig = "debug-config"
    case title
    case statusline
    case theme
    case mcp
    case apps
    case plugins
    case logout
    case quit
    case exit
    case feedback
    case rollout
    case ps
    case stop
    case clear
    case personality
    case realtime
    case settings
    case testApproval = "test-approval"
    case multiAgents = "subagents"
    case memoryDrop = "debug-m-drop"
    case memoryUpdate = "debug-m-update"

    public var command: String { rawValue }

    public var description: String {
        switch self {
        case .feedback:
            return "send logs to maintainers"
        case .new:
            return "start a new chat during a conversation"
        case .`init`:
            return "create an AGENTS.md file with instructions for Codex"
        case .compact:
            return "summarize conversation to prevent hitting the context limit"
        case .review:
            return "review my current changes and find issues"
        case .rename:
            return "rename the current thread"
        case .resume:
            return "resume a saved chat"
        case .clear:
            return "clear the terminal and start a new chat"
        case .fork:
            return "fork the current chat"
        case .quit, .exit:
            return "exit Codex"
        case .copy:
            return "copy last response as markdown"
        case .raw:
            return "toggle raw scrollback mode for copy-friendly terminal selection"
        case .diff:
            return "show git diff (including untracked files)"
        case .mention:
            return "mention a file"
        case .skills:
            return "use skills to improve how Codex performs specific tasks"
        case .hooks:
            return "view and manage lifecycle hooks"
        case .status:
            return "show current session configuration and token usage"
        case .debugConfig:
            return "show config layers and requirement sources for debugging"
        case .title:
            return "configure which items appear in the terminal title"
        case .statusline:
            return "configure which items appear in the status line"
        case .theme:
            return "choose a syntax highlighting theme"
        case .ps:
            return "list background terminals"
        case .stop:
            return "stop all background terminals"
        case .memoryDrop, .memoryUpdate:
            return "DO NOT USE"
        case .model:
            return "choose what model and reasoning effort to use"
        case .ide:
            return "include current selection, open files, and other context from your IDE"
        case .personality:
            return "choose a communication style for Codex"
        case .realtime:
            return "toggle realtime voice mode (experimental)"
        case .settings:
            return "configure realtime microphone/speaker"
        case .plan:
            return "switch to Plan mode"
        case .goal:
            return "set or view the goal for a long-running task"
        case .agent, .multiAgents:
            return "switch the active agent thread"
        case .side:
            return "start a side conversation in an ephemeral fork"
        case .permissions:
            return "choose what Codex is allowed to do"
        case .keymap:
            return "remap TUI shortcuts"
        case .vim:
            return "toggle Vim mode for the composer"
        case .setupDefaultSandbox:
            return "set up elevated agent sandbox"
        case .sandboxAddReadDir:
            return "let sandbox read a directory: /sandbox-add-read-dir <absolute_path>"
        case .experimental:
            return "toggle experimental features"
        case .autoReview:
            return "approve one retry of a recent auto-review denial"
        case .memories:
            return "configure memory use and generation"
        case .mcp:
            return "list configured MCP tools; use /mcp verbose for details"
        case .apps:
            return "manage apps"
        case .plugins:
            return "browse plugins"
        case .logout:
            return "log out of Codex"
        case .rollout:
            return "print the rollout file path"
        case .testApproval:
            return "test approval request"
        }
    }

    public var supportsInlineArgs: Bool {
        switch self {
        case .review, .rename, .plan, .goal, .ide, .keymap, .mcp, .raw, .side, .resume, .sandboxAddReadDir:
            return true
        case .model, .permissions, .vim, .setupDefaultSandbox, .experimental, .autoReview, .memories, .skills,
             .hooks, .new, .fork, .`init`, .compact, .agent, .copy, .diff, .mention, .status,
             .debugConfig, .title, .statusline, .theme, .apps, .plugins, .logout, .quit, .exit, .feedback,
             .rollout, .ps, .stop, .clear, .personality, .realtime, .settings, .testApproval, .multiAgents,
             .memoryDrop, .memoryUpdate:
            return false
        }
    }

    public var availableInSideConversation: Bool {
        switch self {
        case .copy, .raw, .diff, .mention, .status, .ide:
            return true
        case .model, .permissions, .keymap, .vim, .setupDefaultSandbox, .sandboxAddReadDir, .experimental,
             .autoReview, .memories, .skills, .hooks, .review, .rename, .new, .resume, .fork, .`init`,
             .compact, .plan, .goal, .agent, .side, .debugConfig, .title, .statusline, .theme,
             .mcp, .apps, .plugins, .logout, .quit, .exit, .feedback, .rollout, .ps, .stop, .clear,
             .personality, .realtime, .settings, .testApproval, .multiAgents, .memoryDrop, .memoryUpdate:
            return false
        }
    }

    public var availableDuringTask: Bool {
        switch self {
        case .new, .resume, .fork, .`init`, .compact, .model, .personality, .permissions, .keymap, .vim,
             .setupDefaultSandbox, .sandboxAddReadDir, .experimental, .memories, .review, .plan, .clear,
             .logout, .memoryDrop, .memoryUpdate, .theme:
            return false
        case .diff, .copy, .raw, .rename, .mention, .skills, .hooks, .status, .debugConfig, .ps, .stop,
             .goal, .mcp, .apps, .plugins, .title, .statusline, .autoReview, .feedback, .ide, .quit, .exit,
             .side, .rollout, .testApproval, .realtime, .settings, .agent, .multiAgents:
            return true
        }
    }

    public static func from(commandName: String) -> SlashCommand? {
        if let command = SlashCommand(rawValue: commandName) {
            return command
        }

        switch commandName {
        case "clean":
            return .stop
        default:
            return nil
        }
    }

    public static func builtInCommands(includeDebugCommands: Bool = _isDebugAssertConfiguration()) -> [(String, SlashCommand)] {
        allCases
            .filter { $0.isVisible(includeDebugCommands: includeDebugCommands) }
            .map { ($0.command, $0) }
    }

    public static func builtInCommands(options: SlashCommandOptions) -> [(String, SlashCommand)] {
        builtInCommands(includeDebugCommands: options.includeDebugCommands)
            .filter { _, command in options.allowElevateSandbox || command != .setupDefaultSandbox }
            .filter { _, command in options.collaborationModesEnabled || command != .plan }
            .filter { _, command in options.connectorsEnabled || command != .apps }
            .filter { _, command in options.pluginsCommandEnabled || command != .plugins }
            .filter { _, command in options.goalCommandEnabled || command != .goal }
            .filter { _, command in options.personalityCommandEnabled || command != .personality }
            .filter { _, command in options.realtimeConversationEnabled || command != .realtime }
            .filter { _, command in options.audioDeviceSelectionEnabled || command != .settings }
            .filter { _, command in !options.sideConversationActive || command.availableInSideConversation }
    }

    private func isVisible(includeDebugCommands: Bool) -> Bool {
        switch self {
        case .sandboxAddReadDir:
            #if os(Windows)
            return true
            #else
            return false
            #endif
        case .copy:
            #if os(Android)
            return false
            #else
            return true
            #endif
        case .rollout, .testApproval:
            return includeDebugCommands
        case .model, .ide, .permissions, .keymap, .vim, .setupDefaultSandbox, .experimental, .autoReview,
             .memories, .skills, .hooks, .review, .rename, .new, .resume, .fork, .`init`, .compact, .plan,
             .goal, .agent, .side, .raw, .diff, .mention, .status, .debugConfig, .title,
             .statusline, .theme, .mcp, .apps, .plugins, .logout, .quit, .exit, .feedback, .ps, .stop,
             .clear, .personality, .realtime, .settings, .multiAgents, .memoryDrop, .memoryUpdate:
            return true
        }
    }
}

public struct ServiceTierSlashCommand: Equatable, Sendable {
    public let id: String
    public let name: String
    public let description: String

    public init(id: String, name: String, description: String) {
        self.id = id
        self.name = name
        self.description = description
    }

    public init(modelServiceTier serviceTier: ModelServiceTier) {
        self.init(id: serviceTier.id, name: serviceTier.name, description: serviceTier.description)
    }
}

public enum SlashCommandItem: Equatable, Sendable {
    case builtIn(SlashCommand)
    case serviceTier(ServiceTierSlashCommand)

    public var command: String {
        switch self {
        case let .builtIn(command):
            return command.command
        case let .serviceTier(command):
            return command.name
        }
    }

    public var description: String {
        switch self {
        case let .builtIn(command):
            return command.description
        case let .serviceTier(command):
            return command.description
        }
    }

    public var availableDuringTask: Bool {
        switch self {
        case let .builtIn(command):
            return command.availableDuringTask
        case .serviceTier:
            return false
        }
    }

    public var supportsInlineArgs: Bool {
        switch self {
        case let .builtIn(command):
            return command.supportsInlineArgs
        case .serviceTier:
            return false
        }
    }

    public var availableInSideConversation: Bool {
        switch self {
        case let .builtIn(command):
            return command.availableInSideConversation
        case .serviceTier:
            return false
        }
    }
}

public struct SlashCommandOptions: Equatable, Sendable {
    public let includeDebugCommands: Bool
    public let collaborationModesEnabled: Bool
    public let connectorsEnabled: Bool
    public let pluginsCommandEnabled: Bool
    public let serviceTierCommandsEnabled: Bool
    public let goalCommandEnabled: Bool
    public let personalityCommandEnabled: Bool
    public let realtimeConversationEnabled: Bool
    public let audioDeviceSelectionEnabled: Bool
    public let allowElevateSandbox: Bool
    public let sideConversationActive: Bool
    public let serviceTiers: [ModelServiceTier]

    public init(
        includeDebugCommands: Bool = _isDebugAssertConfiguration(),
        collaborationModesEnabled: Bool = false,
        connectorsEnabled: Bool = false,
        pluginsCommandEnabled: Bool = false,
        serviceTierCommandsEnabled: Bool = false,
        goalCommandEnabled: Bool = false,
        personalityCommandEnabled: Bool = false,
        realtimeConversationEnabled: Bool = false,
        audioDeviceSelectionEnabled: Bool = false,
        allowElevateSandbox: Bool = false,
        sideConversationActive: Bool = false,
        serviceTiers: [ModelServiceTier] = []
    ) {
        self.includeDebugCommands = includeDebugCommands
        self.collaborationModesEnabled = collaborationModesEnabled
        self.connectorsEnabled = connectorsEnabled
        self.pluginsCommandEnabled = pluginsCommandEnabled
        self.serviceTierCommandsEnabled = serviceTierCommandsEnabled
        self.goalCommandEnabled = goalCommandEnabled
        self.personalityCommandEnabled = personalityCommandEnabled
        self.realtimeConversationEnabled = realtimeConversationEnabled
        self.audioDeviceSelectionEnabled = audioDeviceSelectionEnabled
        self.allowElevateSandbox = allowElevateSandbox
        self.sideConversationActive = sideConversationActive
        self.serviceTiers = serviceTiers
    }

    fileprivate var withoutSideConversationGating: SlashCommandOptions {
        SlashCommandOptions(
            includeDebugCommands: includeDebugCommands,
            collaborationModesEnabled: collaborationModesEnabled,
            connectorsEnabled: connectorsEnabled,
            pluginsCommandEnabled: pluginsCommandEnabled,
            serviceTierCommandsEnabled: serviceTierCommandsEnabled,
            goalCommandEnabled: goalCommandEnabled,
            personalityCommandEnabled: personalityCommandEnabled,
            realtimeConversationEnabled: realtimeConversationEnabled,
            audioDeviceSelectionEnabled: audioDeviceSelectionEnabled,
            allowElevateSandbox: allowElevateSandbox,
            sideConversationActive: false,
            serviceTiers: serviceTiers
        )
    }
}

public enum SlashCommandCatalog {
    public static func commands(options: SlashCommandOptions = SlashCommandOptions()) -> [SlashCommandItem] {
        let serviceTierCommands = options.serviceTiers.map { ServiceTierSlashCommand(modelServiceTier: $0) }
        let includeServiceTiers = options.serviceTierCommandsEnabled
        var commands: [SlashCommandItem] = []
        commands.reserveCapacity(SlashCommand.allCases.count + (includeServiceTiers ? serviceTierCommands.count : 0))

        for (_, command) in SlashCommand.builtInCommands(options: options) {
            commands.append(.builtIn(command))
            if command == .model, includeServiceTiers {
                commands.append(contentsOf: serviceTierCommands.map(SlashCommandItem.serviceTier))
            }
        }

        return commands.filter { !options.sideConversationActive || $0.availableInSideConversation }
    }

    public static func find(_ name: String, options: SlashCommandOptions = SlashCommandOptions()) -> SlashCommandItem? {
        if let builtIn = SlashCommand.from(commandName: name),
           SlashCommand.builtInCommands(options: options.withoutSideConversationGating)
               .contains(where: { _, visibleCommand in visibleCommand == builtIn }) {
            return .builtIn(builtIn)
        }

        guard options.serviceTierCommandsEnabled else {
            return nil
        }

        return options.serviceTiers
            .map { ServiceTierSlashCommand(modelServiceTier: $0) }
            .first { $0.name == name }
            .map(SlashCommandItem.serviceTier)
    }
}
