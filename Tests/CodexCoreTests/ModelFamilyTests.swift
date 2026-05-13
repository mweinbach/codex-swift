import XCTest
@testable import CodexCore

final class ModelFamilyTests: XCTestCase {
    func testFindFamilyForModelMatchesRustBranchMetadata() {
        let o3 = ModelsManager.findFamilyForModel("o3-mini")
        XCTAssertEqual(o3.family, "o3")
        XCTAssertTrue(o3.supportsReasoningSummaries)
        XCTAssertTrue(o3.needsSpecialApplyPatchInstructions)
        XCTAssertEqual(o3.contextWindow, 200_000)
        XCTAssertEqual(o3.autoCompactTokenLimit(), 180_000)

        let codexMini = ModelsManager.findFamilyForModel("codex-mini-latest")
        XCTAssertEqual(codexMini.shellType, .local)
        XCTAssertEqual(codexMini.contextWindow, 200_000)
        XCTAssertTrue(codexMini.needsSpecialApplyPatchInstructions)

        let gptOss = ModelsManager.findFamilyForModel("openai/gpt-oss-120b")
        XCTAssertEqual(gptOss.family, "gpt-oss")
        XCTAssertEqual(gptOss.applyPatchToolType, .freeform)
        XCTAssertEqual(gptOss.contextWindow, 96_000)

        let testModel = ModelsManager.findFamilyForModel("test-gpt-5-codex")
        XCTAssertEqual(testModel.family, "test-gpt-5-codex")
        XCTAssertEqual(testModel.experimentalSupportedTools, [
            "grep_files",
            "list_dir",
            "read_file",
            "test_sync_tool"
        ])
        XCTAssertTrue(testModel.supportsParallelToolCalls)
        XCTAssertEqual(testModel.shellType, .shellCommand)
        XCTAssertEqual(testModel.truncationPolicy, .tokens(10_000))

        let codex52 = ModelsManager.findFamilyForModel("gpt-5.2-codex")
        XCTAssertEqual(codex52.family, "gpt-5.2-codex")
        XCTAssertTrue(codex52.supportsReasoningSummaries)
        XCTAssertEqual(codex52.applyPatchToolType, .freeform)
        XCTAssertEqual(codex52.shellType, .shellCommand)
        XCTAssertTrue(codex52.supportsParallelToolCalls)
        XCTAssertFalse(codex52.supportVerbosity)
        XCTAssertEqual(codex52.truncationPolicy, .tokens(10_000))
        XCTAssertEqual(codex52.contextWindow, ModelFamily.contextWindow272K)
        XCTAssertEqual(codex52.autoCompactTokenLimit(), 244_800)
        XCTAssertEqual(codex52.baseInstructions, ModelsManager.findFamilyForModel("bengalfox").baseInstructions)

        let codex51Max = ModelsManager.findFamilyForModel("gpt-5.1-codex-max")
        XCTAssertFalse(codex51Max.supportsParallelToolCalls)
        XCTAssertEqual(codex51Max.applyPatchToolType, .freeform)
        XCTAssertEqual(codex51Max.truncationPolicy, .tokens(10_000))

        let legacyCodex = ModelsManager.findFamilyForModel("gpt-5-codex")
        XCTAssertFalse(legacyCodex.supportsParallelToolCalls)
        XCTAssertEqual(legacyCodex.baseInstructions, ModelsManager.findFamilyForModel("gpt-5.1-codex").baseInstructions)
        XCTAssertEqual(legacyCodex.truncationPolicy, .tokens(10_000))

        let gpt52 = ModelsManager.findFamilyForModel("gpt-5.2")
        XCTAssertEqual(gpt52.defaultReasoningEffort, .medium)
        XCTAssertEqual(gpt52.defaultVerbosity, .low)
        XCTAssertTrue(gpt52.supportVerbosity)
        XCTAssertTrue(gpt52.supportsParallelToolCalls)
        XCTAssertEqual(gpt52.truncationPolicy, .bytes(10_000))
        XCTAssertEqual(gpt52.shellType, .shellCommand)

        let gpt51 = ModelsManager.findFamilyForModel("gpt-5.1")
        XCTAssertEqual(gpt51.family, "gpt-5.1")
        XCTAssertEqual(gpt51.defaultReasoningEffort, .medium)
        XCTAssertEqual(gpt51.defaultVerbosity, .low)
        XCTAssertEqual(gpt51.applyPatchToolType, .freeform)

        let gpt5 = ModelsManager.findFamilyForModel("gpt-5")
        XCTAssertEqual(gpt5.family, "gpt-5")
        XCTAssertTrue(gpt5.needsSpecialApplyPatchInstructions)
        XCTAssertTrue(gpt5.supportVerbosity)
        XCTAssertNil(gpt5.defaultVerbosity)
        XCTAssertNil(gpt5.defaultReasoningEffort)
        XCTAssertFalse(gpt5.supportsParallelToolCalls)
        XCTAssertEqual(gpt5.shellType, .default)

        let unknown = ModelsManager.findFamilyForModel("unknown-model")
        XCTAssertEqual(unknown.slug, "unknown-model")
        XCTAssertEqual(unknown.family, "unknown-model")
        XCTAssertEqual(unknown.inputModalities, [.text, .image])
        XCTAssertNil(unknown.contextWindow)
        XCTAssertNil(unknown.autoCompactTokenLimit())
        XCTAssertTrue(unknown.baseInstructions.hasPrefix("You are a coding agent running in the Codex CLI"))
    }

