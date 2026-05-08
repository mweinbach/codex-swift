import Foundation

public enum ConfigShellToolType: String, Codable, CaseIterable, Equatable, Sendable {
    case `default`
    case local
    case unifiedExec = "unified_exec"
    case disabled
    case shellCommand = "shell_command"
}

public enum ApplyPatchToolType: String, Codable, CaseIterable, Equatable, Sendable {
    case freeform
    case function
}

public enum JSONSchemaAdditionalProperties: Equatable, Codable, Sendable {
    case boolean(Bool)
    case schema(JSONSchema)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Bool.self) {
            self = .boolean(value)
            return
        }
        self = .schema(try container.decode(JSONSchema.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .boolean(value):
            try container.encode(value)
        case let .schema(schema):
            try container.encode(schema)
        }
    }
}

public indirect enum JSONSchema: Equatable, Codable, Sendable {
    case boolean(description: String?)
    case string(description: String?)
    case number(description: String?)
    case array(items: JSONSchema, description: String?)
    case object(
        properties: [String: JSONSchema],
        required: [String]?,
        additionalProperties: JSONSchemaAdditionalProperties?
    )

    private enum CodingKeys: String, CodingKey {
        case type
        case description
        case items
        case properties
        case required
        case additionalProperties
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "boolean":
            self = .boolean(description: try container.decodeIfPresent(String.self, forKey: .description))
        case "string":
            self = .string(description: try container.decodeIfPresent(String.self, forKey: .description))
        case "number", "integer":
            self = .number(description: try container.decodeIfPresent(String.self, forKey: .description))
        case "array":
            self = .array(
                items: try container.decode(JSONSchema.self, forKey: .items),
                description: try container.decodeIfPresent(String.self, forKey: .description)
            )
        case "object":
            self = .object(
                properties: try container.decode([String: JSONSchema].self, forKey: .properties),
                required: try container.decodeIfPresent([String].self, forKey: .required),
                additionalProperties: try container.decodeIfPresent(
                    JSONSchemaAdditionalProperties.self,
                    forKey: .additionalProperties
                )
            )
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unsupported JSON schema type: \(type)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .boolean(description):
            try container.encode("boolean", forKey: .type)
            try container.encodeIfPresent(description, forKey: .description)
        case let .string(description):
            try container.encode("string", forKey: .type)
            try container.encodeIfPresent(description, forKey: .description)
        case let .number(description):
            try container.encode("number", forKey: .type)
            try container.encodeIfPresent(description, forKey: .description)
        case let .array(items, description):
            try container.encode("array", forKey: .type)
            try container.encode(items, forKey: .items)
            try container.encodeIfPresent(description, forKey: .description)
        case let .object(properties, required, additionalProperties):
            try container.encode("object", forKey: .type)
            try container.encode(properties, forKey: .properties)
            try container.encodeIfPresent(required, forKey: .required)
            try container.encodeIfPresent(additionalProperties, forKey: .additionalProperties)
        }
    }

    public static func sanitized(from value: Any) -> JSONSchema {
        switch value {
        case is Bool:
            return .string(description: nil)
        case let dictionary as [String: Any]:
            return sanitized(fromObject: dictionary)
        case let dictionary as NSDictionary:
            return sanitized(fromObject: dictionary.reduce(into: [String: Any]()) { result, entry in
                guard let key = entry.key as? String else { return }
                result[key] = entry.value
            })
        default:
            return .string(description: nil)
        }
    }

    private static func sanitized(fromObject object: [String: Any]) -> JSONSchema {
        let description = object["description"] as? String
        let type = normalizedType(for: object)

        switch type {
        case "boolean":
            return .boolean(description: description)
        case "array":
            let items = object["items"].map(sanitized(from:)) ?? .string(description: nil)
            return .array(items: items, description: description)
        case "object":
            return .object(
                properties: sanitizedProperties(object["properties"]),
                required: object["required"] as? [String],
                additionalProperties: sanitizedAdditionalProperties(object["additionalProperties"])
            )
        case "number", "integer":
            return .number(description: description)
        case "string":
            fallthrough
        default:
            return .string(description: description)
        }
    }

    private static func normalizedType(for object: [String: Any]) -> String {
        if let type = object["type"] as? String {
            return type
        }

        if let types = object["type"] as? [String],
           let supported = types.first(where: { ["object", "array", "string", "number", "integer", "boolean"].contains($0) })
        {
            return supported
        }

        if object["properties"] != nil || object["required"] != nil || object["additionalProperties"] != nil {
            return "object"
        }
        if object["items"] != nil || object["prefixItems"] != nil {
            return "array"
        }
        if object["enum"] != nil || object["const"] != nil || object["format"] != nil {
            return "string"
        }
        if object["minimum"] != nil || object["maximum"] != nil
            || object["exclusiveMinimum"] != nil || object["exclusiveMaximum"] != nil
            || object["multipleOf"] != nil
        {
            return "number"
        }

        return "string"
    }

    private static func sanitizedProperties(_ value: Any?) -> [String: JSONSchema] {
        guard let properties = value as? [String: Any] else {
            return [:]
        }
        return properties.mapValues(sanitized(from:))
    }

    private static func sanitizedAdditionalProperties(_ value: Any?) -> JSONSchemaAdditionalProperties? {
        guard let value else {
            return nil
        }
        if let bool = value as? Bool {
            return .boolean(bool)
        }
        return .schema(sanitized(from: value))
    }
}

