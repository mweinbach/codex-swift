import Foundation

public enum SandboxPermissions: String, Codable, Equatable, Sendable {
    case useDefault = "use_default"
    case requireEscalated = "require_escalated"

    public var requiresEscalatedPermissions: Bool {
        self == .requireEscalated
    }
}

public enum ContentItem: Equatable, Codable, Sendable {
    case inputText(text: String)
    case inputImage(imageURL: String)
    case outputText(text: String)

    private enum CodingKeys: String, CodingKey {
        case type
        case text
        case imageURL = "image_url"
    }

    private enum ItemType: String, Codable {
        case inputText = "input_text"
        case inputImage = "input_image"
        case outputText = "output_text"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(ItemType.self, forKey: .type) {
        case .inputText:
            self = .inputText(text: try container.decode(String.self, forKey: .text))
        case .inputImage:
            self = .inputImage(imageURL: try container.decode(String.self, forKey: .imageURL))
        case .outputText:
            self = .outputText(text: try container.decode(String.self, forKey: .text))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .inputText(text):
            try container.encode(ItemType.inputText, forKey: .type)
            try container.encode(text, forKey: .text)
        case let .inputImage(imageURL):
            try container.encode(ItemType.inputImage, forKey: .type)
            try container.encode(imageURL, forKey: .imageURL)
        case let .outputText(text):
            try container.encode(ItemType.outputText, forKey: .type)
            try container.encode(text, forKey: .text)
        }
    }
}

public enum FunctionCallOutputContentItem: Equatable, Codable, Sendable {
    case inputText(text: String)
    case inputImage(imageURL: String)

    private enum CodingKeys: String, CodingKey {
        case type
        case text
        case imageURL = "image_url"
    }

    private enum ItemType: String, Codable {
        case inputText = "input_text"
        case inputImage = "input_image"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(ItemType.self, forKey: .type) {
        case .inputText:
            self = .inputText(text: try container.decode(String.self, forKey: .text))
        case .inputImage:
            self = .inputImage(imageURL: try container.decode(String.self, forKey: .imageURL))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .inputText(text):
            try container.encode(ItemType.inputText, forKey: .type)
            try container.encode(text, forKey: .text)
        case let .inputImage(imageURL):
            try container.encode(ItemType.inputImage, forKey: .type)
            try container.encode(imageURL, forKey: .imageURL)
        }
    }
}

public struct FunctionCallOutputPayload: Equatable, Codable, CustomStringConvertible, Sendable {
    public let content: String
    public let contentItems: [FunctionCallOutputContentItem]?
    public let success: Bool?

    public init(
        content: String,
        contentItems: [FunctionCallOutputContentItem]? = nil,
        success: Bool? = nil
    ) {
        self.content = content
        self.contentItems = contentItems
        self.success = success
    }

    public var description: String {
        content
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let text = try? container.decode(String.self) {
            self.init(content: text)
            return
        }

        let items = try container.decode([FunctionCallOutputContentItem].self)
        let content = try String(data: JSONEncoder.codexCompact.encode(items), encoding: .utf8) ?? "[]"
        self.init(content: content, contentItems: items)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let contentItems {
            try container.encode(contentItems)
        } else {
            try container.encode(content)
        }
    }
}

public enum ResponseInputItem: Equatable, Codable, Sendable {
    case message(role: String, content: [ContentItem])
    case functionCallOutput(callID: String, output: FunctionCallOutputPayload)
    case customToolCallOutput(callID: String, output: String)

    private enum CodingKeys: String, CodingKey {
        case type
        case role
        case content
        case callID = "call_id"
        case output
    }

