import CodexCore
import Dispatch
import Darwin
import CryptoKit
import Foundation

public enum AppServerDaemonBackendKind: String, Codable, Sendable {
    case pid
}

public enum AppServerDaemonLifecycleStatus: String, Codable, Sendable {
    case alreadyRunning
    case restarted
    case running
    case started
    case stopped
    case notRunning
}

public enum AppServerDaemonBootstrapStatus: String, Codable, Sendable {
    case bootstrapped
}

public struct AppServerDaemonLifecycleOutput: Equatable, Codable, Sendable {
    public let status: AppServerDaemonLifecycleStatus
    public let backend: AppServerDaemonBackendKind?
    public let pid: UInt32?
    public let socketPath: String
    public let cliVersion: String?
    public let appServerVersion: String?

    public init(
        status: AppServerDaemonLifecycleStatus,
        backend: AppServerDaemonBackendKind?,
        pid: UInt32?,
        socketPath: String,
        cliVersion: String?,
        appServerVersion: String?
    ) {
        self.status = status
        self.backend = backend
        self.pid = pid
        self.socketPath = socketPath
        self.cliVersion = cliVersion
        self.appServerVersion = appServerVersion
    }

    enum CodingKeys: String, CodingKey {
        case status
        case backend
        case pid
        case socketPath
        case cliVersion
        case appServerVersion
    }
}

public struct AppServerDaemonBootstrapOutput: Equatable, Codable, Sendable {
    public let status: AppServerDaemonBootstrapStatus
    public let backend: AppServerDaemonBackendKind
    public let autoUpdateEnabled: Bool
    public let remoteControlEnabled: Bool
    public let managedCodexPath: String
    public let socketPath: String
    public let cliVersion: String
    public let appServerVersion: String

    public init(
        status: AppServerDaemonBootstrapStatus,
        backend: AppServerDaemonBackendKind,
        autoUpdateEnabled: Bool,
        remoteControlEnabled: Bool,
        managedCodexPath: String,
        socketPath: String,
        cliVersion: String,
        appServerVersion: String
    ) {
        self.status = status
        self.backend = backend
        self.autoUpdateEnabled = autoUpdateEnabled
        self.remoteControlEnabled = remoteControlEnabled
        self.managedCodexPath = managedCodexPath
        self.socketPath = socketPath
        self.cliVersion = cliVersion
        self.appServerVersion = appServerVersion
    }
}

public enum AppServerDaemonRemoteControlStartOutput: Equatable, Sendable {
    case bootstrap(AppServerDaemonBootstrapOutput)
    case start(AppServerDaemonLifecycleOutput)
}

public enum AppServerDaemonRemoteControlStatus: String, Codable, Sendable {
    case enabled
    case disabled
    case alreadyEnabled
    case alreadyDisabled
}

public struct AppServerDaemonRemoteControlOutput: Equatable, Codable, Sendable {
    public let status: AppServerDaemonRemoteControlStatus
    public let backend: AppServerDaemonBackendKind?
    public let remoteControlEnabled: Bool
    public let socketPath: String
    public let cliVersion: String
    public let appServerVersion: String?

    public init(
        status: AppServerDaemonRemoteControlStatus,
        backend: AppServerDaemonBackendKind?,
        remoteControlEnabled: Bool,
        socketPath: String,
        cliVersion: String,
        appServerVersion: String?
    ) {
        self.status = status
        self.backend = backend
        self.remoteControlEnabled = remoteControlEnabled
        self.socketPath = socketPath
        self.cliVersion = cliVersion
        self.appServerVersion = appServerVersion
    }
}

public enum AppServerDaemonSignal: Equatable, Sendable {
    case terminate
    case kill
}

public struct AppServerDaemonSpawnRequest: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case appServer(remoteControlEnabled: Bool)
        case updateLoop
    }

    public let executablePath: String
    public let arguments: [String]
    public let kind: Kind

    public init(executablePath: String, arguments: [String], kind: Kind) {
        self.executablePath = executablePath
        self.arguments = arguments
        self.kind = kind
    }
}

public struct AppServerDaemonExecutableIdentity: Equatable, Sendable {
    public let digestHex: String

