import Foundation
import Network
@testable import CodexCore
import XCTest

final class RuntimeOracleParityTests: XCTestCase {
    func testCLIHelpMatchesRustOracleModuloBinaryNameAndVersion() throws {
        let oracle = try RuntimeOracle.required()

        let rust = try oracle.run(.rust, arguments: ["--help"])
        let swift = try oracle.run(.swift, arguments: ["--help"])

        XCTAssertEqual(rust.exitCode, 0, rust.stderr)
        XCTAssertEqual(swift.exitCode, 0, swift.stderr)

        XCTAssertEqual(normalizedHelp(swift.stdout), normalizedHelp(rust.stdout))
    }

    func testExecHelpMatchesRustOracleModuloWhitespace() throws {
        let oracle = try RuntimeOracle.required()

        let rust = try oracle.run(.rust, arguments: ["exec", "--help"])
        let swift = try oracle.run(.swift, arguments: ["exec", "--help"])

        XCTAssertEqual(rust.exitCode, 0, rust.stderr)
        XCTAssertEqual(swift.exitCode, 0, swift.stderr)

        XCTAssertEqual(normalizedHelp(swift.stdout), normalizedHelp(rust.stdout))
    }

    func testExecChildHelpMatchesRustOracleModuloWhitespace() throws {
        let oracle = try RuntimeOracle.required()
        let commands = [
            ["exec", "resume", "--help"],
            ["exec", "help", "resume"],
            ["help", "exec", "resume"],
            ["exec", "review", "--help"],
            ["exec", "help", "review"],
            ["help", "exec", "review"]
        ]

        for arguments in commands {
            let rust = try oracle.run(.rust, arguments: arguments)
            let swift = try oracle.run(.swift, arguments: arguments)

            XCTAssertEqual(rust.exitCode, 0, rust.stderr)
            XCTAssertEqual(swift.exitCode, 0, swift.stderr)
            XCTAssertEqual(normalizedHelp(swift.stdout), normalizedHelp(rust.stdout), arguments.joined(separator: " "))
        }
    }

    func testReviewHelpMatchesRustOracleModuloWhitespace() throws {
        let oracle = try RuntimeOracle.required()

        let rust = try oracle.run(.rust, arguments: ["review", "--help"])
        let swift = try oracle.run(.swift, arguments: ["review", "--help"])

        XCTAssertEqual(rust.exitCode, 0, rust.stderr)
        XCTAssertEqual(swift.exitCode, 0, swift.stderr)

        XCTAssertEqual(normalizedHelp(swift.stdout), normalizedHelp(rust.stdout))
    }

    func testCompletionHelpMatchesRustOracleModuloWhitespace() throws {
        let oracle = try RuntimeOracle.required()

        let rust = try oracle.run(.rust, arguments: ["completion", "--help"])
        let swift = try oracle.run(.swift, arguments: ["completion", "--help"])

        XCTAssertEqual(rust.exitCode, 0, rust.stderr)
        XCTAssertEqual(swift.exitCode, 0, swift.stderr)

        XCTAssertEqual(normalizedHelp(swift.stdout), normalizedHelp(rust.stdout))
    }

    func testLoginHelpMatchesRustOracleModuloWhitespace() throws {
        let oracle = try RuntimeOracle.required()

        let rust = try oracle.run(.rust, arguments: ["login", "--help"])
        let swift = try oracle.run(.swift, arguments: ["login", "--help"])

        XCTAssertEqual(rust.exitCode, 0, rust.stderr)
        XCTAssertEqual(swift.exitCode, 0, swift.stderr)

        XCTAssertEqual(normalizedHelp(swift.stdout), normalizedHelp(rust.stdout))
    }

    func testLoginChildHelpMatchesRustOracleModuloWhitespace() throws {
        let oracle = try RuntimeOracle.required()

        let rust = try oracle.run(.rust, arguments: ["login", "status", "--help"])
        let swift = try oracle.run(.swift, arguments: ["login", "status", "--help"])

        XCTAssertEqual(rust.exitCode, 0, rust.stderr)
        XCTAssertEqual(swift.exitCode, 0, swift.stderr)

        XCTAssertEqual(normalizedHelp(swift.stdout), normalizedHelp(rust.stdout))
    }

    func testLogoutHelpMatchesRustOracleModuloWhitespace() throws {
        let oracle = try RuntimeOracle.required()

        let rust = try oracle.run(.rust, arguments: ["logout", "--help"])
        let swift = try oracle.run(.swift, arguments: ["logout", "--help"])

        XCTAssertEqual(rust.exitCode, 0, rust.stderr)
        XCTAssertEqual(swift.exitCode, 0, swift.stderr)

        XCTAssertEqual(normalizedHelp(swift.stdout), normalizedHelp(rust.stdout))
    }

    func testMcpHelpMatchesRustOracleModuloWhitespace() throws {
        let oracle = try RuntimeOracle.required()

        let rust = try oracle.run(.rust, arguments: ["mcp", "--help"])
        let swift = try oracle.run(.swift, arguments: ["mcp", "--help"])

        XCTAssertEqual(rust.exitCode, 0, rust.stderr)
        XCTAssertEqual(swift.exitCode, 0, swift.stderr)

        XCTAssertEqual(normalizedHelp(swift.stdout), normalizedHelp(rust.stdout))
    }

    func testMcpChildHelpMatchesRustOracleModuloWhitespace() throws {
        let oracle = try RuntimeOracle.required()
        let commands = [
            ["mcp", "list", "--help"],
            ["mcp", "get", "--help"],
            ["mcp", "add", "--help"],
            ["mcp", "remove", "--help"],
            ["mcp", "login", "--help"],
            ["mcp", "logout", "--help"]
        ]

        for arguments in commands {
            let rust = try oracle.run(.rust, arguments: arguments)
            let swift = try oracle.run(.swift, arguments: arguments)

            XCTAssertEqual(rust.exitCode, 0, rust.stderr)
            XCTAssertEqual(swift.exitCode, 0, swift.stderr)
            XCTAssertEqual(normalizedHelp(swift.stdout), normalizedHelp(rust.stdout), arguments.joined(separator: " "))
        }
    }

    func testPluginHelpMatchesRustOracleModuloWhitespace() throws {
        let oracle = try RuntimeOracle.required()

        let rust = try oracle.run(.rust, arguments: ["plugin", "--help"])
        let swift = try oracle.run(.swift, arguments: ["plugin", "--help"])

        XCTAssertEqual(rust.exitCode, 0, rust.stderr)
        XCTAssertEqual(swift.exitCode, 0, swift.stderr)

        XCTAssertEqual(normalizedHelp(swift.stdout), normalizedHelp(rust.stdout))
    }

    func testPluginChildHelpMatchesRustOracleModuloWhitespace() throws {
        let oracle = try RuntimeOracle.required()
        let commands = [
            ["plugin", "add", "--help"],
            ["plugin", "list", "--help"],
            ["plugin", "remove", "--help"],
            ["plugin", "marketplace", "--help"],
            ["plugin", "marketplace", "add", "--help"],
            ["plugin", "marketplace", "list", "--help"],
            ["plugin", "marketplace", "remove", "--help"],
            ["plugin", "marketplace", "upgrade", "--help"]
        ]

        for arguments in commands {
            let rust = try oracle.run(.rust, arguments: arguments)
            let swift = try oracle.run(.swift, arguments: arguments)

            XCTAssertEqual(rust.exitCode, 0, rust.stderr)
            XCTAssertEqual(swift.exitCode, 0, swift.stderr)
            XCTAssertEqual(normalizedHelp(swift.stdout), normalizedHelp(rust.stdout), arguments.joined(separator: " "))
        }
    }

