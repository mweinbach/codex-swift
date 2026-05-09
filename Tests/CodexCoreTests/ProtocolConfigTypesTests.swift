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

    private func encode<T: Encodable>(_ value: T) throws -> String {
        String(data: try JSONEncoder().encode(value), encoding: .utf8)!
    }
}