public struct ResponsesAPITool: Equatable, Codable, Sendable {
    public let name: String
    public let description: String
    public let strict: Bool
    public let parameters: JSONSchema

    public init(name: String, description: String, strict: Bool = false, parameters: JSONSchema) {
        self.name = name
        self.description = description
        self.strict = strict
        self.parameters = parameters
    }
}

public struct FreeformToolFormat: Equatable, Codable, Sendable {
    public let type: String
    public let syntax: String
    public let definition: String

    public init(type: String, syntax: String, definition: String) {
        self.type = type
        self.syntax = syntax
        self.definition = definition
    }
}

public struct FreeformTool: Equatable, Codable, Sendable {
    public let name: String
    public let description: String
    public let format: FreeformToolFormat

    public init(name: String, description: String, format: FreeformToolFormat) {
        self.name = name
        self.description = description
        self.format = format
    }
}

public enum ToolSpec: Equatable, Codable, Sendable {
    case function(ResponsesAPITool)
    case localShell
    case webSearch
    case freeform(FreeformTool)

    private enum CodingKeys: String, CodingKey {
        case type
        case name
        case description
        case strict
        case parameters
        case format
    }

    public var name: String {
        switch self {
        case let .function(tool):
            return tool.name
        case .localShell:
            return "local_shell"
        case .webSearch:
            return "web_search"
        case let .freeform(tool):
            return tool.name
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .type) {
        case "function":
            self = .function(
                ResponsesAPITool(
                    name: try container.decode(String.self, forKey: .name),
                    description: try container.decode(String.self, forKey: .description),
                    strict: try container.decode(Bool.self, forKey: .strict),
                    parameters: try container.decode(JSONSchema.self, forKey: .parameters)
                )
            )
        case "local_shell":
            self = .localShell
        case "web_search":
            self = .webSearch
        case "custom":
            self = .freeform(
                FreeformTool(
                    name: try container.decode(String.self, forKey: .name),
                    description: try container.decode(String.self, forKey: .description),
                    format: try container.decode(FreeformToolFormat.self, forKey: .format)
                )
            )
        case let type:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unsupported tool type: \(type)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .function(tool):
            try container.encode("function", forKey: .type)
            try container.encode(tool.name, forKey: .name)
            try container.encode(tool.description, forKey: .description)
            try container.encode(tool.strict, forKey: .strict)
            try container.encode(tool.parameters, forKey: .parameters)
        case .localShell:
            try container.encode("local_shell", forKey: .type)
        case .webSearch:
            try container.encode("web_search", forKey: .type)
        case let .freeform(tool):
            try container.encode("custom", forKey: .type)
            try container.encode(tool.name, forKey: .name)
            try container.encode(tool.description, forKey: .description)
            try container.encode(tool.format, forKey: .format)
        }
    }
}

public struct ConfiguredToolSpec: Equatable, Sendable {
    public let spec: ToolSpec
    public let supportsParallelToolCalls: Bool

