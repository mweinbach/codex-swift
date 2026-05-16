import XCTest
@testable import CodexCore

final class ConfigProfileTests: XCTestCase {
    func testFeaturesTomlFlattensEntries() throws {
        try XCTAssertJSONObjectEqual(
            FeaturesToml(entries: [
                "web_search_request": true,
                "skills": false
            ]),
            [
                "web_search_request": true,
                "skills": false
            ]
        )
    }

    func testConfigProfileWireShapeUsesSnakeCaseAndNullOptionals() throws {
        try XCTAssertJSONObjectEqual(
            ConfigProfile(
                model: "gpt-5.4",
                modelProvider: "openai",
                approvalPolicy: .onRequest,
                approvalsReviewer: .autoReview,
                sandboxMode: .workspaceWrite,
                modelReasoningEffort: .high,
                planModeReasoningEffort: .low,
                modelReasoningSummary: .detailed,
                modelVerbosity: .medium,
                serviceTier: "priority",
                modelCatalogJSON: "/repo/models.json",
                personality: .friendly,
                chatgptBaseURL: "https://chatgpt.example/backend-api/",
                modelInstructionsFile: "/repo/model.md",
                jsReplNodePath: "/usr/local/bin/node",
                jsReplNodeModuleDirs: ["/repo/node_modules"],
                zshPath: "/usr/local/bin/zsh",
                experimentalCompactPromptFile: "/repo/compact.md",
                includePermissionsInstructions: true,
                includeAppsInstructions: false,
                includeEnvironmentContext: true,
                includeApplyPatchTool: true,
                experimentalUseUnifiedExecTool: false,
                experimentalUseFreeformApplyPatch: true,
                webSearchMode: .cached,
                toolsWebSearch: true,
                toolsViewImage: false,
                tools: ConfigProfileTools(
                    webSearch: AppServerProtocol.WebSearchToolConfig(
                        contextSize: .low,
                        allowedDomains: ["openai.com"],
                        location: AppServerProtocol.WebSearchLocation(country: "US")
                    ),
                    viewImage: true
                ),
                analytics: ConfigProfileAnalytics(enabled: false),
                tui: ConfigProfileTui(sessionPickerView: .comfortable),
                windows: ConfigProfileWindows(sandbox: .unelevated, sandboxPrivateDesktop: false),
                features: FeaturesToml(entries: ["skills": true]),
                ossProvider: "ollama"
            ),
            [
                "model": "gpt-5.4",
                "model_provider": "openai",
                "approval_policy": "on-request",
                "approvals_reviewer": "guardian_subagent",
                "sandbox_mode": "workspace-write",
                "model_reasoning_effort": "high",
                "plan_mode_reasoning_effort": "low",
                "model_reasoning_summary": "detailed",
                "model_verbosity": "medium",
                "service_tier": "priority",
                "model_catalog_json": "/repo/models.json",
                "personality": "friendly",
                "chatgpt_base_url": "https://chatgpt.example/backend-api/",
                "model_instructions_file": "/repo/model.md",
                "js_repl_node_path": "/usr/local/bin/node",
                "js_repl_node_module_dirs": ["/repo/node_modules"],
                "zsh_path": "/usr/local/bin/zsh",
                "experimental_compact_prompt_file": "/repo/compact.md",
                "include_permissions_instructions": true,
                "include_apps_instructions": false,
                "include_environment_context": true,
                "include_apply_patch_tool": true,
                "experimental_use_unified_exec_tool": false,
                "experimental_use_freeform_apply_patch": true,
                "web_search": "cached",
                "tools_web_search": true,
                "tools_view_image": false,
                "tools": [
                    "web_search": [
                        "context_size": "low",
                        "allowed_domains": ["openai.com"],
                        "location": [
                            "country": "US",
                            "region": NSNull(),
                            "city": NSNull(),
                            "timezone": NSNull()
                        ]
                    ],
                    "view_image": true
                ],
                "analytics": ["enabled": false],
                "tui": ["session_picker_view": "comfortable"],
                "windows": [
                    "sandbox": "unelevated",
                    "sandbox_private_desktop": false
                ],
                "features": ["skills": true],
                "oss_provider": "ollama"
            ]
        )

        try XCTAssertJSONObjectEqual(
            ConfigProfile(model: "gpt-5.4"),
            [
                "model": "gpt-5.4",
                "model_provider": NSNull(),
                "approval_policy": NSNull(),
                "approvals_reviewer": NSNull(),
                "sandbox_mode": NSNull(),
                "model_reasoning_effort": NSNull(),
                "plan_mode_reasoning_effort": NSNull(),
                "model_reasoning_summary": NSNull(),
                "model_verbosity": NSNull(),
                "service_tier": NSNull(),
                "model_catalog_json": NSNull(),
                "personality": NSNull(),
                "chatgpt_base_url": NSNull(),
                "model_instructions_file": NSNull(),
                "js_repl_node_path": NSNull(),
                "js_repl_node_module_dirs": NSNull(),
                "zsh_path": NSNull(),
                "experimental_compact_prompt_file": NSNull(),
                "include_permissions_instructions": NSNull(),
                "include_apps_instructions": NSNull(),
                "include_environment_context": NSNull(),
                "include_apply_patch_tool": NSNull(),
                "experimental_use_unified_exec_tool": NSNull(),
                "experimental_use_freeform_apply_patch": NSNull(),
                "web_search": NSNull(),
                "tools_web_search": NSNull(),
                "tools_view_image": NSNull(),
                "tools": NSNull(),
                "analytics": NSNull(),
                "tui": NSNull(),
                "windows": NSNull(),
                "features": NSNull(),
                "oss_provider": NSNull()
            ]
        )
    }