    public init(bytes: Data) {
        digestHex = SHA256.hash(data: bytes)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

public struct AppServerDaemonUpdaterRuntimeClient: Sendable {
    public var managedCodexVersion: @Sendable (URL) async throws -> String
    public var reexecManagedUpdater: @Sendable (URL) async throws -> Void

    public init(
        managedCodexVersion: @escaping @Sendable (URL) async throws -> String,
        reexecManagedUpdater: @escaping @Sendable (URL) async throws -> Void
    ) {
        self.managedCodexVersion = managedCodexVersion
        self.reexecManagedUpdater = reexecManagedUpdater
    }

    public static let live = AppServerDaemonUpdaterRuntimeClient(
        managedCodexVersion: { codexBin in
            try await AppServerDaemonLifecycle.managedCodexVersion(codexBin: codexBin)
        },
        reexecManagedUpdater: { managedCodexBin in
            try AppServerDaemonLifecycle.reexecManagedUpdater(managedCodexBin: managedCodexBin)
        }
    )
}

public enum AppServerDaemonRestartMode: Equatable, Sendable {
    case ifVersionChanged
    case always
}

public enum AppServerDaemonUpdaterRefreshMode: Equatable, Sendable {
    case none
    case reexecIfManagedBinaryChanged
}

public struct AppServerDaemonUpdateModes: Equatable, Sendable {
    public let restartMode: AppServerDaemonRestartMode
    public let updaterRefreshMode: AppServerDaemonUpdaterRefreshMode

    public init(
        restartMode: AppServerDaemonRestartMode,
        updaterRefreshMode: AppServerDaemonUpdaterRefreshMode
    ) {
        self.restartMode = restartMode
        self.updaterRefreshMode = updaterRefreshMode
    }
}

public enum AppServerDaemonRestartDecision: Equatable, Sendable {
    case notReady
    case alreadyCurrent
    case restart
}

public enum AppServerDaemonRestartIfRunningOutcome: Equatable, Sendable {
    case busy
    case notRunning
    case notReady
    case alreadyCurrent
    case restarted
}

public enum AppServerDaemonUpdateLoopControl: Equatable, Sendable {
    case continueRunning
    case stop
}

public struct AppServerDaemonProcessClient: Sendable {
    public var processStartTime: @Sendable (UInt32) async throws -> String?
    public var signalProcess: @Sendable (UInt32, AppServerDaemonSignal) async throws -> Void
    public var sleep: @Sendable (TimeInterval) async throws -> Void
    public var spawnDetached: @Sendable (AppServerDaemonSpawnRequest) async throws -> UInt32
    public var probeAppServerVersion: @Sendable (String) async throws -> String

    public init(
        processStartTime: @escaping @Sendable (UInt32) async throws -> String?,
        signalProcess: @escaping @Sendable (UInt32, AppServerDaemonSignal) async throws -> Void,
        sleep: @escaping @Sendable (TimeInterval) async throws -> Void,
        spawnDetached: @escaping @Sendable (AppServerDaemonSpawnRequest) async throws -> UInt32,
        probeAppServerVersion: @escaping @Sendable (String) async throws -> String
    ) {
        self.processStartTime = processStartTime
        self.signalProcess = signalProcess
        self.sleep = sleep
        self.spawnDetached = spawnDetached
        self.probeAppServerVersion = probeAppServerVersion
    }

    public static let live = AppServerDaemonProcessClient(
        processStartTime: { pid in
            try await AppServerDaemonLifecycle.readProcessStartTime(pid: pid)
        },
        signalProcess: { pid, signal in
            try AppServerDaemonLifecycle.signalProcess(pid: pid, signal: signal)
        },
        sleep: { seconds in
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        },
        spawnDetached: { request in
            try AppServerDaemonLifecycle.spawnDetached(request)
        },
        probeAppServerVersion: { socketPath in
            try await AppServerDaemonLifecycle.probeAppServerVersion(socketPath: socketPath)
        }
    )
}

public struct AppServerDaemonStopOptions: Sendable {
    public let pollInterval: TimeInterval
    public let startTimeout: TimeInterval
    public let gracePeriod: TimeInterval
    public let timeout: TimeInterval
    public let operationLockTimeout: TimeInterval

    public init(
        pollInterval: TimeInterval = 0.05,
        startTimeout: TimeInterval = 10,
        gracePeriod: TimeInterval = 60,
        timeout: TimeInterval = 70,
        operationLockTimeout: TimeInterval = 75
    ) {
        self.pollInterval = pollInterval
        self.startTimeout = startTimeout
        self.gracePeriod = gracePeriod
        self.timeout = timeout
        self.operationLockTimeout = operationLockTimeout
    }
}

public struct AppServerDaemonUpdateLoopClient: Sendable {
    public var currentUpdaterIdentity: @Sendable () async throws -> AppServerDaemonExecutableIdentity
    public var installLatestStandalone: @Sendable () async throws -> Void
    public var resolvedManagedCodexBin: @Sendable (URL) async throws -> URL
    public var executableIdentity: @Sendable (URL) async throws -> AppServerDaemonExecutableIdentity
    public var tryRestartIfRunning: @Sendable (
        AppServerDaemonRestartMode,
        AppServerDaemonUpdaterRefreshMode,
        URL
    ) async throws -> AppServerDaemonRestartIfRunningOutcome
    public var sleepOrTerminate: @Sendable (TimeInterval) async throws -> Bool
    public var terminationRequested: @Sendable () async -> Bool

    public init(
        currentUpdaterIdentity: @escaping @Sendable () async throws -> AppServerDaemonExecutableIdentity,
        installLatestStandalone: @escaping @Sendable () async throws -> Void,
        resolvedManagedCodexBin: @escaping @Sendable (URL) async throws -> URL,
        executableIdentity: @escaping @Sendable (URL) async throws -> AppServerDaemonExecutableIdentity,
        tryRestartIfRunning: @escaping @Sendable (
            AppServerDaemonRestartMode,
            AppServerDaemonUpdaterRefreshMode,
            URL
        ) async throws -> AppServerDaemonRestartIfRunningOutcome,
        sleepOrTerminate: @escaping @Sendable (TimeInterval) async throws -> Bool,
        terminationRequested: @escaping @Sendable () async -> Bool
    ) {
        self.currentUpdaterIdentity = currentUpdaterIdentity
        self.installLatestStandalone = installLatestStandalone
        self.resolvedManagedCodexBin = resolvedManagedCodexBin
        self.executableIdentity = executableIdentity
        self.tryRestartIfRunning = tryRestartIfRunning
        self.sleepOrTerminate = sleepOrTerminate
        self.terminationRequested = terminationRequested
    }

    public static func live(
        codexHome: URL,
        processClient: AppServerDaemonProcessClient = .live,
        updaterClient: AppServerDaemonUpdaterRuntimeClient = .live,
        options: AppServerDaemonStopOptions = AppServerDaemonStopOptions()
    ) -> AppServerDaemonUpdateLoopClient {
        let termination = AppServerDaemonTerminationFlag()
        AppServerDaemonLifecycle.installTerminationHandler(termination: termination)
        return AppServerDaemonUpdateLoopClient(
            currentUpdaterIdentity: {
                try AppServerDaemonLifecycle.currentUpdaterIdentity()
            },
            installLatestStandalone: {
                try await AppServerDaemonLifecycle.installLatestStandalone()
            },
            resolvedManagedCodexBin: { codexBin in
                try AppServerDaemonLifecycle.resolvedManagedCodexBin(codexBin)
            },
            executableIdentity: { executable in
                try AppServerDaemonLifecycle.executableIdentity(at: executable)
            },
            tryRestartIfRunning: { restartMode, updaterRefreshMode, managedCodexBin in
                try await AppServerDaemonLifecycle.tryRestartIfRunning(
                    codexHome: codexHome,
                    restartMode: restartMode,
                    updaterRefreshMode: updaterRefreshMode,
                    managedCodexBin: managedCodexBin,
                    processClient: processClient,
                    updaterClient: updaterClient,
                    options: options
                )
            },
            sleepOrTerminate: { seconds in
                try await AppServerDaemonLifecycle.sleepOrTerminate(
                    seconds,
                    termination: termination,
                    processClient: processClient,
                    pollInterval: options.pollInterval
                )
            },
            terminationRequested: {
                await termination.isTerminated()
            }
        )
    }
}

public enum AppServerDaemonLifecycle {
    public static func executableIdentity(at executable: URL) throws -> AppServerDaemonExecutableIdentity {
        do {
            return AppServerDaemonExecutableIdentity(bytes: try Data(contentsOf: executable))
        } catch {
            throw AppServerDaemonLifecycleError("failed to read executable \(executable.path): \(error)")
        }
    }

    public static func parseManagedCodexVersionOutput(_ output: String) throws -> String {
        guard let version = output.split(whereSeparator: \.isWhitespace).dropFirst().first,
              !version.isEmpty else {
            throw AppServerDaemonLifecycleError("managed Codex version output was malformed")
        }
        return String(version)
    }

    public static func managedCodexVersion(codexBin: URL) async throws -> String {
        try await Task.detached {
            let process = Process()
            process.executableURL = codexBin
            process.arguments = ["--version"]
            let stdout = Pipe()
            process.standardOutput = stdout
            process.standardError = Pipe()
            do {
                try process.run()
            } catch {
                throw AppServerDaemonLifecycleError(
                    "failed to invoke managed Codex binary \(codexBin.path): \(error)"
                )
            }
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                throw AppServerDaemonLifecycleError(
                    "managed Codex binary \(codexBin.path) exited with status \(process.terminationStatus)"
                )
            }
            let data = stdout.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else {
                throw AppServerDaemonLifecycleError(
                    "managed Codex version was not utf-8: \(codexBin.path)"
                )
            }
            return try parseManagedCodexVersionOutput(output)
        }.value
    }

    public static func resolvedManagedCodexBin(_ codexBin: URL) throws -> URL {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        guard realpath(codexBin.path, &buffer) != nil else {
            throw AppServerDaemonLifecycleError(
                "failed to resolve managed Codex binary \(codexBin.path): \(String(cString: strerror(errno)))"
            )
        }
        let end = buffer.firstIndex(of: 0) ?? buffer.endIndex
        let pathBytes = buffer[..<end].map { UInt8(bitPattern: $0) }
        return URL(fileURLWithPath: String(decoding: pathBytes, as: UTF8.self), isDirectory: false)
    }

    public static func updateModesForIdentities(
        currentUpdater: AppServerDaemonExecutableIdentity,
        managedCodex: AppServerDaemonExecutableIdentity
    ) -> AppServerDaemonUpdateModes {
        if currentUpdater == managedCodex {
            return AppServerDaemonUpdateModes(restartMode: .ifVersionChanged, updaterRefreshMode: .none)
        }
        return AppServerDaemonUpdateModes(restartMode: .always, updaterRefreshMode: .reexecIfManagedBinaryChanged)
    }

    public static func restartDecision(
        mode: AppServerDaemonRestartMode,
        appServerVersion: String?,
        managedVersion: String?
    ) -> AppServerDaemonRestartDecision {
        switch mode {
        case .ifVersionChanged:
            guard let appServerVersion else {
                return .notReady
            }
            if appServerVersion == managedVersion {
                return .alreadyCurrent
            }
            return .restart
        case .always:
            return .restart
        }
    }

    public static func shouldReexecUpdater(
        refreshMode: AppServerDaemonUpdaterRefreshMode,
        outcome: AppServerDaemonRestartIfRunningOutcome
    ) -> Bool {
        refreshMode == .reexecIfManagedBinaryChanged && outcome == .restarted
    }

    public static func tryRestartIfRunning(
        codexHome: URL,
        restartMode: AppServerDaemonRestartMode,
        updaterRefreshMode: AppServerDaemonUpdaterRefreshMode,
        managedCodexBin: URL,
        processClient: AppServerDaemonProcessClient = .live,
        updaterClient: AppServerDaemonUpdaterRuntimeClient = .live,
        options: AppServerDaemonStopOptions = AppServerDaemonStopOptions()
    ) async throws -> AppServerDaemonRestartIfRunningOutcome {
        let paths = AppServerDaemonPaths(codexHome: codexHome)
        try FileManager.default.createDirectory(at: paths.stateDirectory, withIntermediateDirectories: true)
        guard let lock = try AppServerDaemonOperationLock.tryAcquire(path: paths.operationLockFile) else {
            return .busy
        }
        defer { lock.close() }

        let settings = try loadSettings(path: paths.settingsFile)
        let outcome: AppServerDaemonRestartIfRunningOutcome
        if try await isPidBackendStartingOrRunning(
            pidFile: paths.pidFile,
            processClient: processClient,
            options: options
        ) {
            let appServerVersion = try? await processClient.probeAppServerVersion(paths.socketPath)
            let managedVersion = appServerVersion == nil
                ? nil
                : try await updaterClient.managedCodexVersion(managedCodexBin)
            switch restartDecision(
                mode: restartMode,
                appServerVersion: appServerVersion,
                managedVersion: managedVersion
            ) {
            case .notReady:
                return .notReady
            case .alreadyCurrent:
                outcome = .alreadyCurrent
            case .restart:
                try await stopPidBackend(pidFile: paths.pidFile, processClient: processClient, options: options)
                _ = try await startPidBackend(
                    pidFile: paths.pidFile,
                    codexBin: managedCodexBin,
                    kind: .appServer(remoteControlEnabled: settings.remoteControlEnabled),
                    processClient: processClient,
                    options: options
                )
                _ = try await waitUntilReady(
                    socketPath: paths.socketPath,
                    processClient: processClient,
                    options: options
                )
                outcome = .restarted
            }
        } else if (try? await processClient.probeAppServerVersion(paths.socketPath)) != nil {
            throw AppServerDaemonLifecycleError("app server is running but is not managed by codex app-server daemon")
        } else {
            outcome = .notRunning
        }

        if shouldReexecUpdater(refreshMode: updaterRefreshMode, outcome: outcome) {
            try await updaterClient.reexecManagedUpdater(managedCodexBin)
        }
        return outcome
    }

    public static func runPidUpdateLoop() async throws {
        try await runPidUpdateLoop(codexHome: try CodexHome.find())
    }

    public static func runPidUpdateLoop(
        codexHome: URL,
        initialDelay: TimeInterval = 5 * 60,
        updateInterval: TimeInterval = 60 * 60,
        retryInterval: TimeInterval = 0.05,
        client: AppServerDaemonUpdateLoopClient? = nil
    ) async throws {
        let updateLoopClient = client ?? AppServerDaemonUpdateLoopClient.live(codexHome: codexHome)
        let runningUpdaterIdentity = try await updateLoopClient.currentUpdaterIdentity()
        if try await updateLoopClient.sleepOrTerminate(initialDelay) {
            return
        }
        while true {
            do {
                switch try await runPidUpdateLoopOnce(
                    codexHome: codexHome,
                    runningUpdaterIdentity: runningUpdaterIdentity,
                    retryInterval: retryInterval,
                    client: updateLoopClient
                ) {
                case .continueRunning:
                    break
                case .stop:
                    return
                }
            } catch {
                // Rust swallows per-iteration updater errors and retries after the normal interval.
            }
            if try await updateLoopClient.sleepOrTerminate(updateInterval) {
                return
            }
        }
    }

    public static func runPidUpdateLoopOnce(
        codexHome: URL,
        runningUpdaterIdentity: AppServerDaemonExecutableIdentity,
        retryInterval: TimeInterval = 0.05,
        client: AppServerDaemonUpdateLoopClient
    ) async throws -> AppServerDaemonUpdateLoopControl {
        let paths = AppServerDaemonPaths(codexHome: codexHome)
        try await client.installLatestStandalone()
        let managedCodexBin = try await client.resolvedManagedCodexBin(paths.managedCodexBin)
        let managedIdentity = try await client.executableIdentity(managedCodexBin)
        let modes = updateModesForIdentities(
            currentUpdater: runningUpdaterIdentity,
            managedCodex: managedIdentity
        )
        while true {
            if await client.terminationRequested() {
                return .stop
            }
            switch try await client.tryRestartIfRunning(
                modes.restartMode,
                modes.updaterRefreshMode,
                managedCodexBin
            ) {
            case .busy:
                if try await client.sleepOrTerminate(retryInterval) {
                    return .stop
                }
            case .notRunning, .notReady, .alreadyCurrent, .restarted:
                return .continueRunning
            }
        }
    }

    public static func installLatestStandalone(
        scriptURL: URL = URL(string: "https://chatgpt.com/codex/install.sh")!
    ) async throws {
        let script: Data
        do {
            let (data, response) = try await URLSession.shared.data(from: scriptURL)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw AppServerDaemonLifecycleError("standalone Codex updater request failed")
            }
            guard (200..<300).contains(httpResponse.statusCode) else {
                throw AppServerDaemonLifecycleError("standalone Codex updater request failed")
            }
            script = data
        } catch let error as AppServerDaemonLifecycleError {
            throw error
        } catch {
            throw AppServerDaemonLifecycleError("failed to fetch standalone Codex updater: \(error)")
        }
        try runStandaloneUpdaterScript(script)
    }

