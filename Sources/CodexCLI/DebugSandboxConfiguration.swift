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
        public let permissionProfile: PermissionProfile
        public let cwd: URL

        public init(
            sandboxPolicy: SandboxPolicy,
            permissionProfile: PermissionProfile? = nil,
            cwd: URL
        ) {
            self.sandboxPolicy = sandboxPolicy
            self.permissionProfile = permissionProfile ?? .fromLegacySandboxPolicyForCwd(
                sandboxPolicy,
                cwd: cwd.standardizedFileURL.path
            )
            self.cwd = cwd
        }
    }

    public enum DebugSandboxConfigurationError: Error, Equatable, CustomStringConvertible, Sendable {
        case customProfile(String)
        case unknownBuiltinProfile(String)

        public var description: String {
            switch self {
            case let .customProfile(profileName):
                return "default_permissions refers to undefined profile `\(profileName)`"
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
        let defaultConfig = try debugSandboxDefaultConfiguration(
            profile: profile,
            configOverrides: configOverrides,
            codexHome: codexHome,
            cwd: cwd,
            environment: environment
        )
        switch profile.resolveBuiltInPolicy(defaultPolicy: defaultConfig.sandboxPolicy) {
        case let .resolved(sandboxPolicy):
            return DebugSandboxConfiguration(
                sandboxPolicy: sandboxPolicy,
                permissionProfile: defaultConfig.permissionProfile,
                cwd: cwd
            )
        case let .customProfile(profileName):
            let config = try loadDebugSandboxConfig(
                permissionsProfile: profileName,
                configOverrides: configOverrides,
                codexHome: codexHome,
                cwd: cwd,
                environment: environment
            )
            return try configuration(from: config, cwd: cwd)
        case let .unknownBuiltinProfile(profileName):
            throw DebugSandboxConfigurationError.unknownBuiltinProfile(profileName)
        }
    }

    private static func debugSandboxDefaultConfiguration(
        profile: SandboxProfileOptions,
        configOverrides: CliConfigOverrides,
        codexHome: URL,
        cwd: URL,
        environment: [String: String]
    ) throws -> DebugSandboxConfiguration {
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
            return try configuration(from: config, cwd: cwd)
        }

        if let permissionsProfile = profile.permissionsProfile {
            let config = try loadDebugSandboxConfig(
                permissionsProfile: permissionsProfile,
                configOverrides: configOverrides,
                codexHome: codexHome,
                cwd: cwd,
                environment: environment
            )
            return try configuration(from: config, cwd: cwd)
        }

        let ambientConfig = try CodexConfigLoader.load(
            codexHome: codexHome,
            cwd: cwd,
            overrides: configOverrides,
            environment: environment
        )
        if ambientConfig.defaultPermissions != nil {
            return try configuration(from: ambientConfig, cwd: cwd)
        }

        if try configOverrides.parseOverrides().contains(where: { key, _ in key == "sandbox_mode" }) {
            let config = try CodexConfigLoader.load(
                codexHome: codexHome,
                cwd: cwd,
                overrides: configOverrides,
                environment: environment
            )
            return try configuration(from: config, cwd: cwd)
        }

        return DebugSandboxConfiguration(sandboxPolicy: .newReadOnlyPolicy(), cwd: cwd)
    }

    private static func loadDebugSandboxConfig(
        permissionsProfile: String,
        configOverrides: CliConfigOverrides,
        codexHome: URL,
        cwd: URL,
        environment: [String: String]
    ) throws -> CodexRuntimeConfig {
        try CodexConfigLoader.load(
            codexHome: codexHome,
            cwd: cwd,
            overrides: CliConfigOverrides(
                rawOverrides: configOverrides.rawOverrides + [
                    #"default_permissions="\#(escapedTomlStringBody(permissionsProfile))""#
                ]
            ),
            environment: environment
        )
    }

    private static func configuration(
        from config: CodexRuntimeConfig,
        cwd: URL
    ) throws -> DebugSandboxConfiguration {
        let permissionProfile = config.permissionProfile
            ?? .fromLegacySandboxPolicyForCwd(config.legacySandboxPolicy(defaultMode: .readOnly), cwd: cwd.path)
        let sandboxPolicy = try permissionProfile.fileSystemSandboxPolicy.toLegacySandboxPolicy(
            networkPolicy: permissionProfile.networkSandboxPolicy,
            cwd: cwd.standardizedFileURL.path
        )
        return DebugSandboxConfiguration(
            sandboxPolicy: sandboxPolicy,
            permissionProfile: permissionProfile,
            cwd: cwd
        )
    }

    private static func tomlQuotedKeySegment(_ value: String) -> String {
        let data = try? JSONEncoder().encode(value)
        return data.flatMap { String(data: $0, encoding: .utf8) } ?? #""""#
    }

    private static func escapedTomlStringBody(_ value: String) -> String {
        let data = try? JSONEncoder().encode(value)
        let encoded = data.flatMap { String(data: $0, encoding: .utf8) } ?? #""""#
        return String(encoded.dropFirst().dropLast())
    }
}
