import CodexCore
import Foundation

public struct DoctorMcpConfigCheckInputs: Equatable, Sendable {
    public let servers: [String: McpServerConfig]
    public let environment: [String: String]
    public let pathExecutableNames: Set<String>
    public let existingDirectories: Set<String>

    public init(
        servers: [String: McpServerConfig],
        environment: [String: String] = ProcessInfo.processInfo.environment,
        pathExecutableNames: Set<String> = [],
        existingDirectories: Set<String> = []
    ) {
        self.servers = servers
        self.environment = environment
        self.pathExecutableNames = pathExecutableNames
        self.existingDirectories = existingDirectories
    }
}

private enum DoctorMcpCommandResolution: Equatable {
    case resolved
    case failed(String)
}

extension DoctorCommandRuntime {
    public static func mcpConfigCheck(settings: CodexRuntimeConfig) -> DoctorCheck {
        mcpConfigCheck(inputs: DoctorMcpConfigCheckInputs(
            servers: settings.mcpServers,
            environment: ProcessInfo.processInfo.environment
        ))
    }

    public static func mcpConfigCheck(inputs: DoctorMcpConfigCheckInputs) -> DoctorCheck {
        let servers = inputs.servers
        guard !servers.isEmpty else {
            return DoctorCheck(
                id: "mcp.config",
                category: "mcp",
                status: .ok,
                summary: "no MCP servers configured"
            )
        }

        var details: [String] = []
        var transportCounts: [String: Int] = [:]
        var disabled = 0
        var missingEnv: [String] = []

        for name in servers.keys.sorted() {
            guard let server = servers[name] else {
                continue
            }
            let disabledServer = !server.enabled || server.disabledReason != nil
            if disabledServer {
                disabled += 1
            }
            switch server.transport {
            case let .stdio(command, _, env, envVars, cwd):
                transportCounts["stdio", default: 0] += 1
                guard !disabledServer else {
                    continue
                }
                if let cwd, !mcpDirectoryExists(cwd, inputs: inputs) {
                    missingEnv.append("\(name): cwd does not exist (\(cwd))")
                }
                if command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    missingEnv.append("\(name): stdio command is empty")
                } else if case let .failed(error) = mcpCommandResolution(command, cwd: cwd, serverEnv: env, inputs: inputs) {
                    missingEnv.append("\(name): stdio command \(debugString(command)) is not resolvable (\(error))")
                }
                if let env {
                    for key in env.keys.sorted() where key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        missingEnv.append("\(name): empty env key \(key)")
                    }
                }
                for envVar in envVars.sorted() where !mcpEnvironmentVariablePresent(envVar, inputs: inputs) {
                    missingEnv.append("\(name): env var \(envVar) is not set")
                }
            case let .streamableHttp(_, bearerTokenEnvVar, _, envHttpHeaders):
                transportCounts["streamable_http", default: 0] += 1
                guard !disabledServer else {
                    continue
                }
                if let bearerTokenEnvVar, !mcpEnvironmentVariablePresent(bearerTokenEnvVar, inputs: inputs) {
                    missingEnv.append("\(name): bearer token env var \(bearerTokenEnvVar) is not set")
                }
                if let envHttpHeaders {
                    for envVar in envHttpHeaders.values.sorted() where !mcpEnvironmentVariablePresent(envVar, inputs: inputs) {
                        missingEnv.append("\(name): header env var \(envVar) is not set")
                    }
                }
            }
        }

        details.append("configured servers: \(servers.count)")
        details.append("disabled servers: \(disabled)")
        for transport in transportCounts.keys.sorted() {
            details.append("\(transport) servers: \(transportCounts[transport] ?? 0)")
        }
        details.append(contentsOf: missingEnv)

        let requiredMissing = servers.contains { name, server in
            server.required && missingEnv.contains { $0.hasPrefix("\(name):") }
        }
        let status: DoctorCheckStatus = if requiredMissing {
            .fail
        } else if missingEnv.isEmpty {
            .ok
        } else {
            .warning
        }
        let summary = switch status {
        case .ok:
            "MCP configuration is locally consistent"
        case .warning:
            "MCP configuration has optional issues"
        case .fail:
            "MCP configuration has failing required inputs or reachability"
        }

        return DoctorCheck(
            id: "mcp.config",
            category: "mcp",
            status: status,
            summary: summary,
            details: details,
            remediation: status == .ok
                ? nil
                : "Set the missing MCP env vars or disable the affected server."
        )
    }

    private static func mcpEnvironmentVariablePresent(
        _ name: String,
        inputs: DoctorMcpConfigCheckInputs
    ) -> Bool {
        guard let value = inputs.environment[name] else {
            return false
        }
        return !value.isEmpty
    }

    private static func mcpDirectoryExists(
        _ path: String,
        inputs: DoctorMcpConfigCheckInputs
    ) -> Bool {
        if inputs.existingDirectories.contains(path) {
            return true
        }
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private static func mcpCommandResolution(
        _ command: String,
        cwd: String?,
        serverEnv: [String: String]?,
        inputs: DoctorMcpConfigCheckInputs
    ) -> DoctorMcpCommandResolution {
        if inputs.pathExecutableNames.contains(command) {
            return .resolved
        }
        if command.contains("/") {
            let path: String
            if command.hasPrefix("/") {
                path = NSString(string: command).expandingTildeInPath
            } else {
                let base = cwd ?? FileManager.default.currentDirectoryPath
                path = URL(fileURLWithPath: base, isDirectory: true)
                    .appendingPathComponent(command, isDirectory: false)
                    .standardizedFileURL
                    .path
            }
            return mcpExecutablePathResult(path)
        }
        guard let pathValue = serverEnv?["PATH"] ?? inputs.environment["PATH"] else {
            return .failed("PATH is not set")
        }
        let pathEntries = pathValue
            .split(separator: ":", omittingEmptySubsequences: false)
            .map(String.init)
        let found = pathEntries.contains { entry in
            let directory = entry.isEmpty ? "." : entry
            let candidate = URL(fileURLWithPath: directory, isDirectory: true)
                .appendingPathComponent(command, isDirectory: false)
                .path
            return FileManager.default.isExecutableFile(atPath: candidate)
        }
        return found ? .resolved : .failed("not found on PATH")
    }

    private static func mcpExecutablePathResult(_ path: String) -> DoctorMcpCommandResolution {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else {
            return .failed("No such file or directory")
        }
        guard !isDirectory.boolValue else {
            return .failed("path is not a file")
        }
        guard FileManager.default.isExecutableFile(atPath: path) else {
            return .failed("\(path) is not executable")
        }
        return .resolved
    }

    private static func debugString(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}