    public static func currentUpdaterIdentity() throws -> AppServerDaemonExecutableIdentity {
        guard let executable = Bundle.main.executableURL else {
            throw AppServerDaemonLifecycleError("failed to resolve current updater executable")
        }
        return try executableIdentity(at: executable)
    }

    public static func start(
        codexHome: URL,
        cliVersion: String,
        processClient: AppServerDaemonProcessClient = .live,
        options: AppServerDaemonStopOptions = AppServerDaemonStopOptions()
    ) async throws -> AppServerDaemonLifecycleOutput {
        let paths = AppServerDaemonPaths(codexHome: codexHome)
        try FileManager.default.createDirectory(at: paths.stateDirectory, withIntermediateDirectories: true)
        let lock = try await AppServerDaemonOperationLock.acquire(
            path: paths.operationLockFile,
            timeout: options.operationLockTimeout,
            pollInterval: options.pollInterval,
            sleep: processClient.sleep
        )
        defer { lock.close() }
        return try await startWithLockHeld(
            paths: paths,
            cliVersion: cliVersion,
            processClient: processClient,
            options: options,
            remoteControlEnabled: false
        )
    }

    public static func restart(
        codexHome: URL,
        cliVersion: String,
        processClient: AppServerDaemonProcessClient = .live,
        options: AppServerDaemonStopOptions = AppServerDaemonStopOptions()
    ) async throws -> AppServerDaemonLifecycleOutput {
        let paths = AppServerDaemonPaths(codexHome: codexHome)
        try FileManager.default.createDirectory(at: paths.stateDirectory, withIntermediateDirectories: true)
        let lock = try await AppServerDaemonOperationLock.acquire(
            path: paths.operationLockFile,
            timeout: options.operationLockTimeout,
            pollInterval: options.pollInterval,
            sleep: processClient.sleep
        )
        defer { lock.close() }
        let settings = try loadSettings(path: paths.settingsFile)
        if (try? await processClient.probeAppServerVersion(paths.socketPath)) != nil,
           try await runningBackend(pidFile: paths.pidFile, processClient: processClient, options: options) == nil {
            throw AppServerDaemonLifecycleError("app server is running but is not managed by codex app-server daemon")
        }
        try ensureManagedCodexBin(paths.managedCodexBin)
        if try await isPidBackendStartingOrRunning(pidFile: paths.pidFile, processClient: processClient, options: options) {
            try await stopPidBackend(pidFile: paths.pidFile, processClient: processClient, options: options)
        }
        let pid = try await startPidBackend(
            pidFile: paths.pidFile,
            codexBin: paths.managedCodexBin,
            kind: .appServer(remoteControlEnabled: settings.remoteControlEnabled),
            processClient: processClient,
            options: options
        )
        let appServerVersion = try await waitUntilReady(
            socketPath: paths.socketPath,
            processClient: processClient,
            options: options
        )
        return AppServerDaemonLifecycleOutput(
            status: .restarted,
            backend: .pid,
            pid: pid,
            socketPath: paths.socketPath,
            cliVersion: cliVersion,
            appServerVersion: appServerVersion
        )
    }

