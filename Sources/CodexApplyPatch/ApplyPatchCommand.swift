import Foundation

public struct ApplyPatchCommandResult: Equatable, Sendable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String

    public init(exitCode: Int32, stdout: String, stderr: String) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }
}

public enum ApplyPatchCommand {
    public static let hiddenArgument = "--codex-run-as-apply-patch"

    private static let aliasNames: Set<String> = ["apply_patch", "applypatch"]

    public static func runForArg0Dispatch(
        argv0: String,
        arguments: [String],
        stdin: () -> Data,
        cwd: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    ) -> ApplyPatchCommandResult? {
        let executableName = URL(fileURLWithPath: argv0).lastPathComponent
        if aliasNames.contains(executableName) {
            return runStandalone(arguments: arguments, stdin: stdin, cwd: cwd)
        }

        guard arguments.first == hiddenArgument else {
            return nil
        }
        return runHidden(arguments: arguments, cwd: cwd)
    }

    public static func runStandalone(
        arguments: [String],
        stdin: () -> Data,
        cwd: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    ) -> ApplyPatchCommandResult {
        let patch: String
        switch arguments.count {
        case 0:
            patch = String(data: stdin(), encoding: .utf8) ?? ""
            guard !patch.isEmpty else {
                return ApplyPatchCommandResult(
                    exitCode: 2,
                    stdout: "",
                    stderr: "Usage: apply_patch 'PATCH'\n       echo 'PATCH' | apply-patch\n"
                )
            }
        case 1:
            patch = arguments[0]
        default:
            return ApplyPatchCommandResult(
                exitCode: 2,
                stdout: "",
                stderr: "Error: apply_patch accepts exactly one argument.\n"
            )
        }

        return apply(patch, cwd: cwd)
    }

    public static func runHidden(
        arguments: [String],
        cwd: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    ) -> ApplyPatchCommandResult {
        guard arguments.count >= 2 else {
            return ApplyPatchCommandResult(
                exitCode: 1,
                stdout: "",
                stderr: "Error: \(hiddenArgument) requires a UTF-8 PATCH argument.\n"
            )
        }

        return apply(arguments[1], cwd: cwd)
    }

    private static func apply(_ patch: String, cwd: URL) -> ApplyPatchCommandResult {
        let result = ApplyPatch.apply(patch, cwd: cwd)
        return ApplyPatchCommandResult(
            exitCode: result.stderr.isEmpty ? 0 : 1,
            stdout: result.stdout,
            stderr: result.stderr
        )
    }
}
