import CodexApplyPatch
import CodexCore
import Foundation
import XCTest

final class PatchApplyEventEmitterTests: XCTestCase {
    func testBeginEventUsesFileChangeTurnItemLikeRust() throws {
        let emitter = PatchApplyEventEmitter(
            threadID: Self.threadID,
            turnID: "turn-1",
            callID: "patch-1",
            changes: ["Sources/New.swift": .add(content: "let x = 1\n")],
            autoApproved: true
        )

        XCTAssertEqual(
            emitter.beginEvent(startedAtMilliseconds: 10),
            .itemStarted(ItemStartedEvent(
                threadID: Self.threadID,
                turnID: "turn-1",
                item: .fileChange(FileChangeItem(
                    id: "patch-1",
                    changes: ["Sources/New.swift": .add(content: "let x = 1\n")],
                    autoApproved: true
                )),
                startedAtMilliseconds: 10
            ))
        )
    }

    func testCompletionTracksKnownDeltaAndEmitsTurnDiffAfterItemCompleted() throws {
        let temp = try TemporaryPatchEventDirectory()
        var tracker = TurnDiffTracker(displayRoot: temp.url.path)
        let result = ApplyPatch.apply(
            """
            *** Begin Patch
            *** Add File: out/dest.txt
            +after
            *** End Patch
            """,
            cwd: temp.url
        )
        XCTAssertTrue(result.stderr.isEmpty)
        let emitter = Self.emitter(changes: ["out/dest.txt": .add(content: "after\n")])

        let events = emitter.completionEvents(
            stdout: result.stdout,
            stderr: "",
            status: .failed,
            tracker: &tracker,
            turnDiffUpdate: .knownDelta(result.delta),
            completedAtMilliseconds: 20
        )

        XCTAssertEqual(events.first, .itemCompleted(ItemCompletedEvent(
            threadID: Self.threadID,
            turnID: "turn-1",
            item: .fileChange(FileChangeItem(
                id: "patch-1",
                changes: ["out/dest.txt": .add(content: "after\n")],
                status: .failed,
                stdout: result.stdout,
                stderr: ""
            )),
            completedAtMilliseconds: 20
        )))
        guard case let .turnDiff(turnDiff)? = events.dropFirst().first else {
            return XCTFail("expected turn diff after item completion")
        }
        XCTAssertTrue(turnDiff.unifiedDiff.contains("diff --git a/out/dest.txt b/out/dest.txt"))
        XCTAssertTrue(turnDiff.unifiedDiff.contains("+after"))
        XCTAssertEqual(tracker.unifiedDiff(), turnDiff.unifiedDiff)
    }

    func testInvalidatingExistingDiffEmitsEmptyTurnDiffLikeRust() throws {
        let temp = try TemporaryPatchEventDirectory()
        var tracker = TurnDiffTracker(displayRoot: temp.url.path)
        let result = ApplyPatch.apply(
            """
            *** Begin Patch
            *** Add File: stale.txt
            +stale
            *** End Patch
            """,
            cwd: temp.url
        )
        tracker.trackDelta(result.delta)
        XCTAssertNotNil(tracker.unifiedDiff())

        let events = Self.emitter().completionEvents(
            stdout: "",
            stderr: "failed",
            status: .failed,
            tracker: &tracker,
            turnDiffUpdate: .invalidate
        )

        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events[1], .turnDiff(TurnDiffEvent(unifiedDiff: "")))
        XCTAssertNil(tracker.unifiedDiff())
    }

    func testInvalidatingFreshTrackerDoesNotEmitTurnDiff() throws {
        let temp = try TemporaryPatchEventDirectory()
        var tracker = TurnDiffTracker(displayRoot: temp.url.path)

        let events = Self.emitter().completionEvents(
            stdout: "",
            stderr: "failed",
            status: .failed,
            tracker: &tracker,
            turnDiffUpdate: .invalidate
        )

        XCTAssertEqual(events.count, 1)
        XCTAssertNil(tracker.unifiedDiff())
    }

    func testExactEmptyKnownDeltaPreservesExistingDiffWithoutEvent() throws {
        let temp = try TemporaryPatchEventDirectory()
        var tracker = TurnDiffTracker(displayRoot: temp.url.path)
        let result = ApplyPatch.apply(
            """
            *** Begin Patch
            *** Add File: kept.txt
            +kept
            *** End Patch
            """,
            cwd: temp.url
        )
        tracker.trackDelta(result.delta)
        let before = tracker.unifiedDiff()

        let events = Self.emitter().completionEvents(
            stdout: "",
            stderr: "",
            status: .completed,
            tracker: &tracker,
            turnDiffUpdate: .knownDelta(.empty)
        )

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(tracker.unifiedDiff(), before)
    }

    func testFileChangesConvertVerifiedApplyPatchActionMetadata() throws {
        let temp = try TemporaryPatchEventDirectory()
        let source = temp.url.appendingPathComponent("old.txt")
        try "old\n".write(to: source, atomically: true, encoding: .utf8)
        let patch = """
        *** Begin Patch
        *** Add File: new.txt
        +new
        *** Update File: old.txt
        @@
        -old
        +new-old
        *** End Patch
        """

        guard case let .body(action) = maybeParseApplyPatchVerified(["apply_patch", patch], cwd: temp.url) else {
            return XCTFail("expected verified apply_patch action")
        }

        let changes = PatchApplyEventEmitter.fileChanges(from: action.changes)
        XCTAssertEqual(changes[temp.url.appendingPathComponent("new.txt").path], .add(content: "new\n"))
        XCTAssertEqual(
            changes[source.path],
            .update(unifiedDiff: "@@ -1 +1 @@\n-old\n+new-old\n", movePath: nil)
        )
    }

    private static let threadID = ConversationId(
        uuid: UUID(uuidString: "00000000-0000-7000-8000-000000000001")!
    )

    private static func emitter(changes: [String: FileChange] = [:]) -> PatchApplyEventEmitter {
        PatchApplyEventEmitter(
            threadID: threadID,
            turnID: "turn-1",
            callID: "patch-1",
            changes: changes,
            autoApproved: false
        )
    }
}

private final class TemporaryPatchEventDirectory {
    let url: URL

    init() throws {
        let base = FileManager.default.temporaryDirectory
        url = base.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}
