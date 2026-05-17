import CodexCLI
import Darwin
import Foundation
import XCTest

final class AppServerDaemonLifecycleTests: XCTestCase {
    func testParseManagedCodexVersionOutputMatchesRust() throws {
        XCTAssertEqual(
            try AppServerDaemonLifecycle.parseManagedCodexVersionOutput("codex 1.2.3\n"),
            "1.2.3"
        )
        XCTAssertEqual(
            try AppServerDaemonLifecycle.parseManagedCodexVersionOutput("codex\t2.0.0 extra\n"),
            "2.0.0"
        )
        XCTAssertThrowsError(try AppServerDaemonLifecycle.parseManagedCodexVersionOutput("codex\n")) { error in
            XCTAssertEqual(
                (error as? AppServerDaemonLifecycleError)?.description,
                "managed Codex version output was malformed"
            )
        }
    }

    func testExecutableIdentityReadsBinaryContentsLikeRust() throws {
        let temp = try AppServerDaemonTemporaryDirectory()
        let path = temp.url.appendingPathComponent("codex", isDirectory: false)
        try Data("old".utf8).write(to: path)
        let old = try AppServerDaemonLifecycle.executableIdentity(at: path)
        let same = AppServerDaemonExecutableIdentity(bytes: Data("old".utf8))
        let new = AppServerDaemonExecutableIdentity(bytes: Data("new".utf8))

        XCTAssertEqual(old, same)
        XCTAssertNotEqual(old, new)
    }

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

    func testTryRestartIfRunningReturnsBusyWhenOperationLockIsHeldLikeRust() async throws {
        let temp = try AppServerDaemonTemporaryDirectory()
        try FileManager.default.createDirectory(at: temp.stateDirectory, withIntermediateDirectories: true)
        let descriptor = Darwin.open(temp.operationLockFile.path, O_CREAT | O_RDWR, 0o600)
        XCTAssertGreaterThanOrEqual(descriptor, 0)
        defer {
            _ = flock(descriptor, LOCK_UN)
            _ = Darwin.close(descriptor)
        }
        XCTAssertEqual(flock(descriptor, LOCK_EX | LOCK_NB), 0)

        let outcome = try await AppServerDaemonLifecycle.tryRestartIfRunning(
            codexHome: temp.url,
            restartMode: .always,
            updaterRefreshMode: .none,
            managedCodexBin: temp.managedCodexBin,
            processClient: .testClient(),
            updaterClient: .testClient(),
            options: .test
        )

        XCTAssertEqual(outcome, .busy)
    }

    func testTryRestartIfRunningReturnsNotRunningWhenNoManagedBackendOrSocketLikeRust() async throws {
        let temp = try AppServerDaemonTemporaryDirectory()

        let outcome = try await AppServerDaemonLifecycle.tryRestartIfRunning(
            codexHome: temp.url,
            restartMode: .ifVersionChanged,
            updaterRefreshMode: .none,
            managedCodexBin: temp.managedCodexBin,
            processClient: .testClient(),
            updaterClient: .testClient(),
            options: .test
        )

        XCTAssertEqual(outcome, .notRunning)
    }

    func testTryRestartIfRunningReturnsNotReadyWhenManagedBackendProbeFailsLikeRust() async throws {
        let temp = try AppServerDaemonTemporaryDirectory()
        try temp.writePidRecord(pid: 1234, processStartTime: "start")
        let updater = AppServerDaemonFakeUpdater()

        let outcome = try await AppServerDaemonLifecycle.tryRestartIfRunning(
            codexHome: temp.url,
            restartMode: .ifVersionChanged,
            updaterRefreshMode: .none,
            managedCodexBin: temp.managedCodexBin,
            processClient: .testClient(startTimes: [1234: "start"]),
            updaterClient: updater.client(),
            options: .test
        )

        XCTAssertEqual(outcome, .notReady)
        let requestedVersions = await updater.requestedVersionsSnapshot()
        XCTAssertEqual(requestedVersions, [])
    }

