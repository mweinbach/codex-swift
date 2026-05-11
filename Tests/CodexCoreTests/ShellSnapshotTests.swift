import Foundation
import XCTest
#if os(Linux)
import Glibc
#elseif os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
import Darwin
#endif
@testable import CodexCore

final class ShellSnapshotTests: XCTestCase {
    func testStripSnapshotPreambleRemovesLeadingOutput() throws {
        let snapshot = "noise\n# Snapshot file\nexport PATH=/bin\n"
        let cleaned = try ShellSnapshot.stripSnapshotPreamble(snapshot)

        XCTAssertEqual(cleaned, "# Snapshot file\nexport PATH=/bin\n")
    }

    func testStripSnapshotPreambleRequiresMarker() {
        XCTAssertThrowsError(try ShellSnapshot.stripSnapshotPreamble("missing header")) { error in
            XCTAssertEqual(
                String(describing: error),
                "Snapshot output missing marker # Snapshot file"
            )
        }
    }

    func testSnapshotFileNameParserSupportsLegacyAndSuffixedNames() {
        let sessionID = "019cf82b-6a62-7700-bbbd-46909794ef89"

        XCTAssertEqual(ShellSnapshot.snapshotSessionID(fromFileName: "\(sessionID).sh"), sessionID)
        XCTAssertEqual(ShellSnapshot.snapshotSessionID(fromFileName: "\(sessionID).123.sh"), sessionID)
        XCTAssertEqual(ShellSnapshot.snapshotSessionID(fromFileName: "\(sessionID).tmp-123"), sessionID)
        XCTAssertNil(ShellSnapshot.snapshotSessionID(fromFileName: "not-a-snapshot.txt"))
    }

    #if os(macOS) || os(Linux)
    func testBashSnapshotFiltersInvalidExports() throws {
        let output = try run(
            executable: "/bin/bash",
            arguments: ["-c", ShellSnapshot.bashSnapshotScript()],
            environment: [
                "BASH_ENV": "/dev/null",
                "VALID_NAME": "ok",
                "PWD": "/tmp/stale",
                "NEXTEST_BIN_EXE_codex-write-config-schema": "/path/to/bin",
                "BAD-NAME": "broken"
            ],
            cwd: FileManager.default.temporaryDirectory
        )

        XCTAssertTrue(output.contains("VALID_NAME"))
        XCTAssertFalse(output.contains("PWD=/tmp/stale"))
        XCTAssertFalse(output.contains("NEXTEST_BIN_EXE_codex-write-config-schema"))
        XCTAssertFalse(output.contains("BAD-NAME"))
    }

    func testBashSnapshotPreservesMultilineExportsAndSources() throws {
        let multilineCertificate = "-----BEGIN CERTIFICATE-----\nabc\n-----END CERTIFICATE-----"
        let output = try run(
            executable: "/bin/bash",
            arguments: ["-c", ShellSnapshot.bashSnapshotScript()],
            environment: [
                "BASH_ENV": "/dev/null",
                "MULTILINE_CERT": multilineCertificate
            ],
            cwd: FileManager.default.temporaryDirectory
        )

        XCTAssertTrue(
            output.contains("MULTILINE_CERT=") || output.contains("MULTILINE_CERT"),
            "snapshot should include the multiline export name"
        )

        let directory = try temporaryDirectory()
        let snapshotPath = directory.appendingPathComponent("snapshot.sh")
        try output.write(to: snapshotPath, atomically: true, encoding: .utf8)

        _ = try run(
            executable: "/bin/bash",
            arguments: ["-c", #"set -e; . "$1""#, "bash", snapshotPath.path],
            environment: ["BASH_ENV": "/dev/null"],
            cwd: directory
        )
    }

    func testTryNewCreatesAndDeletesSnapshotFile() throws {
        let directory = try temporaryDirectory()
        let shell = Shell(shellType: .bash, shellPath: "/bin/bash")
        var snapshot: ShellSnapshot? = try withSanitizedShellHome(directory) {
            try ShellSnapshot.tryNew(
                codexHome: directory,
                sessionID: ThreadId(),
                sessionCwd: directory,
                shell: shell
            )
        }

        let path = try XCTUnwrap(snapshot?.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: path.path))
        XCTAssertEqual(snapshot?.cwd, directory)

        snapshot = nil

        XCTAssertFalse(FileManager.default.fileExists(atPath: path.path))
    }

