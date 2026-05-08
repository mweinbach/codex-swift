import CodexApplyPatch
import Darwin
import Foundation

let result = ApplyPatchCommand.runStandalone(
    arguments: Array(CommandLine.arguments.dropFirst()),
    stdin: { FileHandle.standardInput.readDataToEndOfFile() }
)
if !result.stdout.isEmpty {
    print(result.stdout, terminator: "")
}
if !result.stderr.isEmpty {
    fputs(result.stderr, stderr)
}
exit(result.exitCode)
