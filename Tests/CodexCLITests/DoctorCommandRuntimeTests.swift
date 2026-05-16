import CodexCLI
import CodexCore
import Foundation
import XCTest

final class DoctorCommandRuntimeTests: XCTestCase {
    func testNpmGlobalRootProbeUsesWindowsShimLikeRustDoctor() {
        XCTAssertEqual(DoctorCommandRuntime.npmGlobalRootCommand(isWindows: true), "npm.cmd")
        XCTAssertEqual(DoctorCommandRuntime.npmGlobalRootArguments, ["root", "-g"])
    }

    func testNpmGlobalRootProbeUsesNpmOffWindowsLikeRustDoctor() {
        XCTAssertEqual(DoctorCommandRuntime.npmGlobalRootCommand(isWindows: false), "npm")
        XCTAssertEqual(DoctorCommandRuntime.npmGlobalRootArguments, ["root", "-g"])
    }

    func testRunJsonEmitsRustShapedConfigReport() throws {
        let result = DoctorCommandRuntime.run(
            request: CodexCLI.DoctorCommandRequest(json: true),
            codexVersion: "0.0.0",
            generatedAt: "0s since unix epoch",
            diagnosticChecks: {
                [
                    DoctorCommandRuntime.installationCheck(
                        showDetails: true,
                        inputs: DoctorInstallationInputs(
                            currentExecutablePath: "/tmp/codex",
                            environment: [:],
                            pathEntries: ["/tmp/codex"],
                            installContext: "other"
                        )
                    ),
                    DoctorCommandRuntime.runtimeProvenanceCheck(
                        codexVersion: "0.0.0",
                        currentExecutablePath: "/tmp/codex",
                        osName: "darwin",
                        architecture: "arm64",
                        buildCommit: "abc123"
                    ),
                    DoctorCommandRuntime.searchCheck(
                        commandOutput: { command, arguments in
                            XCTAssertEqual(command, "rg")
                            XCTAssertEqual(arguments, ["--version"])
                            return .success("ripgrep 14.1.1\n")
                        }
                    ),
                    DoctorCommandRuntime.networkEnvironmentCheck(
                        environment: ["HTTPS_PROXY": "https://proxy.example"]
                    ),
                    DoctorCommandRuntime.terminalEnvironmentCheck(
                        noColorFlag: false,
                        inputs: DoctorTerminalCheckInputs(
                            terminalInfo: TerminalInfo(
                                name: .iterm2,
                                termProgram: "iTerm.app",
                                version: "3.5",
                                term: nil,
                                multiplexer: nil
                            ),
                            environment: [
                                "TERM": "xterm-256color",
                                "LANG": "en_US.UTF-8",
                                "COLUMNS": "120",
                                "LINES": "40"
                            ],
                            presentEnvironment: ["TERM", "LANG", "COLUMNS", "LINES"],
                            noColorFlag: false,
                            stdinIsTerminal: true,
                            stdoutIsTerminal: true,
                            stderrIsTerminal: true,
                            streamSupportsColor: true,
                            terminalSize: .available(DoctorTerminalSize(columns: 120, rows: 40))
                        )
                    ),
                    DoctorCommandRuntime.authCredentialsCheck(inputs: DoctorAuthCheckInputs(
                        codexHomePath: "/tmp/codex",
                        authStorageMode: .file,
                        environment: [:],
                        providerRequiresOpenAIAuth: true,
                        providerEnvKey: nil,
                        providerEnvKeyInstructions: nil,
                        storedAuth: .loaded(AuthDotJSON(
                            authMode: .apiKey,
                            openAIAPIKey: "sk-test",
                            tokens: nil,
                            lastRefresh: nil
                        ))
                    )),
                    DoctorCommandRuntime.updatesCheck(inputs: DoctorUpdatesCheckInputs(
                        codexHomePath: "/tmp/codex",
                        checkForUpdateOnStartup: true,
                        installContext: .other,
                        environment: [:],
                        currentVersion: "0.0.0",
                        versionCache: .missing,
                        latestVersion: .success("0.0.0")
                    )),
                    DoctorCommandRuntime.sandboxHelpersCheck(
                        approvalPolicy: .onRequest,
                        sandboxPolicy: .newWorkspaceWritePolicy(),
                        permissionProfile: nil,
                        cwd: "/tmp/project",
                        effectiveWorkspaceRoots: [],
                        helperPaths: DoctorSandboxHelperPaths()
                    ),
                    DoctorCommandRuntime.statePathsCheck(inputs: DoctorStatePathsCheckInputs(
                        codexHomePath: "/tmp/codex",
                        logDirPath: "/tmp/logs",
                        sqliteHomePath: "/tmp/state",
                        codexHome: .directory,
                        logDir: .directory,
                        sqliteHome: .directory,
                        stateDB: .missing,
                        logDB: .missing,
                        stateDBIntegrity: .skippedMissing,
                        logDBIntegrity: .skippedMissing,
                        activeRollouts: DoctorStateRolloutStats(files: 2, totalBytes: 21),
                        archivedRollouts: DoctorStateRolloutStats(files: 0, totalBytes: 0)
                    )),
                    DoctorCommandRuntime.backgroundServerCheck(inputs: DoctorBackgroundServerCheckInputs(
                        codexHomePath: "/tmp/codex",
                        settingsFile: .missing,
                        pidFile: .missing,
                        updatePidFile: .missing,
                        controlSocket: .resolved(
                            path: "/tmp/codex/app-server-control/app-server-control.sock",
                            status: .notRunning
                        )
                    ))
                ]
            }
        ) {
            DoctorCommandRuntime.configLoadedCheck(
                model: "gpt-test",
                modelProviderID: "openai",
                logDir: "/tmp/logs",
                sqliteHome: "/tmp/state",
                mcpServerCount: 2,
                configTomlPath: "/tmp/codex/config.toml",
                configTomlStatus: "parse: ok"
            )
        }

        XCTAssertEqual(result.exitCode, 0)
        let data = try XCTUnwrap(result.stdoutMessage?.data(using: .utf8))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["schemaVersion"] as? Int, 1)
        XCTAssertEqual(json["generatedAt"] as? String, "0s since unix epoch")
        XCTAssertEqual(json["overallStatus"] as? String, "ok")
        XCTAssertEqual(json["codexVersion"] as? String, "0.0.0")

