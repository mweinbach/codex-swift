import CodexCore
import XCTest

final class GitInfoCollectorTests: XCTestCase {
    private var retainedTemporaryDirectories: [GitInfoTemporaryDirectory] = []

    func testGitRepoRootWalksUpToDotGitDirectoryOrFile() throws {
        let dir = try GitInfoTemporaryDirectory()
        let repo = dir.url.appendingPathComponent("repo", isDirectory: true)
        let nested = repo.appendingPathComponent("child/grandchild", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: repo.appendingPathComponent(".git"), withIntermediateDirectories: true)

        XCTAssertEqual(GitInfoCollector.gitRepoRoot(baseDir: nested)?.path, repo.path)

        try FileManager.default.removeItem(at: repo.appendingPathComponent(".git"))
        try "gitdir: elsewhere\n".write(to: repo.appendingPathComponent(".git"), atomically: true, encoding: .utf8)
        XCTAssertEqual(GitInfoCollector.gitRepoRoot(baseDir: nested)?.path, repo.path)
        XCTAssertNil(GitInfoCollector.gitRepoRoot(baseDir: dir.url))
    }

    func testCollectGitInfoReturnsNilOutsideRepo() throws {
        let dir = try GitInfoTemporaryDirectory()
        XCTAssertNil(GitInfoCollector.collectGitInfo(cwd: dir.url))
        XCTAssertEqual(GitInfoCollector.recentCommits(cwd: dir.url, limit: 10), [])
        XCTAssertNil(GitInfoCollector.gitDiffToRemote(cwd: dir.url))
    }

    func testCollectGitInfoReadsCommitBranchAndRemote() throws {
        let repo = try createRepository()
        try runGit(["remote", "add", "origin", "https://github.com/example/repo.git"], cwd: repo)

        let info = try XCTUnwrap(GitInfoCollector.collectGitInfo(cwd: repo))
        let expectedRemote = try runGit(["remote", "get-url", "origin"], cwd: repo, isolatedConfig: false)
            .stdout
            .trimmingCharacters(in: .whitespacesAndNewlines)

        XCTAssertEqual(info.commitHash?.count, 40)
        XCTAssertTrue(info.commitHash?.allSatisfy(\.isHexDigit) == true)
        XCTAssertTrue(info.branch == "main" || info.branch == "master")
        XCTAssertEqual(info.repositoryURL, expectedRemote)
    }

    func testRemoteURLsByNameParsesFetchRemotesLikeRust() throws {
        let repo = try createRepository()
        try runGit(["remote", "add", "origin", "https://github.com/OpenAI/Codex.git"], cwd: repo)
        try runGit(["remote", "add", "fork", "git@ghe.company.com:Org/Repo.git"], cwd: repo)

        XCTAssertEqual(GitInfoCollector.remoteURLsByName(cwd: repo), [
            "fork": "git@ghe.company.com:Org/Repo.git",
            "origin": "https://github.com/OpenAI/Codex.git"
        ])
    }

    func testCanonicalizeGitRemoteURLNormalizesGitHubVariants() {
        for remote in [
            "git@github.com:OpenAI/Codex.git",
            "ssh://git@github.com/openai/codex.git",
            "ssh://git@github.com:22/OpenAI/Codex.git",
            "https://github.com/openai/codex.git",
            "https://github.com:443/openai/codex.git",
            "https://token@github.com/openai/codex/",
            "https://github.com/openai/codex.git?tab=readme",
            "https://github.com/openai/codex.git#main",
            "git://github.com:9418/openai/codex.git",
            "http://github.com:80/openai/codex.git",
            "github.com/OpenAI/Codex.git"
        ] {
            XCTAssertEqual(
                GitInfoCollector.canonicalizeGitRemoteURL(remote),
                "github.com/openai/codex"
            )
        }
    }