    public init(spec: ToolSpec, supportsParallelToolCalls: Bool) {
        self.spec = spec
        self.supportsParallelToolCalls = supportsParallelToolCalls
    }
}

public struct ToolsConfig: Equatable, Sendable {
    public let shellType: ConfigShellToolType
    public let applyPatchToolType: ApplyPatchToolType?
    public let webSearchRequest: Bool
    public let includeViewImageTool: Bool
    public let includeComputerUseTools: Bool
    public let experimentalSupportedTools: [String]

    public init(
        shellType: ConfigShellToolType,
        applyPatchToolType: ApplyPatchToolType? = nil,
        webSearchRequest: Bool = false,
        includeViewImageTool: Bool = true,
        includeComputerUseTools: Bool = false,
        experimentalSupportedTools: [String] = []
    ) {
        self.shellType = shellType
        self.applyPatchToolType = applyPatchToolType
        self.webSearchRequest = webSearchRequest
        self.includeViewImageTool = includeViewImageTool
        self.includeComputerUseTools = includeComputerUseTools
        self.experimentalSupportedTools = experimentalSupportedTools
    }
}

public enum ToolSpecFactory {
    public static func buildSpecs(config: ToolsConfig, mcpTools: [String: McpTool]? = nil) -> [ConfiguredToolSpec] {
        var specs: [ConfiguredToolSpec] = []

        switch config.shellType {
        case .default:
            specs.append(ConfiguredToolSpec(spec: createShellTool(), supportsParallelToolCalls: false))
        case .local:
            specs.append(ConfiguredToolSpec(spec: .localShell, supportsParallelToolCalls: false))
        case .unifiedExec:
            specs.append(ConfiguredToolSpec(spec: createExecCommandTool(), supportsParallelToolCalls: false))
            specs.append(ConfiguredToolSpec(spec: createWriteStdinTool(), supportsParallelToolCalls: false))
        case .disabled:
            break
        case .shellCommand:
            specs.append(ConfiguredToolSpec(spec: createShellCommandTool(), supportsParallelToolCalls: false))
        }

        specs.append(ConfiguredToolSpec(spec: createListMCPResourcesTool(), supportsParallelToolCalls: true))
        specs.append(ConfiguredToolSpec(spec: createListMCPResourceTemplatesTool(), supportsParallelToolCalls: true))
        specs.append(ConfiguredToolSpec(spec: createReadMCPResourceTool(), supportsParallelToolCalls: true))
        specs.append(ConfiguredToolSpec(spec: createPlanTool(), supportsParallelToolCalls: false))

        switch config.applyPatchToolType {
        case .freeform:
            specs.append(ConfiguredToolSpec(spec: createApplyPatchFreeformTool(), supportsParallelToolCalls: false))
        case .function:
            specs.append(ConfiguredToolSpec(spec: createApplyPatchJSONTool(), supportsParallelToolCalls: false))
        case nil:
            break
        }

        if config.experimentalSupportedTools.contains("grep_files") {
            specs.append(ConfiguredToolSpec(spec: createGrepFilesTool(), supportsParallelToolCalls: true))
        }
        if config.experimentalSupportedTools.contains("read_file") {
            specs.append(ConfiguredToolSpec(spec: createReadFileTool(), supportsParallelToolCalls: true))
        }
        if config.experimentalSupportedTools.contains("list_dir") {
            specs.append(ConfiguredToolSpec(spec: createListDirTool(), supportsParallelToolCalls: true))
        }
        if config.experimentalSupportedTools.contains("test_sync_tool") {
            specs.append(ConfiguredToolSpec(spec: createTestSyncTool(), supportsParallelToolCalls: true))
        }

        if config.webSearchRequest {
            specs.append(ConfiguredToolSpec(spec: .webSearch, supportsParallelToolCalls: false))
        }

        if config.includeViewImageTool {
            specs.append(ConfiguredToolSpec(spec: createViewImageTool(), supportsParallelToolCalls: true))
        }

        if config.includeComputerUseTools {
            specs.append(ConfiguredToolSpec(spec: createComputerScreenshotTool(), supportsParallelToolCalls: true))
            specs.append(ConfiguredToolSpec(spec: createComputerClickTool(), supportsParallelToolCalls: true))
            specs.append(ConfiguredToolSpec(spec: createComputerDragTool(), supportsParallelToolCalls: true))
            specs.append(ConfiguredToolSpec(spec: createComputerScrollTool(), supportsParallelToolCalls: true))
            specs.append(ConfiguredToolSpec(spec: createComputerTypeTool(), supportsParallelToolCalls: true))
            specs.append(ConfiguredToolSpec(spec: createComputerKeyTool(), supportsParallelToolCalls: true))
        }

        if let mcpTools {
            for name in mcpTools.keys.sorted() {
                guard let tool = mcpTools[name] else {
                    continue
                }
                specs.append(ConfiguredToolSpec(
                    spec: createMCPTool(fullyQualifiedName: name, tool: tool),
                    supportsParallelToolCalls: false
                ))
            }
        }

        return specs
    }

