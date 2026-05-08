import CodexCore
import Foundation

public struct ResumeCommandResolvedSession: Equatable, Sendable {
    public let conversationID: ConversationId
    public let path: String
    public let historyItemCount: Int

    public init(conversationID: ConversationId, path: String, historyItemCount: Int) {
        self.conversationID = conversationID
        self.path = path
        self.historyItemCount = historyItemCount
    }
}

public enum ResumeCommandResolution: Equatable, Sendable {
    case session(ResumeCommandResolvedSession)
    case picker(ConversationsPage)
}

public enum ResumeCommandError: Error, Equatable, CustomStringConvertible, Sendable {
    case noSavedSessions
    case sessionNotFound(String)

    public var description: String {
        switch self {
        case .noSavedSessions:
            return "No saved sessions found."
        case let .sessionNotFound(sessionID):
            return "No saved session found for \(sessionID)."
        }
    }
}

public enum ResumeCommandResolver {
    public static let defaultProvider = "openai"
    public static let pickerPageSize = 20

    public static func resolve(
        _ request: CodexCLI.ResumeCommandRequest,
        codexHome: URL,
        defaultProvider: String = Self.defaultProvider,
        pickerPageSize: Int = Self.pickerPageSize
    ) throws -> ResumeCommandResolution {
        if let sessionID = request.sessionID {
            guard let path = try RolloutListing.findConversationPathByIDString(
                codexHome: codexHome,
                idString: sessionID
            ) else {
                throw ResumeCommandError.sessionNotFound(sessionID)
            }
            return .session(try resolvedSession(path: path))
        }

        if request.last {
            let page = try RolloutListing.getConversations(
                codexHome: codexHome,
                pageSize: 1,
                modelProviders: request.all ? nil : [defaultProvider],
                defaultProvider: defaultProvider
            )
            guard let item = page.items.first else {
                throw ResumeCommandError.noSavedSessions
            }
            return .session(try resolvedSession(path: item.path))
        }

        let page = try RolloutListing.getConversations(
            codexHome: codexHome,
            pageSize: pickerPageSize,
            modelProviders: request.all ? nil : [defaultProvider],
            defaultProvider: defaultProvider
        )
        return .picker(page)
    }

    private static func resolvedSession(path: String) throws -> ResumeCommandResolvedSession {
        let history = try RolloutRecorder.getRolloutHistory(path: URL(fileURLWithPath: path))
        switch history {
        case let .resumed(resumed):
            return ResumeCommandResolvedSession(
                conversationID: resumed.conversationID,
                path: resumed.rolloutPath,
                historyItemCount: resumed.history.count
            )
        case .new:
            throw ResumeCommandError.noSavedSessions
        case .forked:
            throw ResumeCommandError.noSavedSessions
        }
    }
}

public enum ResumeCommandFormatter {
    public static func render(_ resolution: ResumeCommandResolution) -> String {
        switch resolution {
        case let .session(session):
            return [
                "Session: \(session.conversationID.description)",
                "Path: \(session.path)",
                "History items: \(session.historyItemCount)"
            ].joined(separator: "\n")

        case let .picker(page):
            guard !page.items.isEmpty else {
                return "No saved sessions found."
            }

            let rows = page.items.enumerated().map { index, item in
                let updatedAt = item.updatedAt ?? item.createdAt ?? "unknown-time"
                return "\(index + 1). \(updatedAt)\t\(URL(fileURLWithPath: item.path).lastPathComponent)\t\(item.path)"
            }
            return (["Saved sessions:"] + rows).joined(separator: "\n")
        }
    }
}
