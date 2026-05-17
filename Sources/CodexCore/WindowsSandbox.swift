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

public enum WindowsSandboxSetupErrorCode: String, Codable, CaseIterable, Sendable {
    case orchestratorSandboxDirCreateFailed = "orchestrator_sandbox_dir_create_failed"
    case orchestratorElevationCheckFailed = "orchestrator_elevation_check_failed"
    case orchestratorPayloadSerializeFailed = "orchestrator_payload_serialize_failed"
    case orchestratorHelperLaunchFailed = "orchestrator_helper_launch_failed"
    case orchestratorHelperLaunchCanceled = "orchestrator_helper_launch_canceled"
    case orchestratorHelperExitNonzero = "orchestrator_helper_exit_nonzero"
    case orchestratorHelperReportReadFailed = "orchestrator_helper_report_read_failed"
    case helperRequestArgsFailed = "helper_request_args_failed"
    case helperSandboxDirCreateFailed = "helper_sandbox_dir_create_failed"
    case helperLogFailed = "helper_log_failed"
    case helperUserProvisionFailed = "helper_user_provision_failed"
    case helperUsersGroupCreateFailed = "helper_users_group_create_failed"
    case helperUserCreateOrUpdateFailed = "helper_user_create_or_update_failed"
    case helperDpapiProtectFailed = "helper_dpapi_protect_failed"
    case helperUsersFileWriteFailed = "helper_users_file_write_failed"
    case helperSetupMarkerWriteFailed = "helper_setup_marker_write_failed"
    case helperSidResolveFailed = "helper_sid_resolve_failed"
    case helperCapabilitySidFailed = "helper_capability_sid_failed"
    case helperFirewallComInitFailed = "helper_firewall_com_init_failed"
    case helperFirewallPolicyAccessFailed = "helper_firewall_policy_access_failed"
    case helperFirewallPolicyIneffective = "helper_firewall_policy_ineffective"
    case helperFirewallRuleCreateOrAddFailed = "helper_firewall_rule_create_or_add_failed"
    case helperFirewallRuleVerifyFailed = "helper_firewall_rule_verify_failed"
    case helperReadAclHelperSpawnFailed = "helper_read_acl_helper_spawn_failed"
    case helperSandboxLockFailed = "helper_sandbox_lock_failed"
    case helperUnknownError = "helper_unknown_error"
}

public struct WindowsSandboxSetupFailure: Error, Equatable, Codable, CustomStringConvertible, Sendable {
    public let code: WindowsSandboxSetupErrorCode
    public let message: String

    public init(code: WindowsSandboxSetupErrorCode, message: String) {
        self.code = code
        self.message = message
    }

    public var description: String {
        "\(code.rawValue): \(message)"
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

public func windowsSandboxCodexAppRuntimeBinDirectory(
    environment: [String: String],
    fileManager: FileManager = .default
) -> URL? {
    let localAppData: URL?
    if let value = environment["LOCALAPPDATA"], !value.isEmpty {
        localAppData = URL(fileURLWithPath: value, isDirectory: true)
    } else if let value = environment["USERPROFILE"], !value.isEmpty {
        localAppData = URL(fileURLWithPath: value, isDirectory: true)
            .appendingPathComponent("AppData", isDirectory: true)
            .appendingPathComponent("Local", isDirectory: true)
    } else {
        localAppData = nil
    }

    guard let localAppData else {
        return nil
    }

    let runtimeBin = localAppData
        .appendingPathComponent("OpenAI", isDirectory: true)
        .appendingPathComponent("Codex", isDirectory: true)
        .appendingPathComponent("bin", isDirectory: true)
    var isDirectory: ObjCBool = false
    guard fileManager.fileExists(atPath: runtimeBin.path, isDirectory: &isDirectory),
          isDirectory.boolValue
    else {
        return nil
    }
    return runtimeBin
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
