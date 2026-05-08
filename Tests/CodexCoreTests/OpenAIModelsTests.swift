import CodexCore
import XCTest

final class OpenAIModelsTests: XCTestCase {
    func testModelMetadataEnumsAndClientVersionWireShapes() throws {
        XCTAssertEqual(try encode(ModelVisibility.list), #""list""#)
        XCTAssertEqual(try encode(ModelVisibility.hide), #""hide""#)
        XCTAssertEqual(try encode(ModelVisibility.none), #""none""#)
        XCTAssertEqual(try encode(TruncationMode.bytes), #""bytes""#)
        XCTAssertEqual(try encode(TruncationMode.tokens), #""tokens""#)

        let version = ClientVersion(0, 62, 0)
        XCTAssertEqual(try encode(version), #"[0,62,0]"#)
        XCTAssertEqual(try JSONDecoder().decode(ClientVersion.self, from: Data(#"[0,62,0]"#.utf8)), version)
        XCTAssertThrowsError(try JSONDecoder().decode(ClientVersion.self, from: Data(#"[0,62,0,1]"#.utf8)))
    }

    func testReasoningEffortPresetAndTruncationPolicyConfigWireShape() throws {
        try XCTAssertJSONObjectEqual(ReasoningEffortPreset(effort: .high, description: "More deliberate"), [
            "effort": "high",
            "description": "More deliberate"
        ])

        try XCTAssertJSONObjectEqual(ModelServiceTier(id: "priority", name: "Fast", description: "Priority processing."), [
            "id": "priority",
            "name": "Fast",
            "description": "Priority processing."
        ])

        try XCTAssertJSONObjectEqual(TruncationPolicyConfig.tokens(123_456), [
            "mode": "tokens",
            "limit": 123_456
        ])
    }

    func testModelUpgradeEncodesOptionalNullsAndReasoningEffortMapAsObject() throws {
        let upgrade = ModelUpgrade(
            id: "gpt-5.1",
            reasoningEffortMapping: [
                .none: .minimal,
                .medium: .high,
                .xhigh: .xhigh
            ],
            migrationConfigKey: "gpt-5"
        )

        try XCTAssertJSONObjectEqual(upgrade, [
            "id": "gpt-5.1",
            "reasoning_effort_mapping": [
                "none": "minimal",
                "medium": "high",
                "xhigh": "xhigh"
            ],
            "migration_config_key": "gpt-5",
            "model_link": NSNull(),
            "upgrade_copy": NSNull(),
            "migration_markdown": NSNull()
        ])

        let data = try JSONEncoder().encode(upgrade)
        XCTAssertEqual(try JSONDecoder().decode(ModelUpgrade.self, from: data), upgrade)
    }

    func testModelInfoWireShapeIncludesRustNullOptionals() throws {
        let info = ModelInfo(
            slug: "gpt-5",
            displayName: "GPT-5",
            defaultReasoningLevel: .medium,
            supportedReasoningLevels: [
                ReasoningEffortPreset(effort: .low, description: "Quick"),
                ReasoningEffortPreset(effort: .high, description: "Deep")
            ],
            shellType: .unifiedExec,
            visibility: .list,
            supportedInAPI: true,
            priority: 10,
            additionalSpeedTiers: ["fast"],
            serviceTiers: [
                ModelServiceTier(id: "priority", name: "Fast", description: "Priority processing.")
            ],
            availabilityNux: ModelAvailabilityNux(message: "Try GPT-5."),
            upgrade: ModelInfoUpgrade(model: "gpt-5.1", migrationMarkdown: "Move to GPT-5.1."),
            supportsReasoningSummaries: true,
            supportVerbosity: true,
            defaultVerbosity: .medium,
            applyPatchToolType: .freeform,
            truncationPolicy: .tokens(200_000),
            supportsParallelToolCalls: true,
            contextWindow: 400_000,
            experimentalSupportedTools: ["web_search", "apply_patch"],
            inputModalities: [.text]
        )

        XCTAssertTrue(info.supportsServiceTier("priority"))
        XCTAssertFalse(info.supportsServiceTier("flex"))
        try XCTAssertJSONObjectEqual(info, [
            "slug": "gpt-5",
            "display_name": "GPT-5",
            "description": NSNull(),
            "default_reasoning_level": "medium",
            "supported_reasoning_levels": [
                [
                    "effort": "low",
                    "description": "Quick"
                ],
                [
                    "effort": "high",
                    "description": "Deep"
                ]
            ],
            "shell_type": "unified_exec",
            "visibility": "list",
            "supported_in_api": true,
            "priority": 10,
            "additional_speed_tiers": ["fast"],
            "service_tiers": [
                [
                    "id": "priority",
                    "name": "Fast",
                    "description": "Priority processing."
                ]
            ],
            "availability_nux": [
                "message": "Try GPT-5."
            ],
            "upgrade": [
                "model": "gpt-5.1",
                "migration_markdown": "Move to GPT-5.1."
            ],
            "base_instructions": NSNull(),
            "supports_reasoning_summaries": true,
            "support_verbosity": true,
            "default_verbosity": "medium",
            "apply_patch_tool_type": "freeform",
            "truncation_policy": [
                "mode": "tokens",
                "limit": 200_000
            ],
            "supports_parallel_tool_calls": true,
            "context_window": 400_000,
            "experimental_supported_tools": ["web_search", "apply_patch"],
            "input_modalities": ["text"]
        ])

        let data = try JSONEncoder().encode(info)
        XCTAssertEqual(try JSONDecoder().decode(ModelInfo.self, from: data), info)
    }

    func testModelInfoDefaultsMissingCatalogFieldsLikeRust() throws {
        let decoded = try JSONDecoder().decode(ModelInfo.self, from: Data("""
        {
          "slug": "gpt-test",
          "display_name": "GPT Test",
          "description": null,
          "default_reasoning_level": "medium",
          "supported_reasoning_levels": [],
          "shell_type": "default",
          "visibility": "list",
          "supported_in_api": true,
          "priority": 1,
          "upgrade": null,
          "base_instructions": "base",
          "supports_reasoning_summaries": false,
          "support_verbosity": false,
          "default_verbosity": null,
          "apply_patch_tool_type": null,
          "truncation_policy": { "mode": "bytes", "limit": 4096 },
          "supports_parallel_tool_calls": false,
          "context_window": null,
          "experimental_supported_tools": []
        }
        """.utf8))

        XCTAssertEqual(decoded.additionalSpeedTiers, [])
        XCTAssertEqual(decoded.serviceTiers, [])
        XCTAssertNil(decoded.availabilityNux)
        XCTAssertEqual(decoded.inputModalities, [.text, .image])
    }

    func testModelsResponseDefaultsMissingEtagToEmptyString() throws {
        let info = minimalModelInfo()
        let response = ModelsResponse(models: [info])

        let decoded = try JSONDecoder().decode(ModelsResponse.self, from: Data("""
        {
          "models": []
        }
        """.utf8))
        XCTAssertEqual(decoded, ModelsResponse(models: [], etag: ""))
        XCTAssertThrowsError(try JSONDecoder().decode(ModelsResponse.self, from: Data("""
        {
          "models": [],
          "etag": null
        }
        """.utf8)))

        try XCTAssertJSONObjectEqual(response, [
            "models": [
                [
                    "slug": "codex-mini",
                    "display_name": "Codex Mini",
                    "description": "Small",
                    "default_reasoning_level": "low",
                    "supported_reasoning_levels": [],
                    "shell_type": "default",
                    "visibility": "hide",
                    "supported_in_api": false,
                    "priority": 5,
                    "additional_speed_tiers": [],
                    "service_tiers": [],
                    "availability_nux": NSNull(),
                    "upgrade": NSNull(),
                    "base_instructions": "base",
                    "supports_reasoning_summaries": false,
                    "support_verbosity": false,
                    "default_verbosity": NSNull(),
                    "apply_patch_tool_type": NSNull(),
                    "truncation_policy": [
                        "mode": "bytes",
                        "limit": 4096
                    ],
                    "supports_parallel_tool_calls": false,
                    "context_window": NSNull(),
                    "experimental_supported_tools": [],
                    "input_modalities": ["text", "image"]
                ]
            ],
            "etag": ""
        ])
    }

    func testModelInfoConvertsToPresetWithNearestReasoningEffortMapping() throws {
        let info = ModelInfo(
            slug: "gpt-5",
            displayName: "GPT-5",
            description: nil,
            defaultReasoningLevel: .medium,
            supportedReasoningLevels: [
                ReasoningEffortPreset(effort: .low, description: "Quick"),
                ReasoningEffortPreset(effort: .high, description: "Deep")
            ],
            shellType: .shellCommand,
            visibility: .list,
            supportedInAPI: true,
            priority: 1,
            additionalSpeedTiers: [],
            serviceTiers: [
                ModelServiceTier(id: "priority", name: "Fast", description: "Priority processing.")
            ],
            availabilityNux: ModelAvailabilityNux(message: "Try it."),
            upgrade: ModelInfoUpgrade(model: "gpt-5.1", migrationMarkdown: "Move to GPT-5.1."),
            baseInstructions: nil,
            supportsReasoningSummaries: true,
            supportVerbosity: false,
            defaultVerbosity: nil,
            applyPatchToolType: nil,
            truncationPolicy: .bytes(8192),
            supportsParallelToolCalls: false,
            contextWindow: nil,
            experimentalSupportedTools: []
        )

        let preset = info.preset
        XCTAssertEqual(preset.id, "gpt-5")
        XCTAssertEqual(preset.model, "gpt-5")
        XCTAssertEqual(preset.displayName, "GPT-5")
        XCTAssertEqual(preset.description, "")
        XCTAssertEqual(preset.defaultReasoningEffort, .medium)
        XCTAssertEqual(preset.supportedReasoningEfforts, info.supportedReasoningLevels)
        XCTAssertFalse(preset.supportsPersonality)
        XCTAssertEqual(preset.serviceTiers, info.serviceTiers)
        XCTAssertEqual(preset.availabilityNux, ModelAvailabilityNux(message: "Try it."))
        XCTAssertTrue(preset.supportsFastMode())
        XCTAssertFalse(preset.isDefault)
        XCTAssertTrue(preset.showInPicker)
        XCTAssertTrue(preset.supportedInAPI)
        XCTAssertEqual(preset.upgrade?.id, "gpt-5.1")
        XCTAssertEqual(preset.upgrade?.migrationConfigKey, "gpt-5")
        XCTAssertNil(preset.upgrade?.modelLink)
        XCTAssertNil(preset.upgrade?.upgradeCopy)
        XCTAssertEqual(preset.upgrade?.migrationMarkdown, "Move to GPT-5.1.")
        XCTAssertEqual(preset.upgrade?.reasoningEffortMapping, [
            .none: .low,
            .minimal: .low,
            .low: .low,
            .medium: .low,
            .high: .high,
            .xhigh: .high
        ])

        try XCTAssertJSONObjectEqual(preset, [
            "id": "gpt-5",
            "model": "gpt-5",
            "display_name": "GPT-5",
            "description": "",
            "default_reasoning_effort": "medium",
            "supported_reasoning_efforts": [
                [
                    "effort": "low",
                    "description": "Quick"
                ],
                [
                    "effort": "high",
                    "description": "Deep"
                ]
            ],
            "supports_personality": false,
            "additional_speed_tiers": [],
            "service_tiers": [
                [
                    "id": "priority",
                    "name": "Fast",
                    "description": "Priority processing."
                ]
            ],
            "is_default": false,
            "upgrade": [
                "id": "gpt-5.1",
                "reasoning_effort_mapping": [
                    "none": "low",
                    "minimal": "low",
                    "low": "low",
                    "medium": "low",
                    "high": "high",
                    "xhigh": "high"
                ],
                "migration_config_key": "gpt-5",
                "model_link": NSNull(),
                "upgrade_copy": NSNull(),
                "migration_markdown": "Move to GPT-5.1."
            ],
            "show_in_picker": true,
            "availability_nux": [
                "message": "Try it."
            ],
            "supported_in_api": true,
            "input_modalities": ["text", "image"]
        ])
    }

    func testModelPresetSupportsFastModeFromLegacyAdditionalSpeedTiers() {
        let preset = ModelPreset(
            id: "legacy-fast",
            model: "legacy-fast",
            displayName: "Legacy Fast",
            description: "",
            defaultReasoningEffort: .medium,
            supportedReasoningEfforts: [],
            additionalSpeedTiers: ["fast"],
            isDefault: false,
            showInPicker: true,
            supportedInAPI: true
        )

        XCTAssertTrue(preset.supportsFastMode())
    }

    private func minimalModelInfo() -> ModelInfo {
        ModelInfo(
            slug: "codex-mini",
            displayName: "Codex Mini",
            description: "Small",
            defaultReasoningLevel: .low,
            supportedReasoningLevels: [],
            shellType: .default,
            visibility: .hide,
            supportedInAPI: false,
            priority: 5,
            upgrade: nil,
            baseInstructions: "base",
            supportsReasoningSummaries: false,
            supportVerbosity: false,
            defaultVerbosity: nil,
            applyPatchToolType: nil,
            truncationPolicy: .bytes(4096),
            supportsParallelToolCalls: false,
            contextWindow: nil,
            experimentalSupportedTools: []
        )
    }

    private func encode<T: Encodable>(_ value: T) throws -> String {
        String(data: try JSONEncoder().encode(value), encoding: .utf8) ?? ""
    }
}
