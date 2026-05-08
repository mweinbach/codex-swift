import CodexCore
import Foundation

public struct CodexAppServerConfiguration: Equatable, Sendable {
    public let codexHome: URL
    public let defaultModelProvider: String

    public init(codexHome: URL, defaultModelProvider: String = "openai") {
        self.codexHome = codexHome
        self.defaultModelProvider = defaultModelProvider
    }
}

public enum CodexAppServer {
    private static let defaultListLimit = 25
    private static let maxListLimit = 100
    private static let interactiveSessionSources: [SessionSource] = [.cli, .vscode]

    public static func run(
        configuration: CodexAppServerConfiguration,
        stdin: FileHandle = .standardInput,
        stdout: FileHandle = .standardOutput
    ) throws {
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
                try write(processLine(Data(line), configuration: configuration), to: stdout)
            }
        }

        if !buffer.isEmpty {
            try write(processLine(buffer, configuration: configuration), to: stdout)
        }
    }

    static func processLine(
        _ data: Data,
        configuration: CodexAppServerConfiguration
    ) -> Data? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = object["id"],
              let method = object["method"] as? String
        else {
            return nil
        }

        let params = object["params"] as? [String: Any]
        let response: [String: Any]
        do {
            switch method {
            case "initialize":
                response = responseObject(id: id, result: [
                    "userAgent": "codex_cli_swift/0.0.0"
                ])
            case "thread/list":
                response = responseObject(
                    id: id,
                    result: try threadListResult(params: params, configuration: configuration)
                )
            case "listConversations":
                response = responseObject(
                    id: id,
                    result: try listConversationsResult(params: params, configuration: configuration)
                )
            default:
                response = errorObject(id: id, code: -32601, message: "method not found: \(method)")
            }
        } catch {
            response = errorObject(id: id, code: -32603, message: String(describing: error))
        }

        guard JSONSerialization.isValidJSONObject(response) else {
            return nil
        }
        return try? JSONSerialization.data(withJSONObject: response)
    }

    private static func threadListResult(
        params: [String: Any]?,
        configuration: CodexAppServerConfiguration
    ) throws -> [String: Any] {
        let page = try RolloutListing.getConversations(
            codexHome: configuration.codexHome,
            pageSize: listLimit(params?["limit"]),
            cursor: stringParam(params?["cursor"]).flatMap(RolloutListing.parseCursor),
            allowedSources: interactiveSessionSources,
            modelProviders: modelProviderFilter(params?["modelProviders"], defaultProvider: configuration.defaultModelProvider),
            defaultProvider: configuration.defaultModelProvider
        )
        return [
            "data": try page.items.map { try threadObject(for: $0, defaultProvider: configuration.defaultModelProvider) },
            "nextCursor": page.nextCursor?.token as Any
        ].nullStripped()
    }

    private static func listConversationsResult(
        params: [String: Any]?,
        configuration: CodexAppServerConfiguration
    ) throws -> [String: Any] {
        let page = try RolloutListing.getConversations(
            codexHome: configuration.codexHome,
            pageSize: listLimit(params?["pageSize"]),
            cursor: stringParam(params?["cursor"]).flatMap(RolloutListing.parseCursor),
            allowedSources: interactiveSessionSources,
            modelProviders: modelProviderFilter(params?["modelProviders"], defaultProvider: configuration.defaultModelProvider),
            defaultProvider: configuration.defaultModelProvider
        )
        return [
            "items": try page.items.map { try conversationObject(for: $0, defaultProvider: configuration.defaultModelProvider) },
            "nextCursor": page.nextCursor?.token as Any
        ].nullStripped()
    }

    private static func threadObject(for item: ConversationItem, defaultProvider: String) throws -> [String: Any] {
        let summary = try RolloutSummary(path: item.path, defaultProvider: defaultProvider)
        return [
            "id": summary.id,
            "preview": summary.preview,
            "modelProvider": summary.modelProvider,
            "createdAt": summary.createdAtUnixSeconds,
            "path": item.path,
            "cwd": summary.cwd,
            "cliVersion": summary.cliVersion,
            "source": appServerSource(summary.source),
            "gitInfo": summary.gitInfo as Any,
            "turns": []
        ].nullStripped()
    }

    private static func conversationObject(for item: ConversationItem, defaultProvider: String) throws -> [String: Any] {
        let summary = try RolloutSummary(path: item.path, defaultProvider: defaultProvider)
        return [
            "conversationId": summary.id,
            "path": item.path,
            "preview": summary.preview,
            "timestamp": item.createdAt as Any,
            "modelProvider": summary.modelProvider,
            "cwd": summary.cwd,
            "cliVersion": summary.cliVersion,
            "source": summary.source.description,
            "gitInfo": summary.v1GitInfo as Any
        ].nullStripped()
    }

    private static func appServerSource(_ source: SessionSource) -> String {
        switch source {
        case .cli:
            return "cli"
        case .vscode:
            return "vscode"
        case .exec:
            return "exec"
        case .mcp:
            return "appServer"
        case .subagent, .unknown:
            return "unknown"
        }
    }

    private static func listLimit(_ value: Any?) -> Int {
        min(max(intParam(value, defaultValue: defaultListLimit), 1), maxListLimit)
    }

    private static func intParam(_ value: Any?, defaultValue: Int) -> Int {
        if let int = value as? Int {
            return int
        }
        if let number = value as? NSNumber {
            return number.intValue
        }
        return defaultValue
    }

    private static func stringParam(_ value: Any?) -> String? {
        value as? String
    }

    private static func stringArrayParam(_ value: Any?) -> [String]? {
        value as? [String]
    }

    private static func modelProviderFilter(_ value: Any?, defaultProvider: String) -> [String]? {
        guard let providers = stringArrayParam(value) else {
            return [defaultProvider]
        }
        return providers.isEmpty ? nil : providers
    }

    private static func responseObject(id: Any, result: [String: Any]) -> [String: Any] {
        [
            "id": id,
            "result": result
        ]
    }

    private static func errorObject(id: Any, code: Int, message: String) -> [String: Any] {
        [
            "id": id,
            "error": [
                "code": code,
                "message": message
            ]
        ]
    }

    private static func write(_ data: Data?, to stdout: FileHandle) throws {
        guard let data else {
            return
        }
        try stdout.write(contentsOf: data)
        try stdout.write(contentsOf: Data([0x0A]))
    }
}