    private enum ItemType: String, Codable {
        case message
        case functionCallOutput = "function_call_output"
        case customToolCallOutput = "custom_tool_call_output"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(ItemType.self, forKey: .type) {
        case .message:
            self = .message(
                role: try container.decode(String.self, forKey: .role),
                content: try container.decode([ContentItem].self, forKey: .content)
            )
        case .functionCallOutput:
            self = .functionCallOutput(
                callID: try container.decode(String.self, forKey: .callID),
                output: try container.decode(FunctionCallOutputPayload.self, forKey: .output)
            )
        case .customToolCallOutput:
            self = .customToolCallOutput(
                callID: try container.decode(String.self, forKey: .callID),
                output: try container.decode(String.self, forKey: .output)
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .message(role, content):
            try container.encode(ItemType.message, forKey: .type)
            try container.encode(role, forKey: .role)
            try container.encode(content, forKey: .content)
        case let .functionCallOutput(callID, output):
            try container.encode(ItemType.functionCallOutput, forKey: .type)
            try container.encode(callID, forKey: .callID)
            try container.encode(output, forKey: .output)
        case let .customToolCallOutput(callID, output):
            try container.encode(ItemType.customToolCallOutput, forKey: .type)
            try container.encode(callID, forKey: .callID)
            try container.encode(output, forKey: .output)
        }
    }
}

public enum LocalShellStatus: String, Codable, Equatable, Sendable {
    case completed
    case inProgress = "in_progress"
    case incomplete
}

public enum LocalShellAction: Equatable, Codable, Sendable {
    case exec(LocalShellExecAction)

    private enum CodingKeys: String, CodingKey {
        case type
    }

    private enum ActionType: String, Codable {
        case exec
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(ActionType.self, forKey: .type) {
        case .exec:
            self = .exec(try LocalShellExecAction(from: decoder))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .exec(action):
            try container.encode(ActionType.exec, forKey: .type)
            try action.encode(to: encoder)
        }
    }
}

public struct LocalShellExecAction: Equatable, Codable, Sendable {
    public let command: [String]
    public let timeoutMS: UInt64?
    public let workingDirectory: String?
    public let env: [String: String]?
    public let user: String?

    private enum CodingKeys: String, CodingKey {
        case command
        case timeoutMS = "timeout_ms"
        case workingDirectory = "working_directory"
        case env
        case user
    }

    public init(
        command: [String],
        timeoutMS: UInt64? = nil,
        workingDirectory: String? = nil,
        env: [String: String]? = nil,
        user: String? = nil
    ) {
        self.command = command
        self.timeoutMS = timeoutMS
        self.workingDirectory = workingDirectory
        self.env = env
        self.user = user
    }
}

public enum WebSearchAction: Equatable, Codable, Sendable {
    case search(query: String?)
    case openPage(url: String?)
    case findInPage(url: String?, pattern: String?)
    case other

    private enum CodingKeys: String, CodingKey {
        case type
        case query
        case url
        case pattern
    }

    private enum ActionType: String, Codable {
        case search
        case openPage = "open_page"
        case findInPage = "find_in_page"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let type = try? container.decode(ActionType.self, forKey: .type) else {
            self = .other
            return
        }
        switch type {
        case .search:
            self = .search(query: try container.decodeIfPresent(String.self, forKey: .query))
        case .openPage:
            self = .openPage(url: try container.decodeIfPresent(String.self, forKey: .url))
        case .findInPage:
            self = .findInPage(
                url: try container.decodeIfPresent(String.self, forKey: .url),
                pattern: try container.decodeIfPresent(String.self, forKey: .pattern)
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .search(query):
            try container.encode(ActionType.search, forKey: .type)
            try container.encodeIfPresent(query, forKey: .query)
        case let .openPage(url):
            try container.encode(ActionType.openPage, forKey: .type)
            try container.encodeIfPresent(url, forKey: .url)
        case let .findInPage(url, pattern):
            try container.encode(ActionType.findInPage, forKey: .type)
            try container.encodeIfPresent(url, forKey: .url)
            try container.encodeIfPresent(pattern, forKey: .pattern)
        case .other:
            try container.encode("other", forKey: .type)
        }
    }
}

public enum ReasoningItemReasoningSummary: Equatable, Codable, Sendable {
    case summaryText(text: String)