    public static func createToolsJSONForResponsesAPI(_ tools: [ToolSpec]) throws -> [Any] {
        try tools.map { tool in
            let data = try JSONEncoder().encode(tool)
            return try JSONSerialization.jsonObject(with: data)
        }
    }

    public static func createToolsJSONForChatCompletionsAPI(_ tools: [ToolSpec]) throws -> [Any] {
        try createToolsJSONForResponsesAPI(tools).compactMap { tool in
            guard var object = tool as? [String: Any],
                  object["type"] as? String == "function"
            else {
                return nil
            }
            let name = object["name"] as? String ?? ""
            object.removeValue(forKey: "type")
            return [
                "type": "function",
                "name": name,
                "function": object
            ]
        }
    }

    public static func createMCPTool(fullyQualifiedName: String, tool: McpTool) -> ToolSpec {
        var inputSchema: [String: Any] = ["type": tool.inputSchema.type]
        if let properties = tool.inputSchema.properties {
            inputSchema["properties"] = jsonCompatibleValue(properties)
        } else if tool.inputSchema.type == "object" {
            inputSchema["properties"] = [String: Any]()
        }
        if let required = tool.inputSchema.required {
            inputSchema["required"] = required
        }

        return .function(
            ResponsesAPITool(
                name: fullyQualifiedName,
                description: tool.description ?? "",
                strict: false,
                parameters: JSONSchema.sanitized(from: inputSchema)
            )
        )
    }

    public static func createExecCommandTool() -> ToolSpec {
        functionTool(
            name: "exec_command",
            description: "Runs a command in a PTY, returning output or a session ID for ongoing interaction.",
            properties: [
                "cmd": .string(description: "Shell command to execute."),
                "workdir": .string(description: "Optional working directory to run the command in; defaults to the turn cwd."),
                "shell": .string(description: "Shell binary to launch. Defaults to /bin/bash."),
                "login": .boolean(description: "Whether to run the shell with -l/-i semantics. Defaults to true."),
                "yield_time_ms": .number(description: "How long to wait (in milliseconds) for output before yielding."),
                "max_output_tokens": .number(description: "Maximum number of tokens to return. Excess output will be truncated."),
                "sandbox_permissions": .string(description: "Sandbox permissions for the command. Set to \"require_escalated\" to request running without sandbox restrictions; defaults to \"use_default\"."),
                "justification": .string(description: "Only set if sandbox_permissions is \"require_escalated\". 1-sentence explanation of why we want to run this command.")
            ],
            required: ["cmd"]
        )
    }

    public static func createWriteStdinTool() -> ToolSpec {
        functionTool(
            name: "write_stdin",
            description: "Writes characters to an existing unified exec session and returns recent output.",
            properties: [
                "session_id": .number(description: "Identifier of the running unified exec session."),
                "chars": .string(description: "Bytes to write to stdin (may be empty to poll)."),
                "yield_time_ms": .number(description: "How long to wait (in milliseconds) for output before yielding."),
                "max_output_tokens": .number(description: "Maximum number of tokens to return. Excess output will be truncated.")
            ],
            required: ["session_id"]
        )
    }

