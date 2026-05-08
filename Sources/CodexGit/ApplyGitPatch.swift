import Foundation

public struct ApplyGitRequest: Equatable, Sendable {
    public let cwd: URL
    public let diff: String
    public let revert: Bool
    public let preflight: Bool

    public init(cwd: URL, diff: String, revert: Bool = false, preflight: Bool = false) {
        self.cwd = cwd
        self.diff = diff
        self.revert = revert
        self.preflight = preflight
    }
}

public struct ApplyGitResult: Equatable, Sendable {
    public let exitCode: Int32
    public let appliedPaths: [String]
    public let skippedPaths: [String]
    public let conflictedPaths: [String]
    public let stdout: String
    public let stderr: String
    public let commandForLog: String

    public init(
        exitCode: Int32,
        appliedPaths: [String],
        skippedPaths: [String],
        conflictedPaths: [String],
        stdout: String,
        stderr: String,
        commandForLog: String
    ) {
        self.exitCode = exitCode
        self.appliedPaths = appliedPaths
        self.skippedPaths = skippedPaths
        self.conflictedPaths = conflictedPaths
        self.stdout = stdout
        self.stderr = stderr
        self.commandForLog = commandForLog
    }
}

public enum CodexGitError: Error, Equatable, CustomStringConvertible, Sendable {
    case processLaunch(String)
    case notGitRepository(String)
    case tempPatchWrite(String)

    public var description: String {
        switch self {
        case let .processLaunch(message), let .notGitRepository(message), let .tempPatchWrite(message):
            return message
        }
    }
}

public enum CodexGit {
    public static func applyGitPatch(_ request: ApplyGitRequest) throws -> ApplyGitResult {
        let gitRoot = try resolveGitRoot(request.cwd)
        let patchURL = try writeTempPatch(request.diff)
        defer {
            try? FileManager.default.removeItem(at: patchURL.deletingLastPathComponent())
        }

        if request.revert, !request.preflight {
            _ = try? stagePaths(gitRoot: gitRoot, diff: request.diff)
        }

        let cfgParts = gitConfigPartsFromEnvironment()
        let args: [String]
        if request.preflight {
            args = ["apply", "--check"] + (request.revert ? ["-R"] : []) + [patchURL.path]
        } else {
            args = ["apply", "--3way"] + (request.revert ? ["-R"] : []) + [patchURL.path]
        }

        let commandForLog = renderCommandForLog(cwd: gitRoot, gitConfig: cfgParts, args: args)
        let output = try runGit(cwd: gitRoot, gitConfig: cfgParts, args: args)
        let parsed = parseGitApplyOutput(stdout: output.stdout, stderr: output.stderr)

        return ApplyGitResult(
            exitCode: output.exitCode,
            appliedPaths: parsed.applied,
            skippedPaths: parsed.skipped,
            conflictedPaths: parsed.conflicted,
            stdout: output.stdout,
            stderr: output.stderr,
            commandForLog: commandForLog
        )
    }

