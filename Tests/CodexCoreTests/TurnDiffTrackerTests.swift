import CodexApplyPatch
import CodexCore
import CryptoKit
import XCTest

final class TurnDiffTrackerTests: XCTestCase {
    func testAccumulatesAddThenUpdateAsSingleAdd() throws {
        let temp = try TemporaryTurnDiffDirectory()
        var tracker = TurnDiffTracker(displayRoot: temp.url.path)

        tracker.trackDelta(try applyPatch(
            root: temp.url,
            patch: """
            *** Begin Patch
            *** Add File: a.txt
            +foo
            *** End Patch
            """
        ))
        tracker.trackDelta(try applyPatch(
            root: temp.url,
            patch: """
            *** Begin Patch
            *** Update File: a.txt
            @@
             foo
            +bar
            *** End Patch
            """
        ))

        let expected = """
        diff --git a/a.txt b/a.txt
        new file mode 100644
        index \(zeroObjectID)..\(gitBlobObjectID("foo\nbar\n"))
        --- /dev/null
        +++ b/a.txt
        @@ -0,0 +1,2 @@
        +foo
        +bar

        """
        XCTAssertEqual(tracker.unifiedDiff(), expected)
    }

    func testInexactDeltaInvalidatesExistingDiff() throws {
        let temp = try TemporaryTurnDiffDirectory()
        var tracker = TurnDiffTracker(displayRoot: temp.url.path)

        tracker.trackDelta(try applyPatch(
            root: temp.url,
            patch: """
            *** Begin Patch
            *** Add File: a.txt
            +foo
            *** End Patch
            """
        ))
        tracker.trackDelta(AppliedPatchDelta(changes: [], exact: false))

        XCTAssertNil(tracker.unifiedDiff())
    }

    func testExactEmptyDeltaDoesNotClearExistingDiff() throws {
        let temp = try TemporaryTurnDiffDirectory()
        var tracker = TurnDiffTracker(displayRoot: temp.url.path)

        tracker.trackDelta(try applyPatch(
            root: temp.url,
            patch: """
            *** Begin Patch
            *** Add File: a.txt
            +foo
            *** End Patch
            """
        ))
        let before = tracker.unifiedDiff()
        tracker.trackDelta(.empty)

        XCTAssertEqual(tracker.unifiedDiff(), before)
    }

    func testAccumulatesDelete() throws {
        let temp = try TemporaryTurnDiffDirectory()
        let target = temp.url.appendingPathComponent("b.txt")
        try "x\n".write(to: target, atomically: true, encoding: .utf8)

        var tracker = TurnDiffTracker(displayRoot: temp.url.path)
        tracker.trackDelta(try applyPatch(
            root: temp.url,
            patch: """
            *** Begin Patch
            *** Delete File: b.txt
            *** End Patch
            """
        ))

        let expected = """
        diff --git a/b.txt b/b.txt
        deleted file mode 100644
        index \(gitBlobObjectID("x\n"))..\(zeroObjectID)
        --- a/b.txt
        +++ /dev/null
        @@ -1 +0,0 @@
        -x

        """
        XCTAssertEqual(tracker.unifiedDiff(), expected)
    }

    func testAccumulatesMoveAndUpdate() throws {
        let temp = try TemporaryTurnDiffDirectory()
        try "line\n".write(to: temp.url.appendingPathComponent("src.txt"), atomically: true, encoding: .utf8)

        var tracker = TurnDiffTracker(displayRoot: temp.url.path)
        tracker.trackDelta(try applyPatch(
            root: temp.url,
            patch: """
            *** Begin Patch
            *** Update File: src.txt
            *** Move to: dst.txt
            @@
            -line
            +line2
            *** End Patch
            """
        ))

        let expected = """
        diff --git a/src.txt b/dst.txt
        index \(gitBlobObjectID("line\n"))..\(gitBlobObjectID("line2\n"))
        --- a/src.txt
        +++ b/dst.txt
        @@ -1 +1 @@
        -line
        +line2

        """
        XCTAssertEqual(tracker.unifiedDiff(), expected)
    }

    func testPureRenameYieldsNoDiff() throws {
        let temp = try TemporaryTurnDiffDirectory()
        try "same\n".write(to: temp.url.appendingPathComponent("old.txt"), atomically: true, encoding: .utf8)

        var tracker = TurnDiffTracker(displayRoot: temp.url.path)
        tracker.trackDelta(try applyPatch(
            root: temp.url,
            patch: """
            *** Begin Patch
            *** Update File: old.txt
            *** Move to: new.txt
            @@
             same
            *** End Patch
            """
        ))

        XCTAssertNil(tracker.unifiedDiff())
    }

    func testAddOverExistingFileBecomesUpdate() throws {
        let temp = try TemporaryTurnDiffDirectory()
        try "before\n".write(to: temp.url.appendingPathComponent("dup.txt"), atomically: true, encoding: .utf8)

        var tracker = TurnDiffTracker(displayRoot: temp.url.path)
        tracker.trackDelta(try applyPatch(
            root: temp.url,
            patch: """
            *** Begin Patch
            *** Add File: dup.txt
            +after
            *** End Patch
            """
        ))

        let expected = """
        diff --git a/dup.txt b/dup.txt
        index \(gitBlobObjectID("before\n"))..\(gitBlobObjectID("after\n"))
        --- a/dup.txt
        +++ b/dup.txt
        @@ -1 +1 @@
        -before
        +after

        """
        XCTAssertEqual(tracker.unifiedDiff(), expected)
    }