    public static func bootstrap(
        codexHome: URL,
        cliVersion: String,
        remoteControlEnabled: Bool,
        processClient: AppServerDaemonProcessClient = .live,
        options: AppServerDaemonStopOptions = AppServerDaemonStopOptions()
    ) async throws -> AppServerDaemonBootstrapOutput {
        let paths = AppServerDaemonPaths(codexHome: codexHome)
        try FileManager.default.createDirectory(at: paths.stateDirectory, withIntermediateDirectories: true)
        let lock = try await AppServerDaemonOperationLock.acquire(
            path: paths.operationLockFile,
            timeout: options.operationLockTimeout,
            pollInterval: options.pollInterval,
            sleep: processClient.sleep
        )
        defer { lock.close() }
        return try await bootstrapWithLockHeld(
            paths: paths,
            cliVersion: cliVersion,
            processClient: processClient,
            options: options,
            remoteControlEnabled: remoteControlEnabled
        )
    }

    public static func version(
        codexHome: URL,
        cliVersion: String,
        processClient: AppServerDaemonProcessClient = .live,
        options: AppServerDaemonStopOptions = AppServerDaemonStopOptions()
    ) async throws -> AppServerDaemonLifecycleOutput {
        let paths = AppServerDaemonPaths(codexHome: codexHome)
        _ = try loadSettings(path: paths.settingsFile)
        let appServerVersion = try await processClient.probeAppServerVersion(paths.socketPath)
        return output(
            status: .running,
            backend: try await runningBackend(pidFile: paths.pidFile, processClient: processClient, options: options),
            socketPath: paths.socketPath,
            cliVersion: cliVersion,
            appServerVersion: appServerVersion
        )
    }

    public static func setRemoteControl(
        codexHome: URL,
        cliVersion: String,
        enabled: Bool,
        processClient: AppServerDaemonProcessClient = .live,
        options: AppServerDaemonStopOptions = AppServerDaemonStopOptions()
    ) async throws -> AppServerDaemonRemoteControlOutput {
        let paths = AppServerDaemonPaths(codexHome: codexHome)
        try FileManager.default.createDirectory(at: paths.stateDirectory, withIntermediateDirectories: true)
        let lock = try await AppServerDaemonOperationLock.acquire(
            path: paths.operationLockFile,
            timeout: options.operationLockTimeout,
            pollInterval: options.pollInterval,
            sleep: processClient.sleep
        )
        defer { lock.close() }

        let previousSettings = try loadSettings(path: paths.settingsFile)
        let backend = try await runningBackend(pidFile: paths.pidFile, processClient: processClient, options: options)
        if backend == nil, (try? await processClient.probeAppServerVersion(paths.socketPath)) != nil {
            throw AppServerDaemonLifecycleError("app server is running but is not managed by codex app-server daemon")
        }

        if previousSettings.remoteControlEnabled == enabled {
            let version = backend == nil ? nil : try await waitUntilReady(
                socketPath: paths.socketPath,
                processClient: processClient,
                options: options
            )
            return remoteControlOutput(
                status: enabled ? .alreadyEnabled : .alreadyDisabled,
                backend: backend,
                remoteControlEnabled: enabled,
                socketPath: paths.socketPath,
                cliVersion: cliVersion,
                appServerVersion: version
            )
        }

        try saveSettings(AppServerDaemonSettings(remoteControlEnabled: enabled), path: paths.settingsFile)
        let version: String?
        if backend != nil {
            try ensureManagedCodexBin(paths.managedCodexBin)
            try await stopPidBackend(pidFile: paths.pidFile, processClient: processClient, options: options)
            _ = try await startPidBackend(
                pidFile: paths.pidFile,
                codexBin: paths.managedCodexBin,
                kind: .appServer(remoteControlEnabled: enabled),
                processClient: processClient,
                options: options
            )
            version = try await waitUntilReady(
                socketPath: paths.socketPath,
                processClient: processClient,
                options: options
            )
        } else {
            version = nil
        }

        return remoteControlOutput(
            status: enabled ? .enabled : .disabled,
            backend: version == nil ? nil : .pid,
            remoteControlEnabled: enabled,
            socketPath: paths.socketPath,
            cliVersion: cliVersion,
            appServerVersion: version
        )
    }

    public static func ensureRemoteControlStarted(
        codexHome: URL,
        cliVersion: String,
        processClient: AppServerDaemonProcessClient = .live,
        options: AppServerDaemonStopOptions = AppServerDaemonStopOptions()
    ) async throws -> AppServerDaemonRemoteControlStartOutput {
        let paths = AppServerDaemonPaths(codexHome: codexHome)
        try FileManager.default.createDirectory(
            at: paths.stateDirectory,
            withIntermediateDirectories: true
        )
        let lock = try await AppServerDaemonOperationLock.acquire(
            path: paths.operationLockFile,
            timeout: options.operationLockTimeout,
            pollInterval: options.pollInterval,
            sleep: processClient.sleep
        )
        defer { lock.close() }

        _ = try loadSettings(path: paths.settingsFile)
        if try await isPidBackendStartingOrRunning(
            pidFile: paths.updatePidFile,
            processClient: processClient,
            options: options
        ) {
            try saveSettings(AppServerDaemonSettings(remoteControlEnabled: true), path: paths.settingsFile)
            let output = try await startWithLockHeld(
                paths: paths,
                cliVersion: cliVersion,
                processClient: processClient,
                options: options,
                remoteControlEnabled: true
            )
            return .start(output)
        }

        return .bootstrap(try await bootstrapWithLockHeld(
            paths: paths,
            cliVersion: cliVersion,
            processClient: processClient,
            options: options,
            remoteControlEnabled: true
        ))
    }

    public static func stop(
        codexHome: URL,
        cliVersion: String,
        processClient: AppServerDaemonProcessClient = .live,
        options: AppServerDaemonStopOptions = AppServerDaemonStopOptions()
    ) async throws -> AppServerDaemonLifecycleOutput {
        let paths = AppServerDaemonPaths(codexHome: codexHome)
        try FileManager.default.createDirectory(
            at: paths.stateDirectory,
            withIntermediateDirectories: true
        )
        let lock = try await AppServerDaemonOperationLock.acquire(
            path: paths.operationLockFile,
            timeout: options.operationLockTimeout,
            pollInterval: options.pollInterval,
            sleep: processClient.sleep
        )
        defer { lock.close() }

        return try await stopWithLockHeld(
            paths: paths,
            cliVersion: cliVersion,
            processClient: processClient,
            options: options
        )
    }

