import XCTest
@testable import CodexCore
#if canImport(Darwin)
import Darwin
#endif

final class ProjectDocTests: XCTestCase {
    func testNoDocFileReturnsNil() throws {
        let tmp = try CoreTemporaryDirectory()

        XCTAssertNil(ProjectDoc.getUserInstructions(config: config(cwd: tmp.url)))
        XCTAssertNil(try ProjectDoc.readProjectDocs(config: config(cwd: tmp.url)))
    }

    func testDocSmallerThanLimitIsReturned() throws {
        let tmp = try CoreTemporaryDirectory()
        try write("hello world", to: tmp.url.appendingPathComponent("AGENTS.md"))

        XCTAssertEqual(ProjectDoc.getUserInstructions(config: config(cwd: tmp.url)), "hello world")
    }

    func testDocLargerThanLimitIsTruncated() throws {
        let tmp = try CoreTemporaryDirectory()
        let limit = 1_024
        let huge = String(repeating: "A", count: limit * 2)
        try write(huge, to: tmp.url.appendingPathComponent("AGENTS.md"))

        let result = ProjectDoc.getUserInstructions(config: config(cwd: tmp.url, maxBytes: limit))

        XCTAssertEqual(result?.count, limit)
        XCTAssertEqual(result, String(huge.prefix(limit)))
    }

    func testFindsDocInRepoRoot() throws {
        let repo = try CoreTemporaryDirectory()
        try write("gitdir: /path/to/actual/git/dir\n", to: repo.url.appendingPathComponent(".git"))
        try write("root level doc", to: repo.url.appendingPathComponent("AGENTS.md"))

        let nested = repo.url.appendingPathComponent("workspace/crate_a", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)

        XCTAssertEqual(ProjectDoc.getUserInstructions(config: config(cwd: nested)), "root level doc")
    }

    func testZeroByteLimitDisablesDocs() throws {
        let tmp = try CoreTemporaryDirectory()
        try write("something", to: tmp.url.appendingPathComponent("AGENTS.md"))

        XCTAssertNil(ProjectDoc.getUserInstructions(config: config(cwd: tmp.url, maxBytes: 0)))
        XCTAssertEqual(try ProjectDoc.discoverProjectDocPaths(config: config(cwd: tmp.url, maxBytes: 0)), [])
    }

    func testMergesExistingInstructionsWithProjectDoc() throws {
        let tmp = try CoreTemporaryDirectory()
        try write("proj doc", to: tmp.url.appendingPathComponent("AGENTS.md"))

        let result = ProjectDoc.getUserInstructions(
            config: config(cwd: tmp.url, userInstructions: "base instructions")
        )

        XCTAssertEqual(result, "base instructions\(ProjectDoc.separator)proj doc")
    }

    func testKeepsExistingInstructionsWhenDocMissing() throws {
        let tmp = try CoreTemporaryDirectory()

        XCTAssertEqual(
            ProjectDoc.getUserInstructions(config: config(cwd: tmp.url, userInstructions: "some instructions")),
            "some instructions"
        )
    }

