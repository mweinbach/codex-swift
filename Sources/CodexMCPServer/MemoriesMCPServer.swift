import CodexCore
import Foundation

public enum MemoriesMCPServer {
    public static func run(
        codexHome: URL,
        stdin: FileHandle = .standardInput,
        stdout: FileHandle = .standardOutput
    ) async throws {
        let backend = LocalMemoriesBackend(codexHome: codexHome)
        try FileManager.default.createDirectory(at: backend.root, withIntermediateDirectories: true)
        var state = MemoriesMCPServerState()
        var buffer = Data()
        while true {
            let data = stdin.availableData
            if data.isEmpty {
                break
            }
            buffer.append(data)
            while let newline = buffer.firstIndex(of: 0x0A) {
                let line = buffer[..<newline]
                buffer.removeSubrange(...newline)
                guard !line.isEmpty else {
                    continue
                }
                let responses = processLine(Data(line), state: &state, backend: backend)
                try write(responses, to: stdout)
            }
        }

        if !buffer.isEmpty {
            let responses = processLine(buffer, state: &state, backend: backend)
            try write(responses, to: stdout)
        }
    }

    public static func toolCallResponse(
        codexHome: URL,
        name: String,
        arguments: [String: Any]
    ) throws -> [String: Any] {
        let backend = LocalMemoriesBackend(codexHome: codexHome)
        try FileManager.default.createDirectory(at: backend.root, withIntermediateDirectories: true)
        return handleToolCall(
            id: 1,
            params: [
                "name": name,
                "arguments": arguments
            ],
            backend: backend
        )
    }

    static func processLine(
        _ data: Data,
        state: inout MemoriesMCPServerState,
        backend: LocalMemoriesBackend
    ) -> [Data] {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let method = object["method"] as? String
        else {
            return []
        }

        let id = object["id"]
        let params = object["params"] as? [String: Any]
        if id == nil {
            handleNotification(method: method, state: &state)
            return []
        }

        let response: [String: Any]
        switch method {
        case "initialize":
            response = handleInitialize(id: id as Any, params: params, state: &state)
        case "ping":
            response = jsonRPCResponse(id: id as Any, result: [:])
        case "tools/list":
            response = jsonRPCResponse(id: id as Any, result: ["tools": toolDefinitionsForStatus()])
        case "tools/call":
            response = handleToolCall(id: id as Any, params: params, backend: backend)
        default:
            response = jsonRPCError(id: id as Any, code: -32601, message: "method not found: \(method)")
        }

        guard JSONSerialization.isValidJSONObject(response),
              let responseData = try? JSONSerialization.data(withJSONObject: response)
        else {
            return []
        }
        return [responseData]
    }

    private static func handleNotification(method: String, state _: inout MemoriesMCPServerState) {
        switch method {
        case "notifications/initialized", "notifications/cancelled", "notifications/progress":
            return
        default:
            return
        }
    }

    private static func handleInitialize(
        id: Any,
        params: [String: Any]?,
        state: inout MemoriesMCPServerState
    ) -> [String: Any] {
        guard !state.initialized else {
            return jsonRPCError(id: id, code: -32600, message: "initialize called more than once")
        }

        state.initialized = true
        return jsonRPCResponse(id: id, result: [
            "capabilities": [
                "tools": [
                    "listChanged": true
                ]
            ],
            "instructions": "Use these tools to list, read, and search Codex memory files.",
            "protocolVersion": params?["protocolVersion"] as? String ?? "2025-06-18",
            "serverInfo": [
                "name": "codex-memories-mcp-server",
                "title": "Codex Memories",
                "version": "0.0.0"
            ]
        ])
    }

