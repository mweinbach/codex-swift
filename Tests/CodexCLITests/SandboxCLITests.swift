import CodexCLI
import CodexCore
import XCTest

final class SandboxCLITests: XCTestCase {
    func testRunAsyncSandboxMacosDelegatesToRunnerWithFlagsAndOverrides() async {
        var stdout: [String] = []
        var stderr: [String] = []
        var receivedRequest: CodexCLI.SandboxCommandRequest?

        let exitCode = await CodexCLI().runAsync(
            arguments: [
                "-c",
                "sandbox_mode=\"read-only\"",
                "sandbox",
                "macos",
                "--log-denials",
                "echo",
                "hello"
            ],
            stdout: { stdout.append($0) },
            stderr: { stderr.append($0) },
            sandboxRunner: { request in
                receivedRequest = request
                return CodexCLI.CommandExecutionResult(exitCode: 0, stdoutMessage: "hello")
            }
        )

        XCTAssertEqual(exitCode, 0)
        XCTAssertEqual(stdout, ["hello"])
        XCTAssertTrue(stderr.isEmpty)
        XCTAssertEqual(
            receivedRequest,
            CodexCLI.SandboxCommandRequest(
                action: .macos(
                    profile: CodexCLI.SandboxProfileOptions(),
                    allowUnixSockets: [],
                    logDenials: true,
                    command: ["echo", "hello"]
                ),
                configOverrides: CliConfigOverrides(rawOverrides: ["sandbox_mode=\"read-only\""])
            )
        )
    }

    func testRunAsyncSandboxAliasesMatchRustSubcommands() async {
        var receivedActions: [CodexCLI.SandboxCommandAction] = []

        let seatbeltExitCode = await CodexCLI().runAsync(
            arguments: ["sandbox", "seatbelt", "echo", "ok"],
            stderr: { _ in XCTFail("stderr should not be written") },
            sandboxRunner: { request in
                receivedActions.append(request.action)
                return CodexCLI.CommandExecutionResult(exitCode: 0)
            }
        )

        let landlockExitCode = await CodexCLI().runAsync(
            arguments: ["sandbox", "landlock", "echo", "ok"],
            stderr: { _ in XCTFail("stderr should not be written") },
            sandboxRunner: { request in
                receivedActions.append(request.action)
                return CodexCLI.CommandExecutionResult(exitCode: 0)
            }
        )

        XCTAssertEqual(seatbeltExitCode, 0)
        XCTAssertEqual(landlockExitCode, 0)
        XCTAssertEqual(receivedActions, [
            .macos(
                profile: CodexCLI.SandboxProfileOptions(),
                allowUnixSockets: [],
                logDenials: false,
                command: ["echo", "ok"]
            ),
            .linux(profile: CodexCLI.SandboxProfileOptions(), command: ["echo", "ok"])
        ])
    }

    func testRunAsyncSandboxParsesRustPermissionProfileOptions() async {
        var receivedActions: [CodexCLI.SandboxCommandAction] = []

        let macosExitCode = await CodexCLI().runAsync(
            arguments: [
                "sandbox",
                "macos",
                "--permissions-profile",
                ":workspace",
                "-C",
                "/tmp/work",
                "--include-managed-config",
                "--allow-unix-socket",
                "/tmp/socket",
                "--",
                "echo",
                "ok"
            ],
            stderr: { _ in XCTFail("stderr should not be written") },
            sandboxRunner: { request in
                receivedActions.append(request.action)
                return CodexCLI.CommandExecutionResult(exitCode: 0)
            }
        )

        let linuxExitCode = await CodexCLI().runAsync(
            arguments: [
                "sandbox",
                "linux",
                "--permissions-profile=:workspace",
                "--cd=/tmp/work",
                "echo",
                "ok"
            ],
            stderr: { _ in XCTFail("stderr should not be written") },
            sandboxRunner: { request in
                receivedActions.append(request.action)
                return CodexCLI.CommandExecutionResult(exitCode: 0)
            }
        )

        XCTAssertEqual(macosExitCode, 0)
        XCTAssertEqual(linuxExitCode, 0)
        XCTAssertEqual(receivedActions, [
            .macos(
                profile: CodexCLI.SandboxProfileOptions(
                    permissionsProfile: ":workspace",
                    cwd: "/tmp/work",
                    includeManagedConfig: true
                ),
                allowUnixSockets: ["/tmp/socket"],
                logDenials: false,
                command: ["echo", "ok"]
            ),
            .linux(
                profile: CodexCLI.SandboxProfileOptions(
                    permissionsProfile: ":workspace",
                    cwd: "/tmp/work"
                ),
                command: ["echo", "ok"]
            )
        ])
    }

