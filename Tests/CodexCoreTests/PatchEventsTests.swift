import CodexCore
import XCTest

final class PatchEventsTests: XCTestCase {
    func testFileChangeWireTagsMatchRust() throws {
        try XCTAssertJSONObjectEqual(FileChange.add(content: "new\n"), [
            "type": "add",
            "content": "new\n"
        ])

        try XCTAssertJSONObjectEqual(FileChange.delete(content: "old\n"), [
            "type": "delete",
            "content": "old\n"
        ])

        try XCTAssertJSONObjectEqual(FileChange.update(unifiedDiff: "@@ -1 +1 @@\n-old\n+new\n", movePath: nil), [
            "type": "update",
            "unified_diff": "@@ -1 +1 @@\n-old\n+new\n",
            "move_path": NSNull()
        ])
    }

    func testFileChangeUpdateDecodesMovePath() throws {
        let json = """
        {
          "type": "update",
          "unified_diff": "@@ -1 +1 @@\\n-old\\n+new\\n",
          "move_path": "Sources/New.swift"
        }
        """

        let change = try JSONDecoder().decode(FileChange.self, from: Data(json.utf8))

        XCTAssertEqual(change, .update(
            unifiedDiff: "@@ -1 +1 @@\n-old\n+new\n",
            movePath: "Sources/New.swift"
        ))
    }

    func testPatchApplyBeginEventWireShapeAndDefaultTurnID() throws {
        let event = PatchApplyBeginEvent(
            callID: "patch-1",
            autoApproved: true,
            changes: [
                "Sources/New.swift": .add(content: "let x = 1\n"),
                "Sources/Old.swift": .update(unifiedDiff: "@@ -1 +1 @@\n-old\n+new\n", movePath: nil)
            ]
        )

        try XCTAssertJSONObjectEqual(event, [
            "call_id": "patch-1",
            "turn_id": "",
            "auto_approved": true,
            "changes": [
                "Sources/New.swift": [
                    "type": "add",
                    "content": "let x = 1\n"
                ],
                "Sources/Old.swift": [
                    "type": "update",
                    "unified_diff": "@@ -1 +1 @@\n-old\n+new\n",
                    "move_path": NSNull()
                ]
            ]
        ])

        let json = """
        {
          "call_id": "patch-1",
          "auto_approved": false,
          "changes": {
            "Sources/New.swift": {
              "type": "add",
              "content": "let x = 1\\n"
            }
          }
        }
        """

        let decoded = try JSONDecoder().decode(PatchApplyBeginEvent.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.turnID, "")
        XCTAssertEqual(decoded.autoApproved, false)
        XCTAssertEqual(decoded.changes["Sources/New.swift"], .add(content: "let x = 1\n"))
    }

    func testPatchApplyEndEventDefaultsMissingTurnIDAndChanges() throws {
        let json = """
        {
          "call_id": "patch-1",
          "stdout": "Done",
          "stderr": "",
          "success": true
        }
        """

        let event = try JSONDecoder().decode(PatchApplyEndEvent.self, from: Data(json.utf8))

        XCTAssertEqual(event, PatchApplyEndEvent(
            callID: "patch-1",
            turnID: "",
            stdout: "Done",
            stderr: "",
            success: true,
            changes: [:],
            status: .completed
        ))
        try XCTAssertJSONObjectEqual(event, [
            "call_id": "patch-1",
            "turn_id": "",
            "stdout": "Done",
            "stderr": "",
            "success": true,
            "changes": [:],
            "status": "completed"
        ])
    }

    func testTurnDiffEventUsesRustFieldName() throws {
        try XCTAssertJSONObjectEqual(TurnDiffEvent(unifiedDiff: "diff --git a/a b/a\n"), [
            "unified_diff": "diff --git a/a b/a\n"
        ])
    }
}
