import Foundation

public enum SlashCommand: String, CaseIterable, Equatable, Sendable {
    // Presentation order matches codex-rs/tui/src/slash_command.rs.
    case model
    case approvals
    case experimental
    case skills
    case review
    case new
    case resume
    case `init` = "init"
    case compact
    case diff
    case mention
    case status
    case mcp
    case logout
    case quit
    case exit
    case feedback
    case rollout
    case ps
    case testApproval = "test-approval"

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
        case .resume:
            return "resume a saved chat"
        case .quit, .exit:
            return "exit Codex"
        case .diff:
            return "show git diff (including untracked files)"
        case .mention:
            return "mention a file"
        case .skills:
            return "use skills to improve how Codex performs specific tasks"
        case .status:
            return "show current session configuration and token usage"
        case .ps:
            return "list background terminals"
        case .model:
            return "choose what model and reasoning effort to use"
        case .approvals:
            return "choose what Codex can do without approval"
        case .experimental:
            return "toggle beta features"
        case .mcp:
            return "list configured MCP tools"
        case .logout:
            return "log out of Codex"
        case .rollout:
            return "print the rollout file path"
        case .testApproval:
            return "test approval request"
        }
    }

    public var availableDuringTask: Bool {
        switch self {
        case .new, .resume, .`init`, .compact, .model, .approvals, .experimental, .review, .logout:
            return false
        case .diff, .mention, .skills, .status, .ps, .mcp, .feedback, .quit, .exit, .rollout, .testApproval:
            return true
        }
    }

    public static func builtInCommands(includeDebugCommands: Bool = _isDebugAssertConfiguration()) -> [(String, SlashCommand)] {
        allCases
            .filter { includeDebugCommands || !($0 == .rollout || $0 == .testApproval) }
            .map { ($0.command, $0) }
    }
}
