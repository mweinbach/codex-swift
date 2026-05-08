@testable import CodexCore
import XCTest

final class FeedbackTests: XCTestCase {
    func testRingBufferDropsFrontWhenFullLikeRust() throws {
        let feedback = CodexFeedback(capacity: 8)
        let writer = feedback.makeWriter()

        writer.write(Array("abcdefgh".utf8))
        writer.write(Array("ij".utf8))

        let snapshot = feedback.snapshot(sessionID: nil)
        XCTAssertEqual(String(decoding: snapshot.bytes, as: UTF8.self), "cdefghij")
        XCTAssertTrue(snapshot.threadID.hasPrefix("no-active-thread-"))
    }

    func testRingBufferKeepsTrailingBytesWhenChunkExceedsCapacity() {
        var ring = FeedbackRingBuffer(capacity: 5)

        ring.push(Array("abcdefgh".utf8))

        XCTAssertEqual(String(decoding: ring.snapshotBytes(), as: UTF8.self), "defgh")
    }

    func testRingBufferIgnoresEmptyWritesAndZeroCapacity() {
        var ring = FeedbackRingBuffer(capacity: 0)

        ring.push(Array("abc".utf8))
        ring.push([])

        XCTAssertEqual(ring.count, 0)
        XCTAssertEqual(ring.snapshotBytes(), [])
    }

    func testSnapshotUsesProvidedConversationID() throws {
        let id = try ConversationId(string: "018f7a2d-4c5b-7abc-8def-0123456789ab")
        let feedback = CodexFeedback(capacity: 32)

        feedback.makeWriter().write(Data("hello".utf8))

        XCTAssertEqual(feedback.snapshot(sessionID: id), CodexLogSnapshot(
            bytes: Array("hello".utf8),
            threadID: "018f7a2d-4c5b-7abc-8def-0123456789ab"
        ))
    }

    func testSnapshotSavesToTempFileWithRustFilenamePrefix() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("codex-swift-feedback-tests-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: root)
        }
        let snapshot = CodexLogSnapshot(bytes: Array("logs".utf8), threadID: "thread-1")

        let path = try snapshot.saveToTempFile(temporaryDirectory: root)

        XCTAssertEqual(path.lastPathComponent, "codex-feedback-thread-1.log")
        XCTAssertEqual(try String(contentsOf: path, encoding: .utf8), "logs")
    }
}
