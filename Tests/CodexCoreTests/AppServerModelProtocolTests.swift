import CodexCore
import XCTest

final class AppServerModelProtocolTests: XCTestCase {
    func testModelListParamsEncodeExplicitNullOptionalsLikeRustProtocol() throws {
        try XCTAssertJSONObjectEqual(ModelListParams(), [
            "cursor": NSNull(),
            "limit": NSNull(),
            "includeHidden": NSNull()
        ])

        try XCTAssertJSONObjectEqual(
            ModelListParams(cursor: "2", limit: 25, includeHidden: false),
            [
                "cursor": "2",
                "limit": 25,
                "includeHidden": false
            ]
        )

        let decoded = try JSONDecoder().decode(
            ModelListParams.self,
            from: Data(#"{"cursor":null,"limit":null,"includeHidden":null}"#.utf8)
        )
        XCTAssertNil(decoded.cursor)
        XCTAssertNil(decoded.limit)
        XCTAssertNil(decoded.includeHidden)
    }

    func testModelPayloadsEncodeRustV2Shape() throws {
        let model = Model(
            id: "gpt-test",
            model: "gpt-test",
            upgrade: "gpt-next",
            upgradeInfo: ModelUpgradeInfo(
                model: "gpt-next",
                upgradeCopy: nil,
                modelLink: "https://example.test/model",
                migrationMarkdown: nil
            ),
            availabilityNux: ModelAvailabilityNux(message: "Try this model."),
            displayName: "GPT Test",
            description: "A test model.",
            hidden: false,
            supportedReasoningEfforts: [
                ReasoningEffortOption(reasoningEffort: .low, description: "Fast"),
                ReasoningEffortOption(reasoningEffort: .high, description: "Deep")
            ],
            defaultReasoningEffort: .medium,
            inputModalities: [.text, .image],
            supportsPersonality: true,
            additionalSpeedTiers: ["fast"],
            serviceTiers: [
                ModelServiceTier(id: "priority", name: "Priority", description: "Faster responses")
            ],
            isDefault: true
        )

        try XCTAssertJSONObjectEqual(model, [
            "id": "gpt-test",
            "model": "gpt-test",
            "upgrade": "gpt-next",
            "upgradeInfo": [
                "model": "gpt-next",
                "upgradeCopy": NSNull(),
                "modelLink": "https://example.test/model",
                "migrationMarkdown": NSNull()
            ],
            "availabilityNux": [
                "message": "Try this model."
            ],
            "displayName": "GPT Test",
            "description": "A test model.",
            "hidden": false,
            "supportedReasoningEfforts": [
                [
                    "reasoningEffort": "low",
                    "description": "Fast"
                ],
                [
                    "reasoningEffort": "high",
                    "description": "Deep"
                ]
            ],
            "defaultReasoningEffort": "medium",
            "inputModalities": ["text", "image"],
            "supportsPersonality": true,
            "additionalSpeedTiers": ["fast"],
            "serviceTiers": [
                [
                    "id": "priority",
                    "name": "Priority",
                    "description": "Faster responses"
                ]
            ],
            "isDefault": true
        ])

        try XCTAssertJSONObjectEqual(
            ModelListResponse(data: [model], nextCursor: nil),
            [
                "data": [[
                    "id": "gpt-test",
                    "model": "gpt-test",
                    "upgrade": "gpt-next",
                    "upgradeInfo": [
                        "model": "gpt-next",
                        "upgradeCopy": NSNull(),
                        "modelLink": "https://example.test/model",
                        "migrationMarkdown": NSNull()
                    ],
                    "availabilityNux": [
                        "message": "Try this model."
                    ],
                    "displayName": "GPT Test",
                    "description": "A test model.",
                    "hidden": false,
                    "supportedReasoningEfforts": [
                        [
                            "reasoningEffort": "low",
                            "description": "Fast"
                        ],
                        [
                            "reasoningEffort": "high",
                            "description": "Deep"
                        ]
                    ],
                    "defaultReasoningEffort": "medium",
                    "inputModalities": ["text", "image"],
                    "supportsPersonality": true,
                    "additionalSpeedTiers": ["fast"],
                    "serviceTiers": [
                        [
                            "id": "priority",
                            "name": "Priority",
                            "description": "Faster responses"
                        ]
                    ],
                    "isDefault": true
                ]],
                "nextCursor": NSNull()
            ]
        )
    }

    func testModelPayloadsConvertFromCoreModelPreset() throws {
        let preset = ModelPreset(
            id: "gpt-old",
            model: "gpt-old",
            displayName: "GPT Old",
            description: "Legacy model.",
            defaultReasoningEffort: .medium,
            supportedReasoningEfforts: [
                ReasoningEffortPreset(effort: .low, description: "Fast")
            ],
            supportsPersonality: false,
            additionalSpeedTiers: [],
            serviceTiers: [],
            isDefault: false,
            upgrade: ModelUpgrade(
                id: "gpt-new",
                migrationConfigKey: "gpt-old",
                upgradeCopy: "Use the new model",
                migrationMarkdown: "Migration notes"
            ),
            showInPicker: false,
            availabilityNux: nil,
            supportedInAPI: true,
            inputModalities: [.text]
        )

        try XCTAssertJSONObjectEqual(Model(core: preset), [
            "id": "gpt-old",
            "model": "gpt-old",
            "upgrade": "gpt-new",
            "upgradeInfo": [
                "model": "gpt-new",
                "upgradeCopy": "Use the new model",
                "modelLink": NSNull(),
                "migrationMarkdown": "Migration notes"
            ],
            "availabilityNux": NSNull(),
            "displayName": "GPT Old",
            "description": "Legacy model.",
            "hidden": true,
            "supportedReasoningEfforts": [
                [
                    "reasoningEffort": "low",
                    "description": "Fast"
                ]
            ],
            "defaultReasoningEffort": "medium",
            "inputModalities": ["text"],
            "supportsPersonality": false,
            "additionalSpeedTiers": [],
            "serviceTiers": [],
            "isDefault": false
        ])
    }

    func testModelDecodeAppliesRustSerdeDefaults() throws {
        let decoded = try JSONDecoder().decode(
            Model.self,
            from: Data(
                #"""
                {
                  "id": "gpt-test",
                  "model": "gpt-test",
                  "upgrade": null,
                  "upgradeInfo": null,
                  "availabilityNux": null,
                  "displayName": "GPT Test",
                  "description": "A test model.",
                  "hidden": false,
                  "supportedReasoningEfforts": [],
                  "defaultReasoningEffort": "none",
                  "isDefault": false
                }
                """#.utf8
            )
        )

        XCTAssertEqual(decoded.inputModalities, [.text, .image])
        XCTAssertFalse(decoded.supportsPersonality)
        XCTAssertEqual(decoded.additionalSpeedTiers, [])
        XCTAssertEqual(decoded.serviceTiers, [])
    }

    func testModelProviderCapabilitiesPayloadsEncodeRustWireShape() throws {
        try XCTAssertJSONObjectEqual(ModelProviderCapabilitiesReadParams(), [:])
        try XCTAssertJSONObjectEqual(
            ModelProviderCapabilitiesReadResponse(
                core: ModelProviderCapabilities(namespaceTools: false, imageGeneration: true, webSearch: false)
            ),
            [
                "namespaceTools": false,
                "imageGeneration": true,
                "webSearch": false
            ]
        )
    }

    func testModelNotificationsUseRustV2EnumSpelling() throws {
        try XCTAssertJSONObjectEqual(
            ModelReroutedNotification(
                threadID: "thread-1",
                turnID: "turn-1",
                core: ModelRerouteEvent(
                    fromModel: "gpt-a",
                    toModel: "gpt-b",
                    reason: .highRiskCyberActivity
                )
            ),
            [
                "threadId": "thread-1",
                "turnId": "turn-1",
                "fromModel": "gpt-a",
                "toModel": "gpt-b",
                "reason": "highRiskCyberActivity"
            ]
        )

        try XCTAssertJSONObjectEqual(
            ModelVerificationNotification(
                threadID: "thread-1",
                turnID: "turn-1",
                core: ModelVerificationEvent(verifications: [.trustedAccessForCyber])
            ),
            [
                "threadId": "thread-1",
                "turnId": "turn-1",
                "verifications": ["trustedAccessForCyber"]
            ]
        )
    }
}