        let checks = try XCTUnwrap(json["checks"] as? [String: Any])
        let installation = try XCTUnwrap(checks["installation"] as? [String: Any])
        XCTAssertEqual(installation["category"] as? String, "install")
        XCTAssertEqual(installation["status"] as? String, "ok")
        XCTAssertEqual(installation["summary"] as? String, "installation looks consistent")
        let installationDetails = try XCTUnwrap(installation["details"] as? [String: Any])
        XCTAssertEqual(installationDetails["current executable"] as? String, "/tmp/codex")
        XCTAssertEqual(installationDetails["install context"] as? String, "other")
        XCTAssertEqual(installationDetails["managed by npm"] as? String, "false")
        XCTAssertEqual(installationDetails["managed by bun"] as? String, "false")
        XCTAssertEqual(installationDetails["managed package root"] as? String, "not set")
        XCTAssertEqual(installationDetails["PATH codex #1"] as? String, "/tmp/codex")

        let runtime = try XCTUnwrap(checks["runtime.provenance"] as? [String: Any])
        XCTAssertEqual(runtime["category"] as? String, "runtime")
        XCTAssertEqual(runtime["status"] as? String, "ok")
        XCTAssertEqual(runtime["summary"] as? String, "running local build on darwin-arm64")
        let runtimeDetails = try XCTUnwrap(runtime["details"] as? [String: Any])
        XCTAssertEqual(runtimeDetails["current executable"] as? String, "/tmp/codex")
        XCTAssertEqual(runtimeDetails["commit"] as? String, "abc123")

        let search = try XCTUnwrap(checks["runtime.search"] as? [String: Any])
        XCTAssertEqual(search["category"] as? String, "search")
        XCTAssertEqual(search["status"] as? String, "ok")
        XCTAssertEqual(search["summary"] as? String, "search is OK (system)")
        let searchDetails = try XCTUnwrap(search["details"] as? [String: Any])
        XCTAssertEqual(searchDetails["search command"] as? String, "rg")
        XCTAssertEqual(searchDetails["search command readiness"] as? String, "ripgrep 14.1.1")

        let network = try XCTUnwrap(checks["network.env"] as? [String: Any])
        XCTAssertEqual(network["category"] as? String, "network")
        XCTAssertEqual(network["status"] as? String, "ok")
        XCTAssertEqual(network["summary"] as? String, "network-related environment looks readable")
        let networkDetails = try XCTUnwrap(network["details"] as? [String: Any])
        XCTAssertEqual(networkDetails["proxy env vars present"] as? String, "HTTPS_PROXY")

        let terminal = try XCTUnwrap(checks["terminal.env"] as? [String: Any])
        XCTAssertEqual(terminal["category"] as? String, "terminal")
        XCTAssertEqual(terminal["status"] as? String, "ok")
        XCTAssertEqual(terminal["summary"] as? String, "terminal metadata was detected")
        let terminalDetails = try XCTUnwrap(terminal["details"] as? [String: Any])
        XCTAssertEqual(terminalDetails["terminal"] as? String, "iTerm2")
        XCTAssertEqual(terminalDetails["TERM_PROGRAM"] as? String, "iTerm.app")
        XCTAssertEqual(terminalDetails["terminal version"] as? String, "3.5")
        XCTAssertEqual(terminalDetails["terminal size"] as? String, "120x40")
        XCTAssertEqual(terminalDetails["color output"] as? String, "enabled")

        let auth = try XCTUnwrap(checks["auth.credentials"] as? [String: Any])
        XCTAssertEqual(auth["category"] as? String, "auth")
        XCTAssertEqual(auth["status"] as? String, "ok")
        XCTAssertEqual(auth["summary"] as? String, "auth is configured")
        let authDetails = try XCTUnwrap(auth["details"] as? [String: Any])
        XCTAssertEqual(authDetails["auth storage mode"] as? String, "File")
        XCTAssertEqual(authDetails["auth file"] as? String, "/tmp/codex/auth.json")
        XCTAssertEqual(authDetails["stored auth mode"] as? String, "api_key")
        XCTAssertEqual(authDetails["stored API key"] as? String, "true")

