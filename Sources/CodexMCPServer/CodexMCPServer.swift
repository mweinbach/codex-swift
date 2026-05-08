import CodexCore
import Foundation

public struct CodexMCPToolCall: Equatable, Sendable {
    public let prompt: String
    public let model: String?
    public let profile: String?
    public let cwd: String?
    public let approvalPolicy: String?
    public let sandbox: String?
    public let config: [String: AnyJSONValue]
    public let baseInstructions: String?
    public let developerInstructions: String?
    public let compactPrompt: String?

    public init(
        prompt: String,
        model: String? = nil,
        profile: String? = nil,
        cwd: String? = nil,
        approvalPolicy: String? = nil,
        sandbox: String? = nil,
        config: [String: AnyJSONValue] = [:],
        baseInstructions: String? = nil,
        developerInstructions: String? = nil,
        compactPrompt: String? = nil
    ) {
        self.prompt = prompt
        self.model = model
        self.profile = profile
        self.cwd = cwd
        self.approvalPolicy = approvalPolicy
        self.sandbox = sandbox
        self.config = config
        self.baseInstructions = baseInstructions
        self.developerInstructions = developerInstructions
        self.compactPrompt = compactPrompt
    }
}

public struct CodexMCPToolReply: Equatable, Sendable {
    public let conversationID: String
    public let prompt: String

    public init(conversationID: String, prompt: String) {
        self.conversationID = conversationID
        self.prompt = prompt
    }
}

public struct CodexMCPToolResult: Equatable, Sendable {
    public let text: String
    public let isError: Bool

    public init(text: String, isError: Bool = false) {
        self.text = text
        self.isError = isError
    }
}

public enum CodexMCPServerError: Error, Equatable, CustomStringConvertible, Sendable {
    case invalidToolArguments(String)
    case missingPrompt

    public var description: String {
        switch self {
        case let .invalidToolArguments(message):
            return message
        case .missingPrompt:
            return "Missing arguments for codex tool-call; the `prompt` field is required."
        }
    }
}

public enum CodexMCPServer {
    public typealias CodexToolRunner = @Sendable (CodexMCPToolCall) async throws -> CodexMCPToolResult
    public typealias CodexReplyRunner = @Sendable (CodexMCPToolReply) async throws -> CodexMCPToolResult

