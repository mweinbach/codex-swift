import CodexCore
import XCTest

final class TuiStatusSurfacesTests: XCTestCase {
    func testStatusLineItemsAcceptRustLegacyAliasesAndCanonicalizeThreadID() throws {
        let items = try XCTUnwrap(TuiStatusLineItem.parseIDs([
            "model-name",
            "project",
            "project-root",
            "status",
            "approval",
            "context-usage",
            "session-id",
            "thread-title",
        ]))

        XCTAssertEqual(items, [
            .model,
            .projectName,
            .projectName,
            .runState,
            .approvalMode,
            .contextUsed,
            .threadID,
            .threadTitle,
        ])
        XCTAssertEqual(items.map(\.rawValue), [
            "model",
            "project-name",
            "project-name",
            "run-state",
            "approval-mode",
            "context-used",
            "thread-id",
            "thread-title",
        ])
    }

    func testTerminalTitleItemsAcceptRustLegacyAliasesAndCanonicalizeThreadID() throws {
        let items = try XCTUnwrap(TuiTerminalTitleItem.parseIDs([
            "project",
            "spinner",
            "status",
            "thread",
            "context-usage",
            "session-id",
            "model-name",
            "task-progress",
        ]))

        XCTAssertEqual(items, [
            .projectName,
            .activity,
            .runState,
            .threadTitle,
            .contextUsed,
            .threadID,
            .model,
            .taskProgress,
        ])
        XCTAssertEqual(items.map(\.rawValue), [
            "project-name",
            "activity",
            "run-state",
            "thread-title",
            "context-used",
            "thread-id",
            "model",
            "task-progress",
        ])
    }

    func testStatusSurfaceParsersRejectInvalidSelectionsLikeRustSetup() {
        XCTAssertNil(TuiStatusLineItem.parseIDs(["model", "not-a-status-item"]))
        XCTAssertNil(TuiTerminalTitleItem.parseIDs(["project", "not-a-title-item"]))
    }
}
