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

    func testSkillMetadataPreservesPluginIDWhenPresent() throws {
        try XCTAssertJSONObjectEqual(
            SkillMetadata(
                name: "sample:search",
                description: "Search sample data",
                path: "/plugins/sample/skills/search/SKILL.md",
                scope: .user,
                pluginID: "sample@test"
            ),
            [
                "name": "sample:search",
                "description": "Search sample data",
                "path": "/plugins/sample/skills/search/SKILL.md",
                "scope": "user",
                "plugin_id": "sample@test"
            ]
        )
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
            ### Available skills
            - demo: Use for demos (file: C:/skills/demo/SKILL.md)
            ### How to use skills
            \(Skills.sectionGuidance)

            """
        )
    }

    func testDefaultSkillMetadataBudgetMatchesRust() {
        XCTAssertEqual(Skills.defaultSkillMetadataBudget(contextWindow: 200_000), .tokens(4_000))
        XCTAssertEqual(Skills.defaultSkillMetadataBudget(contextWindow: 99), .tokens(1))
        XCTAssertEqual(Skills.defaultSkillMetadataBudget(contextWindow: nil), .characters(8_000))
        XCTAssertEqual(Skills.defaultSkillMetadataBudget(contextWindow: -1), .characters(8_000))
    }

    func testRenderAvailableSkillsBodyUsesAliasGuidanceWhenRootLinesExist() {
        let rendered = Skills.renderAvailableSkillsBody(
            skillRootLines: ["- `r0` = `/tmp/skills`"],
            skillLines: ["- demo: desc (file: r0/demo/SKILL.md)"]
        )

        XCTAssertEqual(
            rendered,
            """

            ## Skills
            \(Skills.skillsIntroWithAliases)
            ### Skill roots
            - `r0` = `/tmp/skills`
            ### Available skills
            - demo: desc (file: r0/demo/SKILL.md)
            ### How to use skills
            \(Skills.sectionGuidanceWithAliases)

            """
        )
    }

    func testBudgetedRenderTruncatesDescriptionsEquallyBeforeOmittingSkills() {
        let alpha = skill(name: "alpha-skill", description: "abcdef", path: "/tmp/alpha-skill/SKILL.md", scope: .repo)
        let beta = skill(name: "beta-skill", description: "uvwxyz", path: "/tmp/beta-skill/SKILL.md", scope: .repo)
        let minimumCost = "- alpha-skill: (file: /tmp/alpha-skill/SKILL.md)\n".count
            + "- beta-skill: (file: /tmp/beta-skill/SKILL.md)\n".count

        let rendered = Skills.buildAvailableSkills(
            skills: [beta, alpha],
            budget: .characters(minimumCost + 6)
        )

        XCTAssertEqual(rendered?.report.includedCount, 2)
        XCTAssertEqual(rendered?.report.omittedCount, 0)
        XCTAssertEqual(rendered?.report.truncatedDescriptionChars, 8)
        XCTAssertEqual(rendered?.warningMessage, nil)
        XCTAssertEqual(rendered?.skillLines, [
            "- alpha-skill: ab (file: /tmp/alpha-skill/SKILL.md)",
            "- beta-skill: uv (file: /tmp/beta-skill/SKILL.md)"
        ])
    }

    func testBudgetedRenderWarnsWhenAverageDescriptionTruncationExceedsThreshold() {
        let longDescription = String(repeating: "a", count: 250)
        let long = skill(name: "long-skill", description: longDescription, path: "/tmp/long-skill/SKILL.md", scope: .repo)
        let empty = skill(name: "empty-skill", description: "", path: "/tmp/empty-skill/SKILL.md", scope: .repo)
        let minimumCost = "- empty-skill: (file: /tmp/empty-skill/SKILL.md)\n".count
            + "- long-skill: (file: /tmp/long-skill/SKILL.md)\n".count

        let rendered = Skills.buildAvailableSkills(
            skills: [long, empty],
            budget: .characters(minimumCost + 49)
        )

        XCTAssertEqual(rendered?.report.totalCount, 2)
        XCTAssertEqual(rendered?.report.includedCount, 2)
        XCTAssertEqual(rendered?.report.omittedCount, 0)
        XCTAssertEqual(rendered?.report.truncatedDescriptionChars, 202)
        XCTAssertEqual(rendered?.report.truncatedDescriptionCount, 1)
        XCTAssertEqual(rendered?.warningMessage, Skills.skillDescriptionTruncatedWarning)
    }

    func testBudgetedRenderTokenWarningMentionsTwoPercent() {
        let long = skill(name: "long-skill", description: String(repeating: "a", count: 1_000), path: "/tmp/long-skill/SKILL.md", scope: .repo)

        let rendered = Skills.buildAvailableSkills(
            skills: [long],
            budget: .tokens(13)
        )

        XCTAssertEqual(rendered?.warningMessage, Skills.skillDescriptionTruncatedWarningWithPercent)
    }

    func testBudgetedRenderPreservesPromptPriorityWhenMinimumLinesExceedBudget() {
        let system = skill(name: "system-skill", path: "/tmp/system-skill/SKILL.md", scope: .system)
        let admin = skill(name: "admin-skill", path: "/tmp/admin-skill/SKILL.md", scope: .admin)
        let repo = skill(name: "repo-skill", path: "/tmp/repo-skill/SKILL.md", scope: .repo)
        let user = skill(name: "user-skill", path: "/tmp/user-skill/SKILL.md", scope: .user)
        let budget = "- system-skill: (file: /tmp/system-skill/SKILL.md)\n".count
            + "- admin-skill: (file: /tmp/admin-skill/SKILL.md)\n".count

        let rendered = Skills.buildAvailableSkills(
            skills: [system, user, repo, admin],
            budget: .characters(budget)
        )

        XCTAssertEqual(rendered?.report.includedCount, 2)
        XCTAssertEqual(rendered?.report.omittedCount, 2)
        XCTAssertEqual(
            rendered?.warningMessage,
            "Exceeded skills context budget. All skill descriptions were removed and 2 additional skills were not included in the model-visible skills list."
        )
        XCTAssertEqual(rendered?.skillLines, [
            "- system-skill: (file: /tmp/system-skill/SKILL.md)",
            "- admin-skill: (file: /tmp/admin-skill/SKILL.md)"
        ])
    }

    func testOutcomeRenderingUsesAliasesWhenTheyAllowMoreSkillsToFit() throws {
        let root = "/Users/example/" + String(repeating: "shared-prefix/", count: 8) + ".codex/plugins/cache/openai-curated/example-plugin/0123456789abcdef/skills"
        let skills = (0..<12).map { index in
            skill(
                name: "skill-\(index)",
                description: "",
                path: "\(root)/skill-\(index)/SKILL.md",
                scope: .user
            )
        }
        let outcome = outcome(skills: skills, roots: [root])
        let budget = try budgetWhereAliasedRenderSelected(outcome, requireAllIncluded: true)

        let absolute = Skills.buildAvailableSkills(skills: skills, budget: .characters(budget))
        let rendered = Skills.buildAvailableSkills(outcome: outcome, budget: .characters(budget))

        XCTAssertLessThan(absolute?.report.includedCount ?? 0, skills.count)
        XCTAssertEqual(rendered?.report.includedCount, skills.count)
        XCTAssertEqual(rendered?.report.omittedCount, 0)
        XCTAssertEqual(rendered?.skillRootLines, ["- `r0` = `\(root)`"])
        XCTAssertTrue(rendered?.skillLines.contains("- skill-0: (file: r0/skill-0/SKILL.md)") == true)
    }

    func testOutcomeRenderingUsesMarketplaceRootForSingleSkillPluginVersions() throws {
        let marketplaceRoot = "/Users/example/" + String(repeating: "marketplace-prefix/", count: 8) + ".codex/plugins/cache/openai-curated"
        let searchRoot = "\(marketplaceRoot)/search/1111111111111111/skills"
        let githubRoot = "\(marketplaceRoot)/github/2222222222222222/skills"
        let skills = [
            skill(name: "search", description: "", path: "\(searchRoot)/search/SKILL.md", scope: .user),
            skill(name: "gh-fix-ci", description: "", path: "\(githubRoot)/gh-fix-ci/SKILL.md", scope: .user)
        ]
        let outcome = outcome(skills: skills, roots: [searchRoot, githubRoot])
        let budget = try budgetWhereAliasedRenderSelected(outcome, requireAllIncluded: true)

        let rendered = Skills.buildAvailableSkills(outcome: outcome, budget: .characters(budget))

        XCTAssertEqual(rendered?.report.includedCount, skills.count)
        XCTAssertEqual(rendered?.skillRootLines, ["- `r0` = `\(marketplaceRoot)`"])
        XCTAssertEqual(rendered?.skillLines, [
            "- gh-fix-ci: (file: r0/github/2222222222222222/skills/gh-fix-ci/SKILL.md)",
            "- search: (file: r0/search/1111111111111111/skills/search/SKILL.md)"
        ])
    }

    func testOutcomeRenderingUsesSkillRootForMultipleSkillsInOnePluginVersion() throws {
        let root = "/Users/example/" + String(repeating: "plugin-prefix/", count: 8) + ".codex/plugins/cache/openai-curated/github/2222222222222222/skills"
        let skills = [
            skill(name: "gh-address-comments", description: "", path: "\(root)/gh-address-comments/SKILL.md", scope: .user),
            skill(name: "gh-fix-ci", description: "", path: "\(root)/gh-fix-ci/SKILL.md", scope: .user)
        ]
        let outcome = outcome(skills: skills, roots: [root])
        let budget = try budgetWhereAliasedRenderSelected(outcome, requireAllIncluded: true)

        let rendered = Skills.buildAvailableSkills(outcome: outcome, budget: .characters(budget))

        XCTAssertEqual(rendered?.report.includedCount, skills.count)
        XCTAssertEqual(rendered?.skillRootLines, ["- `r0` = `\(root)`"])
        XCTAssertEqual(rendered?.skillLines, [
            "- gh-address-comments: (file: r0/gh-address-comments/SKILL.md)",
            "- gh-fix-ci: (file: r0/gh-fix-ci/SKILL.md)"
        ])
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

    private func skill(
        name: String,
        description: String? = nil,
        path: String,
        scope: SkillScope = .user
    ) -> SkillMetadata {
        SkillMetadata(
            name: name,
            description: description ?? "\(name) description",
            path: path,
            scope: scope
        )
    }

    private func outcome(skills: [SkillMetadata], roots: [String]) -> SkillLoadOutcome {
        let rootByPath = Dictionary(uniqueKeysWithValues: skills.map { skill in
            let root = roots.first { skill.path.hasPrefix($0 + "/") }!
            return (skill.path, root)
        })
        return SkillLoadOutcome(skills: skills, skillRoots: roots, skillRootByPath: rootByPath)
    }

    private func budgetWhereAliasedRenderSelected(
        _ outcome: SkillLoadOutcome,
        requireAllIncluded: Bool = false
    ) throws -> Int {
        for budget in 1...12_000 {
            let absolute = Skills.buildAvailableSkills(skills: outcome.skills, budget: .characters(budget))
            let aliased = Skills.buildAvailableSkills(outcome: outcome, budget: .characters(budget))
            guard aliased?.skillRootLines.isEmpty == false else {
                continue
            }
            if requireAllIncluded,
               aliased?.report.includedCount == outcome.skills.count,
               (absolute?.report.includedCount ?? 0) < outcome.skills.count {
                return budget
            }
            if !requireAllIncluded {
                return budget
            }
        }
        XCTFail("could not find a budget where aliases are selected")
        throw SkillTestFailure()
    }
}

private struct SkillReadError: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}

private struct SkillTestFailure: Error {}
