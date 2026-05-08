import CodexCore
import XCTest

final class ConversationIdTests: XCTestCase {
    func testDefaultConversationIdIsNotZeroesAndIsVersion7() {
        let id = ConversationId()
        XCTAssertNotEqual(id.description, "00000000-0000-0000-0000-000000000000")
        let versionCharacter = Array(id.description)[14]
        XCTAssertEqual(versionCharacter, "7")
    }

    func testConversationIdCodableAsString() throws {
        let id = try ConversationId(string: "018f7a2d-4c5b-7abc-8def-0123456789ab")
        let encoded = try String(data: JSONEncoder().encode(id), encoding: .utf8)
        XCTAssertEqual(encoded, #""018f7a2d-4c5b-7abc-8def-0123456789ab""#)
        XCTAssertEqual(try JSONDecoder().decode(ConversationId.self, from: Data(encoded!.utf8)), id)
    }
}
