import CodexCore
import XCTest

final class SandboxSummaryTests: XCTestCase {
    func testSummarizesSimplePolicies() {
        XCTAssertEqual(SandboxSummary.summarize(.dangerFullAccess), "danger-full-access")
        XCTAssertEqual(SandboxSummary.summarize(.readOnly), "read-only")
    }

    func testSummarizesExternalSandboxWithoutNetworkAccessSuffix() {
        let summary = SandboxSummary.summarize(.externalSandbox(networkAccess: .restricted))

        XCTAssertEqual(summary, "external-sandbox")
    }

    func testSummarizesExternalSandboxWithEnabledNetwork() {
        let summary = SandboxSummary.summarize(.externalSandbox(networkAccess: .enabled))

        XCTAssertEqual(summary, "external-sandbox (network access enabled)")
    }

    func testWorkspaceWriteSummaryUsesDefaultWritableEntries() {
        let summary = SandboxSummary.summarize(.workspaceWrite(
            writableRoots: [],
            networkAccess: false,
            excludeTmpdirEnvVar: false,
            excludeSlashTmp: false
        ))

        XCTAssertEqual(summary, "workspace-write [workdir, /tmp, $TMPDIR]")
    }

    func testWorkspaceWriteSummaryStillIncludesNetworkAccess() throws {
        let writableRoot = try AbsolutePath(absolutePath: "/repo")
        let summary = SandboxSummary.summarize(.workspaceWrite(
            writableRoots: [writableRoot],
            networkAccess: true,
            excludeTmpdirEnvVar: true,
            excludeSlashTmp: true
        ))

        XCTAssertEqual(summary, "workspace-write [workdir, /repo] (network access enabled)")
    }
}
