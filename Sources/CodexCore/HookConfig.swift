import CryptoKit
import Foundation

private struct HookState: Equatable, Sendable {
    var enabled: Bool?
    var trustedHash: String?
}

public enum HookConfig {
    public static func configuredHandlers(
        from stack: ConfigLayerStack,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> [ConfiguredHookHandler] {
        guard configFeatureEnabled("hooks", in: stack.effectiveConfig(), defaultValue: true) else {
            return []
        }

        let hookStates = hookStateMap(from: stack.effectiveConfig())
        var displayOrder: Int64 = 0
        var handlers: [ConfiguredHookHandler] = []

        if let managedHooks = stack.requirements.managedHooks,
           let managedDir = managedHooks.value.managedDirForCurrentPlatform {
            appendHandlers(
                from: .table(["hooks": managedHooks.value.hooks]),
                sourcePath: URL(fileURLWithPath: managedDir, isDirectory: true),
                source: managedHooks.source,
                hookStates: hookStates,
                isManaged: true,
                displayOrder: &displayOrder,
                handlers: &handlers
            )
        }

        for layer in stack.getLayers(ordering: .lowestPrecedenceFirst) {
            switch layer.name {
            case let .user(file):
                appendHandlers(
                    from: layer.config,
                    sourcePath: URL(fileURLWithPath: file.path, isDirectory: false),
                    source: .user,
                    hookStates: hookStates,
                    displayOrder: &displayOrder,
                    handlers: &handlers
                )
            case let .project(dotCodexFolder):
                appendHandlers(
                    from: layer.config,
                    sourcePath: URL(fileURLWithPath: dotCodexFolder.path, isDirectory: true)
                        .appendingPathComponent("config.toml", isDirectory: false),
                    source: .project,
                    hookStates: hookStates,
                    displayOrder: &displayOrder,
                    handlers: &handlers
                )
            case .mdm,
                 .system,
                 .sessionFlags,
                 .legacyManagedConfigTomlFromFile,
                 .legacyManagedConfigTomlFromMdm:
                continue
            }
        }

        return handlers.map { handler in
            var handler = handler
            handler.command = substituteEnvironment(in: handler.command, environment: environment)
            return handler
        }
    }

    public static func hookKey(
        keySource: String,
        eventName: HookEventName,
        groupIndex: Int,
        handlerIndex: Int
    ) -> String {
        "\(keySource):\(eventName.rawValue):\(groupIndex):\(handlerIndex)"
    }

    public static func commandHookHash(
        eventName: HookEventName,
        matcher: String?,
        command: String,
        timeoutSec: UInt64,
        statusMessage: String?
    ) -> String {
        let identity = [
            eventName.rawValue,
            matcher ?? "",
            command,
            String(timeoutSec),
            statusMessage ?? ""
        ].joined(separator: "\u{1f}")
        let digest = SHA256.hash(data: Data(identity.utf8))
        return "sha256:" + digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func appendHandlers(
        from config: ConfigValue,
        sourcePath: URL,
        source: HookSource,
        hookStates: [String: HookState],
        isManaged: Bool = false,
        displayOrder: inout Int64,
        handlers: inout [ConfiguredHookHandler]
    ) {
        guard let root = configTable(config),
              let hooks = root["hooks"].flatMap(configTable)
        else {
            return
        }

        let keySource = sourcePath.standardizedFileURL.path
        guard let absoluteSourcePath = try? AbsolutePath(absolutePath: keySource) else {
            return
        }

        for eventName in HookEventName.allCases {
            guard case let .array(groups)? = hooks[eventName.configLabel] else {
                continue
            }
            for (groupIndex, groupValue) in groups.enumerated() {
                guard let group = configTable(groupValue) else {
                    continue
                }
                let matcher = stringConfig(group, "matcher")
                guard case let .array(handlerValues)? = group["hooks"] else {
                    continue
                }
                for (handlerIndex, handlerValue) in handlerValues.enumerated() {
                    defer { displayOrder += 1 }
                    guard let handler = configTable(handlerValue),
                          stringConfig(handler, "type") == "command",
                          let command = stringConfig(handler, "command")
                    else {
                        continue
                    }
                    let timeoutSec = configHookTimeoutSec(
                        handler["timeout"] ?? handler["timeoutSec"] ?? handler["timeout_sec"]
                    ) ?? 600
                    let statusMessage = stringConfig(handler, "statusMessage") ?? stringConfig(handler, "status_message")
                    let key = hookKey(
                        keySource: keySource,
                        eventName: eventName,
                        groupIndex: groupIndex,
                        handlerIndex: handlerIndex
                    )
                    let currentHash = commandHookHash(
                        eventName: eventName,
                        matcher: matcher,
                        command: command,
                        timeoutSec: timeoutSec,
                        statusMessage: statusMessage
                    )
                    guard hookEnabled(isManaged: isManaged, state: hookStates[key]),
                          hookTrusted(isManaged: isManaged, currentHash: currentHash, state: hookStates[key])
                    else {
                        continue
                    }
                    handlers.append(ConfiguredHookHandler(
                        eventName: eventName,
                        matcher: matcher,
                        command: command,
                        timeoutSec: timeoutSec,
                        statusMessage: statusMessage,
                        sourcePath: absoluteSourcePath,
                        source: source,
                        displayOrder: displayOrder
                    ))
                }
            }
        }
    }

    private static func hookStateMap(from config: ConfigValue) -> [String: HookState] {
        guard let root = configTable(config),
              let hooks = root["hooks"].flatMap(configTable),
              let state = hooks["state"].flatMap(configTable)
        else {
            return [:]
        }
        var output: [String: HookState] = [:]
        for (key, value) in state {
            guard let entry = configTable(value) else {
                continue
            }
            output[key] = HookState(
                enabled: boolConfig(entry, "enabled"),
                trustedHash: stringConfig(entry, "trusted_hash")
            )
        }
        return output
    }

    private static func configHookTimeoutSec(_ value: ConfigValue?) -> UInt64? {
        switch value {
        case let .integer(integer)? where integer >= 0:
            return UInt64(integer)
        case let .double(double)? where double >= 0 && double.rounded() == double:
            return UInt64(double)
        case let .string(string)?:
            return UInt64(string)
        case .bool, .array, .table, .integer, .double, .none:
            return nil
        }
    }

    private static func hookEnabled(isManaged: Bool, state: HookState?) -> Bool {
        isManaged || state?.enabled != false
    }

    private static func hookTrusted(isManaged: Bool, currentHash: String, state: HookState?) -> Bool {
        isManaged || state?.trustedHash == currentHash
    }

    private static func configFeatureEnabled(_ key: String, in config: ConfigValue, defaultValue: Bool) -> Bool {
        guard let root = configTable(config),
              let features = root["features"].flatMap(configTable),
              case let .bool(enabled)? = features[key]
        else {
            return defaultValue
        }
        return enabled
    }

    private static func configTable(_ value: ConfigValue) -> [String: ConfigValue]? {
        guard case let .table(table) = value else {
            return nil
        }
        return table
    }

    private static func stringConfig(_ table: [String: ConfigValue], _ key: String) -> String? {
        guard case let .string(value)? = table[key] else {
            return nil
        }
        return value
    }

    private static func boolConfig(_ table: [String: ConfigValue], _ key: String) -> Bool? {
        guard case let .bool(value)? = table[key] else {
            return nil
        }
        return value
    }

    private static func substituteEnvironment(in command: String, environment: [String: String]) -> String {
        environment.reduce(command) { partial, entry in
            partial.replacingOccurrences(of: "${\(entry.key)}", with: entry.value)
        }
    }
}