    func testTryRestartIfRunningSkipsRestartWhenVersionAlreadyCurrentLikeRust() async throws {
        let temp = try AppServerDaemonTemporaryDirectory()
        try temp.writePidRecord(pid: 1234, processStartTime: "start")
        let fakeProcess = AppServerDaemonFakeProcess(
            startTimes: [1234: "start"],
            probeResults: [.success("1.2.3")]
        )
        let updater = AppServerDaemonFakeUpdater(managedVersions: ["1.2.3"])

        let outcome = try await AppServerDaemonLifecycle.tryRestartIfRunning(
            codexHome: temp.url,
            restartMode: .ifVersionChanged,
            updaterRefreshMode: .reexecIfManagedBinaryChanged,
            managedCodexBin: temp.managedCodexBin,
            processClient: fakeProcess.client(),
            updaterClient: updater.client(),
            options: .test
        )

        XCTAssertEqual(outcome, .alreadyCurrent)
        let signals = await fakeProcess.signalsSnapshot()
        let spawns = await fakeProcess.spawnsSnapshot()
        let reexecs = await updater.reexecsSnapshot()
        XCTAssertEqual(signals, [])
        XCTAssertEqual(spawns, [])
        XCTAssertEqual(reexecs, [])
    }

    func testTryRestartIfRunningRestartsAndReexecsChangedManagedUpdaterLikeRust() async throws {
        let temp = try AppServerDaemonTemporaryDirectory()
        try temp.writeSettings(remoteControlEnabled: true)
        try temp.writePidRecord(pid: 1234, processStartTime: "old-start")
        let fakeProcess = AppServerDaemonFakeProcess(
            startTimes: [1234: "old-start"],
            spawnedStartTimes: [2001: "new-start"],
            probeResults: [.success("1.2.2"), .success("1.2.3")]
        )
        let updater = AppServerDaemonFakeUpdater(managedVersions: ["1.2.3"])

        let outcome = try await AppServerDaemonLifecycle.tryRestartIfRunning(
            codexHome: temp.url,
            restartMode: .always,
            updaterRefreshMode: .reexecIfManagedBinaryChanged,
            managedCodexBin: temp.managedCodexBin,
            processClient: fakeProcess.client(),
            updaterClient: updater.client(),
            options: .test
        )

        XCTAssertEqual(outcome, .restarted)
        let signals = await fakeProcess.signalsSnapshot()
        XCTAssertEqual(signals, [.terminate])
        let spawns = await fakeProcess.spawnsSnapshot()
        XCTAssertEqual(spawns.map(\.executablePath), [temp.managedCodexBin.path])
        XCTAssertEqual(spawns.map(\.arguments), [
            ["app-server", "--remote-control", "--listen", "unix://"]
        ])
        let reexecs = await updater.reexecsSnapshot()
        XCTAssertEqual(reexecs, [temp.managedCodexBin])
    }

    func testRunPidUpdateLoopOnceRetriesBusyRestartLikeRust() async throws {
        let temp = try AppServerDaemonTemporaryDirectory()
        try temp.createManagedCodexBin(contents: Data("managed".utf8))
        let running = AppServerDaemonExecutableIdentity(bytes: Data("running".utf8))
        let loop = AppServerDaemonFakeUpdateLoop(
            managedCodexBin: temp.managedCodexBin,
            managedIdentity: AppServerDaemonExecutableIdentity(bytes: Data("managed".utf8)),
            restartOutcomes: [.busy, .restarted]
        )

        let control = try await AppServerDaemonLifecycle.runPidUpdateLoopOnce(
            codexHome: temp.url,
            runningUpdaterIdentity: running,
            retryInterval: 0.25,
            client: loop.client()
        )

        XCTAssertEqual(control, .continueRunning)
        let events = await loop.eventsSnapshot()
        XCTAssertEqual(events, [
            .installLatestStandalone,
            .resolveManagedCodex(temp.managedCodexBin),
            .executableIdentity(temp.managedCodexBin),
            .tryRestart(.always, .reexecIfManagedBinaryChanged, temp.managedCodexBin),
            .sleepOrTerminate(0.25),
            .tryRestart(.always, .reexecIfManagedBinaryChanged, temp.managedCodexBin)
        ])
    }

