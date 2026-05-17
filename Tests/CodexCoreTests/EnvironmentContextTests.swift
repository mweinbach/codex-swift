import XCTest
@testable import CodexCore

final class EnvironmentContextTests: XCTestCase {
    func testSerializeWorkspaceWriteEnvironmentContext() throws {
        let cwd = "/repo"
        let writableRoot = "/tmp/codex"
        let context = EnvironmentContext(
            cwd: cwd,
            approvalPolicy: .onRequest,
            sandboxPolicy: .workspaceWrite(
                writableRoots: [
                    try AbsolutePath(absolutePath: cwd),
                    try AbsolutePath(absolutePath: writableRoot)
                ],
                networkAccess: false,
                excludeTmpdirEnvVar: false,
                excludeSlashTmp: false
            ),
            shell: fakeShell()
        )

        XCTAssertEqual(context.serializeToXML(), """
        <environment_context>
          <cwd>/repo</cwd>
          <approval_policy>on-request</approval_policy>
          <sandbox_mode>workspace-write</sandbox_mode>
          <network_access>restricted</network_access>
          <writable_roots>
            <root>/repo</root>
            <root>/tmp/codex</root>
          </writable_roots>
          <shell>bash</shell>
        </environment_context>
        """)
    }

    func testSerializeReadOnlyEnvironmentContext() {
        let context = EnvironmentContext(
            cwd: nil,
            approvalPolicy: .never,
            sandboxPolicy: .readOnly,
            shell: fakeShell()
        )

        XCTAssertEqual(context.serializeToXML(), """
        <environment_context>
          <approval_policy>never</approval_policy>
          <sandbox_mode>read-only</sandbox_mode>
          <network_access>restricted</network_access>
          <shell>bash</shell>
        </environment_context>
        """)
    }

    func testSerializeExternalSandboxEnvironmentContext() {
        let context = EnvironmentContext(
            cwd: nil,
            approvalPolicy: .onRequest,
            sandboxPolicy: .externalSandbox(networkAccess: .enabled),
            shell: fakeShell()
        )

        XCTAssertEqual(context.serializeToXML(), """
        <environment_context>
          <approval_policy>on-request</approval_policy>
          <sandbox_mode>danger-full-access</sandbox_mode>
          <network_access>enabled</network_access>
          <shell>bash</shell>
        </environment_context>
        """)
    }

    func testSerializeExternalSandboxWithRestrictedNetworkEnvironmentContext() {
        let context = EnvironmentContext(
            cwd: nil,
            approvalPolicy: .onRequest,
            sandboxPolicy: .externalSandbox(networkAccess: .restricted),
            shell: fakeShell()
        )

        XCTAssertEqual(context.serializeToXML(), """
        <environment_context>
          <approval_policy>on-request</approval_policy>
          <sandbox_mode>danger-full-access</sandbox_mode>
          <network_access>restricted</network_access>
          <shell>bash</shell>
        </environment_context>
        """)
    }

    func testSerializeFullAccessEnvironmentContext() {
        let context = EnvironmentContext(
            cwd: nil,
            approvalPolicy: .onFailure,
            sandboxPolicy: .dangerFullAccess,
            shell: fakeShell()
        )

        XCTAssertEqual(context.serializeToXML(), """
        <environment_context>
          <approval_policy>on-failure</approval_policy>
          <sandbox_mode>danger-full-access</sandbox_mode>
          <network_access>enabled</network_access>
          <shell>bash</shell>
        </environment_context>
        """)
    }

