import CodexCLI
import Foundation
import XCTest

final class AppServerDaemonLifecycleTests: XCTestCase {
    func testUpdaterIdentityUsesRustSHA256Digest() {
        let identity = AppServerDaemonExecutableIdentity(bytes: Data("same".utf8))

        XCTAssertEqual(
            identity.digestHex,
            "0967115f2813a3541eaef77de9d9d5773f1c0c04314b0bbfe4ff3b3b1c55b5d5"
        )
    }

    func testUpdateModesForIdentitiesMatchRust() {
        let current = AppServerDaemonExecutableIdentity(bytes: Data("same".utf8))
        let sameManaged = AppServerDaemonExecutableIdentity(bytes: Data("same".utf8))
        let changedManaged = AppServerDaemonExecutableIdentity(bytes: Data("managed".utf8))

        XCTAssertEqual(
            AppServerDaemonLifecycle.updateModesForIdentities(currentUpdater: current, managedCodex: sameManaged),
            AppServerDaemonUpdateModes(restartMode: .ifVersionChanged, updaterRefreshMode: .none)
        )
        XCTAssertEqual(
            AppServerDaemonLifecycle.updateModesForIdentities(currentUpdater: current, managedCodex: changedManaged),
            AppServerDaemonUpdateModes(
                restartMode: .always,
                updaterRefreshMode: .reexecIfManagedBinaryChanged
            )
        )
    }

    func testRestartDecisionMatchesRust() {
        XCTAssertEqual(
            AppServerDaemonLifecycle.restartDecision(
                mode: .ifVersionChanged,
                appServerVersion: nil,
                managedVersion: "1.2.3"
            ),
            .notReady
        )
        XCTAssertEqual(
            AppServerDaemonLifecycle.restartDecision(
                mode: .ifVersionChanged,
                appServerVersion: "1.2.3",
                managedVersion: "1.2.3"
            ),
            .alreadyCurrent
        )
        XCTAssertEqual(
            AppServerDaemonLifecycle.restartDecision(
                mode: .ifVersionChanged,
                appServerVersion: "1.2.2",
                managedVersion: "1.2.3"
            ),
            .restart
        )
        XCTAssertEqual(
            AppServerDaemonLifecycle.restartDecision(
                mode: .always,
                appServerVersion: "1.2.3",
                managedVersion: "1.2.3"
            ),
            .restart
        )
    }

    func testShouldReexecUpdaterMatchesRust() {
        XCTAssertFalse(AppServerDaemonLifecycle.shouldReexecUpdater(
            refreshMode: .none,
            outcome: .restarted
        ))
        XCTAssertFalse(AppServerDaemonLifecycle.shouldReexecUpdater(
            refreshMode: .reexecIfManagedBinaryChanged,
            outcome: .alreadyCurrent
        ))
        XCTAssertTrue(AppServerDaemonLifecycle.shouldReexecUpdater(
            refreshMode: .reexecIfManagedBinaryChanged,
            outcome: .restarted
        ))
    }

    func testRemoteControlStartFailsWithRustManagedInstallGuidanceWhenMissing() async throws {
        let temp = try AppServerDaemonTemporaryDirectory()

        do {
            _ = try await AppServerDaemonLifecycle.ensureRemoteControlStarted(
                codexHome: temp.url,
                cliVersion: "1.2.3",
                processClient: .testClient(),
                options: .test
            )
            XCTFail("Expected missing managed install to fail")
        } catch let error as AppServerDaemonLifecycleError {
            XCTAssertTrue(error.description.contains("managed standalone Codex install not found at \(temp.managedCodexBin.path)"))
            XCTAssertTrue(error.description.contains("curl -fsSL https://chatgpt.com/codex/install.sh | sh"))
        }
    }

