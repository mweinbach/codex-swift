@testable import CodexResponsesAPIProxy
import XCTest

final class ResponsesAPIProxyTests: XCTestCase {
    func testAuthHeaderReaderReadsKeyWithNoNewline() throws {
        var sent = false
        let header = try ResponsesAPIProxyAuth.readAuthHeader { buffer in
            guard !sent else {
                return 0
            }
            write(Array("sk-abc123".utf8), into: buffer)
            sent = true
            return "sk-abc123".utf8.count
        }

        XCTAssertEqual(header, "Bearer sk-abc123")
    }

    func testAuthHeaderReaderHandlesShortReadsAndTrimsNewlines() throws {
        var chunks = [
            Array("sk-".utf8),
            Array("abc".utf8),
            Array("123\r\n".utf8)
        ]

        let header = try ResponsesAPIProxyAuth.readAuthHeader { buffer in
            guard !chunks.isEmpty else {
                return 0
            }
            let chunk = chunks.removeFirst()
            write(chunk, into: buffer)
            return chunk.count
        }

        XCTAssertEqual(header, "Bearer sk-abc123")
    }

    func testAuthHeaderReaderRejectsMissingOversizedAndInvalidKeys() {
        XCTAssertThrowsError(try ResponsesAPIProxyAuth.readAuthHeader { _ in 0 }) { error in
            XCTAssertEqual(error as? ResponsesAPIProxyError, .apiKeyMissing)
        }

        XCTAssertThrowsError(try ResponsesAPIProxyAuth.readAuthHeader { buffer in
            let data = Array(repeating: UInt8(ascii: "a"), count: buffer.count)
            write(data, into: buffer)
            return data.count
        }) { error in
            XCTAssertEqual(error as? ResponsesAPIProxyError, .apiKeyTooLarge(ResponsesAPIProxyAuth.bufferSize))
        }

        var sentInvalidKey = false
        XCTAssertThrowsError(try ResponsesAPIProxyAuth.readAuthHeader { buffer in
            guard !sentInvalidKey else {
                return 0
            }
            let data = Array("sk-abc!23".utf8)
            write(data, into: buffer)
            sentInvalidKey = true
            return data.count
        }) { error in
            XCTAssertEqual(error as? ResponsesAPIProxyError, .invalidAPIKeyCharacters)
        }
    }

    func testWriteServerInfoCreatesParentAndWritesRustShape() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let path = tempDir.appendingPathComponent("nested/server.json")

        try ResponsesAPIProxy.writeServerInfo(path: path, port: 3456, pid: 99)

        let data = try String(contentsOf: path, encoding: .utf8)
        XCTAssertEqual(data, #"{"port":3456,"pid":99}"# + "\n")
    }

    private func write(_ bytes: [UInt8], into buffer: UnsafeMutableBufferPointer<UInt8>) {
        for index in bytes.indices {
            buffer[index] = bytes[index]
        }
    }
}