    private static func handleToolCall(
        id: Any,
        params: [String: Any]?,
        backend: LocalMemoriesBackend
    ) -> [String: Any] {
        guard let name = params?["name"] as? String else {
            return jsonRPCError(id: id, code: -32602, message: "missing tool name")
        }
        let arguments = params?["arguments"] as? [String: Any] ?? [:]

        do {
            switch name {
            case "list":
                let args = try ListArgs(arguments)
                let result = try backend.list(ListMemoriesRequest(
                    path: args.path,
                    cursor: args.cursor,
                    maxResults: clampMaxResults(args.maxResults, default: defaultMemoriesListMaxResults, maximum: maxMemoriesListResults)
                ))
                return try structuredToolResponse(id: id, value: result)
            case "read":
                let args = try ReadArgs(arguments)
                let result = try backend.read(ReadMemoryRequest(
                    path: args.path,
                    lineOffset: args.lineOffset ?? 1,
                    maxLines: args.maxLines,
                    maxTokens: defaultMemoryReadMaxTokens
                ))
                return try structuredToolResponse(id: id, value: result)
            case "search":
                let args = try SearchArgs(arguments)
                let result = try backend.search(SearchMemoriesRequest(
                    queries: args.queries,
                    matchMode: args.matchMode ?? .any,
                    path: args.path,
                    cursor: args.cursor,
                    contextLines: args.contextLines ?? 0,
                    caseSensitive: args.caseSensitive ?? true,
                    normalized: args.normalized ?? false,
                    maxResults: clampMaxResults(args.maxResults, default: defaultMemoriesSearchMaxResults, maximum: maxMemoriesSearchResults)
                ))
                return try structuredToolResponse(id: id, value: result)
            default:
                return jsonRPCError(id: id, code: -32602, message: "unknown tool: \(name)")
            }
        } catch let error as MemoriesMCPArgumentError {
            return jsonRPCError(id: id, code: -32602, message: error.description)
        } catch let error as MemoriesBackendError {
            return jsonRPCError(id: id, code: mcpErrorCode(for: error), message: error.description)
        } catch {
            return jsonRPCError(id: id, code: -32603, message: String(describing: error))
        }
    }

    private static func structuredToolResponse<T: Encodable>(id: Any, value: T) throws -> [String: Any] {
        let structuredContent = try jsonObject(from: value)
        let textData = try JSONSerialization.data(withJSONObject: structuredContent, options: [.sortedKeys])
        let text = String(decoding: textData, as: UTF8.self)
        return jsonRPCResponse(id: id, result: [
            "content": [
                [
                    "type": "text",
                    "text": text
                ]
            ],
            "structuredContent": structuredContent,
            "isError": false
        ])
    }

    private static func jsonObject<T: Encodable>(from value: T) throws -> Any {
        let data = try JSONEncoder().encode(value)
        return try JSONSerialization.jsonObject(with: data)
    }

    private static func clampMaxResults(_ requested: Int?, default defaultValue: Int, maximum: Int) -> Int {
        min(Swift.max(1, requested ?? defaultValue), maximum)
    }

    private static func mcpErrorCode(for error: MemoriesBackendError) -> Int {
        if case .io = error {
            return -32603
        }
        return -32602
    }

    public static func toolDefinitionsForStatus() -> [[String: Any]] {
        [
            [
                "name": "list",
                "description": "List immediate files and directories under a path in the Codex memories store.",
                "inputSchema": listInputSchema(),
                "outputSchema": listOutputSchema(),
                "annotations": ["readOnlyHint": true]
            ],
            [
                "name": "read",
                "description": "Read a Codex memory file by relative path, optionally starting at a 1-indexed line offset and limiting the number of lines returned.",
                "inputSchema": readInputSchema(),
                "outputSchema": readOutputSchema(),
                "annotations": ["readOnlyHint": true]
            ],
            [
                "name": "search",
                "description": "Search Codex memory files for substring matches, optionally normalizing separators or requiring all query substrings on the same line or within a line window.",
                "inputSchema": searchInputSchema(),
                "outputSchema": searchOutputSchema(),
                "annotations": ["readOnlyHint": true]
            ]
        ]
    }

    private static func listInputSchema() -> [String: Any] {
        [
            "type": "object",
            "additionalProperties": false,
            "properties": [
                "path": ["type": "string"],
                "cursor": ["type": "string"],
                "max_results": ["type": "integer", "minimum": 1]
            ]
        ]
    }

    private static func readInputSchema() -> [String: Any] {
        [
            "type": "object",
            "additionalProperties": false,
            "required": ["path"],
            "properties": [
                "path": ["type": "string"],
                "line_offset": ["type": "integer", "minimum": 1],
                "max_lines": ["type": "integer", "minimum": 1]
            ]
        ]
    }

    private static func searchInputSchema() -> [String: Any] {
        [
            "type": "object",
            "additionalProperties": false,
            "required": ["queries"],
            "properties": [
                "queries": ["type": "array", "minItems": 1, "items": ["type": "string", "minLength": 1]],
                "match_mode": searchMatchModeSchema(),
                "path": ["type": "string"],
                "cursor": ["type": "string"],
                "context_lines": ["type": "integer", "minimum": 0],
                "case_sensitive": ["type": "boolean"],
                "normalized": ["type": "boolean"],
                "max_results": ["type": "integer", "minimum": 1]
            ]
        ]
    }

