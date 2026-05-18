import CodexCLI
import CodexCore
import XCTest

final class PluginCLITests: XCTestCase {
    func testRunAsyncPluginAddListAndRemoveParseRustForms() async {
        var requests: [CodexCLI.PluginCommandRequest] = []

        let cases: [[String]] = [
            ["-c", "model=\"gpt-5\"", "plugin", "add", "weather@debug"],
            ["plugin", "add", "weather", "--marketplace", "debug"],
            ["plugin", "add", "weather", "-m", "debug"],
            ["plugin", "list"],
            ["plugin", "list", "--marketplace", "debug"],
            ["plugin", "remove", "weather@debug"],
            ["plugin", "remove", "weather", "--marketplace=debug"]
        ]

        for arguments in cases {
            let exitCode = await CodexCLI().runAsync(
                arguments: arguments,
                stderr: { _ in XCTFail("stderr should not be written for \(arguments)") },
                pluginRunner: { request in
                    requests.append(request)
                    return CodexCLI.CommandExecutionResult(exitCode: 0)
                }
            )
            XCTAssertEqual(exitCode, 0, "\(arguments)")
        }

        XCTAssertEqual(requests, [
            CodexCLI.PluginCommandRequest(
                action: .add(plugin: "weather@debug", marketplaceName: nil),
                configOverrides: CliConfigOverrides(rawOverrides: ["model=\"gpt-5\""])
            ),
            CodexCLI.PluginCommandRequest(action: .add(plugin: "weather", marketplaceName: "debug")),
            CodexCLI.PluginCommandRequest(action: .add(plugin: "weather", marketplaceName: "debug")),
            CodexCLI.PluginCommandRequest(action: .list(marketplaceName: nil)),
            CodexCLI.PluginCommandRequest(action: .list(marketplaceName: "debug")),
            CodexCLI.PluginCommandRequest(action: .remove(plugin: "weather@debug", marketplaceName: nil)),
            CodexCLI.PluginCommandRequest(action: .remove(plugin: "weather", marketplaceName: "debug"))
        ])
    }

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
            ["plugin", "marketplace", "list"],
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
            .marketplaceList,
            .marketplaceUpgrade(name: nil),
            .marketplaceUpgrade(name: "debug"),
            .marketplaceRemove(name: "debug")
        ])
    }

    func testRunAsyncPluginMarketplaceRejectsInvalidFormsBeforeRunner() async {
        let cases: [([String], Int32, String)] = [
            (
                ["plugin", "install"],
                64,
                "codex-swift: unsupported plugin subcommand: install"
            ),
            (
                ["plugin", "add"],
                2,
                """
                error: the following required arguments were not provided:
                  <PLUGIN[@MARKETPLACE]>

                Usage: codex plugin add <PLUGIN[@MARKETPLACE]>

                For more information, try '--help'.
                """
            ),
            (
                ["plugin", "add", "weather", "--marketplace", "debug", "--marketplace=other"],
                64,
                "codex-swift: duplicate option for command 'plugin add': --marketplace"
            ),
            (
                ["plugin", "add", "weather", "extra"],
                64,
                "codex-swift: unexpected argument for command 'plugin add': extra"
            ),
            (
                ["plugin", "list", "extra"],
                64,
                "codex-swift: unexpected argument for command 'plugin list': extra"
            ),
            (
                ["plugin", "list", "--marketplace", "debug", "-m", "other"],
                64,
                "codex-swift: duplicate option for command 'plugin list': --marketplace"
            ),
            (
                ["plugin", "remove"],
                2,
                """
                error: the following required arguments were not provided:
                  <PLUGIN[@MARKETPLACE]>

                Usage: codex plugin remove <PLUGIN[@MARKETPLACE]>

                For more information, try '--help'.
                """
            ),
            (
                ["plugin", "marketplace", "add"],
                2,
                """
                error: the following required arguments were not provided:
                  <SOURCE>

                Usage: codex plugin marketplace add <SOURCE>

                For more information, try '--help'.
                """
            ),
            (
                ["plugin", "marketplace", "add", "owner/repo", "extra"],
                64,
                "codex-swift: unexpected argument for command 'plugin marketplace add': extra"
            ),
            (
                ["plugin", "marketplace", "add", "--ref", "main", "owner/repo", "--ref=next"],
                64,
                "codex-swift: duplicate option for command 'plugin marketplace add': --ref"
            ),
            (
                ["plugin", "marketplace", "upgrade", "--all"],
                64,
                "codex-swift: unsupported option for command 'plugin marketplace upgrade': --all"
            ),
            (
                ["plugin", "marketplace", "list", "extra"],
                2,
                """
                error: unexpected argument 'extra' found

                Usage: codex plugin marketplace list [OPTIONS]

                For more information, try '--help'.
                """
            ),
            (
                ["plugin", "marketplace", "remove"],
                2,
                """
                error: the following required arguments were not provided:
                  <MARKETPLACE_NAME>

                Usage: codex plugin marketplace remove <MARKETPLACE_NAME>

                For more information, try '--help'.
                """
            )
        ]

        for (arguments, expectedExitCode, expectedMessage) in cases {
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

            XCTAssertEqual(exitCode, expectedExitCode, "\(arguments)")
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
