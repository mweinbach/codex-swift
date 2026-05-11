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

    func testDenyOnlyRequirementsDoNotConstrainAllowlistInFullAccessLikeRust() {
        var config = NetworkProxyConfig()
        config.network.setAllowedDomains(["api.example.com"])
        let requirements = NetworkRequirementsToml(
            domains: ["managed-blocked.example.com": .deny]
        )

        let spec = NetworkProxySpec.fromConfigAndRequirements(
            config,
            requirements: requirements,
            permissionProfile: .fromLegacySandboxPolicy(.dangerFullAccess)
        )

        XCTAssertEqual(spec.config.network.allowedDomains(), ["api.example.com"])
        XCTAssertNil(spec.constraints.allowedDomains)
        XCTAssertNil(spec.constraints.allowlistExpansionEnabled)
        XCTAssertEqual(spec.config.network.deniedDomains(), ["managed-blocked.example.com"])
        XCTAssertEqual(spec.constraints.deniedDomains, ["managed-blocked.example.com"])
        XCTAssertEqual(spec.constraints.denylistExpansionEnabled, false)
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
