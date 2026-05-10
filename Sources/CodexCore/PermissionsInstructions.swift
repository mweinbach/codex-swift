import Foundation

public struct PermissionsPromptConfig: Equatable, Sendable {
    public let approvalPolicy: AskForApproval
    public let approvalsReviewer: ApprovalsReviewer
    public let execPolicy: ExecPolicy
    public let execPermissionApprovalsEnabled: Bool
    public let requestPermissionsToolEnabled: Bool

    public init(
        approvalPolicy: AskForApproval,
        approvalsReviewer: ApprovalsReviewer = .user,
        execPolicy: ExecPolicy = .empty(),
        execPermissionApprovalsEnabled: Bool = false,
        requestPermissionsToolEnabled: Bool = false
    ) {
        self.approvalPolicy = approvalPolicy
        self.approvalsReviewer = approvalsReviewer
        self.execPolicy = execPolicy
        self.execPermissionApprovalsEnabled = execPermissionApprovalsEnabled
        self.requestPermissionsToolEnabled = requestPermissionsToolEnabled
    }
}

/// Renders the model-visible sandbox and approval-policy instructions.
///
/// Session setup and context-update code build this value from the effective
/// `PermissionProfile`; callers can rely on Rust-compatible prompt sections,
/// ordering, and contextual-fragment tags.
public struct PermissionsInstructions: Equatable, Sendable {
    public let text: String

    public init(text: String) {
        self.text = text
    }

    public static func fromPermissionProfile(
        _ permissionProfile: PermissionProfile,
        config: PermissionsPromptConfig,
        cwd: String
    ) -> PermissionsInstructions {
        let prompt = sandboxPrompt(from: permissionProfile, cwd: cwd)
        return fromPermissionsWithNetwork(
            sandboxMode: prompt.sandboxMode,
            networkAccess: permissionProfile.networkSandboxPolicy.isEnabled ? .enabled : .restricted,
            config: config,
            writableRoots: prompt.writableRoots
        )
    }

    public static func fromPolicy(
        _ sandboxPolicy: SandboxPolicy,
        config: PermissionsPromptConfig,
        cwd: String
    ) -> PermissionsInstructions {
        fromPermissionProfile(
            .fromLegacySandboxPolicy(sandboxPolicy),
            config: config,
            cwd: cwd
        )
    }

    public static func fromPermissionsWithNetwork(
        sandboxMode: SandboxMode,
        networkAccess: NetworkAccess,
        config: PermissionsPromptConfig,
        writableRoots: [WritableRoot]?
    ) -> PermissionsInstructions {
        var text = ""
        appendSection(&text, sandboxText(mode: sandboxMode, networkAccess: networkAccess))
        appendSection(&text, approvalText(config: config))
        if let writableRoots = writableRootsText(writableRoots) {
            appendSection(&text, writableRoots)
        }
        if !text.hasSuffix("\n") {
            text.append("\n")
        }
        return PermissionsInstructions(text: text)
    }

    public func render() -> String {
        ContextUpdateBuilder.contextualFragment(
            openTag: "<permissions instructions>",
            closeTag: "</permissions instructions>",
            body: text
        )
    }

    public static func sandboxText(mode: SandboxMode, networkAccess: NetworkAccess) -> String {
        let network = networkAccess.rawValue
        switch mode {
        case .dangerFullAccess:
            return "Filesystem sandboxing defines which files can be read or written. `sandbox_mode` is `danger-full-access`: No filesystem sandboxing - all commands are permitted. Network access is \(network)."
        case .workspaceWrite:
            return "Filesystem sandboxing defines which files can be read or written. `sandbox_mode` is `workspace-write`: The sandbox permits reading files, and editing files in `cwd` and `writable_roots`. Editing files in other directories requires approval. Network access is \(network)."
        case .readOnly:
            return "Filesystem sandboxing defines which files can be read or written. `sandbox_mode` is `read-only`: The sandbox only permits reading files. Network access is \(network)."
        }
    }

    public static func approvalText(config: PermissionsPromptConfig) -> String {
        let text: String
        switch config.approvalPolicy {
        case .never:
            text = approvalPolicyNever
        case .unlessTrusted:
            text = withRequestPermissionsTool(
                approvalPolicyUnlessTrusted,
                enabled: config.requestPermissionsToolEnabled
            )
        case .onFailure:
            text = withRequestPermissionsTool(
                approvalPolicyOnFailure,
                enabled: config.requestPermissionsToolEnabled
            )
        case .onRequest:
            text = onRequestInstructions(config: config)
        case let .granular(granularConfig):
            text = granularInstructions(granularConfig, config: config)
        }

        if config.approvalsReviewer == .autoReview && config.approvalPolicy != .never {
            return "\(text)\n\n\(autoReviewApprovalSuffix)"
        }
        return text
    }

