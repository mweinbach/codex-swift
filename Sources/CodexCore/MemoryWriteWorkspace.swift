import Foundation

private let memoryBaselineCommitMessage = """
Initialize Codex git baseline

Co-authored-by: Codex <noreply@openai.com>
"""

public enum MemoryWorkspaceError: Error, Equatable, CustomStringConvertible, Sendable {
    case gitCommandFailed([String], String)
    case writeDiffFile(String)
    case removeWorkspaceDiff(String)

    public var description: String {
        switch self {
        case let .gitCommandFailed(args, stderr):
            let message = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return "git \(args.joined(separator: " ")) failed\(message.isEmpty ? "" : ": \(message)")"
        case let .writeDiffFile(path):
            return "write memory workspace diff file \(path)"
        case let .removeWorkspaceDiff(path):
            return "remove memory workspace diff file \(path)"
        }
    }
}

/// Prepares the memory directory for git-baseline diffing.
public func prepareMemoryWorkspace(root: URL) throws {
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try removeMemoryWorkspaceDiff(root: root)
    try ensureMemoryGitBaselineRepository(root: root)
}

/// Returns the current workspace diff after removing any stale generated diff artifact.
public func memoryWorkspaceDiff(root: URL) throws -> MemoryWorkspaceDiff {
    try removeMemoryWorkspaceDiff(root: root)
    let status = try gitStatusChanges(root: root)
    return MemoryWorkspaceDiff(
        changes: status,
        unifiedDiff: try renderMemoryWorkspaceUnifiedDiff(root: root, changes: status)
    )
}

/// Writes `phase2_workspace_diff.md` with a bounded git-style diff from the current baseline.
public func writeMemoryWorkspaceDiff(root: URL, diff: MemoryWorkspaceDiff) throws {
    let path = root.appendingPathComponent(memoryWorkspaceDiffFilename, isDirectory: false)
    do {
        try renderMemoryWorkspaceDiffFile(diff).write(to: path, atomically: true, encoding: .utf8)
    } catch {
        throw MemoryWorkspaceError.writeDiffFile(path.path)
    }
}

/// Marks the current memory root as the new baseline.
public func resetMemoryWorkspaceBaseline(root: URL) throws {
    try removeMemoryWorkspaceDiff(root: root)
    try resetMemoryGitBaselineRepository(root: root)
}

func removeMemoryWorkspaceDiff(root: URL) throws {
    let path = root.appendingPathComponent(memoryWorkspaceDiffFilename, isDirectory: false)
    guard FileManager.default.fileExists(atPath: path.path) else {
        return
    }
    do {
        try FileManager.default.removeItem(at: path)
    } catch {
        throw MemoryWorkspaceError.removeWorkspaceDiff(path.path)
    }
}

private func ensureMemoryGitBaselineRepository(root: URL) throws {
    let gitPath = root.appendingPathComponent(".git", isDirectory: true)
    if FileManager.default.fileExists(atPath: gitPath.path),
       (try? runMemoryGit(root: root, args: ["rev-parse", "--verify", "HEAD^{tree}"]))?.exitCode == 0 {
        return
    }
    try resetMemoryGitBaselineRepository(root: root)
}

private func resetMemoryGitBaselineRepository(root: URL) throws {
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let gitPath = root.appendingPathComponent(".git", isDirectory: true)
    if FileManager.default.fileExists(atPath: gitPath.path) {
        try FileManager.default.removeItem(at: gitPath)
    }

    try runSuccessfulMemoryGit(root: root, args: ["init", "-q"])
    try runSuccessfulMemoryGit(root: root, args: ["add", "-A"])
    try runSuccessfulMemoryGit(
        root: root,
        args: [
            "-c", "user.name=Codex",
            "-c", "user.email=noreply@openai.com",
            "commit",
            "--allow-empty",
            "-q",
            "-m",
            memoryBaselineCommitMessage
        ]
    )
    try runSuccessfulMemoryGit(root: root, args: ["read-tree", "--reset", "HEAD"])
}

