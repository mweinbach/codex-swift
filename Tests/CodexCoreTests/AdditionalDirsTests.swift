import XCTest
@testable import CodexCore

final class AdditionalDirsTests: XCTestCase {
    private let cwd = "/tmp/project"

    func testReturnsNilForWorkspaceWrite() {
        XCTAssertNil(addDirWarningMessage(
            additionalDirs: ["/tmp/example"],
            permissionProfile: .workspaceWrite(),
            cwd: cwd
        ))
    }

    func testReturnsNilForDangerFullAccess() {
        XCTAssertNil(addDirWarningMessage(
            additionalDirs: ["/tmp/example"],
            permissionProfile: .disabled,
            cwd: cwd
        ))
    }

    func testReturnsNilForExternalSandbox() {
        XCTAssertNil(addDirWarningMessage(
            additionalDirs: ["/tmp/example"],
            permissionProfile: .external(network: .enabled),
            cwd: cwd
        ))
    }

    func testWarnsForReadOnly() {
        XCTAssertEqual(
            addDirWarningMessage(
                additionalDirs: ["relative", "/abs"],
                permissionProfile: .readOnly(),
                cwd: cwd
            ),
            "Ignoring --add-dir (relative, /abs) because the effective permissions do not allow additional writable roots. Switch to workspace-write or danger-full-access to allow them."
        )
    }

    func testWarnsWhenProfileCanWriteElsewhereButNotCwd() {
        let profile = PermissionProfile.managed(
            fileSystem: .restricted(entries: [
                FileSystemSandboxEntry(
                    path: .special(FileSystemSpecialPath.root.jsonValue),
                    access: .read
                ),
                FileSystemSandboxEntry(path: .path("/tmp/writable"), access: .write)
            ]),
            network: .restricted
        )

        XCTAssertEqual(
            addDirWarningMessage(
                additionalDirs: ["/tmp/extra"],
                permissionProfile: profile,
                cwd: cwd
            ),
            "Ignoring --add-dir (/tmp/extra) because the effective permissions do not allow additional writable roots. Switch to workspace-write or danger-full-access to allow them."
        )
    }

    func testReturnsNilWhenNoAdditionalDirs() {
        XCTAssertNil(addDirWarningMessage(
            additionalDirs: [],
            permissionProfile: .readOnly(),
            cwd: cwd
        ))
    }

    func testLegacySandboxPolicyWrapperUsesResolvedProfile() {
        XCTAssertNil(addDirWarningMessage(
            additionalDirs: ["/tmp/example"],
            sandboxPolicy: .newWorkspaceWritePolicy(),
            cwd: cwd
        ))
    }
}
