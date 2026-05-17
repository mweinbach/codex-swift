import CodexCLI
import Foundation
import XCTest

final class AppServerDaemonLifecycleTests: XCTestCase {
    func testStopReturnsRustNotRunningOutputWhenPidFileIsMissing() async throws {
        let temp = try AppServerDaemonTemporaryDirectory()

        let output = try await AppServerDaemonLifecycle.stop(
            codexHome: temp.url,
            cliVersion: "1.2.3",
            processClient: .testClient(),
            options: .test
        )

        XCTAssertEqual(output, AppServerDaemonLifecycleOutput(
            status: .notRunning,
            backend: nil,
            pid: nil,
            socketPath: temp.url
                .appendingPathComponent("app-server-control", isDirectory: true)
                .appendingPathComponent("app-server-control.sock", isDirectory: false)
                .path,
            cliVersion: "1.2.3",
            appServerVersion: nil
        ))
        XCTAssertEqual(
            try AppServerDaemonLifecycle.encodeOutput(output),
            #"{"status":"notRunning","socketPath":"\#(temp.url.path)/app-server-control/app-server-control.sock","cliVersion":"1.2.3"}"#
        )
    }

    func testStopRemovesStalePidRecordLikeRustAndReportsNotRunning() async throws {
        let temp = try AppServerDaemonTemporaryDirectory()
        try temp.writePidRecord(pid: 1234, processStartTime: "old-start")

        let output = try await AppServerDaemonLifecycle.stop(
            codexHome: temp.url,
            cliVersion: "1.2.3",
            processClient: .testClient(startTimes: [1234: "new-start"]),
            options: .test
        )

        XCTAssertEqual(output.status, .notRunning)
        XCTAssertFalse(FileManager.default.fileExists(atPath: temp.pidFile.path))
    }

    func testStopSignalsRunningPidAndReportsStoppedLikeRust() async throws {
        let temp = try AppServerDaemonTemporaryDirectory()
        try temp.writePidRecord(pid: 1234, processStartTime: "start")
        let fakeProcess = AppServerDaemonFakeProcess(startTimes: [1234: "start"])

        let output = try await AppServerDaemonLifecycle.stop(
            codexHome: temp.url,
            cliVersion: "1.2.3",
            processClient: fakeProcess.client(),
            options: .test
        )

        XCTAssertEqual(output.status, .stopped)
        XCTAssertEqual(output.backend, .pid)
        let signals = await fakeProcess.signalsSnapshot()
        XCTAssertEqual(signals, [.terminate])
        XCTAssertFalse(FileManager.default.fileExists(atPath: temp.pidFile.path))
        XCTAssertEqual(
            try AppServerDaemonLifecycle.encodeOutput(output),
            #"{"status":"stopped","backend":"pid","socketPath":"\#(temp.url.path)/app-server-control/app-server-control.sock","cliVersion":"1.2.3"}"#
        )
    }

    func testStopEscalatesToKillAfterGracePeriodLikeRust() async throws {
        let temp = try AppServerDaemonTemporaryDirectory()
        try temp.writePidRecord(pid: 1234, processStartTime: "start")
        let fakeProcess = AppServerDaemonFakeProcess(
            startTimes: [1234: "start"],
            terminateRemovesProcess: false,
            killRemovesProcess: true
        )

        let output = try await AppServerDaemonLifecycle.stop(
            codexHome: temp.url,
            cliVersion: "1.2.3",
            processClient: fakeProcess.client(),
            options: AppServerDaemonStopOptions(
                pollInterval: 0.001,
                gracePeriod: 0,
                timeout: 0.1,
                operationLockTimeout: 0.1
            )
        )

        XCTAssertEqual(output.status, .stopped)
        let signals = await fakeProcess.signalsSnapshot()
        XCTAssertEqual(signals, [.terminate, .kill])
    }
}

private extension AppServerDaemonProcessClient {
    static func testClient(startTimes: [UInt32: String?] = [:]) -> AppServerDaemonProcessClient {
        AppServerDaemonProcessClient(
            processStartTime: { pid in startTimes[pid] ?? nil },
            signalProcess: { _, _ in },
            sleep: { _ in }
        )
    }
}

private extension AppServerDaemonStopOptions {
    static let test = AppServerDaemonStopOptions(
        pollInterval: 0.001,
        gracePeriod: 0.01,
        timeout: 0.1,
        operationLockTimeout: 0.1
    )
}

private final class AppServerDaemonTemporaryDirectory {
    let url: URL

    var pidFile: URL {
        url
            .appendingPathComponent("app-server-daemon", isDirectory: true)
            .appendingPathComponent("app-server.pid", isDirectory: false)
    }

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-daemon-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    func writePidRecord(pid: UInt32, processStartTime: String) throws {
        let stateDir = pidFile.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: stateDir, withIntermediateDirectories: true)
        let data = #"{"pid":\#(pid),"processStartTime":"\#(processStartTime)"}"#.data(using: .utf8)!
        try data.write(to: pidFile)
    }
}

private actor AppServerDaemonFakeProcess {
    private var startTimes: [UInt32: String]
    private let terminateRemovesProcess: Bool
    private let killRemovesProcess: Bool
    private(set) var signals: [AppServerDaemonSignal] = []

    init(
        startTimes: [UInt32: String],
        terminateRemovesProcess: Bool = true,
        killRemovesProcess: Bool = true
    ) {
        self.startTimes = startTimes
        self.terminateRemovesProcess = terminateRemovesProcess
        self.killRemovesProcess = killRemovesProcess
    }

    func client() -> AppServerDaemonProcessClient {
        AppServerDaemonProcessClient(
            processStartTime: { [weak self] pid in
                guard let self else { return nil }
                return await self.startTimes[pid]
            },
            signalProcess: { [weak self] pid, signal in
                guard let self else { return }
                await self.recordSignal(signal, pid: pid)
            },
            sleep: { _ in }
        )
    }

    func signalsSnapshot() -> [AppServerDaemonSignal] {
        signals
    }

    private func recordSignal(_ signal: AppServerDaemonSignal, pid: UInt32) {
        signals.append(signal)
        switch signal {
        case .terminate where terminateRemovesProcess:
            startTimes.removeValue(forKey: pid)
        case .kill where killRemovesProcess:
            startTimes.removeValue(forKey: pid)
        default:
            break
        }
    }
}