    func testRunPidUpdateLoopOnceStopsWhenTerminationArrivesDuringBusyRetryLikeRust() async throws {
        let temp = try AppServerDaemonTemporaryDirectory()
        try temp.createManagedCodexBin(contents: Data("same".utf8))
        let running = AppServerDaemonExecutableIdentity(bytes: Data("same".utf8))
        let loop = AppServerDaemonFakeUpdateLoop(
            managedCodexBin: temp.managedCodexBin,
            managedIdentity: AppServerDaemonExecutableIdentity(bytes: Data("same".utf8)),
            restartOutcomes: [.busy],
            terminateOnSleep: true
        )

        let control = try await AppServerDaemonLifecycle.runPidUpdateLoopOnce(
            codexHome: temp.url,
            runningUpdaterIdentity: running,
            retryInterval: 0.05,
            client: loop.client()
        )

        XCTAssertEqual(control, .stop)
        let events = await loop.eventsSnapshot()
        XCTAssertEqual(events, [
            .installLatestStandalone,
            .resolveManagedCodex(temp.managedCodexBin),
            .executableIdentity(temp.managedCodexBin),
            .tryRestart(.ifVersionChanged, .none, temp.managedCodexBin),
            .sleepOrTerminate(0.05)
        ])
    }

    func testRunPidUpdateLoopStopsBeforeFirstUpdateWhenInitialSleepTerminatesLikeRust() async throws {
        let temp = try AppServerDaemonTemporaryDirectory()
        let running = AppServerDaemonExecutableIdentity(bytes: Data("same".utf8))
        let loop = AppServerDaemonFakeUpdateLoop(
            managedCodexBin: temp.managedCodexBin,
            managedIdentity: running,
            currentUpdaterIdentity: running,
            sleepResults: [true]
        )

        try await AppServerDaemonLifecycle.runPidUpdateLoop(
            codexHome: temp.url,
            initialDelay: 5,
            updateInterval: 10,
            retryInterval: 0.05,
            client: loop.client()
        )

        let events = await loop.eventsSnapshot()
        XCTAssertEqual(events, [
            .currentUpdaterIdentity,
            .sleepOrTerminate(5)
        ])
    }

    func testInstallLatestStandaloneFetchesScriptBeforeRunningShellLikeRust() async throws {
        let installer = AppServerDaemonFakeStandaloneInstaller(script: Data("echo ok\n".utf8))

        try await AppServerDaemonLifecycle.installLatestStandalone(client: installer.client())

        let events = await installer.eventsSnapshot()
        XCTAssertEqual(events, [
            .fetchScript,
            .runScript(Data("echo ok\n".utf8))
        ])
    }

    func testInstallLatestStandaloneStopsBeforeShellWhenFetchFailsLikeRust() async throws {
        let installer = AppServerDaemonFakeStandaloneInstaller(
            fetchError: AppServerDaemonLifecycleError("failed to fetch standalone Codex updater")
        )

        do {
            try await AppServerDaemonLifecycle.installLatestStandalone(client: installer.client())
            XCTFail("Expected standalone installer fetch failure")
        } catch let error as AppServerDaemonLifecycleError {
            XCTAssertEqual(error.description, "failed to fetch standalone Codex updater")
        }

        let events = await installer.eventsSnapshot()
        XCTAssertEqual(events, [.fetchScript])
    }

