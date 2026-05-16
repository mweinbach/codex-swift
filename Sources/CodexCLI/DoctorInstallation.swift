import Foundation

public enum DoctorNpmRootCheck: Equatable, Sendable {
    case match(packageRoot: String)
    case mismatch(runningPackageRoot: String, npmPackageRoot: String)
    case missingPackageRoot
    case npmUnavailable(String)
}

public struct DoctorInstallationInputs: Equatable, Sendable {
    public var currentExecutablePath: String?
    public var environment: [String: String]
    public var pathEntries: [String]
    public var installContext: String
    public var npmRootCheck: DoctorNpmRootCheck?

    public init(
        currentExecutablePath: String?,
        environment: [String: String],
        pathEntries: [String],
        installContext: String,
        npmRootCheck: DoctorNpmRootCheck? = nil
    ) {
        self.currentExecutablePath = currentExecutablePath
        self.environment = environment
        self.pathEntries = pathEntries
        self.installContext = installContext
        self.npmRootCheck = npmRootCheck
    }

    public static func detect() -> Self {
        Self(
            currentExecutablePath: defaultExecutablePath(),
            environment: ProcessInfo.processInfo.environment,
            pathEntries: defaultPathEntries(),
            installContext: "other"
        )
    }
}

extension DoctorCommandRuntime {
    public static func installationCheck(
        showDetails: Bool,
        inputs: DoctorInstallationInputs = .detect()
    ) -> DoctorCheck {
        var details: [String] = [
            "current executable: \(inputs.currentExecutablePath ?? "none")",
            "install context: \(inputs.installContext)"
        ]

        let inheritedManagedEnvironment = inheritedManagedEnvForCargoBinary(
            currentExecutablePath: inputs.currentExecutablePath,
            environment: inputs.environment
        )
        let managedByNpm = inputs.environment["CODEX_MANAGED_BY_NPM"] != nil && !inheritedManagedEnvironment
        if inheritedManagedEnvironment {
            details.append("ignored inherited package-manager launch env for cargo-built binary")
        }
        details.append("managed by npm: \(managedByNpm)")
        details.append("managed by bun: \(inputs.environment["CODEX_MANAGED_BY_BUN"] != nil)")
        details.append("managed package root: \(inputs.environment["CODEX_MANAGED_PACKAGE_ROOT"] ?? "not set")")

        if inputs.pathEntries.count > 1 {
            details.append("PATH codex entries: \(inputs.pathEntries.count)")
        }
        if showDetails || inputs.pathEntries.count > 1 {
            details.append(contentsOf: inputs.pathEntries.enumerated().map { index, path in
                "PATH codex #\(index + 1): \(path)"
            })
        }

        var status = DoctorCheckStatus.ok
        var summary = "installation looks consistent"
        var remediation: String?

        if managedByNpm {
            switch inputs.npmRootCheck ?? npmGlobalRootCheck(environment: inputs.environment) {
            case let .match(packageRoot):
                details.append("npm update target: \(packageRoot)")
            case let .mismatch(runningPackageRoot, npmPackageRoot):
                status = .fail
                summary = "npm install -g @openai/codex would update a different install"
                remediation =
                    "Fix PATH or npm prefix so the running package root (\(runningPackageRoot)) matches the npm global package root (\(npmPackageRoot))."
                details.append("running package root: \(runningPackageRoot)")
                details.append("npm package root: \(npmPackageRoot)")
            case .missingPackageRoot:
                status = .warning
                summary = "npm-managed launch is missing package-root provenance"
                remediation = "Reinstall or update Codex so the JS shim provides CODEX_MANAGED_PACKAGE_ROOT."
            case let .npmUnavailable(error):
                status = .warning
                summary = "npm-managed launch could not inspect npm global root"
                details.append("npm root -g failed: \(error)")
            }
        }

        return DoctorCheck(
            id: "installation",
            category: "install",
            status: status,
            summary: summary,
            details: details,
            remediation: remediation
        )
    }
}

private func inheritedManagedEnvForCargoBinary(
    currentExecutablePath: String?,
    environment: [String: String]
) -> Bool {
    guard environment["CODEX_MANAGED_BY_NPM"] != nil || environment["CODEX_MANAGED_BY_BUN"] != nil else {
        return false
    }
    guard let currentExecutablePath else { return false }
    let components = URL(fileURLWithPath: currentExecutablePath).pathComponents
    guard components.count >= 2 else { return false }
    return components.indices.dropLast().contains { index in
        components[index] == "target" && ["debug", "release"].contains(components[index + 1])
    }
}

private func npmGlobalRootCheck(environment: [String: String]) -> DoctorNpmRootCheck {
    guard let runningPackageRoot = environment["CODEX_MANAGED_PACKAGE_ROOT"] else {
        return .missingPackageRoot
    }
    switch runDoctorProcess(
        command: DoctorCommandRuntime.npmGlobalRootCommand(),
        arguments: DoctorCommandRuntime.npmGlobalRootArguments
    ) {
    case let .success(output):
        guard let npmRoot = output.split(whereSeparator: \.isNewline).map(String.init).first(where: {
            !$0.trimmingCharacters(in: .whitespaces).isEmpty
        }) else {
            return .npmUnavailable("empty output from npm root -g")
        }
        return compareNpmPackageRoots(
            runningPackageRoot: runningPackageRoot,
            npmRoot: npmRoot.trimmingCharacters(in: .whitespaces)
        )
    case let .failure(error):
        return .npmUnavailable(error)
    }
}

private func compareNpmPackageRoots(runningPackageRoot: String, npmRoot: String) -> DoctorNpmRootCheck {
    let npmPackageRoot = URL(fileURLWithPath: npmRoot).appendingPathComponent("@openai/codex").path
    let normalizedRunningPackageRoot = normalizePackageRoot(runningPackageRoot)
    let normalizedNpmPackageRoot = normalizePackageRoot(npmPackageRoot)
    if normalizedRunningPackageRoot == normalizedNpmPackageRoot {
        return .match(packageRoot: runningPackageRoot)
    }
    return .mismatch(runningPackageRoot: runningPackageRoot, npmPackageRoot: npmPackageRoot)
}

private func normalizePackageRoot(_ path: String) -> String {
    let standardized = URL(fileURLWithPath: path).standardizedFileURL.path.replacingOccurrences(of: "\\", with: "/")
    #if os(Windows)
        return standardized.lowercased()
    #else
        return standardized
    #endif
}

private func defaultExecutablePath() -> String? {
    Bundle.main.executableURL?.path ?? CommandLine.arguments.first
}

private func defaultPathEntries() -> [String] {
    #if os(Windows)
        let command = "where"
    #else
        let command = "which"
    #endif
    let arguments = command == "where" ? ["codex"] : ["-a", "codex"]
    switch runDoctorProcess(command: command, arguments: arguments) {
    case let .success(output):
        return output
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    case .failure:
        return []
    }
}

private func runDoctorProcess(command: String, arguments: [String]) -> DoctorCommandOutput {
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
    do {
        try process.run()
    } catch {
        return .failure(error.localizedDescription)
    }
    process.waitUntilExit()
    let output = String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    if process.terminationStatus == 0 {
        return .success(output)
    }
    let error = String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    if error.isEmpty {
        return .failure("exited with status \(process.terminationStatus)")
    }
    return .failure(error)
}
