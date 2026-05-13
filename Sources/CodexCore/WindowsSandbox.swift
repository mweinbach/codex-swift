import Foundation

public enum WindowsSandboxSetupMode: String, Equatable, Sendable {
    case elevated
    case unelevated
}

public struct WindowsSandboxSetupRequest: Equatable, Sendable {
    public let mode: WindowsSandboxSetupMode
    public let codexHome: URL
    public let commandCwd: URL
    public let activeProfile: String?

    public init(
        mode: WindowsSandboxSetupMode,
        codexHome: URL,
        commandCwd: URL,
        activeProfile: String? = nil
    ) {
        self.mode = mode
        self.codexHome = codexHome
        self.commandCwd = commandCwd
        self.activeProfile = activeProfile
    }
}

public enum WindowsSandboxSetupError: Error, Equatable, CustomStringConvertible {
    case elevatedSetupOnlySupportedOnWindows
    case legacySetupOnlySupportedOnWindows
    case nativeWindowsSandboxRuntimeUnavailable

    public var description: String {
        switch self {
        case .elevatedSetupOnlySupportedOnWindows:
            return "elevated Windows sandbox setup is only supported on Windows"
        case .legacySetupOnlySupportedOnWindows:
            return "legacy Windows sandbox setup is only supported on Windows"
        case .nativeWindowsSandboxRuntimeUnavailable:
            return "Windows sandbox setup requires native Windows sandbox runtime support"
        }
    }
}

public func windowsSandboxSetupIsComplete(codexHome: URL) -> Bool {
    _ = codexHome
    #if os(Windows)
    return false
    #else
    return false
    #endif
}

public func runWindowsSandboxSetup(_ request: WindowsSandboxSetupRequest) throws {
    #if os(Windows)
    _ = request
    throw WindowsSandboxSetupError.nativeWindowsSandboxRuntimeUnavailable
    #else
    switch request.mode {
    case .elevated:
        throw WindowsSandboxSetupError.elevatedSetupOnlySupportedOnWindows
    case .unelevated:
        throw WindowsSandboxSetupError.legacySetupOnlySupportedOnWindows
    }
    #endif
}

public func persistWindowsSandboxSetupMode(
    codexHome: URL,
    activeProfile: String?,
    mode: WindowsSandboxSetupMode,
    fileManager: FileManager = .default
) throws {
    let configFile = codexHome.appendingPathComponent("config.toml", isDirectory: false)
    var config = try CodexConfigLayerLoader.readConfig(from: configFile, fileManager: fileManager) ?? .table([:])
    WindowsSandboxConfigEditor.setSandboxMode(mode, activeProfile: activeProfile, in: &config)
    try fileManager.createDirectory(at: codexHome, withIntermediateDirectories: true)
    try ConfigTomlRenderer.render(config).write(to: configFile, atomically: true, encoding: .utf8)
}
