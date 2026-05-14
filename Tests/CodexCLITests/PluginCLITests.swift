import CodexCLI
import CodexCore
import XCTest

final class PluginCLITests: XCTestCase {
    func testRunAsyncPluginMarketplaceAddParsesRustFlags() async {
        var receivedRequest: CodexCLI.PluginCommandRequest?
        var stdout: [String] = []

        let exitCode = await CodexCLI().runAsync(
            arguments: [
                "-c",
                "model=\"gpt-5\"",
                "plugin",
                "marketplace",
                "add",
                "--sparse",
                "plugins/foo",
                "owner/repo@main",
                "--sparse=skills/bar",
                "--ref",
                "override"
            ],
            stdout: { stdout.append($0) },
            stderr: { _ in XCTFail("stderr should not be written") },
            pluginRunner: { request in
                receivedRequest = request
                return CodexCLI.CommandExecutionResult(
                    exitCode: 0,
                    stdoutMessage: "Added marketplace `debug` from owner/repo@main."
                )
            }
        )

        XCTAssertEqual(exitCode, 0)
        XCTAssertEqual(stdout, ["Added marketplace `debug` from owner/repo@main."])
        XCTAssertEqual(
            receivedRequest,
            CodexCLI.PluginCommandRequest(
                action: .marketplaceAdd(
                    source: "owner/repo@main",
                    refName: "override",
                    sparsePaths: ["plugins/foo", "skills/bar"]
                ),
                configOverrides: CliConfigOverrides(rawOverrides: ["model=\"gpt-5\""])
            )
        )
    }

    func testRunAsyncPluginMarketplaceUpgradeAndRemoveDelegateToRunner() async {
        var actions: [CodexCLI.PluginCommandAction] = []

        for arguments in [
            ["plugin", "marketplace", "upgrade"],
            ["plugin", "marketplace", "upgrade", "debug"],
            ["plugin", "marketplace", "remove", "debug"]
        ] {
            let exitCode = await CodexCLI().runAsync(
                arguments: arguments,
                stderr: { _ in XCTFail("stderr should not be written for \(arguments)") },
                pluginRunner: { request in
                    actions.append(request.action)
                    return CodexCLI.CommandExecutionResult(exitCode: 0)
                }
            )
            XCTAssertEqual(exitCode, 0, "\(arguments)")
        }

        XCTAssertEqual(actions, [
            .marketplaceUpgrade(name: nil),
            .marketplaceUpgrade(name: "debug"),
            .marketplaceRemove(name: "debug")
        ])
    }

    func testRunAsyncPluginMarketplaceRejectsInvalidFormsBeforeRunner() async {
        let cases: [([String], String)] = [
            (
                ["plugin"],
                "codex-swift: missing required subcommand for command 'plugin': marketplace"
            ),
            (
                ["plugin", "install"],
                "codex-swift: unsupported plugin subcommand: install"
            ),
            (
                ["plugin", "marketplace"],
                "codex-swift: missing required subcommand for command 'plugin marketplace': add|upgrade|remove"
            ),
            (
                ["plugin", "marketplace", "add"],
                "codex-swift: missing required argument for command 'plugin marketplace add': <SOURCE>"
            ),
            (
                ["plugin", "marketplace", "add", "owner/repo", "extra"],
                "codex-swift: unexpected argument for command 'plugin marketplace add': extra"
            ),
            (
                ["plugin", "marketplace", "add", "--ref", "main", "owner/repo", "--ref=next"],
                "codex-swift: duplicate option for command 'plugin marketplace add': --ref"
            ),
            (
                ["plugin", "marketplace", "upgrade", "--all"],
                "codex-swift: unsupported option for command 'plugin marketplace upgrade': --all"
            ),
            (
                ["plugin", "marketplace", "remove"],
                "codex-swift: missing required argument for command 'plugin marketplace remove': <NAME>"
            )
        ]

        for (arguments, expectedMessage) in cases {
            var stderr: [String] = []
            let exitCode = await CodexCLI().runAsync(
                arguments: arguments,
                stdout: { _ in XCTFail("stdout should not be written for \(arguments)") },
                stderr: { stderr.append($0) },
                pluginRunner: { _ in
                    XCTFail("runner should not be called for \(arguments)")
                    return CodexCLI.CommandExecutionResult(exitCode: 0)
                }
            )

            XCTAssertEqual(exitCode, 64, "\(arguments)")
            XCTAssertEqual(stderr, [expectedMessage], "\(arguments)")
        }
    }

    func testRunAsyncPluginWithoutRunnerStillReportsUnimplemented() async {
        var stderr: [String] = []

        let exitCode = await CodexCLI().runAsync(
            arguments: ["plugin", "marketplace", "upgrade"],
            stdout: { _ in XCTFail("stdout should not be written") },
            stderr: { stderr.append($0) }
        )

        XCTAssertEqual(exitCode, 78)
        XCTAssertEqual(stderr, ["codex-swift: command 'plugin' is registered but its runtime port is not complete yet."])
    }
}
