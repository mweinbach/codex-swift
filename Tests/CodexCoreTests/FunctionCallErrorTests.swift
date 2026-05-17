import CodexCore
import XCTest

final class FunctionCallErrorTests: XCTestCase {
    func testDescriptionsMatchRustThisErrorMessages() {
        XCTAssertEqual(FunctionCallError.respondToModel("ask user").description, "ask user")
        XCTAssertEqual(FunctionCallError.fatal("boom").description, "Fatal error: boom")
    }
}