private struct RolloutSummary {
    let id: String
    let preview: String
    let modelProvider: String
    let createdAtUnixSeconds: Int
    let cwd: String
    let cliVersion: String
    let source: SessionSource
    let gitInfo: [String: Any]?
    let v1GitInfo: [String: Any]?

    init(path: String, defaultProvider: String) throws {
        let text = try String(contentsOf: URL(fileURLWithPath: path), encoding: .utf8)
        var meta: SessionMetaLine?
        var preview = ""

        for rawLine in text.split(whereSeparator: \.isNewline) {
            guard let data = rawLine.data(using: .utf8),
                  let line = try? JSONDecoder().decode(RolloutLine.self, from: data)
            else {
                continue
            }
            switch line.item {
            case let .sessionMeta(value):
                if meta == nil {
                    meta = value
                }
            case let .eventMsg(.userMessage(message)):
                if preview.isEmpty {
                    preview = message.message
                }
            case let .responseItem(item):
                if preview.isEmpty, let text = Self.itemPreview(item) {
                    preview = text
                }
            case .compacted,
                 .turnContext,
                 .eventMsg:
                continue
            }
            if meta != nil, !preview.isEmpty {
                break
            }
        }

        guard let meta else {
            throw RolloutRecorderError.missingConversationID
        }

        self.id = meta.meta.id.description
        self.preview = preview
        self.modelProvider = meta.meta.modelProvider ?? defaultProvider
        self.createdAtUnixSeconds = Self.unixSeconds(meta.meta.timestamp)
        self.cwd = meta.meta.cwd
        self.cliVersion = meta.meta.cliVersion
        self.source = meta.meta.source
        if let git = meta.git {
            self.gitInfo = [
                "sha": git.commitHash as Any,
                "branch": git.branch as Any,
                "originUrl": git.repositoryURL as Any
            ].nullStripped()
            self.v1GitInfo = [
                "sha": git.commitHash as Any,
                "branch": git.branch as Any,
                "origin_url": git.repositoryURL as Any
            ].nullStripped()
        } else {
            self.gitInfo = nil
            self.v1GitInfo = nil
        }
    }

    private static func itemPreview(_ item: ResponseItem) -> String? {
        guard case let .message(_, role, content) = item,
              role == "user"
        else {
            return nil
        }
        return content.compactMap { content -> String? in
            if case let .inputText(text) = content {
                return text
            }
            return nil
        }.joined(separator: "\n")
    }

    private static func unixSeconds(_ timestamp: String) -> Int {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: timestamp) {
            return Int(date.timeIntervalSince1970)
        }
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: timestamp) {
            return Int(date.timeIntervalSince1970)
        }
        return 0
    }
}

private extension Dictionary where Key == String, Value == Any {
    func nullStripped() -> [String: Any] {
        compactMapValues { value in
            if value is NSNull {
                return nil
            }
            let mirror = Mirror(reflecting: value)
            if mirror.displayStyle == .optional, mirror.children.isEmpty {
                return nil
            }
            return value
        }
    }
}
