import XCTest
@testable import CodexCore

final class SkillLoaderTests: XCTestCase {
    func testLoadsRepoUserAndSystemSkillsInRustPromptOrder() throws {
        let tmp = try SkillLoaderTemporaryDirectory()
        let cwd = tmp.url.appendingPathComponent("repo", isDirectory: true)
        let codexHome = tmp.url.appendingPathComponent("home", isDirectory: true)
        try FileManager.default.createDirectory(at: cwd, withIntermediateDirectories: true)

        let repoSkill = cwd.appendingPathComponent(".codex/skills/repo-plan/SKILL.md", isDirectory: false)
        let userSkill = codexHome.appendingPathComponent("skills/user-doc/SKILL.md", isDirectory: false)
        let systemSkill = codexHome.appendingPathComponent("skills/.system/system-help/SKILL.md", isDirectory: false)
        try writeSkill(name: "repo-plan", description: "repo scoped", to: repoSkill)
        try writeSkill(name: "user-doc", description: "user scoped", to: userSkill)
        try writeSkill(name: "system-help", description: "system scoped", to: systemSkill)

        let outcome = SkillLoader.load(cwd: cwd, codexHome: codexHome)

        XCTAssertEqual(outcome.skills.map { $0.name }, ["repo-plan", "user-doc", "system-help"])
        XCTAssertEqual(outcome.skills.map { $0.scope }, [SkillScope.repo, .user, .system])
        XCTAssertEqual(outcome.skillRoots, [
            repoSkill.deletingLastPathComponent().deletingLastPathComponent().path,
            codexHome.appendingPathComponent("skills", isDirectory: true).path,
            codexHome.appendingPathComponent("skills/.system", isDirectory: true).path
        ])
        XCTAssertEqual(outcome.skillRootByPath[repoSkill.path], repoSkill.deletingLastPathComponent().deletingLastPathComponent().path)
    }

    func testCanOmitSystemSkillsWhenBundledSkillsAreDisabled() throws {
        let tmp = try SkillLoaderTemporaryDirectory()
        let cwd = tmp.url.appendingPathComponent("repo", isDirectory: true)
        let codexHome = tmp.url.appendingPathComponent("home", isDirectory: true)
        try FileManager.default.createDirectory(at: cwd, withIntermediateDirectories: true)
        try writeSkill(
            name: "system-help",
            description: "system scoped",
            to: codexHome.appendingPathComponent("skills/.system/system-help/SKILL.md", isDirectory: false)
        )

        let outcome = SkillLoader.load(cwd: cwd, codexHome: codexHome, includeSystemSkills: false)

        XCTAssertTrue(outcome.skills.isEmpty)
        XCTAssertTrue(outcome.skillRoots.isEmpty)
    }

    func testUserAndSessionSkillConfigRulesFilterPromptSkillsLikeRust() throws {
        let tmp = try SkillLoaderTemporaryDirectory()
        let cwd = tmp.url.appendingPathComponent("repo", isDirectory: true)
        let codexHome = tmp.url.appendingPathComponent("home", isDirectory: true)
        try FileManager.default.createDirectory(at: cwd, withIntermediateDirectories: true)
        let disabledByPath = codexHome.appendingPathComponent("skills/path-disabled/SKILL.md", isDirectory: false)
        let reenabledByName = codexHome.appendingPathComponent("skills/name-toggle/SKILL.md", isDirectory: false)
        try writeSkill(name: "path-disabled", description: "path disabled", to: disabledByPath)
        try writeSkill(name: "name-toggle", description: "session wins", to: reenabledByName)
        try writeSkill(
            name: "kept",
            description: "still enabled",
            to: codexHome.appendingPathComponent("skills/kept/SKILL.md", isDirectory: false)
        )
        let stack = try ConfigLayerStack(layers: [
            ConfigLayerEntry(
                name: .user(file: try AbsolutePath(absolutePath: codexHome.appendingPathComponent("config.toml").path)),
                config: .table([
                    "skills": .table([
                        "config": .array([
                            .table([
                                "path": .string(disabledByPath.path),
                                "enabled": .bool(false)
                            ]),
                            .table([
                                "name": .string("name-toggle"),
                                "enabled": .bool(false)
                            ])
                        ])
                    ])
                ])
            ),
            ConfigLayerEntry(
                name: .sessionFlags,
                config: .table([
                    "skills": .table([
                        "config": .array([
                            .table([
                                "name": .string("name-toggle"),
                                "enabled": .bool(true)
                            ])
                        ])
                    ])
                ])
            )
        ])

        let outcome = SkillLoader.load(cwd: cwd, codexHome: codexHome, configLayerStack: stack)

        XCTAssertEqual(outcome.skills.map { $0.name }, ["kept", "name-toggle"])
        XCTAssertNil(outcome.skillRootByPath[disabledByPath.path])
    }

    func testSystemSkillParseErrorsAreSuppressedLikeRust() throws {
        let tmp = try SkillLoaderTemporaryDirectory()
        let cwd = tmp.url.appendingPathComponent("repo", isDirectory: true)
        let codexHome = tmp.url.appendingPathComponent("home", isDirectory: true)
        try FileManager.default.createDirectory(at: cwd, withIntermediateDirectories: true)
        let malformed = codexHome.appendingPathComponent("skills/.system/broken/SKILL.md", isDirectory: false)
        try FileManager.default.createDirectory(at: malformed.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "no frontmatter".write(to: malformed, atomically: true, encoding: .utf8)

        let outcome = SkillLoader.load(cwd: cwd, codexHome: codexHome)

        XCTAssertTrue(outcome.skills.isEmpty)
        XCTAssertTrue(outcome.errors.isEmpty)
    }

    private func writeSkill(name: String, description: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try """
        ---
        name: \(name)
        description: \(description)
        ---

        # \(name)
        """.write(to: url, atomically: true, encoding: .utf8)
    }
}

private struct SkillLoaderTemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-swift-skill-loader-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
}