    func testTryNewUsesDistinctGenerationPaths() throws {
        let directory = try temporaryDirectory()
        let sessionID = ThreadId()
        let shell = Shell(shellType: .bash, shellPath: "/bin/bash")
        var initialSnapshot: ShellSnapshot? = try withSanitizedShellHome(directory) {
            try ShellSnapshot.tryNew(
                codexHome: directory,
                sessionID: sessionID,
                sessionCwd: directory,
                shell: shell
            )
        }
        var refreshedSnapshot: ShellSnapshot? = try withSanitizedShellHome(directory) {
            try ShellSnapshot.tryNew(
                codexHome: directory,
                sessionID: sessionID,
                sessionCwd: directory,
                shell: shell
            )
        }

        let initialPath = try XCTUnwrap(initialSnapshot?.path)
        let refreshedPath = try XCTUnwrap(refreshedSnapshot?.path)
        XCTAssertNotEqual(initialPath, refreshedPath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: initialPath.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: refreshedPath.path))

        initialSnapshot = nil

        XCTAssertFalse(FileManager.default.fileExists(atPath: initialPath.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: refreshedPath.path))

        refreshedSnapshot = nil

        XCTAssertFalse(FileManager.default.fileExists(atPath: refreshedPath.path))
    }

    func testAttachSnapshotIfEnabledCreatesSnapshotForDefaultFeature() throws {
        let directory = try temporaryDirectory()
        let shell = Shell(shellType: .bash, shellPath: "/bin/bash")
        var attachedShell: Shell? = try withSanitizedShellHome(directory) {
            ShellSnapshot.attachSnapshotIfEnabled(
                codexHome: directory,
                sessionID: ThreadId(),
                sessionCwd: directory,
                shell: shell,
                features: .withDefaults()
            )
        }

        let snapshotPath: URL
        do {
            let snapshot = try XCTUnwrap(attachedShell?.shellSnapshot)
            XCTAssertEqual(attachedShell?.shellType, .bash)
            XCTAssertEqual(attachedShell?.shellPath, "/bin/bash")
            XCTAssertEqual(snapshot.cwd, directory)
            XCTAssertTrue(FileManager.default.fileExists(atPath: snapshot.path.path))
            snapshotPath = snapshot.path
        }
        attachedShell = nil

        XCTAssertFalse(FileManager.default.fileExists(atPath: snapshotPath.path))
    }

    func testAttachSnapshotIfEnabledSkipsWhenFeatureDisabled() throws {
        let directory = try temporaryDirectory()
        var features = FeatureStates.withDefaults()
        features.set(.shellSnapshot, enabled: false)

        let shell = ShellSnapshot.attachSnapshotIfEnabled(
            codexHome: directory,
            sessionID: ThreadId(),
            sessionCwd: directory,
            shell: Shell(shellType: .bash, shellPath: "/bin/bash"),
            features: features
        )

        XCTAssertNil(shell.shellSnapshot)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: directory.appendingPathComponent(ShellSnapshot.directoryName, isDirectory: true).path
        ))
    }

    func testAttachSnapshotIfEnabledFallsBackWhenSnapshotCreationFails() throws {
        let directory = try temporaryDirectory()
        let originalShell = Shell(shellType: .cmd, shellPath: "cmd.exe")

        let shell = ShellSnapshot.attachSnapshotIfEnabled(
            codexHome: directory,
            sessionID: ThreadId(),
            sessionCwd: directory,
            shell: originalShell,
            features: .withDefaults()
        )

        XCTAssertEqual(shell, originalShell)
        XCTAssertNil(shell.shellSnapshot)
    }

    func testCleanupStaleSnapshotsRemovesOrphansAndKeepsLive() throws {
        let directory = try temporaryDirectory()
        let snapshotDirectory = directory.appendingPathComponent(ShellSnapshot.directoryName, isDirectory: true)
        try FileManager.default.createDirectory(at: snapshotDirectory, withIntermediateDirectories: true)

        let liveSession = ThreadId()
        let orphanSession = ThreadId()
        let liveSnapshot = snapshotDirectory.appendingPathComponent("\(liveSession).123.sh")
        let orphanSnapshot = snapshotDirectory.appendingPathComponent("\(orphanSession).456.sh")
        let invalidSnapshot = snapshotDirectory.appendingPathComponent("not-a-snapshot.txt")

        try writeRolloutStub(codexHome: directory, sessionID: liveSession)
        try "live".write(to: liveSnapshot, atomically: true, encoding: .utf8)
        try "orphan".write(to: orphanSnapshot, atomically: true, encoding: .utf8)
        try "invalid".write(to: invalidSnapshot, atomically: true, encoding: .utf8)

        try ShellSnapshot.cleanupStaleSnapshots(codexHome: directory, activeSessionID: ThreadId())

        XCTAssertTrue(FileManager.default.fileExists(atPath: liveSnapshot.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: orphanSnapshot.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: invalidSnapshot.path))
    }

    func testCleanupStaleSnapshotsSkipsActiveSession() throws {
        let directory = try temporaryDirectory()
        let snapshotDirectory = directory.appendingPathComponent(ShellSnapshot.directoryName, isDirectory: true)
        try FileManager.default.createDirectory(at: snapshotDirectory, withIntermediateDirectories: true)

        let activeSession = ThreadId()
        let activeSnapshot = snapshotDirectory.appendingPathComponent("\(activeSession).123.sh")
        try "active".write(to: activeSnapshot, atomically: true, encoding: .utf8)

        try ShellSnapshot.cleanupStaleSnapshots(codexHome: directory, activeSessionID: activeSession)

        XCTAssertTrue(FileManager.default.fileExists(atPath: activeSnapshot.path))
    }

    func testBashSnapshotIncludesRustSections() throws {
        let directory = try temporaryDirectory()
        let snapshotPath = directory.appendingPathComponent("snapshot.sh")

        try withSanitizedShellHome(directory) {
            try ShellSnapshot.writeShellSnapshot(shellType: .bash, outputPath: snapshotPath, cwd: directory)
        }
        let snapshot = try String(contentsOf: snapshotPath, encoding: .utf8)

        XCTAssertTrue(snapshot.contains("# Snapshot file"))
        XCTAssertTrue(snapshot.contains("aliases "))
        XCTAssertTrue(snapshot.contains("exports "))
        XCTAssertTrue(snapshot.contains("PATH"))
        XCTAssertTrue(snapshot.contains("setopts "))
    }

    func testSnapshotCommandWrapperBootstrapsInUserShell() throws {
        let directory = try temporaryDirectory()
        let shell = try shellWithSnapshot(directory: directory, contents: "# Snapshot file\n")
        let command = ["/bin/bash", "-lc", "echo hello"]

        let rewritten = ShellSnapshotCommandWrapper.maybeWrapShellLCWithSnapshot(
            command: command,
            sessionShell: shell,
            cwd: directory,
            explicitEnvOverrides: [:],
            environment: [:]
        )

        XCTAssertEqual(rewritten[0], "/bin/bash")
        XCTAssertEqual(rewritten[1], "-c")
        XCTAssertTrue(rewritten[2].contains("if . '"))
        XCTAssertTrue(rewritten[2].contains("exec '/bin/bash' -c 'echo hello'"))
    }

    func testSnapshotCommandWrapperEscapesSingleQuotesAndTrailingArgs() throws {
        let directory = try temporaryDirectory()
        let shell = try shellWithSnapshot(directory: directory, contents: "# Snapshot file\n")
        let command = ["/bin/bash", "-lc", "printf '%s %s' \"$0\" \"$1\"", "arg'0", "arg1"]

        let rewritten = ShellSnapshotCommandWrapper.maybeWrapShellLCWithSnapshot(
            command: command,
            sessionShell: shell,
            cwd: directory,
            explicitEnvOverrides: [:],
            environment: [:]
        )

        XCTAssertTrue(
            rewritten[2].contains(
                #"exec '/bin/bash' -c 'printf '"'"'%s %s'"'"' "$0" "$1"' 'arg'"'"'0' 'arg1'"#
            )
        )
    }

    func testSnapshotCommandWrapperSkipsWhenCwdDiffers() throws {
        let directory = try temporaryDirectory()
        let snapshotCwd = directory.appendingPathComponent("snapshot-cwd", isDirectory: true)
        let commandCwd = directory.appendingPathComponent("command-cwd", isDirectory: true)
        try FileManager.default.createDirectory(at: snapshotCwd, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: commandCwd, withIntermediateDirectories: true)
        let shell = try shellWithSnapshot(directory: directory, cwd: snapshotCwd, contents: "# Snapshot file\n")
        let command = ["/bin/bash", "-lc", "echo hello"]

        let rewritten = ShellSnapshotCommandWrapper.maybeWrapShellLCWithSnapshot(
            command: command,
            sessionShell: shell,
            cwd: commandCwd,
            explicitEnvOverrides: [:],
            environment: [:]
        )

        XCTAssertEqual(rewritten, command)
    }

    func testSnapshotCommandWrapperAcceptsDotAliasCwd() throws {
        let directory = try temporaryDirectory()
        let shell = try shellWithSnapshot(directory: directory, contents: "# Snapshot file\n")
        let command = ["/bin/bash", "-lc", "echo hello"]

        let rewritten = ShellSnapshotCommandWrapper.maybeWrapShellLCWithSnapshot(
            command: command,
            sessionShell: shell,
            cwd: directory.appendingPathComponent("."),
            explicitEnvOverrides: [:],
            environment: [:]
        )

        XCTAssertNotEqual(rewritten, command)
    }

    func testSnapshotCommandWrapperRestoresExplicitOverridePrecedence() throws {
        let directory = try temporaryDirectory()
        let shell = try shellWithSnapshot(
            directory: directory,
            contents: "# Snapshot file\nexport TEST_ENV_SNAPSHOT=global\nexport SNAPSHOT_ONLY=from_snapshot\n"
        )
        let command = [
            "/bin/bash",
            "-lc",
            #"printf '%s|%s' "$TEST_ENV_SNAPSHOT" "${SNAPSHOT_ONLY-unset}""#
        ]
        let rewritten = ShellSnapshotCommandWrapper.maybeWrapShellLCWithSnapshot(
            command: command,
            sessionShell: shell,
            cwd: directory,
            explicitEnvOverrides: ["TEST_ENV_SNAPSHOT": "worktree"],
            environment: ["TEST_ENV_SNAPSHOT": "worktree"]
        )

        let output = try run(
            executable: rewritten[0],
            arguments: Array(rewritten.dropFirst()),
            environment: ["BASH_ENV": "/dev/null", "TEST_ENV_SNAPSHOT": "worktree"],
            cwd: directory
        )

        XCTAssertEqual(output, "worktree|from_snapshot")
    }

    func testSnapshotCommandWrapperRestoresCodexThreadIDFromEnv() throws {
        let directory = try temporaryDirectory()
        let shell = try shellWithSnapshot(
            directory: directory,
            contents: "# Snapshot file\nexport CODEX_THREAD_ID='parent-thread'\n"
        )
        let command = ["/bin/bash", "-lc", #"printf '%s' "$CODEX_THREAD_ID""#]
        let rewritten = ShellSnapshotCommandWrapper.maybeWrapShellLCWithSnapshot(
            command: command,
            sessionShell: shell,
            cwd: directory,
            explicitEnvOverrides: [:],
            environment: ["CODEX_THREAD_ID": "nested-thread"]
        )

        let output = try run(
            executable: rewritten[0],
            arguments: Array(rewritten.dropFirst()),
            environment: ["BASH_ENV": "/dev/null", "CODEX_THREAD_ID": "nested-thread"],
            cwd: directory
        )

        XCTAssertEqual(output, "nested-thread")
    }

    func testSnapshotCommandWrapperDoesNotEmbedOverrideValuesInArgv() throws {
        let directory = try temporaryDirectory()
        let shell = try shellWithSnapshot(
            directory: directory,
            contents: "# Snapshot file\nexport OPENAI_API_KEY='snapshot-value'\n"
        )
        let command = ["/bin/bash", "-lc", #"printf '%s' "$OPENAI_API_KEY""#]
        let rewritten = ShellSnapshotCommandWrapper.maybeWrapShellLCWithSnapshot(
            command: command,
            sessionShell: shell,
            cwd: directory,
            explicitEnvOverrides: ["OPENAI_API_KEY": "super-secret-value"],
            environment: ["OPENAI_API_KEY": "super-secret-value"]
        )

        XCTAssertFalse(rewritten[2].contains("super-secret-value"))
        let output = try run(
            executable: rewritten[0],
            arguments: Array(rewritten.dropFirst()),
            environment: ["BASH_ENV": "/dev/null", "OPENAI_API_KEY": "super-secret-value"],
            cwd: directory
        )

        XCTAssertEqual(output, "super-secret-value")
    }

    func testSnapshotCommandWrapperRestoresLiveProxyEnvWhenSnapshotProxyActive() throws {
        let directory = try temporaryDirectory()
        let shell = try shellWithSnapshot(
            directory: directory,
            contents: """
            # Snapshot file
            export CODEX_NETWORK_PROXY_ACTIVE='1'
            export PIP_PROXY='http://127.0.0.1:8080'
            export HTTP_PROXY='http://127.0.0.1:8080'
            """
        )
        let command = [
            "/bin/bash",
            "-lc",
            """
            if [ "${PIP_PROXY+x}" = x ]; then printf 'pip:%s\\n' "$PIP_PROXY"; else printf 'pip:unset\\n'; fi; printf 'http:%s\\n' "$HTTP_PROXY"; if [ "${CODEX_NETWORK_PROXY_ACTIVE+x}" = x ]; then printf 'active:%s' "$CODEX_NETWORK_PROXY_ACTIVE"; else printf 'active:unset'; fi
            """
        ]
        let rewritten = ShellSnapshotCommandWrapper.maybeWrapShellLCWithSnapshot(
            command: command,
            sessionShell: shell,
            cwd: directory,
            explicitEnvOverrides: [:],
            environment: ["HTTP_PROXY": "http://user.proxy:8080"]
        )

        let output = try run(
            executable: rewritten[0],
            arguments: Array(rewritten.dropFirst()),
            environment: ["BASH_ENV": "/dev/null", "HTTP_PROXY": "http://user.proxy:8080"],
            cwd: directory
        )

        XCTAssertEqual(output, "pip:unset\nhttp:http://user.proxy:8080\nactive:unset")
    }
    #endif

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "codex-swift-shell-snapshot-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func writeRolloutStub(codexHome: URL, sessionID: ThreadId) throws {
        let directory = codexHome
            .appendingPathComponent("sessions", isDirectory: true)
            .appendingPathComponent("2025", isDirectory: true)
            .appendingPathComponent("01", isDirectory: true)
            .appendingPathComponent("01", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = directory.appendingPathComponent("rollout-2025-01-01T00-00-00-\(sessionID).jsonl")
        try "".write(to: path, atomically: true, encoding: .utf8)
    }

    private func shellWithSnapshot(directory: URL, cwd: URL? = nil, contents: String) throws -> Shell {
        let snapshotPath = directory.appendingPathComponent("snapshot-\(UUID().uuidString).sh")
        try contents.write(to: snapshotPath, atomically: true, encoding: .utf8)
        let snapshot = ShellSnapshot(path: snapshotPath, cwd: cwd ?? directory)
        return Shell(shellType: .bash, shellPath: "/bin/bash", shellSnapshot: snapshot)
    }

    private func withSanitizedShellHome<T>(_ home: URL, _ body: () throws -> T) throws -> T {
        let oldHome = getenv("HOME").map { String(cString: $0) }
        let oldBashEnv = getenv("BASH_ENV").map { String(cString: $0) }
        setenv("HOME", home.path, 1)
        setenv("BASH_ENV", "/dev/null", 1)
        defer {
            restoreEnvironment(name: "HOME", value: oldHome)
            restoreEnvironment(name: "BASH_ENV", value: oldBashEnv)
        }
        return try body()
    }

    private func restoreEnvironment(name: String, value: String?) {
        if let value {
            setenv(name, value, 1)
        } else {
            unsetenv(name)
        }
    }

    private func run(
        executable: String,
        arguments: [String],
        environment: [String: String],
        cwd: URL
    ) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = cwd
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        let stdoutData = stdout.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderr.fileHandleForReading.readDataToEndOfFile()
        if process.terminationStatus != 0 {
            XCTFail("process failed: \(String(decoding: stderrData, as: UTF8.self))")
        }
        return String(decoding: stdoutData, as: UTF8.self)
    }
}
