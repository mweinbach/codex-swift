import Darwin
import Foundation

public enum AppServerDaemonBackendKind: String, Codable, Sendable {
    case pid
}

public enum AppServerDaemonLifecycleStatus: String, Codable, Sendable {
    case stopped
    case notRunning
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

public enum AppServerDaemonSignal: Equatable, Sendable {
    case terminate
    case kill
}

public struct AppServerDaemonProcessClient: Sendable {
    public var processStartTime: @Sendable (UInt32) async throws -> String?
    public var signalProcess: @Sendable (UInt32, AppServerDaemonSignal) async throws -> Void
    public var sleep: @Sendable (TimeInterval) async throws -> Void

    public init(
        processStartTime: @escaping @Sendable (UInt32) async throws -> String?,
        signalProcess: @escaping @Sendable (UInt32, AppServerDaemonSignal) async throws -> Void,
        sleep: @escaping @Sendable (TimeInterval) async throws -> Void
    ) {
        self.processStartTime = processStartTime
        self.signalProcess = signalProcess
        self.sleep = sleep
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
        }
    )
}

public struct AppServerDaemonStopOptions: Sendable {
    public let pollInterval: TimeInterval
    public let gracePeriod: TimeInterval
    public let timeout: TimeInterval
    public let operationLockTimeout: TimeInterval

    public init(
        pollInterval: TimeInterval = 0.05,
        gracePeriod: TimeInterval = 60,
        timeout: TimeInterval = 70,
        operationLockTimeout: TimeInterval = 75
    ) {
        self.pollInterval = pollInterval
        self.gracePeriod = gracePeriod
        self.timeout = timeout
        self.operationLockTimeout = operationLockTimeout
    }
}

public enum AppServerDaemonLifecycle {
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
        cliVersion: String
    ) -> AppServerDaemonLifecycleOutput {
        AppServerDaemonLifecycleOutput(
            status: status,
            backend: backend,
            pid: nil,
            socketPath: socketPath,
            cliVersion: cliVersion,
            appServerVersion: nil
        )
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
}

private struct AppServerDaemonPaths {
    let stateDirectory: URL
    let pidFile: URL
    let operationLockFile: URL
    let socketPath: String

    init(codexHome: URL) {
        stateDirectory = codexHome.appendingPathComponent("app-server-daemon", isDirectory: true)
        pidFile = stateDirectory.appendingPathComponent("app-server.pid", isDirectory: false)
        operationLockFile = stateDirectory.appendingPathComponent("daemon.lock", isDirectory: false)
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
