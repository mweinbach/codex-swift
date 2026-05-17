import Foundation

public struct ConfiguredHookHandler: Equatable, Sendable {
    public var eventName: HookEventName
    public var matcher: String?
    public var command: String
    public var timeoutSec: UInt64
    public var statusMessage: String?
    public var sourcePath: AbsolutePath
    public var source: HookSource
    public var displayOrder: Int64
    public var environment: [String: String]

    public init(
        eventName: HookEventName,
        matcher: String?,
        command: String,
        timeoutSec: UInt64,
        statusMessage: String? = nil,
        sourcePath: AbsolutePath,
        source: HookSource = .user,
        displayOrder: Int64,
        environment: [String: String] = [:]
    ) {
        self.eventName = eventName
        self.matcher = matcher
        self.command = command
        self.timeoutSec = timeoutSec
        self.statusMessage = statusMessage
        self.sourcePath = sourcePath
        self.source = source
        self.displayOrder = displayOrder
        self.environment = environment
    }

    public var runID: String {
        "\(eventName.hookRunLabel):\(displayOrder):\(sourcePath.path)"
    }
}

public struct HookCommandRunResult: Equatable, Sendable {
    public var startedAt: Int64
    public var completedAt: Int64
    public var durationMs: Int64
    public var exitCode: Int32?
    public var stdout: String
    public var stderr: String
    public var error: String?

    public init(
        startedAt: Int64,
        completedAt: Int64,
        durationMs: Int64,
        exitCode: Int32? = nil,
        stdout: String = "",
        stderr: String = "",
        error: String? = nil
    ) {
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.durationMs = durationMs
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
        self.error = error
    }
}

public struct HookCommandShell: Equatable, Sendable {
    public var program: String
    public var arguments: [String]

    public init(program: String = "", arguments: [String] = []) {
        self.program = program
        self.arguments = arguments
    }
}

public enum HookCommandRunner {
    public static func runCommand(
        shell: HookCommandShell,
        handler: ConfiguredHookHandler,
        inputJSON: String,
        cwd: URL,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) async -> HookCommandRunResult {
        let startedAt = currentUnixTimestamp()
        let started = DispatchTime.now()
        let process = Process()
        let command = buildCommand(shell: shell, handler: handler, environment: environment)
        process.executableURL = URL(fileURLWithPath: command.program)
        process.arguments = command.arguments
        process.currentDirectoryURL = cwd
        process.environment = command.environment

        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            return HookCommandRunResult(
                startedAt: startedAt,
                completedAt: currentUnixTimestamp(),
                durationMs: elapsedMilliseconds(since: started),
                error: String(describing: error)
            )
        }

        let stdoutTask = Task.detached {
            stdout.fileHandleForReading.readDataToEndOfFile()
        }
        let stderrTask = Task.detached {
            stderr.fileHandleForReading.readDataToEndOfFile()
        }

        do {
            try stdin.fileHandleForWriting.write(contentsOf: Data(inputJSON.utf8))
            try stdin.fileHandleForWriting.close()
        } catch {
            process.terminate()
            _ = await waitForExitOrTimeout(process: process, timeoutSec: 1)
            stdoutTask.cancel()
            stderrTask.cancel()
            return HookCommandRunResult(
                startedAt: startedAt,
                completedAt: currentUnixTimestamp(),
                durationMs: elapsedMilliseconds(since: started),
                error: "failed to write hook stdin: \(error)"
            )
        }

        let timedOut = await waitForExitOrTimeout(process: process, timeoutSec: handler.timeoutSec)
        let stdoutData = await stdoutTask.value
        let stderrData = await stderrTask.value

        if timedOut {
            return HookCommandRunResult(
                startedAt: startedAt,
                completedAt: currentUnixTimestamp(),
                durationMs: elapsedMilliseconds(since: started),
                stdout: "",
                stderr: "",
                error: "hook timed out after \(handler.timeoutSec)s"
            )
        }

