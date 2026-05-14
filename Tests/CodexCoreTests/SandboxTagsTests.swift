import XCTest
@testable import CodexCore

final class SandboxTagsTests: XCTestCase {
    func testDangerFullAccessIsUntaggedLikeRust() {
        XCTAssertEqual(
            SandboxTags.sandboxTag(
                sandboxPolicy: .dangerFullAccess,
                windowsSandboxLevel: .disabled
            ),
            "none"
        )
    }

    func testExternalSandboxKeepsExternalTagLikeRust() {
        XCTAssertEqual(
            SandboxTags.sandboxTag(
                sandboxPolicy: .externalSandbox(networkAccess: .enabled),
                windowsSandboxLevel: .disabled
            ),
            "external"
        )
    }

    func testDefaultReadOnlyUsesPlatformSandboxTagLikeRust() {
        XCTAssertEqual(
            SandboxTags.sandboxTag(
                sandboxPolicy: .newReadOnlyPolicy(),
                windowsSandboxLevel: .disabled
            ),
            PatchSafety.getPlatformSandbox()?.metricTag ?? "none"
        )
    }

    func testPermissionProfileSandboxTagDistinguishesDisabledFromExternalLikeRust() {
        XCTAssertEqual(
            SandboxTags.permissionProfileSandboxTag(
                profile: .disabled,
                windowsSandboxLevel: .disabled,
                enforceManagedNetwork: false
            ),
            "none"
        )
        XCTAssertEqual(
            SandboxTags.permissionProfileSandboxTag(
                profile: .external(network: .restricted),
                windowsSandboxLevel: .disabled,
                enforceManagedNetwork: false
            ),
            "external"
        )
    }

    func testUnrestrictedManagedProfileWithEnabledNetworkIsUntaggedLikeRust() {
        let profile = PermissionProfile.managed(fileSystem: .unrestricted, network: .enabled)

        XCTAssertEqual(
            SandboxTags.permissionProfileSandboxTag(
                profile: profile,
                windowsSandboxLevel: .disabled,
                enforceManagedNetwork: false
            ),
            "none"
        )
    }

    func testRootWriteManagedProfileWithEnabledNetworkIsUntaggedLikeRust() {
        let profile = PermissionProfile.managed(
            fileSystem: .restricted(entries: [
                FileSystemSandboxEntry(path: .special(FileSystemSpecialPath.root.jsonValue), access: .write)
            ]),
            network: .enabled
        )

        XCTAssertEqual(
            SandboxTags.permissionProfileSandboxTag(
                profile: profile,
                windowsSandboxLevel: .disabled,
                enforceManagedNetwork: false
            ),
            "none"
        )
    }

    func testManagedNetworkEnforcementTagsUnrestrictedProfileAsSandboxedLikeRust() {
        let profile = PermissionProfile.managed(fileSystem: .unrestricted, network: .enabled)

        XCTAssertEqual(
            SandboxTags.permissionProfileSandboxTag(
                profile: profile,
                windowsSandboxLevel: .disabled,
                enforceManagedNetwork: true
            ),
            PatchSafety.getPlatformSandbox()?.metricTag ?? "none"
        )
    }
}