        let updates = try XCTUnwrap(checks["updates.status"] as? [String: Any])
        XCTAssertEqual(updates["category"] as? String, "updates")
        XCTAssertEqual(updates["status"] as? String, "ok")
        XCTAssertEqual(updates["summary"] as? String, "update configuration is locally consistent")
        let updateDetails = try XCTUnwrap(updates["details"] as? [String: Any])
        XCTAssertEqual(updateDetails["check for update on startup"] as? String, "true")
        XCTAssertEqual(updateDetails["update action"] as? String, "manual or unknown")
        XCTAssertEqual(updateDetails["version cache"] as? [String], ["/tmp/codex/version.json", "missing"])
        XCTAssertEqual(updateDetails["latest version"] as? String, "0.0.0")
        XCTAssertEqual(updateDetails["latest version status"] as? String, "current version is not older")

        let sandbox = try XCTUnwrap(checks["sandbox.helpers"] as? [String: Any])
        XCTAssertEqual(sandbox["category"] as? String, "sandbox")
        XCTAssertEqual(sandbox["status"] as? String, "ok")
        XCTAssertEqual(sandbox["summary"] as? String, "sandbox configuration is readable")
        let sandboxDetails = try XCTUnwrap(sandbox["details"] as? [String: Any])
        XCTAssertEqual(sandboxDetails["approval policy"] as? String, "on-request")
        XCTAssertEqual(sandboxDetails["filesystem sandbox"] as? String, "restricted")
        XCTAssertEqual(sandboxDetails["network sandbox"] as? String, "restricted")
        XCTAssertEqual(sandboxDetails["codex-linux-sandbox helper"] as? String, "none")
        XCTAssertEqual(sandboxDetails["execve wrapper helper"] as? String, "none")

        let state = try XCTUnwrap(checks["state.paths"] as? [String: Any])
        XCTAssertEqual(state["category"] as? String, "state")
        XCTAssertEqual(state["status"] as? String, "ok")
        XCTAssertEqual(state["summary"] as? String, "state paths and databases are inspectable")
        let stateDetails = try XCTUnwrap(state["details"] as? [String: Any])
        XCTAssertEqual(stateDetails["CODEX_HOME"] as? String, "/tmp/codex (dir)")
        XCTAssertEqual(stateDetails["log dir"] as? String, "/tmp/logs (dir)")
        XCTAssertEqual(stateDetails["sqlite home"] as? String, "/tmp/state (dir)")
        XCTAssertEqual(stateDetails["state DB"] as? String, "/tmp/state/state_5.sqlite (missing)")
        XCTAssertEqual(stateDetails["log DB"] as? String, "/tmp/state/logs_2.sqlite (missing)")
        XCTAssertEqual(stateDetails["state DB integrity"] as? String, "skipped (missing)")
        XCTAssertEqual(stateDetails["log DB integrity"] as? String, "skipped (missing)")
        XCTAssertEqual(stateDetails["active rollout files"] as? String, "2 files, 21 total bytes, 10 average bytes")
        XCTAssertEqual(stateDetails["archived rollout files"] as? String, "0 files, 0 total bytes, 0 average bytes")

        let appServer = try XCTUnwrap(checks["app_server.status"] as? [String: Any])
        XCTAssertEqual(appServer["category"] as? String, "app-server")
        XCTAssertEqual(appServer["status"] as? String, "ok")
        XCTAssertEqual(appServer["summary"] as? String, "background server is not running")
        let appServerDetails = try XCTUnwrap(appServer["details"] as? [String: Any])
        XCTAssertEqual(appServerDetails["daemon state dir"] as? String, "/tmp/codex/app-server-daemon")
        XCTAssertEqual(appServerDetails["settings"] as? String, "/tmp/codex/app-server-daemon/settings.json (missing)")
        XCTAssertEqual(appServerDetails["pid file"] as? String, "/tmp/codex/app-server-daemon/app-server.pid (missing)")
        XCTAssertEqual(
            appServerDetails["update-loop pid file"] as? String,
            "/tmp/codex/app-server-daemon/app-server-updater.pid (missing)"
        )
        XCTAssertEqual(appServerDetails["control socket"] as? String, "/tmp/codex/app-server-control/app-server-control.sock")
        XCTAssertEqual(appServerDetails["status"] as? String, "not running")
        XCTAssertEqual(appServerDetails["mode"] as? String, "ephemeral")

