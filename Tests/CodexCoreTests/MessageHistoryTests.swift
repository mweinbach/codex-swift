import XCTest
@testable import CodexCore

final class MessageHistoryTests: XCTestCase {
    func testHistoryEntryWireShape() throws {
        let entry = HistoryEntry(
            conversationID: "018f7a2d-4c5b-7abc-8def-0123456789ab",
            ts: 1_717_171_717,
            text: "hello"
        )

        try XCTAssertJSONObjectEqual(entry, [
            "conversation_id": "018f7a2d-4c5b-7abc-8def-0123456789ab",
            "ts": 1_717_171_717,
            "text": "hello"
        ])

        let data = try JSONEncoder().encode(entry)
        XCTAssertEqual(try JSONDecoder().decode(HistoryEntry.self, from: data), entry)
    }
}