    private static func listOutputSchema() -> [String: Any] {
        [
            "type": "object",
            "additionalProperties": false,
            "required": ["entries", "truncated"],
            "properties": [
                "path": ["type": ["string", "null"]],
                "entries": ["type": "array", "items": memoryEntrySchema()],
                "next_cursor": ["type": ["string", "null"]],
                "truncated": ["type": "boolean"]
            ]
        ]
    }

    private static func readOutputSchema() -> [String: Any] {
        [
            "type": "object",
            "additionalProperties": false,
            "required": ["path", "start_line_number", "content", "truncated"],
            "properties": [
                "path": ["type": "string"],
                "start_line_number": ["type": "integer"],
                "content": ["type": "string"],
                "truncated": ["type": "boolean"]
            ]
        ]
    }

    private static func searchOutputSchema() -> [String: Any] {
        [
            "type": "object",
            "additionalProperties": false,
            "required": ["queries", "match_mode", "matches", "truncated"],
            "properties": [
                "queries": ["type": "array", "items": ["type": "string"]],
                "match_mode": searchMatchModeSchema(),
                "path": ["type": ["string", "null"]],
                "matches": ["type": "array", "items": memorySearchMatchSchema()],
                "next_cursor": ["type": ["string", "null"]],
                "truncated": ["type": "boolean"]
            ]
        ]
    }

    private static func memoryEntrySchema() -> [String: Any] {
        [
            "type": "object",
            "additionalProperties": false,
            "required": ["path", "entry_type"],
            "properties": [
                "path": ["type": "string"],
                "entry_type": ["type": "string", "enum": ["file", "directory"]]
            ]
        ]
    }

    private static func memorySearchMatchSchema() -> [String: Any] {
        [
            "type": "object",
            "additionalProperties": false,
            "required": ["path", "match_line_number", "content_start_line_number", "content", "matched_queries"],
            "properties": [
                "path": ["type": "string"],
                "match_line_number": ["type": "integer"],
                "content_start_line_number": ["type": "integer"],
                "content": ["type": "string"],
                "matched_queries": ["type": "array", "items": ["type": "string"]]
            ]
        ]
    }

    private static func searchMatchModeSchema() -> [String: Any] {
        [
            "oneOf": [
                [
                    "type": "object",
                    "required": ["type"],
                    "properties": ["type": ["const": "any"]],
                    "additionalProperties": false
                ],
                [
                    "type": "object",
                    "required": ["type"],
                    "properties": ["type": ["const": "all_on_same_line"]],
                    "additionalProperties": false
                ],
                [
                    "type": "object",
                    "required": ["type", "line_count"],
                    "properties": [
                        "type": ["const": "all_within_lines"],
                        "line_count": ["type": "integer", "minimum": 1]
                    ],
                    "additionalProperties": false
                ]
            ]
        ]
    }

    private static func jsonRPCResponse(id: Any, result: [String: Any]) -> [String: Any] {
        [
            "jsonrpc": "2.0",
            "id": id,
            "result": result
        ]
    }

    private static func jsonRPCError(id: Any, code: Int, message: String) -> [String: Any] {
        [
            "jsonrpc": "2.0",
            "id": id,
            "error": [
                "code": code,
                "message": message
            ]
        ]
    }

    private static func write(_ messages: [Data], to stdout: FileHandle) throws {
        for message in messages {
            try stdout.write(contentsOf: message)
            try stdout.write(contentsOf: Data([0x0A]))
        }
    }
}

struct MemoriesMCPServerState {
    var initialized = false
}

private enum MemoriesMCPArgumentError: Error, CustomStringConvertible {
    case invalidParams(String)

    var description: String {
        switch self {
        case let .invalidParams(message):
            return message
        }
    }
}

private struct ListArgs {
    let path: String?
    let cursor: String?
    let maxResults: Int?

    init(_ object: [String: Any]) throws {
        try rejectUnknownFields(in: object, allowed: ["path", "cursor", "max_results"])
        self.path = try optionalString(object["path"], field: "path")
        self.cursor = try optionalString(object["cursor"], field: "cursor")
        self.maxResults = try optionalNonNegativeInteger(object["max_results"], field: "max_results")
    }
}

private struct ReadArgs {
    let path: String
    let lineOffset: Int?
    let maxLines: Int?

    init(_ object: [String: Any]) throws {
        try rejectUnknownFields(in: object, allowed: ["path", "line_offset", "max_lines"])
        self.path = try requiredString(object["path"], field: "path")
        self.lineOffset = try optionalNonNegativeInteger(object["line_offset"], field: "line_offset")
        self.maxLines = try optionalNonNegativeInteger(object["max_lines"], field: "max_lines")
    }
}

