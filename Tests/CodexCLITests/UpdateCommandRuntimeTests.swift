import CodexCLI
import XCTest

final class UpdateCommandRuntimeTests: XCTestCase {
    func testRunRejectsDebugBuildLikeRust() throws {
        let result = try UpdateCommandRuntime.run(dependencies: UpdateCommandRuntime.Dependencies(
            isDebugBuild: { true },
            detectUpdateAction: {
                XCTFail("debug build should not inspect install context")
                return .npmGlobalLatest
            },
            runProcess: { _, _ in
                XCTFail("debug build should not run update command")
                return UpdateCommandRuntime.ProcessStatus(isSuccess: true, description: "exit status: 0")
            }
        ))

        XCTAssertEqual(result, CodexCLI.CommandExecutionResult(
            exitCode: 1,
            stderrMessage: "`codex update` is not available in debug builds. Install a release build of Codex to use this command."
        ))
    }

    func testRunRejectsUnknownInstallMethodLikeRust() throws {
        let result = try UpdateCommandRuntime.run(dependencies: UpdateCommandRuntime.Dependencies(
            isDebugBuild: { false },
            detectUpdateAction: { nil },
            runProcess: { _, _ in
                XCTFail("unknown install method should not run update command")
                return UpdateCommandRuntime.ProcessStatus(isSuccess: true, description: "exit status: 0")
            }
        ))

        XCTAssertEqual(result, CodexCLI.CommandExecutionResult(
            exitCode: 1,
            stderrMessage: "Could not detect the Codex installation method. Please update manually: https://developers.openai.com/codex/cli/"
        ))
    }

    func testRunUpdateActionExecutesNormalizedCommandAndPrintsSuccess() throws {
        let capture = UpdateProcessCapture()

        let result = try UpdateCommandRuntime.runUpdateAction(.brewUpgrade) { command, arguments in
            capture.record(command: command, arguments: arguments)
            return UpdateCommandRuntime.ProcessStatus(isSuccess: true, description: "exit status: 0")
        }

        XCTAssertEqual(capture.command, "brew")
        XCTAssertEqual(capture.arguments, ["upgrade", "--cask", "codex"])
        XCTAssertEqual(result, CodexCLI.CommandExecutionResult(
            exitCode: 0,
            stdoutMessage: "\nUpdating Codex via `brew upgrade --cask codex`...\n\n🎉 Update ran successfully! Please restart Codex."
        ))
    }

    func testRunUpdateActionReportsFailedStatus() throws {
        let result = try UpdateCommandRuntime.runUpdateAction(.npmGlobalLatest) { _, _ in
            UpdateCommandRuntime.ProcessStatus(isSuccess: false, description: "exit status: 42")
        }

        XCTAssertEqual(result, CodexCLI.CommandExecutionResult(
            exitCode: 1,
            stderrMessage: "`npm install -g @openai/codex` failed with status exit status: 42"
        ))
    }
}

private final class UpdateProcessCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedCommand: String?
    private var recordedArguments: [String]?

    var command: String? {
        lock.lock()
        defer { lock.unlock() }
        return recordedCommand
    }

    var arguments: [String]? {
        lock.lock()
        defer { lock.unlock() }
        return recordedArguments
    }

    func record(command: String, arguments: [String]) {
        lock.lock()
        recordedCommand = command
        recordedArguments = arguments
        lock.unlock()
    }
}
