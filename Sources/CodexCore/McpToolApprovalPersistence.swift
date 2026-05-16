import Foundation

public enum McpToolApprovalPersistenceError: Error, Equatable, CustomStringConvertible, Sendable {
    case missingConnectorID
    case mcpServerNotConfigured(String)

    public var description: String {
        switch self {
        case .missingConnectorID:
            return "codex_apps MCP tool approval persistence requires a connector_id"
        case let .mcpServerNotConfigured(server):
            return "MCP server `\(server)` is not configured in config.toml"
        }
    }
}

public enum McpToolApprovalPersistence {
    public static func persistMcpToolApproval(
        codexHome: URL,
        key: McpToolApprovalKey,
        fileManager: FileManager = .default
    ) throws {
        if key.server == codexAppsMCPServerName {
            guard let connectorID = key.connectorID else {
                throw McpToolApprovalPersistenceError.missingConnectorID
            }
            try persistCodexAppToolApproval(
                codexHome: codexHome,
                connectorID: connectorID,
                toolName: key.toolName,
                fileManager: fileManager
            )
            return
        }

        try persistCustomMcpToolApproval(
            codexHome: codexHome,
            serverName: key.server,
            toolName: key.toolName,
            fileManager: fileManager
        )
    }

    public static func persistCodexAppToolApproval(
        codexHome: URL,
        connectorID: String,
        toolName: String,
        fileManager: FileManager = .default
    ) throws {
        try fileManager.createDirectory(at: codexHome, withIntermediateDirectories: true)
        let configFile = codexHome.appendingPathComponent("config.toml", isDirectory: false)
        let existing = fileManager.fileExists(atPath: configFile.path)
            ? try String(contentsOf: configFile, encoding: .utf8)
            : ""
        var next = existing
        next = setTomlAssignment(
            in: next,
            tablePath: ["apps", connectorID],
            key: "enabled",
            literal: "true"
        )
        next = setTomlAssignment(
            in: next,
            tablePath: ["apps", connectorID, "tools", toolName],
            key: "approval_mode",
            literal: tomlString(AppToolApproval.approve.rawValue)
        )
        try next.write(to: configFile, atomically: true, encoding: .utf8)
    }

    public static func persistCustomMcpToolApproval(
        codexHome: URL,
        serverName: String,
        toolName: String,
        fileManager: FileManager = .default
    ) throws {
        var servers = try McpConfigStore.loadGlobalMcpServers(
            codexHome: codexHome,
            fileManager: fileManager
        )
        guard var server = servers[serverName] else {
            throw McpToolApprovalPersistenceError.mcpServerNotConfigured(serverName)
        }

        server.tools[toolName] = McpServerToolConfig(approvalMode: .approve)
        servers[serverName] = server
        try McpConfigStore.replaceGlobalMcpServers(
            codexHome: codexHome,
            servers: servers,
            fileManager: fileManager
        )
    }

    private static func setTomlAssignment(
        in contents: String,
        tablePath: [String],
        key: String,
        literal: String
    ) -> String {
        var lines = contents.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if lines == [""] {
            lines = []
        }

        let header = "[\(tablePath.map(tomlKey).joined(separator: "."))]"
        if let tableStart = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == header }) {
            let tableEnd = nextTableIndex(in: lines, after: tableStart) ?? lines.endIndex
            if let assignmentIndex = lines[lines.index(after: tableStart)..<tableEnd].firstIndex(
                where: { lineContainsAssignment($0, key: key) }
            ) {
                lines[assignmentIndex] = "\(key) = \(literal)"
            } else {
                lines.insert("\(key) = \(literal)", at: lines.index(after: tableStart))
            }
        } else {
            if let last = lines.last, !last.trimmingCharacters(in: .whitespaces).isEmpty {
                lines.append("")
            }
            lines.append(header)
            lines.append("\(key) = \(literal)")
        }

        return lines.joined(separator: "\n") + "\n"
    }

    private static func nextTableIndex(in lines: [String], after index: Int) -> Int? {
        lines[lines.index(after: index)...].firstIndex { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return trimmed.hasPrefix("[") && trimmed.hasSuffix("]")
        }
    }

    private static func lineContainsAssignment(_ line: String, key: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("\(key) =") || trimmed.hasPrefix("\(key)=")
    }

    private static func tomlKey(_ value: String) -> String {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-")
        if value.unicodeScalars.allSatisfy({ allowed.contains($0) }) {
            return value
        }
        return tomlString(value)
    }

    private static func tomlString(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}
