import Foundation

public enum ConfigRequirementsParseError: Error, Equatable, CustomStringConvertible, Sendable {
    case invalidLine(String)
    case invalidApprovalPolicy(String)
    case invalidSandboxMode(String)
    case invalidArray(String)

    public var description: String {
        switch self {
        case let .invalidLine(line):
            return "Invalid requirements line: \(line)"
        case let .invalidApprovalPolicy(value):
            return "Invalid approval policy requirement: \(value)"
        case let .invalidSandboxMode(value):
            return "Invalid sandbox mode requirement: \(value)"
        case let .invalidArray(key):
            return "Invalid array for \(key)"
        }
    }
}

public struct ConfigRequirements: Equatable, Sendable {
    public var approvalPolicy: Constrained<AskForApproval>
    public var sandboxPolicy: Constrained<SandboxPolicy>

    public init(
        approvalPolicy: Constrained<AskForApproval> = .allowAnyFromDefault(),
        sandboxPolicy: Constrained<SandboxPolicy> = .allowAny(.readOnly)
    ) {
        self.approvalPolicy = approvalPolicy
        self.sandboxPolicy = sandboxPolicy
    }

    public static let `default` = ConfigRequirements()
}

public struct ConfigRequirementsToml: Equatable, Sendable {
    public var allowedApprovalPolicies: [AskForApproval]?
    public var allowedSandboxModes: [SandboxModeRequirement]?

    public init(
        allowedApprovalPolicies: [AskForApproval]? = nil,
        allowedSandboxModes: [SandboxModeRequirement]? = nil
    ) {
        self.allowedApprovalPolicies = allowedApprovalPolicies
        self.allowedSandboxModes = allowedSandboxModes
    }

    public mutating func mergeUnsetFields(from other: ConfigRequirementsToml) {
        if allowedApprovalPolicies == nil, let value = other.allowedApprovalPolicies {
            allowedApprovalPolicies = value
        }
        if allowedSandboxModes == nil, let value = other.allowedSandboxModes {
            allowedSandboxModes = value
        }
    }

    public func requirements() throws -> ConfigRequirements {
        let approvalPolicy: Constrained<AskForApproval>
        if let policies = allowedApprovalPolicies {
            guard let first = policies.first else {
                throw ConstraintError.emptyField("allowed_approval_policies")
            }
            approvalPolicy = try Constrained.allowValues(
                first,
                allowed: policies,
                debugDescription: { $0.rustDebugDescription }
            )
        } else {
            approvalPolicy = .allowAnyFromDefault()
        }

        let defaultSandboxPolicy = SandboxPolicy.readOnly
        let sandboxPolicy: Constrained<SandboxPolicy>
        if let modes = allowedSandboxModes {
            guard modes.contains(.readOnly) else {
                throw ConstraintError.invalidValue(
                    "allowed_sandbox_modes",
                    "must include 'read-only' to allow any SandboxPolicy"
                )
            }

            sandboxPolicy = try Constrained(defaultSandboxPolicy) { candidate in
                let mode = SandboxModeRequirement(sandboxPolicy: candidate)
                if modes.contains(mode) {
                    return .success(())
                }
                return .failure(.invalidValue(
                    candidate.rustDebugDescription,
                    SandboxModeRequirement.rustDebugDescription(for: modes)
                ))
            }
        } else {
            sandboxPolicy = .allowAny(defaultSandboxPolicy)
        }

        return ConfigRequirements(
            approvalPolicy: approvalPolicy,
            sandboxPolicy: sandboxPolicy
        )
    }

