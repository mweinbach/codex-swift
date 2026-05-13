import CodexCore
import Foundation
import XCTest

final class PatchApplyArgumentDiffConsumerTests: XCTestCase {
    func testStreamsApplyPatchChangesLikeRust() throws {
        var consumer = ApplyPatchArgumentDiffConsumer()
        let start = Date(timeIntervalSince1970: 0)

        XCTAssertNil(consumer.pushDelta(callID: "call-1", delta: "*** Begin Patch\n", now: start))

        let firstEvent = try XCTUnwrap(consumer.pushDelta(
            callID: "call-1",
            delta: "*** Add File: hello.txt\n+hello",
            now: start
        ))
        XCTAssertEqual(
            firstEvent,
            PatchApplyUpdatedEvent(
                callID: "call-1",
                changes: ["hello.txt": .add(content: "")]
            )
        )

        XCTAssertNil(consumer.pushDelta(callID: "call-1", delta: "\n+world", now: start))
        XCTAssertNil(consumer.pushDelta(callID: "call-1", delta: "\n*** End Patch", now: start))

        let finalEvent = try XCTUnwrap(try consumer.finishUpdateOnComplete(now: start))
        XCTAssertEqual(
            finalEvent,
            PatchApplyUpdatedEvent(
                callID: "call-1",
                changes: ["hello.txt": .add(content: "hello\nworld\n")]
            )
        )
    }

    func testSendsNextUpdateAfterBufferInterval() throws {
        var consumer = ApplyPatchArgumentDiffConsumer()
        let start = Date(timeIntervalSince1970: 0)
        XCTAssertNil(consumer.pushDelta(callID: "call-1", delta: "*** Begin Patch\n", now: start))

        let firstEvent = try XCTUnwrap(consumer.pushDelta(
            callID: "call-1",
            delta: "*** Add File: hello.txt\n+hello",
            now: start
        ))
        XCTAssertEqual(
            firstEvent.changes,
            ["hello.txt": .add(content: "")]
        )

        let secondEvent = try XCTUnwrap(consumer.pushDelta(
            callID: "call-1",
            delta: "\n+world",
            now: start.addingTimeInterval(ApplyPatchArgumentDiffConsumer.bufferInterval)
        ))
        XCTAssertEqual(
            secondEvent.changes,
            ["hello.txt": .add(content: "hello\n")]
        )
    }

    func testFormatsUpdateProgressChangesLikeRust() throws {
        var consumer = ApplyPatchArgumentDiffConsumer()
        let event = try XCTUnwrap(consumer.pushDelta(
            callID: "call-1",
            delta: """
            *** Begin Patch
            *** Update File: old.txt
            *** Move to: new.txt
            @@ title
            -old
            +new
            *** End of File

            """,
            now: Date(timeIntervalSince1970: 0)
        ))

        XCTAssertEqual(
            event.changes,
            [
                "old.txt": .update(
                    unifiedDiff: "@@ title\n-old\n+new\n*** End of File\n",
                    movePath: "new.txt"
                )
            ]
        )
    }

    func testFinishReportsParserErrorLikeRustToolConsumer() throws {
        var consumer = ApplyPatchArgumentDiffConsumer()
        _ = consumer.pushDelta(callID: "call-1", delta: "*** Begin Patch\n*** Add File: file.txt\n+hello\n")

        XCTAssertThrowsError(try consumer.finishUpdateOnComplete()) { error in
            XCTAssertEqual(
                String(describing: error),
                "failed to parse apply_patch: Invalid patch: The last line of the patch must be '*** End Patch'"
            )
        }
    }
}
