import Foundation

public enum ReasoningSummary: String, Codable, CaseIterable, Equatable, Sendable {
    case auto
    case concise
    case detailed
    case none
}

public enum Verbosity: String, Codable, CaseIterable, Equatable, Sendable {
    case low
    case medium
    case high
}

public enum ForcedLoginMethod: String, Codable, CaseIterable, Equatable, Sendable {
    case chatgpt
    case api
}

public enum TrustLevel: String, Codable, CaseIterable, Equatable, Sendable {
    case trusted
    case untrusted
}