private func gitStatusChanges(root: URL) throws -> [MemoryWorkspaceChange] {
    let output = try runSuccessfulMemoryGit(
        root: root,
        args: ["status", "--porcelain=v1", "--untracked-files=all"]
    )

    var changes: [MemoryWorkspaceChange] = []
    for rawLine in output.stdout.split(separator: "\n", omittingEmptySubsequences: true) {
        let line = String(rawLine)
        guard line.count >= 4 else {
            continue
        }
        let statusText = String(line.prefix(2))
        let pathStart = line.index(line.startIndex, offsetBy: 3)
        var path = String(line[pathStart...])
        if let renameSeparator = path.range(of: " -> ") {
            path = String(path[renameSeparator.upperBound...])
        }
        let status: MemoryWorkspaceChangeStatus
        if statusText.contains("D") {
            status = .deleted
        } else if statusText == "??" || statusText.contains("A") {
            status = .added
        } else {
            status = .modified
        }
        changes.append(MemoryWorkspaceChange(status: status, path: unquoteGitPath(path)))
    }

    return changes
        .filter { $0.path != memoryWorkspaceDiffFilename && !$0.path.hasPrefix(".git/") }
        .sorted { $0.path < $1.path }
}

private func renderMemoryWorkspaceUnifiedDiff(
    root: URL,
    changes: [MemoryWorkspaceChange]
) throws -> String {
    var rendered = ""
    let trackedDiff = try runSuccessfulMemoryGit(root: root, args: ["diff", "--no-ext-diff", "HEAD", "--"])
    rendered += trackedDiff.stdout

    for change in changes where change.status == .added && !trackedDiff.stdout.contains("diff --git a/\(change.path) b/\(change.path)") {
        rendered += try renderAddedFileDiff(root: root, path: change.path)
    }

    return rendered
}

private func renderAddedFileDiff(root: URL, path: String) throws -> String {
    let fileURL = root.appendingPathComponent(path, isDirectory: false)
    let data: Data
    let mode: String
    if let symlinkTarget = try? FileManager.default.destinationOfSymbolicLink(atPath: fileURL.path) {
        data = Data(symlinkTarget.utf8)
        mode = "120000"
    } else {
        data = (try? Data(contentsOf: fileURL)) ?? Data()
        mode = isExecutable(fileURL) ? "100755" : "100644"
    }
    let text = String(decoding: data, as: UTF8.self)
    var rendered = """
    diff --git a/\(path) b/\(path)
    new file mode \(mode)
    --- /dev/null
    +++ b/\(path)
    """

    let lines = diffLines(text)
    if !lines.isEmpty {
        rendered += "@@ -0,0 +1,\(lines.count) @@\n"
    }
    for line in lines {
        rendered += "+\(line)\n"
    }
    return rendered
}

private func diffLines(_ text: String) -> [Substring] {
    var lines = text.split(separator: "\n", omittingEmptySubsequences: false)
    if text.hasSuffix("\n") {
        lines.removeLast()
    }
    return lines
}

private func isExecutable(_ url: URL) -> Bool {
    FileManager.default.isExecutableFile(atPath: url.path)
}

@discardableResult
private func runSuccessfulMemoryGit(root: URL, args: [String]) throws -> MemoryGitOutput {
    let output = try runMemoryGit(root: root, args: args)
    guard output.exitCode == 0 else {
        throw MemoryWorkspaceError.gitCommandFailed(args, output.stderr)
    }
    return output
}

private struct MemoryGitOutput {
    let exitCode: Int32
    let stdout: String
    let stderr: String
}

private func runMemoryGit(root: URL, args: [String]) throws -> MemoryGitOutput {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["git"] + args
    process.currentDirectoryURL = root

    let stdout = Pipe()
    let stderr = Pipe()
    process.standardOutput = stdout
    process.standardError = stderr

    do {
        try process.run()
    } catch {
        throw MemoryWorkspaceError.gitCommandFailed(args, error.localizedDescription)
    }
    process.waitUntilExit()

    return MemoryGitOutput(
        exitCode: process.terminationStatus,
        stdout: String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "",
        stderr: String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    )
}

private func unquoteGitPath(_ path: String) -> String {
    guard path.hasPrefix("\""), path.hasSuffix("\"") else {
        return path
    }
    let inner = String(path.dropFirst().dropLast())
    var result = ""
    var iterator = inner.makeIterator()
    while let character = iterator.next() {
        guard character == "\\" else {
            result.append(character)
            continue
        }
        guard let escaped = iterator.next() else {
            result.append("\\")
            break
        }
        switch escaped {
        case "\\":
            result.append("\\")
        case "\"":
            result.append("\"")
        case "n":
            result.append("\n")
        case "t":
            result.append("\t")
        default:
            result.append(escaped)
        }
    }
    return result
}
