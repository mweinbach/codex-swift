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
