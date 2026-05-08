import Foundation

public struct UserInstructions: Equatable, Codable, Sendable {
    public static let legacyOpenTag = "<user_instructions>"
    public static let prefix = "# AGENTS.md instructions for "

    public let directory: String
    public let text: String

    public init(directory: String, text: String) {
        self.directory = directory
        self.text = text
    }

    public static func isUserInstructions(message: [ContentItem]) -> Bool {
        guard message.count == 1, case let .inputText(text) = message[0] else {
            return false
        }
        return text.hasPrefix(prefix) || text.hasPrefix(legacyOpenTag)
    }

    public func asResponseItem() -> ResponseItem {
        .message(
            role: "user",
            content: [.inputText(
                text: "\(Self.prefix)\(directory)\n\n<INSTRUCTIONS>\n\(text)\n</INSTRUCTIONS>"
            )]
        )
    }
}

public struct SkillInstructions: Equatable, Codable, Sendable {
    public static let prefix = "<skill"

    public let name: String
    public let path: String
    public let contents: String

    public init(name: String, path: String, contents: String) {
        self.name = name
        self.path = path
        self.contents = contents
    }

    public static func isSkillInstructions(message: [ContentItem]) -> Bool {
        guard message.count == 1, case let .inputText(text) = message[0] else {
            return false
        }
        return text.hasPrefix(prefix)
    }

    public func asResponseItem() -> ResponseItem {
        .message(
            role: "user",
            content: [.inputText(
                text: "<skill>\n<name>\(name)</name>\n<path>\(path)</path>\n\(contents)\n</skill>"
            )]
        )
    }
}

public struct DeveloperInstructions: Equatable, Codable, Sendable {
    private let text: String

    public init(_ text: String) {
        self.text = text
    }

    public func intoText() -> String {
        text
    }

    public func asResponseItem() -> ResponseItem {
        .message(
            role: "developer",
            content: [.inputText(text: text)]
        )
    }
}
