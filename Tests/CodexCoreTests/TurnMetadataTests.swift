import XCTest
@testable import CodexCore

final class TurnMetadataTests: XCTestCase {
    private var retainedTemporaryDirectories: [TurnMetadataTemporaryDirectory] = []

    func testBuildTurnMetadataHeaderIncludesGitMetadataForCleanRepoLikeRust() throws {
        let repo = try createRepository(named: "repo-東京")
        let remoteURL = "https://github.com/OpenAI/Codex.git"
        try runGit(["remote", "add", "origin", remoteURL], cwd: repo)
        let head = try runGit(["rev-parse", "HEAD"], cwd: repo)
            .stdout
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let header = try XCTUnwrap(buildTurnMetadataHeader(cwd: repo, sandbox: "none"))
        XCTAssertTrue(header.allSatisfy(\.isASCII))
        XCTAssertFalse(header.contains("東京"))
        let json = try jsonObject(header)
        let workspaces = try XCTUnwrap(json["workspaces"] as? [String: [String: Any]])
        let workspace = try XCTUnwrap(workspaces[repo.path])

        XCTAssertEqual(json["sandbox"] as? String, "none")
        XCTAssertEqual(workspace["associated_remote_urls"] as? [String: String], ["origin": remoteURL])
        XCTAssertEqual(workspace["latest_git_commit_hash"] as? String, head)
        XCTAssertEqual(workspace["has_changes"] as? Bool, false)
    }

    func testBuildTurnMetadataHeaderReturnsNilOutsideRepoWithoutSandboxLikeRust() throws {
        let dir = try TurnMetadataTemporaryDirectory()
        retainedTemporaryDirectories.append(dir)

        XCTAssertNil(buildTurnMetadataHeader(cwd: dir.url))
    }

    func testBuildTurnMetadataHeaderKeepsSandboxOutsideRepoLikeRust() throws {
        let dir = try TurnMetadataTemporaryDirectory()
        retainedTemporaryDirectories.append(dir)

        let header = try XCTUnwrap(buildTurnMetadataHeader(cwd: dir.url, sandbox: "none"))
        let json = try jsonObject(header)

        XCTAssertEqual(json["sandbox"] as? String, "none")
        XCTAssertNil(json["workspaces"])
    }

    func testBuildTurnMetadataHeaderWithIdentityKeepsIdentityOutsideGitRepoLikeRust() throws {
        let dir = try TurnMetadataTemporaryDirectory()
        retainedTemporaryDirectories.append(dir)

        XCTAssertNil(buildTurnMetadataHeader(cwd: dir.url))
        let header = try XCTUnwrap(buildTurnMetadataHeaderWithIdentity(
            cwd: dir.url,
            sessionID: "session-a",
            threadID: "thread-a",
            threadSource: .memoryConsolidation,
            turnID: "turn-a"
        ))
        XCTAssertTrue(header.allSatisfy(\.isASCII))
        let json = try jsonObject(header)

        XCTAssertEqual(json["session_id"] as? String, "session-a")
        XCTAssertEqual(json["thread_id"] as? String, "thread-a")
        XCTAssertEqual(json["thread_source"] as? String, "memory_consolidation")
        XCTAssertEqual(json["turn_id"] as? String, "turn-a")
        XCTAssertNil(json["workspaces"])
    }

    func testTurnMetadataStateEnrichesHeaderWithWorkspaceGitMetadataLikeRust() async throws {
        let repo = try createRepository(named: "repo-東京")
        let remoteURL = "https://github.com/OpenAI/Codex.git"
        try runGit(["remote", "add", "origin", remoteURL], cwd: repo)
        let head = try runGit(["rev-parse", "HEAD"], cwd: repo)
            .stdout
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let state = TurnMetadataState(
            sessionID: "session-a",
            threadID: "thread-a",
            threadSource: .user,
            turnID: "turn-a",
            cwd: repo,
            sandbox: "read-only"
        )

        let baseHeader = try XCTUnwrap(state.currentHeaderValue())
        XCTAssertNil(try jsonObject(baseHeader)["workspaces"])

        state.spawnGitEnrichmentTask()
        let enriched = try await waitForHeader(state) { header in
            guard let json = try? jsonObject(header),
                  let workspaces = json["workspaces"] as? [String: [String: Any]]
            else {
                return false
            }
            return workspaces[repo.path] != nil
        }
        let json = try jsonObject(enriched)
        let workspaces = try XCTUnwrap(json["workspaces"] as? [String: [String: Any]])
        let workspace = try XCTUnwrap(workspaces[repo.path])

        XCTAssertTrue(enriched.allSatisfy(\.isASCII))
        XCTAssertFalse(enriched.contains("東京"))
        XCTAssertEqual(json["session_id"] as? String, "session-a")
        XCTAssertEqual(json["sandbox"] as? String, "read-only")
        XCTAssertEqual(workspace["associated_remote_urls"] as? [String: String], ["origin": remoteURL])
        XCTAssertEqual(workspace["latest_git_commit_hash"] as? String, head)
        XCTAssertEqual(workspace["has_changes"] as? Bool, false)
    }

    func testTurnMetadataStateDoesNotEnrichOutsideGitRepoLikeRust() throws {
        let dir = try TurnMetadataTemporaryDirectory()
        retainedTemporaryDirectories.append(dir)
        let state = TurnMetadataState(
            sessionID: "session-a",
            threadID: "thread-a",
            threadSource: .user,
            turnID: "turn-a",
            cwd: dir.url,
            sandbox: "read-only"
        )

        state.spawnGitEnrichmentTask()

        let header = try XCTUnwrap(state.currentHeaderValue())
        let json = try jsonObject(header)
        XCTAssertNil(json["workspaces"])
        XCTAssertEqual(json["session_id"] as? String, "session-a")
        XCTAssertEqual(json["sandbox"] as? String, "read-only")
    }