    func testRemoteControlStartBootstrapsAppServerAndUpdaterLikeRust() async throws {
        let temp = try AppServerDaemonTemporaryDirectory()
        try temp.createManagedCodexBin()
        let fakeProcess = AppServerDaemonFakeProcess(
            startTimes: [:],
            spawnedStartTimes: [2001: "app-start", 2002: "updater-start"],
            probeResults: [.failure(AppServerDaemonLifecycleError("not ready")), .success("1.2.4")]
        )

        let output = try await AppServerDaemonLifecycle.ensureRemoteControlStarted(
            codexHome: temp.url,
            cliVersion: "1.2.3",
            processClient: fakeProcess.client(),
            options: .test
        )

        guard case let .bootstrap(bootstrap) = output else {
            return XCTFail("Expected bootstrap output")
        }
        XCTAssertEqual(bootstrap, AppServerDaemonBootstrapOutput(
            status: .bootstrapped,
            backend: .pid,
            autoUpdateEnabled: true,
            remoteControlEnabled: true,
            managedCodexPath: temp.managedCodexBin.path,
            socketPath: temp.socketPath.path,
            cliVersion: "1.2.3",
            appServerVersion: "1.2.4"
        ))
        XCTAssertEqual(try temp.settingsJSON(), #"{"remoteControlEnabled":true}"#)
        let spawns = await fakeProcess.spawnsSnapshot()
        XCTAssertEqual(spawns.map(\.arguments), [
            ["app-server", "--remote-control", "--listen", "unix://"],
            ["app-server", "daemon", "pid-update-loop"]
        ])
        XCTAssertEqual(
            try AppServerDaemonLifecycle.encodeRemoteControlStartOutput(output),
            #"{"status":"bootstrapped","backend":"pid","autoUpdateEnabled":true,"remoteControlEnabled":true,"managedCodexPath":"\#(temp.managedCodexBin.path)","socketPath":"\#(temp.socketPath.path)","cliVersion":"1.2.3","appServerVersion":"1.2.4"}"#
        )
    }

    func testRemoteControlStartUsesBootstrappedStartOutputWithoutWrapperTag() async throws {
        let temp = try AppServerDaemonTemporaryDirectory()
        try temp.createManagedCodexBin()
        try temp.writeUpdaterPidRecord(pid: 9001, processStartTime: "updater")
        let fakeProcess = AppServerDaemonFakeProcess(
            startTimes: [9001: "updater"],
            spawnedStartTimes: [2001: "app-start"],
            probeResults: [.failure(AppServerDaemonLifecycleError("not ready")), .success("1.2.4")]
        )

        let output = try await AppServerDaemonLifecycle.ensureRemoteControlStarted(
            codexHome: temp.url,
            cliVersion: "1.2.3",
            processClient: fakeProcess.client(),
            options: .test
        )

        guard case let .start(start) = output else {
            return XCTFail("Expected start output")
        }
        XCTAssertEqual(start.status, .started)
        XCTAssertEqual(start.backend, .pid)
        XCTAssertEqual(start.pid, 2001)
        XCTAssertEqual(start.appServerVersion, "1.2.4")
        XCTAssertEqual(
            try AppServerDaemonLifecycle.encodeRemoteControlStartOutput(output),
            #"{"status":"started","backend":"pid","pid":2001,"socketPath":"\#(temp.socketPath.path)","cliVersion":"1.2.3","appServerVersion":"1.2.4"}"#
        )
    }

    func testDaemonStartUsesPersistedRemoteControlSettingLikeRust() async throws {
        let temp = try AppServerDaemonTemporaryDirectory()
        try temp.createManagedCodexBin()
        try temp.writeSettings(remoteControlEnabled: true)
        let fakeProcess = AppServerDaemonFakeProcess(
            startTimes: [:],
            spawnedStartTimes: [2001: "app-start"],
            probeResults: [.failure(AppServerDaemonLifecycleError("not ready")), .success("1.2.4")]
        )

        let output = try await AppServerDaemonLifecycle.start(
            codexHome: temp.url,
            cliVersion: "1.2.3",
            processClient: fakeProcess.client(),
            options: .test
        )

        XCTAssertEqual(output.status, .started)
        XCTAssertEqual(output.backend, .pid)
        XCTAssertEqual(output.pid, 2001)
        XCTAssertEqual(output.appServerVersion, "1.2.4")
        let spawns = await fakeProcess.spawnsSnapshot()
        XCTAssertEqual(spawns.map(\.arguments), [
            ["app-server", "--remote-control", "--listen", "unix://"]
        ])
        XCTAssertEqual(
            try AppServerDaemonLifecycle.encodeOutput(output),
            #"{"status":"started","backend":"pid","pid":2001,"socketPath":"\#(temp.socketPath.path)","cliVersion":"1.2.3","appServerVersion":"1.2.4"}"#
        )
    }

    func testDaemonBootstrapWithoutRemoteControlStartsAppAndUpdaterLikeRust() async throws {
        let temp = try AppServerDaemonTemporaryDirectory()
        try temp.createManagedCodexBin()
        let fakeProcess = AppServerDaemonFakeProcess(
            startTimes: [:],
            spawnedStartTimes: [2001: "app-start", 2002: "updater-start"],
            probeResults: [.failure(AppServerDaemonLifecycleError("not ready")), .success("1.2.4")]
        )

        let output = try await AppServerDaemonLifecycle.bootstrap(
            codexHome: temp.url,
            cliVersion: "1.2.3",
            remoteControlEnabled: false,
            processClient: fakeProcess.client(),
            options: .test
        )

        XCTAssertEqual(output, AppServerDaemonBootstrapOutput(
            status: .bootstrapped,
            backend: .pid,
            autoUpdateEnabled: true,
            remoteControlEnabled: false,
            managedCodexPath: temp.managedCodexBin.path,
            socketPath: temp.socketPath.path,
            cliVersion: "1.2.3",
            appServerVersion: "1.2.4"
        ))
        XCTAssertEqual(try temp.settingsJSON(), #"{"remoteControlEnabled":false}"#)
        let spawns = await fakeProcess.spawnsSnapshot()
        XCTAssertEqual(spawns.map(\.arguments), [
            ["app-server", "--listen", "unix://"],
            ["app-server", "daemon", "pid-update-loop"]
        ])
        XCTAssertEqual(
            try AppServerDaemonLifecycle.encodeBootstrapOutput(output),
            #"{"status":"bootstrapped","backend":"pid","autoUpdateEnabled":true,"remoteControlEnabled":false,"managedCodexPath":"\#(temp.managedCodexBin.path)","socketPath":"\#(temp.socketPath.path)","cliVersion":"1.2.3","appServerVersion":"1.2.4"}"#
        )
    }

    func testDaemonVersionReportsRunningOutputLikeRust() async throws {
        let temp = try AppServerDaemonTemporaryDirectory()
        try temp.writeSettings(remoteControlEnabled: false)
        try temp.writePidRecord(pid: 1234, processStartTime: "start")
        let fakeProcess = AppServerDaemonFakeProcess(
            startTimes: [1234: "start"],
            probeResults: [.success("1.2.4")]
        )

        let output = try await AppServerDaemonLifecycle.version(
            codexHome: temp.url,
            cliVersion: "1.2.3",
            processClient: fakeProcess.client(),
            options: .test
        )

        XCTAssertEqual(output, AppServerDaemonLifecycleOutput(
            status: .running,
            backend: .pid,
            pid: nil,
            socketPath: temp.socketPath.path,
            cliVersion: "1.2.3",
            appServerVersion: "1.2.4"
        ))
        XCTAssertEqual(
            try AppServerDaemonLifecycle.encodeOutput(output),
            #"{"status":"running","backend":"pid","socketPath":"\#(temp.socketPath.path)","cliVersion":"1.2.3","appServerVersion":"1.2.4"}"#
        )
    }

    func testSetRemoteControlEnablesPersistedSettingsWhenStoppedLikeRust() async throws {
        let temp = try AppServerDaemonTemporaryDirectory()
        try temp.writeSettings(remoteControlEnabled: false)

        let output = try await AppServerDaemonLifecycle.setRemoteControl(
            codexHome: temp.url,
            cliVersion: "1.2.3",
            enabled: true,
            processClient: .testClient(),
            options: .test
        )

        XCTAssertEqual(output, AppServerDaemonRemoteControlOutput(
            status: .enabled,
            backend: nil,
            remoteControlEnabled: true,
            socketPath: temp.socketPath.path,
            cliVersion: "1.2.3",
            appServerVersion: nil
        ))
        XCTAssertEqual(try temp.settingsJSON(), #"{"remoteControlEnabled":true}"#)
        XCTAssertEqual(
            try AppServerDaemonLifecycle.encodeRemoteControlOutput(output),
            #"{"status":"enabled","remoteControlEnabled":true,"socketPath":"\#(temp.socketPath.path)","cliVersion":"1.2.3"}"#
        )
    }

    func testSetRemoteControlRestartsRunningBackendLikeRust() async throws {
        let temp = try AppServerDaemonTemporaryDirectory()
        try temp.createManagedCodexBin()
        try temp.writeSettings(remoteControlEnabled: false)
        try temp.writePidRecord(pid: 1234, processStartTime: "old-start")
        let fakeProcess = AppServerDaemonFakeProcess(
            startTimes: [1234: "old-start"],
            spawnedStartTimes: [2001: "new-start"],
            probeResults: [.success("1.2.4")]
        )

        let output = try await AppServerDaemonLifecycle.setRemoteControl(
            codexHome: temp.url,
            cliVersion: "1.2.3",
            enabled: true,
            processClient: fakeProcess.client(),
            options: .test
        )

        XCTAssertEqual(output, AppServerDaemonRemoteControlOutput(
            status: .enabled,
            backend: .pid,
            remoteControlEnabled: true,
            socketPath: temp.socketPath.path,
            cliVersion: "1.2.3",
            appServerVersion: "1.2.4"
        ))
        XCTAssertEqual(try temp.settingsJSON(), #"{"remoteControlEnabled":true}"#)
        let signals = await fakeProcess.signalsSnapshot()
        XCTAssertEqual(signals, [.terminate])
        let spawns = await fakeProcess.spawnsSnapshot()
        XCTAssertEqual(spawns.map(\.arguments), [
            ["app-server", "--remote-control", "--listen", "unix://"]
        ])
        XCTAssertEqual(
            try AppServerDaemonLifecycle.encodeRemoteControlOutput(output),
            #"{"status":"enabled","backend":"pid","remoteControlEnabled":true,"socketPath":"\#(temp.socketPath.path)","cliVersion":"1.2.3","appServerVersion":"1.2.4"}"#
        )
    }

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
            sleep: { _ in },
            spawnDetached: { _ in 0 },
            probeAppServerVersion: { _ in throw AppServerDaemonLifecycleError("not ready") }
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

    var socketPath: URL {
        url
            .appendingPathComponent("app-server-control", isDirectory: true)
            .appendingPathComponent("app-server-control.sock", isDirectory: false)
    }

    var pidFile: URL {
        url
            .appendingPathComponent("app-server-daemon", isDirectory: true)
            .appendingPathComponent("app-server.pid", isDirectory: false)
    }

    var updatePidFile: URL {
        url
            .appendingPathComponent("app-server-daemon", isDirectory: true)
            .appendingPathComponent("app-server-updater.pid", isDirectory: false)
    }

    var settingsFile: URL {
        url
            .appendingPathComponent("app-server-daemon", isDirectory: true)
            .appendingPathComponent("settings.json", isDirectory: false)
    }

    var managedCodexBin: URL {
        url
            .appendingPathComponent("packages", isDirectory: true)
            .appendingPathComponent("standalone", isDirectory: true)
            .appendingPathComponent("current", isDirectory: true)
            .appendingPathComponent("codex", isDirectory: false)
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
        try writePidRecord(pid: pid, processStartTime: processStartTime, path: pidFile)
    }

    func writeUpdaterPidRecord(pid: UInt32, processStartTime: String) throws {
        try writePidRecord(pid: pid, processStartTime: processStartTime, path: updatePidFile)
    }

    func createManagedCodexBin() throws {
        try FileManager.default.createDirectory(at: managedCodexBin.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: managedCodexBin)
    }

    func writeSettings(remoteControlEnabled: Bool) throws {
        try FileManager.default.createDirectory(at: settingsFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = #"{"remoteControlEnabled":\#(remoteControlEnabled)}"#.data(using: .utf8)!
        try data.write(to: settingsFile)
    }

    func settingsJSON() throws -> String {
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: settingsFile))
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    private func writePidRecord(pid: UInt32, processStartTime: String, path: URL) throws {
        let stateDir = pidFile.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: stateDir, withIntermediateDirectories: true)
        let data = #"{"pid":\#(pid),"processStartTime":"\#(processStartTime)"}"#.data(using: .utf8)!
        try data.write(to: path)
    }
}

private actor AppServerDaemonFakeProcess {
    private var startTimes: [UInt32: String]
    private var spawnedStartTimes: [UInt32: String]
    private var nextSpawnPID: UInt32 = 2001
    private var probeResults: [Result<String, Error>]
    private let terminateRemovesProcess: Bool
    private let killRemovesProcess: Bool
    private(set) var signals: [AppServerDaemonSignal] = []
    private(set) var spawns: [AppServerDaemonSpawnRequest] = []

    init(
        startTimes: [UInt32: String],
        spawnedStartTimes: [UInt32: String] = [:],
        probeResults: [Result<String, Error>] = [],
        terminateRemovesProcess: Bool = true,
        killRemovesProcess: Bool = true
    ) {
        self.startTimes = startTimes
        self.spawnedStartTimes = spawnedStartTimes
        self.probeResults = probeResults
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
            sleep: { _ in },
            spawnDetached: { [weak self] request in
                guard let self else { return 0 }
                return await self.recordSpawn(request)
            },
            probeAppServerVersion: { [weak self] _ in
                guard let self else { throw AppServerDaemonLifecycleError("not ready") }
                return try await self.nextProbeResult()
            }
        )
    }

    func signalsSnapshot() -> [AppServerDaemonSignal] {
        signals
    }

    func spawnsSnapshot() -> [AppServerDaemonSpawnRequest] {
        spawns
    }

    private func recordSpawn(_ request: AppServerDaemonSpawnRequest) -> UInt32 {
        let pid = nextSpawnPID
        nextSpawnPID += 1
        spawns.append(request)
        if let startTime = spawnedStartTimes[pid] {
            startTimes[pid] = startTime
        }
        return pid
    }

    private func nextProbeResult() throws -> String {
        guard !probeResults.isEmpty else {
            throw AppServerDaemonLifecycleError("not ready")
        }
        return try probeResults.removeFirst().get()
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
