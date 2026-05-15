@testable import CodexCore
import XCTest

final class ConfiguredEnvironmentsTests: XCTestCase {
    func testMissingEnvironmentsTomlFallsBackToLegacyExecServerURL() throws {
        let temp = try ConfiguredEnvironmentTemporaryDirectory()

        let snapshot = try ConfiguredEnvironmentLoader.load(
            codexHome: temp.url,
            environment: [
                ConfiguredEnvironmentLoader.codexExecServerURLEnvironmentVariable: " ws://127.0.0.1:8765 "
            ]
        )

        XCTAssertEqual(snapshot.environments.map(\.id), ["local", "remote"])
        XCTAssertEqual(snapshot.environment(id: "remote")?.execServerURL, "ws://127.0.0.1:8765")
        XCTAssertEqual(snapshot.defaultEnvironment, .environmentID("remote"))
        XCTAssertEqual(snapshot.defaultEnvironmentIDs(), ["remote", "local"])
        XCTAssertEqual(snapshot.defaultThreadEnvironmentSelections(cwd: "/repo"), [
            TurnEnvironmentSelection(environmentID: "remote", cwd: "/repo"),
            TurnEnvironmentSelection(environmentID: "local", cwd: "/repo")
        ])
    }

    func testMissingEnvironmentsTomlKeepsLegacyDisabledDefault() throws {
        let temp = try ConfiguredEnvironmentTemporaryDirectory()

        let snapshot = try ConfiguredEnvironmentLoader.load(
            codexHome: temp.url,
            environment: [
                ConfiguredEnvironmentLoader.codexExecServerURLEnvironmentVariable: "none"
            ]
        )

        XCTAssertEqual(snapshot.environments.map(\.id), ["local"])
        XCTAssertEqual(snapshot.defaultEnvironment, .disabled)
        XCTAssertEqual(snapshot.defaultEnvironmentIDs(), [])
    }

    func testInvalidCodexHomePathWrapsEnvironmentConfigInspectErrorLikeRust() throws {
        let temp = try ConfiguredEnvironmentTemporaryDirectory()
        let codexHomeFile = temp.url.appendingPathComponent("codex-home", isDirectory: false)
        try "not a directory".write(to: codexHomeFile, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try ConfiguredEnvironmentLoader.load(
            codexHome: codexHomeFile,
            environment: [
                ConfiguredEnvironmentLoader.codexExecServerURLEnvironmentVariable: "ws://legacy.example"
            ]
        )) { error in
            let description = (error as? ConfiguredEnvironmentLoadError)?.description ?? ""
            XCTAssertTrue(description.contains("failed to inspect environment config"))
            XCTAssertTrue(description.contains("environments.toml"))
        }
    }

