import Foundation

public enum AppCommandRuntime {
    public static let macArm64DMGURL = "https://persistent.oaistatic.com/codex-app-prod/Codex.dmg"
    public static let macX64DMGURL = "https://persistent.oaistatic.com/codex-app-prod/Codex-latest-x64.dmg"

    public struct Dependencies: Sendable {
        public var currentDirectory: @Sendable () -> URL
        public var canonicalizePath: @Sendable (String, URL) -> URL?
        public var homeDirectory: @Sendable () -> URL?
        public var isDirectory: @Sendable (URL) -> Bool
        public var isAppleSiliconMac: @Sendable () -> Bool
        public var makeTemporaryDirectory: @Sendable () throws -> URL
        public var removeItem: @Sendable (URL) throws -> Void
        public var createDirectory: @Sendable (URL) throws -> Void
        public var contentsOfDirectory: @Sendable (URL) throws -> [URL]
        public var runProcess: @Sendable (String, [String]) throws -> ProcessStatus
        public var runProcessWithOutput: @Sendable (String, [String]) throws -> ProcessOutput

        public init(
            currentDirectory: @escaping @Sendable () -> URL = {
                URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            },
            canonicalizePath: @escaping @Sendable (String, URL) -> URL? = { path, cwd in
                let url = URL(fileURLWithPath: path, relativeTo: path.hasPrefix("/") ? nil : cwd)
                guard FileManager.default.fileExists(atPath: url.path) else {
                    return nil
                }
                return url.resolvingSymlinksInPath().standardizedFileURL
            },
            homeDirectory: @escaping @Sendable () -> URL? = {
                guard let home = ProcessInfo.processInfo.environment["HOME"], !home.isEmpty else {
                    return nil
                }
                return URL(fileURLWithPath: home, isDirectory: true)
            },
            isDirectory: @escaping @Sendable (URL) -> Bool = { url in
                var isDirectory: ObjCBool = false
                return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
            },
            isAppleSiliconMac: @escaping @Sendable () -> Bool = {
                #if arch(arm64)
                return true
                #else
                return false
                #endif
            },
            makeTemporaryDirectory: @escaping @Sendable () throws -> URL = {
                let root = FileManager.default.temporaryDirectory
                    .appendingPathComponent("codex-app-installer-\(UUID().uuidString)", isDirectory: true)
                try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                return root
            },
            removeItem: @escaping @Sendable (URL) throws -> Void = { url in
                try FileManager.default.removeItem(at: url)
            },
            createDirectory: @escaping @Sendable (URL) throws -> Void = { url in
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            },
            contentsOfDirectory: @escaping @Sendable (URL) throws -> [URL] = { url in
                try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey])
            },
            runProcess: @escaping @Sendable (String, [String]) throws -> ProcessStatus = { command, arguments in
                try ProcessStatus.run(command: command, arguments: arguments)
            },
            runProcessWithOutput: @escaping @Sendable (String, [String]) throws -> ProcessOutput = { command, arguments in
                try ProcessOutput.run(command: command, arguments: arguments)
            }
        ) {
            self.currentDirectory = currentDirectory
            self.canonicalizePath = canonicalizePath
            self.homeDirectory = homeDirectory
            self.isDirectory = isDirectory
            self.isAppleSiliconMac = isAppleSiliconMac
            self.makeTemporaryDirectory = makeTemporaryDirectory
            self.removeItem = removeItem
            self.createDirectory = createDirectory
            self.contentsOfDirectory = contentsOfDirectory
            self.runProcess = runProcess
            self.runProcessWithOutput = runProcessWithOutput
        }
    }

    public struct ProcessStatus: Equatable, Sendable {
        public let isSuccess: Bool
        public let description: String

        public init(isSuccess: Bool, description: String) {
            self.isSuccess = isSuccess
            self.description = description
        }

        public static func run(command: String, arguments: [String]) throws -> ProcessStatus {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [command] + arguments
            try process.run()
            process.waitUntilExit()
            return ProcessStatus(
                isSuccess: process.terminationStatus == 0,
                description: statusDescription(process)
            )
        }
    }

    public struct ProcessOutput: Equatable, Sendable {
        public let status: ProcessStatus
        public let stdout: String
        public let stderr: String

        public init(status: ProcessStatus, stdout: String, stderr: String = "") {
            self.status = status
            self.stdout = stdout
            self.stderr = stderr
        }

        public static func run(command: String, arguments: [String]) throws -> ProcessOutput {
            let process = Process()
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [command] + arguments
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe
            try process.run()
            process.waitUntilExit()
            let stdout = String(decoding: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            let stderr = String(decoding: stderrPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            return ProcessOutput(
                status: ProcessStatus(
                    isSuccess: process.terminationStatus == 0,
                    description: statusDescription(process)
                ),
                stdout: stdout,
                stderr: stderr
            )
        }
    }

    public static func run(
        _ request: CodexCLI.AppCommandRequest,
        dependencies: Dependencies = Dependencies()
    ) throws -> CodexCLI.CommandExecutionResult {
        let workspace = dependencies.canonicalizePath(request.path, dependencies.currentDirectory())
            ?? URL(fileURLWithPath: request.path, relativeTo: request.path.hasPrefix("/") ? nil : dependencies.currentDirectory())

        guard let existingApp = findExistingCodexAppPath(dependencies: dependencies) else {
            return try downloadInstallAndOpen(
                workspace: workspace,
                downloadURLOverride: request.downloadURLOverride,
                dependencies: dependencies
            )
        }

        try openCodexApp(existingApp, workspace: workspace, dependencies: dependencies)
        return CodexCLI.CommandExecutionResult(
            exitCode: 0,
            stderrMessage: [
                "Opening Codex Desktop at \(existingApp.path)...",
                "Opening workspace \(workspace.path)..."
            ].joined(separator: "\n")
        )
    }

    public static func candidateCodexAppPaths(homeDirectory: URL?) -> [URL] {
        var paths = [URL(fileURLWithPath: "/Applications/Codex.app", isDirectory: true)]
        if let homeDirectory {
            paths.append(homeDirectory.appendingPathComponent("Applications/Codex.app", isDirectory: true))
        }
        return paths
    }

    public static func parseHdiutilAttachMountPoint(_ output: String) -> String? {
        output.split(separator: "\n", omittingEmptySubsequences: false).compactMap { line -> String? in
            guard line.contains("/Volumes/") else {
                return nil
            }
            if let tabIndex = line.lastIndex(of: "\t") {
                return String(line[line.index(after: tabIndex)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return line.split(whereSeparator: \.isWhitespace)
                .first { $0.hasPrefix("/Volumes/") }
                .map(String.init)
        }.first
    }

    private static func findExistingCodexAppPath(dependencies: Dependencies) -> URL? {
        candidateCodexAppPaths(homeDirectory: dependencies.homeDirectory())
            .first(where: dependencies.isDirectory)
    }

    private static func downloadInstallAndOpen(
        workspace: URL,
        downloadURLOverride: String?,
        dependencies: Dependencies
    ) throws -> CodexCLI.CommandExecutionResult {
        let downloadURL = downloadURLOverride ?? (dependencies.isAppleSiliconMac() ? macArm64DMGURL : macX64DMGURL)
        let installedApp = try downloadAndInstallCodex(
            downloadURL: downloadURL,
            dependencies: dependencies
        )
        try openCodexApp(installedApp, workspace: workspace, dependencies: dependencies)
        return CodexCLI.CommandExecutionResult(
            exitCode: 0,
            stderrMessage: [
                "Codex Desktop not found; downloading installer...",
                "Launching Codex Desktop from \(installedApp.path)...",
                "Opening workspace \(workspace.path)..."
            ].joined(separator: "\n")
        )
    }

    private static func openCodexApp(
        _ appPath: URL,
        workspace: URL,
        dependencies: Dependencies
    ) throws {
        let status = try dependencies.runProcess("open", ["-a", appPath.path, workspace.path])
        guard status.isSuccess else {
            throw AppCommandRuntimeError.openFailed(appPath: appPath.path, workspace: workspace.path, status: status.description)
        }
    }

    private static func downloadAndInstallCodex(
        downloadURL: String,
        dependencies: Dependencies
    ) throws -> URL {
        let tempDirectory = try dependencies.makeTemporaryDirectory()
        defer { try? dependencies.removeItem(tempDirectory) }
        let dmgPath = tempDirectory.appendingPathComponent("Codex.dmg", isDirectory: false)

        let downloadStatus = try dependencies.runProcess("curl", [
            "-fL",
            "--retry",
            "3",
            "--retry-delay",
            "1",
            "-o",
            dmgPath.path,
            downloadURL
        ])
        guard downloadStatus.isSuccess else {
            throw AppCommandRuntimeError.downloadFailed(status: downloadStatus.description)
        }

        let attachOutput = try dependencies.runProcessWithOutput("hdiutil", [
            "attach",
            "-nobrowse",
            "-readonly",
            dmgPath.path
        ])
        guard attachOutput.status.isSuccess else {
            throw AppCommandRuntimeError.attachFailed(
                status: attachOutput.status.description,
                stderr: attachOutput.stderr
            )
        }
        guard let mountPointPath = parseHdiutilAttachMountPoint(attachOutput.stdout) else {
            throw AppCommandRuntimeError.mountPointParseFailed(stdout: attachOutput.stdout)
        }

        let mountPoint = URL(fileURLWithPath: mountPointPath, isDirectory: true)
        defer { _ = try? dependencies.runProcess("hdiutil", ["detach", mountPoint.path]) }
        let appInVolume = try findCodexApp(inMount: mountPoint, dependencies: dependencies)
        return try installCodexAppBundle(appInVolume, dependencies: dependencies)
    }

    private static func findCodexApp(
        inMount mountPoint: URL,
        dependencies: Dependencies
    ) throws -> URL {
        let direct = mountPoint.appendingPathComponent("Codex.app", isDirectory: true)
        if dependencies.isDirectory(direct) {
            return direct
        }

        for entry in try dependencies.contentsOfDirectory(mountPoint) {
            if entry.pathExtension == "app", dependencies.isDirectory(entry) {
                return entry
            }
        }
        throw AppCommandRuntimeError.missingMountedApp(mountPoint: mountPoint.path)
    }

    private static func installCodexAppBundle(
        _ appInVolume: URL,
        dependencies: Dependencies
    ) throws -> URL {
        for applicationsDirectory in candidateApplicationsDirectories(homeDirectory: dependencies.homeDirectory()) {
            try dependencies.createDirectory(applicationsDirectory)
            let destination = applicationsDirectory.appendingPathComponent("Codex.app", isDirectory: true)
            if dependencies.isDirectory(destination) {
                return destination
            }
            let status = try dependencies.runProcess("ditto", [appInVolume.path, destination.path])
            if status.isSuccess {
                return destination
            }
        }
        throw AppCommandRuntimeError.installFailed
    }

    private static func candidateApplicationsDirectories(homeDirectory: URL?) -> [URL] {
        var directories = [URL(fileURLWithPath: "/Applications", isDirectory: true)]
        if let homeDirectory {
            directories.append(homeDirectory.appendingPathComponent("Applications", isDirectory: true))
        }
        return directories
    }
}

public enum AppCommandRuntimeError: Error, Equatable, CustomStringConvertible, Sendable {
    case openFailed(appPath: String, workspace: String, status: String)
    case downloadFailed(status: String)
    case attachFailed(status: String, stderr: String)
    case mountPointParseFailed(stdout: String)
    case missingMountedApp(mountPoint: String)
    case installFailed

    public var description: String {
        switch self {
        case let .openFailed(appPath, workspace, status):
            return "`open -a \(appPath) \(workspace)` exited with \(status)"
        case let .downloadFailed(status):
            return "curl download failed with \(status)"
        case let .attachFailed(status, stderr):
            return "`hdiutil attach` failed with \(status): \(stderr)"
        case let .mountPointParseFailed(stdout):
            return "failed to parse mount point from hdiutil output:\n\(stdout)"
        case let .missingMountedApp(mountPoint):
            return "no .app bundle found at \(mountPoint)"
        case .installFailed:
            return "failed to install Codex.app to any applications directory"
        }
    }
}

private func statusDescription(_ process: Process) -> String {
    switch process.terminationReason {
    case .exit:
        return "exit status: \(process.terminationStatus)"
    case .uncaughtSignal:
        return "signal: \(process.terminationStatus)"
    @unknown default:
        return "status: \(process.terminationStatus)"
    }
}
