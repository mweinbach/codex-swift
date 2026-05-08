import Foundation

public enum ReasoningSummary: String, Codable, CaseIterable, Equatable, Sendable {
    case auto
    case concise
    case detailed
    case none
}

public enum ReasoningEffort: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case none
    case minimal
    case low
    case medium
    case high
    case xhigh
}

public enum Verbosity: String, Codable, CaseIterable, Equatable, Sendable {
    case low
    case medium
    case high
}

public enum WireAPI: String, Codable, CaseIterable, Equatable, Sendable {
    case responses
    case chat
    case compact
}

public enum ForcedLoginMethod: String, Codable, CaseIterable, Equatable, Sendable {
    case chatgpt
    case api
}

public enum TrustLevel: String, Codable, CaseIterable, Equatable, Sendable {
    case trusted
    case untrusted
}