    func testUpdateHelpMatchesRustOracleModuloWhitespace() throws {
        let oracle = try RuntimeOracle.required()

        let rust = try oracle.run(.rust, arguments: ["update", "--help"])
        let swift = try oracle.run(.swift, arguments: ["update", "--help"])

        XCTAssertEqual(rust.exitCode, 0, rust.stderr)
        XCTAssertEqual(swift.exitCode, 0, swift.stderr)

        XCTAssertEqual(normalizedHelp(swift.stdout), normalizedHelp(rust.stdout))
    }

    func testDoctorHelpMatchesRustOracleModuloWhitespace() throws {
        let oracle = try RuntimeOracle.required()

        let rust = try oracle.run(.rust, arguments: ["doctor", "--help"])
        let swift = try oracle.run(.swift, arguments: ["doctor", "--help"])

        XCTAssertEqual(rust.exitCode, 0, rust.stderr)
        XCTAssertEqual(swift.exitCode, 0, swift.stderr)

        XCTAssertEqual(normalizedHelp(swift.stdout), normalizedHelp(rust.stdout))
    }

    func testSandboxHelpMatchesRustOracleModuloWhitespace() throws {
        let oracle = try RuntimeOracle.required()

        let rust = try oracle.run(.rust, arguments: ["sandbox", "--help"])
        let swift = try oracle.run(.swift, arguments: ["sandbox", "--help"])

        XCTAssertEqual(rust.exitCode, 0, rust.stderr)
        XCTAssertEqual(swift.exitCode, 0, swift.stderr)

        XCTAssertEqual(normalizedHelp(swift.stdout), normalizedHelp(rust.stdout))
    }

    func testSandboxChildHelpMatchesRustOracleModuloWhitespace() throws {
        let oracle = try RuntimeOracle.required()
        let commands = [
            ["sandbox", "macos", "--help"],
            ["sandbox", "seatbelt", "--help"],
            ["sandbox", "linux", "--help"],
            ["sandbox", "landlock", "--help"],
            ["sandbox", "windows", "--help"]
        ]

        for arguments in commands {
            let rust = try oracle.run(.rust, arguments: arguments)
            let swift = try oracle.run(.swift, arguments: arguments)

            XCTAssertEqual(rust.exitCode, 0, rust.stderr)
            XCTAssertEqual(swift.exitCode, 0, swift.stderr)
            XCTAssertEqual(normalizedHelp(swift.stdout), normalizedHelp(rust.stdout), arguments.joined(separator: " "))
        }
    }

    func testDebugHelpMatchesRustOracleModuloWhitespace() throws {
        let oracle = try RuntimeOracle.required()

        let rust = try oracle.run(.rust, arguments: ["debug", "--help"])
        let swift = try oracle.run(.swift, arguments: ["debug", "--help"])

        XCTAssertEqual(rust.exitCode, 0, rust.stderr)
        XCTAssertEqual(swift.exitCode, 0, swift.stderr)

        XCTAssertEqual(normalizedHelp(swift.stdout), normalizedHelp(rust.stdout))
    }

    func testDebugChildHelpMatchesRustOracleModuloWhitespace() throws {
        let oracle = try RuntimeOracle.required()
        let commands = [
            ["debug", "models", "--help"],
            ["debug", "app-server", "--help"],
            ["debug", "app-server", "send-message-v2", "--help"],
            ["debug", "prompt-input", "--help"],
            ["debug", "trace-reduce", "--help"],
            ["debug", "clear-memories", "--help"]
        ]

        for arguments in commands {
            let rust = try oracle.run(.rust, arguments: arguments)
            let swift = try oracle.run(.swift, arguments: arguments)

            XCTAssertEqual(rust.exitCode, 0, rust.stderr)
            XCTAssertEqual(swift.exitCode, 0, swift.stderr)
            XCTAssertEqual(normalizedHelp(swift.stdout), normalizedHelp(rust.stdout), arguments.joined(separator: " "))
        }
    }

    func testExecPolicyHelpMatchesRustOracleModuloWhitespace() throws {
        let oracle = try RuntimeOracle.required()

        let rust = try oracle.run(.rust, arguments: ["execpolicy", "--help"])
        let swift = try oracle.run(.swift, arguments: ["execpolicy", "--help"])

        XCTAssertEqual(rust.exitCode, 0, rust.stderr)
        XCTAssertEqual(swift.exitCode, 0, swift.stderr)

        XCTAssertEqual(normalizedHelp(swift.stdout), normalizedHelp(rust.stdout))
    }

    func testExecPolicyChildHelpMatchesRustOracleModuloWhitespace() throws {
        let oracle = try RuntimeOracle.required()

        let rust = try oracle.run(.rust, arguments: ["execpolicy", "check", "--help"])
        let swift = try oracle.run(.swift, arguments: ["execpolicy", "check", "--help"])

        XCTAssertEqual(rust.exitCode, 0, rust.stderr)
        XCTAssertEqual(swift.exitCode, 0, swift.stderr)

        XCTAssertEqual(normalizedHelp(swift.stdout), normalizedHelp(rust.stdout))
    }

    func testApplyHelpMatchesRustOracleModuloWhitespace() throws {
        let oracle = try RuntimeOracle.required()

        let rust = try oracle.run(.rust, arguments: ["apply", "--help"])
        let swift = try oracle.run(.swift, arguments: ["apply", "--help"])

        XCTAssertEqual(rust.exitCode, 0, rust.stderr)
        XCTAssertEqual(swift.exitCode, 0, swift.stderr)

        XCTAssertEqual(normalizedHelp(swift.stdout), normalizedHelp(rust.stdout))
    }

    func testAppServerHelpMatchesRustOracleModuloWhitespace() throws {
        let oracle = try RuntimeOracle.required()

        let rust = try oracle.run(.rust, arguments: ["app-server", "--help"])
        let swift = try oracle.run(.swift, arguments: ["app-server", "--help"])

        XCTAssertEqual(rust.exitCode, 0, rust.stderr)
        XCTAssertEqual(swift.exitCode, 0, swift.stderr)

        XCTAssertEqual(normalizedHelp(swift.stdout), normalizedHelp(rust.stdout))
    }

    func testAppServerChildHelpMatchesRustOracleModuloWhitespace() throws {
        let oracle = try RuntimeOracle.required()
        let commands = [
            ["app-server", "daemon", "--help"],
            ["app-server", "daemon", "bootstrap", "--help"],
            ["app-server", "daemon", "start", "--help"],
            ["app-server", "daemon", "restart", "--help"],
            ["app-server", "daemon", "enable-remote-control", "--help"],
            ["app-server", "daemon", "disable-remote-control", "--help"],
            ["app-server", "daemon", "stop", "--help"],
            ["app-server", "daemon", "version", "--help"],
            ["app-server", "daemon", "pid-update-loop", "--help"],
            ["app-server", "proxy", "--help"],
            ["app-server", "generate-ts", "--help"],
            ["app-server", "generate-json-schema", "--help"],
            ["app-server", "generate-internal-json-schema", "--help"]
        ]

        for arguments in commands {
            let rust = try oracle.run(.rust, arguments: arguments)
            let swift = try oracle.run(.swift, arguments: arguments)

            XCTAssertEqual(rust.exitCode, 0, rust.stderr)
            XCTAssertEqual(swift.exitCode, 0, swift.stderr)
            XCTAssertEqual(normalizedHelp(swift.stdout), normalizedHelp(rust.stdout), arguments.joined(separator: " "))
        }
    }