    private static func sandboxPrompt(
        from permissionProfile: PermissionProfile,
        cwd: String
    ) -> (sandboxMode: SandboxMode, writableRoots: [WritableRoot]?) {
        switch permissionProfile {
        case .disabled, .external:
            return (.dangerFullAccess, nil)
        case .managed:
            let fileSystemPolicy = permissionProfile.fileSystemSandboxPolicy
            if fileSystemPolicy.hasFullDiskWriteAccess {
                return (.dangerFullAccess, nil)
            }

            let writableRoots = fileSystemPolicy.getWritableRootsWithCwd(cwd)
            if writableRoots.isEmpty {
                return (.readOnly, nil)
            }
            return (.workspaceWrite, writableRoots)
        }
    }

    private static func appendSection(_ text: inout String, _ section: String) {
        if !text.hasSuffix("\n") {
            text.append("\n")
        }
        text.append(section)
    }

    private static func writableRootsText(_ writableRoots: [WritableRoot]?) -> String? {
        guard let writableRoots, !writableRoots.isEmpty else {
            return nil
        }
        let rootsList = writableRoots.map { "`\($0.root.path)`" }
        if rootsList.count == 1 {
            return " The writable root is \(rootsList[0])."
        }
        return " The writable roots are \(rootsList.joined(separator: ", "))."
    }

    private static func withRequestPermissionsTool(_ text: String, enabled: Bool) -> String {
        enabled ? "\(text)\n\n\(requestPermissionsToolPromptSection)" : text
    }

    private static func onRequestInstructions(config: PermissionsPromptConfig) -> String {
        let onRequestRule = config.execPermissionApprovalsEnabled
            ? approvalPolicyOnRequestRuleRequestPermission
            : approvalPolicyOnRequestRule
        var sections = [onRequestRule]
        if config.requestPermissionsToolEnabled {
            sections.append(requestPermissionsToolPromptSection)
        }
        if let prefixes = config.execPolicy.formattedAllowedPrefixes() {
            sections.append("""
            ## Approved command prefixes
            The following prefix rules have already been approved: \(prefixes)
            """)
        }
        return sections.joined(separator: "\n\n")
    }

    private static func granularInstructions(
        _ granularConfig: GranularApprovalConfig,
        config: PermissionsPromptConfig
    ) -> String {
        let shellPermissionRequestsAvailable =
            config.execPermissionApprovalsEnabled && granularConfig.allowsSandboxApproval
        let requestPermissionsToolPromptsAllowed =
            config.requestPermissionsToolEnabled && granularConfig.allowsRequestPermissions
        let categories: [(Bool, String)] = [
            (granularConfig.allowsSandboxApproval, "`sandbox_approval`"),
            (granularConfig.allowsRulesApproval, "`rules`"),
            (granularConfig.allowsSkillApproval, "`skill_approval`")
        ] + (config.requestPermissionsToolEnabled ? [
            (granularConfig.allowsRequestPermissions, "`request_permissions`")
        ] : []) + [
            (granularConfig.allowsMcpElicitations, "`mcp_elicitations`")
        ]

        let promptedCategories = categories
            .filter(\.0)
            .map { "- \($0.1)" }
        let rejectedCategories = categories
            .filter { !$0.0 }
            .map { "- \($0.1)" }

        var sections = [granularPromptIntroText]
        if !promptedCategories.isEmpty {
            sections.append("""
            These approval categories may still prompt the user when needed:
            \(promptedCategories.joined(separator: "\n"))
            """)
        }
        if !rejectedCategories.isEmpty {
            sections.append("""
            These approval categories are automatically rejected instead of prompting the user:
            \(rejectedCategories.joined(separator: "\n"))
            """)
        }
        if shellPermissionRequestsAvailable {
            sections.append(approvalPolicyOnRequestRuleRequestPermission)
        }
        if requestPermissionsToolPromptsAllowed {
            sections.append(requestPermissionsToolPromptSection)
        }
        if let prefixes = config.execPolicy.formattedAllowedPrefixes() {
            sections.append("""
            ## Approved command prefixes
            The following prefix rules have already been approved: \(prefixes)
            """)
        }
        return sections.joined(separator: "\n\n")
    }

    private static let approvalPolicyNever = "Approval policy is currently never. Do not provide the `sandbox_permissions` for any reason, commands will be rejected."

    private static let approvalPolicyUnlessTrusted = #" Approvals are your mechanism to get user consent to run shell commands without the sandbox. `approval_policy` is `unless-trusted`: The harness will escalate most commands for user approval, apart from a limited allowlist of safe "read" commands."#

    private static let approvalPolicyOnFailure = "Approvals are your mechanism to get user consent to run shell commands without the sandbox. `approval_policy` is `on-failure`: The harness will allow all commands to run in the sandbox (if enabled), and failures will be escalated to the user for approval to run again without the sandbox."