    func testConfigProfileDecodesMissingFieldsAsNil() throws {
        let profile = try JSONDecoder().decode(ConfigProfile.self, from: Data("""
        {
          "model": "gpt-5.4",
          "model_catalog_json": "/repo/models.json",
          "personality": "pragmatic",
          "model_instructions_file": "/repo/model.md",
          "js_repl_node_path": "/usr/local/bin/node",
          "js_repl_node_module_dirs": ["/repo/node_modules"],
          "zsh_path": "/usr/local/bin/zsh",
          "tools": {
            "web_search": true,
            "view_image": false
          },
          "analytics": {
            "enabled": true
          },
          "tui": {
            "session_picker_view": "dense"
          },
          "windows": {
            "sandbox": "elevated",
            "sandbox_private_desktop": true
          },
          "features": {
            "skills": true,
            "web_search_request": false
          }
        }
        """.utf8))

        XCTAssertEqual(profile.model, "gpt-5.4")
        XCTAssertEqual(profile.modelProvider, nil)
        XCTAssertEqual(profile.modelCatalogJSON, "/repo/models.json")
        XCTAssertEqual(profile.personality, .pragmatic)
        XCTAssertEqual(profile.modelInstructionsFile, "/repo/model.md")
        XCTAssertEqual(profile.jsReplNodePath, "/usr/local/bin/node")
        XCTAssertEqual(profile.jsReplNodeModuleDirs, ["/repo/node_modules"])
        XCTAssertEqual(profile.zshPath, "/usr/local/bin/zsh")
        XCTAssertEqual(profile.tools, ConfigProfileTools(webSearch: nil, viewImage: false))
        XCTAssertEqual(profile.analytics, ConfigProfileAnalytics(enabled: true))
        XCTAssertEqual(profile.tui, ConfigProfileTui(sessionPickerView: .dense))
        XCTAssertEqual(profile.windows, ConfigProfileWindows(sandbox: .elevated, sandboxPrivateDesktop: true))
        XCTAssertEqual(profile.features, FeaturesToml(entries: [
            "skills": true,
            "web_search_request": false
        ]))
    }

    func testConfigProfileRejectsUnknownFieldsLikeRustDenyUnknownFields() {
        XCTAssertThrowsError(
            try JSONDecoder().decode(ConfigProfile.self, from: Data("""
            {
              "model": "gpt-5.4",
              "modell": "typo"
            }
            """.utf8))
        ) { error in
            let decodingError = error as? DecodingError
            guard case let .dataCorrupted(context)? = decodingError else {
                return XCTFail("expected dataCorrupted error, got \(error)")
            }
            XCTAssertEqual(context.debugDescription, "Unknown field 'modell'")
        }
    }

    func testConfigProfileRejectsUnknownNestedTableFieldsLikeRustDenyUnknownFields() {
        XCTAssertThrowsError(
            try JSONDecoder().decode(ConfigProfile.self, from: Data("""
            {
              "model": "gpt-5.4",
              "tui": {
                "session_picker_view": "dense",
                "theme": "unsupported-here"
              }
            }
            """.utf8))
        ) { error in
            let decodingError = error as? DecodingError
            guard case let .dataCorrupted(context)? = decodingError else {
                return XCTFail("expected dataCorrupted error, got \(error)")
            }
            XCTAssertEqual(context.debugDescription, "Unknown field 'theme'")
        }
    }

    func testAppServerProfileConversionKeepsOnlyRustForwardedFields() throws {
        let profile = ConfigProfile(
            model: "gpt-5.4",
            modelProvider: "openai",
            approvalPolicy: .unlessTrusted,
            approvalsReviewer: .autoReview,
            sandboxMode: .dangerFullAccess,
            modelReasoningEffort: .medium,
            planModeReasoningEffort: .high,
            modelReasoningSummary: .concise,
            modelVerbosity: .high,
            serviceTier: "flex",
            chatgptBaseURL: "https://chatgpt.example/backend-api/",
            modelInstructionsFile: "/repo/model.md",
            zshPath: "/usr/local/bin/zsh",
            includeApplyPatchTool: true,
            toolsWebSearch: true,
            analytics: ConfigProfileAnalytics(enabled: true),
            features: FeaturesToml(entries: ["skills": false]),
            ossProvider: "ollama"
        )

        let appServerProfile = profile.appServerProfile()
        XCTAssertEqual(appServerProfile, AppServerProfile(
            model: "gpt-5.4",
            modelProvider: "openai",
            approvalPolicy: .unlessTrusted,
            approvalsReviewer: .autoReview,
            modelReasoningEffort: .medium,
            modelReasoningSummary: .concise,
            modelVerbosity: .high,
            chatgptBaseURL: "https://chatgpt.example/backend-api/"
        ))

        try XCTAssertJSONObjectEqual(appServerProfile, [
            "model": "gpt-5.4",
            "modelProvider": "openai",
            "approvalPolicy": "untrusted",
            "approvalsReviewer": "guardian_subagent",
            "modelReasoningEffort": "medium",
            "modelReasoningSummary": "concise",
            "modelVerbosity": "high",
            "chatgptBaseURL": "https://chatgpt.example/backend-api/"
        ])
    }

    func testAppServerProfileSerializesNilValuesAsNull() throws {
        try XCTAssertJSONObjectEqual(
            AppServerProfile(model: "gpt-5.4"),
            [
                "model": "gpt-5.4",
                "modelProvider": NSNull(),
                "approvalPolicy": NSNull(),
                "approvalsReviewer": NSNull(),
                "modelReasoningEffort": NSNull(),
                "modelReasoningSummary": NSNull(),
                "modelVerbosity": NSNull(),
                "chatgptBaseURL": NSNull()
            ]
        )
    }
}
