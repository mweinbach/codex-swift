import CodexCore
import XCTest

final class PermissionProfileSnapshotTests: XCTestCase {
    func testLegacySnapshotClearsActivePermissionProfileLikeRust() throws {
        let snapshot = PermissionProfileSnapshot.legacy(.readOnly())

        XCTAssertEqual(snapshot.permissionProfile, .readOnly())
        XCTAssertNil(snapshot.activePermissionProfile)
        XCTAssertEqual(snapshot.profileWorkspaceRoots, [])
    }

    func testActiveSnapshotKeepsResolvedProfileIdentityAndRootsTogetherLikeRust() throws {
        let profileRoot = try AbsolutePath(absolutePath: "/tmp/codex-profile-root")

        let snapshot = PermissionProfileSnapshot.activeWithProfileWorkspaceRoots(
            .workspaceWrite(),
            activePermissionProfile: ActivePermissionProfile(id: "workspace"),
            profileWorkspaceRoots: [profileRoot]
        )

        XCTAssertEqual(snapshot.permissionProfile, .workspaceWrite())
        XCTAssertEqual(snapshot.activePermissionProfile, ActivePermissionProfile(id: "workspace"))
        XCTAssertEqual(snapshot.profileWorkspaceRoots, [profileRoot])
    }

    func testRuntimeConfigAppliesPermissionProfileSnapshotAtomicallyLikeRustSessionBridge() throws {
        let profileRoot = try AbsolutePath(absolutePath: "/tmp/codex-profile-root")
        var config = CodexRuntimeConfig(
            permissionProfile: .disabled,
            activePermissionProfile: ActivePermissionProfile(id: ":danger-full-access"),
            memories: MemoriesConfig()
        )
        config.profileWorkspaceRoots = [try AbsolutePath(absolutePath: "/tmp/stale-profile-root")]

        config.applyPermissionProfileSnapshot(.activeWithProfileWorkspaceRoots(
            .readOnly(),
            activePermissionProfile: ActivePermissionProfile(id: ":read-only"),
            profileWorkspaceRoots: [profileRoot]
        ))

        XCTAssertEqual(config.permissionProfile, .readOnly())
        XCTAssertEqual(config.activePermissionProfile, ActivePermissionProfile(id: ":read-only"))
        XCTAssertEqual(config.profileWorkspaceRoots, [profileRoot])

        config.applyPermissionProfileSnapshot(.legacy(.workspaceWrite()))

        XCTAssertEqual(config.permissionProfile, .workspaceWrite())
        XCTAssertNil(config.activePermissionProfile)
        XCTAssertEqual(config.profileWorkspaceRoots, [])
    }
}
