import Foundation

public enum McpRequiredStartupValidator {
    public static func startupFailures(
        mcpServers: [String: McpServerConfig],
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> [McpStartupFailure] {
        mcpServers
            .filter { _, config in config.enabled && config.required }
            .sorted { lhs, rhs in lhs.key < rhs.key }
            .compactMap { name, config in
                guard case let .stdio(command, _, _, _, cwd) = config.transport,
                      !canResolveExecutable(command, cwd: cwd, environment: environment, fileManager: fileManager)
                else {
                    return nil
                }
                return McpStartupFailure(server: name, error: "command not found: \(command)")
            }
    }

    public static func requiredStartupFailureMessage(for failures: [McpStartupFailure]) -> String? {
        guard !failures.isEmpty else {
            return nil
        }
        let details = failures
            .map { "\($0.server): \($0.error)" }
            .joined(separator: "; ")
        return "required MCP servers failed to initialize: \(details)"
    }

    public static func requiredStartupFailureMessage(
        mcpServers: [String: McpServerConfig],
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> String? {
        requiredStartupFailureMessage(for: startupFailures(
            mcpServers: mcpServers,
            environment: environment,
            fileManager: fileManager
        ))
    }

    private static func canResolveExecutable(
        _ command: String,
        cwd: String?,
        environment: [String: String],
        fileManager: FileManager
    ) -> Bool {
        guard !command.isEmpty else {
            return false
        }
        if command.contains("/") {
            let expanded = NSString(string: command).expandingTildeInPath
            let path = URL(fileURLWithPath: expanded, relativeTo: cwd.map {
                URL(fileURLWithPath: $0, isDirectory: true)
            }).standardizedFileURL.path
            return fileManager.isExecutableFile(atPath: path)
        }
        let pathEntries = (environment["PATH"] ?? ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":", omittingEmptySubsequences: false)
            .map(String.init)
        return pathEntries.contains { entry in
            let directory = entry.isEmpty ? "." : entry
            let candidate = URL(fileURLWithPath: directory, isDirectory: true)
                .appendingPathComponent(command, isDirectory: false)
                .path
            return fileManager.isExecutableFile(atPath: candidate)
        }
    }
}
