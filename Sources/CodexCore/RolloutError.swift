import Foundation

public enum CodexRuntimeError: Error, Equatable, CustomStringConvertible, Sendable {
    case fatal(String)

    public var description: String {
        switch self {
        case let .fatal(message):
            return message
        }
    }
}

public enum RolloutIOErrorKind: Equatable, Sendable {
    case permissionDenied
    case notFound
    case alreadyExists
    case invalidData
    case invalidInput
    case isDirectory
    case notDirectory
    case other
}

public struct RolloutIOFailure: Error, Equatable, CustomStringConvertible, Sendable {
    public let kind: RolloutIOErrorKind
    public let underlyingDescription: String

    public init(kind: RolloutIOErrorKind, underlyingDescription: String) {
        self.kind = kind
        self.underlyingDescription = underlyingDescription
    }

    public var description: String {
        underlyingDescription
    }
}

public struct RolloutSessionInitFailure: Error, Equatable, CustomStringConvertible, Sendable {
    public let description: String
    public let causes: [RolloutIOFailure]

    public init(description: String, causes: [RolloutIOFailure] = []) {
        self.description = description
        self.causes = causes
    }
}

public enum RolloutErrors {
    public static let sessionsSubdirectory = "sessions"
    public static let archivedSessionsSubdirectory = "archived_sessions"

    public static func mapSessionInitError(
        _ error: RolloutSessionInitFailure,
        codexHome: URL
    ) -> CodexRuntimeError {
        for cause in error.causes {
            if let mapped = mapRolloutIOError(cause, codexHome: codexHome) {
                return mapped
            }
        }
        return .fatal("Failed to initialize session: \(error.description)")
    }

    public static func mapRolloutIOError(
        _ error: RolloutIOFailure,
        codexHome: URL
    ) -> CodexRuntimeError? {
        let sessionsDir = codexHome.appendingPathComponent(sessionsSubdirectory, isDirectory: true)
        let hint: String

        switch error.kind {
        case .permissionDenied:
            hint = """
            Codex cannot access session files at \(sessionsDir.path) (permission denied). If sessions were created using sudo, fix ownership: sudo chown -R $(whoami) \(codexHome.path)
            """
        case .notFound:
            hint = """
            Session storage missing at \(sessionsDir.path). Create the directory or choose a different Codex home.
            """
        case .alreadyExists:
            hint = """
            Session storage path \(sessionsDir.path) is blocked by an existing file. Remove or rename it so Codex can create sessions.
            """
        case .invalidData, .invalidInput:
            hint = """
            Session data under \(sessionsDir.path) looks corrupt or unreadable. Clearing the sessions directory may help (this will remove saved conversations).
            """
        case .isDirectory, .notDirectory:
            hint = """
            Session storage path \(sessionsDir.path) has an unexpected type. Ensure it is a directory Codex can use for session files.
            """
        case .other:
            return nil
        }

        return .fatal("\(hint) (underlying error: \(error.underlyingDescription))")
    }
}
