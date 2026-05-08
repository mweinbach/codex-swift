import CodexCore
import XCTest

final class SSEDataFrameDecoderTests: XCTestCase {
    func testDecodesFramesAcrossChunkBoundaries() {
        var decoder = SSEDataFrameDecoder()

        let first = decoder.receive("data: {\"a\"")
        let second = decoder.receive(":1}\n")
        let third = decoder.receive("data: {\"b\":2}\n\n")
        let finished = decoder.finish()

        XCTAssertEqual(first, [])
        XCTAssertEqual(second, [])
        XCTAssertEqual(third, [
            "{\"a\":1}\n{\"b\":2}"
        ])
        XCTAssertEqual(finished, [])
    }

    func testFinishFlushesPendingFrameAndIgnoresNonDataLines() {
        var decoder = SSEDataFrameDecoder()

        let first = decoder.receive(": comment\r\nid: 1\r\ndata: first\r\n")
        let second = decoder.receive("data:  second")
        let finished = decoder.finish()

        XCTAssertEqual(first, [])
        XCTAssertEqual(second, [])
        XCTAssertEqual(finished, ["first\n second"])
    }

    func testBlankLinesOnlyFlushWhenDataExists() {
        var decoder = SSEDataFrameDecoder()

        let frames = decoder.receive("\n\n: keepalive\n\ndata: done\n\n")
        let finished = decoder.finish()

        XCTAssertEqual(frames, ["done"])
        XCTAssertEqual(finished, [])
    }

    func testResponsesSSEParserUsesIncrementalFrameDecoder() {
        let text = """
        : ignored
        data: {"type":"response.created","response":{}}

        data: {"type":"response.completed","response":{"id":"resp_1","usage":null}}

        """

        XCTAssertEqual(ResponsesSSEParser.dataFrames(fromSSEText: text), [
            #"{"type":"response.created","response":{}}"#,
            #"{"type":"response.completed","response":{"id":"resp_1","usage":null}}"#
        ])
    }
}