    private static func stopWithLockHeld(
        paths: AppServerDaemonPaths,
        cliVersion: String,
        processClient: AppServerDaemonProcessClient,
        options: AppServerDaemonStopOptions
    ) async throws -> AppServerDaemonLifecycleOutput {
        _ = try loadSettings(path: paths.settingsFile)
        while true {
            guard let record = try readPidRecord(path: paths.pidFile) else {
                return output(
                    status: .notRunning,
                    backend: nil,
                    socketPath: paths.socketPath,
                    cliVersion: cliVersion
                )
            }
            guard try await recordIsActive(record, processClient: processClient) else {
                try? FileManager.default.removeItem(at: paths.pidFile)
                continue
            }

            try await processClient.signalProcess(record.pid, .terminate)
            let startedAt = Date()
            let deadline = startedAt.addingTimeInterval(options.timeout)
            var forced = false
            while Date() < deadline {
                if try await !recordIsActive(record, processClient: processClient) {
                    try? FileManager.default.removeItem(at: paths.pidFile)
                    return output(
                        status: .stopped,
                        backend: .pid,
                        socketPath: paths.socketPath,
                        cliVersion: cliVersion
                    )
                }
                if !forced && Date().timeIntervalSince(startedAt) >= options.gracePeriod {
                    try await processClient.signalProcess(record.pid, .kill)
                    forced = true
                }
                try await processClient.sleep(options.pollInterval)
            }

            if try await recordIsActive(record, processClient: processClient) {
                throw AppServerDaemonLifecycleError(
                    "timed out waiting for pid-managed app server \(record.pid) to stop"
                )
            }
        }
    }

    private static func startWithLockHeld(
        paths: AppServerDaemonPaths,
        cliVersion: String,
        processClient: AppServerDaemonProcessClient,
        options: AppServerDaemonStopOptions,
        remoteControlEnabled: Bool
    ) async throws -> AppServerDaemonLifecycleOutput {
        let settings = try loadSettings(path: paths.settingsFile)
        if let appServerVersion = try? await processClient.probeAppServerVersion(paths.socketPath) {
            return output(
                status: .alreadyRunning,
                backend: try await runningBackend(
                    pidFile: paths.pidFile,
                    processClient: processClient,
                    options: options
                ),
                socketPath: paths.socketPath,
                cliVersion: cliVersion,
                appServerVersion: appServerVersion
            )
        }

        if try await isPidBackendStartingOrRunning(
            pidFile: paths.pidFile,
            processClient: processClient,
            options: options
        ) {
            let appServerVersion = try await waitUntilReady(
                socketPath: paths.socketPath,
                processClient: processClient,
                options: options
            )
            return output(
                status: .alreadyRunning,
                backend: .pid,
                socketPath: paths.socketPath,
                cliVersion: cliVersion,
                appServerVersion: appServerVersion
            )
        }

        try ensureManagedCodexBin(paths.managedCodexBin)
        let pid = try await startPidBackend(
            pidFile: paths.pidFile,
            codexBin: paths.managedCodexBin,
            kind: .appServer(remoteControlEnabled: settings.remoteControlEnabled || remoteControlEnabled),
            processClient: processClient,
            options: options
        )
        let appServerVersion = try await waitUntilReady(
            socketPath: paths.socketPath,
            processClient: processClient,
            options: options
        )
        return AppServerDaemonLifecycleOutput(
            status: .started,
            backend: .pid,
            pid: pid,
            socketPath: paths.socketPath,
            cliVersion: cliVersion,
            appServerVersion: appServerVersion
        )
    }

    private static func bootstrapWithLockHeld(
        paths: AppServerDaemonPaths,
        cliVersion: String,
        processClient: AppServerDaemonProcessClient,
        options: AppServerDaemonStopOptions,
        remoteControlEnabled: Bool
    ) async throws -> AppServerDaemonBootstrapOutput {
        try ensureManagedCodexBin(paths.managedCodexBin)
        let settings = AppServerDaemonSettings(remoteControlEnabled: remoteControlEnabled)
        if (try? await processClient.probeAppServerVersion(paths.socketPath)) != nil,
           try await runningBackend(pidFile: paths.pidFile, processClient: processClient, options: options) == nil {
            throw AppServerDaemonLifecycleError("app server is running but is not managed by codex app-server daemon")
        }
        try saveSettings(settings, path: paths.settingsFile)

        if try await isPidBackendStartingOrRunning(pidFile: paths.pidFile, processClient: processClient, options: options) {
            _ = try await stopWithLockHeld(paths: paths, cliVersion: cliVersion, processClient: processClient, options: options)
        }
        _ = try await startPidBackend(
            pidFile: paths.pidFile,
            codexBin: paths.managedCodexBin,
            kind: .appServer(remoteControlEnabled: settings.remoteControlEnabled),
            processClient: processClient,
            options: options
        )
        if try await isPidBackendStartingOrRunning(pidFile: paths.updatePidFile, processClient: processClient, options: options) {
            try await stopPidBackend(pidFile: paths.updatePidFile, processClient: processClient, options: options)
        }
        _ = try await startPidBackend(
            pidFile: paths.updatePidFile,
            codexBin: paths.managedCodexBin,
            kind: .updateLoop,
            processClient: processClient,
            options: options
        )
        let appServerVersion = try await waitUntilReady(
            socketPath: paths.socketPath,
            processClient: processClient,
            options: options
        )
        return AppServerDaemonBootstrapOutput(
            status: .bootstrapped,
            backend: .pid,
            autoUpdateEnabled: true,
            remoteControlEnabled: settings.remoteControlEnabled,
            managedCodexPath: paths.managedCodexBin.path,
            socketPath: paths.socketPath,
            cliVersion: cliVersion,
            appServerVersion: appServerVersion
        )
    }

    public static func encodeOutput(_ output: AppServerDaemonLifecycleOutput) throws -> String {
        var fields = [
            "\"status\":\(try jsonString(output.status.rawValue))"
        ]
        if let backend = output.backend {
            fields.append("\"backend\":\(try jsonString(backend.rawValue))")
        }
        if let pid = output.pid {
            fields.append("\"pid\":\(pid)")
        }
        fields.append("\"socketPath\":\(try jsonString(output.socketPath))")
        if let cliVersion = output.cliVersion {
            fields.append("\"cliVersion\":\(try jsonString(cliVersion))")
        }
        if let appServerVersion = output.appServerVersion {
            fields.append("\"appServerVersion\":\(try jsonString(appServerVersion))")
        }
        return "{\(fields.joined(separator: ","))}"
    }

    public static func encodeRemoteControlStartOutput(_ output: AppServerDaemonRemoteControlStartOutput) throws -> String {
        switch output {
        case let .start(output):
            return try encodeOutput(output)
        case let .bootstrap(output):
            return try encodeBootstrapOutput(output)
        }
    }

    public static func encodeBootstrapOutput(_ output: AppServerDaemonBootstrapOutput) throws -> String {
        let fields = [
            "\"status\":\(try jsonString(output.status.rawValue))",
            "\"backend\":\(try jsonString(output.backend.rawValue))",
            "\"autoUpdateEnabled\":\(output.autoUpdateEnabled)",
            "\"remoteControlEnabled\":\(output.remoteControlEnabled)",
            "\"managedCodexPath\":\(try jsonString(output.managedCodexPath))",
            "\"socketPath\":\(try jsonString(output.socketPath))",
            "\"cliVersion\":\(try jsonString(output.cliVersion))",
            "\"appServerVersion\":\(try jsonString(output.appServerVersion))"
        ]
        return "{\(fields.joined(separator: ","))}"
    }

    public static func encodeRemoteControlOutput(_ output: AppServerDaemonRemoteControlOutput) throws -> String {
        var fields = [
            "\"status\":\(try jsonString(output.status.rawValue))"
        ]
        if let backend = output.backend {
            fields.append("\"backend\":\(try jsonString(backend.rawValue))")
        }
        fields.append("\"remoteControlEnabled\":\(output.remoteControlEnabled)")
        fields.append("\"socketPath\":\(try jsonString(output.socketPath))")
        fields.append("\"cliVersion\":\(try jsonString(output.cliVersion))")
        if let appServerVersion = output.appServerVersion {
            fields.append("\"appServerVersion\":\(try jsonString(appServerVersion))")
        }
        return "{\(fields.joined(separator: ","))}"
    }