    func testConcatenatesRootAndCwdDocs() throws {
        let repo = try CoreTemporaryDirectory()
        try write("gitdir: /path/to/actual/git/dir\n", to: repo.url.appendingPathComponent(".git"))
        try write("root doc", to: repo.url.appendingPathComponent("AGENTS.md"))

        let nested = repo.url.appendingPathComponent("workspace/crate_a", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try write("crate doc", to: nested.appendingPathComponent("AGENTS.md"))

        XCTAssertEqual(ProjectDoc.getUserInstructions(config: config(cwd: nested)), "root doc\n\ncrate doc")
    }

    func testProjectRootMarkersAreHonoredForAgentsDiscoveryLikeRust() throws {
        let repo = try CoreTemporaryDirectory()
        try write("", to: repo.url.appendingPathComponent(".codex-root"))
        try write("parent doc", to: repo.url.appendingPathComponent("AGENTS.md"))

        let nested = repo.url.appendingPathComponent("dir1", isDirectory: true)
        try FileManager.default.createDirectory(at: nested.appendingPathComponent(".git", isDirectory: true), withIntermediateDirectories: true)
        try write("child doc", to: nested.appendingPathComponent("AGENTS.md"))

        let cfg = config(cwd: nested, projectRootMarkers: [".codex-root"])
        let discovery = try ProjectDoc.discoverProjectDocPaths(config: cfg)

        XCTAssertEqual(discovery.map { $0.lastPathComponent }, ["AGENTS.md", "AGENTS.md"])
        XCTAssertEqual(discovery.map { $0.standardizedFileURL.path }, [
            repo.url.appendingPathComponent("AGENTS.md").standardizedFileURL.path,
            nested.appendingPathComponent("AGENTS.md").standardizedFileURL.path
        ])
        XCTAssertEqual(ProjectDoc.getUserInstructions(config: cfg), "parent doc\n\nchild doc")
    }

    func testEmptyProjectRootMarkersDisableAncestorProjectDocSearchLikeRust() throws {
        let repo = try CoreTemporaryDirectory()
        try write("root doc", to: repo.url.appendingPathComponent("AGENTS.md"))
        try write("gitdir: /path/to/actual/git/dir\n", to: repo.url.appendingPathComponent(".git"))

        let nested = repo.url.appendingPathComponent("workspace/crate_a", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try write("crate doc", to: nested.appendingPathComponent("AGENTS.md"))

        let cfg = config(cwd: nested, projectRootMarkers: [])

        XCTAssertEqual(ProjectDoc.getUserInstructions(config: cfg), "crate doc")
        XCTAssertEqual(
            try ProjectDoc.discoverProjectDocPaths(config: cfg).map { $0.standardizedFileURL.path },
            [nested.appendingPathComponent("AGENTS.md").standardizedFileURL.path]
        )
    }

    func testLocalOverridePreferredOverAgents() throws {
        let tmp = try CoreTemporaryDirectory()
        try write("versioned", to: tmp.url.appendingPathComponent(ProjectDoc.defaultFilename))
        try write("local", to: tmp.url.appendingPathComponent(ProjectDoc.localOverrideFilename))

        let cfg = config(cwd: tmp.url)
        let discovery = try ProjectDoc.discoverProjectDocPaths(config: cfg)

        XCTAssertEqual(ProjectDoc.getUserInstructions(config: cfg), "local")
        XCTAssertEqual(discovery.map { $0.lastPathComponent }, [ProjectDoc.localOverrideFilename])
    }

    func testUsesConfiguredFallbackWhenAgentsMissing() throws {
        let tmp = try CoreTemporaryDirectory()
        try write("example instructions", to: tmp.url.appendingPathComponent("EXAMPLE.md"))

        XCTAssertEqual(
            ProjectDoc.getUserInstructions(config: config(cwd: tmp.url, fallbackFilenames: ["EXAMPLE.md"])),
            "example instructions"
        )
    }

    func testAgentsDirectoryIsIgnoredLikeRust() throws {
        let tmp = try CoreTemporaryDirectory()
        try FileManager.default.createDirectory(
            at: tmp.url.appendingPathComponent(ProjectDoc.defaultFilename, isDirectory: true),
            withIntermediateDirectories: true
        )

        let cfg = config(cwd: tmp.url)

        XCTAssertNil(ProjectDoc.getUserInstructions(config: cfg))
        XCTAssertEqual(try ProjectDoc.discoverProjectDocPaths(config: cfg), [])
    }

    func testOverrideDirectoryFallsBackToAgentsFileLikeRust() throws {
        let tmp = try CoreTemporaryDirectory()
        try FileManager.default.createDirectory(
            at: tmp.url.appendingPathComponent(ProjectDoc.localOverrideFilename, isDirectory: true),
            withIntermediateDirectories: true
        )
        try write("primary", to: tmp.url.appendingPathComponent(ProjectDoc.defaultFilename))

        let cfg = config(cwd: tmp.url)
        let discovery = try ProjectDoc.discoverProjectDocPaths(config: cfg)

        XCTAssertEqual(ProjectDoc.getUserInstructions(config: cfg), "primary")
        XCTAssertEqual(discovery.map { $0.lastPathComponent }, [ProjectDoc.defaultFilename])
    }

#if canImport(Darwin)
    func testAgentsSpecialFileIsIgnoredLikeRust() throws {
        let tmp = try CoreTemporaryDirectory()
        let fifoPath = tmp.url.appendingPathComponent(ProjectDoc.defaultFilename).path
        let created = fifoPath.withCString { path in
            mkfifo(path, mode_t(0o644))
        }
        XCTAssertEqual(created, 0)

        let cfg = config(cwd: tmp.url)

        XCTAssertNil(ProjectDoc.getUserInstructions(config: cfg))
        XCTAssertEqual(try ProjectDoc.discoverProjectDocPaths(config: cfg), [])
    }
#endif

    func testAgentsPreferredOverFallbacks() throws {
        let tmp = try CoreTemporaryDirectory()
        try write("primary", to: tmp.url.appendingPathComponent("AGENTS.md"))
        try write("secondary", to: tmp.url.appendingPathComponent("EXAMPLE.md"))

        let cfg = config(cwd: tmp.url, fallbackFilenames: ["EXAMPLE.md", ".example.md"])
        let discovery = try ProjectDoc.discoverProjectDocPaths(config: cfg)

        XCTAssertEqual(ProjectDoc.getUserInstructions(config: cfg), "primary")
        XCTAssertEqual(discovery.map { $0.lastPathComponent }, [ProjectDoc.defaultFilename])
    }

    func testSkillsAreNotAppendedToProjectDocLikeRust() throws {
        let tmp = try CoreTemporaryDirectory()
        try write("base doc", to: tmp.url.appendingPathComponent("AGENTS.md"))

        let result = ProjectDoc.getUserInstructions(config: config(cwd: tmp.url))

        XCTAssertEqual(result, "base doc")
    }

    func testSkillsDoNotCreateProjectDocUserInstructionsLikeRust() throws {
        let tmp = try CoreTemporaryDirectory()

        let result = ProjectDoc.getUserInstructions(config: config(cwd: tmp.url))

        XCTAssertNil(result)
    }

    func testConfigLoaderReadsProjectDocSettings() throws {
        let tmp = try CoreTemporaryDirectory()
        try """
        project_doc_max_bytes = 123
        project_doc_fallback_filenames = ["GUIDE.md", "NOTES.md"]
        """.write(to: tmp.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        let runtime = try CodexConfigLoader.load(codexHome: tmp.url, systemConfigFile: nil)
        let projectConfig = ProjectDocConfig(runtimeConfig: runtime, cwd: tmp.url)

        XCTAssertEqual(runtime.projectDocMaxBytes, 123)
        XCTAssertEqual(runtime.projectDocFallbackFilenames, ["GUIDE.md", "NOTES.md"])
        XCTAssertEqual(runtime.projectRootMarkers, [".git"])
        XCTAssertEqual(projectConfig.projectDocMaxBytes, 123)
        XCTAssertEqual(projectConfig.projectDocFallbackFilenames, ["GUIDE.md", "NOTES.md"])
        XCTAssertEqual(projectConfig.projectRootMarkers, [".git"])
    }

    func testConfigLoaderProjectRootMarkersFeedProjectDocDiscovery() throws {
        let tmp = try CoreTemporaryDirectory()
        let repo = tmp.url.appendingPathComponent("repo", isDirectory: true)
        let nested = repo.appendingPathComponent("nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try write("", to: repo.appendingPathComponent(".hg"))
        try write("root doc", to: repo.appendingPathComponent("AGENTS.md"))
        try write("child doc", to: nested.appendingPathComponent("AGENTS.md"))
        try #"project_root_markers = [".hg"]"#
            .write(to: tmp.url.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        let runtime = try CodexConfigLoader.load(codexHome: tmp.url, systemConfigFile: nil)
        let projectConfig = ProjectDocConfig(runtimeConfig: runtime, cwd: nested)

        XCTAssertEqual(projectConfig.projectRootMarkers, [".hg"])
        XCTAssertEqual(ProjectDoc.getUserInstructions(config: projectConfig), "root doc\n\nchild doc")
    }

    private func config(
        cwd: URL,
        userInstructions: String? = nil,
        maxBytes: Int = CodexConfigDefaults.projectDocMaxBytes,
        fallbackFilenames: [String] = [],
        projectRootMarkers: [String] = CodexConfigDefaults.projectRootMarkers
    ) -> ProjectDocConfig {
        ProjectDocConfig(
            cwd: cwd,
            userInstructions: userInstructions,
            projectDocMaxBytes: maxBytes,
            projectDocFallbackFilenames: fallbackFilenames,
            projectRootMarkers: projectRootMarkers
        )
    }

    private func write(_ contents: String, to url: URL) throws {
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }
}

private final class CoreTemporaryDirectory {
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