        return HookCommandRunResult(
            startedAt: startedAt,
            completedAt: currentUnixTimestamp(),
            durationMs: elapsedMilliseconds(since: started),
            exitCode: process.terminationStatus,
            stdout: String(decoding: stdoutData, as: UTF8.self),
            stderr: String(decoding: stderrData, as: UTF8.self),
            error: nil
        )
    }

    public static func buildCommand(
        shell: HookCommandShell,
        handler: ConfiguredHookHandler,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> (program: String, arguments: [String], environment: [String: String]) {
        var mergedEnvironment = environment
        for (key, value) in handler.environment {
            mergedEnvironment[key] = value
        }

        if shell.program.isEmpty {
            #if os(Windows)
            let program = environment["COMSPEC"] ?? "cmd.exe"
            return (program, ["/C", handler.command], mergedEnvironment)
            #else
            let program = environment["SHELL"] ?? "/bin/sh"
            return (program, ["-lc", handler.command], mergedEnvironment)
            #endif
        }

        return (shell.program, shell.arguments + [handler.command], mergedEnvironment)
    }

    private static func waitForExitOrTimeout(process: Process, timeoutSec: UInt64) async -> Bool {
        await withCheckedContinuation { continuation in
            let state = HookProcessWaitState(continuation: continuation)

            process.terminationHandler = { _ in
                state.resume(timedOut: false)
            }

            if !process.isRunning {
                state.resume(timedOut: false)
                return
            }

            Task.detached {
                try? await Task.sleep(nanoseconds: timeoutSec.saturatingNanoseconds)
                guard let continuation = state.claim() else {
                    return
                }
                if process.isRunning {
                    process.terminate()
                }
                continuation.resume(returning: true)
            }
        }
    }

    private static func currentUnixTimestamp() -> Int64 {
        Int64(Date().timeIntervalSince1970)
    }

    private static func elapsedMilliseconds(since started: DispatchTime) -> Int64 {
        let elapsed = DispatchTime.now().uptimeNanoseconds - started.uptimeNanoseconds
        return Int64(min(elapsed / 1_000_000, UInt64(Int64.max)))
    }
}

private extension UInt64 {
    var saturatingNanoseconds: UInt64 {
        let (value, overflow) = multipliedReportingOverflow(by: 1_000_000_000)
        return overflow ? UInt64.max : value
    }
}

private final class HookProcessWaitState: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Bool, Never>?

    init(continuation: CheckedContinuation<Bool, Never>) {
        self.continuation = continuation
    }

    func resume(timedOut: Bool) {
        claim()?.resume(returning: timedOut)
    }

    func claim() -> CheckedContinuation<Bool, Never>? {
        lock.withLock {
            let continuation = self.continuation
            self.continuation = nil
            return continuation
        }
    }
}

public enum HookDispatcher {
    public static func executeHandlers<Data: Equatable & Sendable>(
        handlers: [ConfiguredHookHandler],
        shell: HookCommandShell,
        inputJSON: String,
        cwd: URL,
        parse: @escaping @Sendable (ConfiguredHookHandler, HookCommandRunResult) -> ParsedHookHandler<Data>
    ) async -> [ParsedHookHandler<Data>] {
        let cwdPath = cwd.path
        let indexedParsed = await withTaskGroup(of: (Int, ParsedHookHandler<Data>).self) { group in
            for (index, handler) in handlers.enumerated() {
                group.addTask {
                    let result = await HookCommandRunner.runCommand(
                        shell: shell,
                        handler: handler,
                        inputJSON: inputJSON,
                        cwd: URL(fileURLWithPath: cwdPath)
                    )
                    return (index, parse(handler, result))
                }
            }

            var parsed: [(Int, ParsedHookHandler<Data>)] = []
            var completionOrder = 0
            for await var value in group {
                value.1.completionOrder = completionOrder
                completionOrder += 1
                parsed.append(value)
            }
            return parsed
        }

        return indexedParsed
            .sorted { $0.0 < $1.0 }
            .map { $0.1 }
    }

    public static func matcherPattern(for eventName: HookEventName, matcher: String?) -> String? {
        switch eventName {
        case .preToolUse, .permissionRequest, .postToolUse, .preCompact, .postCompact, .sessionStart:
            return matcher
        case .userPromptSubmit, .stop:
            return nil
        }
    }

    public static func validateMatcherPattern(_ matcher: String) -> Bool {
        if isMatchAllMatcher(matcher) || isExactMatcher(matcher) {
            return true
        }
        return (try? NSRegularExpression(pattern: matcher)) != nil
    }

