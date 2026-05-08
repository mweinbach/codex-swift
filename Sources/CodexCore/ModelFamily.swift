import Foundation

public struct ModelFamilyConfigOverrides: Equatable, Sendable {
    public var supportsReasoningSummaries: Bool?
    public var contextWindow: Int64?
    public var autoCompactTokenLimit: Int64?

    public init(
        supportsReasoningSummaries: Bool? = nil,
        contextWindow: Int64? = nil,
        autoCompactTokenLimit: Int64? = nil
    ) {
        self.supportsReasoningSummaries = supportsReasoningSummaries
        self.contextWindow = contextWindow
        self.autoCompactTokenLimit = autoCompactTokenLimit
    }
}

public struct ModelFamily: Equatable, Sendable {
    public static let contextWindow272K: Int64 = 272_000

    public var slug: String
    public var family: String
    public var needsSpecialApplyPatchInstructions: Bool
    public var contextWindow: Int64?
    public var supportsReasoningSummaries: Bool
    public var defaultReasoningEffort: ReasoningEffort?
    public var supportsParallelToolCalls: Bool
    public var applyPatchToolType: ApplyPatchToolType?
    public var baseInstructions: String
    public var experimentalSupportedTools: [String]
    public var effectiveContextWindowPercent: Int64
    public var supportVerbosity: Bool
    public var defaultVerbosity: Verbosity?
    public var defaultReasoningSummary: ReasoningSummary
    public var shellType: ConfigShellToolType
    public var truncationPolicy: TruncationPolicy

    private var configuredAutoCompactTokenLimit: Int64?

    public init(
        slug: String,
        family: String,
        needsSpecialApplyPatchInstructions: Bool = false,
        contextWindow: Int64? = 272_000,
        autoCompactTokenLimit: Int64? = nil,
        supportsReasoningSummaries: Bool = false,
        defaultReasoningEffort: ReasoningEffort? = nil,
        supportsParallelToolCalls: Bool = false,
        applyPatchToolType: ApplyPatchToolType? = nil,
        baseInstructions: String? = nil,
        experimentalSupportedTools: [String] = [],
        effectiveContextWindowPercent: Int64 = 95,
        supportVerbosity: Bool = false,
        defaultVerbosity: Verbosity? = nil,
        defaultReasoningSummary: ReasoningSummary = .auto,
        shellType: ConfigShellToolType = .default,
        truncationPolicy: TruncationPolicy = .bytes(10_000)
    ) {
        self.slug = slug
        self.family = family
        self.needsSpecialApplyPatchInstructions = needsSpecialApplyPatchInstructions
        self.contextWindow = contextWindow
        self.configuredAutoCompactTokenLimit = autoCompactTokenLimit
        self.supportsReasoningSummaries = supportsReasoningSummaries
        self.defaultReasoningEffort = defaultReasoningEffort
        self.supportsParallelToolCalls = supportsParallelToolCalls
        self.applyPatchToolType = applyPatchToolType
        self.baseInstructions = baseInstructions ?? ModelFamilyPrompts.base
        self.experimentalSupportedTools = experimentalSupportedTools
        self.effectiveContextWindowPercent = effectiveContextWindowPercent
        self.supportVerbosity = supportVerbosity
        self.defaultVerbosity = defaultVerbosity
        self.defaultReasoningSummary = defaultReasoningSummary
        self.shellType = shellType
        self.truncationPolicy = truncationPolicy
    }

    public func withConfigOverrides(_ overrides: ModelFamilyConfigOverrides) -> ModelFamily {
        var family = self
        if let supportsReasoningSummaries = overrides.supportsReasoningSummaries {
            family.supportsReasoningSummaries = supportsReasoningSummaries
        }
        if let contextWindow = overrides.contextWindow {
            family.contextWindow = contextWindow
        }
        if let autoCompactTokenLimit = overrides.autoCompactTokenLimit {
            family.configuredAutoCompactTokenLimit = autoCompactTokenLimit
        }
        return family
    }