    func testRemoteControlHelpMatchesRustOracleModuloWhitespace() throws {
        let oracle = try RuntimeOracle.required()

        let rust = try oracle.run(.rust, arguments: ["remote-control", "--help"])
        let swift = try oracle.run(.swift, arguments: ["remote-control", "--help"])

        XCTAssertEqual(rust.exitCode, 0, rust.stderr)
        XCTAssertEqual(swift.exitCode, 0, swift.stderr)

        XCTAssertEqual(normalizedHelp(swift.stdout), normalizedHelp(rust.stdout))
    }

    func testRemoteControlChildHelpMatchesRustOracleModuloWhitespace() throws {
        let oracle = try RuntimeOracle.required()
        let commands = [
            ["remote-control", "start", "--help"],
            ["remote-control", "stop", "--help"]
        ]

        for arguments in commands {
            let rust = try oracle.run(.rust, arguments: arguments)
            let swift = try oracle.run(.swift, arguments: arguments)

            XCTAssertEqual(rust.exitCode, 0, rust.stderr)
            XCTAssertEqual(swift.exitCode, 0, swift.stderr)
            XCTAssertEqual(normalizedHelp(swift.stdout), normalizedHelp(rust.stdout), arguments.joined(separator: " "))
        }
    }

    func testFeaturesHelpMatchesRustOracleModuloWhitespace() throws {
        let oracle = try RuntimeOracle.required()

        let rust = try oracle.run(.rust, arguments: ["features", "--help"])
        let swift = try oracle.run(.swift, arguments: ["features", "--help"])

        XCTAssertEqual(rust.exitCode, 0, rust.stderr)
        XCTAssertEqual(swift.exitCode, 0, swift.stderr)

        XCTAssertEqual(normalizedHelp(swift.stdout), normalizedHelp(rust.stdout))
    }

    func testFeaturesChildHelpMatchesRustOracleModuloWhitespace() throws {
        let oracle = try RuntimeOracle.required()
        let commands = [
            ["features", "list", "--help"],
            ["features", "enable", "--help"],
            ["features", "disable", "--help"]
        ]

        for arguments in commands {
            let rust = try oracle.run(.rust, arguments: arguments)
            let swift = try oracle.run(.swift, arguments: arguments)

            XCTAssertEqual(rust.exitCode, 0, rust.stderr)
            XCTAssertEqual(swift.exitCode, 0, swift.stderr)
            XCTAssertEqual(normalizedHelp(swift.stdout), normalizedHelp(rust.stdout), arguments.joined(separator: " "))
        }
    }

    func testMcpServerHelpMatchesRustOracleModuloWhitespace() throws {
        let oracle = try RuntimeOracle.required()

        let rust = try oracle.run(.rust, arguments: ["mcp-server", "--help"])
        let swift = try oracle.run(.swift, arguments: ["mcp-server", "--help"])

        XCTAssertEqual(rust.exitCode, 0, rust.stderr)
        XCTAssertEqual(swift.exitCode, 0, swift.stderr)

        XCTAssertEqual(normalizedHelp(swift.stdout), normalizedHelp(rust.stdout))
    }

    func testAppHelpMatchesRustOracleModuloWhitespace() throws {
        let oracle = try RuntimeOracle.required()

        let rust = try oracle.run(.rust, arguments: ["app", "--help"])
        let swift = try oracle.run(.swift, arguments: ["app", "--help"])

        XCTAssertEqual(rust.exitCode, 0, rust.stderr)
        XCTAssertEqual(swift.exitCode, 0, swift.stderr)

        XCTAssertEqual(normalizedHelp(swift.stdout), normalizedHelp(rust.stdout))
    }

    func testExecServerHelpMatchesRustOracleModuloWhitespace() throws {
        let oracle = try RuntimeOracle.required()

        let rust = try oracle.run(.rust, arguments: ["exec-server", "--help"])
        let swift = try oracle.run(.swift, arguments: ["exec-server", "--help"])

        XCTAssertEqual(rust.exitCode, 0, rust.stderr)
        XCTAssertEqual(swift.exitCode, 0, swift.stderr)

        XCTAssertEqual(normalizedHelp(swift.stdout), normalizedHelp(rust.stdout))
    }

    func testResumeHelpMatchesRustOracleModuloWhitespace() throws {
        let oracle = try RuntimeOracle.required()

        let rust = try oracle.run(.rust, arguments: ["resume", "--help"])
        let swift = try oracle.run(.swift, arguments: ["resume", "--help"])

        XCTAssertEqual(rust.exitCode, 0, rust.stderr)
        XCTAssertEqual(swift.exitCode, 0, swift.stderr)

        XCTAssertEqual(normalizedHelp(swift.stdout), normalizedHelp(rust.stdout))
    }

    func testForkHelpMatchesRustOracleModuloWhitespace() throws {
        let oracle = try RuntimeOracle.required()

        let rust = try oracle.run(.rust, arguments: ["fork", "--help"])
        let swift = try oracle.run(.swift, arguments: ["fork", "--help"])

        XCTAssertEqual(rust.exitCode, 0, rust.stderr)
        XCTAssertEqual(swift.exitCode, 0, swift.stderr)

        XCTAssertEqual(normalizedHelp(swift.stdout), normalizedHelp(rust.stdout))
    }

    func testCloudHelpMatchesRustOracleModuloWhitespace() throws {
        let oracle = try RuntimeOracle.required()

        let rust = try oracle.run(.rust, arguments: ["cloud", "--help"])
        let swift = try oracle.run(.swift, arguments: ["cloud", "--help"])

        XCTAssertEqual(rust.exitCode, 0, rust.stderr)
        XCTAssertEqual(swift.exitCode, 0, swift.stderr)

        XCTAssertEqual(normalizedHelp(swift.stdout), normalizedHelp(rust.stdout))
    }

    func testCloudChildHelpMatchesRustOracleModuloWhitespace() throws {
        let oracle = try RuntimeOracle.required()
        let commands = [
            ["cloud", "exec", "--help"],
            ["cloud", "status", "--help"],
            ["cloud", "list", "--help"],
            ["cloud", "apply", "--help"],
            ["cloud", "diff", "--help"]
        ]

        for arguments in commands {
            let rust = try oracle.run(.rust, arguments: arguments)
            let swift = try oracle.run(.swift, arguments: arguments)

            XCTAssertEqual(rust.exitCode, 0, rust.stderr)
            XCTAssertEqual(swift.exitCode, 0, swift.stderr)
            XCTAssertEqual(normalizedHelp(swift.stdout), normalizedHelp(rust.stdout), arguments.joined(separator: " "))
        }
    }

    func testResponsesAPIProxyHelpMatchesRustOracleModuloWhitespace() throws {
        let oracle = try RuntimeOracle.required()

        let rust = try oracle.run(.rust, arguments: ["responses-api-proxy", "--help"])
        let swift = try oracle.run(.swift, arguments: ["responses-api-proxy", "--help"])

        XCTAssertEqual(rust.exitCode, 0, rust.stderr)
        XCTAssertEqual(swift.exitCode, 0, swift.stderr)

        XCTAssertEqual(normalizedHelp(swift.stdout), normalizedHelp(rust.stdout))
    }