    public static func parse(_ contents: String) throws -> ConfigRequirementsToml {
        var result = ConfigRequirementsToml()

        for rawLine in contents.split(whereSeparator: \.isNewline) {
            let line = stripComment(from: String(rawLine)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            guard let equalsIndex = line.firstIndex(of: "=") else {
                throw ConfigRequirementsParseError.invalidLine(line)
            }

            let key = String(line[..<equalsIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            let valueStart = line.index(after: equalsIndex)
            let valueText = String(line[valueStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
            switch key {
            case "allowed_approval_policies":
                result.allowedApprovalPolicies = try parseApprovalPolicies(valueText)
            case "allowed_sandbox_modes":
                result.allowedSandboxModes = try parseSandboxModes(valueText)
            default:
                continue
            }
        }

        return result
    }

    private static func parseApprovalPolicies(_ valueText: String) throws -> [AskForApproval] {
        try stringArray(valueText, key: "allowed_approval_policies").map { value in
            guard let policy = AskForApproval(rawValue: value) else {
                throw ConfigRequirementsParseError.invalidApprovalPolicy(value)
            }
            return policy
        }
    }

    private static func parseSandboxModes(_ valueText: String) throws -> [SandboxModeRequirement] {
        try stringArray(valueText, key: "allowed_sandbox_modes").map { value in
            guard let mode = SandboxModeRequirement(rawValue: value) else {
                throw ConfigRequirementsParseError.invalidSandboxMode(value)
            }
            return mode
        }
    }

    private static func stringArray(_ valueText: String, key: String) throws -> [String] {
        guard case let .array(values) = try ConfigValueParser.parseTomlLiteral(valueText) else {
            throw ConfigRequirementsParseError.invalidArray(key)
        }
        return try values.map { value in
            guard case let .string(string) = value else {
                throw ConfigRequirementsParseError.invalidArray(key)
            }
            return string
        }
    }

    private static func stripComment(from line: String) -> String {
        var quote: Character?
        var previousWasBackslash = false

        for index in line.indices {
            let character = line[index]
            if let activeQuote = quote {
                if character == activeQuote && !previousWasBackslash {
                    quote = nil
                }
                previousWasBackslash = character == "\\" && !previousWasBackslash
                if character != "\\" {
                    previousWasBackslash = false
                }
                continue
            }

            if character == "\"" || character == "'" {
                quote = character
                previousWasBackslash = false
                continue
            }

            if character == "#" {
                return String(line[..<index])
            }
        }

        return line
    }
}

public enum SandboxModeRequirement: String, Codable, CaseIterable, Equatable, Sendable {
    case readOnly = "read-only"
    case workspaceWrite = "workspace-write"
    case dangerFullAccess = "danger-full-access"
    case externalSandbox = "external-sandbox"

    public init(sandboxMode: SandboxMode) {
        switch sandboxMode {
        case .readOnly:
            self = .readOnly
        case .workspaceWrite:
            self = .workspaceWrite
        case .dangerFullAccess:
            self = .dangerFullAccess
        }
    }

    public init(sandboxPolicy: SandboxPolicy) {
        switch sandboxPolicy {
        case .readOnly:
            self = .readOnly
        case .workspaceWrite:
            self = .workspaceWrite
        case .dangerFullAccess:
            self = .dangerFullAccess
        case .externalSandbox:
            self = .externalSandbox
        }
    }

    public var rustDebugDescription: String {
        switch self {
        case .readOnly:
            return "ReadOnly"
        case .workspaceWrite:
            return "WorkspaceWrite"
        case .dangerFullAccess:
            return "DangerFullAccess"
        case .externalSandbox:
            return "ExternalSandbox"
        }
    }

    public static func rustDebugDescription(for modes: [SandboxModeRequirement]) -> String {
        "[" + modes.map(\.rustDebugDescription).joined(separator: ", ") + "]"
    }
}

extension AskForApproval {
    public var rustDebugDescription: String {
        switch self {
        case .unlessTrusted:
            return "UnlessTrusted"
        case .onFailure:
            return "OnFailure"
        case .onRequest:
            return "OnRequest"
        case .never:
            return "Never"
        }
    }
}

extension SandboxPolicy {
    public var rustDebugDescription: String {
        switch self {
        case .dangerFullAccess:
            return "DangerFullAccess"
        case .readOnly:
            return "ReadOnly"
        case let .externalSandbox(networkAccess):
            return "ExternalSandbox { network_access: \(networkAccess.rustDebugDescription) }"
        case let .workspaceWrite(writableRoots, networkAccess, excludeTmpdirEnvVar, excludeSlashTmp):
            return "WorkspaceWrite { writable_roots: \(writableRoots), network_access: \(networkAccess), exclude_tmpdir_env_var: \(excludeTmpdirEnvVar), exclude_slash_tmp: \(excludeSlashTmp) }"
        }
    }
}

extension NetworkAccess {
    public var rustDebugDescription: String {
        switch self {
        case .restricted:
            return "Restricted"
        case .enabled:
            return "Enabled"
        }
    }
}