        let config = try XCTUnwrap(checks["config.load"] as? [String: Any])
        XCTAssertEqual(config["id"] as? String, "config.load")
        XCTAssertEqual(config["category"] as? String, "config")
        XCTAssertEqual(config["status"] as? String, "ok")
        XCTAssertEqual(config["summary"] as? String, "config loaded")
        let details = try XCTUnwrap(config["details"] as? [String: Any])
        XCTAssertEqual(details["model"] as? String, "gpt-test")
        XCTAssertEqual(details["model provider"] as? String, "openai")
        XCTAssertEqual(details["mcp servers"] as? String, "2")
        XCTAssertEqual(details["config.toml"] as? String, "/tmp/codex/config.toml")
        XCTAssertEqual(details["config.toml parse"] as? String, "ok")
    }

    func testSearchCheckWarnsWithRustRemediationWhenRgCannotRun() {
        let check = DoctorCommandRuntime.searchCheck(
            commandOutput: { command, arguments in
                XCTAssertEqual(command, "rg")
                XCTAssertEqual(arguments, ["--version"])
                return .failure("No such file or directory")
            }
        )

        XCTAssertEqual(check.id, "runtime.search")
        XCTAssertEqual(check.category, "search")
        XCTAssertEqual(check.status, .warning)
        XCTAssertEqual(check.summary, "search command could not be verified")
        XCTAssertEqual(check.details, [
            "search command: rg",
            "search provider: system",
            "search command readiness: No such file or directory"
        ])
        XCTAssertEqual(check.remediation, "Install ripgrep or repair the bundled standalone resources.")
    }

    func testInstallationCheckWarnsForNpmManagedMissingPackageRootLikeRustDoctor() {
        let check = DoctorCommandRuntime.installationCheck(
            showDetails: false,
            inputs: DoctorInstallationInputs(
                currentExecutablePath: "/usr/local/bin/codex",
                environment: ["CODEX_MANAGED_BY_NPM": "1"],
                pathEntries: [],
                installContext: "npm"
            )
        )

        XCTAssertEqual(check.id, "installation")
        XCTAssertEqual(check.category, "install")
        XCTAssertEqual(check.status, .warning)
        XCTAssertEqual(check.summary, "npm-managed launch is missing package-root provenance")
        XCTAssertEqual(check.details, [
            "current executable: /usr/local/bin/codex",
            "install context: npm",
            "managed by npm: true",
            "managed by bun: false",
            "managed package root: not set"
        ])
        XCTAssertEqual(
            check.remediation,
            "Reinstall or update Codex so the JS shim provides CODEX_MANAGED_PACKAGE_ROOT."
        )
    }

    func testInstallationCheckFailsForNpmRootMismatchLikeRustDoctor() {
        let check = DoctorCommandRuntime.installationCheck(
            showDetails: false,
            inputs: DoctorInstallationInputs(
                currentExecutablePath: "/opt/codex/bin/codex",
                environment: [
                    "CODEX_MANAGED_BY_NPM": "1",
                    "CODEX_MANAGED_PACKAGE_ROOT": "/opt/codex/lib/node_modules/@openai/codex"
                ],
                pathEntries: ["/opt/codex/bin/codex", "/usr/local/bin/codex"],
                installContext: "npm",
                npmRootCheck: .mismatch(
                    runningPackageRoot: "/opt/codex/lib/node_modules/@openai/codex",
                    npmPackageRoot: "/usr/local/lib/node_modules/@openai/codex"
                )
            )
        )

        XCTAssertEqual(check.status, .fail)
        XCTAssertEqual(check.summary, "npm install -g @openai/codex would update a different install")
        XCTAssertEqual(check.details, [
            "current executable: /opt/codex/bin/codex",
            "install context: npm",
            "managed by npm: true",
            "managed by bun: false",
            "managed package root: /opt/codex/lib/node_modules/@openai/codex",
            "PATH codex entries: 2",
            "PATH codex #1: /opt/codex/bin/codex",
            "PATH codex #2: /usr/local/bin/codex",
            "running package root: /opt/codex/lib/node_modules/@openai/codex",
            "npm package root: /usr/local/lib/node_modules/@openai/codex"
        ])
        XCTAssertEqual(
            check.remediation,
            "Fix PATH or npm prefix so the running package root (/opt/codex/lib/node_modules/@openai/codex) matches the npm global package root (/usr/local/lib/node_modules/@openai/codex)."
        )
    }

    func testAuthCredentialsCheckFailsWhenOpenAIAuthIsMissingLikeRustDoctor() {
        let check = DoctorCommandRuntime.authCredentialsCheck(inputs: DoctorAuthCheckInputs(
            codexHomePath: "/tmp/codex",
            authStorageMode: .file,
            environment: [:],
            providerRequiresOpenAIAuth: true,
            providerEnvKey: nil,
            providerEnvKeyInstructions: nil,
            storedAuth: .loaded(nil)
        ))

        XCTAssertEqual(check.id, "auth.credentials")
        XCTAssertEqual(check.category, "auth")
        XCTAssertEqual(check.status, .fail)
        XCTAssertEqual(check.summary, "no Codex credentials were found")
        XCTAssertEqual(check.details, [
            "auth storage mode: File",
            "auth file: /tmp/codex/auth.json"
        ])
        XCTAssertEqual(
            check.remediation,
            "Run codex login or provide an API key through a supported auth env var."
        )
    }

    func testAuthCredentialsCheckAllowsProviderEnvAuthLikeRustDoctor() {
        let check = DoctorCommandRuntime.authCredentialsCheck(inputs: DoctorAuthCheckInputs(
            codexHomePath: "/tmp/codex",
            authStorageMode: .auto,
            environment: ["PROVIDER_API_KEY": "present"],
            providerRequiresOpenAIAuth: false,
            providerEnvKey: "PROVIDER_API_KEY",
            providerEnvKeyInstructions: nil,
            storedAuth: .loaded(nil)
        ))

        XCTAssertEqual(check.status, .ok)
        XCTAssertEqual(check.summary, "auth is provided by the active model provider")
        XCTAssertEqual(check.details, [
            "auth storage mode: Auto",
            "auth file: /tmp/codex/auth.json",
            "model provider requires OpenAI auth: false",
            "provider auth env var: PROVIDER_API_KEY (present)"
        ])
    }

    func testAuthCredentialsCheckFailsMissingProviderEnvAuthLikeRustDoctor() {
        let check = DoctorCommandRuntime.authCredentialsCheck(inputs: DoctorAuthCheckInputs(
            codexHomePath: "/tmp/codex",
            authStorageMode: .auto,
            environment: [:],
            providerRequiresOpenAIAuth: false,
            providerEnvKey: "PROVIDER_API_KEY",
            providerEnvKeyInstructions: "Set PROVIDER_API_KEY before running Codex.",
            storedAuth: .loaded(AuthDotJSON(
                authMode: .apiKey,
                openAIAPIKey: "sk-test",
                tokens: nil,
                lastRefresh: nil
            ))
        ))

        XCTAssertEqual(check.status, .fail)
        XCTAssertEqual(check.summary, "active model provider auth env var is missing")
        XCTAssertEqual(check.details, [
            "auth storage mode: Auto",
            "auth file: /tmp/codex/auth.json",
            "model provider requires OpenAI auth: false",
            "provider auth env var: PROVIDER_API_KEY (missing)"
        ])
        XCTAssertEqual(check.remediation, "Set PROVIDER_API_KEY before running Codex.")
    }

    func testAuthCredentialsCheckWarnsForIncompleteStoredAuthWhenEnvironmentPresentLikeRustDoctor() {
        let check = DoctorCommandRuntime.authCredentialsCheck(inputs: DoctorAuthCheckInputs(
            codexHomePath: "/tmp/codex",
            authStorageMode: .file,
            environment: [CodexAuthStorage.codexAccessTokenEnvironmentVariable: "access"],
            providerRequiresOpenAIAuth: true,
            providerEnvKey: nil,
            providerEnvKeyInstructions: nil,
            storedAuth: .loaded(AuthDotJSON(
                authMode: .chatGPT,
                openAIAPIKey: nil,
                tokens: nil,
                lastRefresh: nil
            ))
        ))

        XCTAssertEqual(check.status, .warning)
        XCTAssertEqual(
            check.summary,
            "auth is provided by environment, but stored credentials are incomplete"
        )
        XCTAssertEqual(check.details, [
            "auth storage mode: File",
            "auth file: /tmp/codex/auth.json",
            "auth env vars present: CODEX_ACCESS_TOKEN",
            "stored auth mode: chatgpt",
            "stored API key: false",
            "stored ChatGPT tokens: false",
            "stored agent identity: false",
            "stored auth issue: ChatGPT auth is missing token data",
            "stored auth issue: ChatGPT auth is missing refresh metadata"
        ])
    }

    func testAuthCredentialsCheckFailsForIncompleteStoredAPIKeyLikeRustDoctor() {
        let check = DoctorCommandRuntime.authCredentialsCheck(inputs: DoctorAuthCheckInputs(
            codexHomePath: "/tmp/codex",
            authStorageMode: .file,
            environment: [:],
            providerRequiresOpenAIAuth: true,
            providerEnvKey: nil,
            providerEnvKeyInstructions: nil,
            storedAuth: .loaded(AuthDotJSON(
                authMode: .apiKey,
                openAIAPIKey: "   ",
                tokens: nil,
                lastRefresh: nil
            ))
        ))

        XCTAssertEqual(check.status, .fail)
        XCTAssertEqual(check.summary, "stored credentials are incomplete")
        XCTAssertEqual(check.details, [
            "auth storage mode: File",
            "auth file: /tmp/codex/auth.json",
            "stored auth mode: api_key",
            "stored API key: true",
            "stored ChatGPT tokens: false",
            "stored agent identity: false",
            "stored auth issue: API key auth is missing an API key"
        ])
        XCTAssertEqual(
            check.remediation,
            "Run codex login again or provide a supported auth env var."
        )
    }

    func testUpdatesCheckReportsCachedVersionAndNewerLatestLikeRustDoctor() {
        let check = DoctorCommandRuntime.updatesCheck(inputs: DoctorUpdatesCheckInputs(
            codexHomePath: "/tmp/codex",
            checkForUpdateOnStartup: false,
            installContext: .brew,
            environment: [:],
            currentVersion: "1.2.3",
            versionCache: .loaded("""
            {
              "latest_version": "1.3.0",
              "last_checked_at": "2026-05-16T10:00:00Z",
              "dismissed_version": "1.2.9"
            }
            """),
            latestVersion: .success("1.3.0")
        ))

        XCTAssertEqual(check.id, "updates.status")
        XCTAssertEqual(check.category, "updates")
        XCTAssertEqual(check.status, .ok)
        XCTAssertEqual(check.summary, "update configuration is locally consistent")
        XCTAssertEqual(check.details, [
            "check for update on startup: false",
            "update action: brew upgrade --cask codex",
            "version cache: /tmp/codex/version.json",
            "cached latest version: 1.3.0",
            "last checked at: 2026-05-16T10:00:00Z",
            "dismissed version: 1.2.9",
            "latest version: 1.3.0",
            "latest version status: newer version is available"
        ])
    }

    func testUpdatesCheckWarnsWhenLatestVersionProbeFailsLikeRustDoctor() {
        let check = DoctorCommandRuntime.updatesCheck(inputs: DoctorUpdatesCheckInputs(
            codexHomePath: "/tmp/codex",
            checkForUpdateOnStartup: true,
            installContext: .other,
            environment: [:],
            currentVersion: "1.2.3",
            versionCache: .missing,
            latestVersion: .failed("curl exited with status 28")
        ))

        XCTAssertEqual(check.status, .warning)
        XCTAssertEqual(check.summary, "update configuration is locally consistent")
        XCTAssertEqual(check.details, [
            "check for update on startup: true",
            "update action: manual or unknown",
            "version cache: /tmp/codex/version.json",
            "version cache: missing",
            "latest version probe: curl exited with status 28"
        ])
    }

    func testUpdatesCheckFailsForNpmTargetMismatchLikeRustDoctor() {
        let check = DoctorCommandRuntime.updatesCheck(inputs: DoctorUpdatesCheckInputs(
            codexHomePath: "/tmp/codex",
            checkForUpdateOnStartup: true,
            installContext: .npm,
            environment: [
                "CODEX_MANAGED_BY_NPM": "1",
                "CODEX_MANAGED_PACKAGE_ROOT": "/opt/codex/lib/node_modules/@openai/codex"
            ],
            currentVersion: "1.2.3",
            versionCache: .missing,
            latestVersion: .success("1.2.3"),
            npmRootCheck: .mismatch(
                runningPackageRoot: "/opt/codex/lib/node_modules/@openai/codex",
                npmPackageRoot: "/usr/local/lib/node_modules/@openai/codex"
            )
        ))

        XCTAssertEqual(check.status, .fail)
        XCTAssertEqual(check.summary, "update would target a different npm install")
        XCTAssertEqual(check.details, [
            "check for update on startup: true",
            "update action: npm install -g @openai/codex",
            "version cache: /tmp/codex/version.json",
            "version cache: missing",
            "running package root: /opt/codex/lib/node_modules/@openai/codex",
            "npm package root: /usr/local/lib/node_modules/@openai/codex",
            "latest version: 1.2.3",
            "latest version status: current version is not older"
        ])
        XCTAssertEqual(
            check.remediation,
            "Fix PATH or npm prefix so the running package root (/opt/codex/lib/node_modules/@openai/codex) matches the npm global package root (/usr/local/lib/node_modules/@openai/codex)."
        )
    }

    func testBackgroundServerCheckReportsPersistentRunningLikeRustDoctor() {
        let check = DoctorCommandRuntime.backgroundServerCheck(inputs: DoctorBackgroundServerCheckInputs(
            codexHomePath: "/tmp/codex",
            settingsFile: .file,
            pidFile: .file,
            updatePidFile: .missing,
            controlSocket: .resolved(
                path: "/tmp/codex/app-server-control/app-server-control.sock",
                status: .running
            )
        ))

        XCTAssertEqual(check.id, "app_server.status")
        XCTAssertEqual(check.category, "app-server")
        XCTAssertEqual(check.status, .ok)
        XCTAssertEqual(check.summary, "background server is running")
        XCTAssertEqual(check.details, [
            "daemon state dir: /tmp/codex/app-server-daemon",
            "settings: /tmp/codex/app-server-daemon/settings.json (file)",
            "pid file: /tmp/codex/app-server-daemon/app-server.pid (file)",
            "update-loop pid file: /tmp/codex/app-server-daemon/app-server-updater.pid (missing)",
            "control socket: /tmp/codex/app-server-control/app-server-control.sock",
            "status: running",
            "mode: persistent"
        ])
        XCTAssertNil(check.remediation)
    }

    func testBackgroundServerCheckWarnsForStaleSocketLikeRustDoctor() {
        let check = DoctorCommandRuntime.backgroundServerCheck(inputs: DoctorBackgroundServerCheckInputs(
            codexHomePath: "/tmp/codex",
            settingsFile: .missing,
            pidFile: .notFile,
            updatePidFile: .failed("permission denied"),
            controlSocket: .resolved(
                path: "/tmp/codex/app-server-control/app-server-control.sock",
                status: .staleOrUnreachable
            )
        ))

        XCTAssertEqual(check.status, .warning)
        XCTAssertEqual(check.summary, "background server socket is stale or unreachable")
        XCTAssertEqual(check.details, [
            "daemon state dir: /tmp/codex/app-server-daemon",
            "settings: /tmp/codex/app-server-daemon/settings.json (missing)",
            "pid file: /tmp/codex/app-server-daemon/app-server.pid (not a file)",
            "update-loop pid file: /tmp/codex/app-server-daemon/app-server-updater.pid (permission denied)",
            "control socket: /tmp/codex/app-server-control/app-server-control.sock",
            "status: stale or unreachable",
            "mode: ephemeral"
        ])
        XCTAssertEqual(check.remediation, "Run codex app-server daemon version for more details.")
    }

    func testBackgroundServerCheckWarnsWhenSocketPathCannotResolveLikeRustDoctor() {
        let check = DoctorCommandRuntime.backgroundServerCheck(inputs: DoctorBackgroundServerCheckInputs(
            codexHomePath: "/tmp/codex",
            settingsFile: .missing,
            pidFile: .missing,
            updatePidFile: .missing,
            controlSocket: .failed("failed to resolve CODEX_HOME")
        ))

        XCTAssertEqual(check.status, .warning)
        XCTAssertEqual(check.summary, "background server socket path could not be resolved")
        XCTAssertEqual(check.details, [
            "daemon state dir: /tmp/codex/app-server-daemon",
            "settings: /tmp/codex/app-server-daemon/settings.json (missing)",
            "pid file: /tmp/codex/app-server-daemon/app-server.pid (missing)",
            "update-loop pid file: /tmp/codex/app-server-daemon/app-server-updater.pid (missing)",
            "failed to resolve CODEX_HOME"
        ])
        XCTAssertNil(check.remediation)
    }

    func testStatePathsCheckReportsInspectablePathsLikeRustDoctor() {
        let check = DoctorCommandRuntime.statePathsCheck(inputs: DoctorStatePathsCheckInputs(
            codexHomePath: "/tmp/codex",
            logDirPath: "/tmp/codex/log",
            sqliteHomePath: "/tmp/codex",
            codexHome: .directory,
            logDir: .missing,
            sqliteHome: .directory,
            stateDB: .file,
            logDB: .missing,
            stateDBIntegrity: .rows(["ok"]),
            logDBIntegrity: .skippedMissing,
            activeRollouts: DoctorStateRolloutStats(files: 3, totalBytes: 30),
            archivedRollouts: DoctorStateRolloutStats(files: 1, totalBytes: 4),
            standaloneReleaseCache: "standalone release cache: 2 entries in /tmp/codex/releases"
        ))

        XCTAssertEqual(check.id, "state.paths")
        XCTAssertEqual(check.category, "state")
        XCTAssertEqual(check.status, .ok)
        XCTAssertEqual(check.summary, "state paths and databases are inspectable")
        XCTAssertEqual(check.details, [
            "CODEX_HOME: /tmp/codex (dir)",
            "log dir: /tmp/codex/log (missing)",
            "sqlite home: /tmp/codex (dir)",
            "state DB: /tmp/codex/state_5.sqlite (file)",
            "log DB: /tmp/codex/logs_2.sqlite (missing)",
            "state DB integrity: ok",
            "log DB integrity: skipped (missing)",
            "active rollout files: 3 files, 30 total bytes, 10 average bytes",
            "archived rollout files: 1 files, 4 total bytes, 4 average bytes",
            "standalone release cache: 2 entries in /tmp/codex/releases"
        ])
        XCTAssertNil(check.remediation)
    }

    func testStatePathsCheckFailsWhenSQLiteIntegrityFailsLikeRustDoctor() {
        let check = DoctorCommandRuntime.statePathsCheck(inputs: DoctorStatePathsCheckInputs(
            codexHomePath: "/tmp/codex",
            logDirPath: "/tmp/codex/log",
            sqliteHomePath: "/tmp/state",
            codexHome: .directory,
            logDir: .directory,
            sqliteHome: .directory,
            stateDB: .file,
            logDB: .file,
            stateDBIntegrity: .rows(["ok"]),
            logDBIntegrity: .rows(["row 2 missing", "wrong page count"]),
            activeRollouts: DoctorStateRolloutStats(files: 0, totalBytes: 0),
            archivedRollouts: DoctorStateRolloutStats(files: 0, totalBytes: 0, error: "permission denied")
        ))

        XCTAssertEqual(check.status, .fail)
        XCTAssertEqual(check.summary, "state database integrity check failed")
        XCTAssertEqual(check.details, [
            "CODEX_HOME: /tmp/codex (dir)",
            "log dir: /tmp/codex/log (dir)",
            "sqlite home: /tmp/state (dir)",
            "state DB: /tmp/state/state_5.sqlite (file)",
            "log DB: /tmp/state/logs_2.sqlite (file)",
            "state DB integrity: ok",
            "log DB integrity: row 2 missing; wrong page count",
            "active rollout files: 0 files, 0 total bytes, 0 average bytes",
            "archived rollout files: scan failed (permission denied)"
        ])
        XCTAssertEqual(
            check.remediation,
            "Back up CODEX_HOME, then remove or repair the affected SQLite database."
        )
    }

    func testInstallationCheckIgnoresInheritedManagedEnvironmentForCargoBuiltBinaryLikeRustDoctor() {
        let check = DoctorCommandRuntime.installationCheck(
            showDetails: false,
            inputs: DoctorInstallationInputs(
                currentExecutablePath: "/repo/target/debug/codex",
                environment: [
                    "CODEX_MANAGED_BY_NPM": "1",
                    "CODEX_MANAGED_PACKAGE_ROOT": "/wrong/root"
                ],
                pathEntries: [],
                installContext: "other",
                npmRootCheck: .mismatch(runningPackageRoot: "/wrong/root", npmPackageRoot: "/npm/root")
            )
        )

        XCTAssertEqual(check.status, .ok)
        XCTAssertEqual(check.summary, "installation looks consistent")
        XCTAssertEqual(check.remediation, nil)
        XCTAssertEqual(check.details, [
            "current executable: /repo/target/debug/codex",
            "install context: other",
            "ignored inherited package-manager launch env for cargo-built binary",
            "managed by npm: false",
            "managed by bun: false",
            "managed package root: /wrong/root"
        ])
    }

    func testNetworkEnvironmentCheckWarnsForUnreadableCustomCAPathLikeRustDoctor() {
        let check = DoctorCommandRuntime.networkEnvironmentCheck(
            environment: [
                "HTTP_PROXY": "",
                "SSL_CERT_FILE": "/definitely/missing/cert.pem"
            ]
        )

        XCTAssertEqual(check.id, "network.env")
        XCTAssertEqual(check.category, "network")
        XCTAssertEqual(check.status, .warning)
        XCTAssertEqual(check.summary, "custom CA env var points at an unreadable path")
        XCTAssertEqual(check.details, [
            "proxy env vars: none",
            "SSL_CERT_FILE: /definitely/missing/cert.pem (No such file or directory)"
        ])
    }

    func testSandboxHelpersCheckReportsRustWarningForMissingLinuxHelper() {
        let check = DoctorCommandRuntime.sandboxHelpersCheck(
            approvalPolicy: .never,
            sandboxPolicy: .dangerFullAccess,
            permissionProfile: nil,
            cwd: "/tmp/project",
            effectiveWorkspaceRoots: [],
            helperPaths: DoctorSandboxHelperPaths(
                codexLinuxSandbox: "/definitely/missing/codex-linux-sandbox",
                execveWrapper: "/tmp/main-execve-wrapper"
            )
        )

        XCTAssertEqual(check.id, "sandbox.helpers")
        XCTAssertEqual(check.category, "sandbox")
        XCTAssertEqual(check.status, .warning)
        XCTAssertEqual(check.summary, "Linux sandbox helper path does not exist")
        XCTAssertEqual(check.details, [
            "approval policy: never",
            "filesystem sandbox: unrestricted",
            "network sandbox: enabled",
            "codex-linux-sandbox helper: /definitely/missing/codex-linux-sandbox",
            "execve wrapper helper: /tmp/main-execve-wrapper"
        ])
    }

    func testTerminalEnvironmentCheckReportsRustIssuesForDumbTerminalAndNarrowSize() {
        let check = DoctorCommandRuntime.terminalEnvironmentCheck(
            noColorFlag: false,
            inputs: DoctorTerminalCheckInputs(
                terminalInfo: TerminalInfo(name: .dumb, term: "dumb"),
                environment: [
                    "TERM": "dumb",
                    "LANG": "C",
                    "COLUMNS": "79",
                    "LINES": "20",
                    "TERMINFO": "/definitely/missing/terminfo"
                ],
                presentEnvironment: ["TERM", "LANG", "COLUMNS", "LINES", "TERMINFO"],
                noColorFlag: false,
                stdinIsTerminal: true,
                stdoutIsTerminal: true,
                stderrIsTerminal: true,
                streamSupportsColor: true,
                terminalSize: .available(DoctorTerminalSize(columns: 79, rows: 20))
            )
        )

        XCTAssertEqual(check.id, "terminal.env")
        XCTAssertEqual(check.category, "terminal")
        XCTAssertEqual(check.status, .fail)
        XCTAssertEqual(check.summary, "TERM=dumb - colors and cursor control are disabled")
        XCTAssertTrue(check.details.contains("terminal: dumb"))
        XCTAssertTrue(check.details.contains("TERM: dumb"))
        XCTAssertTrue(check.details.contains("terminal size: 79x20"))
        XCTAssertTrue(check.details.contains("color output: disabled (TERM=dumb)"))
        XCTAssertTrue(check.details.contains("effective locale: C"))
        XCTAssertTrue(check.details.contains("TERMINFO: /definitely/missing/terminfo (missing)"))
        XCTAssertEqual(check.issues.map(\.cause), [
            "TERM=dumb - colors and cursor control are disabled",
            "locale is not UTF-8 - unicode glyphs may render incorrectly",
            "TERMINFO unreadable - terminal capabilities are unknown",
            "width 79 cols - output may wrap (recommended >=80)",
            "height 20 rows - content may scroll off (recommended >=24)",
            "COLUMNS=79 - output may wrap (recommended >=80)",
            "LINES=20 - content may scroll off (recommended >=24)"
        ])
    }

    func testRunJsonReturnsFailWhenConfigLoadFailsLikeRustDoctor() throws {
        struct TestError: Error, CustomStringConvertible {
            let description = "failed to load Codex config"
        }

        let result = DoctorCommandRuntime.run(
            request: CodexCLI.DoctorCommandRequest(json: true),
            codexVersion: "0.0.0",
            generatedAt: "0s since unix epoch"
        ) {
            DoctorCommandRuntime.configLoadFailedCheck(TestError())
        }

        XCTAssertEqual(result.exitCode, 1)
        let data = try XCTUnwrap(result.stdoutMessage?.data(using: .utf8))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["overallStatus"] as? String, "fail")
        let checks = try XCTUnwrap(json["checks"] as? [String: Any])
        let config = try XCTUnwrap(checks["config.load"] as? [String: Any])
        XCTAssertEqual(config["status"] as? String, "fail")
        XCTAssertEqual(config["summary"] as? String, "config could not be loaded")
        XCTAssertEqual(config["remediation"] as? String, "Fix the reported config error, then rerun codex doctor.")
    }

    func testRunHumanSummaryUsesAsciiCompactFooter() {
        let result = DoctorCommandRuntime.run(
            request: CodexCLI.DoctorCommandRequest(summary: true, ascii: true),
            codexVersion: "0.0.0",
            generatedAt: "0s since unix epoch"
        ) {
            DoctorCommandRuntime.configLoadedCheck(
                model: nil,
                modelProviderID: nil,
                logDir: nil,
                sqliteHome: nil,
                mcpServerCount: 0,
                configTomlPath: "/tmp/codex/config.toml",
                configTomlStatus: "missing"
            )
        }

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stdoutMessage, """
        Codex Doctor 0.0.0

        Configuration
          [ok] config       config loaded

        -------------------------------------------------------------
        1 ok | 0 warn | 0 fail ok

        Run codex doctor without --summary for detailed diagnostics.
        --all expand truncated lists       --json redacted report

        """)
    }
}