    func testCanonicalizeGitRemoteURLHandlesGHEWithoutLowercasingPath() {
        XCTAssertEqual(
            GitInfoCollector.canonicalizeGitRemoteURL("git@ghe.company.com:Org/Repo.git"),
            "ghe.company.com/Org/Repo"
        )
        XCTAssertEqual(
            GitInfoCollector.canonicalizeGitRemoteURL("ssh://git@ghe.company.com:2222/Org/Repo.git"),
            "ghe.company.com:2222/Org/Repo"
        )
    }

    func testCanonicalizeGitRemoteURLStripsUserInfoAtLastAtLikeRust() {
        XCTAssertEqual(
            GitInfoCollector.canonicalizeGitRemoteURL("ssh://token@user@github.com/openai/codex.git"),
            "github.com/openai/codex"
        )
    }

    func testCanonicalizeGitRemoteURLRejectsNonRepositoryValues() {
        for remote in [
            "",
            "file:///tmp/repo",
            "github.com/openai",
            "/tmp/repo",
            "HTTPS://github.com/openai/codex.git",
            "https://github.com/./codex.git",
            "https://github.com/openai/../codex.git"
        ] {
            XCTAssertNil(GitInfoCollector.canonicalizeGitRemoteURL(remote))
        }
    }

    func testCollectGitInfoOmitsBranchForDetachedHead() throws {
        let repo = try createRepository()
        let head = try runGit(["rev-parse", "HEAD"], cwd: repo).stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        try runGit(["checkout", head], cwd: repo)

        let info = try XCTUnwrap(GitInfoCollector.collectGitInfo(cwd: repo))

        XCTAssertEqual(info.commitHash, head)
        XCTAssertNil(info.branch)
    }

    func testRecentCommitsOrdersAndLimits() throws {
        let repo = try createRepository()
        try commitFile(name: "file.txt", contents: "one", message: "first change", cwd: repo)
        try commitFile(name: "file.txt", contents: "two", message: "second change", cwd: repo)
        try commitFile(name: "file.txt", contents: "three", message: "third change", cwd: repo)

        let entries = GitInfoCollector.recentCommits(cwd: repo, limit: 3)

        XCTAssertEqual(entries.map(\.subject), ["third change", "second change", "first change"])
        XCTAssertTrue(entries.allSatisfy { $0.sha.count == 40 && $0.sha.allSatisfy(\.isHexDigit) })
        XCTAssertTrue(entries.allSatisfy { $0.timestamp > 0 })
    }

    func testBranchHelpersMatchRustBehavior() throws {
        let repo = try createRepository()
        try runGit(["checkout", "-b", "feature-branch"], cwd: repo)

        XCTAssertEqual(GitInfoCollector.currentBranchName(cwd: repo), "feature-branch")

        let branches = GitInfoCollector.localGitBranches(cwd: repo)
        XCTAssertTrue(branches.contains("feature-branch"))
        XCTAssertTrue(branches.contains("main") || branches.contains("master"))
        let defaultBranch = GitInfoCollector.defaultBranchName(cwd: repo)
        XCTAssertTrue(defaultBranch == "main" || defaultBranch == "master")
    }

    func testGitDiffToRemoteReturnsCleanState() throws {
        let (repo, branch) = try createRepositoryWithRemote()
        let remoteSha = try runGit(["rev-parse", "origin/\(branch)"], cwd: repo)
            .stdout
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let state = try XCTUnwrap(GitInfoCollector.gitDiffToRemote(cwd: repo))

        XCTAssertEqual(state.sha, remoteSha)
        XCTAssertTrue(state.diff.isEmpty)
    }

    func testGitDiffToRemoteIncludesTrackedAndUntrackedChanges() throws {
        let (repo, branch) = try createRepositoryWithRemote()
        let remoteSha = try runGit(["rev-parse", "origin/\(branch)"], cwd: repo)
            .stdout
            .trimmingCharacters(in: .whitespacesAndNewlines)
        try "modified".write(to: repo.appendingPathComponent("test.txt"), atomically: true, encoding: .utf8)
        try "new".write(to: repo.appendingPathComponent("untracked.txt"), atomically: true, encoding: .utf8)

        let state = try XCTUnwrap(GitInfoCollector.gitDiffToRemote(cwd: repo))

        XCTAssertEqual(state.sha, remoteSha)
        XCTAssertTrue(state.diff.contains("test.txt"))
        XCTAssertTrue(state.diff.contains("untracked.txt"))
        XCTAssertTrue(state.diff.contains("modified"))
    }

