import XCTest
@testable import CodexCore

final class AdditionalDirsTests: XCTestCase {
    func testReturnsNilForWorkspaceWrite() {
        XCTAssertNil(addDirWarningMessage(
            additionalDirs: ["/tmp/example"],
            sandboxPolicy: .newWorkspaceWritePolicy()
        ))
    }

    func testReturnsNilForDangerFullAccess() {
        XCTAssertNil(addDirWarningMessage(
            additionalDirs: ["/tmp/example"],
            sandboxPolicy: .dangerFullAccess
        ))
    }

    func testReturnsNilForExternalSandbox() {
        XCTAssertNil(addDirWarningMessage(
            additionalDirs: ["/tmp/example"],
            sandboxPolicy: .externalSandbox(networkAccess: .enabled)
        ))
    }

    func testWarnsForReadOnly() {
        XCTAssertEqual(
            addDirWarningMessage(
                additionalDirs: ["relative", "/abs"],
                sandboxPolicy: .readOnly
            ),
            "Ignoring --add-dir (relative, /abs) because the effective sandbox mode is read-only. Switch to workspace-write or danger-full-access to allow additional writable roots."
        )
    }

    func testReturnsNilWhenNoAdditionalDirs() {
        XCTAssertNil(addDirWarningMessage(
            additionalDirs: [],
            sandboxPolicy: .readOnly
        ))
    }
}
