import Foundation

public enum CustomPromptConstants {
    public static let promptsCommandPrefix = "prompts"
}

public struct CustomPrompt: Equatable, Codable, Sendable {
    public let name: String
    public let path: String
    public let content: String
    public let description: String?
    public let argumentHint: String?

    private enum CodingKeys: String, CodingKey {
        case name
        case path
        case content
        case description
        case argumentHint = "argument_hint"
    }

    public init(
        name: String,
        path: String,
        content: String,
        description: String? = nil,
        argumentHint: String? = nil
    ) {
        self.name = name
        self.path = path
        self.content = content
        self.description = description
        self.argumentHint = argumentHint
    }
}
