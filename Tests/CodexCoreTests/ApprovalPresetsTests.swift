import CodexCore
import XCTest

final class ApprovalPresetsTests: XCTestCase {
    func testBuiltInApprovalPresetsMatchRustOrderAndPolicies() {
        let presets = ApprovalPresets.builtIn()
        XCTAssertEqual(presets.map(\.id), ["read-only", "auto", "full-access"])
        XCTAssertEqual(presets.map(\.label), ["Read Only", "Default", "Full Access"])

        XCTAssertEqual(presets[0].approval, .onRequest)
        XCTAssertEqual(presets[0].activePermissionProfile, ActivePermissionProfile(id: ":read-only"))
        XCTAssertEqual(presets[0].permissionProfile, .readOnly())
        XCTAssertEqual(presets[0].sandbox, .readOnly)

        XCTAssertEqual(presets[1].approval, .onRequest)
        XCTAssertEqual(presets[1].activePermissionProfile, ActivePermissionProfile(id: ":workspace"))
        XCTAssertEqual(presets[1].permissionProfile, .workspaceWrite())
        XCTAssertEqual(presets[1].sandbox, .newWorkspaceWritePolicy())

        XCTAssertEqual(presets[2].approval, .never)
        XCTAssertEqual(presets[2].activePermissionProfile, ActivePermissionProfile(id: ":danger-full-access"))
        XCTAssertEqual(presets[2].permissionProfile, .disabled)
        XCTAssertEqual(presets[2].sandbox, .dangerFullAccess)
    }

    func testBuiltInPermissionProfileLookupMatchesRustActiveProfileIDs() {
        XCTAssertEqual(
            ApprovalPresets.permissionProfile(for: ActivePermissionProfile(id: ":read-only")),
            .readOnly()
        )
        XCTAssertEqual(
            ApprovalPresets.permissionProfile(for: ActivePermissionProfile(id: ":workspace")),
            .workspaceWrite()
        )
        XCTAssertEqual(
            ApprovalPresets.permissionProfile(for: ActivePermissionProfile(id: ":danger-full-access")),
            .disabled
        )
    }

    func testBuiltInPermissionProfileLookupRejectsExtendedOrUnknownProfilesLikeRust() {
        XCTAssertNil(ApprovalPresets.permissionProfile(for: ActivePermissionProfile(id: "custom")))
        XCTAssertNil(ApprovalPresets.permissionProfile(
            for: ActivePermissionProfile(id: ":workspace", extends: ":read-only")
        ))
    }
}