    public static func createShellTool() -> ToolSpec {
        functionTool(
            name: "shell",
            description: """
            Runs a shell command and returns its output.
            - The arguments to `shell` will be passed to execvp(). Most terminal commands should be prefixed with ["bash", "-lc"].
            - Always set the `workdir` param when using the shell function. Do not use `cd` unless absolutely necessary.
            """,
            properties: [
                "command": .array(items: .string(description: nil), description: "The command to execute"),
                "workdir": .string(description: "The working directory to execute the command in"),
                "timeout_ms": .number(description: "The timeout for the command in milliseconds"),
                "sandbox_permissions": .string(description: "Sandbox permissions for the command. Set to \"require_escalated\" to request running without sandbox restrictions; defaults to \"use_default\"."),
                "justification": .string(description: "Only set if sandbox_permissions is \"require_escalated\". 1-sentence explanation of why we want to run this command.")
            ],
            required: ["command"]
        )
    }

    public static func createShellCommandTool() -> ToolSpec {
        functionTool(
            name: "shell_command",
            description: """
            Runs a shell command and returns its output.
            - Always set the `workdir` param when using the shell_command function. Do not use `cd` unless absolutely necessary.
            """,
            properties: [
                "command": .string(description: "The shell script to execute in the user's default shell"),
                "workdir": .string(description: "The working directory to execute the command in"),
                "login": .boolean(description: "Whether to run the shell with login shell semantics. Defaults to true."),
                "timeout_ms": .number(description: "The timeout for the command in milliseconds"),
                "sandbox_permissions": .string(description: "Sandbox permissions for the command. Set to \"require_escalated\" to request running without sandbox restrictions; defaults to \"use_default\"."),
                "justification": .string(description: "Only set if sandbox_permissions is \"require_escalated\". 1-sentence explanation of why we want to run this command.")
            ],
            required: ["command"]
        )
    }

    public static func createPlanTool() -> ToolSpec {
        functionTool(
            name: "update_plan",
            description: """
            Updates the task plan.
            Provide an optional explanation and a list of plan items, each with a step and status.
            At most one step can be in_progress at a time.

            """,
            properties: [
                "explanation": .string(description: nil),
                "plan": .array(
                    items: .object(
                        properties: [
                            "step": .string(description: nil),
                            "status": .string(description: "One of: pending, in_progress, completed")
                        ],
                        required: ["step", "status"],
                        additionalProperties: .boolean(false)
                    ),
                    description: "The list of steps"
                )
            ],
            required: ["plan"]
        )
    }

    public static func createApplyPatchFreeformTool() -> ToolSpec {
        .freeform(
            FreeformTool(
                name: "apply_patch",
                description: "Use the `apply_patch` tool to edit files. This is a FREEFORM tool, so do not wrap the patch in JSON.",
                format: FreeformToolFormat(type: "grammar", syntax: "lark", definition: applyPatchLarkGrammar)
            )
        )
    }

    public static func createApplyPatchJSONTool() -> ToolSpec {
        functionTool(
            name: "apply_patch",
            description: "Use the `apply_patch` tool to edit files.",
            properties: [
                "input": .string(description: "The entire contents of the apply_patch command")
            ],
            required: ["input"]
        )
    }

    public static func createViewImageTool() -> ToolSpec {
        functionTool(
            name: "view_image",
            description: "Attach a local image (by filesystem path) to the conversation context for this turn.",
            properties: [
                "path": .string(description: "Local filesystem path to an image file")
            ],
            required: ["path"]
        )
    }

    public static func createComputerScreenshotTool() -> ToolSpec {
        functionTool(
            name: "computer_screenshot",
            description: "Capture a single on-demand screenshot of the GUI (1280x720 coordinate space).",
            properties: [:],
            required: nil
        )
    }

    public static func createComputerClickTool() -> ToolSpec {
        functionTool(
            name: "computer_click",
            description: "Move the mouse to a coordinate and click (coordinates are 1280x720).",
            properties: [
                "x": .number(description: "X coordinate in 1280x720 space."),
                "y": .number(description: "Y coordinate in 1280x720 space."),
                "button": .string(description: "Mouse button: left (default), right, or middle."),
                "double": .boolean(description: "Double-click when true.")
            ],
            required: ["x", "y"]
        )
    }

