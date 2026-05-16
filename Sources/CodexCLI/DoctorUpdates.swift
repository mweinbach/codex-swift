import CodexCore
import Foundation

public enum DoctorInstallContext: String, Equatable, Sendable {
    case npm
    case bun
    case brew
    case standalone
    case other
}

public enum DoctorVersionCacheProbe: Equatable, Sendable {
    case loaded(String)
    case missing
    case failed(String)
}

public enum DoctorLatestVersionProbe: Equatable, Sendable {
    case success(String)
    case failed(String)
}

public struct DoctorUpdatesCheckInputs: Equatable, Sendable {
    public let codexHomePath: String
    public let checkForUpdateOnStartup: Bool
    public let installContext: DoctorInstallContext
    public let environment: [String: String]
    public let currentVersion: String
    public let versionCache: DoctorVersionCacheProbe
    public let latestVersion: DoctorLatestVersionProbe
    public let npmRootCheck: DoctorNpmRootCheck?

    public init(
        codexHomePath: String,
        checkForUpdateOnStartup: Bool,
        installContext: DoctorInstallContext,
        environment: [String: String],
        currentVersion: String,
        versionCache: DoctorVersionCacheProbe,
        latestVersion: DoctorLatestVersionProbe,
        npmRootCheck: DoctorNpmRootCheck? = nil
    ) {
        self.codexHomePath = codexHomePath
        self.checkForUpdateOnStartup = checkForUpdateOnStartup
        self.installContext = installContext
        self.environment = environment
        self.currentVersion = currentVersion
        self.versionCache = versionCache
        self.latestVersion = latestVersion
        self.npmRootCheck = npmRootCheck
    }
}

extension DoctorCommandRuntime {
    public static func updatesCheck(
        codexHome: URL,
        settings: CodexRuntimeConfig,
        codexVersion: String,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        currentExecutablePath: String? = Bundle.main.executableURL?.path ?? CommandLine.arguments.first
    ) -> DoctorCheck {
        let installContext = doctorInstallContext(
            currentExecutablePath: currentExecutablePath,
            environment: environment
        )
        return updatesCheck(inputs: DoctorUpdatesCheckInputs(
            codexHomePath: codexHome.path,
            checkForUpdateOnStartup: settings.checkForUpdateOnStartup,
            installContext: installContext,
            environment: environment,
            currentVersion: codexVersion,
            versionCache: readVersionCache(codexHome: codexHome),
            latestVersion: fetchLatestVersion(installContext: installContext)
        ))
    }

    public static func updatesCheck(inputs: DoctorUpdatesCheckInputs) -> DoctorCheck {
        var details = [
            "check for update on startup: \(updatesRustBool(inputs.checkForUpdateOnStartup))",
            "update action: \(updateActionLabel(inputs.installContext))"
        ]
        pushCachedVersionDetails(
            into: &details,
            versionFilePath: URL(fileURLWithPath: inputs.codexHomePath)
                .appendingPathComponent(UpdateVersion.versionFilename)
                .path,
            cache: inputs.versionCache
        )

        var status = DoctorCheckStatus.ok
        var summary = "update configuration is locally consistent"
        var remediation: String?

        if doctorManagedByNpm(environment: inputs.environment) {
            switch inputs.npmRootCheck ?? npmGlobalRootCheckForUpdates(environment: inputs.environment) {
            case let .match(packageRoot):
                details.append("npm update target: \(packageRoot)")
            case let .mismatch(runningPackageRoot, npmPackageRoot):
                status = .fail
                summary = "update would target a different npm install"
                details.append("running package root: \(runningPackageRoot)")
                details.append("npm package root: \(npmPackageRoot)")
                remediation =
                    "Fix PATH or npm prefix so the running package root (\(runningPackageRoot)) matches the npm global package root (\(npmPackageRoot))."
            case .missingPackageRoot:
                status = maxStatus(status, .warning)
                summary = "npm update target could not be proven"
                remediation = "Reinstall or update Codex so the JS shim provides CODEX_MANAGED_PACKAGE_ROOT."
            case let .npmUnavailable(error):
                status = maxStatus(status, .warning)
                summary = "npm update target could not be inspected"
                details.append("npm root -g failed: \(error)")
            }
        }

        switch inputs.latestVersion {
        case let .success(latestVersion):
            details.append("latest version: \(latestVersion)")
            if UpdateVersion.isNewer(latest: latestVersion, current: inputs.currentVersion) == true {
                details.append("latest version status: newer version is available")
            } else {
                details.append("latest version status: current version is not older")
            }
        case let .failed(error):
            status = maxStatus(status, .warning)
            details.append("latest version probe: \(error)")
        }

        return DoctorCheck(
            id: "updates.status",
            category: "updates",
            status: status,
            summary: summary,
            details: details,
            remediation: remediation
        )
    }

