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

    func testLoadsPluginSkillRootsWithManifestNamespaceAndPluginIDLikeRust() throws {
        let tmp = try SkillLoaderTemporaryDirectory()
        let cwd = tmp.url.appendingPathComponent("repo", isDirectory: true)
        let codexHome = tmp.url.appendingPathComponent("home", isDirectory: true)
        let pluginRoot = tmp.url.appendingPathComponent("plugins/sample", isDirectory: true)
        let pluginSkillsRoot = pluginRoot.appendingPathComponent("skills", isDirectory: true)
        let pluginSkill = pluginSkillsRoot.appendingPathComponent("sample-search/SKILL.md", isDirectory: false)
        try FileManager.default.createDirectory(at: cwd, withIntermediateDirectories: true)
        try writeSkill(name: "sample-search", description: "search sample data", to: pluginSkill)
        try writePluginManifest(name: "sample", to: pluginRoot.appendingPathComponent(".codex-plugin/plugin.json"))

        let outcome = SkillLoader.load(
            cwd: cwd,
            codexHome: codexHome,
            pluginSkillRoots: [PluginSkillRoot(path: pluginSkillsRoot, pluginID: "sample@test")],
            includeSystemSkills: false
        )

        XCTAssertEqual(outcome.errors, [])
        XCTAssertEqual(outcome.skills, [
            SkillMetadata(
                name: "sample:sample-search",
                description: "search sample data",
                path: pluginSkill.path,
                scope: .user,
                pluginID: "sample@test"
            )
        ])
        XCTAssertEqual(outcome.skillRoots, [pluginSkillsRoot.path])
        XCTAssertEqual(outcome.skillRootByPath[pluginSkill.path], pluginSkillsRoot.path)
    }

    func testPluginSkillRootsHonorNameConfigRulesUsingNamespacedName() throws {
        let tmp = try SkillLoaderTemporaryDirectory()
        let cwd = tmp.url.appendingPathComponent("repo", isDirectory: true)
        let codexHome = tmp.url.appendingPathComponent("home", isDirectory: true)
        let pluginRoot = tmp.url.appendingPathComponent("plugins/sample", isDirectory: true)
        let pluginSkillsRoot = pluginRoot.appendingPathComponent("skills", isDirectory: true)
        let pluginSkill = pluginSkillsRoot.appendingPathComponent("sample-search/SKILL.md", isDirectory: false)
        try FileManager.default.createDirectory(at: cwd, withIntermediateDirectories: true)
        try writeSkill(name: "sample-search", description: "search sample data", to: pluginSkill)
        try writePluginManifest(name: "sample", to: pluginRoot.appendingPathComponent(".codex-plugin/plugin.json"))
        let stack = try ConfigLayerStack(layers: [
            ConfigLayerEntry(
                name: .user(file: try AbsolutePath(absolutePath: codexHome.appendingPathComponent("config.toml").path)),
                config: .table([
                    "skills": .table([
                        "config": .array([
                            .table([
                                "name": .string("sample:sample-search"),
                                "enabled": .bool(false)
                            ])
                        ])
                    ])
                ])
            )
        ])

        let outcome = SkillLoader.load(
            cwd: cwd,
            codexHome: codexHome,
            configLayerStack: stack,
            pluginSkillRoots: [PluginSkillRoot(path: pluginSkillsRoot, pluginID: "sample@test")],
            includeSystemSkills: false
        )

        XCTAssertTrue(outcome.skills.isEmpty)
        XCTAssertNil(outcome.skillRootByPath[pluginSkill.path])
    }

    func testConfiguredInstalledPluginSkillRootsLoadLikeRustManager() throws {
        let tmp = try SkillLoaderTemporaryDirectory()
        let cwd = tmp.url.appendingPathComponent("repo", isDirectory: true)
        let codexHome = tmp.url.appendingPathComponent("home", isDirectory: true)
        let pluginRoot = codexHome.appendingPathComponent(
            "plugins/cache/test/sample/2026-05-11",
            isDirectory: true
        )
        let defaultSkill = pluginRoot.appendingPathComponent("skills/search/SKILL.md", isDirectory: false)
        let customSkill = pluginRoot.appendingPathComponent("more-skills/deep/SKILL.md", isDirectory: false)
        try FileManager.default.createDirectory(at: cwd, withIntermediateDirectories: true)
        try writeSkill(name: "search", description: "search sample data", to: defaultSkill)
        try writeSkill(name: "deep", description: "deep sample data", to: customSkill)
        try writePluginManifest(
            name: "sample",
            skillsPath: "./more-skills",
            to: pluginRoot.appendingPathComponent(".codex-plugin/plugin.json")
        )
        let stack = try pluginConfigStack(codexHome: codexHome, pluginID: "sample@test")

        let roots = SkillLoader.configuredPluginSkillRoots(codexHome: codexHome, configLayerStack: stack)
        let outcome = SkillLoader.load(
            cwd: cwd,
            codexHome: codexHome,
            configLayerStack: stack,
            includeSystemSkills: false
        )

        XCTAssertEqual(roots, [
            PluginSkillRoot(path: pluginRoot.appendingPathComponent("more-skills", isDirectory: true), pluginID: "sample@test"),
            PluginSkillRoot(path: pluginRoot.appendingPathComponent("skills", isDirectory: true), pluginID: "sample@test")
        ])
        XCTAssertEqual(outcome.errors, [])
        XCTAssertEqual(outcome.skills.map(\.name), ["sample:deep", "sample:search"])
        XCTAssertEqual(outcome.skills.map(\.pluginID), ["sample@test", "sample@test"])
        XCTAssertEqual(outcome.skillRootByPath[customSkill.path], pluginRoot.appendingPathComponent("more-skills").path)
        XCTAssertEqual(outcome.skillRootByPath[defaultSkill.path], pluginRoot.appendingPathComponent("skills").path)
    }

    func testConfiguredPluginSkillRootsRespectFeatureAndEnablementLikeRustManager() throws {
        let tmp = try SkillLoaderTemporaryDirectory()
        let codexHome = tmp.url.appendingPathComponent("home", isDirectory: true)
        let pluginRoot = codexHome.appendingPathComponent("plugins/cache/test/sample/local", isDirectory: true)
        try writeSkill(
            name: "search",
            description: "search sample data",
            to: pluginRoot.appendingPathComponent("skills/search/SKILL.md", isDirectory: false)
        )
        try writePluginManifest(name: "sample", to: pluginRoot.appendingPathComponent(".codex-plugin/plugin.json"))

        let disabledPluginStack = try pluginConfigStack(
            codexHome: codexHome,
            pluginID: "sample@test",
            enabled: false
        )
        let disabledFeatureStack = try pluginConfigStack(
            codexHome: codexHome,
            pluginID: "sample@test",
            pluginsFeatureEnabled: false
        )

        XCTAssertTrue(SkillLoader.configuredPluginSkillRoots(
            codexHome: codexHome,
            configLayerStack: disabledPluginStack
        ).isEmpty)
        XCTAssertTrue(SkillLoader.configuredPluginSkillRoots(
            codexHome: codexHome,
            configLayerStack: disabledFeatureStack
        ).isEmpty)
    }

    func testRemoteInstalledPluginSkillRootsLoadFromCacheWithoutUserPluginConfigLikeRustManager() throws {
        let tmp = try SkillLoaderTemporaryDirectory()
        let cwd = tmp.url.appendingPathComponent("repo", isDirectory: true)
        let codexHome = tmp.url.appendingPathComponent("home", isDirectory: true)
        let pluginRoot = codexHome.appendingPathComponent(
            "plugins/cache/chatgpt-global/linear/local",
            isDirectory: true
        )
        let skillPath = pluginRoot.appendingPathComponent("skills/search/SKILL.md", isDirectory: false)
        try FileManager.default.createDirectory(at: cwd, withIntermediateDirectories: true)
        try writeSkill(name: "search", description: "search Linear data", to: skillPath)
        try writePluginManifest(name: "linear", to: pluginRoot.appendingPathComponent(".codex-plugin/plugin.json"))
        let stack = try remotePluginFeatureConfigStack(codexHome: codexHome)
        let remoteInstalled = [
            RemoteInstalledPluginReference(
                marketplaceName: "chatgpt-global",
                pluginName: "linear",
                enabled: true
            )
        ]

        let roots = SkillLoader.configuredPluginSkillRoots(
            codexHome: codexHome,
            configLayerStack: stack,
            remoteInstalledPlugins: remoteInstalled
        )
        let outcome = SkillLoader.load(
            cwd: cwd,
            codexHome: codexHome,
            configLayerStack: stack,
            remoteInstalledPlugins: remoteInstalled,
            includeSystemSkills: false
        )

        XCTAssertEqual(roots, [
            PluginSkillRoot(path: pluginRoot.appendingPathComponent("skills", isDirectory: true), pluginID: "linear@chatgpt-global")
        ])
        XCTAssertEqual(outcome.errors, [])
        XCTAssertEqual(outcome.skills.map(\.name), ["linear:search"])
        XCTAssertEqual(outcome.skills.map(\.pluginID), ["linear@chatgpt-global"])
    }

    func testRemoteInstalledPluginSkillRootsRespectPluginsFeatureAndLocalCacheLikeRustManager() throws {
        let tmp = try SkillLoaderTemporaryDirectory()
        let codexHome = tmp.url.appendingPathComponent("home", isDirectory: true)
        let pluginRoot = codexHome.appendingPathComponent(
            "plugins/cache/chatgpt-global/linear/local",
            isDirectory: true
        )
        try writeSkill(
            name: "search",
            description: "search Linear data",
            to: pluginRoot.appendingPathComponent("skills/search/SKILL.md", isDirectory: false)
        )
        try writePluginManifest(name: "linear", to: pluginRoot.appendingPathComponent(".codex-plugin/plugin.json"))
        let remoteInstalled = [
            RemoteInstalledPluginReference(
                marketplaceName: "chatgpt-global",
                pluginName: "linear",
                enabled: true
            )
        ]

        XCTAssertEqual(SkillLoader.configuredPluginSkillRoots(
            codexHome: codexHome,
            configLayerStack: try remotePluginFeatureConfigStack(codexHome: codexHome, remotePluginEnabled: false),
            remoteInstalledPlugins: remoteInstalled
        ), [
            PluginSkillRoot(path: pluginRoot.appendingPathComponent("skills", isDirectory: true), pluginID: "linear@chatgpt-global")
        ])
        XCTAssertTrue(SkillLoader.configuredPluginSkillRoots(
            codexHome: codexHome,
            configLayerStack: try remotePluginFeatureConfigStack(codexHome: codexHome, pluginsFeatureEnabled: false),
            remoteInstalledPlugins: remoteInstalled
        ).isEmpty)
        XCTAssertTrue(SkillLoader.configuredPluginSkillRoots(
            codexHome: codexHome,
            configLayerStack: try remotePluginFeatureConfigStack(codexHome: codexHome),
            remoteInstalledPlugins: [
                RemoteInstalledPluginReference(
                    marketplaceName: "chatgpt-global",
                    pluginName: "linear",
                    enabled: false
                )
            ]
        ).isEmpty)
        XCTAssertTrue(SkillLoader.configuredPluginSkillRoots(
            codexHome: codexHome,
            configLayerStack: try remotePluginFeatureConfigStack(codexHome: codexHome),
            remoteInstalledPlugins: [
                RemoteInstalledPluginReference(
                    marketplaceName: "chatgpt-global",
                    pluginName: "missing",
                    enabled: true
                )
            ]
        ).isEmpty)
    }

    func testFallsBackToDirectoryNameWhenSkillNameIsMissingLikeRust() throws {
        let tmp = try SkillLoaderTemporaryDirectory()
        let cwd = tmp.url.appendingPathComponent("repo", isDirectory: true)
        let codexHome = tmp.url.appendingPathComponent("home", isDirectory: true)
        let skillPath = codexHome.appendingPathComponent(
            "skills/directory-derived/SKILL.md",
            isDirectory: false
        )
        try FileManager.default.createDirectory(at: cwd, withIntermediateDirectories: true)
        try writeRawSkill(frontmatter: "description: fallback name", to: skillPath)

        let outcome = SkillLoader.load(cwd: cwd, codexHome: codexHome, includeSystemSkills: false)

        XCTAssertEqual(outcome.errors, [])
        XCTAssertEqual(outcome.skills, [
            SkillMetadata(
                name: "directory-derived",
                description: "fallback name",
                path: skillPath.path,
                scope: .user
            )
        ])
    }

    func testFallsBackToDirectoryNameWhenSkillNameIsBlankLikeRust() throws {
        let tmp = try SkillLoaderTemporaryDirectory()
        let cwd = tmp.url.appendingPathComponent("repo", isDirectory: true)
        let codexHome = tmp.url.appendingPathComponent("home", isDirectory: true)
        let skillPath = codexHome.appendingPathComponent("skills/blank-name/SKILL.md", isDirectory: false)
        try FileManager.default.createDirectory(at: cwd, withIntermediateDirectories: true)
        try writeRawSkill(
            frontmatter: """
            name:
            description: fallback name
            """,
            to: skillPath
        )

        let outcome = SkillLoader.load(cwd: cwd, codexHome: codexHome, includeSystemSkills: false)

        XCTAssertEqual(outcome.errors, [])
        XCTAssertEqual(outcome.skills.map(\.name), ["blank-name"])
    }

    func testLoadsOptionalOpenAIMetadataLikeRust() throws {
        let tmp = try SkillLoaderTemporaryDirectory()
        let cwd = tmp.url.appendingPathComponent("repo", isDirectory: true)
        let codexHome = tmp.url.appendingPathComponent("home", isDirectory: true)
        let skillPath = codexHome.appendingPathComponent("skills/metadata-rich/SKILL.md", isDirectory: false)
        let skillDirectory = skillPath.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: cwd, withIntermediateDirectories: true)
        try writeSkill(name: "metadata-rich", description: "metadata skill", to: skillPath)
        try FileManager.default.createDirectory(
            at: skillDirectory.appendingPathComponent("assets", isDirectory: true),
            withIntermediateDirectories: true
        )
        try Data().write(to: skillDirectory.appendingPathComponent("assets/small.png", isDirectory: false))
        try Data().write(to: skillDirectory.appendingPathComponent("assets/large.svg", isDirectory: false))
        try writeOpenAIMetadata(
            """
            interface:
              display_name: "Metadata Skill"
              short_description: "  short   metadata description "
              icon_small: "./assets/small.png"
              icon_large: assets/large.svg
              brand_color: "#3B82F6"
              default_prompt: "  use   this skill "
            dependencies:
              tools:
                - type: mcp
                  value: github
                  description: " GitHub access "
                  transport: stdio
                  command: npx -y server
                  url: https://example.com
            policy:
              allow_implicit_invocation: false
              products:
                - CODEX
                - CHATGPT
            """,
            for: skillPath
        )

        let outcome = SkillLoader.load(cwd: cwd, codexHome: codexHome, includeSystemSkills: false)

        let skill = try XCTUnwrap(outcome.skills.first)
        let expectedSkillDirectory = URL(fileURLWithPath: skill.path).deletingLastPathComponent()
        XCTAssertEqual(outcome.errors, [])
        let interface = try XCTUnwrap(skill.interface)
        XCTAssertEqual(interface.displayName, "Metadata Skill")
        XCTAssertEqual(interface.shortDescription, "short metadata description")
        XCTAssertEqual(
            normalizedTemporaryPath(interface.iconSmall),
            normalizedTemporaryPath(expectedSkillDirectory.appendingPathComponent("assets/small.png").path)
        )
        XCTAssertEqual(
            normalizedTemporaryPath(interface.iconLarge),
            normalizedTemporaryPath(expectedSkillDirectory.appendingPathComponent("assets/large.svg").path)
        )
        XCTAssertEqual(interface.brandColor, "#3B82F6")
        XCTAssertEqual(interface.defaultPrompt, "use this skill")
        XCTAssertEqual(
            skill.dependencies,
            SkillDependencies(tools: [
                SkillToolDependency(
                    type: "mcp",
                    value: "github",
                    description: "GitHub access",
                    transport: "stdio",
                    command: "npx -y server",
                    url: "https://example.com"
                )
            ])
        )
        XCTAssertEqual(skill.policy, SkillPolicy(allowImplicitInvocation: false, products: [.codex, .chatgpt]))
    }

    func testInvalidOpenAIMetadataFieldsFailOpenLikeRust() throws {
        let tmp = try SkillLoaderTemporaryDirectory()
        let cwd = tmp.url.appendingPathComponent("repo", isDirectory: true)
        let codexHome = tmp.url.appendingPathComponent("home", isDirectory: true)
        let skillPath = codexHome.appendingPathComponent("skills/invalid-metadata/SKILL.md", isDirectory: false)
        try FileManager.default.createDirectory(at: cwd, withIntermediateDirectories: true)
        try writeSkill(name: "invalid-metadata", description: "metadata skill", to: skillPath)
        try writeOpenAIMetadata(
            """
            interface:
              icon_small: ../outside.png
              brand_color: blue
            dependencies:
              tools:
                - type: mcp
            policy:
              products:
                - UNKNOWN
            """,
            for: skillPath
        )

        let outcome = SkillLoader.load(cwd: cwd, codexHome: codexHome, includeSystemSkills: false)

        let skill = try XCTUnwrap(outcome.skills.first)
        XCTAssertEqual(outcome.errors, [])
        XCTAssertNil(skill.interface)
        XCTAssertNil(skill.dependencies)
        XCTAssertEqual(skill.policy, SkillPolicy(allowImplicitInvocation: nil, products: []))
    }

    func testProductRestrictedSkillsAreFilteredLikeRustManager() throws {
        let tmp = try SkillLoaderTemporaryDirectory()
        let cwd = tmp.url.appendingPathComponent("repo", isDirectory: true)
        let codexHome = tmp.url.appendingPathComponent("home", isDirectory: true)
        let codexSkill = codexHome.appendingPathComponent("skills/codex-only/SKILL.md", isDirectory: false)
        let chatSkill = codexHome.appendingPathComponent("skills/chat-only/SKILL.md", isDirectory: false)
        try FileManager.default.createDirectory(at: cwd, withIntermediateDirectories: true)
        try writeSkill(name: "codex-only", description: "codex skill", to: codexSkill)
        try writeSkill(name: "chat-only", description: "chat skill", to: chatSkill)
        try writeOpenAIMetadata(
            """
            policy:
              products:
                - codex
            """,
            for: codexSkill
        )
        try writeOpenAIMetadata(
            """
            policy:
              products:
                - CHATGPT
            """,
            for: chatSkill
        )

        let codexOutcome = SkillLoader.load(cwd: cwd, codexHome: codexHome, includeSystemSkills: false)
        let chatOutcome = SkillLoader.load(
            cwd: cwd,
            codexHome: codexHome,
            includeSystemSkills: false,
            restrictionProduct: .chatgpt
        )
        let unrestrictedOutcome = SkillLoader.load(
            cwd: cwd,
            codexHome: codexHome,
            includeSystemSkills: false,
            restrictionProduct: nil
        )

        XCTAssertEqual(codexOutcome.skills.map(\.name), ["codex-only"])
        XCTAssertEqual(codexOutcome.skillRootByPath.keys.sorted(), [codexOutcome.skills[0].path])
        XCTAssertEqual(chatOutcome.skills.map(\.name), ["chat-only"])
        XCTAssertTrue(unrestrictedOutcome.skills.isEmpty)
        XCTAssertTrue(unrestrictedOutcome.skillRoots.isEmpty)
        XCTAssertTrue(unrestrictedOutcome.skillRootByPath.isEmpty)
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

    private func writeRawSkill(frontmatter: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try """
        ---
        \(frontmatter)
        ---

        # Body
        """.write(to: url, atomically: true, encoding: .utf8)
    }

    private func writeOpenAIMetadata(_ contents: String, for skillPath: URL) throws {
        let metadataPath = skillPath
            .deletingLastPathComponent()
            .appendingPathComponent("agents/openai.yaml", isDirectory: false)
        try FileManager.default.createDirectory(at: metadataPath.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: metadataPath, atomically: true, encoding: .utf8)
    }

    private func normalizedTemporaryPath(_ path: String?) -> String? {
        path?.replacingOccurrences(of: "/private/var/", with: "/var/")
    }

    private func writePluginManifest(name: String, skillsPath: String? = nil, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let skillsPath {
            try #"{"name":"\#(name)","skills":"\#(skillsPath)"}"#.write(to: url, atomically: true, encoding: .utf8)
        } else {
            try #"{"name":"\#(name)"}"#.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private func pluginConfigStack(
        codexHome: URL,
        pluginID: String,
        enabled: Bool = true,
        pluginsFeatureEnabled: Bool = true
    ) throws -> ConfigLayerStack {
        try ConfigLayerStack(layers: [
            ConfigLayerEntry(
                name: .user(file: try AbsolutePath(absolutePath: codexHome.appendingPathComponent("config.toml").path)),
                config: .table([
                    "features": .table([
                        "plugins": .bool(pluginsFeatureEnabled)
                    ]),
                    "plugins": .table([
                        pluginID: .table([
                            "enabled": .bool(enabled)
                        ])
                    ])
                ])
            )
        ])
    }

    private func remotePluginFeatureConfigStack(
        codexHome: URL,
        pluginsFeatureEnabled: Bool = true,
        remotePluginEnabled: Bool = true
    ) throws -> ConfigLayerStack {
        try ConfigLayerStack(layers: [
            ConfigLayerEntry(
                name: .user(file: try AbsolutePath(absolutePath: codexHome.appendingPathComponent("config.toml").path)),
                config: .table([
                    "features": .table([
                        "plugins": .bool(pluginsFeatureEnabled),
                        "remote_plugin": .bool(remotePluginEnabled)
                    ])
                ])
            )
        ])
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
