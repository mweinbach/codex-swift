import CodexCLI
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
