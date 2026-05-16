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
                    DoctorCommandRuntime.sandboxHelpersCheck(
                        approvalPolicy: .onRequest,
                        sandboxPolicy: .newWorkspaceWritePolicy(),
                        permissionProfile: nil,
                        cwd: "/tmp/project",
                        effectiveWorkspaceRoots: [],
                        helperPaths: DoctorSandboxHelperPaths()
                    )
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
