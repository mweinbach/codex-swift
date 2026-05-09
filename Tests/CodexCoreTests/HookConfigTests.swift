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