    public static func matchesMatcher(_ matcher: String?, input: String?) -> Bool {
        guard let matcher else {
            return true
        }
        if isMatchAllMatcher(matcher) {
            return true
        }
        guard let input else {
            return false
        }
        if isExactMatcher(matcher) {
            return matcher.split(separator: "|").contains { $0 == input }
        }
        guard let regex = try? NSRegularExpression(pattern: matcher) else {
            return false
        }
        let range = NSRange(input.startIndex..<input.endIndex, in: input)
        return regex.firstMatch(in: input, range: range) != nil
    }

    public static func matcherInputs(toolName: String, matcherAliases: [String]) -> [String] {
        [toolName] + matcherAliases
    }

    public static func selectHandlers(
        _ handlers: [ConfiguredHookHandler],
        eventName: HookEventName,
        matcherInput: String?
    ) -> [ConfiguredHookHandler] {
        selectHandlers(handlers, eventName: eventName, matcherInputs: matcherInput.map { [$0] } ?? [])
    }

    public static func selectHandlers(
        _ handlers: [ConfiguredHookHandler],
        eventName: HookEventName,
        matcherInputs: [String]
    ) -> [ConfiguredHookHandler] {
        handlers.filter { handler in
            guard handler.eventName == eventName else {
                return false
            }

            switch eventName {
            case .preToolUse, .permissionRequest, .postToolUse, .preCompact, .postCompact, .sessionStart:
                if matcherInputs.isEmpty {
                    return matchesMatcher(handler.matcher, input: nil)
                }
                return matcherInputs.contains { matchesMatcher(handler.matcher, input: $0) }
            case .userPromptSubmit, .stop:
                return true
            }
        }
    }

    public static func runningSummary(
        handler: ConfiguredHookHandler,
        startedAt: Int64 = Int64(Date().timeIntervalSince1970)
    ) -> HookRunSummary {
        HookRunSummary(
            id: handler.runID,
            eventName: handler.eventName,
            handlerType: .command,
            executionMode: .sync,
            scope: scope(for: handler.eventName),
            sourcePath: handler.sourcePath,
            source: handler.source,
            displayOrder: handler.displayOrder,
            status: .running,
            statusMessage: handler.statusMessage,
            startedAt: startedAt,
            completedAt: nil,
            durationMs: nil,
            entries: []
        )
    }

    public static func completedSummary(
        handler: ConfiguredHookHandler,
        runResult: HookCommandRunResult,
        status: HookRunStatus,
        entries: [HookOutputEntry]
    ) -> HookRunSummary {
        HookRunSummary(
            id: handler.runID,
            eventName: handler.eventName,
            handlerType: .command,
            executionMode: .sync,
            scope: scope(for: handler.eventName),
            sourcePath: handler.sourcePath,
            source: handler.source,
            displayOrder: handler.displayOrder,
            status: status,
            statusMessage: handler.statusMessage,
            startedAt: runResult.startedAt,
            completedAt: runResult.completedAt,
            durationMs: runResult.durationMs,
            entries: entries
        )
    }

    public static func scope(for eventName: HookEventName) -> HookScope {
        switch eventName {
        case .sessionStart:
            return .thread
        case .preToolUse, .permissionRequest, .postToolUse, .preCompact, .postCompact, .userPromptSubmit, .stop:
            return .turn
        }
    }

    private static func isMatchAllMatcher(_ matcher: String) -> Bool {
        matcher.isEmpty || matcher == "*"
    }

    private static func isExactMatcher(_ matcher: String) -> Bool {
        matcher.unicodeScalars.allSatisfy { scalar in
            (scalar.value >= 48 && scalar.value <= 57)
                || (scalar.value >= 65 && scalar.value <= 90)
                || (scalar.value >= 97 && scalar.value <= 122)
                || scalar == "_"
                || scalar == "|"
        }
    }
}

extension HookEventName {
    public var hookRunLabel: String {
        switch self {
        case .preToolUse: return "pre-tool-use"
        case .permissionRequest: return "permission-request"
        case .postToolUse: return "post-tool-use"
        case .preCompact: return "pre-compact"
        case .postCompact: return "post-compact"
        case .sessionStart: return "session-start"
        case .userPromptSubmit: return "user-prompt-submit"
        case .stop: return "stop"
        }
    }
}