    public static func extractPaths(fromPatch diffText: String) -> [String] {
        var set = Set<String>()
        for line in diffText.components(separatedBy: .newlines) {
            guard line.hasPrefix("diff --git a/") else { continue }
            let rest = String(line.dropFirst("diff --git a/".count))
            guard let separator = rest.range(of: " b/") else { continue }
            let lhs = String(rest[..<separator.lowerBound])
            let rhs = String(rest[separator.upperBound...])
            for path in [lhs, rhs] where path != "/dev/null" && !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                set.insert(path)
            }
        }
        return set.sorted()
    }

    public static func parseGitApplyOutput(stdout: String, stderr: String) -> (applied: [String], skipped: [String], conflicted: [String]) {
        var applied = Set<String>()
        var skipped = Set<String>()
        var conflicted = Set<String>()
        var lastSeenPath: String?
        let combined = [stdout, stderr].filter { !$0.isEmpty }.joined(separator: "\n")

        func add(_ rawPath: String, to set: inout Set<String>) -> String? {
            let path = unquote(rawPath)
            guard !path.isEmpty else { return nil }
            set.insert(path)
            return path
        }

        for rawLine in combined.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            if let path = regexCapture(line, #"^Checking patch\s+(.+?)\.\.\.$"#) {
                lastSeenPath = path
                continue
            }

            if let path = regexCapture(line, #"^Applied patch(?: to)?\s+(.+?)\s+cleanly\.?$"#),
               let added = add(path, to: &applied)
            {
                skipped.remove(added)
                conflicted.remove(added)
                lastSeenPath = added
                continue
            }

            if let path = regexCapture(line, #"^Applied patch(?: to)?\s+(.+?)\s+with conflicts\.?$"#),
               let added = add(path, to: &conflicted)
            {
                applied.remove(added)
                skipped.remove(added)
                lastSeenPath = added
                continue
            }

            if let path = regexCapture(line, #"^Applying patch\s+(.+?)\s+with\s+\d+\s+rejects?\.{0,3}$"#),
               let added = add(path, to: &conflicted)
            {
                applied.remove(added)
                skipped.remove(added)
                lastSeenPath = added
                continue
            }

            if let path = regexCapture(line, #"^U\s+(.+)$"#),
               let added = add(path, to: &conflicted)
            {
                applied.remove(added)
                skipped.remove(added)
                lastSeenPath = added
                continue
            }

            if let path = firstRegexCapture(line, patterns: [
                #"^error:\s+patch failed:\s+(.+?)(?::\d+)?(?:\s|$)"#,
                #"^error:\s+(.+?):\s+patch does not apply$"#
            ]) {
                if let added = add(path, to: &skipped) {
                    lastSeenPath = added
                }
                continue
            }

            if regexMatches(line, #"^(?:Performing three-way merge|Falling back to three-way merge)\.\.\.$"#)
                || regexMatches(line, #"^Falling back to direct application\.\.\.$"#)
            {
                continue
            }

            if regexMatches(line, #"^Failed to perform three-way merge\.\.\.$"#)
                || regexMatches(line, #"^(?:error: )?repository lacks the necessary blob to (?:perform|fall back on) 3-?way merge\.?$"#)
            {
                if let lastSeenPath, let added = add(lastSeenPath, to: &skipped) {
                    applied.remove(added)
                    conflicted.remove(added)
                }
                continue
            }

            if let path = firstRegexCapture(line, patterns: [
                #"^error:\s+(.+?):\s+does not match index\b"#,
                #"^error:\s+(.+?):\s+does not exist in index\b"#,
                #"^error:\s+(.+?)\s+already exists in (?:the )?working directory\b"#,
                #"^error:\s+patch failed:\s+(.+?)\s+File exists"#,
                #"^error:\s+path\s+(.+?)\s+has been renamed/deleted"#,
                #"^error:\s+cannot apply binary patch to\s+['"]?(.+?)['"]?\s+without full index line$"#,
                #"^error:\s+binary patch does not apply to\s+['"]?(.+?)['"]?$"#,
                #"^error:\s+binary patch to\s+['"]?(.+?)['"]?\s+creates incorrect result\b"#,
                #"^error:\s+cannot read the current contents of\s+['"]?(.+?)['"]?$"#,
                #"^Skipped patch\s+['"]?(.+?)['"]\.$"#
            ]), let added = add(path, to: &skipped) {
                applied.remove(added)
                conflicted.remove(added)
                lastSeenPath = added
                continue
            }

            if let path = regexCapture(line, #"^warning:\s*Cannot merge binary files:\s+(.+?)\s+\(ours\s+vs\.\s+theirs\)"#),
               let added = add(path, to: &conflicted)
            {
                applied.remove(added)
                skipped.remove(added)
                lastSeenPath = added
                continue
            }
        }

        for path in conflicted {
            applied.remove(path)
            skipped.remove(path)
        }
        for path in applied {
            skipped.remove(path)
        }

        return (applied.sorted(), skipped.sorted(), conflicted.sorted())
    }

    public static func stagePaths(gitRoot: URL, diff: String) throws {
        let existing = extractPaths(fromPatch: diff).filter { path in
            FileManager.default.fileExists(atPath: gitRoot.appendingPathComponent(path).path)
        }
        guard !existing.isEmpty else { return }
        _ = try runGit(cwd: gitRoot, gitConfig: [], args: ["add", "--"] + existing)
    }

    private static func resolveGitRoot(_ cwd: URL) throws -> URL {
        let output = try runGit(cwd: cwd, gitConfig: [], args: ["rev-parse", "--show-toplevel"])
        guard output.exitCode == 0 else {
            throw CodexGitError.notGitRepository("not a git repository (exit \(output.exitCode)): \(output.stderr)")
        }
        return URL(fileURLWithPath: output.stdout.trimmingCharacters(in: .whitespacesAndNewlines), isDirectory: true)
    }

    private static func writeTempPatch(_ diff: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let patch = directory.appendingPathComponent("patch.diff")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try diff.write(to: patch, atomically: true, encoding: .utf8)
            return patch
        } catch {
            throw CodexGitError.tempPatchWrite("failed to write temporary patch: \(error.localizedDescription)")
        }
    }

    private static func runGit(cwd: URL, gitConfig: [String], args: [String]) throws -> (exitCode: Int32, stdout: String, stderr: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = gitConfig + args
        process.currentDirectoryURL = cwd

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            throw CodexGitError.processLaunch("failed to launch git: \(error.localizedDescription)")
        }
        process.waitUntilExit()

        return (
            process.terminationStatus,
            String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "",
            String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        )
    }

    private static func gitConfigPartsFromEnvironment() -> [String] {
        guard let config = ProcessInfo.processInfo.environment["CODEX_APPLY_GIT_CFG"] else {
            return []
        }
        return config
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.contains("=") }
            .flatMap { ["-c", $0] }
    }

    private static func renderCommandForLog(cwd: URL, gitConfig: [String], args: [String]) -> String {
        let command = (["git"] + gitConfig + args).map(quoteShell).joined(separator: " ")
        return "(cd \(quoteShell(cwd.path)) && \(command))"
    }

    private static func quoteShell(_ value: String) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.:/@%+")
        if value.unicodeScalars.allSatisfy({ allowed.contains($0) }) {
            return value
        }
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func firstRegexCapture(_ line: String, patterns: [String]) -> String? {
        for pattern in patterns {
            if let capture = regexCapture(line, pattern) {
                return capture
            }
        }
        return nil
    }

    private static func regexCapture(_ line: String, _ pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = regex.firstMatch(in: line, range: range),
              match.numberOfRanges > 1,
              let captureRange = Range(match.range(at: 1), in: line)
        else {
            return nil
        }
        return String(line[captureRange])
    }

    private static func regexMatches(_ line: String, _ pattern: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return false
        }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        return regex.firstMatch(in: line, range: range) != nil
    }

    private static func unquote(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2, let first = trimmed.first, trimmed.last == first, first == "\"" || first == "'" else {
            return trimmed
        }
        return String(trimmed.dropFirst().dropLast())
    }
}
