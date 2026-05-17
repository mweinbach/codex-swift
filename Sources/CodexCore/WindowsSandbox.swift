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

struct WindowsSandboxCapabilitySIDs: Codable, Equatable, Sendable {
    let workspace: String
    let readonly: String
    var workspaceByCwd: [String: String]
    var writableRootByPath: [String: String]

    init(
        workspace: String,
        readonly: String,
        workspaceByCwd: [String: String] = [:],
        writableRootByPath: [String: String] = [:]
    ) {
        self.workspace = workspace
        self.readonly = readonly
        self.workspaceByCwd = workspaceByCwd
        self.writableRootByPath = writableRootByPath
    }

    private enum CodingKeys: String, CodingKey {
        case workspace
        case readonly
        case workspaceByCwd = "workspace_by_cwd"
        case writableRootByPath = "writable_root_by_path"
    }
}

struct WindowsSandboxRootCapabilitySID: Equatable, Sendable {
    let root: URL
    let sidString: String

    init(root: URL, sidString: String) {
        self.root = root
        self.sidString = sidString
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

func windowsSandboxCapabilitySIDFile(codexHome: URL) -> URL {
    codexHome.appendingPathComponent("cap_sid", isDirectory: false)
}

func windowsSandboxCanonicalCapabilityPathKey(_ path: String) -> String {
    URL(fileURLWithPath: path)
        .resolvingSymlinksInPath()
        .standardizedFileURL
        .path
        .replacingOccurrences(of: "\\", with: "/")
        .lowercased()
}

func loadOrCreateWindowsSandboxCapabilitySIDs(
    codexHome: URL,
    fileManager: FileManager = .default
) throws -> WindowsSandboxCapabilitySIDs {
    let file = windowsSandboxCapabilitySIDFile(codexHome: codexHome)
    if fileManager.fileExists(atPath: file.path),
       let contents = try? String(contentsOf: file, encoding: .utf8) {
        let trimmed = contents.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{"), trimmed.hasSuffix("}"),
           let data = trimmed.data(using: .utf8),
           let caps = try? JSONDecoder().decode(WindowsSandboxCapabilitySIDs.self, from: data) {
            return caps
        }
        if !trimmed.isEmpty {
            let caps = WindowsSandboxCapabilitySIDs(
                workspace: trimmed,
                readonly: makeWindowsSandboxCapabilitySID()
            )
            try persistWindowsSandboxCapabilitySIDs(caps, to: file, fileManager: fileManager)
            return caps
        }
    }

    let caps = WindowsSandboxCapabilitySIDs(
        workspace: makeWindowsSandboxCapabilitySID(),
        readonly: makeWindowsSandboxCapabilitySID()
    )
    try persistWindowsSandboxCapabilitySIDs(caps, to: file, fileManager: fileManager)
    return caps
}

func windowsSandboxWorkspaceCapabilitySIDForCwd(
    codexHome: URL,
    cwd: URL,
    fileManager: FileManager = .default
) throws -> String {
    let file = windowsSandboxCapabilitySIDFile(codexHome: codexHome)
    var caps = try loadOrCreateWindowsSandboxCapabilitySIDs(
        codexHome: codexHome,
        fileManager: fileManager
    )
    let key = windowsSandboxCanonicalCapabilityPathKey(cwd.path)
    if let sid = caps.workspaceByCwd[key] {
        return sid
    }
    let sid = makeWindowsSandboxCapabilitySID()
    caps.workspaceByCwd[key] = sid
    try persistWindowsSandboxCapabilitySIDs(caps, to: file, fileManager: fileManager)
    return sid
}

func windowsSandboxWritableRootCapabilitySIDForPath(
    codexHome: URL,
    root: URL,
    fileManager: FileManager = .default
) throws -> String {
    let file = windowsSandboxCapabilitySIDFile(codexHome: codexHome)
    var caps = try loadOrCreateWindowsSandboxCapabilitySIDs(
        codexHome: codexHome,
        fileManager: fileManager
    )
    let key = windowsSandboxCanonicalCapabilityPathKey(root.path)
    if let sid = caps.writableRootByPath[key] {
        return sid
    }
    let sid = makeWindowsSandboxCapabilitySID()
    caps.writableRootByPath[key] = sid
    try persistWindowsSandboxCapabilitySIDs(caps, to: file, fileManager: fileManager)
    return sid
}

func windowsSandboxWorkspaceWriteCapabilitySIDForRoot(
    codexHome: URL,
    cwd: URL,
    root: URL,
    fileManager: FileManager = .default
) throws -> String {
    if windowsSandboxCanonicalCapabilityPathKey(root.path) == windowsSandboxCanonicalCapabilityPathKey(cwd.path) {
        return try windowsSandboxWorkspaceCapabilitySIDForCwd(
            codexHome: codexHome,
            cwd: cwd,
            fileManager: fileManager
        )
    }
    return try windowsSandboxWritableRootCapabilitySIDForPath(
        codexHome: codexHome,
        root: root,
        fileManager: fileManager
    )
}

func windowsSandboxWorkspaceWriteRootContainsPath(root: URL, path: URL) -> Bool {
    let rootPath = windowsSandboxCanonicalCapabilityPathKey(root.path)
    let path = windowsSandboxCanonicalCapabilityPathKey(path.path)
    return path == rootPath || path.hasPrefix(rootPath.hasSuffix("/") ? rootPath : "\(rootPath)/")
}

func windowsSandboxWorkspaceWriteRootOverlapsPath(root: URL, path: URL) -> Bool {
    windowsSandboxWorkspaceWriteRootContainsPath(root: root, path: path)
        || windowsSandboxWorkspaceWriteRootContainsPath(root: path, path: root)
}

func windowsSandboxWorkspaceWriteRootSpecificity(root: URL) -> Int {
    windowsSandboxCanonicalCapabilityPathKey(root.path)
        .split(separator: "/", omittingEmptySubsequences: true)
        .count
}

func windowsSandboxRootCapabilitySIDs(
    codexHome: URL,
    cwd: URL,
    allowPaths: [URL],
    fileManager: FileManager = .default
) throws -> [WindowsSandboxRootCapabilitySID] {
    var seen = Set<String>()
    let roots = allowPaths
        .sorted {
            windowsSandboxCanonicalCapabilityPathKey($0.path) < windowsSandboxCanonicalCapabilityPathKey($1.path)
        }
        .filter { root in
            seen.insert(windowsSandboxCanonicalCapabilityPathKey(root.path)).inserted
        }

    var result: [WindowsSandboxRootCapabilitySID] = []
    result.reserveCapacity(roots.count)
    for root in roots {
        let sid = try windowsSandboxWorkspaceWriteCapabilitySIDForRoot(
            codexHome: codexHome,
            cwd: cwd,
            root: root,
            fileManager: fileManager
        )
        result.append(WindowsSandboxRootCapabilitySID(root: root, sidString: sid))
    }
    return result
}

func windowsSandboxDenyRootCapabilitySIDsForPath(
    path: URL,
    rootSIDs: [WindowsSandboxRootCapabilitySID]
) -> [WindowsSandboxRootCapabilitySID] {
    let matching = rootSIDs.filter { rootSID in
        windowsSandboxWorkspaceWriteRootOverlapsPath(root: rootSID.root, path: path)
    }
    return matching.isEmpty ? rootSIDs : matching
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

private func makeWindowsSandboxCapabilitySID() -> String {
    let first = UInt32.random(in: .min ... .max)
    let second = UInt32.random(in: .min ... .max)
    let third = UInt32.random(in: .min ... .max)
    let fourth = UInt32.random(in: .min ... .max)
    return "S-1-5-21-\(first)-\(second)-\(third)-\(fourth)"
}

private func persistWindowsSandboxCapabilitySIDs(
    _ caps: WindowsSandboxCapabilitySIDs,
    to file: URL,
    fileManager: FileManager
) throws {
    let parent = file.deletingLastPathComponent()
    try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(caps)
    try data.write(to: file, options: .atomic)
}
