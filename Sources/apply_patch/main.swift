import CodexApplyPatch
import Darwin
import Foundation

let patch: String
if CommandLine.arguments.count > 1 {
    patch = CommandLine.arguments.dropFirst().joined(separator: "\n")
} else {
    let data = FileHandle.standardInput.readDataToEndOfFile()
    patch = String(data: data, encoding: .utf8) ?? ""
}

let result = ApplyPatch.apply(patch)
if !result.stdout.isEmpty {
    print(result.stdout, terminator: "")
}
if !result.stderr.isEmpty {
    fputs(result.stderr, stderr)
}
exit(result.stderr.isEmpty ? 0 : 1)