    func testRemoteOverridesApplyWhenSlugMatches() {
        let family = ModelFamily(slug: "gpt-4o-mini", family: "gpt-4o-mini")
        XCTAssertNotEqual(family.defaultReasoningEffort, .high)

        let updated = family.withRemoteOverrides([
            remote("gpt-4o-mini", effort: .high, shell: .shellCommand),
            remote("other-model", effort: .low, shell: .unifiedExec)
        ])

        XCTAssertEqual(updated.defaultReasoningEffort, .high)
        XCTAssertEqual(updated.shellType, .shellCommand)
    }

    func testRemoteOverridesUseLongestPrefixLikeRustModelInfoLookup() {
        let family = ModelFamily(slug: "gpt-overlay-experiment", family: "gpt-overlay-experiment")

        let updated = family.withRemoteOverrides([
            remote("gpt", effort: .low, shell: .local),
            remote("gpt-overlay", effort: .high, shell: .shellCommand),
            remote("other-model", effort: .medium, shell: .unifiedExec)
        ])

        XCTAssertEqual(updated.slug, "gpt-overlay-experiment")
        XCTAssertEqual(updated.defaultReasoningEffort, .high)
        XCTAssertEqual(updated.shellType, .shellCommand)
    }

    func testRemoteOverridesMatchSingleProviderNamespaceSuffixLikeRustModelInfoLookup() {
        let family = ModelFamily(slug: "openai-codex/gpt-image-preview", family: "openai-codex/gpt-image-preview")

        let updated = family.withRemoteOverrides([
            remote("gpt-image", effort: .high, shell: .shellCommand)
        ])

        XCTAssertEqual(updated.defaultReasoningEffort, .high)
        XCTAssertEqual(updated.shellType, .shellCommand)
    }

    func testRemoteOverridesRejectMultiSegmentNamespaceSuffixLikeRustModelInfoLookup() {
        let family = ModelFamily(slug: "ns1/ns2/gpt-image", family: "ns1/ns2/gpt-image")

        let updated = family.withRemoteOverrides([
            remote("gpt-image", effort: .high, shell: .shellCommand)
        ])

        XCTAssertEqual(updated.defaultReasoningEffort, family.defaultReasoningEffort)
        XCTAssertEqual(updated.shellType, family.shellType)
    }

    func testRemoteOverridesSkipNonMatchingModels() {
        let family = ModelFamily(
            slug: "codex-mini-latest",
            family: "codex-mini-latest",
            shellType: .local
        )

        let updated = family.withRemoteOverrides([
            remote("other", effort: .high, shell: .shellCommand)
        ])

        XCTAssertEqual(updated.defaultReasoningEffort, family.defaultReasoningEffort)
        XCTAssertEqual(updated.shellType, family.shellType)
    }

