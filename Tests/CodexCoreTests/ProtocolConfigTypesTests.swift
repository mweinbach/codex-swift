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
        XCTAssertEqual(try encode(SandboxMode.workspaceWrite), #""workspace-write""#)
        XCTAssertEqual(try encode(AskForApproval.unlessTrusted), #""untrusted""#)
    }

    private func encode<T: Encodable>(_ value: T) throws -> String {
        String(data: try JSONEncoder().encode(value), encoding: .utf8)!
    }
}
