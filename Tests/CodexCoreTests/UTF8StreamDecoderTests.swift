import CodexCore
import XCTest

final class UTF8StreamDecoderTests: XCTestCase {
    func testBuffersIncompleteMultibyteSequenceAcrossChunks() throws {
        var decoder = UTF8StreamDecoder()
        let bytes = Array("a\u{1F30A}b".utf8)

        XCTAssertEqual(decoder.receive(Data(bytes.prefix(2))), "a")
        XCTAssertEqual(decoder.receive(Data(bytes.dropFirst(2).prefix(2))), "")
        XCTAssertEqual(decoder.receive(Data(bytes.dropFirst(4))), "\u{1F30A}b")
        XCTAssertEqual(try decoder.finish(), "")
    }

    func testFinishReportsIncompleteUTF8LikeRustEventsourceStream() {
        var decoder = UTF8StreamDecoder()

        XCTAssertEqual(decoder.receive(Data([0xF0, 0x9F])), "")
        XCTAssertThrowsError(try decoder.finish()) { error in
            XCTAssertEqual(
                String(describing: error),
                "UTF8 error: incomplete utf-8 byte sequence from index 0"
            )
        }
    }

    func testFinishReportsInvalidUTF8LikeRustEventsourceStream() {
        var decoder = UTF8StreamDecoder()

        XCTAssertEqual(decoder.receive(Data([0x61, 0xFF])), "a")
        XCTAssertThrowsError(try decoder.finish()) { error in
            XCTAssertEqual(
                String(describing: error),
                "UTF8 error: invalid utf-8 sequence of 1 bytes from index 0"
            )
        }
    }
}