    func testLoadCodexHomeEnvironmentsTomlUsesDefaultFirstSelections() throws {
        let temp = try ConfiguredEnvironmentTemporaryDirectory()
        try """
        default = "dev"

        [[environments]]
        id = "dev"
        program = "ssh"
        args = ["dev", "cd /tmp && codex exec-server --listen stdio"]
        """.write(
            to: temp.url.appendingPathComponent("environments.toml", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )

        let selections = try ConfiguredEnvironmentLoader.defaultThreadEnvironmentSelections(
            codexHome: temp.url,
            cwd: "/workspace",
            environment: [
                ConfiguredEnvironmentLoader.codexExecServerURLEnvironmentVariable: "ws://legacy.example"
            ]
        )

        XCTAssertEqual(selections, [
            TurnEnvironmentSelection(environmentID: "dev", cwd: "/workspace"),
            TurnEnvironmentSelection(environmentID: "local", cwd: "/workspace")
        ])
    }

    func testLoadCodexHomeEnvironmentsTomlKeepsConfiguredEnvironmentsWhenLocalIsDefault() throws {
        let temp = try ConfiguredEnvironmentTemporaryDirectory()
        try """
        default = "local"

        [[environments]]
        id = "dev"
        program = "ssh"

        [[environments]]
        id = "qa"
        url = "ws://127.0.0.1:4512"
        """.write(
            to: temp.url.appendingPathComponent("environments.toml", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )

        let snapshot = try ConfiguredEnvironmentLoader.load(codexHome: temp.url, environment: [
            ConfiguredEnvironmentLoader.codexExecServerURLEnvironmentVariable: "ws://legacy.example"
        ])

        XCTAssertEqual(snapshot.environments.map(\.id), ["local", "dev", "qa"])
        XCTAssertEqual(snapshot.defaultEnvironmentIDs(), ["local", "dev", "qa"])
        XCTAssertEqual(snapshot.defaultThreadEnvironmentSelections(cwd: "/workspace"), [
            TurnEnvironmentSelection(environmentID: "local", cwd: "/workspace"),
            TurnEnvironmentSelection(environmentID: "dev", cwd: "/workspace"),
            TurnEnvironmentSelection(environmentID: "qa", cwd: "/workspace")
        ])
    }

    func testLoadCodexHomeEnvironmentsTomlKeepsConfiguredEnvironmentsWhenDefaultIsOmitted() throws {
        let temp = try ConfiguredEnvironmentTemporaryDirectory()
        try """
        [[environments]]
        id = "dev"
        program = "ssh"

        [[environments]]
        id = "qa"
        url = "ws://127.0.0.1:4512"
        """.write(
            to: temp.url.appendingPathComponent("environments.toml", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )

        let snapshot = try ConfiguredEnvironmentLoader.load(codexHome: temp.url, environment: [:])

        XCTAssertEqual(snapshot.environments.map(\.id), ["local", "dev", "qa"])
        XCTAssertEqual(snapshot.defaultEnvironment, .environmentID("local"))
        XCTAssertEqual(snapshot.defaultThreadEnvironmentSelections(cwd: "/workspace"), [
            TurnEnvironmentSelection(environmentID: "local", cwd: "/workspace"),
            TurnEnvironmentSelection(environmentID: "dev", cwd: "/workspace"),
            TurnEnvironmentSelection(environmentID: "qa", cwd: "/workspace")
        ])
    }

    func testEnvironmentContextEnvironmentsUseDefaultFirstSelections() throws {
        let snapshot = try ConfiguredEnvironmentLoader.snapshot(fromToml: """
        default = "dev"

        [[environments]]
        id = "dev"
        program = "ssh"

        [[environments]]
        id = "qa"
        url = "ws://127.0.0.1:4512"
        """)

        XCTAssertEqual(
            snapshot.environmentContextEnvironments(cwd: "/workspace", shell: Shell(shellType: .zsh, shellPath: "/bin/zsh")),
            [
                EnvironmentContextEnvironment(id: "dev", cwd: "/workspace", shell: "zsh"),
                EnvironmentContextEnvironment(id: "local", cwd: "/workspace", shell: "zsh"),
                EnvironmentContextEnvironment(id: "qa", cwd: "/workspace", shell: "zsh")
            ]
        )
    }

    func testEnvironmentContextEnvironmentsUseInheritedShellNameLikeRust() throws {
        let snapshot = try ConfiguredEnvironmentLoader.snapshot(fromToml: """
        default = "dev"

        [[environments]]
        id = "dev"
        program = "ssh"
        """)

        XCTAssertEqual(
            snapshot.environmentContextEnvironments(
                cwd: "/workspace",
                shell: Shell(shellType: .powerShell, shellPath: "pwsh.exe")
            ),
            [
                EnvironmentContextEnvironment(id: "dev", cwd: "/workspace", shell: "powershell"),
                EnvironmentContextEnvironment(id: "local", cwd: "/workspace", shell: "powershell")
            ]
        )
    }

    func testLegacySnapshotStillExpandsRemoteBeforeLocalForExecServerURL() {
        let snapshot = ConfiguredEnvironmentLoader.legacyEnvironmentSnapshot(environment: [
            ConfiguredEnvironmentLoader.codexExecServerURLEnvironmentVariable: "ws://127.0.0.1:8765"
        ])

        XCTAssertEqual(snapshot.defaultEnvironmentIDs(), ["remote", "local"])
        XCTAssertEqual(
            snapshot.environmentContextEnvironments(cwd: "/workspace", shell: Shell(shellType: .bash, shellPath: "/bin/bash")),
            [
                EnvironmentContextEnvironment(id: "remote", cwd: "/workspace", shell: "bash"),
                EnvironmentContextEnvironment(id: "local", cwd: "/workspace", shell: "bash")
            ]
        )
    }

    func testLoadCodexHomeEnvironmentsTomlParsesWebsocketAndStdioEntries() throws {
        let temp = try ConfiguredEnvironmentTemporaryDirectory()
        try """
        default = "ssh-dev"

        [[environments]]
        id = "devbox"
        url = " ws://127.0.0.1:4512 "

        [[environments]]
        id = "ssh-dev"
        program = " ssh "
        args = ["dev", "codex exec-server --listen stdio"]
        cwd = "workspace"
        [environments.env]
        CODEX_LOG = "debug"
        """.write(
            to: temp.url.appendingPathComponent("environments.toml", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )

        let snapshot = try ConfiguredEnvironmentLoader.load(codexHome: temp.url, environment: [:])

        XCTAssertEqual(snapshot.environments.map(\.id), ["local", "devbox", "ssh-dev"])
        XCTAssertEqual(snapshot.environment(id: "devbox")?.execServerURL, "ws://127.0.0.1:4512")
        XCTAssertEqual(snapshot.defaultEnvironmentIDs(), ["ssh-dev", "local", "devbox"])
        XCTAssertEqual(
            snapshot.environment(id: "ssh-dev")?.transport,
            .stdio(StdioConfiguredEnvironmentCommand(
                program: "ssh",
                args: ["dev", "codex exec-server --listen stdio"],
                env: ["CODEX_LOG": "debug"],
                cwd: temp.url.appendingPathComponent("workspace", isDirectory: true).standardizedFileURL.path
            ))
        )
    }

    func testEnvironmentsTomlAcceptsMultilineLiteralsLikeRustToml() throws {
        let snapshot = try ConfiguredEnvironmentLoader.snapshot(fromToml: """
        [[environments]]
        id = "ssh-dev"
        program = "ssh"
        args = [
          "dev",
          "codex exec-server --listen stdio",
        ]
        env = {
          CODEX_LOG = "debug",
          CODEX_TRACE = "1",
        }
        """)

        XCTAssertEqual(
            snapshot.environment(id: "ssh-dev")?.transport,
            .stdio(StdioConfiguredEnvironmentCommand(
                program: "ssh",
                args: ["dev", "codex exec-server --listen stdio"],
                env: ["CODEX_LOG": "debug", "CODEX_TRACE": "1"],
                cwd: nil
            ))
        )
    }

    func testEnvironmentsTomlDefaultOmittedSelectsLocalAndNoneDisablesDefault() throws {
        let localSnapshot = try ConfiguredEnvironmentLoader.snapshot(fromToml: "")
        XCTAssertEqual(localSnapshot.defaultEnvironment, .environmentID("local"))
        XCTAssertEqual(localSnapshot.defaultEnvironmentIDs(), ["local"])

        let disabledSnapshot = try ConfiguredEnvironmentLoader.snapshot(fromToml: #"default = "none""#)
        XCTAssertEqual(disabledSnapshot.defaultEnvironment, .disabled)
        XCTAssertEqual(disabledSnapshot.defaultEnvironmentIDs(), [])
    }

    func testEnvironmentsTomlRejectsInvalidEnvironmentDefinitions() throws {
        let cases: [(String, String)] = [
            (
                """
                [[environments]]
                id = "local"
                url = "ws://127.0.0.1:8765"
                """,
                "environment id `local` is reserved"
            ),
            (
                """
                [[environments]]
                id = " devbox "
                url = "ws://127.0.0.1:8765"
                """,
                "environment id ` devbox ` must not contain surrounding whitespace"
            ),
            (
                """
                [[environments]]
                id = "dev box"
                url = "ws://127.0.0.1:8765"
                """,
                "environment id `dev box` must contain only ASCII letters, numbers, '-' or '_'"
            ),
            (
                """
                [[environments]]
                id = "devbox"
                url = "http://127.0.0.1:8765"
                """,
                "environment url `http://127.0.0.1:8765` must use ws:// or wss://"
            ),
            (
                """
                [[environments]]
                id = "devbox"
                url = "ws://127.0.0.1:8765"
                program = "codex"
                """,
                "environment `devbox` must set exactly one of url or program"
            ),
            (
                """
                [[environments]]
                id = "devbox"
                program = " "
                """,
                "environment `devbox` program cannot be empty"
            ),
            (
                """
                [[environments]]
                id = "devbox"
                args = []
                """,
                "environment `devbox` args, env, and cwd require program"
            )
        ]

        for (toml, expected) in cases {
            XCTAssertThrowsError(try ConfiguredEnvironmentLoader.snapshot(fromToml: toml)) { error in
                XCTAssertEqual((error as? ConfiguredEnvironmentLoadError)?.description, "exec-server protocol error: \(expected)")
            }
        }
    }

    func testEnvironmentsTomlRejectsDuplicateUnknownDefaultAndMalformedURL() throws {
        XCTAssertThrowsError(try ConfiguredEnvironmentLoader.snapshot(fromToml: """
        [[environments]]
        id = "devbox"
        url = "ws://127.0.0.1:8765"

        [[environments]]
        id = "devbox"
        program = "codex"
        """)) { error in
            XCTAssertEqual(
                (error as? ConfiguredEnvironmentLoadError)?.description,
                "exec-server protocol error: environment id `devbox` is duplicated"
            )
        }

        XCTAssertThrowsError(try ConfiguredEnvironmentLoader.snapshot(fromToml: #"default = "missing""#)) { error in
            XCTAssertEqual(
                (error as? ConfiguredEnvironmentLoadError)?.description,
                "exec-server protocol error: default environment `missing` is not configured"
            )
        }

        XCTAssertThrowsError(try ConfiguredEnvironmentLoader.snapshot(fromToml: """
        [[environments]]
        id = "devbox"
        url = "ws://"
        """)) { error in
            XCTAssertEqual(
                (error as? ConfiguredEnvironmentLoadError)?.description,
                "exec-server protocol error: environment url `ws://` is invalid: HTTP format error: empty string"
            )
        }

        let highPortSnapshot = try ConfiguredEnvironmentLoader.snapshot(fromToml: """
        [[environments]]
        id = "devbox"
        url = "ws://127.0.0.1:99999"
        """)
        XCTAssertEqual(
            highPortSnapshot.environment(id: "devbox")?.transport,
            .websocketURL("ws://127.0.0.1:99999")
        )
    }

    func testEnvironmentsTomlRejectsOverlongIDEmptyDefaultAndRelativeCwdWithoutConfigDir() throws {
        let overlongID = String(repeating: "a", count: ConfiguredEnvironmentLoader.maxEnvironmentIDLength + 1)
        let cases: [(String, String)] = [
            (
                """
                [[environments]]
                id = "\(overlongID)"
                url = "ws://127.0.0.1:8765"
                """,
                "environment id `\(overlongID)` cannot be longer than \(ConfiguredEnvironmentLoader.maxEnvironmentIDLength) characters"
            ),
            (
                #"default = " ""#,
                "default environment id cannot be empty"
            ),
            (
                """
                [[environments]]
                id = "ssh-dev"
                program = "ssh"
                cwd = "workspace"
                """,
                "environment `ssh-dev` cwd must be absolute"
            )
        ]

        for (toml, expected) in cases {
            XCTAssertThrowsError(try ConfiguredEnvironmentLoader.snapshot(fromToml: toml)) { error in
                XCTAssertEqual((error as? ConfiguredEnvironmentLoadError)?.description, "exec-server protocol error: \(expected)")
            }
        }
    }

    func testEnvironmentIDLengthUsesRustByteLimitBeforeASCIIValidation() throws {
        let overlongMultiByteID = String(repeating: "é", count: 33)

        XCTAssertThrowsError(try ConfiguredEnvironmentLoader.snapshot(fromToml: """
        [[environments]]
        id = "\(overlongMultiByteID)"
        url = "ws://127.0.0.1:8765"
        """)) { error in
            XCTAssertEqual(
                (error as? ConfiguredEnvironmentLoadError)?.description,
                "exec-server protocol error: environment id `\(overlongMultiByteID)` cannot be longer than \(ConfiguredEnvironmentLoader.maxEnvironmentIDLength) characters"
            )
        }
    }

    func testLoadEnvironmentsTomlWrapsUnknownFieldAsParseError() throws {
        let temp = try ConfiguredEnvironmentTemporaryDirectory()
        try """
        [[environments]]
        id = "devbox"
        url = "ws://127.0.0.1:4512"
        unknown = true
        """.write(
            to: temp.url.appendingPathComponent("environments.toml", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )

        XCTAssertThrowsError(try ConfiguredEnvironmentLoader.load(codexHome: temp.url)) { error in
            let description = (error as? ConfiguredEnvironmentLoadError)?.description ?? ""
            XCTAssertTrue(description.contains("failed to parse environment config"))
            XCTAssertTrue(description.contains("unknown field `unknown`"))
        }
    }

    func testEnvironmentsTomlRejectsDuplicateKeysLikeRustToml() throws {
        let directCases: [(String, String)] = [
            (
                """
                [[environments]]
                id = "devbox"
                id = "other"
                url = "ws://127.0.0.1:4512"
                """,
                "duplicate key `id`"
            ),
            (
                """
                [[environments]]
                id = "devbox"
                program = "ssh"
                [environments.env]
                CODEX_LOG = "debug"
                CODEX_LOG = "trace"
                """,
                "duplicate key `CODEX_LOG`"
            ),
            (
                """
                [[environments]]
                id = "devbox"
                program = "ssh"
                env = { CODEX_LOG = "debug" }
                [environments.env]
                CODEX_TRACE = "1"
                """,
                "duplicate key `env`"
            )
        ]

        for (toml, expected) in directCases {
            XCTAssertThrowsError(try ConfiguredEnvironmentLoader.snapshot(fromToml: toml)) { error in
                XCTAssertEqual(
                    (error as? ConfiguredEnvironmentLoadError)?.description,
                    "exec-server protocol error: \(expected)"
                )
            }
        }

        let temp = try ConfiguredEnvironmentTemporaryDirectory()
        try """
        default = "local"
        default = "none"
        """.write(
            to: temp.url.appendingPathComponent("environments.toml", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )

        XCTAssertThrowsError(try ConfiguredEnvironmentLoader.load(codexHome: temp.url)) { error in
            let description = (error as? ConfiguredEnvironmentLoadError)?.description ?? ""
            XCTAssertTrue(description.contains("failed to parse environment config"))
            XCTAssertTrue(description.contains("duplicate key `default`"))
        }
    }

    func testEmptyEnvironmentEnvTableRequiresProgramLikeRustSerde() throws {
        XCTAssertThrowsError(try ConfiguredEnvironmentLoader.snapshot(fromToml: """
        [[environments]]
        id = "devbox"
        [environments.env]
        """)) { error in
            XCTAssertEqual(
                (error as? ConfiguredEnvironmentLoadError)?.description,
                "exec-server protocol error: environment `devbox` args, env, and cwd require program"
            )
        }
    }
}

private final class ConfiguredEnvironmentTemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}