    public func withRemoteOverrides(_ remoteModels: [ModelInfo]) -> ModelFamily {
        var family = self
        for model in remoteModels where model.slug == family.slug {
            family.applyRemoteOverrides(model)
        }
        return family
    }

    public func autoCompactTokenLimit() -> Int64? {
        configuredAutoCompactTokenLimit ?? contextWindow.map(Self.defaultAutoCompactLimit)
    }

    public func modelSlug() -> String {
        slug
    }

    private mutating func applyRemoteOverrides(_ model: ModelInfo) {
        defaultReasoningEffort = model.defaultReasoningLevel
        shellType = model.shellType
        if let baseInstructions = model.baseInstructions {
            self.baseInstructions = baseInstructions
        }
        supportsReasoningSummaries = model.supportsReasoningSummaries
        defaultReasoningSummary = model.defaultReasoningSummary
        supportVerbosity = model.supportVerbosity
        defaultVerbosity = model.defaultVerbosity
        applyPatchToolType = model.applyPatchToolType
        truncationPolicy = model.truncationPolicy.runtimePolicy
        supportsParallelToolCalls = model.supportsParallelToolCalls
        contextWindow = model.resolvedContextWindow
        configuredAutoCompactTokenLimit = model.autoCompactTokenLimitValue()
        effectiveContextWindowPercent = model.effectiveContextWindowPercent
        experimentalSupportedTools = model.experimentalSupportedTools
    }

    private static func defaultAutoCompactLimit(contextWindow: Int64) -> Int64 {
        (contextWindow * 9) / 10
    }
}

extension ModelsManager {
    public static func constructModelFamily(
        model: String,
        remoteModels: [ModelInfo],
        configOverrides: ModelFamilyConfigOverrides = ModelFamilyConfigOverrides()
    ) -> ModelFamily {
        findFamilyForModel(model)
            .withRemoteOverrides(remoteModels)
            .withConfigOverrides(configOverrides)
    }

    public static func constructModelFamilyOffline(
        model: String,
        configOverrides: ModelFamilyConfigOverrides = ModelFamilyConfigOverrides()
    ) -> ModelFamily {
        findFamilyForModel(model).withConfigOverrides(configOverrides)
    }

