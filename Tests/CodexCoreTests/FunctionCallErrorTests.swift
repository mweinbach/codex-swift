import CodexCore
import XCTest

final class FunctionCallErrorTests: XCTestCase {
    func testDescriptionsMatchRustThisErrorMessages() {
        XCTAssertEqual(FunctionCallError.respondToModel("ask user").description, "ask user")
        XCTAssertEqual(FunctionCallError.denied("denied").description, "denied")
        XCTAssertEqual(
            FunctionCallError.missingLocalShellCallID.description,
            "LocalShellCall without call_id or id"
        )
        XCTAssertEqual(FunctionCallError.fatal("boom").description, "Fatal error: boom")
    }
}
