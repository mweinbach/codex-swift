import Foundation

public enum ProviderAuthCommandError: Error, Equatable, CustomStringConvertible, Sendable {
    case timedOut(command: String, timeoutMilliseconds: UInt64)
    case failedToStart(command: String, message: String)
    case exited(command: String, status: String, stderr: String)
    case nonUTF8Stdout(command: String)
    case emptyToken(command: String)

    public var description: String {
        switch self {
        case let .timedOut(command, timeoutMilliseconds):
            return "provider auth command `\(command)` timed out after \(timeoutMilliseconds) ms"
        case let .failedToStart(command, message):
            return "provider auth command `\(command)` failed to start: \(message)"
        case let .exited(command, status, stderr):
            let stderrSuffix = stderr.isEmpty ? "" : ": \(stderr)"
            return "provider auth command `\(command)` exited with status \(status)\(stderrSuffix)"
        case let .nonUTF8Stdout(command):
            return "provider auth command `\(command)` wrote non-UTF-8 data to stdout"
        case let .emptyToken(command):
            return "provider auth command `\(command)` produced an empty token"
        }
    }
}

public actor ProviderAuthCommandRunner {
    private struct CachedToken: Sendable {
        let accessToken: String
        let fetchedAt: Date
    }

    private var cachedTokens: [ModelProviderAuthInfo: CachedToken] = [:]
    private var inFlightTokenFetches: [ModelProviderAuthInfo: Task<String, Error>] = [:]
    private let now: @Sendable () -> Date

    public init(now: @escaping @Sendable () -> Date = Date.init) {
        self.now = now
    }

    public func resolveToken(config: ModelProviderAuthInfo) async throws -> String {
        if let cached = cachedTokens[config] {
            if let refreshInterval = config.refreshIntervalMS {
                if now().timeIntervalSince(cached.fetchedAt) < TimeInterval(refreshInterval) / 1_000 {
                    return cached.accessToken
                }
            } else {
                return cached.accessToken
            }
        }

        if let inFlight = inFlightTokenFetches[config] {
            return try await inFlight.value
        }

        let inFlight = Task<String, Error> {
            try await Self.runProviderAuthCommand(config)
        }
        inFlightTokenFetches[config] = inFlight
        let token: String
        do {
            token = try await inFlight.value
        } catch {
            inFlightTokenFetches[config] = nil
            throw error
        }
        inFlightTokenFetches[config] = nil
        cachedTokens[config] = CachedToken(accessToken: token, fetchedAt: now())
        return token
    }

    public func refreshToken(config: ModelProviderAuthInfo) async throws -> String {
        let token = try await Self.runProviderAuthCommand(config)
        cachedTokens[config] = CachedToken(accessToken: token, fetchedAt: now())
        return token
    }

    public static func runProviderAuthCommand(_ config: ModelProviderAuthInfo) async throws -> String {
        let process = Process()
        let program = resolveProviderAuthProgram(config.command, cwd: config.cwd)
        if program.isBareCommand {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [program.path] + config.args
        } else {
            process.executableURL = URL(fileURLWithPath: program.path)
            process.arguments = config.args
        }
        process.currentDirectoryURL = URL(fileURLWithPath: config.cwd.path, isDirectory: true)

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        process.standardInput = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            throw ProviderAuthCommandError.failedToStart(
                command: config.command,
                message: String(describing: error)
            )
        }

        let timedOut = await waitForExit(process, timeoutMilliseconds: config.timeoutMilliseconds)
        if timedOut {
            process.terminate()
            throw ProviderAuthCommandError.timedOut(
                command: config.command,
                timeoutMilliseconds: config.timeoutMilliseconds
            )
        }

        let stdoutData = stdout.fileHandleForReading.readDataToEndOfFile()
        let stderrText = String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard process.terminationStatus == 0 else {
            throw ProviderAuthCommandError.exited(
                command: config.command,
                status: "exit status: \(process.terminationStatus)",
                stderr: stderrText
            )
        }

        guard let stdoutText = String(data: stdoutData, encoding: .utf8) else {
            throw ProviderAuthCommandError.nonUTF8Stdout(command: config.command)
        }
        let token = stdoutText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            throw ProviderAuthCommandError.emptyToken(command: config.command)
        }
        return token
    }

    private static func waitForExit(_ process: Process, timeoutMilliseconds: UInt64) async -> Bool {
        await withCheckedContinuation { continuation in
            let state = ProcessWaitState(process: process, continuation: continuation)

            process.terminationHandler = { _ in
                state.resume(timedOut: false)
            }

            DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(Int(timeoutMilliseconds))) {
                state.terminateAndResumeTimedOut()
            }
        }
    }

    private static func resolveProviderAuthProgram(_ command: String, cwd: AbsolutePath) -> (path: String, isBareCommand: Bool) {
        if command.hasPrefix("/") {
            return (command, false)
        }
        if command.contains("/") {
            return ((cwd.path as NSString).appendingPathComponent(command), false)
        }
        return (command, true)
    }
}

// Foundation invokes process termination handlers from concurrent contexts; this
// wrapper keeps the non-Sendable Process and continuation behind a single lock.
private final class ProcessWaitState: @unchecked Sendable {
    private let lock = NSLock()
    private var didResume = false
    private let process: Process
    private let continuation: CheckedContinuation<Bool, Never>

    init(process: Process, continuation: CheckedContinuation<Bool, Never>) {
        self.process = process
        self.continuation = continuation
    }

    func resume(timedOut: Bool) {
        lock.lock()
        defer { lock.unlock() }
        guard !didResume else {
            return
        }
        didResume = true
        process.terminationHandler = nil
        continuation.resume(returning: timedOut)
    }

    func terminateAndResumeTimedOut() {
        lock.lock()
        let shouldTerminate = !didResume
        lock.unlock()

        guard shouldTerminate else {
            return
        }
        process.terminate()
        resume(timedOut: true)
    }
}