    func testSandboxProfileOptionsResolveBuiltInPoliciesLikeRust() throws {
        let workspaceRoot = try AbsolutePath(absolutePath: "/tmp/workspace")
        let configuredWorkspace = SandboxPolicy.workspaceWrite(
            writableRoots: [workspaceRoot],
            networkAccess: true,
            excludeTmpdirEnvVar: true,
            excludeSlashTmp: true
        )

        XCTAssertEqual(
            CodexCLI.SandboxProfileOptions().resolveBuiltInPolicy(defaultPolicy: configuredWorkspace),
            .resolved(configuredWorkspace)
        )
        XCTAssertEqual(
            CodexCLI.SandboxProfileOptions(permissionsProfile: ":read-only")
                .resolveBuiltInPolicy(defaultPolicy: configuredWorkspace),
            .resolved(.readOnly)
        )
        XCTAssertEqual(
            CodexCLI.SandboxProfileOptions(permissionsProfile: ":workspace")
                .resolveBuiltInPolicy(defaultPolicy: configuredWorkspace),
            .resolved(configuredWorkspace)
        )
        XCTAssertEqual(
            CodexCLI.SandboxProfileOptions(permissionsProfile: ":workspace")
                .resolveBuiltInPolicy(defaultPolicy: .readOnly),
            .resolved(.newWorkspaceWritePolicy())
        )
        XCTAssertEqual(
            CodexCLI.SandboxProfileOptions(permissionsProfile: ":danger-full-access")
                .resolveBuiltInPolicy(defaultPolicy: .readOnly),
            .resolved(.dangerFullAccess)
        )
        XCTAssertEqual(
            CodexCLI.SandboxProfileOptions(permissionsProfile: ":danger-no-sandbox")
                .resolveBuiltInPolicy(defaultPolicy: .readOnly),
            .unknownBuiltinProfile(":danger-no-sandbox")
        )
        XCTAssertEqual(
            CodexCLI.SandboxProfileOptions(permissionsProfile: ":typo")
                .resolveBuiltInPolicy(defaultPolicy: .readOnly),
            .unknownBuiltinProfile(":typo")
        )
        XCTAssertEqual(
            CodexCLI.SandboxProfileOptions(permissionsProfile: "limited-read-test")
                .resolveBuiltInPolicy(defaultPolicy: .readOnly),
            .customProfile("limited-read-test")
        )
    }