    private static func pushCachedVersionDetails(
        into details: inout [String],
        versionFilePath: String,
        cache: DoctorVersionCacheProbe
    ) {
        details.append("version cache: \(versionFilePath)")
        switch cache {
        case let .loaded(contents):
            do {
                let data = Data(contents.utf8)
                let info = try JSONDecoder().decode(DoctorCachedVersionInfo.self, from: data)
                details.append("cached latest version: \(info.latestVersion)")
                if let lastCheckedAt = info.lastCheckedAt {
                    details.append("last checked at: \(lastCheckedAt)")
                }
                if let dismissedVersion = info.dismissedVersion {
                    details.append("dismissed version: \(dismissedVersion)")
                }
            } catch {
                details.append("version cache parse: \(error)")
            }
        case .missing:
            details.append("version cache: missing")
        case let .failed(error):
            details.append("version cache read: \(error)")
        }
    }

    private static func readVersionCache(codexHome: URL) -> DoctorVersionCacheProbe {
        let path = UpdateVersion.versionFilePath(codexHome: codexHome)
        do {
            return .loaded(try String(contentsOf: path, encoding: .utf8))
        } catch {
            if (error as NSError).domain == NSCocoaErrorDomain,
               (error as NSError).code == NSFileReadNoSuchFileError
            {
                return .missing
            }
            return .failed(error.localizedDescription)
        }
    }

    private static func fetchLatestVersion(installContext: DoctorInstallContext) -> DoctorLatestVersionProbe {
        switch installContext {
        case .brew:
            switch runDoctorProcessForUpdates(
                command: "curl",
                arguments: ["-fsSL", "--max-time", "5", "https://formulae.brew.sh/api/cask/codex.json"]
            ) {
            case let .success(output):
                do {
                    let data = Data(output.utf8)
                    let info = try JSONDecoder().decode(DoctorHomebrewCaskInfo.self, from: data)
                    return .success(info.version)
                } catch {
                    return .failed(String(describing: error))
                }
            case let .failure(error):
                return .failed(error)
            }
        case .npm, .bun, .standalone, .other:
            switch runDoctorProcessForUpdates(
                command: "curl",
                arguments: ["-fsSL", "--max-time", "5", UpdateVersion.latestReleaseURL]
            ) {
            case let .success(output):
                do {
                    let data = Data(output.utf8)
                    let info = try JSONDecoder().decode(DoctorGitHubReleaseInfo.self, from: data)
                    return .success(try UpdateVersion.extractVersionFromLatestTag(info.tagName))
                } catch {
                    let rawTag = (try? JSONDecoder().decode(DoctorGitHubReleaseInfo.self, from: Data(output.utf8)).tagName)
                    if let rawTag {
                        return .failed("failed to parse latest tag \(rawTag)")
                    }
                    return .failed(String(describing: error))
                }
            case let .failure(error):
                return .failed(error)
            }
        }
    }

    private static func doctorInstallContext(
        currentExecutablePath: String?,
        environment: [String: String]
    ) -> DoctorInstallContext {
        if doctorManagedByNpm(environment: environment) {
            return .npm
        }
        if environment["CODEX_MANAGED_BY_BUN"]?.isEmpty == false {
            return .bun
        }
        guard let currentExecutablePath else {
            return .other
        }
        if currentExecutablePath == "/opt/homebrew" || currentExecutablePath.hasPrefix("/opt/homebrew/")
            || currentExecutablePath == "/usr/local" || currentExecutablePath.hasPrefix("/usr/local/")
        {
            return .brew
        }
        return .other
    }

    private static func updateActionLabel(_ installContext: DoctorInstallContext) -> String {
        switch installContext {
        case .npm:
            "npm install -g @openai/codex"
        case .bun:
            "bun install -g @openai/codex"
        case .brew:
            "brew upgrade --cask codex"
        case .standalone:
            "standalone installer"
        case .other:
            "manual or unknown"
        }
    }

