import Foundation

public struct CommitLogEntry: Equatable, Codable, Sendable {
    public let sha: String
    public let timestamp: Int64
    public let subject: String

    public init(sha: String, timestamp: Int64, subject: String) {
        self.sha = sha
        self.timestamp = timestamp
        self.subject = subject
    }
}

public struct GitDiffToRemote: Equatable, Codable, Sendable {
    public let sha: String
    public let diff: String

    public init(sha: String, diff: String) {
        self.sha = sha
        self.diff = diff
    }
}

public enum GitInfoCollector {
    public static let commandTimeout: TimeInterval = 5

    public static func gitRepoRoot(baseDir: URL, fileManager: FileManager = .default) -> URL? {
        var currentPath = (baseDir.standardizedFileURL.path as NSString).standardizingPath
        while true {
            let gitPath = URL(fileURLWithPath: currentPath).appendingPathComponent(".git").path
            if fileManager.fileExists(atPath: gitPath) {
                return URL(fileURLWithPath: currentPath, isDirectory: true)
            }

            let parent = (currentPath as NSString).deletingLastPathComponent
            let parentPath = parent.isEmpty ? "/" : parent
            if parentPath == currentPath {
                return nil
            }
            currentPath = parentPath
        }
    }

    public static func collectGitInfo(cwd: URL) -> GitInfo? {
        guard runGit(["rev-parse", "--git-dir"], cwd: cwd)?.exitCode == 0 else {
            return nil
        }

        var info = GitInfo()

        if let output = runGit(["rev-parse", "HEAD"], cwd: cwd),
           output.exitCode == 0
        {
            let hash = output.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            if !hash.isEmpty {
                info = GitInfo(commitHash: hash, branch: info.branch, repositoryURL: info.repositoryURL)
            }
        }

        if let output = runGit(["rev-parse", "--abbrev-ref", "HEAD"], cwd: cwd),
           output.exitCode == 0
        {
            let branch = output.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            if !branch.isEmpty, branch != "HEAD" {
                info = GitInfo(commitHash: info.commitHash, branch: branch, repositoryURL: info.repositoryURL)
            }
        }

        if let output = runGit(["remote", "get-url", "origin"], cwd: cwd),
           output.exitCode == 0
        {
            let url = output.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            if !url.isEmpty {
                info = GitInfo(commitHash: info.commitHash, branch: info.branch, repositoryURL: url)
            }
        }

        return info
    }

