import CodexCore
import XCTest

final class HookConfigTests: XCTestCase {
    func testConfiguredHandlersSkipUntrustedUserHooks() throws {
        let stack = try ConfigLayerStack(layers: [
            ConfigLayerEntry(name: .user(file: try path("/tmp/config.toml")), config: hookConfig(command: "echo no"))
        ])

        XCTAssertEqual(HookConfig.configuredHandlers(from: stack), [])
    }

    func testConfiguredHandlersIncludeTrustedUserHooks() throws {
        let command = "echo ${NAME}"
        let key = HookConfig.hookKey(
            keySource: "/tmp/config.toml",
            eventName: .userPromptSubmit,
            groupIndex: 0,
            handlerIndex: 0
        )
        let hash = HookConfig.commandHookHash(
            eventName: .userPromptSubmit,
            matcher: nil,
            command: command,
            timeoutSec: 7,
            statusMessage: "checking"
        )
        let stack = try ConfigLayerStack(layers: [
            ConfigLayerEntry(
                name: .user(file: try path("/tmp/config.toml")),
                config: hookConfig(command: command, timeoutSec: 7, statusMessage: "checking", trustedKey: key, trustedHash: hash)
            )
        ])

        let handlers = HookConfig.configuredHandlers(from: stack, environment: ["NAME": "swift"])

        XCTAssertEqual(handlers, [
            ConfiguredHookHandler(
                eventName: .userPromptSubmit,
                matcher: nil,
                command: "echo swift",
                timeoutSec: 7,
                statusMessage: "checking",
                sourcePath: try path("/tmp/config.toml"),
                source: .user,
                displayOrder: 0
            )
        ])
    }

    func testConfiguredHandlersRespectDisabledTrustedHookState() throws {
        let command = "echo no"
        let key = HookConfig.hookKey(
            keySource: "/tmp/config.toml",
            eventName: .userPromptSubmit,
            groupIndex: 0,
            handlerIndex: 0
        )
        let hash = HookConfig.commandHookHash(
            eventName: .userPromptSubmit,
            matcher: nil,
            command: command,
            timeoutSec: 600,
            statusMessage: nil
        )
        let stack = try ConfigLayerStack(layers: [
            ConfigLayerEntry(
                name: .user(file: try path("/tmp/config.toml")),
                config: hookConfig(command: command, trustedKey: key, trustedHash: hash, enabled: false)
            )
        ])

        XCTAssertEqual(HookConfig.configuredHandlers(from: stack), [])
    }

    func testConfiguredHandlersIncludeManagedHooksWithoutTrustState() throws {
        let stack = try ConfigLayerStack(
            layers: [],
            requirements: ConfigRequirements(managedHooks: ManagedHooksRequirement(
                value: ManagedHooksRequirementsToml(
                    managedDir: "/tmp/managed-hooks",
                    hooks: hookGroups(command: "echo managed")
                ),
                source: .system,
                sourceDescription: "/etc/codex/requirements.toml"
            ))
        )

        let handlers = HookConfig.configuredHandlers(from: stack)

        XCTAssertEqual(handlers, [
            ConfiguredHookHandler(
                eventName: .userPromptSubmit,
                matcher: nil,
                command: "echo managed",
                timeoutSec: 600,
                sourcePath: try path("/tmp/managed-hooks"),
                source: .system,
                displayOrder: 0
            )
        ])
    }