    func testDeleteThenReaddSamePathBecomesUpdate() throws {
        let temp = try TemporaryTurnDiffDirectory()
        try "before\n".write(to: temp.url.appendingPathComponent("cycle.txt"), atomically: true, encoding: .utf8)

        var tracker = TurnDiffTracker(displayRoot: temp.url.path)
        tracker.trackDelta(try applyPatch(
            root: temp.url,
            patch: """
            *** Begin Patch
            *** Delete File: cycle.txt
            *** End Patch
            """
        ))
        tracker.trackDelta(try applyPatch(
            root: temp.url,
            patch: """
            *** Begin Patch
            *** Add File: cycle.txt
            +after
            *** End Patch
            """
        ))

        let expected = """
        diff --git a/cycle.txt b/cycle.txt
        index \(gitBlobObjectID("before\n"))..\(gitBlobObjectID("after\n"))
        --- a/cycle.txt
        +++ b/cycle.txt
        @@ -1 +1 @@
        -before
        +after

        """
        XCTAssertEqual(tracker.unifiedDiff(), expected)
    }

    func testMoveOverExistingDestinationWithoutContentChangeDeletesSourceOnly() throws {
        let temp = try TemporaryTurnDiffDirectory()
        try "same\n".write(to: temp.url.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try "same\n".write(to: temp.url.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)

        var tracker = TurnDiffTracker(displayRoot: temp.url.path)
        tracker.trackDelta(try applyPatch(
            root: temp.url,
            patch: """
            *** Begin Patch
            *** Update File: a.txt
            *** Move to: b.txt
            @@
             same
            *** End Patch
            """
        ))

        let expected = """
        diff --git a/a.txt b/a.txt
        deleted file mode 100644
        index \(gitBlobObjectID("same\n"))..\(zeroObjectID)
        --- a/a.txt
        +++ /dev/null
        @@ -1 +0,0 @@
        -same

        """
        XCTAssertEqual(tracker.unifiedDiff(), expected)
    }

    func testMoveOverExistingDestinationWithContentChangeDeletesSourceAndUpdatesDestination() throws {
        let temp = try TemporaryTurnDiffDirectory()
        try "from\n".write(to: temp.url.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try "existing\n".write(to: temp.url.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)

        var tracker = TurnDiffTracker(displayRoot: temp.url.path)
        tracker.trackDelta(try applyPatch(
            root: temp.url,
            patch: """
            *** Begin Patch
            *** Update File: a.txt
            *** Move to: b.txt
            @@
            -from
            +new
            *** End Patch
            """
        ))

        let expected = """
        diff --git a/a.txt b/a.txt
        deleted file mode 100644
        index \(gitBlobObjectID("from\n"))..\(zeroObjectID)
        --- a/a.txt
        +++ /dev/null
        @@ -1 +0,0 @@
        -from
        diff --git a/b.txt b/b.txt
        index \(gitBlobObjectID("existing\n"))..\(gitBlobObjectID("new\n"))
        --- a/b.txt
        +++ b/b.txt
        @@ -1 +1 @@
        -existing
        +new

        """
        XCTAssertEqual(tracker.unifiedDiff(), expected)
    }

    func testPreservesCommittedChangeOrderWithDeleteThenMoveOverwrite() throws {
        let temp = try TemporaryTurnDiffDirectory()
        try "from\n".write(to: temp.url.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try "existing\n".write(to: temp.url.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)

        var tracker = TurnDiffTracker(displayRoot: temp.url.path)
        tracker.trackDelta(try applyPatch(
            root: temp.url,
            patch: """
            *** Begin Patch
            *** Delete File: b.txt
            *** Update File: a.txt
            *** Move to: b.txt
            @@
            -from
            +new
            *** End Patch
            """
        ))

        let expected = """
        diff --git a/a.txt b/a.txt
        deleted file mode 100644
        index \(gitBlobObjectID("from\n"))..\(zeroObjectID)
        --- a/a.txt
        +++ /dev/null
        @@ -1 +0,0 @@
        -from
        diff --git a/b.txt b/b.txt
        index \(gitBlobObjectID("existing\n"))..\(gitBlobObjectID("new\n"))
        --- a/b.txt
        +++ b/b.txt
        @@ -1 +1 @@
        -existing
        +new

        """
        XCTAssertEqual(tracker.unifiedDiff(), expected)
    }

    private func applyPatch(root: URL, patch: String) throws -> AppliedPatchDelta {
        let result = ApplyPatch.apply(patch, cwd: root)
        XCTAssertEqual(result.stderr, "")
        XCTAssertFalse(result.delta.isEmpty)
        return result.delta
    }
}

private let zeroObjectID = "0000000000000000000000000000000000000000"

private func gitBlobObjectID(_ content: String) -> String {
    var data = Data("blob \(Data(content.utf8).count)\0".utf8)
    data.append(Data(content.utf8))
    return hexString(Insecure.SHA1.hash(data: data))
}

private func hexString<D: Sequence>(_ bytes: D) -> String where D.Element == UInt8 {
    let digits = Array("0123456789abcdef".utf8)
    var output = [UInt8]()
    output.reserveCapacity(40)
    for byte in bytes {
        output.append(digits[Int(byte >> 4)])
        output.append(digits[Int(byte & 0x0f)])
    }
    return String(decoding: output, as: UTF8.self)
}

private final class TemporaryTurnDiffDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}