    public static func findFamilyForModel(_ slug: String) -> ModelFamily {
        if slug.hasPrefix("o3") {
            return ModelFamily(
                slug: slug,
                family: "o3",
                needsSpecialApplyPatchInstructions: true,
                contextWindow: 200_000,
                supportsReasoningSummaries: true
            )
        } else if slug.hasPrefix("o4-mini") {
            return ModelFamily(
                slug: slug,
                family: "o4-mini",
                needsSpecialApplyPatchInstructions: true,
                contextWindow: 200_000,
                supportsReasoningSummaries: true
            )
        } else if slug.hasPrefix("codex-mini-latest") {
            return ModelFamily(
                slug: slug,
                family: "codex-mini-latest",
                needsSpecialApplyPatchInstructions: true,
                contextWindow: 200_000,
                supportsReasoningSummaries: true,
                shellType: .local
            )
        } else if slug.hasPrefix("gpt-4.1") {
            return ModelFamily(
                slug: slug,
                family: "gpt-4.1",
                needsSpecialApplyPatchInstructions: true,
                contextWindow: 1_047_576
            )
        } else if slug.hasPrefix("gpt-oss") || slug.hasPrefix("openai/gpt-oss") {
            return ModelFamily(
                slug: slug,
                family: "gpt-oss",
                contextWindow: 96_000,
                applyPatchToolType: .freeform
            )
        } else if slug.hasPrefix("gpt-4o") {
            return ModelFamily(
                slug: slug,
                family: "gpt-4o",
                needsSpecialApplyPatchInstructions: true,
                contextWindow: 128_000
            )
        } else if slug.hasPrefix("gpt-3.5") {
            return ModelFamily(
                slug: slug,
                family: "gpt-3.5",
                needsSpecialApplyPatchInstructions: true,
                contextWindow: 16_385
            )
        } else if slug.hasPrefix("test-gpt-5") {
            return ModelFamily(
                slug: slug,
                family: slug,
                supportsReasoningSummaries: true,
                supportsParallelToolCalls: true,
                baseInstructions: ModelFamilyPrompts.gpt5Codex,
                experimentalSupportedTools: [
                    "grep_files",
                    "list_dir",
                    "read_file",
                    "test_sync_tool"
                ],
                supportVerbosity: true,
                shellType: .shellCommand,
                truncationPolicy: .tokens(10_000)
            )
        } else if slug.hasPrefix("exp-codex") || slug.hasPrefix("codex-1p") {
            return codex52Family(slug)
        } else if slug.hasPrefix("exp-") {
            return ModelFamily(
                slug: slug,
                family: slug,
                supportsReasoningSummaries: true,
                defaultReasoningEffort: .medium,
                supportsParallelToolCalls: true,
                applyPatchToolType: .freeform,
                baseInstructions: ModelFamilyPrompts.base,
                supportVerbosity: true,
                defaultVerbosity: .low,
                shellType: .unifiedExec,
                truncationPolicy: .bytes(10_000)
            )
        } else if slug.hasPrefix("gpt-5.5") {
            return gpt55Family(slug)
        } else if slug.hasPrefix("gpt-5.4-mini") {
            return gpt54MiniFamily(slug)
        } else if slug.hasPrefix("gpt-5.4") || slug.hasPrefix("codex-auto-review") {
            return gpt54Family(slug)
        } else if slug.hasPrefix("gpt-5.3-codex") {
            return gpt53CodexFamily(slug)
        } else if slug.hasPrefix("gpt-5.2-codex") {
            return codex52Family(slug)
        } else if slug.hasPrefix("bengalfox") {
            return codex52Family(slug)
        } else if slug.hasPrefix("gpt-5.1-codex-max") {
            return ModelFamily(
                slug: slug,
                family: slug,
                supportsReasoningSummaries: true,
                supportsParallelToolCalls: false,
                applyPatchToolType: .freeform,
                baseInstructions: ModelFamilyPrompts.gpt51CodexMax,
                supportVerbosity: false,
                shellType: .shellCommand,
                truncationPolicy: .tokens(10_000)
            )
        } else if slug.hasPrefix("gpt-5-codex")
            || slug.hasPrefix("gpt-5.1-codex")
            || slug.hasPrefix("codex-")
        {
            return ModelFamily(
                slug: slug,
                family: slug,
                supportsReasoningSummaries: true,
                supportsParallelToolCalls: false,
                applyPatchToolType: .freeform,
                baseInstructions: ModelFamilyPrompts.gpt5Codex,
                supportVerbosity: false,
                shellType: .shellCommand,
                truncationPolicy: .tokens(10_000)
            )
        } else if slug.hasPrefix("gpt-5.2") {
            return gpt52Family(slug)
        } else if slug.hasPrefix("boomslang") {
            return gpt52Family(slug)
        } else if slug.hasPrefix("gpt-5.1") {
            return ModelFamily(
                slug: slug,
                family: "gpt-5.1",
                supportsReasoningSummaries: true,
                defaultReasoningEffort: .medium,
                supportsParallelToolCalls: true,
                applyPatchToolType: .freeform,
                baseInstructions: ModelFamilyPrompts.gpt51,
                supportVerbosity: true,
                defaultVerbosity: .low,
                shellType: .shellCommand,
                truncationPolicy: .bytes(10_000)
            )
        } else if slug.hasPrefix("gpt-5") {
            return ModelFamily(
                slug: slug,
                family: "gpt-5",
                needsSpecialApplyPatchInstructions: true,
                supportsReasoningSummaries: true,
                supportVerbosity: true,
                shellType: .default,
                truncationPolicy: .bytes(10_000)
            )
        } else {
            return deriveDefaultModelFamily(slug)
        }
    }

