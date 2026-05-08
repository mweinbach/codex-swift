import CodexCore
import XCTest

final class ConfigLayerLoaderTests: XCTestCase {
    func testManagedConfigDefaultPathHonorsEnvironmentOverride() throws {
        let dir = try ConfigLayerTemporaryDirectory()
        let managedPath = dir.url.appendingPathComponent("managed_config.toml")

        XCTAssertEqual(
            CodexConfigLayerLoader.managedConfigDefaultPath(
                codexHome: dir.url,
                environment: ["CODEX_MANAGED_CONFIG_PATH": managedPath.path]
            ).path,
            managedPath.path
        )
    }

    func testReadConfigReturnsNilForMissingFileAndParsesNestedTables() throws {
        let dir = try ConfigLayerTemporaryDirectory()
        let missing = dir.url.appendingPathComponent("missing.toml")
        XCTAssertNil(try CodexConfigLayerLoader.readConfig(from: missing))

        let file = dir.url.appendingPathComponent("config.toml")
        try """
        foo = 1

        [nested]
        value = "base"
        flag = true
        """.write(to: file, atomically: true, encoding: .utf8)

        XCTAssertEqual(
            try CodexConfigLayerLoader.readConfig(from: file),
            .table([
                "foo": .integer(1),
                "nested": .table([
                    "value": .string("base"),
                    "flag": .bool(true)
                ])
            ])
        )
    }

    func testReadConfigResolvesRelativePathFieldsAndPreservesUnknownFieldsLikeRust() throws {
        let dir = try ConfigLayerTemporaryDirectory()
        let file = dir.url.appendingPathComponent("config.toml")
        try """
        experimental_instructions_file = "./some_file.md"
        experimental_compact_prompt_file = "../compact.md"
        model = "gpt-1000"
        foo = "xyzzy"

        [profiles.work]
        experimental_instructions_file = "profile.md"
        """.write(to: file, atomically: true, encoding: .utf8)

        XCTAssertEqual(
            try CodexConfigLayerLoader.readConfig(from: file),
            .table([
                "experimental_instructions_file": .string(dir.url.appendingPathComponent("some_file.md").path),
                "experimental_compact_prompt_file": .string(dir.url.deletingLastPathComponent().appendingPathComponent("compact.md").path),
                "model": .string("gpt-1000"),
                "foo": .string("xyzzy"),
                "profiles": .table([
                    "work": .table([
                        "experimental_instructions_file": .string(dir.url.appendingPathComponent("profile.md").path)
                    ])
                ])
            ])
        )
    }

    func testManagedPreferencesBase64DecodesTomlTable() throws {
        let payload = """
        [nested]
        value = "managed"
        enabled = false
        """
        let encoded = Data(payload.utf8).base64EncodedString()

        XCTAssertEqual(
            try CodexConfigLayerLoader.parseManagedPreferencesBase64(encoded),
            .table([
                "nested": .table([
                    "value": .string("managed"),
                    "enabled": .bool(false)
                ])
            ])
        )
        XCTAssertNil(try CodexConfigLayerLoader.loadManagedAdminConfigLayer(overrideBase64: "   "))
    }

