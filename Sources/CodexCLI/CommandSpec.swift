import Foundation

public struct CommandSpec: Equatable, Sendable {
    public let name: String
    public let aliases: [String]
    public let summary: String
    public let isHidden: Bool

    public init(name: String, aliases: [String] = [], summary: String, isHidden: Bool = false) {
        self.name = name
        self.aliases = aliases
        self.summary = summary
        self.isHidden = isHidden
    }

    public func matches(_ token: String) -> Bool {
        token == name || aliases.contains(token)
    }
}

public enum CodexCommandRegistry {
    public static let commands: [CommandSpec] = [
        CommandSpec(name: "exec", aliases: ["e"], summary: "Run Codex non-interactively."),
        CommandSpec(name: "computer-use", aliases: ["cu"], summary: "Run Codex in computer-use mode (CLI-only or GUI-enabled)."),
        CommandSpec(name: "review", summary: "Run a code review non-interactively."),
        CommandSpec(name: "login", summary: "Manage login."),
        CommandSpec(name: "logout", summary: "Remove stored authentication credentials."),
        CommandSpec(name: "mcp", summary: "[experimental] Run Codex as an MCP server and manage MCP servers."),
        CommandSpec(name: "mcp-server", summary: "[experimental] Run the Codex MCP server (stdio transport)."),
        CommandSpec(name: "app-server", summary: "[experimental] Run the app server or related tooling."),
        CommandSpec(name: "completion", summary: "Generate shell completion scripts."),
        CommandSpec(name: "sandbox", aliases: ["debug"], summary: "Run commands within a Codex-provided sandbox."),
        CommandSpec(name: "execpolicy", summary: "Execpolicy tooling.", isHidden: true),
        CommandSpec(name: "apply", aliases: ["a"], summary: "Apply the latest diff produced by Codex agent as a git apply to your local working tree."),
        CommandSpec(name: "resume", summary: "Resume a previous interactive session."),
        CommandSpec(name: "cloud", aliases: ["cloud-tasks"], summary: "[EXPERIMENTAL] Browse tasks from Codex Cloud and apply changes locally."),
        CommandSpec(name: "responses-api-proxy", summary: "Internal: run the responses API proxy.", isHidden: true),
        CommandSpec(name: "stdio-to-uds", summary: "Internal: relay stdio to a Unix domain socket.", isHidden: true),
        CommandSpec(name: "features", summary: "Inspect feature flags.")
    ]

    public static func command(matching token: String) -> CommandSpec? {
        commands.first { $0.matches(token) }
    }
}