    func testSerializeMultipleConfiguredEnvironments() {
        let context = EnvironmentContext(
            cwd: "/ignored",
            approvalPolicy: .never,
            sandboxPolicy: .dangerFullAccess,
            shell: fakeShell(),
            environments: [
                EnvironmentContextEnvironment(id: "dev", cwd: "/repo/dev", shell: "bash"),
                EnvironmentContextEnvironment(id: "local", cwd: "/repo/local", shell: "zsh")
            ],
            currentDate: "2026-02-26",
            timezone: "America/Los_Angeles"
        )

        XCTAssertEqual(context.serializeToXML(), #"""
        <environment_context>
          <environments>
            <environment id="dev">
              <cwd>/repo/dev</cwd>
              <shell>bash</shell>
            </environment>
            <environment id="local">
              <cwd>/repo/local</cwd>
              <shell>zsh</shell>
            </environment>
          </environments>
          <current_date>2026-02-26</current_date>
          <timezone>America/Los_Angeles</timezone>
        </environment_context>
        """#)
    }

    func testEqualsExceptShellComparesDateContext() {
        let context1 = EnvironmentContext(
            cwd: "/repo",
            approvalPolicy: .never,
            sandboxPolicy: .readOnly,
            shell: fakeShell(),
            currentDate: "2026-02-26",
            timezone: "America/Los_Angeles"
        )
        let context2 = EnvironmentContext(
            cwd: "/repo",
            approvalPolicy: .never,
            sandboxPolicy: .readOnly,
            shell: Shell(shellType: .zsh, shellPath: "/bin/zsh"),
            currentDate: "2026-02-27",
            timezone: "America/Los_Angeles"
        )

        XCTAssertFalse(context1.equalsExceptShell(context2))
    }

    func testSerializeEnvironmentContextWithNetwork() {
        let context = EnvironmentContext(
            cwd: "/repo",
            approvalPolicy: .never,
            sandboxPolicy: .readOnly,
            shell: fakeShell(),
            currentDate: "2026-02-26",
            timezone: "America/Los_Angeles",
            network: EnvironmentContextNetwork(
                allowedDomains: ["api.example.com", "*.openai.com"],
                deniedDomains: ["blocked.example.com"]
            )
        )

        XCTAssertEqual(context.serializeToXML(), #"""
        <environment_context>
          <cwd>/repo</cwd>
          <approval_policy>never</approval_policy>
          <sandbox_mode>read-only</sandbox_mode>
          <network_access>restricted</network_access>
          <shell>bash</shell>
          <current_date>2026-02-26</current_date>
          <timezone>America/Los_Angeles</timezone>
          <network enabled="true">
            <allowed>api.example.com</allowed>
            <allowed>*.openai.com</allowed>
            <denied>blocked.example.com</denied>
          </network>
        </environment_context>
        """#)
    }

    func testEqualsExceptShellComparesApprovalPolicy() throws {
        let context1 = EnvironmentContext(
            cwd: "/repo",
            approvalPolicy: .onRequest,
            sandboxPolicy: try workspaceWritePolicy(writableRoots: ["/repo"], networkAccess: false),
            shell: fakeShell()
        )
        let context2 = EnvironmentContext(
            cwd: "/repo",
            approvalPolicy: .never,
            sandboxPolicy: try workspaceWritePolicy(writableRoots: ["/repo"], networkAccess: true),
            shell: fakeShell()
        )

        XCTAssertFalse(context1.equalsExceptShell(context2))
    }

    func testEqualsExceptShellComparesSandboxPolicy() {
        let context1 = EnvironmentContext(
            cwd: "/repo",
            approvalPolicy: .onRequest,
            sandboxPolicy: .newReadOnlyPolicy(),
            shell: fakeShell()
        )
        let context2 = EnvironmentContext(
            cwd: "/repo",
            approvalPolicy: .onRequest,
            sandboxPolicy: .newWorkspaceWritePolicy(),
            shell: fakeShell()
        )

        XCTAssertFalse(context1.equalsExceptShell(context2))
    }

    func testEqualsExceptShellComparesWorkspaceWritePolicy() throws {
        let context1 = EnvironmentContext(
            cwd: "/repo",
            approvalPolicy: .onRequest,
            sandboxPolicy: try workspaceWritePolicy(writableRoots: ["/repo", "/tmp", "/var"], networkAccess: false),
            shell: fakeShell()
        )
        let context2 = EnvironmentContext(
            cwd: "/repo",
            approvalPolicy: .onRequest,
            sandboxPolicy: try workspaceWritePolicy(writableRoots: ["/repo", "/tmp"], networkAccess: true),
            shell: fakeShell()
        )

        XCTAssertFalse(context1.equalsExceptShell(context2))
    }

    func testEqualsExceptShellIgnoresShell() throws {
        let context1 = EnvironmentContext(
            cwd: "/repo",
            approvalPolicy: .onRequest,
            sandboxPolicy: try workspaceWritePolicy(writableRoots: ["/repo"], networkAccess: false),
            shell: Shell(shellType: .bash, shellPath: "/bin/bash")
        )
        let context2 = EnvironmentContext(
            cwd: "/repo",
            approvalPolicy: .onRequest,
            sandboxPolicy: try workspaceWritePolicy(writableRoots: ["/repo"], networkAccess: false),
            shell: Shell(shellType: .zsh, shellPath: "/bin/zsh")
        )

        XCTAssertTrue(context1.equalsExceptShell(context2))
    }

    func testDiffIncludesOnlyChangedTurnContextValues() throws {
        let before = TurnContext(
            cwd: "/repo",
            approvalPolicy: .onRequest,
            sandboxPolicy: try workspaceWritePolicy(writableRoots: ["/repo"], networkAccess: false)
        )
        let after = TurnContext(
            cwd: "/repo/subdir",
            approvalPolicy: .onRequest,
            sandboxPolicy: try workspaceWritePolicy(writableRoots: ["/repo"], networkAccess: true)
        )

        let diff = EnvironmentContext.diff(before: before, after: after, shell: fakeShell())

        XCTAssertEqual(diff.cwd, "/repo/subdir")
        XCTAssertNil(diff.approvalPolicy)
        XCTAssertEqual(diff.sandboxMode, .workspaceWrite)
        XCTAssertEqual(diff.networkAccess, .enabled)
        XCTAssertEqual(diff.writableRoots, [try AbsolutePath(absolutePath: "/repo")])
    }

    func testTurnContextSelectedEnvironmentCwdPreservesLegacyCwdValueLikeRust() {
        let turnContext = TurnContext(
            cwd: "/repo",
            approvalPolicy: .never,
            sandboxPolicy: .readOnly
        )

        XCTAssertEqual(turnContext.selectedEnvironmentCwd, "/repo")
    }

    func testFromTurnContextAndResponseItem() {
        let turnContext = TurnContext(
            cwd: "/repo",
            approvalPolicy: .never,
            sandboxPolicy: .readOnly
        )

        let context = EnvironmentContext.fromTurnContext(turnContext, shell: fakeShell())

        XCTAssertEqual(context.cwd, "/repo")
        XCTAssertEqual(context.asResponseItem(), .message(
            role: "user",
            content: [.inputText(text: context.serializeToXML())]
        ))
    }

    func testEnvironmentContextCodableShapeUsesSnakeCaseFields() throws {
        let context = EnvironmentContext(
            cwd: "/repo",
            approvalPolicy: .onRequest,
            sandboxPolicy: .workspaceWrite(
                writableRoots: [try AbsolutePath(absolutePath: "/repo")],
                networkAccess: false,
                excludeTmpdirEnvVar: false,
                excludeSlashTmp: false
            ),
            shell: fakeShell()
        )

        try XCTAssertJSONObjectEqual(context, [
            "cwd": "/repo",
            "approval_policy": "on-request",
            "sandbox_mode": "workspace-write",
            "network_access": "restricted",
            "writable_roots": ["/repo"],
            "shell": [
                "shell_type": "Bash",
                "shell_path": "/bin/bash"
            ]
        ])
    }

    private func fakeShell() -> Shell {
        Shell(shellType: .bash, shellPath: "/bin/bash")
    }

    private func workspaceWritePolicy(writableRoots: [String], networkAccess: Bool) throws -> SandboxPolicy {
        .workspaceWrite(
            writableRoots: try writableRoots.map { try AbsolutePath(absolutePath: $0) },
            networkAccess: networkAccess,
            excludeTmpdirEnvVar: false,
            excludeSlashTmp: false
        )
    }
}