    public static func recentCommits(cwd: URL, limit: Int) -> [CommitLogEntry] {
        guard runGit(["rev-parse", "--git-dir"], cwd: cwd)?.exitCode == 0 else {
            return []
        }

        let format = "%H%x1f%ct%x1f%s"
        var args = ["log"]
        if limit > 0 {
            args.append(contentsOf: ["-n", String(limit)])
        }
        args.append("--pretty=format:\(format)")

        guard let output = runGit(args, cwd: cwd), output.exitCode == 0 else {
            return []
        }

        return output.stdout
            .split(whereSeparator: \.isNewline)
            .compactMap { line -> CommitLogEntry? in
                let parts = line.split(separator: "\u{001f}", maxSplits: 2, omittingEmptySubsequences: false)
                guard parts.count == 3 else {
                    return nil
                }

                let sha = String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines)
                let timestampText = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
                let subject = String(parts[2]).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !sha.isEmpty, let timestamp = Int64(timestampText) else {
                    return nil
                }
                return CommitLogEntry(sha: sha, timestamp: timestamp, subject: subject)
            }
    }

    public static func gitDiffToRemote(cwd: URL) -> GitDiffToRemote? {
        guard gitRepoRoot(baseDir: cwd) != nil,
              let remotes = gitRemotes(cwd: cwd),
              let branches = branchAncestry(cwd: cwd),
              let baseSha = findClosestSha(cwd: cwd, branches: branches, remotes: remotes),
              let diff = diffAgainstSha(cwd: cwd, sha: baseSha)
        else {
            return nil
        }

        return GitDiffToRemote(sha: baseSha, diff: diff)
    }

    public static func resolveRootGitProjectForTrust(cwd: URL, fileManager: FileManager = .default) -> URL? {
        let base: URL
        if isDirectory(cwd, fileManager: fileManager) {
            base = cwd
        } else {
            base = cwd.deletingLastPathComponent()
        }

        guard let output = runGit(["rev-parse", "--git-common-dir"], cwd: base),
              output.exitCode == 0
        else {
            return nil
        }

        let gitDirText = output.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !gitDirText.isEmpty else {
            return nil
        }

        let resolvedPath = CoreUtils.resolvePath(base: base.path, path: gitDirText)
        let normalizedURL = URL(fileURLWithPath: resolvedPath).resolvingSymlinksInPath().standardizedFileURL
        return normalizedURL.deletingLastPathComponent()
    }

    public static func localGitBranches(cwd: URL) -> [String] {
        guard let output = runGit(["branch", "--format=%(refname:short)"], cwd: cwd),
              output.exitCode == 0
        else {
            return []
        }

        var branches = output.stdout
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .sorted()

        if let base = defaultBranchNameLocal(cwd: cwd),
           let index = branches.firstIndex(of: base)
        {
            branches.remove(at: index)
            branches.insert(base, at: 0)
        }
        return branches
    }

    public static func currentBranchName(cwd: URL) -> String? {
        guard let output = runGit(["branch", "--show-current"], cwd: cwd),
              output.exitCode == 0
        else {
            return nil
        }
        let name = output.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    public static func defaultBranchName(cwd: URL) -> String? {
        for remote in gitRemotes(cwd: cwd) ?? [] {
            if let output = runGit(["symbolic-ref", "--quiet", "refs/remotes/\(remote)/HEAD"], cwd: cwd),
               output.exitCode == 0
            {
                let trimmed = output.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                if let name = trimmed.split(separator: "/").last, !name.isEmpty {
                    return String(name)
                }
            }

            if let output = runGit(["remote", "show", remote], cwd: cwd),
               output.exitCode == 0
            {
                for rawLine in output.stdout.split(whereSeparator: \.isNewline) {
                    let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                    if line.hasPrefix("HEAD branch:") {
                        let name = String(line.dropFirst("HEAD branch:".count))
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        if !name.isEmpty {
                            return name
                        }
                    }
                }
            }
        }

        return defaultBranchNameLocal(cwd: cwd)
    }

    public static func remoteURLs(cwd: URL) -> [String] {
        if let output = runGit(["config", "--get-regexp", "remote\\..*\\.url"], cwd: cwd),
           output.exitCode == 0 {
            let urls = output.stdout
                .split(whereSeparator: \.isNewline)
                .compactMap { line -> String? in
                    guard let separator = line.firstIndex(of: " ") else {
                        return nil
                    }
                    let value = line[line.index(after: separator)...]
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    return value.isEmpty ? nil : value
                }
            let unique = uniqueSorted(urls)
            if !unique.isEmpty {
                return unique
            }
        }

        guard let output = runGit(["remote", "-v"], cwd: cwd),
              output.exitCode == 0
        else {
            return []
        }
        let urls = output.stdout
            .split(whereSeparator: \.isNewline)
            .compactMap { line -> String? in
                let parts = line.split(whereSeparator: \.isWhitespace)
                guard parts.count >= 2 else {
                    return nil
                }
                let value = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
                return value.isEmpty ? nil : value
            }
        return uniqueSorted(urls)
    }

    private static func gitRemotes(cwd: URL) -> [String]? {
        guard let output = runGit(["remote"], cwd: cwd),
              output.exitCode == 0
        else {
            return nil
        }

        var remotes = output.stdout
            .split(whereSeparator: \.isNewline)
            .map(String.init)
        if let originIndex = remotes.firstIndex(of: "origin") {
            remotes.remove(at: originIndex)
            remotes.insert("origin", at: 0)
        }
        return remotes
    }

    private static func branchAncestry(cwd: URL) -> [String]? {
        let currentBranch = runGit(["rev-parse", "--abbrev-ref", "HEAD"], cwd: cwd).flatMap { output -> String? in
            guard output.exitCode == 0 else {
                return nil
            }
            let name = output.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            return name == "HEAD" || name.isEmpty ? nil : name
        }

        let defaultBranch = defaultBranchName(cwd: cwd)
        var ancestry: [String] = []
        var seen: Set<String> = []
        if let currentBranch {
            seen.insert(currentBranch)
            ancestry.append(currentBranch)
        }
        if let defaultBranch, !seen.contains(defaultBranch) {
            seen.insert(defaultBranch)
            ancestry.append(defaultBranch)
        }

        for remote in gitRemotes(cwd: cwd) ?? [] {
            guard let output = runGit([
                "for-each-ref",
                "--format=%(refname:short)",
                "--contains=HEAD",
                "refs/remotes/\(remote)"
            ], cwd: cwd),
                output.exitCode == 0
            else {
                continue
            }

            for rawLine in output.stdout.split(whereSeparator: \.isNewline) {
                let short = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                let prefix = "\(remote)/"
                guard short.hasPrefix(prefix) else {
                    continue
                }
                let branch = String(short.dropFirst(prefix.count))
                if !branch.isEmpty, !seen.contains(branch) {
                    seen.insert(branch)
                    ancestry.append(branch)
                }
            }
        }

        return ancestry
    }

    private static func branchRemoteAndDistance(
        cwd: URL,
        branch: String,
        remotes: [String]
    ) -> (remoteSha: String?, distance: Int)? {
        var foundRemoteSha: String?
        var foundRemoteRef: String?

        for remote in remotes {
            let remoteRef = "refs/remotes/\(remote)/\(branch)"
            guard let verifyOutput = runGit(["rev-parse", "--verify", "--quiet", remoteRef], cwd: cwd) else {
                return nil
            }
            guard verifyOutput.exitCode == 0 else {
                continue
            }

            let sha = verifyOutput.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !sha.isEmpty else {
                return nil
            }
            foundRemoteSha = sha
            foundRemoteRef = remoteRef
            break
        }

        let localCountOutput = runGit(["rev-list", "--count", "\(branch)..HEAD"], cwd: cwd)
        let countOutput: GitCommandOutput
        if let localCountOutput, localCountOutput.exitCode == 0 {
            countOutput = localCountOutput
        } else if let foundRemoteRef,
                  let remoteCountOutput = runGit(["rev-list", "--count", "\(foundRemoteRef)..HEAD"], cwd: cwd)
        {
            countOutput = remoteCountOutput
        } else {
            return nil
        }

        guard countOutput.exitCode == 0 else {
            return nil
        }
        let distanceText = countOutput.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let distance = Int(distanceText) else {
            return nil
        }
        return (foundRemoteSha, distance)
    }

    private static func findClosestSha(cwd: URL, branches: [String], remotes: [String]) -> String? {
        var closest: (sha: String, distance: Int)?
        for branch in branches {
            guard let (remoteSha, distance) = branchRemoteAndDistance(cwd: cwd, branch: branch, remotes: remotes),
                  let remoteSha
            else {
                continue
            }

            if closest == nil || distance < closest!.distance {
                closest = (remoteSha, distance)
            }
        }
        return closest?.sha
    }

    private static func diffAgainstSha(cwd: URL, sha: String) -> String? {
        guard let output = runGit(["diff", "--no-textconv", "--no-ext-diff", sha], cwd: cwd),
              output.exitCode == 0 || output.exitCode == 1
        else {
            return nil
        }

        var diff = output.stdout
        if let untrackedOutput = runGit(["ls-files", "--others", "--exclude-standard"], cwd: cwd),
           untrackedOutput.exitCode == 0
        {
            let untracked = untrackedOutput.stdout
                .split(whereSeparator: \.isNewline)
                .map(String.init)
                .filter { !$0.isEmpty }

            for file in untracked {
                guard let extra = runGit([
                    "diff",
                    "--no-textconv",
                    "--no-ext-diff",
                    "--binary",
                    "--no-index",
                    "--",
                    "/dev/null",
                    file
                ], cwd: cwd),
                    extra.exitCode == 0 || extra.exitCode == 1
                else {
                    continue
                }
                diff += extra.stdout
            }
        }

        return diff
    }

    private static func defaultBranchNameLocal(cwd: URL) -> String? {
        for candidate in ["main", "master"] {
            if let output = runGit(["rev-parse", "--verify", "--quiet", "refs/heads/\(candidate)"], cwd: cwd),
               output.exitCode == 0
            {
                return candidate
            }
        }
        return nil
    }

    private static func uniqueSorted(_ values: [String]) -> [String] {
        Array(Set(values)).sorted()
    }

    private static func isDirectory(_ url: URL, fileManager: FileManager) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private struct GitCommandOutput {
        let exitCode: Int32
        let stdout: String
    }

    private static func runGit(_ args: [String], cwd: URL) -> GitCommandOutput? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = cwd

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let semaphore = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in
            semaphore.signal()
        }

        do {
            try process.run()
        } catch {
            return nil
        }

        if semaphore.wait(timeout: .now() + commandTimeout) == .timedOut {
            process.terminate()
            _ = semaphore.wait(timeout: .now() + 1)
            return nil
        }

        return GitCommandOutput(
            exitCode: process.terminationStatus,
            stdout: String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        )
    }
}