    func testResolveDebugSandboxConfigurationPreservesWorkspaceWriteSettingsForBuiltInProfile() throws {
        let codexHome = try SandboxTemporaryDirectory()
        let processCwd = try SandboxTemporaryDirectory()
        let workspaceRoot = codexHome.url.appendingPathComponent("allowed", isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceRoot, withIntermediateDirectories: true)
        try """
        profile = "legacy"

        [profiles.legacy]
        sandbox_mode = "danger-full-access"

        [sandbox_workspace_write]
        writable_roots = ["\(workspaceRoot.path)"]
        network_access = true
        exclude_tmpdir_env_var = true
        exclude_slash_tmp = true
        """.write(
            to: codexHome.url.appendingPathComponent("config.toml", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )

        let configuration = try CodexCLI.resolveDebugSandboxConfiguration(
            profile: CodexCLI.SandboxProfileOptions(
                permissionsProfile: ":workspace",
                cwd: "nested"
            ),
            configOverrides: CliConfigOverrides(),
            codexHome: codexHome.url,
            processCwd: processCwd.url,
            environment: [:]
        )

        XCTAssertEqual(configuration.cwd.standardizedFileURL.path, processCwd.url.appendingPathComponent("nested").path)
        guard case let .workspaceWrite(writableRoots, networkAccess, excludeTmpdirEnvVar, excludeSlashTmp) =
            configuration.sandboxPolicy
        else {
            return XCTFail("expected workspace-write sandbox policy")
        }
        XCTAssertTrue(writableRoots.contains(try AbsolutePath(absolutePath: workspaceRoot.path)))
        XCTAssertTrue(writableRoots.contains(try AbsolutePath(
            absolutePath: codexHome.url.appendingPathComponent("memories", isDirectory: true).path
        )))
        XCTAssertTrue(networkAccess)
        XCTAssertTrue(excludeTmpdirEnvVar)
        XCTAssertTrue(excludeSlashTmp)
        XCTAssertTrue(configuration.permissionProfile.fileSystemSandboxPolicy.canWritePathWithCwd(
            workspaceRoot.path,
            cwd: configuration.cwd.path
        ))
        XCTAssertTrue(configuration.permissionProfile.networkSandboxPolicy.isEnabled)
    }

    func testResolveDebugSandboxConfigurationDerivesPermissionProfileForDangerFullAccessBuiltIn() throws {
        let codexHome = try SandboxTemporaryDirectory()
        let processCwd = try SandboxTemporaryDirectory()

        let configuration = try CodexCLI.resolveDebugSandboxConfiguration(
            profile: CodexCLI.SandboxProfileOptions(permissionsProfile: ":danger-full-access"),
            configOverrides: CliConfigOverrides(),
            codexHome: codexHome.url,
            processCwd: processCwd.url,
            environment: [:]
        )

        XCTAssertEqual(configuration.sandboxPolicy, .dangerFullAccess)
        XCTAssertEqual(configuration.permissionProfile, .fromLegacySandboxPolicy(.dangerFullAccess))
    }

    func testResolveDebugSandboxConfigurationKeepsLegacyConfigsReadOnlyUnlessSandboxModeIsExplicit() throws {
        let codexHome = try SandboxTemporaryDirectory()
        let processCwd = try SandboxTemporaryDirectory()
        let workspaceRoot = codexHome.url.appendingPathComponent("allowed", isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceRoot, withIntermediateDirectories: true)
        try """
        sandbox_mode = "workspace-write"

        [sandbox_workspace_write]
        writable_roots = ["\(workspaceRoot.path)"]
        network_access = true
        """.write(
            to: codexHome.url.appendingPathComponent("config.toml", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )

        let ambientConfiguration = try CodexCLI.resolveDebugSandboxConfiguration(
            profile: CodexCLI.SandboxProfileOptions(),
            configOverrides: CliConfigOverrides(),
            codexHome: codexHome.url,
            processCwd: processCwd.url,
            environment: [:]
        )
        XCTAssertEqual(ambientConfiguration.sandboxPolicy, .readOnly)

        let explicitConfiguration = try CodexCLI.resolveDebugSandboxConfiguration(
            profile: CodexCLI.SandboxProfileOptions(),
            configOverrides: CliConfigOverrides(rawOverrides: [#"sandbox_mode="workspace-write""#]),
            codexHome: codexHome.url,
            processCwd: processCwd.url,
            environment: [:]
        )
        guard case let .workspaceWrite(writableRoots, networkAccess, _, _) = explicitConfiguration.sandboxPolicy else {
            return XCTFail("expected explicit workspace-write sandbox policy")
        }
        XCTAssertTrue(writableRoots.contains(try AbsolutePath(absolutePath: workspaceRoot.path)))
        XCTAssertTrue(networkAccess)
    }

    func testResolveDebugSandboxConfigurationHonorsNamedPermissionProfileLikeRust() throws {
        let codexHome = try SandboxTemporaryDirectory()
        let processCwd = try SandboxTemporaryDirectory()
        let paths = try SandboxTemporaryDirectory()
        let docs = paths.url.appendingPathComponent("docs", isDirectory: true)
        let privateDir = docs.appendingPathComponent("private", isDirectory: true)
        try FileManager.default.createDirectory(at: privateDir, withIntermediateDirectories: true)
        try """
        default_permissions = "limited-read-test"

        [permissions.limited-read-test.filesystem]
        ":minimal" = "read"
        "\(docs.path)" = "read"
        "\(privateDir.path)" = "none"

        [permissions.limited-read-test.network]
        enabled = true
        """.write(
            to: codexHome.url.appendingPathComponent("config.toml", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )

        let configuration = try CodexCLI.resolveDebugSandboxConfiguration(
            profile: CodexCLI.SandboxProfileOptions(permissionsProfile: "limited-read-test"),
            configOverrides: CliConfigOverrides(),
            codexHome: codexHome.url,
            processCwd: processCwd.url,
            environment: [:]
        )

        XCTAssertEqual(configuration.sandboxPolicy, .readOnlyWithNetworkAccess)
        XCTAssertEqual(
            configuration.permissionProfile,
            .managed(
                fileSystem: .restricted(entries: [
                    FileSystemSandboxEntry(path: .path(docs.path), access: .read),
                    FileSystemSandboxEntry(path: .path(privateDir.path), access: .none),
                    FileSystemSandboxEntry(path: .special(FileSystemSpecialPath.minimal.jsonValue), access: .read)
                ]),
                network: .enabled
            )
        )
    }

    func testResolveDebugSandboxConfigurationIgnoresManagedRequirementsUnlessIncludedLikeRust() throws {
        let codexHome = try SandboxTemporaryDirectory()
        let processCwd = try SandboxTemporaryDirectory()
        let requirementsPath = codexHome.url.appendingPathComponent("requirements.toml", isDirectory: false)
        try """
        allowed_sandbox_modes = ["read-only"]
        """.write(to: requirementsPath, atomically: true, encoding: .utf8)

        let managedOverrides = ConfigLayerLoaderOverrides(
            managedConfigPath: codexHome.url.appendingPathComponent("missing-managed.toml", isDirectory: false),
            requirementsPath: requirementsPath
        )

        let ignoredConfiguration = try CodexCLI.resolveDebugSandboxConfiguration(
            profile: CodexCLI.SandboxProfileOptions(permissionsProfile: ":workspace"),
            configOverrides: CliConfigOverrides(),
            codexHome: codexHome.url,
            processCwd: processCwd.url,
            managedConfigOverrides: managedOverrides,
            environment: [:]
        )
        guard case .workspaceWrite = ignoredConfiguration.sandboxPolicy else {
            return XCTFail("expected debug sandbox to ignore managed requirements by default for profile invocations")
        }

        XCTAssertThrowsError(try CodexCLI.resolveDebugSandboxConfiguration(
            profile: CodexCLI.SandboxProfileOptions(
                permissionsProfile: ":workspace",
                includeManagedConfig: true
            ),
            configOverrides: CliConfigOverrides(),
            codexHome: codexHome.url,
            processCwd: processCwd.url,
            managedConfigOverrides: managedOverrides,
            environment: [:]
        )) { error in
            XCTAssertEqual(
                error as? ConstraintError,
                .invalidValue(
                    candidate: "WorkspaceWrite { writable_roots: [], network_access: false, exclude_tmpdir_env_var: false, exclude_slash_tmp: false }",
                    allowed: "[ReadOnly]"
                )
            )
        }
    }

    func testResolveDebugSandboxConfigurationPreservesNonLegacyPermissionProfileForDirectSeatbeltRuntime() throws {
        let codexHome = try SandboxTemporaryDirectory()
        let processCwd = try SandboxTemporaryDirectory()
        let externalWriteRoot = try SandboxTemporaryDirectory()
        try """
        default_permissions = "external-write-test"

        [permissions.external-write-test.filesystem]
        "\(externalWriteRoot.url.path)" = "write"

        [permissions.external-write-test.network]
        enabled = false
        """.write(
            to: codexHome.url.appendingPathComponent("config.toml", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )

        let configuration = try CodexCLI.resolveDebugSandboxConfiguration(
            profile: CodexCLI.SandboxProfileOptions(permissionsProfile: "external-write-test"),
            configOverrides: CliConfigOverrides(),
            codexHome: codexHome.url,
            processCwd: processCwd.url,
            environment: [:]
        )

        XCTAssertEqual(configuration.sandboxPolicy, .readOnly)
        XCTAssertEqual(
            configuration.permissionProfile,
            .managed(
                fileSystem: .restricted(entries: [
                    FileSystemSandboxEntry(path: .path(externalWriteRoot.url.path), access: .write)
                ]),
                network: .restricted
            )
        )
    }

    func testRunAsyncSandboxWindowsDelegatesToRunner() async {
        var receivedRequest: CodexCLI.SandboxCommandRequest?

        let exitCode = await CodexCLI().runAsync(
            arguments: ["sandbox", "windows", "cmd", "/c", "echo", "ok"],
            stderr: { _ in XCTFail("stderr should not be written") },
            sandboxRunner: { request in
                receivedRequest = request
                return CodexCLI.CommandExecutionResult(exitCode: 0)
            }
        )

        XCTAssertEqual(exitCode, 0)
        XCTAssertEqual(
            receivedRequest?.action,
            .windows(
                profile: CodexCLI.SandboxProfileOptions(),
                command: ["cmd", "/c", "echo", "ok"]
            )
        )
    }

    func testRunAsyncSandboxPreservesFlagLikeCommandAfterDoubleDash() async {
        var receivedRequest: CodexCLI.SandboxCommandRequest?

        let exitCode = await CodexCLI().runAsync(
            arguments: ["sandbox", "macos", "--", "-weird"],
            stderr: { _ in XCTFail("stderr should not be written") },
            sandboxRunner: { request in
                receivedRequest = request
                return CodexCLI.CommandExecutionResult(exitCode: 0)
            }
        )

        XCTAssertEqual(exitCode, 0)
        XCTAssertEqual(
            receivedRequest?.action,
            .macos(
                profile: CodexCLI.SandboxProfileOptions(),
                allowUnixSockets: [],
                logDenials: false,
                command: ["-weird"]
            )
        )
    }

    func testRunAsyncSandboxRejectsInvalidFormsBeforeRunner() async {
        let cases: [([String], String)] = [
            (
                ["sandbox", "freebsd", "echo", "ok"],
                "codex-swift: unsupported sandbox subcommand: freebsd"
            ),
            (
                ["sandbox", "macos"],
                "codex-swift: missing required argument for command 'sandbox macos': <COMMAND>"
            ),
            (
                ["sandbox", "linux", "--log-denials", "echo", "ok"],
                "codex-swift: unsupported option for command 'sandbox linux': --log-denials"
            ),
            (
                ["sandbox", "linux", "--full-auto", "echo", "ok"],
                "codex-swift: unsupported option for command 'sandbox linux': --full-auto"
            ),
            (
                ["sandbox", "macos", "-C", "/tmp", "echo", "ok"],
                "codex-swift: --cd and --include-managed-config require --permissions-profile"
            ),
            (
                ["sandbox", "linux", "--allow-unix-socket", "/tmp/socket", "echo", "ok"],
                "codex-swift: unsupported option for command 'sandbox linux': --allow-unix-socket"
            )
        ]

        for (arguments, expectedMessage) in cases {
            var stderr: [String] = []
            let exitCode = await CodexCLI().runAsync(
                arguments: arguments,
                stdout: { _ in XCTFail("stdout should not be written for \(arguments)") },
                stderr: { stderr.append($0) },
                sandboxRunner: { _ in
                    XCTFail("runner should not be called for \(arguments)")
                    return CodexCLI.CommandExecutionResult(exitCode: 0)
                }
            )

            XCTAssertEqual(exitCode, 64, "\(arguments)")
            XCTAssertEqual(stderr, [expectedMessage], "\(arguments)")
        }
    }

    func testRunAsyncSandboxWithoutRunnerStillReportsUnimplemented() async {
        var stderr: [String] = []

        let exitCode = await CodexCLI().runAsync(
            arguments: ["sandbox", "macos", "echo", "ok"],
            stdout: { _ in XCTFail("stdout should not be written") },
            stderr: { stderr.append($0) }
        )

        XCTAssertEqual(exitCode, 78)
        XCTAssertEqual(stderr, ["codex-swift: command 'sandbox' is registered but its runtime port is not complete yet."])
    }
}

private final class SandboxTemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-swift-sandbox-cli-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}