    private static func jsonString(_ value: String) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        let encoded = try encoder.encode([value])
        let array = String(decoding: encoded, as: UTF8.self)
        return String(array.dropFirst().dropLast())
    }

    private static func output(
        status: AppServerDaemonLifecycleStatus,
        backend: AppServerDaemonBackendKind?,
        socketPath: String,
        cliVersion: String,
        appServerVersion: String? = nil
    ) -> AppServerDaemonLifecycleOutput {
        AppServerDaemonLifecycleOutput(
            status: status,
            backend: backend,
            pid: nil,
            socketPath: socketPath,
            cliVersion: cliVersion,
            appServerVersion: appServerVersion
        )
    }

    private static func remoteControlOutput(
        status: AppServerDaemonRemoteControlStatus,
        backend: AppServerDaemonBackendKind?,
        remoteControlEnabled: Bool,
        socketPath: String,
        cliVersion: String,
        appServerVersion: String?
    ) -> AppServerDaemonRemoteControlOutput {
        AppServerDaemonRemoteControlOutput(
            status: status,
            backend: backend,
            remoteControlEnabled: remoteControlEnabled,
            socketPath: socketPath,
            cliVersion: cliVersion,
            appServerVersion: appServerVersion
        )
    }

    private static func runningBackend(
        pidFile: URL,
        processClient: AppServerDaemonProcessClient,
        options: AppServerDaemonStopOptions
    ) async throws -> AppServerDaemonBackendKind? {
        try await isPidBackendStartingOrRunning(
            pidFile: pidFile,
            processClient: processClient,
            options: options
        ) ? .pid : nil
    }

    private static func isPidBackendStartingOrRunning(
        pidFile: URL,
        processClient: AppServerDaemonProcessClient,
        options: AppServerDaemonStopOptions
    ) async throws -> Bool {
        while true {
            guard let record = try readPidRecord(path: pidFile) else {
                return false
            }
            if try await recordIsActive(record, processClient: processClient) {
                return true
            }
            try? FileManager.default.removeItem(at: pidFile)
        }
    }

    private static func stopPidBackend(
        pidFile: URL,
        processClient: AppServerDaemonProcessClient,
        options: AppServerDaemonStopOptions
    ) async throws {
        while true {
            guard let record = try readPidRecord(path: pidFile) else {
                return
            }
            guard try await recordIsActive(record, processClient: processClient) else {
                try? FileManager.default.removeItem(at: pidFile)
                continue
            }
            try await processClient.signalProcess(record.pid, .terminate)
            let deadline = Date().addingTimeInterval(options.timeout)
            while Date() < deadline {
                if try await !recordIsActive(record, processClient: processClient) {
                    try? FileManager.default.removeItem(at: pidFile)
                    return
                }
                try await processClient.sleep(options.pollInterval)
            }
            throw AppServerDaemonLifecycleError("timed out waiting for pid-managed app server \(record.pid) to stop")
        }
    }

    private static func startPidBackend(
        pidFile: URL,
        codexBin: URL,
        kind: AppServerDaemonSpawnRequest.Kind,
        processClient: AppServerDaemonProcessClient,
        options: AppServerDaemonStopOptions
    ) async throws -> UInt32? {
        if let parent = pidFile.deletingLastPathComponentIfPresent() {
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        }
        let reservationLock = try await AppServerDaemonOperationLock.acquire(
            path: pidFile.deletingPathExtension().appendingPathExtension("pid.lock"),
            timeout: options.startTimeout,
            pollInterval: options.pollInterval,
            sleep: processClient.sleep
        )
        defer { reservationLock.close() }

        if let record = try readPidRecord(path: pidFile) {
            if try await recordIsActive(record, processClient: processClient) {
                return nil
            }
            try? FileManager.default.removeItem(at: pidFile)
        }

        FileManager.default.createFile(atPath: pidFile.path, contents: Data())
        let request = AppServerDaemonSpawnRequest(
            executablePath: codexBin.path,
            arguments: commandArguments(for: kind),
            kind: kind
        )
        let pid: UInt32
        do {
            pid = try await processClient.spawnDetached(request)
        } catch {
            try? FileManager.default.removeItem(at: pidFile)
            throw AppServerDaemonLifecycleError(
                "failed to spawn detached app-server process using \(codexBin.path): \(error)"
            )
        }

        let processStartTime: String
        do {
            guard let startTime = try await processClient.processStartTime(pid) else {
                throw AppServerDaemonLifecycleError("pid-managed app server \(pid) has no recorded start time")
            }
            processStartTime = startTime
        } catch {
            try? await processClient.signalProcess(pid, .terminate)
            try? FileManager.default.removeItem(at: pidFile)
            throw error
        }

        let record = AppServerDaemonPidRecord(pid: pid, processStartTime: processStartTime)
        let data = try JSONEncoder().encode(record)
        let tempFile = pidFile.deletingPathExtension().appendingPathExtension("pid.tmp")
        do {
            try data.write(to: tempFile)
            if FileManager.default.fileExists(atPath: pidFile.path) {
                try FileManager.default.removeItem(at: pidFile)
            }
            try FileManager.default.moveItem(at: tempFile, to: pidFile)
        } catch {
            try? await processClient.signalProcess(pid, .terminate)
            try? FileManager.default.removeItem(at: tempFile)
            try? FileManager.default.removeItem(at: pidFile)
            throw error
        }
        return pid
    }

    private static func commandArguments(for kind: AppServerDaemonSpawnRequest.Kind) -> [String] {
        switch kind {
        case .appServer(remoteControlEnabled: true):
            return ["app-server", "--remote-control", "--listen", "unix://"]
        case .appServer(remoteControlEnabled: false):
            return ["app-server", "--listen", "unix://"]
        case .updateLoop:
            return ["app-server", "daemon", "pid-update-loop"]
        }
    }

    private static func waitUntilReady(
        socketPath: String,
        processClient: AppServerDaemonProcessClient,
        options: AppServerDaemonStopOptions
    ) async throws -> String {
        let deadline = Date().addingTimeInterval(options.startTimeout)
        var lastError: Error?
        repeat {
            do {
                return try await processClient.probeAppServerVersion(socketPath)
            } catch {
                lastError = error
                try await processClient.sleep(options.pollInterval)
            }
        } while Date() < deadline
        throw AppServerDaemonLifecycleError(
            "app server did not become ready on \(socketPath): \(lastError?.localizedDescription ?? "probe failed")"
        )
    }

    private static func ensureManagedCodexBin(_ path: URL) throws {
        guard FileManager.default.isExecutableFile(atPath: path.path) || FileManager.default.fileExists(atPath: path.path) else {
            throw AppServerDaemonLifecycleError(
                """
                managed standalone Codex install not found at \(path.path)

                This command requires the standalone install managed by the Codex installer, because the daemon starts and updates app-server from that fixed path.

                Install it with:
                  curl -fsSL https://chatgpt.com/codex/install.sh | sh

                Then rerun the command you just tried.
                """
            )
        }
    }

    private static func loadSettings(path: URL) throws -> AppServerDaemonSettings {
        guard FileManager.default.fileExists(atPath: path.path) else {
            return AppServerDaemonSettings()
        }
        do {
            return try JSONDecoder().decode(AppServerDaemonSettings.self, from: Data(contentsOf: path))
        } catch {
            throw AppServerDaemonLifecycleError("failed to parse daemon settings \(path.path): \(error)")
        }
    }

    private static func saveSettings(_ settings: AppServerDaemonSettings, path: URL) throws {
        try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        let data = try encoder.encode(settings)
        try data.write(to: path)
    }

    private static func recordIsActive(
        _ record: AppServerDaemonPidRecord,
        processClient: AppServerDaemonProcessClient
    ) async throws -> Bool {
        try await processClient.processStartTime(record.pid) == record.processStartTime
    }

    private static func readPidRecord(path: URL) throws -> AppServerDaemonPidRecord? {
        guard FileManager.default.fileExists(atPath: path.path) else {
            return nil
        }
        let data = try Data(contentsOf: path)
        guard !data.allSatisfy({ $0 == UInt8(ascii: " ") || $0 == UInt8(ascii: "\n") || $0 == UInt8(ascii: "\t") }) else {
            try? FileManager.default.removeItem(at: path)
            return nil
        }
        do {
            return try JSONDecoder().decode(AppServerDaemonPidRecord.self, from: data)
        } catch {
            throw AppServerDaemonLifecycleError("invalid pid file contents in \(path.path): \(error)")
        }
    }

    static func readProcessStartTime(pid: UInt32) async throws -> String? {
        guard processExists(pid: pid) else {
            return nil
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-p", String(pid), "-o", "lstart="]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            if processExists(pid: pid) {
                throw AppServerDaemonLifecycleError("failed to read start time for pid-managed app server \(pid)")
            }
            return nil
        }
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if output.isEmpty {
            throw AppServerDaemonLifecycleError("pid-managed app server \(pid) has no recorded start time")
        }
        return output
    }

    static func signalProcess(pid: UInt32, signal: AppServerDaemonSignal) throws {
        let rawSignal: Int32
        switch signal {
        case .terminate:
            rawSignal = SIGTERM
        case .kill:
            rawSignal = SIGKILL
        }
        guard let rawPid = Int32(exactly: pid) else {
            throw AppServerDaemonLifecycleError("pid-managed app server pid \(pid) is out of range")
        }
        let result = Darwin.kill(rawPid, rawSignal)
        if result == 0 || errno == ESRCH {
            return
        }
        throw AppServerDaemonLifecycleError("failed to terminate pid-managed app server \(pid): \(String(cString: strerror(errno)))")
    }

    private static func processExists(pid: UInt32) -> Bool {
        guard let rawPid = Int32(exactly: pid) else {
            return false
        }
        let result = Darwin.kill(rawPid, 0)
        return result == 0 || errno == EPERM
    }

    static func spawnDetached(_ request: AppServerDaemonSpawnRequest) throws -> UInt32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: request.executablePath)
        process.arguments = request.arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        return UInt32(process.processIdentifier)
    }

    static func runStandaloneUpdaterScript(_ script: Data) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-s"]
        let stdin = Pipe()
        process.standardInput = stdin
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            throw AppServerDaemonLifecycleError("failed to invoke standalone Codex updater: \(error)")
        }
        stdin.fileHandleForWriting.write(script)
        stdin.fileHandleForWriting.closeFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw AppServerDaemonLifecycleError(
                "standalone Codex updater exited with status \(process.terminationStatus)"
            )
        }
    }

    static func installTerminationHandler(termination: AppServerDaemonTerminationFlag) {
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .global())
        source.setEventHandler {
            Task {
                await termination.markTerminated()
            }
        }
        source.resume()
        AppServerDaemonSignalSourceStore.shared.retain(source)
    }

    static func sleepOrTerminate(
        _ seconds: TimeInterval,
        termination: AppServerDaemonTerminationFlag,
        processClient: AppServerDaemonProcessClient,
        pollInterval: TimeInterval
    ) async throws -> Bool {
        try await withThrowingTaskGroup(of: Bool.self) { group in
            group.addTask {
                try await processClient.sleep(seconds)
                return false
            }
            group.addTask {
                while await !termination.isTerminated() {
                    try await processClient.sleep(pollInterval)
                }
                return true
            }
            let result = try await group.next() ?? false
            group.cancelAll()
            return result
        }
    }

    static func reexecManagedUpdater(managedCodexBin: URL) throws {
        let arguments = [
            managedCodexBin.path,
            "app-server",
            "daemon",
            "pid-update-loop"
        ]
        let cArguments = arguments.map { strdup($0) } + [nil]
        defer {
            for argument in cArguments {
                free(argument)
            }
        }
        execv(managedCodexBin.path, cArguments)
        throw AppServerDaemonLifecycleError(
            "failed to replace updater with managed Codex binary \(managedCodexBin.path): \(String(cString: strerror(errno)))"
        )
    }

    static func probeAppServerVersion(socketPath: String) async throws -> String {
        try await Task.detached {
            try probeAppServerVersionSynchronously(socketPath: socketPath)
        }.value
    }

    private static func probeAppServerVersionSynchronously(socketPath: String) throws -> String {
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw AppServerDaemonLifecycleError("failed to connect to \(socketPath): \(posixMessage(operation: "socket"))")
        }
        defer { Darwin.close(fd) }
        var timeout = timeval(tv_sec: 2, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        var address = try unixSocketAddress(path: socketPath)
        let connectResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                Darwin.connect(fd, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connectResult == 0 else {
            throw AppServerDaemonLifecycleError("failed to connect to \(socketPath): \(posixMessage(operation: "connect"))")
        }

        let key = Data((0..<16).map { _ in UInt8.random(in: UInt8.min...UInt8.max) }).base64EncodedString()
        let request = """
        GET / HTTP/1.1\r
        Host: localhost\r
        Upgrade: websocket\r
        Connection: Upgrade\r
        Sec-WebSocket-Key: \(key)\r
        Sec-WebSocket-Version: 13\r
        \r

        """
        try writeAll(Data(request.utf8), to: fd, context: "failed to upgrade \(socketPath)")
        let response = try readHTTPHeaders(from: fd, socketPath: socketPath)
        guard response.contains(" 101 ") || response.contains(" 101\r\n") else {
            throw AppServerDaemonLifecycleError("failed to upgrade \(socketPath): \(response.components(separatedBy: "\r\n").first ?? response)")
        }

        let initialize = """
        {"id":1,"method":"initialize","params":{"clientInfo":{"name":"codex_app_server_daemon","title":"Codex App Server Daemon","version":"\(CodexCLI.version)"},"capabilities":null}}
        """
        try writeWebSocketText(initialize, to: fd)
        while true {
            let frame = try readWebSocketFrame(from: fd, socketPath: socketPath)
            guard frame.opcode == 0x1, let text = String(data: frame.payload, encoding: .utf8) else {
                continue
            }
            guard let object = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
                  (object["id"] as? Int) == 1,
                  let result = object["result"] as? [String: Any],
                  let userAgent = result["userAgent"] as? String else {
                continue
            }
            let initialized = #"{"method":"initialized"}"#
            try? writeWebSocketText(initialized, to: fd)
            return try appServerVersion(fromUserAgent: userAgent)
        }
    }

    private static func appServerVersion(fromUserAgent userAgent: String) throws -> String {
        guard let slash = userAgent.firstIndex(of: "/") else {
            throw AppServerDaemonLifecycleError("app-server user-agent omitted version separator")
        }
        let rest = userAgent[userAgent.index(after: slash)...]
        guard let version = rest.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" }).first,
              !version.isEmpty else {
            throw AppServerDaemonLifecycleError("app-server user-agent omitted version")
        }
        return String(version)
    }

    private static func readHTTPHeaders(from fd: Int32, socketPath: String) throws -> String {
        var buffer = Data()
        while !buffer.contains(Data("\r\n\r\n".utf8)) {
            var byte = UInt8.zero
            let count = Darwin.recv(fd, &byte, 1, 0)
            guard count > 0 else {
                throw AppServerDaemonLifecycleError("failed to upgrade \(socketPath): \(posixMessage(operation: "recv"))")
            }
            buffer.append(byte)
            if buffer.count > 16_384 {
                throw AppServerDaemonLifecycleError("failed to upgrade \(socketPath): websocket response headers are too large")
            }
        }
        return String(decoding: buffer, as: UTF8.self)
    }

    private static func writeWebSocketText(_ text: String, to fd: Int32) throws {
        var frame = Data([0x81])
        let payload = Data(text.utf8)
        switch payload.count {
        case 0..<126:
            frame.append(UInt8(0x80 | payload.count))
        case 126...Int(UInt16.max):
            frame.append(0x80 | 126)
            frame.append(UInt8((payload.count >> 8) & 0xff))
            frame.append(UInt8(payload.count & 0xff))
        default:
            frame.append(0x80 | 127)
            for shift in stride(from: 56, through: 0, by: -8) {
                frame.append(UInt8((UInt64(payload.count) >> UInt64(shift)) & 0xff))
            }
        }
        let mask = (0..<4).map { _ in UInt8.random(in: UInt8.min...UInt8.max) }
        frame.append(contentsOf: mask)
        for (index, byte) in payload.enumerated() {
            frame.append(byte ^ mask[index % 4])
        }
        try writeAll(frame, to: fd, context: "failed to send initialize request")
    }

    private static func readWebSocketFrame(from fd: Int32, socketPath: String) throws -> (opcode: UInt8, payload: Data) {
        let header = try readExactly(2, from: fd, socketPath: socketPath)
        let opcode = header[0] & 0x0f
        let masked = (header[1] & 0x80) != 0
        var length = UInt64(header[1] & 0x7f)
        if length == 126 {
            let bytes = try readExactly(2, from: fd, socketPath: socketPath)
            length = (UInt64(bytes[0]) << 8) | UInt64(bytes[1])
        } else if length == 127 {
            let bytes = try readExactly(8, from: fd, socketPath: socketPath)
            length = bytes.reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
        }
        let mask = masked ? try readExactly(4, from: fd, socketPath: socketPath) : Data()
        var payload = try readExactly(Int(length), from: fd, socketPath: socketPath)
        if masked {
            for index in payload.indices {
                payload[index] ^= mask[index % 4]
            }
        }
        if opcode == 0x8 {
            throw AppServerDaemonLifecycleError("app-server closed before initialize response")
        }
        return (opcode, payload)
    }

    private static func readExactly(_ count: Int, from fd: Int32, socketPath: String) throws -> Data {
        var buffer = Data(count: count)
        var offset = 0
        while offset < count {
            let read = buffer.withUnsafeMutableBytes { rawBuffer in
                Darwin.recv(fd, rawBuffer.baseAddress!.advanced(by: offset), count - offset, 0)
            }
            guard read > 0 else {
                throw AppServerDaemonLifecycleError("failed to read from \(socketPath): \(posixMessage(operation: "recv"))")
            }
            offset += read
        }
        return buffer
    }

    private static func writeAll(_ data: Data, to fd: Int32, context: String) throws {
        try data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else {
                return
            }
            var written = 0
            while written < data.count {
                let count = Darwin.send(fd, baseAddress.advanced(by: written), data.count - written, 0)
                guard count > 0 else {
                    throw AppServerDaemonLifecycleError("\(context): \(posixMessage(operation: "send"))")
                }
                written += count
            }
        }
    }

    private static func unixSocketAddress(path: String) throws -> sockaddr_un {
        let pathBytes = Array(path.utf8)
        guard pathBytes.count < MemoryLayout.size(ofValue: sockaddr_un().sun_path) else {
            throw AppServerDaemonLifecycleError("socket path is too long: \(path)")
        }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { rawBuffer in
            rawBuffer.copyBytes(from: pathBytes)
            rawBuffer[pathBytes.count] = 0
        }
        return address
    }

    private static func posixMessage(operation: String) -> String {
        "\(operation): \(String(cString: strerror(errno)))"
    }
}

