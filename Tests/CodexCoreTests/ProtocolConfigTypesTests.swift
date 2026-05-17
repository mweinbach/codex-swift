import CodexCore
import XCTest

final class ProtocolConfigTypesTests: XCTestCase {
    func testConfigEnumsUseRustWireValues() throws {
        XCTAssertEqual(try encode(ReasoningSummary.detailed), #""detailed""#)
        XCTAssertEqual(try encode(ReasoningSummary.none), #""none""#)
        XCTAssertEqual(try encode(ReasoningEffort.minimal), #""minimal""#)
        XCTAssertEqual(try encode(ReasoningEffort.xhigh), #""xhigh""#)
        XCTAssertEqual(try encode(Verbosity.medium), #""medium""#)
        XCTAssertEqual(try encode(ServiceTier.fast), #""fast""#)
        XCTAssertEqual(ServiceTier.fast.requestValue, "priority")
        XCTAssertEqual(ServiceTier.flex.requestValue, "flex")
        XCTAssertEqual(ServiceTier.fromRequestValue("fast"), .fast)
        XCTAssertEqual(ServiceTier.fromRequestValue("priority"), .fast)
        XCTAssertEqual(ServiceTier.fromRequestValue("flex"), .flex)
        XCTAssertNil(ServiceTier.fromRequestValue("slow"))
        XCTAssertEqual(try encode(WireAPI.responses), #""responses""#)
        XCTAssertEqual(try encode(WireAPI.chat), #""chat""#)
        XCTAssertEqual(try encode(WireAPI.compact), #""compact""#)
        XCTAssertEqual(try encode(ForcedLoginMethod.chatgpt), #""chatgpt""#)
        XCTAssertEqual(try encode(TrustLevel.untrusted), #""untrusted""#)
        XCTAssertEqual(try encode(CollaborationModeKind.plan), #""plan""#)
        XCTAssertEqual(try encode(CollaborationModeKind.defaultMode), #""default""#)
        XCTAssertEqual(try encode(SandboxMode.workspaceWrite), #""workspace-write""#)
        XCTAssertEqual(try encode(AskForApproval.unlessTrusted), #""untrusted""#)
    }

    func testGranularApprovalConfigMatchesRustWireShapeAndDefaults() throws {
        let config = GranularApprovalConfig(
            sandboxApproval: true,
            rules: false,
            skillApproval: true,
            requestPermissions: true,
            mcpElicitations: false
        )

        try XCTAssertJSONObjectEqual(AskForApproval.granular(config), [
            "granular": [
                "sandbox_approval": true,
                "rules": false,
                "skill_approval": true,
                "request_permissions": true,
                "mcp_elicitations": false
            ]
        ])
        XCTAssertEqual(AskForApproval.granular(config).rawValue, "granular")
        XCTAssertTrue(config.allowsSandboxApproval)
        XCTAssertFalse(config.allowsRulesApproval)
        XCTAssertTrue(config.allowsSkillApproval)
        XCTAssertTrue(config.allowsRequestPermissions)
        XCTAssertFalse(config.allowsMcpElicitations)

        let decoded = try JSONDecoder().decode(GranularApprovalConfig.self, from: Data(#"""
        {
          "sandbox_approval": true,
          "rules": false,
          "mcp_elicitations": true
        }
        """#.utf8))
        XCTAssertEqual(decoded, GranularApprovalConfig(
            sandboxApproval: true,
            rules: false,
            skillApproval: false,
            requestPermissions: false,
            mcpElicitations: true
        ))

        let mode = try JSONDecoder().decode(AskForApproval.self, from: Data(#"""
        {
          "granular": {
            "sandbox_approval": false,
            "rules": true,
            "mcp_elicitations": true
          }
        }
        """#.utf8))
        XCTAssertEqual(mode, .granular(GranularApprovalConfig(
            sandboxApproval: false,
            rules: true,
            mcpElicitations: true
        )))
    }

    func testGranularApprovalConfigRejectsNullForRustDefaultedFlags() {
        XCTAssertThrowsError(try JSONDecoder().decode(
            GranularApprovalConfig.self,
            from: Data(#"{"sandbox_approval":true,"rules":true,"skill_approval":null,"mcp_elicitations":true}"#.utf8)
        ))
        XCTAssertThrowsError(try JSONDecoder().decode(
            GranularApprovalConfig.self,
            from: Data(#"{"sandbox_approval":true,"rules":true,"request_permissions":null,"mcp_elicitations":true}"#.utf8)
        ))
    }

    func testGranularApprovalPolicyReportsRustExperimentalReason() {
        XCTAssertEqual(
            AskForApproval.granular(GranularApprovalConfig(
                sandboxApproval: true,
                rules: false,
                requestPermissions: true,
                mcpElicitations: false
            )).appServerExperimentalReason,
            "askForApproval.granular"
        )
        XCTAssertNil(AskForApproval.onRequest.appServerExperimentalReason)
    }

    func testCollaborationModeKindAliasesMatchRustDefaults() throws {
        let decoder = JSONDecoder()
        for alias in ["default", "code", "pair_programming", "execute", "custom"] {
            let data = Data("\"\(alias)\"".utf8)
            XCTAssertEqual(try decoder.decode(CollaborationModeKind.self, from: data), .defaultMode)
        }
        XCTAssertEqual(try decoder.decode(CollaborationModeKind.self, from: Data(#""plan""#.utf8)), .plan)
    }

    func testBuiltinCollaborationModePresetsMatchRustOrder() {
        XCTAssertEqual(CollaborationModeRegistry.tuiVisibleModes, [.defaultMode, .plan])
        XCTAssertEqual(CollaborationModeRegistry.builtinPresets, [
            CollaborationModeMask(name: "Plan", mode: .plan, reasoningEffort: .medium),
            CollaborationModeMask(name: "Default", mode: .defaultMode)
        ])
    }

    func testBuiltinCollaborationModeDeveloperInstructionsMatchRustTemplates() throws {
        let defaultInstructions = try XCTUnwrap(
            CollaborationModeRegistry.builtinDeveloperInstructions(for: .defaultMode)
        )
        XCTAssertFalse(defaultInstructions.contains("{{KNOWN_MODE_NAMES}}"))
        XCTAssertTrue(defaultInstructions.contains("Known mode names are Default and Plan."))
        XCTAssertTrue(defaultInstructions.contains(
            "Use the `request_user_input` tool only when it is listed in the available tools"
        ))
        XCTAssertTrue(defaultInstructions.contains(
            "ask the user directly with a concise plain-text question"
        ))

        let planInstructions = try XCTUnwrap(
            CollaborationModeRegistry.builtinDeveloperInstructions(for: .plan)
        )
        XCTAssertTrue(planInstructions.contains("# Plan Mode (Conversational)"))
    }

    func testCollaborationModeMaskCanClearOptionalFieldsLikeRust() {
        let mode = CollaborationMode(
            mode: .defaultMode,
            settings: CollaborationModeSettings(
                model: "gpt-5.2-codex",
                reasoningEffort: .high,
                developerInstructions: "stay focused"
            )
        )
        let mask = CollaborationModeMask(
            name: "Clear",
            reasoningEffort: .clear,
            developerInstructions: .clear
        )

        XCTAssertEqual(mode.applying(mask), CollaborationMode(
            mode: .defaultMode,
            settings: CollaborationModeSettings(model: "gpt-5.2-codex")
        ))
    }

    func testCollaborationModeMaskDecodeDistinguishesMissingNullAndValuesLikeRust() throws {
        let missing = try JSONDecoder().decode(CollaborationModeMask.self, from: Data(#"""
        {
          "name": "Keep"
        }
        """#.utf8))
        XCTAssertEqual(missing.reasoningEffort, .preserve)
        XCTAssertEqual(missing.developerInstructions, .preserve)

        let clearing = try JSONDecoder().decode(CollaborationModeMask.self, from: Data(#"""
        {
          "name": "Clear",
          "reasoning_effort": null,
          "developer_instructions": null
        }
        """#.utf8))
        XCTAssertEqual(clearing.reasoningEffort, .clear)
        XCTAssertEqual(clearing.developerInstructions, .clear)

        let setting = try JSONDecoder().decode(CollaborationModeMask.self, from: Data(#"""
        {
          "name": "Set",
          "mode": "plan",
          "model": "gpt-5.4",
          "reasoning_effort": "medium",
          "developer_instructions": "plan first"
        }
        """#.utf8))
        XCTAssertEqual(setting.mode, .plan)
        XCTAssertEqual(setting.model, "gpt-5.4")
        XCTAssertEqual(setting.reasoningEffort, .set(.medium))
        XCTAssertEqual(setting.developerInstructions, .set("plan first"))
    }

    func testCollaborationModeMaskEncodesRustWireShape() throws {
        let mask = CollaborationModeMask(
            name: "Set",
            mode: .plan,
            model: "gpt-5.4",
            reasoningEffort: .set(.medium),
            developerInstructions: .clear
        )

        try XCTAssertJSONObjectEqual(mask, [
            "name": "Set",
            "mode": "plan",
            "model": "gpt-5.4",
            "reasoning_effort": "medium",
            "developer_instructions": NSNull()
        ])
    }

    private func encode<T: Encodable>(_ value: T) throws -> String {
        String(data: try JSONEncoder().encode(value), encoding: .utf8)!
    }
}
