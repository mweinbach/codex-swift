import CodexCore
import XCTest

final class ConfigLayerStackTests: XCTestCase {
    func testConfigLayerSourcePrecedenceAndWireShape() throws {
        XCTAssertLessThan(ConfigLayerSource.mdm(domain: "com.openai.codex", key: "config"), .system(file: try path("/etc/codex/config.toml")))
        XCTAssertLessThan(ConfigLayerSource.system(file: try path("/etc/codex/config.toml")), .user(file: try path("/Users/me/.codex/config.toml")))
        XCTAssertLessThan(ConfigLayerSource.user(file: try path("/Users/me/.codex/config.toml")), .project(dotCodexFolder: try path("/repo/.codex")))
        XCTAssertLessThan(ConfigLayerSource.project(dotCodexFolder: try path("/repo/.codex")), .sessionFlags)
        XCTAssertLessThan(ConfigLayerSource.sessionFlags, .legacyManagedConfigTomlFromFile(file: try path("/etc/codex/managed_config.toml")))
        XCTAssertLessThan(ConfigLayerSource.legacyManagedConfigTomlFromFile(file: try path("/etc/codex/managed_config.toml")), .legacyManagedConfigTomlFromMdm)

        try XCTAssertJSONObjectEqual(
            ConfigLayerSource.project(dotCodexFolder: try path("/repo/.codex")),
            [
                "type": "project",
                "dotCodexFolder": "/repo/.codex"
            ]
        )
        try XCTAssertJSONObjectEqual(
            ConfigLayerSource.sessionFlags,
            [
                "type": "sessionFlags"
            ]
        )

        let decoded = try JSONDecoder().decode(
            ConfigLayerSource.self,
            from: Data(#"{"type":"legacyManagedConfigTomlFromFile","file":"/etc/codex/managed_config.toml"}"#.utf8)
        )
        XCTAssertEqual(decoded, .legacyManagedConfigTomlFromFile(file: try path("/etc/codex/managed_config.toml")))
    }

    func testConfigLayerEntryVersionMetadataAndWireShape() throws {
        let entry = ConfigLayerEntry(
            name: .user(file: try path("/Users/me/.codex/config.toml")),
            config: .table([
                "b": .integer(2),
                "a": .bool(true)
            ])
        )

        XCTAssertEqual(entry.version, "sha256:e8837c10728b357106304c71610ad4e1a933b6d5b9d0b3950edaefa075aaa817")
        XCTAssertEqual(ConfigFingerprint.version(for: .table([:])), "sha256:44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a")
        XCTAssertEqual(
            entry.metadata(),
            ConfigLayerMetadata(
                name: .user(file: try path("/Users/me/.codex/config.toml")),
                version: entry.version
            )
        )
        try XCTAssertJSONObjectEqual(
            entry.asLayer(),
            [
                "name": [
                    "type": "user",
                    "file": "/Users/me/.codex/config.toml"
                ],
                "version": entry.version,
                "config": [
                    "a": true,
                    "b": 2
                ]
            ]
        )
    }

    func testConfigFolderMatchesRustLayerRules() throws {
        XCTAssertEqual(
            ConfigLayerEntry(name: .system(file: try path("/etc/codex/config.toml")), config: .table([:])).configFolder(),
            try path("/etc/codex")
        )
        XCTAssertEqual(
            ConfigLayerEntry(name: .user(file: try path("/Users/me/.codex/config.toml")), config: .table([:])).configFolder(),
            try path("/Users/me/.codex")
        )
        XCTAssertEqual(
            ConfigLayerEntry(name: .project(dotCodexFolder: try path("/repo/.codex")), config: .table([:])).configFolder(),
            try path("/repo/.codex")
        )
        XCTAssertNil(ConfigLayerEntry(name: .sessionFlags, config: .table([:])).configFolder())
        XCTAssertNil(ConfigLayerEntry(name: .legacyManagedConfigTomlFromFile(file: try path("/etc/codex/managed_config.toml")), config: .table([:])).configFolder())
    }

    func testEffectiveConfigMergesLayersAndTracksOrigins() throws {
        let system = ConfigLayerEntry(
            name: .system(file: try path("/etc/codex/config.toml")),
            config: .table([
                "plain": .string("base"),
                "nested": .table([
                    "child": .string("base"),
                    "keep": .bool(true)
                ]),
                "array": .array([.string("base")])
            ])
        )
        let user = ConfigLayerEntry(
            name: .user(file: try path("/Users/me/.codex/config.toml")),
            config: .table([
                "nested": .table([
                    "child": .string("user")
                ]),
                "array": .array([.string("user"), .integer(2)])
            ])
        )
        let stack = try ConfigLayerStack(layers: [system, user])

        XCTAssertEqual(
            stack.effectiveConfig(),
            .table([
                "plain": .string("base"),
                "nested": .table([
                    "child": .string("user"),
                    "keep": .bool(true)
                ]),
                "array": .array([.string("user"), .integer(2)])
            ])
        )

        let origins = stack.origins()
        XCTAssertEqual(origins["plain"], system.metadata())
        XCTAssertEqual(origins["nested.keep"], system.metadata())
        XCTAssertEqual(origins["nested.child"], user.metadata())
        XCTAssertEqual(origins["array.0"], user.metadata())
        XCTAssertEqual(origins["array.1"], user.metadata())
    }

    func testWithUserConfigInsertsOrReplacesUserLayerByPrecedence() throws {
        let system = ConfigLayerEntry(name: .system(file: try path("/etc/codex/config.toml")), config: .table([:]))
        let project = ConfigLayerEntry(name: .project(dotCodexFolder: try path("/repo/.codex")), config: .table([:]))
        let flags = ConfigLayerEntry(name: .sessionFlags, config: .table(["flag": .bool(true)]))
        let stack = try ConfigLayerStack(layers: [system, project, flags])

        let userPath = try path("/Users/me/.codex/config.toml")
        let withUser = stack.withUserConfig(configToml: userPath, userConfig: .table(["user": .string("first")]))
        XCTAssertEqual(
            withUser.getLayers(ordering: .lowestPrecedenceFirst).map(\.name),
            [
                system.name,
                .user(file: userPath),
                project.name,
                flags.name
            ]
        )
        XCTAssertEqual(withUser.getUserLayer()?.config, .table(["user": .string("first")]))

        let replaced = withUser.withUserConfig(configToml: userPath, userConfig: .table(["user": .string("second")]))
        XCTAssertEqual(replaced.layers.count, withUser.layers.count)
        XCTAssertEqual(replaced.getUserLayer()?.config, .table(["user": .string("second")]))
        XCTAssertEqual(replaced.layersHighToLow().map(\.name), [flags.name, project.name, .user(file: userPath), system.name])
    }

    func testRejectsInvalidLayerOrdering() throws {
        let system = ConfigLayerEntry(name: .system(file: try path("/etc/codex/config.toml")), config: .table([:]))
        let user = ConfigLayerEntry(name: .user(file: try path("/Users/me/.codex/config.toml")), config: .table([:]))

        XCTAssertThrowsError(try ConfigLayerStack(layers: [user, system])) { error in
            XCTAssertEqual((error as? ConfigLayerError)?.description, "config layers are not in correct precedence order")
        }
        XCTAssertThrowsError(try ConfigLayerStack(layers: [system, user, user])) { error in
            XCTAssertEqual((error as? ConfigLayerError)?.description, "multiple user config layers found")
        }
    }

    func testRejectsProjectLayersNotOrderedFromRootToCwd() throws {
        let child = ConfigLayerEntry(name: .project(dotCodexFolder: try path("/repo/child/.codex")), config: .table([:]))
        let root = ConfigLayerEntry(name: .project(dotCodexFolder: try path("/repo/.codex")), config: .table([:]))

        XCTAssertNoThrow(try ConfigLayerStack(layers: [root, child]))
        XCTAssertThrowsError(try ConfigLayerStack(layers: [child, root])) { error in
            XCTAssertEqual((error as? ConfigLayerError)?.description, "project layers are not ordered from root to cwd")
        }
        XCTAssertThrowsError(try ConfigLayerStack(layers: [root, root])) { error in
            XCTAssertEqual((error as? ConfigLayerError)?.description, "project layers are not ordered from root to cwd")
        }
    }

    private func path(_ value: String) throws -> AbsolutePath {
        try AbsolutePath(absolutePath: value)
    }
}