    func testStdioToUDSHelpMatchesRustOracleModuloWhitespace() throws {
        let oracle = try RuntimeOracle.required()

        let rust = try oracle.run(.rust, arguments: ["stdio-to-uds", "--help"])
        let swift = try oracle.run(.swift, arguments: ["stdio-to-uds", "--help"])

        XCTAssertEqual(rust.exitCode, 0, rust.stderr)
        XCTAssertEqual(swift.exitCode, 0, swift.stderr)

        XCTAssertEqual(normalizedHelp(swift.stdout), normalizedHelp(rust.stdout))
    }

    func testExecVersionMatchesRustOracleModuloVersionNumber() throws {
        let oracle = try RuntimeOracle.required()

        let rust = try oracle.run(.rust, arguments: ["exec", "--version"])
        let swift = try oracle.run(.swift, arguments: ["exec", "--version"])

        XCTAssertEqual(rust.exitCode, 0, rust.stderr)
        XCTAssertEqual(swift.exitCode, 0, swift.stderr)

        XCTAssertEqual(normalizedVersionLine(swift.stdout), normalizedVersionLine(rust.stdout))
    }

    func testCloudVersionMatchesRustOracleModuloVersionNumber() throws {
        let oracle = try RuntimeOracle.required()

        let rust = try oracle.run(.rust, arguments: ["cloud", "--version"])
        let swift = try oracle.run(.swift, arguments: ["cloud", "--version"])

        XCTAssertEqual(rust.exitCode, 0, rust.stderr)
        XCTAssertEqual(swift.exitCode, 0, swift.stderr)

        XCTAssertEqual(normalizedVersionLine(swift.stdout), normalizedVersionLine(rust.stdout))
    }

    func testInteractivePickerVersionCommandsMatchRustOracleModuloVersionNumber() throws {
        let oracle = try RuntimeOracle.required()
        let commands = [
            ["resume", "--version"],
            ["fork", "--version"]
        ]

        for arguments in commands {
            let rust = try oracle.run(.rust, arguments: arguments)
            let swift = try oracle.run(.swift, arguments: arguments)

            XCTAssertEqual(rust.exitCode, 0, rust.stderr)
            XCTAssertEqual(swift.exitCode, 0, swift.stderr)
            XCTAssertEqual(
                normalizedVersionLine(swift.stdout),
                normalizedVersionLine(rust.stdout),
                arguments.joined(separator: " ")
            )
        }
    }

    func testReviewVersionRejectionMatchesRustOracle() throws {
        let oracle = try RuntimeOracle.required()
        let codexHome = try RuntimeOracleTemporaryDirectory(prefix: "codex-runtime-oracle-home")
        let environment = [
            "CODEX_HOME": codexHome.url.path,
            "NO_COLOR": "1",
            "TERM": "dumb"
        ]

        let rust = try oracle.run(.rust, arguments: ["review", "--version"], environment: environment)
        let swift = try oracle.run(.swift, arguments: ["review", "--version"], environment: environment)

        XCTAssertEqual(rust.exitCode, 2, rust.stderr)
        XCTAssertEqual(swift.exitCode, 2, swift.stderr)
        XCTAssertEqual(swift.stdout, rust.stdout)
        XCTAssertEqual(normalizedCommandError(swift.stderr), normalizedCommandError(rust.stderr))
    }

    func testUnknownHelpSubcommandMatchesRustOracle() throws {
        let oracle = try RuntimeOracle.required()

        let rust = try oracle.run(.rust, arguments: ["help", "unknown"])
        let swift = try oracle.run(.swift, arguments: ["help", "unknown"])

        XCTAssertEqual(rust.exitCode, 2, rust.stderr)
        XCTAssertEqual(swift.exitCode, 2, swift.stderr)
        XCTAssertEqual(swift.stdout, rust.stdout)
        XCTAssertEqual(normalizedCommandError(swift.stderr), normalizedCommandError(rust.stderr))
    }

    func testUnknownChildHelpSubcommandsMatchRustOracle() throws {
        let oracle = try RuntimeOracle.required()
        let commands = [
            ["help", "mcp", "unknown"],
            ["mcp", "unknown", "--help"],
            ["plugin", "unknown", "--help"],
            ["plugin", "marketplace", "unknown", "--help"],
            ["app-server", "unknown", "--help"],
            ["app-server", "daemon", "unknown", "--help"],
            ["remote-control", "unknown", "--help"],
            ["sandbox", "unknown", "--help"],
            ["debug", "unknown", "--help"],
            ["debug", "app-server", "unknown", "--help"],
            ["execpolicy", "unknown", "--help"],
            ["cloud", "unknown", "--help"],
            ["features", "unknown", "--help"],
            ["login", "unknown", "--help"]
        ]

        for arguments in commands {
            let rust = try oracle.run(.rust, arguments: arguments)
            let swift = try oracle.run(.swift, arguments: arguments)

            XCTAssertEqual(rust.exitCode, 2, rust.stderr)
            XCTAssertEqual(swift.exitCode, 2, swift.stderr)
            XCTAssertEqual(swift.stdout, rust.stdout, arguments.joined(separator: " "))
            XCTAssertEqual(
                normalizedCommandError(swift.stderr),
                normalizedCommandError(rust.stderr),
                arguments.joined(separator: " ")
            )
        }
    }

    func testMissingChildSubcommandsRenderRustShortHelpOnStderr() throws {
        let oracle = try RuntimeOracle.required()
        let commands = [
            ["mcp"],
            ["plugin"],
            ["plugin", "marketplace"],
            ["sandbox"],
            ["debug"],
            ["debug", "app-server"],
            ["features"],
            ["execpolicy"],
            ["app-server", "daemon"]
        ]

        for arguments in commands {
            let rust = try oracle.run(.rust, arguments: arguments)
            let swift = try oracle.run(.swift, arguments: arguments)

            XCTAssertEqual(rust.exitCode, 2, rust.stderr)
            XCTAssertEqual(swift.exitCode, 2, swift.stderr)
            XCTAssertEqual(swift.stdout, rust.stdout, arguments.joined(separator: " "))
            XCTAssertEqual(
                normalizedHelp(swift.stderr),
                normalizedHelp(rust.stderr),
                arguments.joined(separator: " ")
            )
        }
    }