    private static func doctorManagedByNpm(environment: [String: String]) -> Bool {
        environment["CODEX_MANAGED_BY_NPM"]?.isEmpty == false
    }

    private static func npmGlobalRootCheckForUpdates(environment: [String: String]) -> DoctorNpmRootCheck {
        guard let runningPackageRoot = environment["CODEX_MANAGED_PACKAGE_ROOT"] else {
            return .missingPackageRoot
        }
        switch runDoctorProcessForUpdates(
            command: DoctorCommandRuntime.npmGlobalRootCommand(),
            arguments: DoctorCommandRuntime.npmGlobalRootArguments
        ) {
        case let .success(output):
            guard let npmRoot = output.split(whereSeparator: \.isNewline).map(String.init).first(where: {
                !$0.trimmingCharacters(in: .whitespaces).isEmpty
            }) else {
                return .npmUnavailable("empty output from npm root -g")
            }
            let npmPackageRoot = URL(fileURLWithPath: npmRoot.trimmingCharacters(in: .whitespaces))
                .appendingPathComponent("@openai/codex")
                .standardizedFileURL
                .path
            let normalizedRunning = URL(fileURLWithPath: runningPackageRoot)
                .standardizedFileURL
                .path
                .replacingOccurrences(of: "\\", with: "/")
            let normalizedNpm = npmPackageRoot.replacingOccurrences(of: "\\", with: "/")
            if normalizedRunning == normalizedNpm {
                return .match(packageRoot: runningPackageRoot)
            }
            return .mismatch(runningPackageRoot: runningPackageRoot, npmPackageRoot: npmPackageRoot)
        case let .failure(error):
            return .npmUnavailable(error)
        }
    }

    private static func runDoctorProcessForUpdates(command: String, arguments: [String]) -> DoctorCommandOutput {
        let process = Process()
        if command.contains("/") {
            process.executableURL = URL(fileURLWithPath: command)
            process.arguments = arguments
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [command] + arguments
        }
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        let stdoutData = DoctorProcessDataBuffer()
        let stderrData = DoctorProcessDataBuffer()
        stdout.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            stdoutData.append(data)
        }
        stderr.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            stderrData.append(data)
        }
        do {
            try process.run()
        } catch {
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil
            return .failure(error.localizedDescription)
        }
        let deadline = Date().addingTimeInterval(7)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            process.terminate()
            process.waitUntilExit()
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil
            return .failure("timed out")
        }
        process.waitUntilExit()
        stdout.fileHandleForReading.readabilityHandler = nil
        stderr.fileHandleForReading.readabilityHandler = nil
        stdoutData.append(stdout.fileHandleForReading.readDataToEndOfFile())
        stderrData.append(stderr.fileHandleForReading.readDataToEndOfFile())
        let output = String(decoding: stdoutData.snapshot(), as: UTF8.self)
        let errorOutput = String(decoding: stderrData.snapshot(), as: UTF8.self)
        if process.terminationStatus == 0 {
            return .success(output)
        }
        let error = errorOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        if error.isEmpty {
            return .failure("exited with status \(process.terminationStatus)")
        }
        return .failure(error)
    }

    private static func maxStatus(_ lhs: DoctorCheckStatus, _ rhs: DoctorCheckStatus) -> DoctorCheckStatus {
        if lhs == .fail || rhs == .fail {
            return .fail
        }
        if lhs == .warning || rhs == .warning {
            return .warning
        }
        return .ok
    }

    private static func updatesRustBool(_ value: Bool) -> String {
        value ? "true" : "false"
    }
}

private struct DoctorCachedVersionInfo: Decodable {
    let latestVersion: String
    let lastCheckedAt: String?
    let dismissedVersion: String?

    private enum CodingKeys: String, CodingKey {
        case latestVersion = "latest_version"
        case lastCheckedAt = "last_checked_at"
        case dismissedVersion = "dismissed_version"
    }
}

private struct DoctorGitHubReleaseInfo: Decodable {
    let tagName: String

    private enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
    }
}

private struct DoctorHomebrewCaskInfo: Decodable {
    let version: String
}

// Foundation pipe readability callbacks can arrive on background queues; the
// buffer remains sendable because every Data access is guarded by this lock.
private final class DoctorProcessDataBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ next: Data) {
        lock.lock()
        data.append(next)
        lock.unlock()
    }

    func snapshot() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return data
    }
}
