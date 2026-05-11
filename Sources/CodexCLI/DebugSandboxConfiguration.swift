import CodexCore
import Foundation

extension CodexCLI.SandboxProfileOptions {
    public func resolvedCwd(relativeTo processCwd: URL) -> URL {
        guard let cwd, !cwd.isEmpty else {
            return processCwd
        }
        if cwd.hasPrefix("/") {
            return URL(fileURLWithPath: cwd, isDirectory: true)
        }
        return processCwd.appendingPathComponent(cwd, isDirectory: true)
    }
}

extension CodexCLI {
    public struct DebugSandboxConfiguration: Equatable, Sendable {
        public let sandboxPolicy: SandboxPolicy
        public let cwd: URL

        public init(sandboxPolicy: SandboxPolicy, cwd: URL) {
            self.sandboxPolicy = sandboxPolicy
            self.cwd = cwd
        }
    }

    public enum DebugSandboxConfigurationError: Error, Equatable, CustomStringConvertible, Sendable {
        case customProfile(String)
        case unknownBuiltinProfile(String)

        public var description: String {
            switch self {
            case .customProfile:
                return "codex-swift: sandbox permission profile runtime is not complete yet."
            case let .unknownBuiltinProfile(profileName):
                return "default_permissions refers to unknown built-in profile `\(profileName)`"
            }
        }
    }

    public static func resolveDebugSandboxConfiguration(
        profile: SandboxProfileOptions,
        configOverrides: CliConfigOverrides,
        codexHome: URL,
        processCwd: URL,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> DebugSandboxConfiguration {
        let cwd = profile.resolvedCwd(relativeTo: processCwd)
        let defaultPolicy = try debugSandboxDefaultPolicy(
            profile: profile,
            configOverrides: configOverrides,
            codexHome: codexHome,
            cwd: cwd,
            environment: environment
        )
        switch profile.resolveBuiltInPolicy(defaultPolicy: defaultPolicy) {
        case let .resolved(sandboxPolicy):
            return DebugSandboxConfiguration(sandboxPolicy: sandboxPolicy, cwd: cwd)
        case let .customProfile(profileName):
            throw DebugSandboxConfigurationError.customProfile(profileName)
        case let .unknownBuiltinProfile(profileName):
            throw DebugSandboxConfigurationError.unknownBuiltinProfile(profileName)
        }
    }

    private static func debugSandboxDefaultPolicy(
        profile: SandboxProfileOptions,
        configOverrides: CliConfigOverrides,
        codexHome: URL,
        cwd: URL,
        environment: [String: String]
    ) throws -> SandboxPolicy {
        if profile.permissionsProfile == ":workspace" {
            let workspaceOverrides = configOverrides.rawOverrides + [#"sandbox_mode="workspace-write""#]
            var config = try CodexConfigLoader.load(
                codexHome: codexHome,
                cwd: cwd,
                overrides: CliConfigOverrides(rawOverrides: workspaceOverrides),
                environment: environment
            )
            if let activeProfile = config.activeProfile {
                config = try CodexConfigLoader.load(
                    codexHome: codexHome,
                    cwd: cwd,
                    overrides: CliConfigOverrides(rawOverrides: workspaceOverrides + [
                        #"profiles.\#(tomlQuotedKeySegment(activeProfile)).sandbox_mode="workspace-write""#
                    ]),
                    environment: environment
                )
            }
            return config.legacySandboxPolicy(defaultMode: .readOnly)
        }

        if try configOverrides.parseOverrides().contains(where: { key, _ in key == "sandbox_mode" }) {
            return try CodexConfigLoader.load(
                codexHome: codexHome,
                cwd: cwd,
                overrides: configOverrides,
                environment: environment
            ).legacySandboxPolicy(defaultMode: .readOnly)
        }

        return .newReadOnlyPolicy()
    }

    private static func tomlQuotedKeySegment(_ value: String) -> String {
        let data = try? JSONEncoder().encode(value)
        return data.flatMap { String(data: $0, encoding: .utf8) } ?? #""""#
    }
}