    private static func codex52Family(_ slug: String) -> ModelFamily {
        ModelFamily(
            slug: slug,
            family: slug,
            supportsReasoningSummaries: true,
            supportsParallelToolCalls: true,
            applyPatchToolType: .freeform,
            baseInstructions: ModelFamilyPrompts.gpt52Codex,
            supportVerbosity: false,
            shellType: .shellCommand,
            truncationPolicy: .tokens(10_000)
        )
    }

    private static func gpt52Family(_ slug: String) -> ModelFamily {
        ModelFamily(
            slug: slug,
            family: slug,
            supportsReasoningSummaries: true,
            defaultReasoningEffort: .medium,
            supportsParallelToolCalls: true,
            applyPatchToolType: .freeform,
            baseInstructions: ModelFamilyPrompts.gpt52,
            supportVerbosity: true,
            defaultVerbosity: .low,
            shellType: .shellCommand,
            truncationPolicy: .bytes(10_000)
        )
    }

    private static func gpt55Family(_ slug: String) -> ModelFamily {
        ModelFamily(
            slug: slug,
            family: slug,
            supportsReasoningSummaries: true,
            defaultReasoningEffort: .medium,
            supportsParallelToolCalls: true,
            applyPatchToolType: .freeform,
            baseInstructions: ModelFamilyPrompts.base,
            supportVerbosity: true,
            defaultVerbosity: .low,
            defaultReasoningSummary: .none,
            shellType: .shellCommand,
            truncationPolicy: .tokens(10_000)
        )
    }

    private static func gpt54Family(_ slug: String) -> ModelFamily {
        ModelFamily(
            slug: slug,
            family: slug,
            supportsReasoningSummaries: true,
            defaultReasoningEffort: .medium,
            supportsParallelToolCalls: true,
            applyPatchToolType: .freeform,
            baseInstructions: ModelFamilyPrompts.base,
            supportVerbosity: true,
            defaultVerbosity: .low,
            defaultReasoningSummary: .none,
            shellType: .shellCommand,
            truncationPolicy: .tokens(10_000)
        )
    }

    private static func gpt54MiniFamily(_ slug: String) -> ModelFamily {
        var family = gpt54Family(slug)
        family.defaultVerbosity = .medium
        return family
    }

    private static func gpt53CodexFamily(_ slug: String) -> ModelFamily {
        ModelFamily(
            slug: slug,
            family: slug,
            supportsReasoningSummaries: true,
            defaultReasoningEffort: .medium,
            supportsParallelToolCalls: true,
            applyPatchToolType: .freeform,
            baseInstructions: ModelFamilyPrompts.gpt5Codex,
            supportVerbosity: true,
            defaultVerbosity: .low,
            defaultReasoningSummary: .none,
            shellType: .shellCommand,
            truncationPolicy: .tokens(10_000)
        )
    }

    private static func deriveDefaultModelFamily(_ model: String) -> ModelFamily {
        ModelFamily(
            slug: model,
            family: model,
            contextWindow: nil
        )
    }
}

private enum ModelFamilyPrompts {
    static let base = load("prompt")
    static let gpt5Codex = load("gpt_5_codex_prompt")
    static let gpt51 = load("gpt_5_1_prompt")
    static let gpt52 = load("gpt_5_2_prompt")
    static let gpt51CodexMax = load("gpt-5.1-codex-max_prompt")
    static let gpt52Codex = load("gpt-5.2-codex_prompt")

    private static func load(_ name: String) -> String {
        let url = Bundle.module.url(
            forResource: name,
            withExtension: "md",
            subdirectory: "ModelPrompts"
        ) ?? Bundle.module.url(forResource: name, withExtension: "md")

        guard let url else {
            preconditionFailure("Missing bundled model prompt resource: \(name).md")
        }

        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            preconditionFailure("Unable to load bundled model prompt resource \(name).md: \(error)")
        }
    }
}