    func testLayerStackMergesManagedConfigAboveCLIAndUser() throws {
        let dir = try ConfigLayerTemporaryDirectory()
        let home = dir.url.appendingPathComponent("home", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try """
        foo = 1

        [nested]
        value = "user"
        """.write(to: home.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        let managedPath = dir.url.appendingPathComponent("managed_config.toml")
        try """
        foo = 2

        [nested]
        value = "managed_config"
        extra = true
        """.write(to: managedPath, atomically: true, encoding: .utf8)

        let stack = try CodexConfigLayerLoader.loadConfigLayerStack(
            codexHome: home,
            cliOverrides: CliConfigOverrides(rawOverrides: ["nested.value=\"cli\""]),
            overrides: ConfigLayerLoaderOverrides(managedConfigPath: managedPath),
            systemConfigFile: nil
        )

        XCTAssertEqual(
            stack.effectiveConfig(),
            .table([
                "foo": .integer(2),
                "nested": .table([
                    "value": .string("managed_config"),
                    "extra": .bool(true)
                ])
            ])
        )
        XCTAssertEqual(
            stack.layersHighToLow().map(\.name),
            [
                .legacyManagedConfigTomlFromFile(file: try AbsolutePath(absolutePath: managedPath.path)),
                .sessionFlags,
                .user(file: try AbsolutePath(absolutePath: home.appendingPathComponent("config.toml").path))
            ]
        )
    }

    func testManagedPreferencesTakeHighestPrecedence() throws {
        let dir = try ConfigLayerTemporaryDirectory()
        let home = dir.url.appendingPathComponent("home", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try """
        [nested]
        value = "user"
        """.write(
            to: home.appendingPathComponent("config.toml"),
            atomically: true,
            encoding: .utf8
        )

        let managedPath = dir.url.appendingPathComponent("managed_config.toml")
        try """
        [nested]
        value = "managed_config"
        flag = true
        """.write(
            to: managedPath,
            atomically: true,
            encoding: .utf8
        )
        let managedPreferences = Data("""
        [nested]
        value = "mdm"
        flag = false
        """.utf8)
            .base64EncodedString()

        let stack = try CodexConfigLayerLoader.loadConfigLayerStack(
            codexHome: home,
            overrides: ConfigLayerLoaderOverrides(
                managedConfigPath: managedPath,
                managedPreferencesBase64: managedPreferences
            ),
            systemConfigFile: nil
        )

        XCTAssertEqual(
            stack.effectiveConfig(),
            .table([
                "nested": .table([
                    "value": .string("mdm"),
                    "flag": .bool(false)
                ])
            ])
        )
        XCTAssertEqual(stack.layersHighToLow().first?.name, .legacyManagedConfigTomlFromMdm)
    }

    func testLayerStackReturnsEmptyUserLayerWhenAllFilesMissing() throws {
        let dir = try ConfigLayerTemporaryDirectory()
        let home = dir.url.appendingPathComponent("home", isDirectory: true)
        let cwd = dir.url.appendingPathComponent("workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: cwd, withIntermediateDirectories: true)

        let stack = try CodexConfigLayerLoader.loadConfigLayerStack(
            codexHome: home,
            cwd: cwd,
            overrides: ConfigLayerLoaderOverrides(
                managedConfigPath: dir.url.appendingPathComponent("missing-managed.toml")
            ),
            systemConfigFile: nil
        )

        XCTAssertEqual(stack.effectiveConfig(), .table([:]))
        XCTAssertEqual(stack.getUserLayer()?.config, .table([:]))
        XCTAssertEqual(
            stack.getUserLayer()?.name,
            .user(file: try AbsolutePath(absolutePath: home.appendingPathComponent("config.toml").path))
        )
        XCTAssertTrue(stack.layersHighToLow().allSatisfy { layer in
            if case .project = layer.name {
                return false
            }
            return true
        })
    }

    func testProjectLayerAddedWhenDotCodexExistsWithoutConfig() throws {
        let dir = try ConfigLayerTemporaryDirectory()
        let home = dir.url.appendingPathComponent("home", isDirectory: true)
        let project = dir.url.appendingPathComponent("project", isDirectory: true)
        let nested = project.appendingPathComponent("child", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: project.appendingPathComponent(".codex"), withIntermediateDirectories: true)
        try "gitdir: here\n".write(to: project.appendingPathComponent(".git"), atomically: true, encoding: .utf8)

        let stack = try CodexConfigLayerLoader.loadConfigLayerStack(
            codexHome: home,
            cwd: nested,
            overrides: ConfigLayerLoaderOverrides(
                managedConfigPath: dir.url.appendingPathComponent("missing-managed.toml")
            ),
            systemConfigFile: nil
        )

        let projectLayers = stack.layersHighToLow().filter {
            if case .project = $0.name {
                return true
            }
            return false
        }
        XCTAssertEqual(projectLayers.count, 1)
        XCTAssertEqual(projectLayers.first?.config, .table([:]))
        XCTAssertEqual(
            projectLayers.first?.name,
            .project(dotCodexFolder: try AbsolutePath(absolutePath: project.appendingPathComponent(".codex").path))
        )
    }

    func testProjectLayersPreferClosestCwd() throws {
        let dir = try ConfigLayerTemporaryDirectory()
        let home = dir.url.appendingPathComponent("home", isDirectory: true)
        let project = dir.url.appendingPathComponent("project", isDirectory: true)
        let nested = project.appendingPathComponent("child", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: project.appendingPathComponent(".codex"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: nested.appendingPathComponent(".codex"), withIntermediateDirectories: true)
        try "gitdir: here\n".write(to: project.appendingPathComponent(".git"), atomically: true, encoding: .utf8)
        try #"foo = "root""#.write(
            to: project.appendingPathComponent(".codex/config.toml"),
            atomically: true,
            encoding: .utf8
        )
        try #"foo = "child""#.write(
            to: nested.appendingPathComponent(".codex/config.toml"),
            atomically: true,
            encoding: .utf8
        )

        let stack = try CodexConfigLayerLoader.loadConfigLayerStack(
            codexHome: home,
            cwd: nested,
            overrides: ConfigLayerLoaderOverrides(
                managedConfigPath: dir.url.appendingPathComponent("missing-managed.toml")
            ),
            systemConfigFile: nil
        )

        XCTAssertEqual(stack.effectiveConfig(), .table(["foo": .string("child")]))
        let projectLayerNames = stack.layersHighToLow().compactMap { layer -> AbsolutePath? in
            if case let .project(dotCodexFolder) = layer.name {
                return dotCodexFolder
            }
            return nil
        }
        XCTAssertEqual(projectLayerNames, [
            try AbsolutePath(absolutePath: nested.appendingPathComponent(".codex").path),
            try AbsolutePath(absolutePath: project.appendingPathComponent(".codex").path)
        ])
    }

    func testProjectRootMarkersSupportAlternateMarkersLikeRust() throws {
        let dir = try ConfigLayerTemporaryDirectory()
        let home = dir.url.appendingPathComponent("home", isDirectory: true)
        let project = dir.url.appendingPathComponent("project", isDirectory: true)
        let nested = project.appendingPathComponent("child", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: project.appendingPathComponent(".codex"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: nested.appendingPathComponent(".codex"), withIntermediateDirectories: true)
        try "hg\n".write(to: project.appendingPathComponent(".hg"), atomically: true, encoding: .utf8)
        try """
        project_root_markers = [".hg"]
        """.write(
            to: home.appendingPathComponent("config.toml"),
            atomically: true,
            encoding: .utf8
        )
        try #"foo = "root""#.write(
            to: project.appendingPathComponent(".codex/config.toml"),
            atomically: true,
            encoding: .utf8
        )
        try #"foo = "child""#.write(
            to: nested.appendingPathComponent(".codex/config.toml"),
            atomically: true,
            encoding: .utf8
        )

        let stack = try CodexConfigLayerLoader.loadConfigLayerStack(
            codexHome: home,
            cwd: nested,
            overrides: ConfigLayerLoaderOverrides(
                managedConfigPath: dir.url.appendingPathComponent("missing-managed.toml")
            ),
            systemConfigFile: nil
        )

        XCTAssertEqual(stack.effectiveConfig(), .table([
            "project_root_markers": .array([.string(".hg")]),
            "foo": .string("child")
        ]))
        let projectLayerNames = stack.layersHighToLow().compactMap { layer -> AbsolutePath? in
            if case let .project(dotCodexFolder) = layer.name {
                return dotCodexFolder
            }
            return nil
        }
        XCTAssertEqual(projectLayerNames, [
            try AbsolutePath(absolutePath: nested.appendingPathComponent(".codex").path),
            try AbsolutePath(absolutePath: project.appendingPathComponent(".codex").path)
        ])
    }
}

private final class ConfigLayerTemporaryDirectory {
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
