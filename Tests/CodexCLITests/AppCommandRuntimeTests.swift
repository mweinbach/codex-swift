import CodexCLI
import XCTest

final class AppCommandRuntimeTests: XCTestCase {
    func testCandidateCodexAppPathsMatchRustOrder() {
        XCTAssertEqual(
            AppCommandRuntime.candidateCodexAppPaths(homeDirectory: URL(fileURLWithPath: "/Users/test", isDirectory: true))
                .map(\.path),
            [
                "/Applications/Codex.app",
                "/Users/test/Applications/Codex.app"
            ]
        )
    }

    func testParsesMountPointFromHdiutilOutputLikeRust() {
        XCTAssertEqual(
            AppCommandRuntime.parseHdiutilAttachMountPoint("/dev/disk2s1\tApple_HFS\tCodex\t/Volumes/Codex\n"),
            "/Volumes/Codex"
        )
        XCTAssertEqual(
            AppCommandRuntime.parseHdiutilAttachMountPoint("/dev/disk2s1\tApple_HFS\tCodex Installer\t/Volumes/Codex Installer\n"),
            "/Volumes/Codex Installer"
        )
    }

    func testExistingMacAppOpensCanonicalWorkspaceLikeRust() throws {
        let capture = AppProcessCapture()
        let cwd = URL(fileURLWithPath: "/Users/test/repo", isDirectory: true)
        let home = URL(fileURLWithPath: "/Users/test", isDirectory: true)
        let workspace = URL(fileURLWithPath: "/Users/test/repo/workspace", isDirectory: true)
        let app = URL(fileURLWithPath: "/Users/test/Applications/Codex.app", isDirectory: true)

        let result = try AppCommandRuntime.run(
            CodexCLI.AppCommandRequest(path: "workspace"),
            dependencies: AppCommandRuntime.Dependencies(
                currentDirectory: { cwd },
                canonicalizePath: { path, _ in path == "workspace" ? workspace : nil },
                homeDirectory: { home },
                isDirectory: { $0.path == app.path },
                runProcess: { command, arguments in
                    capture.record(command: command, arguments: arguments)
                    return AppCommandRuntime.ProcessStatus(isSuccess: true, description: "exit status: 0")
                }
            )
        )

        XCTAssertEqual(capture.commands, [
            AppProcessCapture.Command(command: "open", arguments: ["-a", app.path, workspace.path])
        ])
        XCTAssertEqual(result, CodexCLI.CommandExecutionResult(
            exitCode: 0,
            stderrMessage: [
                "Opening Codex Desktop at \(app.path)...",
                "Opening workspace \(workspace.path)..."
            ].joined(separator: "\n")
        ))
    }

    func testMissingMacAppDownloadsInstallsAndOpensLikeRust() throws {
        let capture = AppProcessCapture()
        let cwd = URL(fileURLWithPath: "/Users/test/repo", isDirectory: true)
        let home = URL(fileURLWithPath: "/Users/test", isDirectory: true)
        let temp = URL(fileURLWithPath: "/tmp/codex-app-installer-test", isDirectory: true)
        let mount = URL(fileURLWithPath: "/Volumes/Codex Installer", isDirectory: true)
        let volumeApp = mount.appendingPathComponent("Codex.app", isDirectory: true)
        let userApp = home.appendingPathComponent("Applications/Codex.app", isDirectory: true)

        let result = try AppCommandRuntime.run(
            CodexCLI.AppCommandRequest(path: ".", downloadURLOverride: "https://example.test/Codex.dmg"),
            dependencies: AppCommandRuntime.Dependencies(
                currentDirectory: { cwd },
                canonicalizePath: { path, currentDirectory in path == "." ? currentDirectory : nil },
                homeDirectory: { home },
                isDirectory: { url in
                    url.path == volumeApp.path || capture.installedDirectories.contains(url.path)
                },
                makeTemporaryDirectory: { temp },
                removeItem: { _ in },
                createDirectory: { url in capture.createdDirectories.append(url.path) },
                contentsOfDirectory: { _ in [volumeApp] },
                runProcess: { command, arguments in
                    capture.record(command: command, arguments: arguments)
                    if command == "ditto", arguments.last == "/Applications/Codex.app" {
                        return AppCommandRuntime.ProcessStatus(isSuccess: false, description: "exit status: 1")
                    }
                    if command == "ditto", arguments.last == userApp.path {
                        capture.installedDirectories.insert(userApp.path)
                    }
                    return AppCommandRuntime.ProcessStatus(isSuccess: true, description: "exit status: 0")
                },
                runProcessWithOutput: { command, arguments in
                    capture.record(command: command, arguments: arguments)
                    return AppCommandRuntime.ProcessOutput(
                        status: AppCommandRuntime.ProcessStatus(isSuccess: true, description: "exit status: 0"),
                        stdout: "/dev/disk2s1\tApple_HFS\tCodex Installer\t\(mount.path)\n"
                    )
                }
            )
        )

        XCTAssertEqual(capture.commands, [
            AppProcessCapture.Command(command: "curl", arguments: [
                "-fL",
                "--retry",
                "3",
                "--retry-delay",
                "1",
                "-o",
                temp.appendingPathComponent("Codex.dmg").path,
                "https://example.test/Codex.dmg"
            ]),
            AppProcessCapture.Command(command: "hdiutil", arguments: [
                "attach",
                "-nobrowse",
                "-readonly",
                temp.appendingPathComponent("Codex.dmg").path
            ]),
            AppProcessCapture.Command(command: "ditto", arguments: [volumeApp.path, "/Applications/Codex.app"]),
            AppProcessCapture.Command(command: "ditto", arguments: [volumeApp.path, userApp.path]),
            AppProcessCapture.Command(command: "hdiutil", arguments: ["detach", mount.path]),
            AppProcessCapture.Command(command: "open", arguments: ["-a", userApp.path, cwd.path])
        ])
        XCTAssertEqual(capture.createdDirectories, ["/Applications", home.appendingPathComponent("Applications").path])
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderrMessage?.contains("Codex Desktop not found; downloading installer...") == true)
        XCTAssertTrue(result.stderrMessage?.contains("Launching Codex Desktop from \(userApp.path)...") == true)
    }
}

private final class AppProcessCapture: @unchecked Sendable {
    struct Command: Equatable {
        let command: String
        let arguments: [String]
    }

    private let lock = NSLock()
    private var recordedCommands: [Command] = []
    var createdDirectories: [String] = []
    var installedDirectories = Set<String>()

    var commands: [Command] {
        lock.lock()
        defer { lock.unlock() }
        return recordedCommands
    }

    func record(command: String, arguments: [String]) {
        lock.lock()
        recordedCommands.append(Command(command: command, arguments: arguments))
        lock.unlock()
    }
}
