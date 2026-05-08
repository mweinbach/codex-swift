import CodexCore
import XCTest

final class GuardianAssessmentTests: XCTestCase {
    func testGuardianAssessmentEventWireShapeAndDefaults() throws {
        let event = GuardianAssessmentEvent(
            id: "guardian-1",
            status: .inProgress,
            action: .command(source: .unifiedExec, command: "git status", cwd: "/repo")
        )

        try XCTAssertJSONObjectEqual(event, [
            "id": "guardian-1",
            "turn_id": "",
            "started_at_ms": 0,
            "status": "in_progress",
            "action": [
                "type": "command",
                "source": "unified_exec",
                "command": "git status",
                "cwd": "/repo"
            ]
        ])

        let decoded = try JSONDecoder().decode(GuardianAssessmentEvent.self, from: Data("""
        {
          "id": "guardian-2",
          "status": "aborted",
          "action": {
            "type": "apply_patch",
            "cwd": "/repo",
            "files": ["/repo/a.swift"]
          }
        }
        """.utf8))
        XCTAssertEqual(decoded.turnID, "")
        XCTAssertEqual(decoded.startedAtMilliseconds, 0)
    }

    func testGuardianAssessmentActionVariantsUseRustTaggedShape() throws {
        let actions: [(GuardianAssessmentAction, [String: Any])] = [
            (.execve(source: .shell, program: "/bin/rm", argv: ["rm", "-rf", "build"], cwd: "/repo"), [
                "type": "execve",
                "source": "shell",
                "program": "/bin/rm",
                "argv": ["rm", "-rf", "build"],
                "cwd": "/repo"
            ]),
            (.networkAccess(target: "https://example.com", host: "example.com", protocol: .socks5Tcp, port: 443), [
                "type": "network_access",
                "target": "https://example.com",
                "host": "example.com",
                "protocol": "socks5_tcp",
                "port": 443
            ]),
            (.mcpToolCall(
                server: "github",
                toolName: "create_issue",
                connectorID: "conn-1",
                connectorName: "GitHub",
                toolTitle: "Create issue"
            ), [
                "type": "mcp_tool_call",
                "server": "github",
                "tool_name": "create_issue",
                "connector_id": "conn-1",
                "connector_name": "GitHub",
                "tool_title": "Create issue"
            ]),
            (.requestPermissions(
                reason: "Need network",
                permissions: RequestPermissionProfile(network: RequestPermissionNetworkPermissions(enabled: true))
            ), [
                "type": "request_permissions",
                "reason": "Need network",
                "permissions": [
                    "network": [
                        "enabled": true
                    ]
                ]
            ])
        ]

        for (action, expected) in actions {
            try XCTAssertJSONObjectEqual(action, expected)
            let data = try JSONEncoder().encode(action)
            XCTAssertEqual(try JSONDecoder().decode(GuardianAssessmentAction.self, from: data), action)
        }
    }

    func testNetworkApprovalProtocolDecodesRustAliases() throws {
        XCTAssertEqual(try decodeProtocol(#""https""#), .https)
        XCTAssertEqual(try decodeProtocol(#""https_connect""#), .https)
        XCTAssertEqual(try decodeProtocol(#""http-connect""#), .https)
    }

    private func decodeProtocol(_ json: String) throws -> NetworkApprovalProtocol {
        try JSONDecoder().decode(NetworkApprovalProtocol.self, from: Data(json.utf8))
    }
}
