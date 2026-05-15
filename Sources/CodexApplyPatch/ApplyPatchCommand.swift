import Foundation

public final class ApplyPatchAliasDirectory {
    public let url: URL

    fileprivate init(url: URL) {
        self.url = url
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}

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
    private static let pathSeparator = ":"

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
                    stderr: "Usage: apply_patch 'PATCH'\n       echo 'PATCH' | apply_patch\n"
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

    public static func prependPathEntryForCodexAliases(
        currentExecutable: URL? = Bundle.main.executableURL,
        existingPATH: String? = ProcessInfo.processInfo.environment["PATH"],
        setPATH: (String) throws -> Void = { value in setenv("PATH", value, 1) }
    ) throws -> ApplyPatchAliasDirectory {
        let executable = currentExecutable ?? URL(fileURLWithPath: CommandLine.arguments.first ?? "")
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        do {
            for aliasName in aliasNames {
                try FileManager.default.createSymbolicLink(
                    at: tempDirectory.appendingPathComponent(aliasName),
                    withDestinationURL: executable
                )
            }

            let updatedPATH: String
            if let existingPATH, !existingPATH.isEmpty {
                updatedPATH = "\(tempDirectory.path)\(pathSeparator)\(existingPATH)"
            } else {
                updatedPATH = tempDirectory.path
            }
            try setPATH(updatedPATH)
            return ApplyPatchAliasDirectory(url: tempDirectory)
        } catch {
            try? FileManager.default.removeItem(at: tempDirectory)
            throw error
        }
    }
}