    private static let approvalPolicyOnRequestRule = """
    # Escalation Requests

    Commands are run outside the sandbox if they are approved by the user, or match an existing rule that allows it to run unrestricted. The command string is split into independent command segments at shell control operators, including but not limited to:

    - Pipes: |
    - Logical operators: &&, ||
    - Command separators: ;
    - Subshell boundaries: (...), $(...)

    Each resulting segment is evaluated independently for sandbox restrictions and approval requirements.

    Example:

    git pull | tee output.txt

    This is treated as two command segments:

    ["git", "pull"]

    ["tee", "output.txt"]

    Commands that use more advanced shell features like redirection (>, >>, <), substitutions ($(...), ...), environment variables (FOO=bar), or wildcard patterns (*, ?) will not be evaluated against rules, to limit the scope of what an approved rule allows.

    ## How to request escalation

    IMPORTANT: To request approval to execute a command that will require escalated privileges:

    - Provide the `sandbox_permissions` parameter with the value `"require_escalated"`
    - Include a short question asking the user if they want to allow the action in `justification` parameter. e.g. "Do you want to download and install dependencies for this project?"
    - Optionally suggest a `prefix_rule` - this will be shown to the user with an option to persist the rule approval for future sessions.

    If you run a command that is important to solving the user's query, but it fails because of sandboxing or with a likely sandbox-related network error (for example DNS/host resolution, registry/index access, or dependency download failure), rerun the command with "require_escalated". ALWAYS proceed to use the `justification` parameter - do not message the user before requesting approval for the command.

    ## When to request escalation

    While commands are running inside the sandbox, here are some scenarios that will require escalation outside the sandbox:

    - You need to run a command that writes to a directory that requires it (e.g. running tests that write to /var)
    - You need to run a GUI app (e.g., open/xdg-open/osascript) to open browsers or files.
    - If you run a command that is important to solving the user's query, but it fails because of sandboxing or with a likely sandbox-related network error (for example DNS/host resolution, registry/index access, or dependency download failure), rerun the command with `require_escalated`. ALWAYS proceed to use the `sandbox_permissions` and `justification` parameters. do not message the user before requesting approval for the command.
    - You are about to take a potentially destructive action such as an `rm` or `git reset` that the user did not explicitly ask for.
    - Be judicious with escalating, but if completing the user's request requires it, you should do so - don't try and circumvent approvals by using other tools.

    ## prefix_rule guidance

    When choosing a `prefix_rule`, request one that will allow you to fulfill similar requests from the user in the future without re-requesting escalation. It should be categorical and reasonably scoped to similar capabilities. You should rarely pass the entire command into `prefix_rule`.

    ### Banned prefix_rules 
    Avoid requesting overly broad prefixes that the user would be ill-advised to approve. For example, do not request ["python3"], ["python", "-"], or other similar prefixes that would allow arbitrary scripting.
    NEVER provide a prefix_rule argument for destructive commands like rm.
    NEVER provide a prefix_rule if your command uses a heredoc or herestring. 

    ### Examples
    Good examples of prefixes:
    - ["npm", "run", "dev"]
    - ["gh", "pr", "check"]
    - ["cargo", "test"]
    """

    private static let approvalPolicyOnRequestRuleRequestPermission = """
    # Permission Requests

    Commands may require user approval before execution. Prefer requesting sandboxed additional permissions instead of asking to run fully outside the sandbox.

    ## Preferred request mode

    When you need extra sandboxed permissions for one command, use:

    - `sandbox_permissions: "with_additional_permissions"`
    - `additional_permissions` with one or more of:
      - `network.enabled`: set to `true` to enable network access
      - `file_system.read`: list of paths that need read access
      - `file_system.write`: list of paths that need write access

    When using the `request_permissions` tool directly, only request `network` and `file_system` permissions.

    This keeps execution inside the current sandbox policy, while adding only the requested permissions for that command, unless an exec-policy allow rule applies and authorizes running the command outside the sandbox.

    If the command already matches an exec-policy allow rule, the command can be auto-approved without an extra prompt. In that case, exec-policy allow behavior (including any sandbox bypass) takes precedence.

    ## Escalation Requests

    Use full escalation only when sandboxed additional permissions cannot satisfy the task.

    - `sandbox_permissions: "require_escalated"`
    - Include `justification` as a short question asking for approval.
    - Optionally include `prefix_rule` to suggest a reusable allow rule.

    ## Command segmentation reminder

    The command string is split into independent command segments at shell control operators, including pipes (`|`), logical operators (`&&`, `||`), command separators (`;`), and subshell boundaries (`(...)`, `$()`).

    Each segment is evaluated independently for sandbox restrictions and approval requirements.
    """

    private static let autoReviewApprovalSuffix = "`approvals_reviewer` is `auto_review`: Sandbox escalations with require_escalated will be reviewed for compliance with the policy. If a rejection happens, you should proceed only with a materially safer alternative, or inform the user of the risk and send a final message to ask for approval."

    private static let granularPromptIntroText = "# Approval Requests\n\nApproval policy is `granular`. Categories set to `false` are automatically rejected instead of prompting the user."

    private static let requestPermissionsToolPromptSection = """
    # request_permissions Tool

    The built-in `request_permissions` tool is available in this session. Invoke it when you need to request additional `network` or `file_system` permissions before later shell-like commands need them. Request only the specific permissions required for the task.
    """
}
