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

public enum ImageDetail: String, Codable, Equatable, Sendable {
    case auto
    case low
    case high
    case original
}

public let defaultImageDetail: ImageDetail = .high

public enum FunctionCallOutputContentItem: Equatable, Codable, Sendable {
    case inputText(text: String)
    case inputImage(imageURL: String, detail: ImageDetail? = nil)

    private enum CodingKeys: String, CodingKey {
        case type
        case text
        case imageURL = "image_url"
        case detail
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
            self = .inputImage(
                imageURL: try container.decode(String.self, forKey: .imageURL),
                detail: try container.decodeIfPresent(ImageDetail.self, forKey: .detail)
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .inputText(text):
            try container.encode(ItemType.inputText, forKey: .type)
            try container.encode(text, forKey: .text)
        case let .inputImage(imageURL, detail):
            try container.encode(ItemType.inputImage, forKey: .type)
            try container.encode(imageURL, forKey: .imageURL)
            try container.encodeIfPresent(detail, forKey: .detail)
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

    public init(callToolResult: McpCallToolResult) {
        let isSuccess = callToolResult.isError != true

        if let structuredContent = callToolResult.structuredContent,
           structuredContent != .null
        {
            do {
                let data = try JSONEncoder.codexCompact.encode(structuredContent)
                self.init(
                    content: String(data: data, encoding: .utf8) ?? "null",
                    success: isSuccess
                )
            } catch {
                self.init(content: String(describing: error), success: false)
            }
            return
        }

        do {
            let data = try JSONEncoder.codexCompact.encode(callToolResult.content)
            let serializedContent = String(data: data, encoding: .utf8) ?? "[]"
            self.init(
                content: serializedContent,
                contentItems: Self.contentItems(from: callToolResult.content),
                success: isSuccess
            )
        } catch {
            self.init(content: String(describing: error), success: false)
        }
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

    private static func contentItems(
        from blocks: [McpContentBlock]
    ) -> [FunctionCallOutputContentItem]? {
        var sawImage = false
        var items: [FunctionCallOutputContentItem] = []

        for block in blocks {
            switch block {
            case let .text(text):
                items.append(.inputText(text: text.text))
            case let .image(image):
                sawImage = true
                let imageURL: String
                if image.data.hasPrefix("data:") {
                    imageURL = image.data
                } else {
                    imageURL = "data:\(image.mimeType);base64,\(image.data)"
                }
                items.append(.inputImage(imageURL: imageURL))
            case .audio,
                 .resourceLink,
                 .embeddedResource:
                return nil
            }
        }

        return sawImage ? items : nil
    }
}

public enum MessagePhase: String, Codable, Equatable, Sendable {
    case commentary
    case finalAnswer = "final_answer"
}

public enum ResponseInputItem: Equatable, Codable, Sendable {
    case message(role: String, content: [ContentItem], phase: MessagePhase? = nil)
    case functionCallOutput(callID: String, output: FunctionCallOutputPayload)
    case mcpToolCallOutput(callID: String, result: McpToolCallResult)
    case customToolCallOutput(callID: String, name: String? = nil, output: FunctionCallOutputPayload)
    case toolSearchOutput(callID: String, status: String, execution: String, tools: [JSONValue])

    private enum CodingKeys: String, CodingKey {
        case type
        case role
        case content
        case phase
        case callID = "call_id"
        case name
        case output
        case legacyResult = "result"
        case status
        case execution
        case tools
    }

    private enum ItemType: String, Codable {
        case message
        case functionCallOutput = "function_call_output"
        case mcpToolCallOutput = "mcp_tool_call_output"
        case customToolCallOutput = "custom_tool_call_output"
        case toolSearchOutput = "tool_search_output"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(ItemType.self, forKey: .type) {
        case .message:
            self = .message(
                role: try container.decode(String.self, forKey: .role),
                content: try container.decode([ContentItem].self, forKey: .content),
                phase: try container.decodeIfPresent(MessagePhase.self, forKey: .phase)
            )
        case .functionCallOutput:
            self = .functionCallOutput(
                callID: try container.decode(String.self, forKey: .callID),
                output: try container.decode(FunctionCallOutputPayload.self, forKey: .output)
            )
        case .mcpToolCallOutput:
            self = .mcpToolCallOutput(
                callID: try container.decode(String.self, forKey: .callID),
                result: try container.decodeIfPresent(McpToolCallResult.self, forKey: .output)
                    ?? container.decode(McpToolCallResult.self, forKey: .legacyResult)
            )
        case .customToolCallOutput:
            self = .customToolCallOutput(
                callID: try container.decode(String.self, forKey: .callID),
                name: try container.decodeIfPresent(String.self, forKey: .name),
                output: try container.decode(FunctionCallOutputPayload.self, forKey: .output)
            )
        case .toolSearchOutput:
            self = .toolSearchOutput(
                callID: try container.decode(String.self, forKey: .callID),
                status: try container.decode(String.self, forKey: .status),
                execution: try container.decode(String.self, forKey: .execution),
                tools: try container.decode([JSONValue].self, forKey: .tools)
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .message(role, content, phase):
            try container.encode(ItemType.message, forKey: .type)
            try container.encode(role, forKey: .role)
            try container.encode(content, forKey: .content)
            try container.encodeIfPresent(phase, forKey: .phase)
        case let .functionCallOutput(callID, output):
            try container.encode(ItemType.functionCallOutput, forKey: .type)
            try container.encode(callID, forKey: .callID)
            try container.encode(output, forKey: .output)
        case let .mcpToolCallOutput(callID, result):
            try container.encode(ItemType.mcpToolCallOutput, forKey: .type)
            try container.encode(callID, forKey: .callID)
            try container.encode(result, forKey: .output)
        case let .customToolCallOutput(callID, name, output):
            try container.encode(ItemType.customToolCallOutput, forKey: .type)
            try container.encode(callID, forKey: .callID)
            try container.encodeIfPresent(name, forKey: .name)
            try container.encode(output, forKey: .output)
        case let .toolSearchOutput(callID, status, execution, tools):
            try container.encode(ItemType.toolSearchOutput, forKey: .type)
            try container.encode(callID, forKey: .callID)
            try container.encode(status, forKey: .status)
            try container.encode(execution, forKey: .execution)
            try container.encode(tools, forKey: .tools)
        }
    }
}

public extension ResponseInputItem {
    static func customToolCallOutput(callID: String, name: String? = nil, output: String) -> ResponseInputItem {
        .customToolCallOutput(callID: callID, name: name, output: FunctionCallOutputPayload(content: output))
    }

    init(userInputs: [UserInput]) {
        let content = userInputs.compactMap(Self.contentItem)
        self = .message(role: "user", content: content)
    }

    private static func contentItem(from input: UserInput) -> ContentItem? {
        switch input {
        case let .text(text):
            return .inputText(text: text)
        case let .image(imageURL):
            return .inputImage(imageURL: imageURL)
        case let .localImage(path):
            return localImageContentItem(path: path)
        case .skill:
            return nil
        }
    }

    private static func localImageContentItem(path: String) -> ContentItem {
        do {
            let image = try LocalImageProcessor.loadAndResizeToFit(path: URL(fileURLWithPath: path))
            return .inputImage(imageURL: image.dataURL)
        } catch let error as ImageProcessingError {
            if case .read = error {
                return localImageErrorPlaceholder(path: path, error: error.description)
            }
            if error.isInvalidImage {
                return invalidImageErrorPlaceholder(path: path, error: error.description)
            }

            guard let mime = LocalImageProcessor.mimeType(forPath: path) else {
                return localImageErrorPlaceholder(
                    path: path,
                    error: "unsupported MIME type (unknown)"
                )
            }
            if !mime.hasPrefix("image/") {
                return localImageErrorPlaceholder(
                    path: path,
                    error: "unsupported MIME type `\(mime)`"
                )
            }
            return unsupportedImageErrorPlaceholder(path: path, mime: mime)
        } catch {
            return localImageErrorPlaceholder(path: path, error: String(describing: error))
        }
    }

    private static func localImageErrorPlaceholder(path: String, error: String) -> ContentItem {
        .inputText(text: "Codex could not read the local image at `\(path)`: \(error)")
    }

    private static func invalidImageErrorPlaceholder(path: String, error: String) -> ContentItem {
        .inputText(text: "Image located at `\(path)` is invalid: \(error)")
    }

    private static func unsupportedImageErrorPlaceholder(path: String, mime: String) -> ContentItem {
        .inputText(text: "Codex cannot attach image at `\(path)`: unsupported image format `\(mime)`.")
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
    case search(query: String?, queries: [String]? = nil)
    case openPage(url: String?)
    case findInPage(url: String?, pattern: String?)
    case other

    private enum CodingKeys: String, CodingKey {
        case type
        case query
        case queries
        case url
        case pattern
    }

    private enum ActionType: String, Codable {
        case search
        case openPage = "open_page"
        case findInPage = "find_in_page"
    }

    public var detail: String {
        switch self {
        case let .search(query, queries):
            if let query, !query.isEmpty {
                return query
            }
            let first = queries?.first ?? ""
            if let queries, queries.count > 1, !first.isEmpty {
                return "\(first) ..."
            }
            return first

        case let .openPage(url):
            return url ?? ""

        case let .findInPage(url, pattern):
            switch (pattern, url) {
            case let (pattern?, url?):
                return "'\(pattern)' in \(url)"
            case let (pattern?, nil):
                return "'\(pattern)'"
            case let (nil, url?):
                return url
            case (nil, nil):
                return ""
            }

        case .other:
            return ""
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let type = try? container.decode(ActionType.self, forKey: .type) else {
            self = .other
            return
        }
        switch type {
        case .search:
            self = .search(
                query: try container.decodeIfPresent(String.self, forKey: .query),
                queries: try container.decodeIfPresent([String].self, forKey: .queries)
            )
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
        case let .search(query, queries):
            try container.encode(ActionType.search, forKey: .type)
            try container.encodeIfPresent(query, forKey: .query)
            try container.encodeIfPresent(queries, forKey: .queries)
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

public struct GhostCommit: Equatable, Codable, Sendable {
    public let id: String
    public let parent: String?
    public let preexistingUntrackedFiles: [String]
    public let preexistingUntrackedDirs: [String]

    private enum CodingKeys: String, CodingKey {
        case id
        case parent
        case preexistingUntrackedFiles = "preexisting_untracked_files"
        case preexistingUntrackedDirs = "preexisting_untracked_dirs"
    }

    public init(
        id: String,
        parent: String? = nil,
        preexistingUntrackedFiles: [String] = [],
        preexistingUntrackedDirs: [String] = []
    ) {
        self.id = id
        self.parent = parent
        self.preexistingUntrackedFiles = preexistingUntrackedFiles
        self.preexistingUntrackedDirs = preexistingUntrackedDirs
    }
}

public struct ShellToolCallParams: Equatable, Decodable, Sendable {
    public let command: [String]
    public let workdir: String?
    public let timeoutMS: UInt64?
    public let sandboxPermissions: SandboxPermissions?
    public let prefixRule: [String]?
    public let additionalPermissions: RequestPermissionProfile?
    public let justification: String?

    private enum CodingKeys: String, CodingKey {
        case command
        case workdir
        case timeout
        case timeoutMS = "timeout_ms"
        case sandboxPermissions = "sandbox_permissions"
        case prefixRule = "prefix_rule"
        case additionalPermissions = "additional_permissions"
        case justification
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.command = try container.decode([String].self, forKey: .command)
        self.workdir = try container.decodeIfPresent(String.self, forKey: .workdir)
        self.timeoutMS = try container.decodeIfPresent(UInt64.self, forKey: .timeoutMS)
            ?? container.decodeIfPresent(UInt64.self, forKey: .timeout)
        self.sandboxPermissions = try container.decodeIfPresent(SandboxPermissions.self, forKey: .sandboxPermissions)
        self.prefixRule = try container.decodeIfPresent([String].self, forKey: .prefixRule)
        self.additionalPermissions = try container.decodeIfPresent(
            RequestPermissionProfile.self,
            forKey: .additionalPermissions
        )
        self.justification = try container.decodeIfPresent(String.self, forKey: .justification)
    }
}

public struct ShellCommandToolCallParams: Equatable, Decodable, Sendable {
    public let command: String
    public let workdir: String?
    public let login: Bool?
    public let timeoutMS: UInt64?
    public let sandboxPermissions: SandboxPermissions?
    public let prefixRule: [String]?
    public let additionalPermissions: RequestPermissionProfile?
    public let justification: String?

    private enum CodingKeys: String, CodingKey {
        case command
        case workdir
        case login
        case timeout
        case timeoutMS = "timeout_ms"
        case sandboxPermissions = "sandbox_permissions"
        case prefixRule = "prefix_rule"
        case additionalPermissions = "additional_permissions"
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
        self.prefixRule = try container.decodeIfPresent([String].self, forKey: .prefixRule)
        self.additionalPermissions = try container.decodeIfPresent(
            RequestPermissionProfile.self,
            forKey: .additionalPermissions
        )
        self.justification = try container.decodeIfPresent(String.self, forKey: .justification)
    }
}

public struct ExecCommandToolCallParams: Equatable, Decodable, Sendable {
    public let cmd: String
    public let workdir: String?
    public let shell: String?
    public let login: Bool
    public let yieldTimeMS: UInt64
    public let maxOutputTokens: Int?
    public let sandboxPermissions: SandboxPermissions
    public let justification: String?

    private enum CodingKeys: String, CodingKey {
        case cmd
        case workdir
        case shell
        case login
        case yieldTimeMS = "yield_time_ms"
        case maxOutputTokens = "max_output_tokens"
        case sandboxPermissions = "sandbox_permissions"
        case justification
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.cmd = try container.decode(String.self, forKey: .cmd)
        self.workdir = try container.decodeIfPresent(String.self, forKey: .workdir)
        self.shell = try container.decodeIfPresent(String.self, forKey: .shell)
        self.login = try container.decodeIfPresent(Bool.self, forKey: .login) ?? true
        self.yieldTimeMS = try container.decodeIfPresent(UInt64.self, forKey: .yieldTimeMS) ?? 10_000
        self.maxOutputTokens = try container.decodeIfPresent(Int.self, forKey: .maxOutputTokens)
        self.sandboxPermissions = try container.decodeIfPresent(
            SandboxPermissions.self,
            forKey: .sandboxPermissions
        ) ?? .useDefault
        self.justification = try container.decodeIfPresent(String.self, forKey: .justification)
    }
}

public struct WriteStdinToolCallParams: Equatable, Decodable, Sendable {
    public let sessionID: Int
    public let chars: String
    public let yieldTimeMS: UInt64
    public let maxOutputTokens: Int?

    private enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case chars
        case yieldTimeMS = "yield_time_ms"
        case maxOutputTokens = "max_output_tokens"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.sessionID = try container.decode(Int.self, forKey: .sessionID)
        self.chars = try container.decodeIfPresent(String.self, forKey: .chars) ?? ""
        self.yieldTimeMS = try container.decodeIfPresent(UInt64.self, forKey: .yieldTimeMS) ?? 250
        self.maxOutputTokens = try container.decodeIfPresent(Int.self, forKey: .maxOutputTokens)
    }
}

public enum ResponseItem: Equatable, Codable, Sendable {
    case message(id: String? = nil, role: String, content: [ContentItem], phase: MessagePhase? = nil)
    case reasoning(
        id: String,
        summary: [ReasoningItemReasoningSummary],
        content: [ReasoningItemContent]? = nil,
        encryptedContent: String? = nil
    )
    case localShellCall(id: String? = nil, callID: String?, status: LocalShellStatus, action: LocalShellAction)
    case functionCall(id: String? = nil, name: String, namespace: String? = nil, arguments: String, callID: String)
    case toolSearchCall(
        id: String? = nil,
        callID: String? = nil,
        status: String? = nil,
        execution: String,
        arguments: JSONValue
    )
    case functionCallOutput(callID: String, output: FunctionCallOutputPayload)
    case customToolCall(id: String? = nil, status: String? = nil, callID: String, name: String, input: String)
    case customToolCallOutput(callID: String, name: String? = nil, output: FunctionCallOutputPayload)
    case toolSearchOutput(callID: String? = nil, status: String, execution: String, tools: [JSONValue])
    case webSearchCall(id: String? = nil, status: String? = nil, action: WebSearchAction?)
    case imageGenerationCall(id: String, status: String, revisedPrompt: String? = nil, result: String)
    case ghostSnapshot(ghostCommit: GhostCommit)
    case compaction(encryptedContent: String)
    case contextCompaction(encryptedContent: String? = nil)
    case knownPersisted(type: String)
    case other

    private enum CodingKeys: String, CodingKey {
        case type
        case id
        case role
        case content
        case phase
        case summary
        case callID = "call_id"
        case name
        case namespace
        case arguments
        case input
        case output
        case status
        case action
        case execution
        case tools
        case revisedPrompt = "revised_prompt"
        case result
        case ghostCommit = "ghost_commit"
        case encryptedContent = "encrypted_content"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "message":
            self = .message(
                id: try container.decodeIfPresent(String.self, forKey: .id),
                role: try container.decode(String.self, forKey: .role),
                content: try container.decode([ContentItem].self, forKey: .content),
                phase: try container.decodeIfPresent(MessagePhase.self, forKey: .phase)
            )
        case "reasoning":
            if let summary = try? container.decode([ReasoningItemReasoningSummary].self, forKey: .summary)
            {
                self = .reasoning(
                    id: try container.decodeIfPresent(String.self, forKey: .id) ?? "",
                    summary: summary,
                    content: try container.decodeIfPresent([ReasoningItemContent].self, forKey: .content),
                    encryptedContent: try container.decodeIfPresent(String.self, forKey: .encryptedContent)
                )
            } else {
                self = .knownPersisted(type: type)
            }
        case "local_shell_call":
            if let status = try? container.decode(LocalShellStatus.self, forKey: .status),
               let action = try? container.decode(LocalShellAction.self, forKey: .action)
            {
                self = .localShellCall(
                    id: try container.decodeIfPresent(String.self, forKey: .id),
                    callID: try container.decodeIfPresent(String.self, forKey: .callID),
                    status: status,
                    action: action
                )
            } else {
                self = .knownPersisted(type: type)
            }
        case "function_call":
            if let name = try? container.decode(String.self, forKey: .name),
               let arguments = try? container.decode(String.self, forKey: .arguments),
               let callID = try? container.decode(String.self, forKey: .callID)
            {
                self = .functionCall(
                    id: try container.decodeIfPresent(String.self, forKey: .id),
                    name: name,
                    namespace: try container.decodeIfPresent(String.self, forKey: .namespace),
                    arguments: arguments,
                    callID: callID
                )
            } else {
                self = .knownPersisted(type: type)
            }
        case "tool_search_call":
            if let execution = try? container.decode(String.self, forKey: .execution),
               let arguments = try? container.decode(JSONValue.self, forKey: .arguments)
            {
                self = .toolSearchCall(
                    id: try container.decodeIfPresent(String.self, forKey: .id),
                    callID: try container.decodeIfPresent(String.self, forKey: .callID),
                    status: try container.decodeIfPresent(String.self, forKey: .status),
                    execution: execution,
                    arguments: arguments
                )
            } else {
                self = .knownPersisted(type: type)
            }
        case "function_call_output":
            if let callID = try? container.decode(String.self, forKey: .callID),
               let output = try? container.decode(FunctionCallOutputPayload.self, forKey: .output)
            {
                self = .functionCallOutput(callID: callID, output: output)
            } else {
                self = .knownPersisted(type: type)
            }
        case "custom_tool_call":
            if let callID = try? container.decode(String.self, forKey: .callID),
               let name = try? container.decode(String.self, forKey: .name),
               let input = try? container.decode(String.self, forKey: .input)
            {
                self = .customToolCall(
                    id: try container.decodeIfPresent(String.self, forKey: .id),
                    status: try container.decodeIfPresent(String.self, forKey: .status),
                    callID: callID,
                    name: name,
                    input: input
                )
            } else {
                self = .knownPersisted(type: type)
            }
        case "custom_tool_call_output":
            if let callID = try? container.decode(String.self, forKey: .callID),
               let output = try? container.decode(FunctionCallOutputPayload.self, forKey: .output)
            {
                self = .customToolCallOutput(
                    callID: callID,
                    name: try container.decodeIfPresent(String.self, forKey: .name),
                    output: output
                )
            } else {
                self = .knownPersisted(type: type)
            }
        case "tool_search_output":
            if let status = try? container.decode(String.self, forKey: .status),
               let execution = try? container.decode(String.self, forKey: .execution),
               let tools = try? container.decode([JSONValue].self, forKey: .tools)
            {
                self = .toolSearchOutput(
                    callID: try container.decodeIfPresent(String.self, forKey: .callID),
                    status: status,
                    execution: execution,
                    tools: tools
                )
            } else {
                self = .knownPersisted(type: type)
            }
        case "web_search_call":
            self = .webSearchCall(
                id: try container.decodeIfPresent(String.self, forKey: .id),
                status: try container.decodeIfPresent(String.self, forKey: .status),
                action: try container.decodeIfPresent(WebSearchAction.self, forKey: .action)
            )
        case "image_generation_call":
            if let id = try? container.decode(String.self, forKey: .id),
               let status = try? container.decode(String.self, forKey: .status),
               let result = try? container.decode(String.self, forKey: .result)
            {
                self = .imageGenerationCall(
                    id: id,
                    status: status,
                    revisedPrompt: try container.decodeIfPresent(String.self, forKey: .revisedPrompt),
                    result: result
                )
            } else {
                self = .knownPersisted(type: type)
            }
        case "compaction", "compaction_summary":
            self = .compaction(encryptedContent: try container.decode(String.self, forKey: .encryptedContent))
        case "context_compaction":
            self = .contextCompaction(encryptedContent: try container.decodeIfPresent(String.self, forKey: .encryptedContent))
        case "ghost_snapshot":
            if let ghostCommit = try? container.decode(GhostCommit.self, forKey: .ghostCommit) {
                self = .ghostSnapshot(ghostCommit: ghostCommit)
            } else {
                self = .knownPersisted(type: type)
            }
        default:
            self = .other
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .message(_, role, content, phase):
            try container.encode("message", forKey: .type)
            try container.encode(role, forKey: .role)
            try container.encode(content, forKey: .content)
            try container.encodeIfPresent(phase, forKey: .phase)
        case let .reasoning(_, summary, content, encryptedContent):
            try container.encode("reasoning", forKey: .type)
            try container.encode(summary, forKey: .summary)
            if !Self.shouldSkipReasoningContent(content) {
                try container.encode(content, forKey: .content)
            }
            try container.encodePresentOrNull(encryptedContent, forKey: .encryptedContent)
        case let .localShellCall(_, callID, status, action):
            try container.encode("local_shell_call", forKey: .type)
            try container.encodePresentOrNull(callID, forKey: .callID)
            try container.encode(status, forKey: .status)
            try container.encode(action, forKey: .action)
        case let .functionCall(_, name, namespace, arguments, callID):
            try container.encode("function_call", forKey: .type)
            try container.encode(name, forKey: .name)
            try container.encodeIfPresent(namespace, forKey: .namespace)
            try container.encode(arguments, forKey: .arguments)
            try container.encode(callID, forKey: .callID)
        case let .toolSearchCall(_, callID, status, execution, arguments):
            try container.encode("tool_search_call", forKey: .type)
            try container.encodePresentOrNull(callID, forKey: .callID)
            try container.encodeIfPresent(status, forKey: .status)
            try container.encode(execution, forKey: .execution)
            try container.encode(arguments, forKey: .arguments)
        case let .functionCallOutput(callID, output):
            try container.encode("function_call_output", forKey: .type)
            try container.encode(callID, forKey: .callID)
            try container.encode(output, forKey: .output)
        case let .customToolCall(_, status, callID, name, input):
            try container.encode("custom_tool_call", forKey: .type)
            try container.encodeIfPresent(status, forKey: .status)
            try container.encode(callID, forKey: .callID)
            try container.encode(name, forKey: .name)
            try container.encode(input, forKey: .input)
        case let .customToolCallOutput(callID, name, output):
            try container.encode("custom_tool_call_output", forKey: .type)
            try container.encode(callID, forKey: .callID)
            try container.encodeIfPresent(name, forKey: .name)
            try container.encode(output, forKey: .output)
        case let .toolSearchOutput(callID, status, execution, tools):
            try container.encode("tool_search_output", forKey: .type)
            try container.encodePresentOrNull(callID, forKey: .callID)
            try container.encode(status, forKey: .status)
            try container.encode(execution, forKey: .execution)
            try container.encode(tools, forKey: .tools)
        case let .webSearchCall(_, status, action):
            try container.encode("web_search_call", forKey: .type)
            try container.encodeIfPresent(status, forKey: .status)
            try container.encodeIfPresent(action, forKey: .action)
        case let .imageGenerationCall(id, status, revisedPrompt, result):
            try container.encode("image_generation_call", forKey: .type)
            try container.encode(id, forKey: .id)
            try container.encode(status, forKey: .status)
            try container.encodeIfPresent(revisedPrompt, forKey: .revisedPrompt)
            try container.encode(result, forKey: .result)
        case let .ghostSnapshot(ghostCommit):
            try container.encode("ghost_snapshot", forKey: .type)
            try container.encode(ghostCommit, forKey: .ghostCommit)
        case let .compaction(encryptedContent):
            try container.encode("compaction", forKey: .type)
            try container.encode(encryptedContent, forKey: .encryptedContent)
        case let .contextCompaction(encryptedContent):
            try container.encode("context_compaction", forKey: .type)
            try container.encodeIfPresent(encryptedContent, forKey: .encryptedContent)
        case let .knownPersisted(type):
            try container.encode(type, forKey: .type)
        case .other:
            try container.encode("other", forKey: .type)
        }
    }

    private static func shouldSkipReasoningContent(_ content: [ReasoningItemContent]?) -> Bool {
        guard let content else {
            return true
        }
        return !content.contains { item in
            if case .reasoningText = item {
                return true
            }
            return false
        }
    }
}

public extension ResponseItem {
    static func customToolCallOutput(callID: String, name: String? = nil, output: String) -> ResponseItem {
        .customToolCallOutput(callID: callID, name: name, output: FunctionCallOutputPayload(content: output))
    }
}

private extension JSONEncoder {
    static var codexCompact: JSONEncoder {
        JSONEncoder()
    }
}

private extension KeyedEncodingContainer {
    mutating func encodePresentOrNull<T: Encodable>(_ value: T?, forKey key: Key) throws {
        if let value {
            try encode(value, forKey: key)
        } else {
            try encodeNil(forKey: key)
        }
    }
}
