import CodexCore
import Foundation

struct AppServerRuntimeConfigRefresh {
    static func applyRuntimeRefreshableSnapshot(
        _ snapshot: ConfigValue,
        to settings: inout CodexRuntimeConfig,
        codexHome: URL,
        cwd: URL,
        environment: [String: String],
        baseStack: ConfigLayerStack? = nil
    ) throws -> ConfigLayerStack {
        let stack = try configLayerStack(
            snapshot,
            codexHome: codexHome,
            baseStack: baseStack
        )
        let refreshed = try CodexConfigLoader.loadEffectiveConfigStack(
            stack,
            codexHome: codexHome,
            cwd: cwd,
            environment: environment
        )
        settings.toolSuggest = refreshed.toolSuggest
        return stack
    }

    static func configLayerStack(
        _ snapshot: ConfigValue,
        codexHome: URL,
        baseStack: ConfigLayerStack? = nil
    ) throws -> ConfigLayerStack {
        let configFile = codexHome.appendingPathComponent("config.toml", isDirectory: false)
        let configPath = try AbsolutePath(absolutePath: configFile.standardizedFileURL.path)
        if let baseStack {
            return baseStack.withUserConfig(configToml: configPath, userConfig: snapshot)
        }
        return try ConfigLayerStack(layers: [
            ConfigLayerEntry(
                name: .user(file: configPath),
                config: snapshot
            )
        ])
    }
}