    func testCommandParseFailuresMatchRustClapDiagnostics() throws {
        let oracle = try RuntimeOracle.required()
        let commands = [
            ["mcp", "get"],
            ["mcp", "get", "docs", "extra"],
            ["mcp", "get", "--bad"],
            ["mcp", "add"],
            ["mcp", "add", "docs"],
            ["mcp", "add", "docs", "--env"],
            ["mcp", "add", "docs", "--env", "BROKEN"],
            ["mcp", "add", "--url", "https://example.com/mcp"],
            ["mcp", "add", "--bad"],
            ["mcp", "add", "docs", "--unknown"],
            ["mcp", "add", "docs", "--url", "https://example.com/mcp", "--", "echo"],
            ["mcp", "add", "docs", "--url", "https://one.example/mcp", "--url=https://two.example/mcp"],
            [
                "mcp", "add", "docs", "--url", "https://example.com/mcp",
                "--bearer-token-env-var", "TOKEN_A", "--bearer-token-env-var=TOKEN_B"
            ],
            ["mcp", "add", "docs", "--bearer-token-env-var"],
            ["mcp", "add", "docs", "--bearer-token-env-var", "TOKEN"],
            ["mcp", "login", "docs", "--scopes"],
            ["mcp", "login", "docs", "extra"],
            ["mcp", "login", "--bad"],
            ["mcp", "remove", "docs", "extra"],
            ["mcp", "remove", "--bad"],
            ["mcp", "logout", "docs", "extra"],
            ["mcp", "logout", "--bad"],
            ["plugin", "install"],
            ["plugin", "add"],
            ["plugin", "add", "--bad"],
            ["plugin", "add", "weather", "--marketplace", "debug", "--marketplace=other"],
            ["plugin", "add", "weather", "extra"],
            ["plugin", "list", "extra"],
            ["plugin", "list", "--bad"],
            ["plugin", "list", "--marketplace", "debug", "-m", "other"],
            ["plugin", "marketplace", "list", "extra"],
            ["plugin", "marketplace", "list", "--bad"],
            ["plugin", "marketplace", "remove"],
            ["plugin", "marketplace", "remove", "--bad"],
            ["plugin", "marketplace", "remove", "debug", "extra"],
            ["plugin", "marketplace", "add", "--bad"],
            ["plugin", "marketplace", "add", "owner/repo", "extra"],
            ["plugin", "marketplace", "add", "--ref", "main", "owner/repo", "--ref=next"],
            ["plugin", "marketplace", "upgrade", "--all"],
            ["plugin", "marketplace", "upgrade", "debug", "extra"],
            ["apply"],
            ["stdio-to-uds"],
            ["cloud", "bogus"],
            ["cloud", "exec"],
            ["cloud", "exec", "--bad"],
            ["cloud", "exec", "--env", "env_123", "query", "extra"],
            ["cloud", "exec", "--env", "env_123", "--attempts", "abc"],
            ["cloud", "exec", "--env", "env_123", "--attempts", "0"],
            ["cloud", "exec", "--env", "env_123", "--attempts", "1", "--attempts", "2"],
            ["cloud", "exec", "--env", "env_123", "--env", "other"],
            ["cloud", "list", "extra"],
            ["cloud", "list", "--bad"],
            ["cloud", "list", "--env"],
            ["cloud", "list", "--env", "env_a", "--env", "env_b"],
            ["cloud", "list", "--limit"],
            ["cloud", "list", "--limit", "abc"],
            ["cloud", "list", "--limit", "0"],
            ["cloud", "list", "--limit", "1", "--limit", "2"],
            ["cloud", "list", "--cursor", "a", "--cursor", "b"],
            ["cloud", "status", "--attempt", "2", "task_123"],
            ["cloud", "status", "task_123", "extra"],
            ["cloud", "status", "--bad"],
            ["cloud", "diff", "task_123", "--attempt"],
            ["cloud", "diff", "task_123", "--attempt", "abc"],
            ["cloud", "diff", "task_123", "--attempt", "0"],
            ["cloud", "diff", "task_123", "--attempt", "1", "--attempt", "2"],
            ["cloud", "diff", "task_123", "--bad"],
            ["cloud", "diff", "task_123", "extra"],
            ["cloud", "apply", "task_123", "--attempt", "abc"],
            ["cloud", "apply", "task_123", "--attempt", "1", "--attempt", "2"],
            ["exec", "--output-schema"],
            ["exec", "--output-last-message"],
            ["exec", "--image"],
            ["exec", "--cd"],
            ["exec", "--model"],
            ["exec", "--config"],
            ["exec", "--color"],
            ["exec", "--bad"],
            ["exec", "ship", "extra"],
            ["exec", "--full-auto", "--dangerously-bypass-approvals-and-sandbox", "ship"],
            ["exec", "--dangerously-bypass-approvals-and-sandbox", "--full-auto", "ship"],
            ["exec", "resume", "--last", "--output-last-message"],
            ["exec", "resume", "--last", "--image"],
            ["exec", "resume", "--last", "--model"],
            ["exec", "resume", "--last", "--config"],
            ["exec", "resume", "sid", "prompt", "extra"],
            ["exec", "resume", "--last", "--full-auto", "--yolo", "prompt"],
            ["features", "list", "extra"],
            ["features", "enable"],
            ["features", "enable", "runtime_metrics", "extra"],
            ["features", "disable"],
            ["features", "disable", "shell_tool", "extra"],
            ["features", "bogus"],
            ["execpolicy", "check"],
            ["execpolicy", "check", "git", "status"],
            ["execpolicy", "check", "--rules"],
            ["execpolicy", "check", "--rules=policy.rules"],
            ["execpolicy", "check", "--pretty"],
            ["execpolicy", "check", "--pretty", "--rules", "policy.rules"],
            ["execpolicy", "check", "-rpolicy.rules", "--flaggy"],
            ["execpolicy", "bogus"],
            ["app-server", "--bad"],
            ["app-server", "bogus"],
            ["app-server", "proxy", "--bad"],
            ["app-server", "proxy", "extra"],
            ["app-server", "proxy", "--sock"],
            ["app-server", "proxy", "--sock", "/tmp/a", "--sock", "/tmp/b"],
            ["app-server", "generate-ts"],
            ["app-server", "generate-ts", "--out"],
            ["app-server", "generate-ts", "--bad"],
            ["app-server", "generate-ts", "extra"],
            ["app-server", "generate-ts", "--out", "/tmp/a", "--out", "/tmp/b"],
            ["app-server", "generate-ts", "--out", "/tmp/a", "--prettier", "p", "--prettier", "q"],
            ["app-server", "generate-json-schema"],
            ["app-server", "generate-json-schema", "--out"],
            ["app-server", "generate-json-schema", "--bad"],
            ["app-server", "generate-json-schema", "--prettier", "prettier", "--out", "/tmp/schema"],
            ["app-server", "generate-json-schema", "--out", "/tmp/a", "--out", "/tmp/b"],
            ["app-server", "generate-internal-json-schema"],
            ["app-server", "generate-internal-json-schema", "--out"],
            ["app-server", "generate-internal-json-schema", "--bad"],
            ["app-server", "daemon", "bogus"],
            ["app-server", "daemon", "start", "extra"],
            ["app-server", "daemon", "start", "--remote-control"],
            ["app-server", "daemon", "pid-update-loop", "--bad"],
            ["app-server", "daemon", "bootstrap", "extra"],
            ["app-server", "daemon", "bootstrap", "--remote-control", "extra"],
            ["app-server", "daemon", "bootstrap", "--bad"],
            ["remote-control", "bogus"],
            ["remote-control", "--listen"],
            ["remote-control", "start", "extra"],
            ["remote-control", "start", "--listen"],
            ["remote-control", "stop", "extra"],
            ["remote-control", "stop", "--listen"],
            ["sandbox", "freebsd"],
            ["sandbox", "linux", "--log-denials"],
            ["sandbox", "linux", "--full-auto"],
            ["sandbox", "linux", "--allow-unix-socket=/tmp"],
            ["sandbox", "macos", "--full-auto"],
            ["sandbox", "windows", "--foo=bar"],
            ["debug", "bogus"],
            ["debug", "models", "extra"],
            ["debug", "models", "--bad"],
            ["debug", "app-server", "bogus"],
            ["debug", "app-server", "send-message-v2"],
            ["debug", "app-server", "send-message-v2", "--bad"],
            ["debug", "prompt-input", "--image"],
            ["debug", "prompt-input", "extra1", "extra2"],
            ["debug", "trace-reduce"],
            ["debug", "trace-reduce", "--output"],
            ["debug", "trace-reduce", "bundle", "extra"],
            ["debug", "trace-reduce", "bundle", "--output", "a.json", "-ob.json"],
            ["debug", "clear-memories", "extra"],
            ["app", "--download-url"],
            ["app", "--download-url", "https://example.test/a", "--download-url", "https://example.test/b"],
            ["app", "--verbose"],
            ["app", "path", "extra"],
            ["update", "now"],
            ["update", "--bad"],
            ["doctor", "repair"],
            ["doctor", "--bad"],
            ["mcp-server", "--bad"],
            ["mcp-server", "extra"],
            ["exec-server", "--listen"],
            ["exec-server", "--remote", "https://registry.example.test"],
            ["exec-server", "--remote", "https://registry.example.test", "--name", "Local Executor"],
            [
                "exec-server",
                "--remote",
                "https://registry.example.test",
                "--name",
                "Local Executor",
                "--use-agent-identity-auth"
            ],
            ["exec-server", "--listen", "stdio", "--remote", "https://registry.example.test"],
            ["exec-server", "--listen", "stdio", "--listen=ws://127.0.0.1:4500"],
            ["exec-server", "--remote", "https://registry.example.test", "--remote=https://other.example.test"],
            ["exec-server", "--remote", "https://registry.example.test", "--executor-id", "exec-1", "--executor-id=exec-2"],
            ["exec-server", "--remote", "https://registry.example.test", "--executor-id", "exec-1", "--name", "a", "--name=b"],
            ["exec-server", "--use-agent-identity-auth"],
            ["exec-server", "--bogus"],
            ["exec-server", "extra"],
            ["exec-server", "--executor-id"],
            ["exec-server", "--name"],
            ["responses-api-proxy", "--port"],
            ["responses-api-proxy", "--port", "abc"],
            ["responses-api-proxy", "--port", "70000"],
            ["responses-api-proxy", "--server-info"],
            ["responses-api-proxy", "--upstream-url"],
            ["responses-api-proxy", "--dump-dir"],
            ["responses-api-proxy", "--bad"],
            ["responses-api-proxy", "extra"]
        ]

        for arguments in commands {
            let rust = try oracle.run(.rust, arguments: arguments)
            let swift = try oracle.run(.swift, arguments: arguments)

            XCTAssertEqual(rust.exitCode, 2, rust.stderr)
            XCTAssertEqual(swift.exitCode, 2, swift.stderr)
            XCTAssertEqual(swift.stdout, rust.stdout, arguments.joined(separator: " "))
            XCTAssertEqual(
                normalizedCommandError(swift.stderr),
                normalizedCommandError(rust.stderr),
                arguments.joined(separator: " ")
            )
        }
    }