private struct AppServerDaemonPaths {
    let stateDirectory: URL
    let pidFile: URL
    let updatePidFile: URL
    let operationLockFile: URL
    let settingsFile: URL
    let managedCodexBin: URL
    let socketPath: String

    init(codexHome: URL) {
        stateDirectory = codexHome.appendingPathComponent("app-server-daemon", isDirectory: true)
        pidFile = stateDirectory.appendingPathComponent("app-server.pid", isDirectory: false)
        updatePidFile = stateDirectory.appendingPathComponent("app-server-updater.pid", isDirectory: false)
        operationLockFile = stateDirectory.appendingPathComponent("daemon.lock", isDirectory: false)
        settingsFile = stateDirectory.appendingPathComponent("settings.json", isDirectory: false)
        managedCodexBin = codexHome
            .appendingPathComponent("packages", isDirectory: true)
            .appendingPathComponent("standalone", isDirectory: true)
            .appendingPathComponent("current", isDirectory: true)
            .appendingPathComponent("codex", isDirectory: false)
        socketPath = codexHome
            .appendingPathComponent("app-server-control", isDirectory: true)
            .appendingPathComponent("app-server-control.sock", isDirectory: false)
            .path
    }
}

private struct AppServerDaemonPidRecord: Codable, Equatable {
    let pid: UInt32
    let processStartTime: String
}

