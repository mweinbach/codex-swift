import XCTest
@testable import CodexCore

final class SkillsTests: XCTestCase {
    func testSkillScopeWireValues() throws {
        XCTAssertEqual(try JSONEncoder().encode(SkillScope.user), Data(#""user""#.utf8))
        XCTAssertEqual(try JSONEncoder().encode(SkillScope.repo), Data(#""repo""#.utf8))
        XCTAssertEqual(try JSONEncoder().encode(SkillScope.system), Data(#""system""#.utf8))
        XCTAssertEqual(try JSONEncoder().encode(SkillScope.admin), Data(#""admin""#.utf8))
    }

    func testSkillMetadataOmitsMissingShortDescription() throws {
        try XCTAssertJSONObjectEqual(
            SkillMetadata(
                name: "demo",
                description: "Use for demos",
                path: "/skills/demo/SKILL.md",
                scope: .user
            ),
            [
                "name": "demo",
                "description": "Use for demos",
                "path": "/skills/demo/SKILL.md",
                "scope": "user"
            ]
        )
    }

    func testSkillMetadataDecodesMissingShortDescriptionAsNil() throws {
        let skill = try JSONDecoder().decode(SkillMetadata.self, from: Data("""
        {
          "name": "repo-skill",
          "description": "Repo scoped",
          "path": "/repo/.codex/skills/repo-skill/SKILL.md",
          "scope": "repo"
        }
        """.utf8))

        XCTAssertEqual(skill.shortDescription, nil)
        XCTAssertEqual(skill.scope, .repo)
    }

    func testListSkillsResponseWireShape() throws {
        try XCTAssertJSONObjectEqual(
            ListSkillsResponseEvent(skills: [
                SkillsListEntry(
                    cwd: "/repo",
                    skills: [
                        SkillMetadata(
                            name: "demo",
                            description: "Demo skill",
                            shortDescription: "Demo",
                            path: "/skills/demo/SKILL.md",
                            scope: .system
                        )
                    ],
                    errors: [
                        SkillErrorInfo(path: "/bad/SKILL.md", message: "missing description")
                    ]
                )
            ]),
            [
                "skills": [[
                    "cwd": "/repo",
                    "skills": [[
                        "name": "demo",
                        "description": "Demo skill",
                        "short_description": "Demo",
                        "path": "/skills/demo/SKILL.md",
                        "scope": "system"
                    ]],
                    "errors": [[
                        "path": "/bad/SKILL.md",
                        "message": "missing description"
                    ]]
                ]]
            ]
        )
    }

    func testRenderSkillsSectionReturnsNilForEmptySkills() {
        XCTAssertNil(Skills.renderSkillsSection([]))
    }

    func testRenderSkillsSectionMatchesRustFormatAndNormalizesPathSeparators() {
        let rendered = Skills.renderSkillsSection([
            SkillMetadata(
                name: "demo",
                description: "Use for demos",
                path: #"C:\skills\demo\SKILL.md"#,
                scope: .user
            )
        ])

        XCTAssertEqual(
            rendered,
            """
            ## Skills
            \(Skills.sectionIntro)
            - demo: Use for demos (file: C:/skills/demo/SKILL.md)
            \(Skills.sectionGuidance)
            """
        )
    }

    func testCollectExplicitSkillMentionsSelectsKnownSkillOnceInInputOrder() {
        let first = skill(name: "first", path: "/skills/first/SKILL.md")
        let second = skill(name: "second", path: "/skills/second/SKILL.md")

        let mentions = Skills.collectExplicitSkillMentions(
            inputs: [
                .text("hello"),
                .skill(name: "first", path: first.path),
                .skill(name: "first", path: first.path),
                .skill(name: "second", path: second.path)
            ],
            skills: [second, first]
        )

        XCTAssertEqual(mentions, [first, second])
    }

    func testCollectExplicitSkillMentionsFromPlainTextPreservesSkillOrderLikeRust() {
        let alpha = skill(name: "alpha-skill", path: "/skills/alpha/SKILL.md")
        let beta = skill(name: "beta-skill", path: "/skills/beta/SKILL.md")

        let mentions = Skills.collectExplicitSkillMentions(
            inputs: [.text("first $alpha-skill then $beta-skill")],
            skills: [beta, alpha]
        )

        XCTAssertEqual(mentions, [beta, alpha])
    }

    func testCollectExplicitSkillMentionsPrioritizesStructuredInputsLikeRust() {
        let alpha = skill(name: "alpha-skill", path: "/skills/alpha/SKILL.md")
        let beta = skill(name: "beta-skill", path: "/skills/beta/SKILL.md")

        let mentions = Skills.collectExplicitSkillMentions(
            inputs: [
                .text("please run $alpha-skill"),
                .skill(name: "beta-skill", path: beta.path)
            ],
            skills: [alpha, beta]
        )

        XCTAssertEqual(mentions, [beta, alpha])
    }

    func testCollectExplicitSkillMentionsAllowsLaterStructuredPathMatchLikeRust() {
        let matched = skill(name: "demo", path: "/skills/demo/SKILL.md")

        let mentions = Skills.collectExplicitSkillMentions(
            inputs: [
                .skill(name: "demo", path: "/wrong/SKILL.md"),
                .skill(name: "demo", path: matched.path)
            ],
            skills: [matched]
        )

        XCTAssertEqual(mentions, [matched])
    }

    func testCollectExplicitSkillMentionsBlocksPlainFallbackForInvalidStructuredInputLikeRust() {
        let alpha = skill(name: "alpha-skill", path: "/skills/alpha/SKILL.md")

        let mentions = Skills.collectExplicitSkillMentions(
            inputs: [
                .text("please run $alpha-skill"),
                .skill(name: "alpha-skill", path: "/skills/missing/SKILL.md")
            ],
            skills: [alpha]
        )

        XCTAssertEqual(mentions, [])
    }

    func testCollectExplicitSkillMentionsUsesLinkedPathForAmbiguousNamesLikeRust() {
        let alpha = skill(name: "demo-skill", path: "/skills/alpha/SKILL.md")
        let beta = skill(name: "demo-skill", path: "/skills/beta/SKILL.md")
        let windows = skill(name: "demo-skill", path: #"C:\skills\demo\SKILL.md"#)

        let mentions = Skills.collectExplicitSkillMentions(
            inputs: [
                .text(#"use [$demo-skill]( /skills/beta/SKILL.md ) and [$demo-skill](C:\skills\demo\SKILL.md)"#)
            ],
            skills: [alpha, beta, windows]
        )

        XCTAssertEqual(mentions, [beta, windows])
    }

    func testCollectExplicitSkillMentionsSkipsAmbiguousPlainNamesAndConnectorCollisionsLikeRust() {
        let first = skill(name: "demo-skill", path: "/skills/one/SKILL.md")
        let second = skill(name: "demo-skill", path: "/skills/two/SKILL.md")
        let connector = skill(name: "drive", path: "/skills/drive/SKILL.md")

        XCTAssertEqual(
            Skills.collectExplicitSkillMentions(
                inputs: [.text("use $demo-skill")],
                skills: [first, second]
            ),
            []
        )
        XCTAssertEqual(
            Skills.collectExplicitSkillMentions(
                inputs: [.text("use $drive")],
                skills: [connector],
                connectorSlugCounts: ["drive": 1]
            ),
            []
        )
    }

    func testCollectExplicitSkillMentionsSkipsAppPluginAndCommonEnvironmentMentionsLikeRust() {
        let pathSkill = skill(name: "path", path: "/skills/path/SKILL.md")
        let plugin = skill(name: "sample", path: "/skills/sample/SKILL.md")
        let app = skill(name: "drive", path: "/skills/drive/SKILL.md")

        let mentions = Skills.collectExplicitSkillMentions(
            inputs: [.text("use $PATH and [$sample](plugin://sample@test) and [$drive](app://drive)")],
            skills: [pathSkill, plugin, app]
        )

        XCTAssertEqual(mentions, [])
    }

    func testBuildSkillInjectionsReturnsDefaultForNoInputsOrMissingOutcome() {
        let readFile: (String) throws -> String = { _ in
            XCTFail("readFile should not be called")
            return ""
        }

        XCTAssertEqual(Skills.buildSkillInjections(inputs: [], skills: SkillLoadOutcome(), readFile: readFile), SkillInjections())
        XCTAssertEqual(Skills.buildSkillInjections(inputs: [.skill(name: "demo", path: "/demo")], skills: nil, readFile: readFile), SkillInjections())
    }

    func testBuildSkillInjectionsReadsMentionedSkillsAndWarnsOnFailures() {
        let ok = skill(name: "ok", path: "/skills/ok/SKILL.md")
        let missing = skill(name: "missing", path: "/skills/missing/SKILL.md")

        let injections = Skills.buildSkillInjections(
            inputs: [
                .skill(name: "ok", path: ok.path),
                .skill(name: "missing", path: missing.path)
            ],
            skills: SkillLoadOutcome(skills: [ok, missing])
        ) { path in
            if path == ok.path {
                return "ok body"
            }
            throw SkillReadError("no file")
        }

        XCTAssertEqual(injections.items, [
            SkillInstructions(name: "ok", path: ok.path, contents: "ok body").asResponseItem()
        ])
        XCTAssertEqual(injections.warnings, [
            "Failed to load skill missing at /skills/missing/SKILL.md: no file"
        ])
    }

    private func skill(name: String, path: String) -> SkillMetadata {
        SkillMetadata(
            name: name,
            description: "\(name) description",
            path: path,
            scope: .user
        )
    }
}

private struct SkillReadError: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}