    func testRemoteOverridesApplyExtendedMetadata() {
        let family = ModelFamily(
            slug: "gpt-5.1",
            family: "gpt-5.1",
            supportsReasoningSummaries: false,
            supportsParallelToolCalls: false,
            applyPatchToolType: nil,
            experimentalSupportedTools: ["local"],
            supportVerbosity: false,
            defaultVerbosity: nil,
            truncationPolicy: .bytes(10_000)
        )

        let updated = family.withRemoteOverrides([
            ModelInfo(
                slug: "gpt-5.1",
                displayName: "gpt-5.1",
                description: "desc",
                defaultReasoningLevel: .high,
                supportedReasoningLevels: [
                    ReasoningEffortPreset(effort: .high, description: "High")
                ],
                shellType: .shellCommand,
                visibility: .list,
                supportedInAPI: true,
                priority: 10,
                serviceTiers: [
                    ModelServiceTier(id: "priority", name: "fast", description: "Fastest inference.")
                ],
                baseInstructions: "Remote instructions",
                supportsReasoningSummaries: true,
                supportVerbosity: true,
                defaultVerbosity: .high,
                applyPatchToolType: .freeform,
                truncationPolicy: .tokens(2_000),
                supportsParallelToolCalls: true,
                contextWindow: 400_000,
                experimentalSupportedTools: ["alpha", "beta"],
                inputModalities: [.text]
            )
        ])

        XCTAssertEqual(updated.defaultReasoningEffort, .high)
        XCTAssertTrue(updated.supportsReasoningSummaries)
        XCTAssertTrue(updated.supportVerbosity)
        XCTAssertEqual(updated.defaultVerbosity, .high)
        XCTAssertEqual(updated.shellType, .shellCommand)
        XCTAssertEqual(updated.applyPatchToolType, .freeform)
        XCTAssertEqual(updated.truncationPolicy, .tokens(2_000))
        XCTAssertTrue(updated.supportsParallelToolCalls)
        XCTAssertEqual(updated.contextWindow, 400_000)
        XCTAssertEqual(updated.experimentalSupportedTools, ["alpha", "beta"])
        XCTAssertEqual(updated.inputModalities, [.text])
        XCTAssertEqual(updated.serviceTiers.map(\.id), ["priority"])
        XCTAssertEqual(updated.baseInstructions, "Remote instructions")
    }

    func testConstructModelFamilyOfflineUsesBundledServiceTiersLikeRust() {
        let family = ModelsManager.constructModelFamilyOffline(model: "gpt-5.5")

        XCTAssertEqual(family.serviceTiers.map(\.id), ["priority"])
    }

    func testConstructModelFamilyAppliesConfigAfterRemoteOverrides() {
        let updated = ModelsManager.constructModelFamily(
            model: "gpt-5.1",
            remoteModels: [
                ModelInfo(
                    slug: "gpt-5.1",
                    displayName: "gpt-5.1",
                    defaultReasoningLevel: .high,
                    supportedReasoningLevels: [
                        ReasoningEffortPreset(effort: .high, description: "High")
                    ],
                    shellType: .shellCommand,
                    visibility: .list,
                    supportedInAPI: true,
                    priority: 1,
                    baseInstructions: "Remote instructions",
                    supportsReasoningSummaries: false,
                    supportVerbosity: false,
                    truncationPolicy: .tokens(4_000),
                    supportsParallelToolCalls: false,
                    contextWindow: 400_000,
                    experimentalSupportedTools: []
                )
            ],
            configOverrides: ModelFamilyConfigOverrides(
                supportsReasoningSummaries: true,
                contextWindow: 123_456,
                autoCompactTokenLimit: 12_345
            )
        )

        XCTAssertEqual(updated.defaultReasoningEffort, .high)
        XCTAssertEqual(updated.baseInstructions, "Remote instructions")
        XCTAssertTrue(updated.supportsReasoningSummaries)
        XCTAssertEqual(updated.contextWindow, 123_456)
        XCTAssertEqual(updated.autoCompactTokenLimit(), 12_345)
        XCTAssertEqual(updated.truncationPolicy, .tokens(4_000))
    }

