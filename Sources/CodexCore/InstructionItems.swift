import Foundation

public struct UserInstructions: Equatable, Codable, Sendable {
    public static let legacyOpenTag = "<user_instructions>"
    public static let legacyCloseTag = "</user_instructions>"
    public static let prefix = "# AGENTS.md instructions for "
    public static let closeTag = "</INSTRUCTIONS>"

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
        return matchesText(text)
    }

    public static func matchesText(_ text: String) -> Bool {
        contextualFragmentMatches(text, startMarker: prefix, endMarker: closeTag)
            || contextualFragmentMatches(text, startMarker: legacyOpenTag, endMarker: legacyCloseTag)
    }

    public func intoText() -> String {
        "\(Self.prefix)\(directory)\n\n<INSTRUCTIONS>\n\(text)\n</INSTRUCTIONS>"
    }

    public func asResponseItem() -> ResponseItem {
        .message(
            role: "user",
            content: [.inputText(
                text: intoText()
            )]
        )
    }
}

public struct SkillInstructions: Equatable, Codable, Sendable {
    public static let prefix = "<skill>"
    public static let closeTag = "</skill>"

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
        return matchesText(text)
    }

    public static func matchesText(_ text: String) -> Bool {
        contextualFragmentMatches(text, startMarker: prefix, endMarker: closeTag)
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

func contextualFragmentMatches(_ text: String, startMarker: String, endMarker: String) -> Bool {
    guard !startMarker.isEmpty, !endMarker.isEmpty else {
        return false
    }
    let leadingTrimmed = text.trimmingPrefix { $0.isWhitespace }
    guard leadingTrimmed.count >= startMarker.count else {
        return false
    }
    let startCandidate = String(leadingTrimmed.prefix(startMarker.count))
    guard startCandidate.caseInsensitiveCompare(startMarker) == .orderedSame else {
        return false
    }

    let trailingTrimmed = leadingTrimmed.trimmingSuffix { $0.isWhitespace }
    guard trailingTrimmed.count >= endMarker.count else {
        return false
    }
    let endCandidate = String(trailingTrimmed.suffix(endMarker.count))
    return endCandidate.caseInsensitiveCompare(endMarker) == .orderedSame
}

private extension String {
    func trimmingPrefix(where shouldTrim: (Character) -> Bool) -> String {
        String(drop(while: shouldTrim))
    }

    func trimmingSuffix(where shouldTrim: (Character) -> Bool) -> String {
        String(reversed().drop(while: shouldTrim).reversed())
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