    func testConfiguredHandlersIncludeTrustedEnabledPluginHooks() throws {
        let codexHome = try HookConfigTemporaryDirectory()
        let pluginRoot = codexHome.url.appendingPathComponent("plugins/cache/test/demo/local", isDirectory: true)
        let manifestRoot = pluginRoot.appendingPathComponent(".codex-plugin", isDirectory: true)
        let hooksRoot = pluginRoot.appendingPathComponent("hooks", isDirectory: true)
        try FileManager.default.createDirectory(at: manifestRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: hooksRoot, withIntermediateDirectories: true)
        try #"{"name":"demo"}"#.write(
            to: manifestRoot.appendingPathComponent("plugin.json", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        try """
        {
          "hooks": {
            "PreToolUse": [
              {
                "matcher": "Bash",
                "hooks": [
                  {
                    "type": "command",
                    "command": "echo ${NAME}",
                    "timeout": 7,
                    "statusMessage": "running plugin hook"
                  }
                ]
              }
            ]
          }
        }
        """.write(to: hooksRoot.appendingPathComponent("hooks.json", isDirectory: false), atomically: true, encoding: .utf8)
        let key = HookConfig.pluginHookKey(
            pluginID: "demo@test",
            sourcePath: "hooks/hooks.json",
            eventName: .preToolUse,
            groupIndex: 0,
            handlerIndex: 0
        )
        let hash = HookConfig.commandHookHash(
            eventName: .preToolUse,
            matcher: "Bash",
            command: "echo ${NAME}",
            timeoutSec: 7,
            statusMessage: "running plugin hook"
        )
        let stack = try ConfigLayerStack(layers: [
            ConfigLayerEntry(name: .user(file: try path(codexHome.url.appendingPathComponent("config.toml").path)), config: .table([
                "features": .table([
                    "hooks": .bool(true),
                    "plugins": .bool(true),
                    "plugin_hooks": .bool(true)
                ]),
                "plugins": .table([
                    "demo@test": .table(["enabled": .bool(true)])
                ]),
                "hooks": .table([
                    "state": .table([
                        key: .table(["trusted_hash": .string(hash)])
                    ])
                ])
            ]))
        ])

        let handlers = HookConfig.configuredHandlers(
            from: stack,
            codexHome: codexHome.url,
            environment: ["NAME": "swift"]
        )

        XCTAssertEqual(handlers, [
            ConfiguredHookHandler(
                eventName: .preToolUse,
                matcher: "Bash",
                command: "echo swift",
                timeoutSec: 7,
                statusMessage: "running plugin hook",
                sourcePath: try path(hooksRoot.appendingPathComponent("hooks.json").standardizedFileURL.path),
                source: .plugin,
                displayOrder: 0
            )
        ])
    }

    func testConfiguredHandlersSkipUntrustedPluginHooks() throws {
        let codexHome = try HookConfigTemporaryDirectory()
        let pluginRoot = codexHome.url.appendingPathComponent("plugins/cache/test/demo/local", isDirectory: true)
        let hooksRoot = pluginRoot.appendingPathComponent("hooks", isDirectory: true)
        try FileManager.default.createDirectory(at: hooksRoot, withIntermediateDirectories: true)
        try """
        {
          "hooks": {
            "PreToolUse": [
              {
                "matcher": "Bash",
                "hooks": [{"type": "command", "command": "echo no"}]
              }
            ]
          }
        }
        """.write(to: hooksRoot.appendingPathComponent("hooks.json", isDirectory: false), atomically: true, encoding: .utf8)
        let stack = try ConfigLayerStack(layers: [
            ConfigLayerEntry(name: .user(file: try path(codexHome.url.appendingPathComponent("config.toml").path)), config: .table([
                "features": .table([
                    "hooks": .bool(true),
                    "plugins": .bool(true),
                    "plugin_hooks": .bool(true)
                ]),
                "plugins": .table([
                    "demo@test": .table(["enabled": .bool(true)])
                ])
            ]))
        ])

        XCTAssertEqual(HookConfig.configuredHandlers(from: stack, codexHome: codexHome.url), [])
    }

    private func hookConfig(
        command: String,
        timeoutSec: UInt64 = 600,
        statusMessage: String? = nil,
        trustedKey: String? = nil,
        trustedHash: String? = nil,
        enabled: Bool? = nil
    ) -> ConfigValue {
        var hooks = hookGroups(command: command, timeoutSec: timeoutSec, statusMessage: statusMessage)
        if let trustedKey {
            var state: [String: ConfigValue] = [:]
            if let trustedHash {
                state["trusted_hash"] = .string(trustedHash)
            }
            if let enabled {
                state["enabled"] = .bool(enabled)
            }
            if case var .table(table) = hooks {
                table["state"] = .table([trustedKey: .table(state)])
                hooks = .table(table)
            }
        }
        return .table(["hooks": hooks])
    }

    private func hookGroups(command: String, timeoutSec: UInt64 = 600, statusMessage: String? = nil) -> ConfigValue {
        var handler: [String: ConfigValue] = [
            "type": .string("command"),
            "command": .string(command)
        ]
        if timeoutSec != 600 {
            handler["timeout"] = .integer(Int64(timeoutSec))
        }
        if let statusMessage {
            handler["statusMessage"] = .string(statusMessage)
        }
        return .table([
            "UserPromptSubmit": .array([
                .table([
                    "hooks": .array([.table(handler)])
                ])
            ])
        ])
    }

    private func path(_ value: String) throws -> AbsolutePath {
        try AbsolutePath(absolutePath: value)
    }
}

private final class HookConfigTemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-swift-hook-config-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}