    func testResolveRootGitProjectForTrustRegularRepoReturnsRepoRoot() throws {
        let repo = try createRepository()
        let nested = repo.appendingPathComponent("sub/dir", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let expected = repo.resolvingSymlinksInPath().standardizedFileURL.path

        XCTAssertEqual(GitInfoCollector.resolveRootGitProjectForTrust(cwd: repo)?.path, expected)
        XCTAssertEqual(GitInfoCollector.resolveRootGitProjectForTrust(cwd: nested)?.path, expected)
    }

    func testResolveRootGitProjectForTrustDetectsWorktreeAndReturnsMainRoot() throws {
        let repo = try createRepository()
        let worktree = repo.deletingLastPathComponent().appendingPathComponent("wt", isDirectory: true)
        try runGit(["worktree", "add", worktree.path, "-b", "feature/x"], cwd: repo)
        let nested = worktree.appendingPathComponent("nested/sub", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)

        let expected = repo.resolvingSymlinksInPath().standardizedFileURL.path

        XCTAssertEqual(GitInfoCollector.resolveRootGitProjectForTrust(cwd: worktree)?.path, expected)
        XCTAssertEqual(GitInfoCollector.resolveRootGitProjectForTrust(cwd: nested)?.path, expected)
    }

    func testResolveRootGitProjectForTrustReturnsNilOutsideRepo() throws {
        let dir = try GitInfoTemporaryDirectory()
        XCTAssertNil(GitInfoCollector.resolveRootGitProjectForTrust(cwd: dir.url))
    }

    private func createRepositoryWithRemote() throws -> (repo: URL, branch: String) {
        let repo = try createRepository()
        let remote = repo.deletingLastPathComponent().appendingPathComponent("remote.git", isDirectory: true)
        try runGit(["init", "--bare", remote.path], cwd: repo.deletingLastPathComponent())
        try runGit(["remote", "add", "origin", remote.path], cwd: repo)
        let branch = try runGit(["rev-parse", "--abbrev-ref", "HEAD"], cwd: repo)
            .stdout
            .trimmingCharacters(in: .whitespacesAndNewlines)
        try runGit(["push", "-u", "origin", branch], cwd: repo)
        return (repo, branch)
    }

    private func createRepository() throws -> URL {
        let dir = try GitInfoTemporaryDirectory()
        let repo = dir.url.appendingPathComponent("repo", isDirectory: true)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        retainedTemporaryDirectories.append(dir)
        try runGit(["init"], cwd: repo)
        try runGit(["config", "user.name", "Test User"], cwd: repo)
        try runGit(["config", "user.email", "test@example.com"], cwd: repo)
        try commitFile(name: "test.txt", contents: "test content", message: "Initial commit", cwd: repo)
        return repo
    }

    private func commitFile(name: String, contents: String, message: String, cwd: URL) throws {
        try contents.write(to: cwd.appendingPathComponent(name), atomically: true, encoding: .utf8)
        try runGit(["add", name], cwd: cwd)
        try runGit(["commit", "-m", message], cwd: cwd)
    }

    @discardableResult
    private func runGit(
        _ args: [String],
        cwd: URL,
        isolatedConfig: Bool = true
    ) throws -> (stdout: String, stderr: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = cwd
        if isolatedConfig {
            process.environment = [
                "GIT_CONFIG_GLOBAL": "/dev/null",
                "GIT_CONFIG_NOSYSTEM": "1"
            ]
        }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        try process.run()
        process.waitUntilExit()

        let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        XCTAssertEqual(process.terminationStatus, 0, "git \(args.joined(separator: " ")) failed: \(stderr)")
        return (stdout, stderr)
    }
}

private final class GitInfoTemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}
