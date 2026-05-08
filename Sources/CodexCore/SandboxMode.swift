import Foundation

public enum SandboxMode: String, Equatable, Sendable {
    case readOnly
    case workspaceWrite
    case dangerFullAccess
}

public enum SandboxModeCLIArgument: String, CaseIterable, Equatable, Sendable {
    case readOnly = "read-only"
    case workspaceWrite = "workspace-write"
    case dangerFullAccess = "danger-full-access"

    public var sandboxMode: SandboxMode {
        switch self {
        case .readOnly:
            return .readOnly
        case .workspaceWrite:
            return .workspaceWrite
        case .dangerFullAccess:
            return .dangerFullAccess
        }
    }
}