private struct AppServerDaemonSettings: Codable, Equatable {
    var remoteControlEnabled: Bool = false
}

public actor AppServerDaemonTerminationFlag {
    private var terminated = false

    public init() {}

    public func markTerminated() {
        terminated = true
    }

    public func isTerminated() -> Bool {
        terminated
    }
}

private final class AppServerDaemonSignalSourceStore: @unchecked Sendable {
    static let shared = AppServerDaemonSignalSourceStore()

    private let lock = NSLock()
    private var sources: [DispatchSourceSignal] = []

    func retain(_ source: DispatchSourceSignal) {
        lock.lock()
        sources.append(source)
        lock.unlock()
    }
}

private extension URL {
    func deletingLastPathComponentIfPresent() -> URL? {
        let parent = deletingLastPathComponent()
        return parent.path == path ? nil : parent
    }
}

private final class AppServerDaemonOperationLock {
    private let descriptor: Int32

    private init(descriptor: Int32) {
        self.descriptor = descriptor
    }

    static func acquire(
        path: URL,
        timeout: TimeInterval,
        pollInterval: TimeInterval,
        sleep: @Sendable (TimeInterval) async throws -> Void
    ) async throws -> AppServerDaemonOperationLock {
        let descriptor = Darwin.open(path.path, O_CREAT | O_RDWR, 0o600)
        guard descriptor >= 0 else {
            throw AppServerDaemonLifecycleError("failed to open daemon operation lock \(path.path): \(String(cString: strerror(errno)))")
        }
        let lock = AppServerDaemonOperationLock(descriptor: descriptor)
        let deadline = Date().addingTimeInterval(timeout)
        while flock(descriptor, LOCK_EX | LOCK_NB) != 0 {
            if errno != EWOULDBLOCK {
                let message = String(cString: strerror(errno))
                lock.close()
                throw AppServerDaemonLifecycleError("failed to lock daemon operation lock \(path.path): \(message)")
            }
            if Date() >= deadline {
                lock.close()
                throw AppServerDaemonLifecycleError("timed out waiting for daemon operation lock \(path.path)")
            }
            try await sleep(pollInterval)
        }
        return lock
    }

    static func tryAcquire(path: URL) throws -> AppServerDaemonOperationLock? {
        let descriptor = Darwin.open(path.path, O_CREAT | O_RDWR, 0o600)
        guard descriptor >= 0 else {
            throw AppServerDaemonLifecycleError("failed to open daemon operation lock \(path.path): \(String(cString: strerror(errno)))")
        }
        let lock = AppServerDaemonOperationLock(descriptor: descriptor)
        if flock(descriptor, LOCK_EX | LOCK_NB) == 0 {
            return lock
        }
        if errno == EWOULDBLOCK {
            lock.close()
            return nil
        }
        let message = String(cString: strerror(errno))
        lock.close()
        throw AppServerDaemonLifecycleError("failed to lock daemon operation lock \(path.path): \(message)")
    }

    func close() {
        _ = flock(descriptor, LOCK_UN)
        _ = Darwin.close(descriptor)
    }
}

public struct AppServerDaemonLifecycleError: Error, CustomStringConvertible, Sendable {
    public let description: String

    public init(_ description: String) {
        self.description = description
    }
}