private struct SearchArgs {
    let queries: [String]
    let matchMode: SearchMatchMode?
    let path: String?
    let cursor: String?
    let contextLines: Int?
    let caseSensitive: Bool?
    let normalized: Bool?
    let maxResults: Int?

    init(_ object: [String: Any]) throws {
        try rejectUnknownFields(
            in: object,
            allowed: ["queries", "match_mode", "path", "cursor", "context_lines", "case_sensitive", "normalized", "max_results"]
        )
        self.queries = try requiredStringArray(object["queries"], field: "queries")
        self.matchMode = try optionalMatchMode(object["match_mode"], field: "match_mode")
        self.path = try optionalString(object["path"], field: "path")
        self.cursor = try optionalString(object["cursor"], field: "cursor")
        self.contextLines = try optionalNonNegativeInteger(object["context_lines"], field: "context_lines")
        self.caseSensitive = try optionalBool(object["case_sensitive"], field: "case_sensitive")
        self.normalized = try optionalBool(object["normalized"], field: "normalized")
        self.maxResults = try optionalNonNegativeInteger(object["max_results"], field: "max_results")
    }
}

private func rejectUnknownFields(in object: [String: Any], allowed: Set<String>) throws {
    if let unknown = object.keys.sorted().first(where: { !allowed.contains($0) }) {
        throw MemoriesMCPArgumentError.invalidParams("unknown field `\(unknown)`")
    }
}

private func requiredString(_ value: Any?, field: String) throws -> String {
    guard let string = value as? String else {
        throw MemoriesMCPArgumentError.invalidParams("missing field `\(field)`")
    }
    return string
}

private func optionalString(_ value: Any?, field: String) throws -> String? {
    guard let value, !(value is NSNull) else {
        return nil
    }
    guard let string = value as? String else {
        throw MemoriesMCPArgumentError.invalidParams("invalid type for `\(field)`")
    }
    return string
}

private func requiredStringArray(_ value: Any?, field: String) throws -> [String] {
    guard let array = value as? [Any] else {
        throw MemoriesMCPArgumentError.invalidParams("missing field `\(field)`")
    }
    guard let strings = array as? [String] else {
        throw MemoriesMCPArgumentError.invalidParams("invalid type for `\(field)`")
    }
    return strings
}

private func optionalBool(_ value: Any?, field: String) throws -> Bool? {
    guard let value, !(value is NSNull) else {
        return nil
    }
    guard let bool = value as? Bool else {
        throw MemoriesMCPArgumentError.invalidParams("invalid type for `\(field)`")
    }
    return bool
}

private func optionalNonNegativeInteger(_ value: Any?, field: String) throws -> Int? {
    guard let integer = try optionalInteger(value, field: field) else {
        return nil
    }
    guard integer >= 0 else {
        throw MemoriesMCPArgumentError.invalidParams("invalid value for `\(field)`: must be at least 0")
    }
    return integer
}

private func optionalInteger(_ value: Any?, field: String) throws -> Int? {
    guard let value, !(value is NSNull) else {
        return nil
    }
    guard let integer = value as? Int else {
        throw MemoriesMCPArgumentError.invalidParams("invalid type for `\(field)`")
    }
    return integer
}

private func optionalMatchMode(_ value: Any?, field: String) throws -> SearchMatchMode? {
    guard let value, !(value is NSNull) else {
        return nil
    }
    guard let object = value as? [String: Any] else {
        throw MemoriesMCPArgumentError.invalidParams("invalid type for `\(field)`")
    }
    guard let type = object["type"] as? String else {
        throw MemoriesMCPArgumentError.invalidParams("missing field `type`")
    }
    switch type {
    case "any":
        try rejectUnknownFields(in: object, allowed: ["type"])
        return .any
    case "all_on_same_line":
        try rejectUnknownFields(in: object, allowed: ["type"])
        return .allOnSameLine
    case "all_within_lines":
        try rejectUnknownFields(in: object, allowed: ["type", "line_count"])
        guard let lineCount = try optionalNonNegativeInteger(object["line_count"], field: "line_count") else {
            throw MemoriesMCPArgumentError.invalidParams("missing field `line_count`")
        }
        return .allWithinLines(lineCount: lineCount)
    default:
        throw MemoriesMCPArgumentError.invalidParams("unknown variant `\(type)`")
    }
}