    public static func run(
        stdin: FileHandle = .standardInput,
        stdout: FileHandle = .standardOutput,
        codexToolRunner: @escaping CodexToolRunner,
        codexReplyRunner: CodexReplyRunner? = nil
    ) async throws {
        var state = CodexMCPServerState()
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
                let responses = await processLine(
                    Data(line),
                    state: &state,
                    codexToolRunner: codexToolRunner,
                    codexReplyRunner: codexReplyRunner
                )
                try write(responses, to: stdout)
            }
        }

        if !buffer.isEmpty {
            let responses = await processLine(
                buffer,
                state: &state,
                codexToolRunner: codexToolRunner,
                codexReplyRunner: codexReplyRunner
            )
            try write(responses, to: stdout)
        }
    }

    static func processLine(
        _ data: Data,
        state: inout CodexMCPServerState,
        codexToolRunner: CodexToolRunner,
        codexReplyRunner: CodexReplyRunner? = nil
    ) async -> [Data] {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let method = object["method"] as? String
        else {
            return []
        }

        let id = object["id"]
        let params = object["params"] as? [String: Any]
        if id == nil {
            handleNotification(method: method, params: params, state: &state)
            return []
        }

        let response: [String: Any]
        switch method {
        case "initialize":
            response = handleInitialize(id: id as Any, params: params, state: &state)
        case "ping":
            response = jsonRPCResponse(id: id as Any, result: [:])
        case "tools/list":
            response = jsonRPCResponse(id: id as Any, result: toolsListResult())
        case "tools/call":
            response = await handleToolCall(
                id: id as Any,
                params: params,
                codexToolRunner: codexToolRunner,
                codexReplyRunner: codexReplyRunner
            )
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

    private static func handleNotification(
        method: String,
        params _: [String: Any]?,
        state _: inout CodexMCPServerState
    ) {
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
        state: inout CodexMCPServerState
    ) -> [String: Any] {
        guard !state.initialized else {
            return jsonRPCError(id: id, code: -32600, message: "initialize called more than once")
        }

        state.initialized = true
        let protocolVersion = params?["protocolVersion"] as? String ?? "2025-06-18"
        let clientInfo = params?["clientInfo"] as? [String: Any]
        let userAgent = buildUserAgent(clientInfo: clientInfo)
        return jsonRPCResponse(id: id, result: [
            "capabilities": [
                "tools": [
                    "listChanged": true
                ]
            ],
            "protocolVersion": protocolVersion,
            "serverInfo": [
                "name": "codex-mcp-server",
                "title": "Codex",
                "version": "0.0.0",
                "userAgent": userAgent
            ]
        ])
    }

    private static func buildUserAgent(
        clientInfo: [String: Any]?,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String {
        let clientName = (clientInfo?["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let clientVersion = (clientInfo?["version"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let suffix = clientName.isEmpty && clientVersion.isEmpty ? "" : " (\(clientName); \(clientVersion))"
        return sanitizeHeaderValue("codex_swift/0.0.0 \(Terminal.userAgent(environment: environment))\(suffix)")
    }

    private static func sanitizeHeaderValue(_ value: String) -> String {
        String(value.map { character in
            character.asciiValue.map { (0x20...0x7E).contains($0) } == true ? character : "_"
        })
    }

    private static func handleToolCall(
        id: Any,
        params: [String: Any]?,
        codexToolRunner: CodexToolRunner,
        codexReplyRunner: CodexReplyRunner?
    ) async -> [String: Any] {
        guard let name = params?["name"] as? String else {
            return toolResponse(id: id, text: "Missing tool name.", isError: true)
        }
        let arguments = params?["arguments"] as? [String: Any]

        do {
            switch name {
            case "codex":
                let call = try decodeCodexToolCall(arguments)
                let result = try await codexToolRunner(call)
                return toolResponse(id: id, text: result.text, isError: result.isError)
            case "codex-reply":
                guard let codexReplyRunner else {
                    return toolResponse(id: id, text: "codex-reply is not available in this server.", isError: true)
                }
                let reply = try decodeCodexReply(arguments)
                let result = try await codexReplyRunner(reply)
                return toolResponse(id: id, text: result.text, isError: result.isError)
            default:
                return toolResponse(id: id, text: "Unknown tool '\(name)'", isError: true)
            }
        } catch let error as CodexMCPServerError {
            return toolResponse(id: id, text: error.description, isError: true)
        } catch {
            return toolResponse(id: id, text: String(describing: error), isError: true)
        }
    }

    private static func decodeCodexToolCall(_ arguments: [String: Any]?) throws -> CodexMCPToolCall {
        guard let arguments else {
            throw CodexMCPServerError.missingPrompt
        }
        guard let prompt = arguments["prompt"] as? String, !prompt.isEmpty else {
            throw CodexMCPServerError.missingPrompt
        }

        return CodexMCPToolCall(
            prompt: prompt,
            model: arguments["model"] as? String,
            profile: arguments["profile"] as? String,
            cwd: arguments["cwd"] as? String,
            approvalPolicy: arguments["approval-policy"] as? String,
            sandbox: arguments["sandbox"] as? String,
            config: (arguments["config"] as? [String: Any] ?? [:]).mapValues(AnyJSONValue.fromJSONObject),
            baseInstructions: arguments["base-instructions"] as? String,
            developerInstructions: arguments["developer-instructions"] as? String,
            compactPrompt: arguments["compact-prompt"] as? String
        )
    }

    private static func decodeCodexReply(_ arguments: [String: Any]?) throws -> CodexMCPToolReply {
        guard let arguments,
              let conversationID = arguments["conversationId"] as? String,
              let prompt = arguments["prompt"] as? String
        else {
            throw CodexMCPServerError.invalidToolArguments(
                "Missing arguments for codex-reply tool-call; the `conversation_id` and `prompt` fields are required."
            )
        }
        return CodexMCPToolReply(conversationID: conversationID, prompt: prompt)
    }

    private static func toolsListResult() -> [String: Any] {
        [
            "tools": [
                [
                    "name": "codex",
                    "title": "Codex",
                    "description": "Run a Codex session. Accepts configuration parameters matching the Codex Config struct.",
                    "inputSchema": [
                        "type": "object",
                        "required": ["prompt"],
                        "properties": [
                            "prompt": [
                                "type": "string",
                                "description": "The initial user prompt to start the Codex conversation."
                            ],
                            "model": [
                                "type": "string",
                                "description": #"Optional override for the model name (e.g. "o3", "o4-mini")."#
                            ],
                            "profile": [
                                "type": "string",
                                "description": "Configuration profile from config.toml to specify default options."
                            ],
                            "cwd": [
                                "type": "string",
                                "description": "Working directory for the session. If relative, it is resolved against the server process's current working directory."
                            ],
                            "approval-policy": [
                                "type": "string",
                                "description": "Approval policy for shell commands generated by the model: `untrusted`, `on-failure`, `on-request`, `never`.",
                                "enum": ["untrusted", "on-failure", "on-request", "never"]
                            ],
                            "sandbox": [
                                "type": "string",
                                "description": "Sandbox mode: `read-only`, `workspace-write`, or `danger-full-access`.",
                                "enum": ["read-only", "workspace-write", "danger-full-access"]
                            ],
                            "config": [
                                "type": "object",
                                "description": "Individual config settings that will override what is in CODEX_HOME/config.toml.",
                                "additionalProperties": true
                            ],
                            "base-instructions": [
                                "type": "string",
                                "description": "The set of instructions to use instead of the default ones."
                            ],
                            "developer-instructions": [
                                "type": "string",
                                "description": "Developer instructions that should be injected as a developer role message."
                            ],
                            "compact-prompt": [
                                "type": "string",
                                "description": "Prompt used when compacting the conversation."
                            ]
                        ]
                    ]
                ],
                [
                    "name": "codex-reply",
                    "title": "Codex Reply",
                    "description": "Continue a Codex conversation by providing the conversation id and prompt.",
                    "inputSchema": [
                        "type": "object",
                        "required": ["conversationId", "prompt"],
                        "properties": [
                            "conversationId": [
                                "type": "string",
                                "description": "The conversation id for this Codex session."
                            ],
                            "prompt": [
                                "type": "string",
                                "description": "The *next user prompt* to continue the Codex conversation."
                            ]
                        ]
                    ]
                ]
            ]
        ]
    }

    private static func toolResponse(id: Any, text: String, isError: Bool) -> [String: Any] {
        var result: [String: Any] = [
            "content": [
                [
                    "type": "text",
                    "text": text
                ]
            ]
        ]
        if isError {
            result["isError"] = true
        }
        return jsonRPCResponse(id: id, result: result)
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

struct CodexMCPServerState {
    var initialized = false
}