    public static func createComputerDragTool() -> ToolSpec {
        functionTool(
            name: "computer_drag",
            description: "Click-and-drag between two coordinates (coordinates are 1280x720).",
            properties: [
                "from_x": .number(description: "Start X coordinate in 1280x720 space."),
                "from_y": .number(description: "Start Y coordinate in 1280x720 space."),
                "to_x": .number(description: "End X coordinate in 1280x720 space."),
                "to_y": .number(description: "End Y coordinate in 1280x720 space."),
                "button": .string(description: "Mouse button: left (default), right, or middle.")
            ],
            required: ["from_x", "from_y", "to_x", "to_y"]
        )
    }

    public static func createComputerScrollTool() -> ToolSpec {
        functionTool(
            name: "computer_scroll",
            description: "Scroll the mouse wheel (coordinates are 1280x720 if provided).",
            properties: [
                "direction": .string(description: "Scroll direction: up or down."),
                "amount": .number(description: "Number of scroll ticks (defaults to 3)."),
                "x": .number(description: "Optional X coordinate in 1280x720 space."),
                "y": .number(description: "Optional Y coordinate in 1280x720 space.")
            ],
            required: ["direction"]
        )
    }

    public static func createComputerTypeTool() -> ToolSpec {
        functionTool(
            name: "computer_type",
            description: "Type text at the current focus.",
            properties: [
                "text": .string(description: "Text to type."),
                "delay_ms": .number(description: "Optional delay between keystrokes in milliseconds.")
            ],
            required: ["text"]
        )
    }

    public static func createComputerKeyTool() -> ToolSpec {
        functionTool(
            name: "computer_key",
            description: "Press a key or key chord.",
            properties: [
                "keys": .array(items: .string(description: nil), description: "Key chord, e.g. [\"ctrl\", \"c\"]."),
                "confirm": .boolean(description: "Required for destructive combos (Alt+F4, Ctrl+Q, Ctrl+W, etc.).")
            ],
            required: ["keys"]
        )
    }

    public static func createTestSyncTool() -> ToolSpec {
        functionTool(
            name: "test_sync_tool",
            description: "Internal synchronization helper used by Codex integration tests.",
            properties: [
                "sleep_before_ms": .number(description: "Optional delay in milliseconds before any other action"),
                "sleep_after_ms": .number(description: "Optional delay in milliseconds after completing the barrier"),
                "barrier": .object(
                    properties: [
                        "id": .string(description: "Identifier shared by concurrent calls that should rendezvous"),
                        "participants": .number(description: "Number of tool calls that must arrive before the barrier opens"),
                        "timeout_ms": .number(description: "Maximum time in milliseconds to wait at the barrier")
                    ],
                    required: ["id", "participants"],
                    additionalProperties: .boolean(false)
                )
            ],
            required: nil
        )
    }

    public static func createGrepFilesTool() -> ToolSpec {
        functionTool(
            name: "grep_files",
            description: "Finds files whose contents match the pattern and lists them by modification time.",
            properties: [
                "pattern": .string(description: "Regular expression pattern to search for."),
                "include": .string(description: "Optional glob that limits which files are searched (e.g. \"*.rs\" or \"*.{ts,tsx}\")."),
                "path": .string(description: "Directory or file path to search. Defaults to the session's working directory."),
                "limit": .number(description: "Maximum number of file paths to return (defaults to 100).")
            ],
            required: ["pattern"]
        )
    }

    public static func createReadFileTool() -> ToolSpec {
        functionTool(
            name: "read_file",
            description: "Reads a local file with 1-indexed line numbers, supporting slice and indentation-aware block modes.",
            properties: [
                "file_path": .string(description: "Absolute path to the file"),
                "offset": .number(description: "The line number to start reading from. Must be 1 or greater."),
                "limit": .number(description: "The maximum number of lines to return."),
                "mode": .string(description: "Optional mode selector: \"slice\" for simple ranges (default) or \"indentation\" to expand around an anchor line."),
                "indentation": .object(
                    properties: [
                        "anchor_line": .number(description: "Anchor line to center the indentation lookup on (defaults to offset)."),
                        "max_levels": .number(description: "How many parent indentation levels (smaller indents) to include."),
                        "include_siblings": .boolean(description: "When true, include additional blocks that share the anchor indentation."),
                        "include_header": .boolean(description: "Include doc comments or attributes directly above the selected block."),
                        "max_lines": .number(description: "Hard cap on the number of lines returned when using indentation mode.")
                    ],
                    required: nil,
                    additionalProperties: .boolean(false)
                )
            ],
            required: ["file_path"]
        )
    }