    func testCurrentHeaderValueStartsWithBaseTurnMetadataLikeRust() throws {
        let state = TurnMetadataState(
            sessionID: "session-a",
            threadID: "thread-a",
            threadSource: .user,
            turnID: "turn-a",
            sandbox: "read-only"
        )

        let header = try XCTUnwrap(state.currentHeaderValue())
        let json = try jsonObject(header)

        XCTAssertEqual(json["session_id"] as? String, "session-a")
        XCTAssertEqual(json["thread_id"] as? String, "thread-a")
        XCTAssertEqual(json["thread_source"] as? String, "user")
        XCTAssertEqual(json["turn_id"] as? String, "turn-a")
        XCTAssertEqual(json["sandbox"] as? String, "read-only")
    }

    func testClientMetadataCannotSetReservedTurnStartedAtLikeRust() throws {
        let state = TurnMetadataState(
            sessionID: "session-a",
            threadID: "thread-a",
            threadSource: .user,
            turnID: "turn-a"
        )
        state.setResponsesAPIClientMetadata([
            "turn_started_at_unix_ms": "client-supplied"
        ])

        let header = try XCTUnwrap(state.currentHeaderValue())
        let json = try jsonObject(header)

        XCTAssertNil(json["turn_started_at_unix_ms"])
    }

    func testClientMetadataMergesWithoutReplacingReservedFieldsLikeRust() throws {
        let state = TurnMetadataState(
            sessionID: "session-a",
            threadID: "thread-a",
            threadSource: .user,
            turnID: "turn-a"
        )
        state.setResponsesAPIClientMetadata([
            "fiber_run_id": "fiber-123",
            "origin": "東京",
            "model": "client-supplied",
            "reasoning_effort": "client-supplied",
            "session_id": "client-supplied",
            "thread_id": "client-supplied",
            "thread_source": "client-supplied",
            "turn_started_at_unix_ms": "client-supplied"
        ])
        state.setTurnStartedAtUnixMs(1_700_000_000_123)

        let header = try XCTUnwrap(state.currentHeaderValue())
        XCTAssertTrue(header.allSatisfy(\.isASCII))
        XCTAssertFalse(header.contains("東京"))
        let json = try jsonObject(header)

        XCTAssertEqual(json["fiber_run_id"] as? String, "fiber-123")
        XCTAssertEqual(json["origin"] as? String, "東京")
        XCTAssertEqual(json["model"] as? String, "client-supplied")
        XCTAssertEqual(json["reasoning_effort"] as? String, "client-supplied")
        XCTAssertEqual(json["session_id"] as? String, "session-a")
        XCTAssertEqual(json["thread_id"] as? String, "thread-a")
        XCTAssertEqual(json["thread_source"] as? String, "user")
        XCTAssertEqual(json["turn_id"] as? String, "turn-a")
        XCTAssertEqual(json["turn_started_at_unix_ms"] as? Int64, 1_700_000_000_123)
    }

    func testCurrentMetaValueForMcpRequestAddsModelAndReasoningEffortLikeRust() throws {
        let state = TurnMetadataState(
            sessionID: "session-a",
            threadID: "thread-a",
            threadSource: .user,
            turnID: "turn-a"
        )
        state.setResponsesAPIClientMetadata([
            "model": "client-supplied",
            "reasoning_effort": "client-supplied",
            "trace": "turn-trace"
        ])

        let value = try XCTUnwrap(state.currentMetaValueForMcpRequest(
            context: McpTurnMetadataContext(model: "gpt-5.4", reasoningEffort: .high)
        ))
        guard case let .object(object) = value else {
            return XCTFail("expected object metadata")
        }

        XCTAssertEqual(object["model"], .string("gpt-5.4"))
        XCTAssertEqual(object["reasoning_effort"], .string("high"))
        XCTAssertEqual(object["trace"], .string("turn-trace"))
        XCTAssertEqual(object["session_id"], .string("session-a"))

        let noEffort = try XCTUnwrap(state.currentMetaValueForMcpRequest(
            context: McpTurnMetadataContext(model: "gpt-5.4")
        ))
        guard case let .object(noEffortObject) = noEffort else {
            return XCTFail("expected object metadata")
        }
        XCTAssertNil(noEffortObject["reasoning_effort"])
    }
}

private func jsonObject(_ text: String) throws -> [String: Any] {
    try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
}

private func waitForHeader(
    _ state: TurnMetadataState,
    matching predicate: (String) throws -> Bool
) async throws -> String {
    for _ in 0..<50 {
        if let header = state.currentHeaderValue(),
           try predicate(header)
        {
            return header
        }
        try await Task.sleep(nanoseconds: 20_000_000)
    }
    return try XCTUnwrap(state.currentHeaderValue())
}

private extension TurnMetadataTests {
    func createRepository(named name: String = "repo") throws -> URL {
        let dir = try TurnMetadataTemporaryDirectory()
        retainedTemporaryDirectories.append(dir)
        let repo = dir.url.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        try runGit(["init"], cwd: repo)
        try runGit(["config", "user.name", "Test User"], cwd: repo)
        try runGit(["config", "user.email", "test@example.com"], cwd: repo)
        try "hello".write(to: repo.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        try runGit(["add", "."], cwd: repo)
        try runGit(["commit", "-m", "initial"], cwd: repo)
        return repo
    }

    @discardableResult
    func runGit(_ args: [String], cwd: URL) throws -> (stdout: String, stderr: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = cwd
        process.environment = [
            "GIT_CONFIG_GLOBAL": "/dev/null",
            "GIT_CONFIG_NOSYSTEM": "1"
        ]

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

private final class TurnMetadataTemporaryDirectory {
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
