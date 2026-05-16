import XCTest
@testable import CodexCore

final class ConfigSummaryTests: XCTestCase {
    func testRendersExecStartupBannerWithoutResearchPreviewSuffix() {
        let output = ConfigSummary.renderStartupBanner(
            version: "1.2.3",
            entries: [
                ConfigSummaryEntry("workdir", "/repo"),
                ConfigSummaryEntry("model", "gpt-5.1-codex")
            ]
        )

        XCTAssertEqual(output, """
        OpenAI Codex v1.2.3
        --------
        workdir: /repo
        model: gpt-5.1-codex
        """)
        XCTAssertFalse(output.contains("research preview"))
    }

    func testCreatesResponsesProviderSummaryEntriesInRustOrder() {
        let entries = ConfigSummary.createEntries(
            config: ConfigSummaryInput(
                workdir: "/repo",
                modelProviderID: "openai",
                approvalPolicy: .onRequest,
                sandboxPolicy: .newWorkspaceWritePolicy(),
                modelProviderWireAPI: .responses,
                modelReasoningEffort: .high,
                modelReasoningSummary: .detailed
            ),
            model: "gpt-5.1-codex"
        )

        XCTAssertEqual(entries, [
            ConfigSummaryEntry("workdir", "/repo"),
            ConfigSummaryEntry("model", "gpt-5.1-codex"),
            ConfigSummaryEntry("provider", "openai"),
            ConfigSummaryEntry("approval", "on-request"),
            ConfigSummaryEntry("sandbox", "workspace-write [workdir, /tmp, $TMPDIR]"),
            ConfigSummaryEntry("reasoning effort", "high"),
            ConfigSummaryEntry("reasoning summaries", "detailed")
        ])
    }

    func testPermissionProfileSummaryUsesRuntimeWorkspaceRootsLikeRust() throws {
        let hiddenRoot = try AbsolutePath(absolutePath: "/repo/.hidden-write")
        let permissionProfile = PermissionProfile.workspaceWriteWith(
            writableRoots: [hiddenRoot],
            network: .restricted
        )

        let summary = SandboxSummary.summarize(
            permissionProfile: permissionProfile,
            cwd: "/repo",
            effectiveWorkspaceRoots: ["/repo", "/repo-extra"]
        )

        XCTAssertEqual(summary, "workspace-write [workdir, /tmp, $TMPDIR, /repo-extra]")
        XCTAssertFalse(summary.contains(hiddenRoot.path))
    }

    func testConfigEntriesUsePermissionProfileRuntimeWorkspaceRootsLikeRust() {
        let entries = ConfigSummary.createEntries(
            config: ConfigSummaryInput(
                workdir: "/repo",
                modelProviderID: "openai",
                approvalPolicy: .onRequest,
                sandboxPolicy: .newWorkspaceWritePolicy(),
                permissionProfile: .workspaceWrite(),
                effectiveWorkspaceRoots: ["/repo", "/repo-extra"],
                modelProviderWireAPI: .responses,
                modelReasoningEffort: .high,
                modelReasoningSummary: .detailed
            ),
            model: "gpt-5.1-codex"
        )

        XCTAssertEqual(entries[4], ConfigSummaryEntry("sandbox", "workspace-write [workdir, /tmp, $TMPDIR, /repo-extra]"))
    }

    func testPermissionProfileSummaryFallsBackToCustomPermissionsLikeRust() {
        let permissionProfile = PermissionProfile.managed(
            fileSystem: .restricted(
                entries: [
                    FileSystemSandboxEntry(path: .path("/outside"), access: .write)
                ],
                globScanMaxDepth: nil
            ),
            network: .enabled
        )

        let summary = SandboxSummary.summarize(
            permissionProfile: permissionProfile,
            cwd: "/repo",
            effectiveWorkspaceRoots: ["/repo"]
        )

        XCTAssertEqual(summary, "custom permissions (network access enabled)")
    }

    func testResponsesProviderSummaryUsesNoneWhenReasoningEffortIsMissing() {
        let entries = ConfigSummary.createEntries(
            config: ConfigSummaryInput(
                workdir: "/repo",
                modelProviderID: "openai",
                approvalPolicy: .never,
                sandboxPolicy: .dangerFullAccess,
                modelProviderWireAPI: .responses,
                modelReasoningEffort: nil,
                modelReasoningSummary: .auto
            ),
            model: "gpt-5.1"
        )

        XCTAssertEqual(entries.suffix(2), [
            ConfigSummaryEntry("reasoning effort", "none"),
            ConfigSummaryEntry("reasoning summaries", "auto")
        ])
    }

    func testChatProviderSummarySkipsReasoningEntries() {
        let entries = ConfigSummary.createEntries(
            config: ConfigSummaryInput(
                workdir: "/repo",
                modelProviderID: "openai-chat-completions",
                approvalPolicy: .unlessTrusted,
                sandboxPolicy: .readOnly,
                modelProviderWireAPI: .chat,
                modelReasoningEffort: .high,
                modelReasoningSummary: .detailed
            ),
            model: "gpt-3.5-turbo"
        )

        XCTAssertEqual(entries, [
            ConfigSummaryEntry("workdir", "/repo"),
            ConfigSummaryEntry("model", "gpt-3.5-turbo"),
            ConfigSummaryEntry("provider", "openai-chat-completions"),
            ConfigSummaryEntry("approval", "untrusted"),
            ConfigSummaryEntry("sandbox", "read-only")
        ])
    }
}
