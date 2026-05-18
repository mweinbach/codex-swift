import Foundation

public struct TurnContext: Equatable, Sendable {
    private let environmentCwd: String
    public let approvalPolicy: AskForApproval
    public let sandboxPolicy: SandboxPolicy

    public init(cwd: String, approvalPolicy: AskForApproval, sandboxPolicy: SandboxPolicy) {
        self.environmentCwd = cwd
        self.approvalPolicy = approvalPolicy
        self.sandboxPolicy = sandboxPolicy
    }

    public var selectedEnvironmentCwd: String {
        environmentCwd
    }

    @available(*, deprecated, message: "use selectedEnvironmentCwd instead")
    public var cwd: String {
        environmentCwd
    }
}

public struct EnvironmentContextEnvironment: Equatable, Codable, Sendable {
    public let id: String
    public let cwd: String
    public let shell: String

    public init(id: String, cwd: String, shell: String) {
        self.id = id
        self.cwd = cwd
        self.shell = shell
    }
}

public struct EnvironmentContextNetwork: Equatable, Codable, Sendable {
    public let allowedDomains: [String]
    public let deniedDomains: [String]

    private enum CodingKeys: String, CodingKey {
        case allowedDomains = "allowed_domains"
        case deniedDomains = "denied_domains"
    }

    public init(allowedDomains: [String] = [], deniedDomains: [String] = []) {
        self.allowedDomains = allowedDomains
        self.deniedDomains = deniedDomains
    }
}

public struct EnvironmentContext: Equatable, Codable, Sendable {
    public static let openTag = "<environment_context>"
    public static let closeTag = "</environment_context>"

    public let environments: [EnvironmentContextEnvironment]?
    public let currentDate: String?
    public let timezone: String?
    public let network: EnvironmentContextNetwork?
    public let cwd: String?
    public let approvalPolicy: AskForApproval?
    public let sandboxMode: SandboxMode?
    public let networkAccess: NetworkAccess?
    public let writableRoots: [AbsolutePath]?
    public let shell: Shell
    public let subagents: String?

    private enum CodingKeys: String, CodingKey {
        case environments
        case currentDate = "current_date"
        case timezone
        case network
        case cwd
        case approvalPolicy = "approval_policy"
        case sandboxMode = "sandbox_mode"
        case networkAccess = "network_access"
        case writableRoots = "writable_roots"
        case shell
        case subagents
    }

    public init(
        cwd: String?,
        approvalPolicy: AskForApproval?,
        sandboxPolicy: SandboxPolicy?,
        shell: Shell,
        environments: [EnvironmentContextEnvironment]? = nil,
        currentDate: String? = nil,
        timezone: String? = nil,
        network: EnvironmentContextNetwork? = nil,
        subagents: String? = nil
    ) {
        self.environments = environments
        self.currentDate = currentDate
        self.timezone = timezone
        self.network = network
        self.cwd = cwd
        self.approvalPolicy = approvalPolicy
        self.sandboxMode = sandboxPolicy.map(Self.sandboxMode(for:))
        self.networkAccess = sandboxPolicy.map(Self.networkAccess(for:))
        self.writableRoots = Self.writableRoots(for: sandboxPolicy)
        self.shell = shell
        self.subagents = subagents.flatMap(Self.nonEmpty)
    }

    public init(
        cwd: String?,
        approvalPolicy: AskForApproval?,
        sandboxMode: SandboxMode?,
        networkAccess: NetworkAccess?,
        writableRoots: [AbsolutePath]?,
        shell: Shell,
        environments: [EnvironmentContextEnvironment]? = nil,
        currentDate: String? = nil,
        timezone: String? = nil,
        network: EnvironmentContextNetwork? = nil,
        subagents: String? = nil
    ) {
        self.environments = environments
        self.currentDate = currentDate
        self.timezone = timezone
        self.network = network
        self.cwd = cwd
        self.approvalPolicy = approvalPolicy
        self.sandboxMode = sandboxMode
        self.networkAccess = networkAccess
        self.writableRoots = writableRoots
        self.shell = shell
        self.subagents = subagents.flatMap(Self.nonEmpty)
    }

    public static func diff(before: TurnContext, after: TurnContext, shell: Shell) -> EnvironmentContext {
        EnvironmentContext(
            cwd: before.selectedEnvironmentCwd == after.selectedEnvironmentCwd ? nil : after.selectedEnvironmentCwd,
            approvalPolicy: before.approvalPolicy == after.approvalPolicy ? nil : after.approvalPolicy,
            sandboxPolicy: before.sandboxPolicy == after.sandboxPolicy ? nil : after.sandboxPolicy,
            shell: shell
        )
    }

    public static func fromTurnContext(_ turnContext: TurnContext, shell: Shell) -> EnvironmentContext {
        EnvironmentContext(
            cwd: turnContext.selectedEnvironmentCwd,
            approvalPolicy: turnContext.approvalPolicy,
            sandboxPolicy: turnContext.sandboxPolicy,
            shell: shell
        )
    }