    func testSubcommandVersionRejectionsMatchRustOracle() throws {
        let oracle = try RuntimeOracle.required()
        let commands = [
            ["app-server", "--version"],
            ["remote-control", "--version"],
            ["apply", "--version"],
            ["debug", "--version"],
            ["sandbox", "--version"],
            ["app", "--version"],
            ["login", "--version"],
            ["execpolicy", "--version"],
            ["responses-api-proxy", "--version"],
            ["stdio-to-uds", "--version"]
        ]
        let codexHome = try RuntimeOracleTemporaryDirectory(prefix: "codex-runtime-oracle-home")
        let environment = [
            "CODEX_HOME": codexHome.url.path,
            "NO_COLOR": "1",
            "TERM": "dumb"
        ]

        for arguments in commands {
            let rust = try oracle.run(.rust, arguments: arguments, environment: environment)
            let swift = try oracle.run(.swift, arguments: arguments, environment: environment)

            XCTAssertEqual(rust.exitCode, 2, rust.stderr)
            XCTAssertEqual(swift.exitCode, 2, swift.stderr)
            XCTAssertEqual(swift.stdout, rust.stdout, arguments.joined(separator: " "))
            XCTAssertEqual(
                normalizedCommandError(swift.stderr),
                normalizedCommandError(rust.stderr),
                arguments.joined(separator: " ")
            )
        }
    }

    func testAppServerInitializeMatchesRustOracle() throws {
        let oracle = try RuntimeOracle.required()
        let request = """
        {"id":1,"method":"initialize","params":{"clientInfo":{"name":"oracle","version":"0"},"capabilities":{"optOutNotificationMethods":["remoteControl/status/changed"]}}}

        """

        let rust = try oracle.runAppServer(.rust, arguments: ["app-server"], stdin: request)
        let swift = try oracle.runAppServer(.swift, arguments: ["app-server"], stdin: request)

        XCTAssertEqual(rust.exitCode, 0, rust.stderr)
        XCTAssertEqual(swift.exitCode, 0, swift.stderr)

        XCTAssertEqual(
            try normalizedAppServerMessages(swift.stdout),
            try normalizedAppServerMessages(rust.stdout)
        )
    }

    func testNonInteractiveNoToolsPromptMatchesRustOracle() throws {
        let oracle = try RuntimeOracle.required()
        let server = try RuntimeOracleResponsesServer(
            responseBodies: [
                noToolsAssistantMessageSSE(text: "oracle says hi"),
                noToolsAssistantMessageSSE(text: "oracle says hi")
            ]
        )

        let rust = try oracle.runNonInteractiveExec(
            .rust,
            responsesBaseURL: server.baseURL,
            prompt: "oracle prompt"
        )
        let swift = try oracle.runNonInteractiveExec(
            .swift,
            responsesBaseURL: server.baseURL,
            prompt: "oracle prompt"
        )

        XCTAssertEqual(rust.exitCode, 0, rust.stderr)
        XCTAssertEqual(swift.exitCode, 0, swift.stderr)

        XCTAssertEqual(
            try normalizedExecJSONLines(swift.stdout),
            try normalizedExecJSONLines(rust.stdout)
        )
    }