    public static func createListDirTool() -> ToolSpec {
        functionTool(
            name: "list_dir",
            description: "Lists entries in a local directory with 1-indexed entry numbers and simple type labels.",
            properties: [
                "dir_path": .string(description: "Absolute path to the directory to list."),
                "offset": .number(description: "The entry number to start listing from. Must be 1 or greater."),
                "limit": .number(description: "The maximum number of entries to return."),
                "depth": .number(description: "The maximum directory depth to traverse. Must be 1 or greater.")
            ],
            required: ["dir_path"]
        )
    }

    public static func createListMCPResourcesTool() -> ToolSpec {
        functionTool(
            name: "list_mcp_resources",
            description: "Lists resources provided by MCP servers. Resources allow servers to share data that provides context to language models, such as files, database schemas, or application-specific information. Prefer resources over web search when possible.",
            properties: [
                "server": .string(description: "Optional MCP server name. When omitted, lists resources from every configured server."),
                "cursor": .string(description: "Opaque cursor returned by a previous list_mcp_resources call for the same server.")
            ],
            required: nil
        )
    }

    public static func createListMCPResourceTemplatesTool() -> ToolSpec {
        functionTool(
            name: "list_mcp_resource_templates",
            description: "Lists resource templates provided by MCP servers. Parameterized resource templates allow servers to share data that takes parameters and provides context to language models, such as files, database schemas, or application-specific information. Prefer resource templates over web search when possible.",
            properties: [
                "server": .string(description: "Optional MCP server name. When omitted, lists resource templates from all configured servers."),
                "cursor": .string(description: "Opaque cursor returned by a previous list_mcp_resource_templates call for the same server.")
            ],
            required: nil
        )
    }

    public static func createReadMCPResourceTool() -> ToolSpec {
        functionTool(
            name: "read_mcp_resource",
            description: "Read a specific resource from an MCP server given the server name and resource URI.",
            properties: [
                "server": .string(description: "MCP server name exactly as configured. Must match the 'server' field returned by list_mcp_resources."),
                "uri": .string(description: "Resource URI to read. Must be one of the URIs returned by list_mcp_resources.")
            ],
            required: ["server", "uri"]
        )
    }

    private static func functionTool(
        name: String,
        description: String,
        properties: [String: JSONSchema],
        required: [String]?
    ) -> ToolSpec {
        .function(
            ResponsesAPITool(
                name: name,
                description: description,
                strict: false,
                parameters: .object(
                    properties: properties,
                    required: required,
                    additionalProperties: .boolean(false)
                )
            )
        )
    }

    private static func jsonCompatibleValue(_ value: JSONValue) -> Any {
        switch value {
        case .null:
            return NSNull()
        case let .bool(value):
            return value
        case let .integer(value):
            return value
        case let .double(value):
            return value
        case let .string(value):
            return value
        case let .array(values):
            return values.map(jsonCompatibleValue)
        case let .object(values):
            return values.mapValues(jsonCompatibleValue)
        }
    }

    public static let applyPatchLarkGrammar = """
    start: begin_patch hunk+ end_patch
    begin_patch: "*** Begin Patch" LF
    end_patch: "*** End Patch" LF?

    hunk: add_hunk | delete_hunk | update_hunk
    add_hunk: "*** Add File: " filename LF add_line+
    delete_hunk: "*** Delete File: " filename LF
    update_hunk: "*** Update File: " filename LF change_move? change?

    filename: /(.+)/
    add_line: "+" /(.*)/ LF -> line

    change_move: "*** Move to: " filename LF
    change: (change_context | change_line)+ eof_line?
    change_context: ("@@" | "@@ " /(.+)/) LF
    change_line: ("+" | "-" | " ") /(.*)/ LF
    eof_line: "*** End of File" LF

    %import common.LF
    """
}