    private enum CodingKeys: String, CodingKey {
        case type
        case text
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        _ = try container.decode(String.self, forKey: .type)
        self = .summaryText(text: try container.decode(String.self, forKey: .text))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("summary_text", forKey: .type)
        switch self {
        case let .summaryText(text):
            try container.encode(text, forKey: .text)
        }
    }
}

public enum ReasoningItemContent: Equatable, Codable, Sendable {
    case reasoningText(text: String)
    case text(String)

    private enum CodingKeys: String, CodingKey {
        case type
        case text
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .type) {
        case "reasoning_text":
            self = .reasoningText(text: try container.decode(String.self, forKey: .text))
        default:
            self = .text(try container.decode(String.self, forKey: .text))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .reasoningText(text):
            try container.encode("reasoning_text", forKey: .type)
            try container.encode(text, forKey: .text)
        case let .text(text):
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .text)
        }
    }
}

public struct ShellToolCallParams: Equatable, Decodable, Sendable {
    public let command: [String]
    public let workdir: String?
    public let timeoutMS: UInt64?
    public let sandboxPermissions: SandboxPermissions?
    public let justification: String?

    private enum CodingKeys: String, CodingKey {
        case command
        case workdir
        case timeout
        case timeoutMS = "timeout_ms"
        case sandboxPermissions = "sandbox_permissions"
        case justification
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.command = try container.decode([String].self, forKey: .command)
        self.workdir = try container.decodeIfPresent(String.self, forKey: .workdir)
        self.timeoutMS = try container.decodeIfPresent(UInt64.self, forKey: .timeoutMS)
            ?? container.decodeIfPresent(UInt64.self, forKey: .timeout)
        self.sandboxPermissions = try container.decodeIfPresent(SandboxPermissions.self, forKey: .sandboxPermissions)
        self.justification = try container.decodeIfPresent(String.self, forKey: .justification)
    }
}

public struct ShellCommandToolCallParams: Equatable, Decodable, Sendable {
    public let command: String
    public let workdir: String?
    public let login: Bool?
    public let timeoutMS: UInt64?
    public let sandboxPermissions: SandboxPermissions?
    public let justification: String?

    private enum CodingKeys: String, CodingKey {
        case command
        case workdir
        case login
        case timeout
        case timeoutMS = "timeout_ms"
        case sandboxPermissions = "sandbox_permissions"
        case justification
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.command = try container.decode(String.self, forKey: .command)
        self.workdir = try container.decodeIfPresent(String.self, forKey: .workdir)
        self.login = try container.decodeIfPresent(Bool.self, forKey: .login)
        self.timeoutMS = try container.decodeIfPresent(UInt64.self, forKey: .timeoutMS)
            ?? container.decodeIfPresent(UInt64.self, forKey: .timeout)
        self.sandboxPermissions = try container.decodeIfPresent(SandboxPermissions.self, forKey: .sandboxPermissions)
        self.justification = try container.decodeIfPresent(String.self, forKey: .justification)
    }
}

public enum ResponseItem: Equatable, Codable, Sendable {
    case webSearchCall(status: String?, action: WebSearchAction)
    case compaction(encryptedContent: String)
    case other

    private enum CodingKeys: String, CodingKey {
        case type
        case status
        case action
        case encryptedContent = "encrypted_content"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .type) {
        case "web_search_call":
            self = .webSearchCall(
                status: try container.decodeIfPresent(String.self, forKey: .status),
                action: try container.decode(WebSearchAction.self, forKey: .action)
            )
        case "compaction", "compaction_summary":
            self = .compaction(encryptedContent: try container.decode(String.self, forKey: .encryptedContent))
        default:
            self = .other
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .webSearchCall(status, action):
            try container.encode("web_search_call", forKey: .type)
            try container.encodeIfPresent(status, forKey: .status)
            try container.encode(action, forKey: .action)
        case let .compaction(encryptedContent):
            try container.encode("compaction", forKey: .type)
            try container.encode(encryptedContent, forKey: .encryptedContent)
        case .other:
            try container.encode("other", forKey: .type)
        }
    }
}

private extension JSONEncoder {
    static var codexCompact: JSONEncoder {
        JSONEncoder()
    }
}