    func testValidateStandaloneUpdaterResponseRejectsNonHTTPSuccessLikeRust() throws {
        let ok = HTTPURLResponse(
            url: URL(string: "https://chatgpt.com/codex/install.sh")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        XCTAssertNoThrow(try AppServerDaemonLifecycle.validateStandaloneUpdaterResponse(ok))

        let missingHTTP = URLResponse(
            url: URL(string: "https://chatgpt.com/codex/install.sh")!,
            mimeType: nil,
            expectedContentLength: 0,
            textEncodingName: nil
        )
        XCTAssertThrowsError(try AppServerDaemonLifecycle.validateStandaloneUpdaterResponse(missingHTTP)) { error in
            XCTAssertEqual(
                (error as? AppServerDaemonLifecycleError)?.description,
                "standalone Codex updater request failed"
            )
        }

        let notFound = HTTPURLResponse(
            url: URL(string: "https://chatgpt.com/codex/install.sh")!,
            statusCode: 404,
            httpVersion: nil,
            headerFields: nil
        )!
        XCTAssertThrowsError(try AppServerDaemonLifecycle.validateStandaloneUpdaterResponse(notFound)) { error in
            XCTAssertEqual(
                (error as? AppServerDaemonLifecycleError)?.description,
                "standalone Codex updater request failed"
            )
        }
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

private extension AppServerDaemonUpdaterRuntimeClient {
    static func testClient() -> AppServerDaemonUpdaterRuntimeClient {
        AppServerDaemonUpdaterRuntimeClient(
            managedCodexVersion: { _ in "1.2.3" },
            reexecManagedUpdater: { _ in }
        )
    }
}

private final class AppServerDaemonTemporaryDirectory {
    let url: URL

    var stateDirectory: URL {
        url.appendingPathComponent("app-server-daemon", isDirectory: true)
    }

    var socketPath: URL {
        url
            .appendingPathComponent("app-server-control", isDirectory: true)
            .appendingPathComponent("app-server-control.sock", isDirectory: false)
    }

    var pidFile: URL {
        stateDirectory.appendingPathComponent("app-server.pid", isDirectory: false)
    }

    var updatePidFile: URL {
        stateDirectory.appendingPathComponent("app-server-updater.pid", isDirectory: false)
    }

    var operationLockFile: URL {
        stateDirectory.appendingPathComponent("daemon.lock", isDirectory: false)
    }

    var settingsFile: URL {
        stateDirectory.appendingPathComponent("settings.json", isDirectory: false)
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

    func createManagedCodexBin(contents: Data = Data()) throws {
        try FileManager.default.createDirectory(at: managedCodexBin.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: managedCodexBin)
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

private actor AppServerDaemonFakeUpdater {
    private var managedVersions: [String]
    private var requestedVersions: [URL] = []
    private var reexecs: [URL] = []

    init(managedVersions: [String] = []) {
        self.managedVersions = managedVersions
    }

    func client() -> AppServerDaemonUpdaterRuntimeClient {
        AppServerDaemonUpdaterRuntimeClient(
            managedCodexVersion: { [weak self] codexBin in
                guard let self else { return "1.2.3" }
                return await self.nextManagedVersion(codexBin: codexBin)
            },
            reexecManagedUpdater: { [weak self] managedCodexBin in
                await self?.recordReexec(managedCodexBin)
            }
        )
    }

    func requestedVersionsSnapshot() -> [URL] {
        requestedVersions
    }

    func reexecsSnapshot() -> [URL] {
        reexecs
    }

    private func nextManagedVersion(codexBin: URL) -> String {
        requestedVersions.append(codexBin)
        guard !managedVersions.isEmpty else {
            return "1.2.3"
        }
        return managedVersions.removeFirst()
    }

    private func recordReexec(_ managedCodexBin: URL) {
        reexecs.append(managedCodexBin)
    }
}

private enum AppServerDaemonUpdateLoopEvent: Equatable {
    case currentUpdaterIdentity
    case installLatestStandalone
    case resolveManagedCodex(URL)
    case executableIdentity(URL)
    case tryRestart(AppServerDaemonRestartMode, AppServerDaemonUpdaterRefreshMode, URL)
    case sleepOrTerminate(TimeInterval)
}

private actor AppServerDaemonFakeUpdateLoop {
    private let managedCodexBin: URL
    private let managedIdentity: AppServerDaemonExecutableIdentity
    private let currentIdentity: AppServerDaemonExecutableIdentity
    private var restartOutcomes: [AppServerDaemonRestartIfRunningOutcome]
    private var sleepResults: [Bool]
    private let terminateOnSleep: Bool
    private var terminated = false
    private var events: [AppServerDaemonUpdateLoopEvent] = []

    init(
        managedCodexBin: URL,
        managedIdentity: AppServerDaemonExecutableIdentity,
        currentUpdaterIdentity: AppServerDaemonExecutableIdentity? = nil,
        restartOutcomes: [AppServerDaemonRestartIfRunningOutcome] = [.notRunning],
        sleepResults: [Bool] = [],
        terminateOnSleep: Bool = false
    ) {
        self.managedCodexBin = managedCodexBin
        self.managedIdentity = managedIdentity
        currentIdentity = currentUpdaterIdentity ?? AppServerDaemonExecutableIdentity(bytes: Data("running".utf8))
        self.restartOutcomes = restartOutcomes
        self.sleepResults = sleepResults
        self.terminateOnSleep = terminateOnSleep
    }

    func client() -> AppServerDaemonUpdateLoopClient {
        AppServerDaemonUpdateLoopClient(
            currentUpdaterIdentity: { [weak self] in
                guard let self else {
                    return AppServerDaemonExecutableIdentity(bytes: Data())
                }
                return await self.recordCurrentUpdaterIdentity()
            },
            installLatestStandalone: { [weak self] in
                await self?.record(.installLatestStandalone)
            },
            resolvedManagedCodexBin: { [weak self] codexBin in
                await self?.record(.resolveManagedCodex(codexBin))
                return self?.managedCodexBin ?? codexBin
            },
            executableIdentity: { [weak self] executable in
                guard let self else {
                    return AppServerDaemonExecutableIdentity(bytes: Data())
                }
                return await self.recordExecutableIdentity(executable)
            },
            tryRestartIfRunning: { [weak self] restartMode, updaterRefreshMode, managedCodexBin in
                guard let self else { return .notRunning }
                return await self.nextRestartOutcome(
                    restartMode: restartMode,
                    updaterRefreshMode: updaterRefreshMode,
                    managedCodexBin: managedCodexBin
                )
            },
            sleepOrTerminate: { [weak self] seconds in
                guard let self else { return false }
                return await self.nextSleepResult(seconds: seconds)
            },
            terminationRequested: { [weak self] in
                await self?.terminationRequested() ?? false
            }
        )
    }

    func eventsSnapshot() -> [AppServerDaemonUpdateLoopEvent] {
        events
    }

    private func record(_ event: AppServerDaemonUpdateLoopEvent) {
        events.append(event)
    }

    private func recordCurrentUpdaterIdentity() -> AppServerDaemonExecutableIdentity {
        events.append(.currentUpdaterIdentity)
        return currentIdentity
    }

    private func recordExecutableIdentity(_ executable: URL) -> AppServerDaemonExecutableIdentity {
        events.append(.executableIdentity(executable))
        return managedIdentity
    }

    private func nextRestartOutcome(
        restartMode: AppServerDaemonRestartMode,
        updaterRefreshMode: AppServerDaemonUpdaterRefreshMode,
        managedCodexBin: URL
    ) -> AppServerDaemonRestartIfRunningOutcome {
        events.append(.tryRestart(restartMode, updaterRefreshMode, managedCodexBin))
        guard !restartOutcomes.isEmpty else {
            return .notRunning
        }
        return restartOutcomes.removeFirst()
    }

    private func nextSleepResult(seconds: TimeInterval) -> Bool {
        events.append(.sleepOrTerminate(seconds))
        if terminateOnSleep {
            terminated = true
            return true
        }
        guard !sleepResults.isEmpty else {
            return false
        }
        return sleepResults.removeFirst()
    }

    private func terminationRequested() -> Bool {
        terminated
    }
}

private enum AppServerDaemonStandaloneInstallerEvent: Equatable {
    case fetchScript
    case runScript(Data)
}

private actor AppServerDaemonFakeStandaloneInstaller {
    private let script: Data
    private let fetchError: Error?
    private let runError: Error?
    private var events: [AppServerDaemonStandaloneInstallerEvent] = []

    init(
        script: Data = Data(),
        fetchError: Error? = nil,
        runError: Error? = nil
    ) {
        self.script = script
        self.fetchError = fetchError
        self.runError = runError
    }

    func client() -> AppServerDaemonStandaloneInstallerClient {
        AppServerDaemonStandaloneInstallerClient(
            fetchScript: { [weak self] in
                guard let self else { return Data() }
                return try await self.fetchScript()
            },
            runScript: { [weak self] script in
                try await self?.runScript(script)
            }
        )
    }

    func eventsSnapshot() -> [AppServerDaemonStandaloneInstallerEvent] {
        events
    }

    private func fetchScript() throws -> Data {
        events.append(.fetchScript)
        if let fetchError {
            throw fetchError
        }
        return script
    }

    private func runScript(_ script: Data) throws {
        events.append(.runScript(script))
        if let runError {
            throw runError
        }
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
