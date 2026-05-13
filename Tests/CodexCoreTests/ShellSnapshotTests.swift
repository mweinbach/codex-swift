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

    func testSnapshotShellDoesNotInheritStdin() throws {
        let stdinGuard = try BlockingStdinPipe.install()
        defer { _ = stdinGuard }
        let directory = try temporaryDirectory()
        let readStatusPath = directory.appendingPathComponent("stdin-read-status")
        let bashrc = """
        read -t 1 -r ignored
        printf '%s' "$?" > "\(readStatusPath.path)"
        """
        try bashrc.write(to: directory.appendingPathComponent(".bashrc"), atomically: true, encoding: .utf8)

        let output = try withSanitizedShellHome(directory, bashEnv: nil) {
            try ShellSnapshot.captureSnapshot(
                shell: Shell(shellType: .bash, shellPath: "/bin/bash"),
                cwd: directory
            )
        }
        let readStatus = try String(contentsOf: readStatusPath, encoding: .utf8)

        XCTAssertEqual(
            readStatus,
            "1",
            "expected shell startup read to see EOF on stdin; status=\(readStatus)"
        )
        XCTAssertTrue(output.contains("# Snapshot file"))
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

    func testCleanupStaleSnapshotsRemovesStaleRollouts() throws {
        let directory = try temporaryDirectory()
        let snapshotDirectory = directory.appendingPathComponent(ShellSnapshot.directoryName, isDirectory: true)
        try FileManager.default.createDirectory(at: snapshotDirectory, withIntermediateDirectories: true)

        let staleSession = ThreadId()
        let staleSnapshot = snapshotDirectory.appendingPathComponent("\(staleSession).123.sh")
        let rolloutPath = try writeRolloutStub(codexHome: directory, sessionID: staleSession)
        try "stale".write(to: staleSnapshot, atomically: true, encoding: .utf8)

        try setModificationDate(Date().addingTimeInterval(-(ShellSnapshot.retention + 60)), for: rolloutPath)
        try ShellSnapshot.cleanupStaleSnapshots(codexHome: directory, activeSessionID: ThreadId())

        XCTAssertFalse(FileManager.default.fileExists(atPath: staleSnapshot.path))
    }

    func testCleanupStaleSnapshotsUsesStateStoreRolloutPath() async throws {
        let directory = try temporaryDirectory()
        let snapshotDirectory = directory.appendingPathComponent(ShellSnapshot.directoryName, isDirectory: true)
        try FileManager.default.createDirectory(at: snapshotDirectory, withIntermediateDirectories: true)

        let session = ThreadId()
        let snapshot = snapshotDirectory.appendingPathComponent("\(session).123.sh")
        try "state".write(to: snapshot, atomically: true, encoding: .utf8)

        let rolloutDirectory = directory.appendingPathComponent("state-rollouts", isDirectory: true)
        try FileManager.default.createDirectory(at: rolloutDirectory, withIntermediateDirectories: true)
        let rolloutPath = rolloutDirectory.appendingPathComponent("rollout-\(session).jsonl")
        try "".write(to: rolloutPath, atomically: true, encoding: .utf8)

        let store = try SQLiteAgentGraphStore(databaseURL: directory.appendingPathComponent("state.sqlite3"))
        try await store.upsertThread(threadMetadata(id: session, rolloutPath: rolloutPath))

        try await ShellSnapshot.cleanupStaleSnapshots(
            codexHome: directory,
            activeSessionID: ThreadId(),
            threadLookup: store
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: snapshot.path))

        try setModificationDate(Date().addingTimeInterval(-(ShellSnapshot.retention + 60)), for: rolloutPath)
        try await ShellSnapshot.cleanupStaleSnapshots(
            codexHome: directory,
            activeSessionID: ThreadId(),
            threadLookup: store
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: snapshot.path))
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

    func testSnapshotCommandWrapperRestoresProxyEnvFromProcessEnv() throws {
        let directory = try temporaryDirectory()
        let shell = try shellWithSnapshot(
            directory: directory,
            contents: """
            # Snapshot file
            export PIP_PROXY='http://127.0.0.1:8080'
            export HTTP_PROXY='http://127.0.0.1:8080'
            export http_proxy='http://127.0.0.1:8080'
            export GIT_SSH_COMMAND='ssh -o ProxyCommand=stale'
            """
        )
        let command = [
            "/bin/bash",
            "-lc",
            #"printf '%s\n%s\n%s\n%s' "$PIP_PROXY" "$HTTP_PROXY" "$http_proxy" "$GIT_SSH_COMMAND""#
        ]
        let rewritten = ShellSnapshotCommandWrapper.maybeWrapShellLCWithSnapshot(
            command: command,
            sessionShell: shell,
            cwd: directory,
            explicitEnvOverrides: [:],
            environment: [:]
        )

        let output = try run(
            executable: rewritten[0],
            arguments: Array(rewritten.dropFirst()),
            environment: [
                "BASH_ENV": "/dev/null",
                ShellSnapshotCommandWrapper.proxyActiveEnvKey: "1",
                "PIP_PROXY": "http://127.0.0.1:4321",
                "HTTP_PROXY": "http://127.0.0.1:4321",
                "http_proxy": "http://127.0.0.1:4321",
                ShellSnapshotCommandWrapper.proxyGitSSHCommandEnvKey: "ssh -o ProxyCommand=fresh"
            ],
            cwd: directory
        )

        XCTAssertEqual(
            output,
            "http://127.0.0.1:4321\nhttp://127.0.0.1:4321\nhttp://127.0.0.1:4321\nssh -o ProxyCommand=stale"
        )
    }

    func testSnapshotCommandWrapperKeepsUserProxyEnvWhenProxyInactive() throws {
        let directory = try temporaryDirectory()
        let shell = try shellWithSnapshot(
            directory: directory,
            contents: "# Snapshot file\nexport HTTP_PROXY='http://user.proxy:8080'\n"
        )
        let command = ["/bin/bash", "-lc", #"printf '%s' "$HTTP_PROXY""#]
        let rewritten = ShellSnapshotCommandWrapper.maybeWrapShellLCWithSnapshot(
            command: command,
            sessionShell: shell,
            cwd: directory,
            explicitEnvOverrides: [:],
            environment: [:]
        )

        let output = try run(
            executable: rewritten[0],
            arguments: Array(rewritten.dropFirst()),
            environment: ["BASH_ENV": "/dev/null"],
            removingEnvironment: ShellSnapshotCommandWrapper.proxyEnvKeys,
            cwd: directory
        )

        XCTAssertEqual(output, "http://user.proxy:8080")
    }

    func testSnapshotCommandWrapperKeepsSnapshotPathWithoutOverride() throws {
        let directory = try temporaryDirectory()
        let shell = try shellWithSnapshot(
            directory: directory,
            contents: "# Snapshot file\nexport PATH='/snapshot/bin'\n"
        )
        let command = ["/bin/bash", "-lc", #"printf '%s' "$PATH""#]
        let rewritten = ShellSnapshotCommandWrapper.maybeWrapShellLCWithSnapshot(
            command: command,
            sessionShell: shell,
            cwd: directory,
            explicitEnvOverrides: [:],
            environment: [:]
        )

        let output = try run(
            executable: rewritten[0],
            arguments: Array(rewritten.dropFirst()),
            environment: ["BASH_ENV": "/dev/null"],
            cwd: directory
        )

        XCTAssertEqual(output, "/snapshot/bin")
    }

    func testSnapshotCommandWrapperAppliesExplicitPathOverride() throws {
        let directory = try temporaryDirectory()
        let shell = try shellWithSnapshot(
            directory: directory,
            contents: "# Snapshot file\nexport PATH='/snapshot/bin'\n"
        )
        let command = ["/bin/bash", "-lc", #"printf '%s' "$PATH""#]
        let rewritten = ShellSnapshotCommandWrapper.maybeWrapShellLCWithSnapshot(
            command: command,
            sessionShell: shell,
            cwd: directory,
            explicitEnvOverrides: ["PATH": "/worktree/bin"],
            environment: ["PATH": "/worktree/bin"]
        )

        let output = try run(
            executable: rewritten[0],
            arguments: Array(rewritten.dropFirst()),
            environment: ["BASH_ENV": "/dev/null", "PATH": "/worktree/bin"],
            cwd: directory
        )

        XCTAssertEqual(output, "/worktree/bin")
    }

    func testSnapshotCommandWrapperPreservesUnsetOverrideVariables() throws {
        let directory = try temporaryDirectory()
        let shell = try shellWithSnapshot(
            directory: directory,
            contents: "# Snapshot file\nexport CODEX_TEST_UNSET_OVERRIDE='snapshot-value'\n"
        )
        let command = [
            "/bin/bash",
            "-lc",
            #"if [ "${CODEX_TEST_UNSET_OVERRIDE+x}" = x ]; then printf 'set:%s' "$CODEX_TEST_UNSET_OVERRIDE"; else printf 'unset'; fi"#
        ]
        let rewritten = ShellSnapshotCommandWrapper.maybeWrapShellLCWithSnapshot(
            command: command,
            sessionShell: shell,
            cwd: directory,
            explicitEnvOverrides: ["CODEX_TEST_UNSET_OVERRIDE": "worktree-value"],
            environment: [:]
        )

        let output = try run(
            executable: rewritten[0],
            arguments: Array(rewritten.dropFirst()),
            environment: ["BASH_ENV": "/dev/null"],
            removingEnvironment: ["CODEX_TEST_UNSET_OVERRIDE"],
            cwd: directory
        )

        XCTAssertEqual(output, "unset")
    }

    #if os(macOS)
    func testSnapshotCommandWrapperRefreshesCodexProxyGitSSHCommand() throws {
        let directory = try temporaryDirectory()
        let staleCommand = "\(ShellSnapshotCommandWrapper.codexProxyGitSSHCommandMarker)ssh -o ProxyCommand='nc -X 5 -x 127.0.0.1:8081 %h %p'"
        let freshCommand = "\(ShellSnapshotCommandWrapper.codexProxyGitSSHCommandMarker)ssh -o ProxyCommand='nc -X 5 -x 127.0.0.1:48081 %h %p'"
        let shell = try shellWithSnapshot(
            directory: directory,
            contents: "# Snapshot file\nexport GIT_SSH_COMMAND='\(ShellSnapshotCommandWrapper.shellSingleQuote(staleCommand))'\n"
        )
        let command = ["/bin/bash", "-lc", #"printf '%s' "$GIT_SSH_COMMAND""#]
        let rewritten = ShellSnapshotCommandWrapper.maybeWrapShellLCWithSnapshot(
            command: command,
            sessionShell: shell,
            cwd: directory,
            explicitEnvOverrides: [:],
            environment: [:]
        )

        let output = try run(
            executable: rewritten[0],
            arguments: Array(rewritten.dropFirst()),
            environment: [
                "BASH_ENV": "/dev/null",
                ShellSnapshotCommandWrapper.proxyGitSSHCommandEnvKey: freshCommand
            ],
            cwd: directory
        )

        XCTAssertEqual(output, freshCommand)
    }

    func testSnapshotCommandWrapperClearsStaleCodexProxyGitSSHCommandWithoutLiveCommand() throws {
        let directory = try temporaryDirectory()
        let staleCommand = "\(ShellSnapshotCommandWrapper.codexProxyGitSSHCommandMarker)ssh -o ProxyCommand='nc -X 5 -x 127.0.0.1:8081 %h %p'"
        let shell = try shellWithSnapshot(
            directory: directory,
            contents: "# Snapshot file\nexport GIT_SSH_COMMAND='\(ShellSnapshotCommandWrapper.shellSingleQuote(staleCommand))'\n"
        )
        let command = [
            "/bin/bash",
            "-lc",
            #"if [ "${GIT_SSH_COMMAND+x}" = x ]; then printf 'set'; else printf 'unset'; fi"#
        ]
        let rewritten = ShellSnapshotCommandWrapper.maybeWrapShellLCWithSnapshot(
            command: command,
            sessionShell: shell,
            cwd: directory,
            explicitEnvOverrides: [:],
            environment: [:]
        )

        let output = try run(
            executable: rewritten[0],
            arguments: Array(rewritten.dropFirst()),
            environment: ["BASH_ENV": "/dev/null"],
            removingEnvironment: [ShellSnapshotCommandWrapper.proxyGitSSHCommandEnvKey],
            cwd: directory
        )

        XCTAssertEqual(output, "unset")
    }
    #endif
    #endif

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "codex-swift-shell-snapshot-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @discardableResult
    private func writeRolloutStub(codexHome: URL, sessionID: ThreadId) throws -> URL {
        let directory = codexHome
            .appendingPathComponent("sessions", isDirectory: true)
            .appendingPathComponent("2025", isDirectory: true)
            .appendingPathComponent("01", isDirectory: true)
            .appendingPathComponent("01", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = directory.appendingPathComponent("rollout-2025-01-01T00-00-00-\(sessionID).jsonl")
        try "".write(to: path, atomically: true, encoding: .utf8)
        return path
    }

    private func shellWithSnapshot(directory: URL, cwd: URL? = nil, contents: String) throws -> Shell {
        let snapshotPath = directory.appendingPathComponent("snapshot-\(UUID().uuidString).sh")
        try contents.write(to: snapshotPath, atomically: true, encoding: .utf8)
        let snapshot = ShellSnapshot(path: snapshotPath, cwd: cwd ?? directory)
        return Shell(shellType: .bash, shellPath: "/bin/bash", shellSnapshot: snapshot)
    }

    private func withSanitizedShellHome<T>(
        _ home: URL,
        bashEnv: String? = "/dev/null",
        _ body: () throws -> T
    ) throws -> T {
        let oldHome = getenv("HOME").map { String(cString: $0) }
        let oldBashEnv = getenv("BASH_ENV").map { String(cString: $0) }
        setenv("HOME", home.path, 1)
        if let bashEnv {
            setenv("BASH_ENV", bashEnv, 1)
        } else {
            unsetenv("BASH_ENV")
        }
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

    private func setModificationDate(_ date: Date, for path: URL) throws {
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: path.path)
    }

    private func threadMetadata(id: ThreadId, rolloutPath: URL, updatedAt: Date = Date()) -> ThreadMetadata {
        ThreadMetadata(
            id: id,
            rolloutPath: rolloutPath.path,
            createdAt: updatedAt,
            updatedAt: updatedAt,
            source: "cli",
            modelProvider: "openai",
            cwd: rolloutPath.deletingLastPathComponent().path,
            cliVersion: "0.0.0-test",
            title: "Shell snapshot state lookup",
            sandboxPolicy: "workspace-write",
            approvalMode: "on-request",
            tokensUsed: 0
        )
    }

    private final class BlockingStdinPipe {
        private let original: Int32
        private let writeEnd: Int32

        private init(original: Int32, writeEnd: Int32) {
            self.original = original
            self.writeEnd = writeEnd
        }

        static func install() throws -> BlockingStdinPipe {
            var descriptors = [Int32](repeating: 0, count: 2)
            guard pipe(&descriptors) == 0 else {
                throw posixError("create stdin pipe")
            }

            let original = dup(STDIN_FILENO)
            guard original != -1 else {
                let error = posixError("dup stdin")
                close(descriptors[0])
                close(descriptors[1])
                throw error
            }

            guard dup2(descriptors[0], STDIN_FILENO) != -1 else {
                let error = posixError("replace stdin")
                close(descriptors[0])
                close(descriptors[1])
                close(original)
                throw error
            }

            close(descriptors[0])
            return BlockingStdinPipe(original: original, writeEnd: descriptors[1])
        }

        deinit {
            dup2(original, STDIN_FILENO)
            close(original)
            close(writeEnd)
        }

        private static func posixError(_ operation: String) -> NSError {
            NSError(
                domain: NSPOSIXErrorDomain,
                code: Int(errno),
                userInfo: [NSLocalizedDescriptionKey: operation]
            )
        }
    }

    private func run(
        executable: String,
        arguments: [String],
        environment: [String: String],
        removingEnvironment environmentRemovals: [String] = [],
        cwd: URL
    ) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = cwd
        var processEnvironment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
        for key in environmentRemovals {
            processEnvironment.removeValue(forKey: key)
        }
        process.environment = processEnvironment

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