    func testNonInteractiveShellCommandToolMatchesRustOracle() throws {
        let command = "printf 'oracle tool\\n'"
        let responseBodies = [
            functionCallSSE(callID: "call-shell", name: "shell_command", arguments: [
                "command": command,
                "login": false
            ]),
            noToolsAssistantMessageSSE(text: "tool complete")
        ]
        XCTAssertEqual(
            ResponsesSSEParser.collectEvents(fromSSEText: responseBodies[0]),
            [
                .success(.created),
                .success(.outputItemDone(.functionCall(
                    name: "shell_command",
                    arguments: #"{"command":"printf 'oracle tool\\n'","login":false}"#,
                    callID: "call-shell"
                ))),
                .success(.completed(responseID: "resp-1", tokenUsage: nil))
            ]
        )
        let oracle = try RuntimeOracle.required()
        let rustServer = try RuntimeOracleResponsesServer(responseBodies: responseBodies)
        let swiftServer = try RuntimeOracleResponsesServer(responseBodies: responseBodies)

        let rust = try oracle.runNonInteractiveExec(
            .rust,
            responsesBaseURL: rustServer.baseURL,
            prompt: "run oracle shell"
        )
        let swift = try oracle.runNonInteractiveExec(
            .swift,
            responsesBaseURL: swiftServer.baseURL,
            prompt: "run oracle shell"
        )

        XCTAssertEqual(rust.exitCode, 0, rust.stderr)
        XCTAssertEqual(swift.exitCode, 0, swift.stderr)

        let normalizedSwiftOutput = try normalizedExecJSONLines(swift.stdout)
        let normalizedRustOutput = try normalizedExecJSONLines(rust.stdout)
        XCTAssertTrue(
            normalizedSwiftOutput.contains { line in
                line.contains(#""type":"command_execution""#)
                    && line.contains(#""aggregated_output":"oracle tool\n""#)
                    && line.contains(#""status":"completed""#)
            },
            normalizedSwiftOutput.joined(separator: "\n")
        )
        XCTAssertEqual(
            normalizedSwiftOutput,
            normalizedRustOutput
        )
    }
}

private enum RuntimeOracleProcessKind {
    case rust
    case swift
}

private struct RuntimeOracle {
    let rustCodex: URL
    let swiftCodex: URL

    static func required() throws -> RuntimeOracle {
        guard ProcessInfo.processInfo.environment["CODEX_RUN_RUST_ORACLE_TESTS"] == "1" else {
            throw XCTSkip("Set CODEX_RUN_RUST_ORACLE_TESTS=1 to run Rust runtime oracle parity tests.")
        }

        let packageRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let rust = try resolveExecutable(
            environmentKey: "CODEX_RUST_BINARY",
            candidates: [
                packageRoot.appendingPathComponent("../codex-rs/target/debug/codex", isDirectory: false),
                packageRoot.appendingPathComponent("../codex/codex-rs/target/debug/codex", isDirectory: false)
            ],
            missingMessage: "Set CODEX_RUST_BINARY to a Rust-built codex executable."
        )
        let swift = try resolveExecutable(
            environmentKey: "SWIFT_CODEX_BINARY",
            candidates: [
                packageRoot.appendingPathComponent(".build/debug/codex", isDirectory: false)
            ],
            missingMessage: "Set SWIFT_CODEX_BINARY to the Swift codex executable, or build it with swift build --product codex."
        )

        return RuntimeOracle(rustCodex: rust, swiftCodex: swift)
    }

    func run(
        _ kind: RuntimeOracleProcessKind,
        arguments: [String],
        stdin: String? = nil,
        environment: [String: String] = [:],
        currentDirectory: URL? = nil,
        keepStdinOpenAfterWrite: TimeInterval = 0
    ) throws -> RuntimeOracleProcessOutput {
        try runProcess(
            executable: executable(for: kind),
            arguments: arguments,
            stdin: stdin,
            environment: environment,
            currentDirectory: currentDirectory,
            keepStdinOpenAfterWrite: keepStdinOpenAfterWrite
        )
    }

    func runAppServer(
        _ kind: RuntimeOracleProcessKind,
        arguments: [String],
        stdin: String
    ) throws -> RuntimeOracleProcessOutput {
        let codexHome = try RuntimeOracleTemporaryDirectory(prefix: "codex-runtime-oracle")
        try """
        [features]
        plugins = false

        """.write(to: codexHome.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        return try run(
            kind,
            arguments: ["--disable", "plugins"] + arguments,
            stdin: stdin,
            environment: [
                "CODEX_HOME": codexHome.url.path,
                "NO_COLOR": "1",
                "TERM": "dumb"
            ],
            keepStdinOpenAfterWrite: 0.5
        )
    }

    func runNonInteractiveExec(
        _ kind: RuntimeOracleProcessKind,
        responsesBaseURL: String,
        prompt: String
    ) throws -> RuntimeOracleProcessOutput {
        let codexHome = try RuntimeOracleTemporaryDirectory(prefix: "codex-runtime-oracle-home")
        let cwd = try RuntimeOracleTemporaryDirectory(prefix: "codex-runtime-oracle-cwd")
        let providerOverride = """
        model_providers.oracle={ name = "Oracle", base_url = "\(responsesBaseURL)", env_key = "CODEX_API_KEY", wire_api = "responses", supports_websockets = false, request_max_retries = 0, stream_max_retries = 0 }
        """

        return try run(
            kind,
            arguments: [
                "--disable", "plugins",
                "-c", #"model_provider="oracle""#,
                "-c", providerOverride,
                "exec",
                "--skip-git-repo-check",
                "--json",
                prompt
            ],
            stdin: nil,
            environment: [
                "CODEX_HOME": codexHome.url.path,
                "CODEX_SQLITE_HOME": codexHome.url.path,
                "CODEX_API_KEY": "dummy",
                "NO_COLOR": "1",
                "TERM": "dumb"
            ],
            currentDirectory: cwd.url
        )
    }

    private func executable(for kind: RuntimeOracleProcessKind) -> URL {
        switch kind {
        case .rust:
            rustCodex
        case .swift:
            swiftCodex
        }
    }
}

private struct RuntimeOracleProcessOutput {
    let exitCode: Int32
    let stdout: String
    let stderr: String
}

private final class RuntimeOracleTemporaryDirectory {
    let url: URL

    init(prefix: String) throws {
        url = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}

private func resolveExecutable(
    environmentKey: String,
    candidates: [URL],
    missingMessage: String
) throws -> URL {
    if let configured = ProcessInfo.processInfo.environment[environmentKey], !configured.isEmpty {
        let url = URL(fileURLWithPath: configured, isDirectory: false).standardizedFileURL
        guard FileManager.default.isExecutableFile(atPath: url.path) else {
            throw XCTSkip("\(environmentKey) is not executable: \(url.path)")
        }
        return url
    }

    for candidate in candidates {
        let url = candidate.standardizedFileURL
        if FileManager.default.isExecutableFile(atPath: url.path) {
            return url
        }
    }

    throw XCTSkip(missingMessage)
}

private func runProcess(
    executable: URL,
    arguments: [String],
    stdin: String?,
    environment: [String: String],
    currentDirectory: URL?,
    keepStdinOpenAfterWrite: TimeInterval
) throws -> RuntimeOracleProcessOutput {
    let process = Process()
    process.executableURL = executable
    process.arguments = arguments
    process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
    process.currentDirectoryURL = currentDirectory

    let stdout = Pipe()
    let stderr = Pipe()
    let input = Pipe()
    process.standardOutput = stdout
    process.standardError = stderr
    process.standardInput = input

    let terminated = DispatchSemaphore(value: 0)
    process.terminationHandler = { _ in terminated.signal() }

    try process.run()
    if let stdin {
        input.fileHandleForWriting.write(Data(stdin.utf8))
    }
    if keepStdinOpenAfterWrite > 0 {
        Thread.sleep(forTimeInterval: keepStdinOpenAfterWrite)
    }
    try? input.fileHandleForWriting.close()

    if terminated.wait(timeout: .now() + .seconds(15)) == .timedOut {
        process.terminate()
        _ = terminated.wait(timeout: .now() + .seconds(2))
        throw RuntimeOracleError.timeout("\(executable.path) \(arguments.joined(separator: " "))")
    }

    return RuntimeOracleProcessOutput(
        exitCode: process.terminationStatus,
        stdout: String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "",
        stderr: String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    )
}

private func normalizedHelp(_ text: String) -> String {
    text
        .replacingOccurrences(of: "\r\n", with: "\n")
        .replacingOccurrences(of: "\u{2011}", with: "-")
        .split(separator: "\n", omittingEmptySubsequences: false)
        .map { line in
            String(line).replacingOccurrences(
                of: #"[ \t]+$"#,
                with: "",
                options: .regularExpression
            )
        }
        .joined(separator: "\n")
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

private func normalizedVersionLine(_ text: String) -> String {
    let normalized = text
        .replacingOccurrences(of: "\r\n", with: "\n")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    let parts = normalized.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
    guard let commandName = parts.first else {
        return normalized
    }
    return "\(commandName) <version>"
}

private func normalizedCommandError(_ text: String) -> String {
    text
        .replacingOccurrences(of: "\r\n", with: "\n")
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

private func normalizedAppServerMessages(_ stdout: String) throws -> [String] {
    try stdout
        .split(separator: "\n")
        .map(String.init)
        .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        .map { line in
            let data = Data(line.utf8)
            guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw RuntimeOracleError.invalidJSONLine(line)
            }
            normalizeAppServerMessage(&object)
            let normalizedData = try JSONSerialization.data(
                withJSONObject: object,
                options: [.sortedKeys]
            )
            return String(data: normalizedData, encoding: .utf8) ?? ""
        }
}

private func normalizedExecJSONLines(_ stdout: String) throws -> [String] {
    try stdout
        .split(separator: "\n")
        .map(String.init)
        .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        .map { line in
            let data = Data(line.utf8)
            guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw RuntimeOracleError.invalidJSONLine(line)
            }
            if object["thread_id"] is String {
                object["thread_id"] = "<THREAD_ID>"
            }
            let normalizedData = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            return String(data: normalizedData, encoding: .utf8) ?? ""
        }
}

private func normalizeAppServerMessage(_ object: inout [String: Any]) {
    if var result = object["result"] as? [String: Any] {
        if result["codexHome"] is String {
            result["codexHome"] = "<CODEX_HOME>"
        }
        if let userAgent = result["userAgent"] as? String {
            result["userAgent"] = normalizeUserAgent(userAgent)
        }
        object["result"] = result
    }

    if var params = object["params"] as? [String: Any] {
        if params["installationId"] is String {
            params["installationId"] = "<INSTALLATION_ID>"
        }
        if params["serverName"] is String {
            params["serverName"] = "<SERVER_NAME>"
        }
        object["params"] = params
    }
}

private func normalizeUserAgent(_ userAgent: String) -> String {
    guard let suffixRange = userAgent.range(of: " dumb (oracle; 0)") else {
        return "<USER_AGENT>"
    }
    return "Codex Desktop/<runtime>\(userAgent[suffixRange.lowerBound...])"
}

private func noToolsAssistantMessageSSE(text: String) -> String {
    let encodedText = (try? JSONEncoder().encode(text))
        .flatMap { String(data: $0, encoding: .utf8) } ?? #""""#
    return [
        #"event: response.created"#,
        #"data: {"type":"response.created","response":{"id":"resp-1"}}"#,
        "",
        #"event: response.output_item.done"#,
        #"data: {"type":"response.output_item.done","item":{"type":"message","role":"assistant","id":"msg-1","content":[{"type":"output_text","text":\#(encodedText)}]}}"#,
        "",
        #"event: response.completed"#,
        #"data: {"type":"response.completed","response":{"id":"resp-1"}}"#,
        "",
        ""
    ].joined(separator: "\n")
}

private func functionCallSSE(callID: String, name: String, arguments: [String: Any]) -> String {
    let encodedArguments = (try? JSONSerialization.data(withJSONObject: arguments, options: [.sortedKeys]))
        .flatMap { String(data: $0, encoding: .utf8) } ?? #"{}"#
    let encodedArgumentsString = (try? JSONEncoder().encode(encodedArguments))
        .flatMap { String(data: $0, encoding: .utf8) } ?? #""{}""#
    return [
        #"event: response.created"#,
        #"data: {"type":"response.created","response":{"id":"resp-1"}}"#,
        "",
        #"event: response.output_item.done"#,
        #"data: {"type":"response.output_item.done","item":{"type":"function_call","call_id":"\#(callID)","name":"\#(name)","arguments":\#(encodedArgumentsString)}}"#,
        "",
        #"event: response.completed"#,
        #"data: {"type":"response.completed","response":{"id":"resp-1"}}"#,
        "",
        ""
    ].joined(separator: "\n")
}

// NWListener invokes callbacks as @Sendable closures. This test server keeps
// mutable response state behind a lock and routes network callbacks through one
// serial queue, so sharing the helper across those callbacks is constrained.
private final class RuntimeOracleResponsesServer: @unchecked Sendable {
    private(set) var baseURL = ""

    private let listener: NWListener
    private let queue = DispatchQueue(label: "codex.runtime-oracle.responses-server")
    private let lock = NSLock()
    private var responseBodies: [Data]

    init(responseBodies: [String]) throws {
        self.responseBodies = responseBodies.map { Data($0.utf8) }
        listener = try NWListener(using: .tcp, on: .any)

        let ready = DispatchSemaphore(value: 0)
        let startupState = RuntimeOracleServerStartupState()

        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                ready.signal()
            case let .failed(error):
                startupState.setError(error)
                ready.signal()
            default:
                break
            }
        }
        listener.start(queue: queue)

        guard ready.wait(timeout: .now() + .seconds(3)) == .success else {
            throw RuntimeOracleError.timeout("start Responses oracle server")
        }
        if let error = startupState.error {
            throw error
        }
        guard let port = listener.port else {
            throw RuntimeOracleError.serverStartup("Responses oracle server did not report a port")
        }
        baseURL = "http://127.0.0.1:\(port.rawValue)/v1"
    }

    deinit {
        listener.cancel()
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveRequest(on: connection, accumulated: Data())
    }

    private func receiveRequest(on connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 128 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }
            var requestData = accumulated
            if let data {
                requestData.append(data)
            }
            guard error != nil || self.requestIsComplete(requestData) else {
                self.receiveRequest(on: connection, accumulated: requestData)
                return
            }
            let request = String(decoding: requestData, as: UTF8.self)
            let response = self.httpResponse(for: request)
            connection.send(content: response, contentContext: .defaultMessage, isComplete: true, completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }

    private func requestIsComplete(_ data: Data) -> Bool {
        let headerEnd: Int
        if let range = data.range(of: Data([13, 10, 13, 10])) {
            headerEnd = range.upperBound
        } else if let range = data.range(of: Data([10, 10])) {
            headerEnd = range.upperBound
        } else {
            return false
        }

        let headerData = data.prefix(headerEnd)
        let headers = String(decoding: headerData, as: UTF8.self)
        let contentLength = headers
            .split(separator: "\n")
            .first { $0.lowercased().hasPrefix("content-length:") }
            .flatMap { line -> Int? in
                let value = line.split(separator: ":", maxSplits: 1).last?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return value.flatMap(Int.init)
            }

        return data.count >= headerEnd + (contentLength ?? 0)
    }

    private func httpResponse(for request: String) -> Data {
        let contentType: String
        let body: Data
        if request.hasPrefix("GET /v1/models ") {
            contentType = "application/json"
            body = Data(#"{"object":"list","data":[]}"#.utf8)
        } else {
            contentType = "text/event-stream"
            body = nextResponseBody()
        }

        let header = [
            "HTTP/1.1 200 OK",
            "Content-Type: \(contentType)",
            "Content-Length: \(body.count)",
            "Connection: close",
            "",
            ""
        ].joined(separator: "\r\n")
        var response = Data(header.utf8)
        response.append(body)
        return response
    }

    private func nextResponseBody() -> Data {
        lock.lock()
        defer { lock.unlock() }
        guard !responseBodies.isEmpty else {
            return Data(noToolsAssistantMessageSSE(text: "oracle fallback").utf8)
        }
        return responseBodies.removeFirst()
    }
}

// NWListener reports startup through @Sendable callbacks; this tiny locked box
// keeps the cross-queue handoff explicit for the test-only fixture server.
private final class RuntimeOracleServerStartupState: @unchecked Sendable {
    private let lock = NSLock()
    private var storedError: Error?

    var error: Error? {
        lock.withLock { storedError }
    }

    func setError(_ error: Error) {
        lock.withLock {
            storedError = error
        }
    }
}

private enum RuntimeOracleError: Error, CustomStringConvertible {
    case invalidJSONLine(String)
    case serverStartup(String)
    case timeout(String)

    var description: String {
        switch self {
        case let .invalidJSONLine(line):
            "invalid JSON line: \(line)"
        case let .serverStartup(message):
            message
        case let .timeout(command):
            "timed out running \(command)"
        }
    }
}
