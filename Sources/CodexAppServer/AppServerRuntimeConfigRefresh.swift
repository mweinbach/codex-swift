import CodexCore
import Foundation

struct AppServerRuntimeConfigRefresh {
    static func applyRuntimeRefreshableSnapshot(
        _ snapshot: ConfigValue,
        to settings: inout CodexRuntimeConfig,
        codexHome: URL,
        cwd: URL,
        environment: [String: String]
    ) throws -> ConfigLayerStack {
        let stack = try configLayerStack(snapshot, codexHome: codexHome)
        let refreshed = try CodexConfigLoader.loadEffectiveConfigSnapshot(
            snapshot,
            codexHome: codexHome,
            cwd: cwd,
            environment: environment
        )
        settings.toolSuggest = refreshed.toolSuggest
        return stack
    }

    static func configLayerStack(
        _ snapshot: ConfigValue,
        codexHome: URL
    ) throws -> ConfigLayerStack {
        let configFile = codexHome.appendingPathComponent("config.toml", isDirectory: false)
        return try ConfigLayerStack(layers: [
            ConfigLayerEntry(
                name: .user(file: AbsolutePath(absolutePath: configFile.standardizedFileURL.path)),
                config: snapshot
            )
        ])
    }
}
