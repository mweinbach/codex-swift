import XCTest
@testable import CodexCore

final class NetworkProxySpecTests: XCTestCase {
    func testRequirementsAllowedDomainsAreBaselineForUserAllowlistLikeRust() {
        var config = NetworkProxyConfig()
        config.network.setAllowedDomains(["api.example.com"])
        let requirements = NetworkRequirementsToml(
            domains: ["*.example.com": .allow]
        )

        let spec = NetworkProxySpec.fromConfigAndRequirements(
            config,
            requirements: requirements,
            permissionProfile: .readOnly()
        )

        XCTAssertEqual(spec.config.network.allowedDomains(), ["*.example.com", "api.example.com"])
        XCTAssertEqual(spec.constraints.allowedDomains, ["*.example.com"])
        XCTAssertEqual(spec.constraints.allowlistExpansionEnabled, true)
    }

    func testRequirementsAllowedDomainsDoNotOverrideUserDeniesForSamePatternLikeRust() {
        var config = NetworkProxyConfig()
        config.network.setDeniedDomains(["api.example.com"])
        let requirements = NetworkRequirementsToml(
            domains: ["api.example.com": .allow]
        )

        let spec = NetworkProxySpec.fromConfigAndRequirements(
            config,
            requirements: requirements,
            permissionProfile: .workspaceWrite()
        )

        XCTAssertNil(spec.config.network.allowedDomains())
        XCTAssertEqual(spec.config.network.deniedDomains(), ["api.example.com"])
        XCTAssertEqual(spec.constraints.allowedDomains, ["api.example.com"])
    }

    func testManagedAllowedDomainsOnlyIgnoresUserAllowlistLikeRust() {
        var config = NetworkProxyConfig()
        config.network.setAllowedDomains(["api.example.com"])
        let requirements = NetworkRequirementsToml(
            domains: ["*.example.com": .allow],
            managedAllowedDomainsOnly: true
        )

        let spec = NetworkProxySpec.fromConfigAndRequirements(
            config,
            requirements: requirements,
            permissionProfile: .readOnly()
        )

        XCTAssertTrue(spec.hardDenyAllowlistMisses)
        XCTAssertEqual(spec.config.network.allowedDomains(), ["*.example.com"])
        XCTAssertEqual(spec.constraints.allowedDomains, ["*.example.com"])
        XCTAssertEqual(spec.constraints.allowlistExpansionEnabled, false)
    }

    func testManagedAllowedDomainsOnlyWithoutManagedAllowlistBlocksAllUserDomainsLikeRust() {
        var config = NetworkProxyConfig()
        config.network.setAllowedDomains(["api.example.com"])
        let requirements = NetworkRequirementsToml(
            managedAllowedDomainsOnly: true
        )

        let spec = NetworkProxySpec.fromConfigAndRequirements(
            config,
            requirements: requirements,
            permissionProfile: .readOnly()
        )

        XCTAssertEqual(spec.config.network.allowedDomains(), nil)
        XCTAssertEqual(spec.constraints.allowedDomains, [])
    }

    func testManagedUnrestrictedProfileAllowsDomainExpansionLikeRust() {
        var config = NetworkProxyConfig()
        config.network.setAllowedDomains(["api.example.com"])
        let requirements = NetworkRequirementsToml(
            domains: ["*.example.com": .allow]
        )
        let permissionProfile = PermissionProfile.managed(fileSystem: .unrestricted, network: .restricted)

        let spec = NetworkProxySpec.fromConfigAndRequirements(
            config,
            requirements: requirements,
            permissionProfile: permissionProfile
        )

        XCTAssertEqual(spec.config.network.allowedDomains(), ["*.example.com", "api.example.com"])
        XCTAssertEqual(spec.constraints.allowlistExpansionEnabled, true)
    }

    func testDangerFullAccessKeepsManagedAllowlistAndDenylistFixedLikeRust() {
        var config = NetworkProxyConfig()
        config.network.setAllowedDomains(["evil.com"])
        config.network.setDeniedDomains(["more-blocked.example.com"])
        let requirements = NetworkRequirementsToml(
            domains: [
                "*.example.com": .allow,
                "blocked.example.com": .deny
            ]
        )

        let spec = NetworkProxySpec.fromConfigAndRequirements(
            config,
            requirements: requirements,
            permissionProfile: .disabled
        )

        XCTAssertEqual(spec.config.network.allowedDomains(), ["*.example.com"])
        XCTAssertEqual(spec.config.network.deniedDomains(), ["blocked.example.com"])
        XCTAssertEqual(spec.constraints.allowlistExpansionEnabled, false)
        XCTAssertEqual(spec.constraints.denylistExpansionEnabled, false)
    }