    func testReasoningSummariesOverrideFalseDoesNotDisableSupportLikeRust() {
        let enabled = ModelFamily(
            slug: "enabled-model",
            family: "test",
            supportsReasoningSummaries: true
        )
        .withConfigOverrides(ModelFamilyConfigOverrides(supportsReasoningSummaries: false))

        XCTAssertTrue(enabled.supportsReasoningSummaries)

        let disabled = ModelFamily(
            slug: "disabled-model",
            family: "test",
            supportsReasoningSummaries: false
        )
        .withConfigOverrides(ModelFamilyConfigOverrides(supportsReasoningSummaries: false))

        XCTAssertFalse(disabled.supportsReasoningSummaries)
    }

    func testConfigContextWindowOverrideClampsToRemoteMaximumLikeRust() {
        let updated = ModelsManager.constructModelFamily(
            model: "gpt-5.1",
            remoteModels: [
                ModelInfo(
                    slug: "gpt-5.1",
                    displayName: "gpt-5.1",
                    supportedReasoningLevels: [],
                    shellType: .default,
                    visibility: .list,
                    supportedInAPI: true,
                    priority: 1,
                    supportsReasoningSummaries: false,
                    supportVerbosity: false,
                    truncationPolicy: .tokens(4_000),
                    supportsParallelToolCalls: false,
                    contextWindow: 273_000,
                    maxContextWindow: 400_000,
                    experimentalSupportedTools: []
                )
            ],
            configOverrides: ModelFamilyConfigOverrides(contextWindow: 500_000)
        )

        XCTAssertEqual(updated.contextWindow, 400_000)
        XCTAssertEqual(updated.maxContextWindow, 400_000)
    }

    func testToolOutputTokenLimitOverridePreservesRustPolicyMode() {
        let bytesFamily = ModelFamily(
            slug: "bytes-model",
            family: "test",
            truncationPolicy: .bytes(10_000)
        )
        .withConfigOverrides(ModelFamilyConfigOverrides(toolOutputTokenLimit: 123))

        XCTAssertEqual(bytesFamily.truncationPolicy, .bytes(Truncation.approxBytesForTokens(123)))

        let tokensFamily = ModelFamily(
            slug: "tokens-model",
            family: "test",
            truncationPolicy: .tokens(10_000)
        )
        .withConfigOverrides(ModelFamilyConfigOverrides(toolOutputTokenLimit: 123))

        XCTAssertEqual(tokensFamily.truncationPolicy, .tokens(123))
    }

    func testConstructModelFamilyAppliesToolOutputTokenLimitAfterRemoteOverridesLikeRust() {
        let updated = ModelsManager.constructModelFamily(
            model: "gpt-5.4",
            remoteModels: [
                ModelInfo(
                    slug: "gpt-5.4",
                    displayName: "gpt-5.4",
                    supportedReasoningLevels: [],
                    shellType: .default,
                    visibility: .list,
                    supportedInAPI: true,
                    priority: 1,
                    supportsReasoningSummaries: false,
                    supportVerbosity: false,
                    truncationPolicy: .tokens(10_000),
                    supportsParallelToolCalls: false,
                    experimentalSupportedTools: []
                )
            ],
            configOverrides: ModelFamilyConfigOverrides(toolOutputTokenLimit: 123)
        )

        XCTAssertEqual(updated.truncationPolicy, .tokens(123))
    }

    func testTruncationPolicyConfigConvertsToRuntimePolicy() {
        XCTAssertEqual(TruncationPolicyConfig.bytes(1_024).runtimePolicy, .bytes(1_024))
        XCTAssertEqual(TruncationPolicyConfig.tokens(2_048).runtimePolicy, .tokens(2_048))
    }

    private func remote(
        _ slug: String,
        effort: ReasoningEffort,
        shell: ConfigShellToolType
    ) -> ModelInfo {
        ModelInfo(
            slug: slug,
            displayName: slug,
            description: "\(slug) desc",
            defaultReasoningLevel: effort,
            supportedReasoningLevels: [
                ReasoningEffortPreset(effort: effort, description: effort.rawValue)
            ],
            shellType: shell,
            visibility: .list,
            supportedInAPI: true,
            priority: 1,
            supportsReasoningSummaries: false,
            supportVerbosity: false,
            truncationPolicy: .bytes(10_000),
            supportsParallelToolCalls: false,
            experimentalSupportedTools: []
        )
    }
}