    public static func matchesText(_ text: String) -> Bool {
        contextualFragmentMatches(text, startMarker: openTag, endMarker: closeTag)
    }

    public func equalsExceptShell(_ other: EnvironmentContext) -> Bool {
        environmentsEqualExceptShell(environments, other.environments)
            && currentDate == other.currentDate
            && timezone == other.timezone
            && network == other.network
            && cwd == other.cwd
            && approvalPolicy == other.approvalPolicy
            && sandboxMode == other.sandboxMode
            && networkAccess == other.networkAccess
            && writableRoots == other.writableRoots
            && subagents == other.subagents
    }

    public func serializeToXML() -> String {
        var lines = [Self.openTag]
        if let environments {
            appendEnvironments(environments, to: &lines)
        } else {
            if let cwd {
                lines.append("  <cwd>\(cwd)</cwd>")
            }
            if let approvalPolicy {
                lines.append("  <approval_policy>\(approvalPolicy.rawValue)</approval_policy>")
            }
            if let sandboxMode {
                lines.append("  <sandbox_mode>\(sandboxMode.rawValue)</sandbox_mode>")
            }
            if let networkAccess {
                lines.append("  <network_access>\(networkAccess.rawValue)</network_access>")
            }
            if let writableRoots {
                lines.append("  <writable_roots>")
                for writableRoot in writableRoots {
                    lines.append("    <root>\(writableRoot.path)</root>")
                }
                lines.append("  </writable_roots>")
            }

            lines.append("  <shell>\(shell.name)</shell>")
        }
        if let currentDate {
            lines.append("  <current_date>\(currentDate)</current_date>")
        }
        if let timezone {
            lines.append("  <timezone>\(timezone)</timezone>")
        }
        if let network {
            lines.append("  \(renderNetwork(network))")
        }
        if let subagents {
            lines.append("  <subagents>")
            lines.append(contentsOf: subagents
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map { "    \($0)" })
            lines.append("  </subagents>")
        }
        lines.append(Self.closeTag)
        return lines.joined(separator: "\n")
    }

    public func asResponseItem() -> ResponseItem {
        .message(
            role: "user",
            content: [.inputText(text: serializeToXML())]
        )
    }

    private static func sandboxMode(for sandboxPolicy: SandboxPolicy) -> SandboxMode {
        switch sandboxPolicy {
        case .dangerFullAccess, .externalSandbox:
            return .dangerFullAccess
        case .readOnly, .readOnlyWithNetworkAccess:
            return .readOnly
        case .workspaceWrite:
            return .workspaceWrite
        }
    }

    private static func networkAccess(for sandboxPolicy: SandboxPolicy) -> NetworkAccess {
        switch sandboxPolicy {
        case .dangerFullAccess:
            return .enabled
        case .readOnly:
            return .restricted
        case .readOnlyWithNetworkAccess:
            return .enabled
        case let .externalSandbox(networkAccess):
            return networkAccess
        case let .workspaceWrite(_, networkAccess, _, _):
            return networkAccess ? .enabled : .restricted
        }
    }

    private static func writableRoots(for sandboxPolicy: SandboxPolicy?) -> [AbsolutePath]? {
        guard case let .workspaceWrite(writableRoots, _, _, _) = sandboxPolicy,
              !writableRoots.isEmpty
        else {
            return nil
        }
        return writableRoots
    }

    private func appendEnvironments(_ environments: [EnvironmentContextEnvironment], to lines: inout [String]) {
        switch environments.count {
        case 0:
            return
        case 1:
            guard let environment = environments.first else { return }
            lines.append("  <cwd>\(environment.cwd)</cwd>")
            lines.append("  <shell>\(environment.shell)</shell>")
        default:
            lines.append("  <environments>")
            for environment in environments {
                lines.append("    <environment id=\"\(environment.id)\">")
                lines.append("      <cwd>\(environment.cwd)</cwd>")
                lines.append("      <shell>\(environment.shell)</shell>")
                lines.append("    </environment>")
            }
            lines.append("  </environments>")
        }
    }

    private func environmentsEqualExceptShell(
        _ lhs: [EnvironmentContextEnvironment]?,
        _ rhs: [EnvironmentContextEnvironment]?
    ) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil):
            return true
        case let (lhs?, rhs?):
            guard lhs.count == rhs.count else {
                return false
            }
            return zip(lhs, rhs).allSatisfy { left, right in
                left.id == right.id && left.cwd == right.cwd
            }
        default:
            return false
        }
    }

    private func renderNetwork(_ network: EnvironmentContextNetwork) -> String {
        var rendered = #"<network enabled="true">"#
        appendDomainElement("allowed", domains: network.allowedDomains, to: &rendered)
        appendDomainElement("denied", domains: network.deniedDomains, to: &rendered)
        rendered += "</network>"
        return rendered
    }

    private func appendDomainElement(_ name: String, domains: [String], to rendered: inout String) {
        guard !domains.isEmpty else {
            return
        }
        rendered += "<\(name)>\(domains.joined(separator: ","))</\(name)>"
    }

    private static func nonEmpty(_ value: String) -> String? {
        value.isEmpty ? nil : value
    }
}