    func testDenyOnlyRequirementsDoNotConstrainAllowlistInFullAccessLikeRust() {
        var config = NetworkProxyConfig()
        config.network.setAllowedDomains(["api.example.com"])
        let requirements = NetworkRequirementsToml(
            domains: ["managed-blocked.example.com": .deny]
        )

        let spec = NetworkProxySpec.fromConfigAndRequirements(
            config,
            requirements: requirements,
            permissionProfile: .disabled
        )

        XCTAssertEqual(spec.config.network.allowedDomains(), ["api.example.com"])
        XCTAssertNil(spec.constraints.allowedDomains)
        XCTAssertNil(spec.constraints.allowlistExpansionEnabled)
        XCTAssertEqual(spec.config.network.deniedDomains(), ["managed-blocked.example.com"])
        XCTAssertEqual(spec.constraints.deniedDomains, ["managed-blocked.example.com"])
        XCTAssertEqual(spec.constraints.denylistExpansionEnabled, false)
    }

    func testAllowOnlyRequirementsDoNotConstrainDenylistInFullAccessLikeRust() {
        var config = NetworkProxyConfig()
        config.network.setDeniedDomains(["blocked.example.com"])
        let requirements = NetworkRequirementsToml(
            domains: ["managed.example.com": .allow]
        )

        let spec = NetworkProxySpec.fromConfigAndRequirements(
            config,
            requirements: requirements,
            permissionProfile: .disabled
        )

        XCTAssertEqual(spec.config.network.allowedDomains(), ["managed.example.com"])
        XCTAssertEqual(spec.config.network.deniedDomains(), ["blocked.example.com"])
        XCTAssertNil(spec.constraints.deniedDomains)
        XCTAssertNil(spec.constraints.denylistExpansionEnabled)
    }

    func testRequirementsDeniedDomainsAreBaselineForDefaultModeLikeRust() {
        var config = NetworkProxyConfig()
        config.network.setDeniedDomains(["blocked.example.com"])
        let requirements = NetworkRequirementsToml(
            domains: ["managed-blocked.example.com": .deny]
        )

        let spec = NetworkProxySpec.fromConfigAndRequirements(
            config,
            requirements: requirements,
            permissionProfile: .workspaceWrite()
        )

        XCTAssertEqual(spec.config.network.deniedDomains(), [
            "managed-blocked.example.com",
            "blocked.example.com"
        ])
        XCTAssertEqual(spec.constraints.deniedDomains, ["managed-blocked.example.com"])
        XCTAssertEqual(spec.constraints.denylistExpansionEnabled, true)
    }

    func testRequirementsPortsAndUnixSocketsApplyToConfigAndConstraintsLikeRust() {
        let requirements = NetworkRequirementsToml(
            enabled: true,
            httpPort: 18080,
            socksPort: 18081,
            allowUpstreamProxy: false,
            dangerouslyAllowNonLoopbackProxy: true,
            dangerouslyAllowAllUnixSockets: false,
            unixSockets: [
                "/tmp/codex.sock": .allow,
                "/tmp/deny.sock": .none
            ],
            allowLocalBinding: true
        )

        let spec = NetworkProxySpec.fromConfigAndRequirements(
            requirements: requirements,
            permissionProfile: .readOnly()
        )

        XCTAssertTrue(spec.enabled)
        XCTAssertEqual(spec.config.network.proxyURL, "http://127.0.0.1:18080")
        XCTAssertEqual(spec.config.network.socksURL, "http://127.0.0.1:18081")
        XCTAssertEqual(spec.config.network.allowUpstreamProxy, false)
        XCTAssertEqual(spec.config.network.dangerouslyAllowNonLoopbackProxy, true)
        XCTAssertEqual(spec.config.network.dangerouslyAllowAllUnixSockets, false)
        XCTAssertEqual(spec.config.network.allowedUnixSockets(), ["/tmp/codex.sock"])
        XCTAssertEqual(spec.constraints.enabled, true)
        XCTAssertEqual(spec.constraints.allowUpstreamProxy, false)
        XCTAssertEqual(spec.constraints.allowUnixSockets, ["/tmp/codex.sock"])
        XCTAssertEqual(spec.constraints.allowLocalBinding, true)
    }
}
