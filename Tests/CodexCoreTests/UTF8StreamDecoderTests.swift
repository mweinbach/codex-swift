import CodexCore
import XCTest

final class UTF8StreamDecoderTests: XCTestCase {
    func testBuffersIncompleteMultibyteSequenceAcrossChunks() {
        var decoder = UTF8StreamDecoder()
        let bytes = Array("a\u{1F30A}b".utf8)

        XCTAssertEqual(decoder.receive(Data(bytes.prefix(2))), "a")
        XCTAssertEqual(decoder.receive(Data(bytes.dropFirst(2).prefix(2))), "")
        XCTAssertEqual(decoder.receive(Data(bytes.dropFirst(4))), "\u{1F30A}b")
        XCTAssertEqual(decoder.finish(), "")
    }

    func testFinishFlushesPendingBytesLossily() {
        var decoder = UTF8StreamDecoder()

        XCTAssertEqual(decoder.receive(Data([0xF0, 0x9F])), "")
        XCTAssertEqual(decoder.finish(), "\u{FFFD}")
    }
}
