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
                sandboxMode: .workspaceWrite,
                modelReasoningEffort: .high,
                modelReasoningSummary: .detailed,
                modelVerbosity: .medium,
                serviceTier: "priority",
                chatgptBaseURL: "https://chatgpt.example/backend-api/",
                experimentalInstructionsFile: "/repo/instructions.md",
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
                features: FeaturesToml(entries: ["skills": true]),
                ossProvider: "ollama"
            ),
            [
                "model": "gpt-5.4",
                "model_provider": "openai",
                "approval_policy": "on-request",
                "sandbox_mode": "workspace-write",
                "model_reasoning_effort": "high",
                "model_reasoning_summary": "detailed",
                "model_verbosity": "medium",
                "service_tier": "priority",
                "chatgpt_base_url": "https://chatgpt.example/backend-api/",
                "experimental_instructions_file": "/repo/instructions.md",
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
                "sandbox_mode": NSNull(),
                "model_reasoning_effort": NSNull(),
                "model_reasoning_summary": NSNull(),
                "model_verbosity": NSNull(),
                "service_tier": NSNull(),
                "chatgpt_base_url": NSNull(),
                "experimental_instructions_file": NSNull(),
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
                "features": NSNull(),
                "oss_provider": NSNull()
            ]
        )
    }

    func testConfigProfileDecodesMissingFieldsAsNil() throws {
        let profile = try JSONDecoder().decode(ConfigProfile.self, from: Data("""
        {
          "model": "gpt-5.4",
          "features": {
            "skills": true,
            "web_search_request": false
          }
        }
        """.utf8))

        XCTAssertEqual(profile.model, "gpt-5.4")
        XCTAssertEqual(profile.modelProvider, nil)
        XCTAssertEqual(profile.features, FeaturesToml(entries: [
            "skills": true,
            "web_search_request": false
        ]))
    }

    func testAppServerProfileConversionKeepsOnlyRustForwardedFields() throws {
        let profile = ConfigProfile(
            model: "gpt-5.4",
            modelProvider: "openai",
            approvalPolicy: .unlessTrusted,
            sandboxMode: .dangerFullAccess,
            modelReasoningEffort: .medium,
            modelReasoningSummary: .concise,
            modelVerbosity: .high,
            serviceTier: "flex",
            chatgptBaseURL: "https://chatgpt.example/backend-api/",
            includeApplyPatchTool: true,
            toolsWebSearch: true,
            features: FeaturesToml(entries: ["skills": false]),
            ossProvider: "ollama"
        )

        let appServerProfile = profile.appServerProfile()
        XCTAssertEqual(appServerProfile, AppServerProfile(
            model: "gpt-5.4",
            modelProvider: "openai",
            approvalPolicy: .unlessTrusted,
            modelReasoningEffort: .medium,
            modelReasoningSummary: .concise,
            modelVerbosity: .high,
            chatgptBaseURL: "https://chatgpt.example/backend-api/"
        ))

        try XCTAssertJSONObjectEqual(appServerProfile, [
            "model": "gpt-5.4",
            "modelProvider": "openai",
            "approvalPolicy": "untrusted",
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
                "modelReasoningEffort": NSNull(),
                "modelReasoningSummary": NSNull(),
                "modelVerbosity": NSNull(),
                "chatgptBaseURL": NSNull()
            ]
        )
    }
}
