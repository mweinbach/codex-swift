import CryptoKit
import Foundation

private struct HookState: Equatable, Sendable {
    var enabled: Bool?
    var trustedHash: String?
}

public enum HookConfig {
    public static func configuredHandlers(
        from stack: ConfigLayerStack,
        codexHome: URL? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> [ConfiguredHookHandler] {
        let effectiveConfig = stack.effectiveConfig()
        guard configFeatureEnabled("hooks", in: effectiveConfig, defaultValue: true) else {
            return []
        }

        let hookStates = hookStateMap(from: effectiveConfig)
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

        if let codexHome,
           configFeatureEnabled("plugins", in: effectiveConfig, defaultValue: false),
           configFeatureEnabled("plugin_hooks", in: effectiveConfig, defaultValue: false) {
            for pluginID in enabledLocalPluginIDs(config: effectiveConfig) {
                guard let root = activeLocalPluginRoot(id: pluginID, codexHome: codexHome) else {
                    continue
                }
                appendPluginHandlers(
                    root: root,
                    pluginID: pluginID,
                    hookStates: hookStates,
                    displayOrder: &displayOrder,
                    handlers: &handlers
                )
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

    private static func appendPluginHandlers(
        root: URL,
        pluginID: String,
        hookStates: [String: HookState],
        displayOrder: inout Int64,
        handlers: inout [ConfiguredHookHandler]
    ) {
        for config in pluginHookConfigs(root: root) {
            for (eventKey, value) in config.hooks {
                guard let eventName = pluginHookEventName(eventKey),
                      let groups = value as? [[String: Any]]
                else {
                    continue
                }
                for (groupIndex, group) in groups.enumerated() {
                    let matcher = group["matcher"] as? String
                    let handlerValues = group["hooks"] as? [[String: Any]] ?? []
                    for (handlerIndex, handler) in handlerValues.enumerated() {
                        defer { displayOrder += 1 }
                        guard (handler["type"] as? String) == "command",
                              let command = handler["command"] as? String
                        else {
                            continue
                        }
                        let timeoutSec = configHookTimeoutSec(
                            anyConfigValue(handler["timeout"] ?? handler["timeoutSec"] ?? handler["timeout_sec"])
                        ) ?? 600
                        let statusMessage = handler["statusMessage"] as? String ?? handler["status_message"] as? String
                        let key = pluginHookKey(
                            pluginID: pluginID,
                            sourcePath: config.sourcePath,
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
                        guard hookEnabled(isManaged: false, state: hookStates[key]),
                              hookTrusted(isManaged: false, currentHash: currentHash, state: hookStates[key]),
                              let sourcePath = try? AbsolutePath(
                                  absolutePath: root.appendingPathComponent(
                                      config.sourcePath,
                                      isDirectory: false
                                  ).standardizedFileURL.path
                              )
                        else {
                            continue
                        }
                        handlers.append(ConfiguredHookHandler(
                            eventName: eventName,
                            matcher: matcher,
                            command: command,
                            timeoutSec: timeoutSec,
                            statusMessage: statusMessage,
                            sourcePath: sourcePath,
                            source: .plugin,
                            displayOrder: displayOrder
                        ))
                    }
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

    public static func pluginHookKey(
        pluginID: String,
        sourcePath: String,
        eventName: HookEventName,
        groupIndex: Int,
        handlerIndex: Int
    ) -> String {
        "\(pluginID):\(sourcePath):\(HooksProtocol.hookEventKeyLabel(eventName)):\(groupIndex):\(handlerIndex)"
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

    private struct PluginHookConfig {
        let sourcePath: String
        let hooks: [String: Any]
    }

    private static func enabledLocalPluginIDs(config: ConfigValue) -> [String] {
        guard let root = configTable(config),
              let plugins = root["plugins"].flatMap(configTable)
        else {
            return []
        }
        return plugins.keys.filter { id in
            guard let entry = plugins[id].flatMap(configTable) else {
                return false
            }
            return boolConfig(entry, "enabled") ?? true
        }.sorted()
    }

    private static func activeLocalPluginRoot(id: String, codexHome: URL) -> URL? {
        guard let version = activeLocalPluginVersion(id: id, codexHome: codexHome) else {
            return nil
        }
        let parts = id.split(separator: "@", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else {
            return nil
        }
        return codexHome
            .appendingPathComponent("plugins/cache", isDirectory: true)
            .appendingPathComponent(parts[1], isDirectory: true)
            .appendingPathComponent(parts[0], isDirectory: true)
            .appendingPathComponent(version, isDirectory: true)
    }

    private static func activeLocalPluginVersion(id: String, codexHome: URL) -> String? {
        let parts = id.split(separator: "@", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else {
            return nil
        }
        let installRoot = codexHome
            .appendingPathComponent("plugins/cache", isDirectory: true)
            .appendingPathComponent(parts[1], isDirectory: true)
            .appendingPathComponent(parts[0], isDirectory: true)
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: installRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }
        let versions = entries
            .filter(isDirectory)
            .map(\.lastPathComponent)
            .filter(isValidPluginVersionSegment)
            .sorted()
        if versions.contains("local") {
            return "local"
        }
        return versions.last
    }

    private static func pluginHookConfigs(root: URL) -> [PluginHookConfig] {
        let manifestHooks = pluginManifestHooks(root: root)
        if !manifestHooks.inline.isEmpty {
            return manifestHooks.inline
        }
        let hookPaths = manifestHooks.paths ?? [root.appendingPathComponent("hooks/hooks.json", isDirectory: false)]
        return hookPaths.compactMap { path in
            guard FileManager.default.fileExists(atPath: path.path),
                  let data = try? Data(contentsOf: path),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let hooks = object["hooks"] as? [String: Any]
            else {
                return nil
            }
            return PluginHookConfig(sourcePath: pluginRelativePath(root: root, path: path), hooks: hooks)
        }
    }

    private static func pluginManifestHooks(root: URL) -> (paths: [URL]?, inline: [PluginHookConfig]) {
        let candidates = [
            root.appendingPathComponent(".codex-plugin/plugin.json", isDirectory: false),
            root.appendingPathComponent(".claude-plugin/plugin.json", isDirectory: false)
        ]
        guard let path = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }),
              let data = try? Data(contentsOf: path),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return (nil, [])
        }
        return (
            pluginManifestHookPaths(root: root, value: object["hooks"]),
            pluginManifestInlineHooks(value: object["hooks"])
        )
    }

    private static func pluginManifestHookPaths(root: URL, value: Any?) -> [URL]? {
        if let path = value as? String {
            return [pluginManifestPath(root: root, value: path)]
        }
        if let paths = value as? [String] {
            return paths.map { pluginManifestPath(root: root, value: $0) }
        }
        return nil
    }

    private static func pluginManifestInlineHooks(value: Any?) -> [PluginHookConfig] {
        if let hooks = value as? [String: Any] {
            return [PluginHookConfig(sourcePath: "plugin.json#hooks[0]", hooks: hooks)]
        }
        if let hookConfigs = value as? [[String: Any]] {
            return hookConfigs.enumerated().compactMap { index, config in
                guard let hooks = config["hooks"] as? [String: Any] else {
                    return nil
                }
                return PluginHookConfig(sourcePath: "plugin.json#hooks[\(index)]", hooks: hooks)
            }
        }
        return []
    }

    private static func pluginManifestPath(root: URL, value: String) -> URL {
        guard value.hasPrefix("./") else {
            return root.appendingPathComponent(value, isDirectory: false).standardizedFileURL
        }
        return root.appendingPathComponent(String(value.dropFirst(2)), isDirectory: false).standardizedFileURL
    }

    private static func pluginRelativePath(root: URL, path: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let path = path.standardizedFileURL.path
        guard path.hasPrefix(rootPath + "/") else {
            return path
        }
        return String(path.dropFirst(rootPath.count + 1))
    }

    private static func pluginHookEventName(_ raw: String) -> HookEventName? {
        if let eventName = HookEventName.allCases.first(where: { $0.configLabel == raw }) {
            return eventName
        }
        return HookEventName.allCases.first { $0.rawValue == raw }
    }

    private static func anyConfigValue(_ value: Any?) -> ConfigValue? {
        switch value {
        case let value as Int:
            return .integer(Int64(value))
        case let value as UInt64:
            return value <= UInt64(Int64.max) ? .integer(Int64(value)) : nil
        case let value as Double:
            return .double(value)
        case let value as String:
            return .string(value)
        default:
            return nil
        }
    }

    private static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    private static func isValidPluginVersionSegment(_ value: String) -> Bool {
        !value.isEmpty && value != "." && value != ".." && !value.contains("/")
    }

    private static func substituteEnvironment(in command: String, environment: [String: String]) -> String {
        environment.reduce(command) { partial, entry in
            partial.replacingOccurrences(of: "${\(entry.key)}", with: entry.value)
        }
    }
}
