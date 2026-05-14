import CodexCore
import XCTest

final class ReviewAnalyticsTests: XCTestCase {
    func testCodexReviewEventRequestUsesRustWireShape() throws {
        let event = CodexReviewEventRequest(
            eventType: "codex_review_event",
            eventParams: CodexReviewEventParams(
                threadID: "thread-1",
                turnID: "turn-1",
                itemID: nil,
                reviewID: "review-1",
                appServerClient: CodexAppServerClientMetadata(
                    productClientID: "codex_tui",
                    clientName: "codex-tui",
                    clientVersion: "1.2.3",
                    rpcTransport: .websocket,
                    experimentalAPIEnabled: true
                ),
                runtime: CodexRuntimeMetadata(
                    codexRSVersion: "0.99.0",
                    runtimeOS: "macos",
                    runtimeOSVersion: "15.3.1",
                    runtimeArch: "aarch64"
                ),
                threadSource: .user,
                subagentSource: nil,
                parentThreadID: nil,
                toolKind: .mcpToolCall,
                toolName: "mcp__example__run",
                reviewer: .guardian,
                trigger: .networkPolicyDenial,
                status: .approved,
                resolution: .networkPolicyAmendment,
                startedAtMilliseconds: 123_000,
                completedAtMilliseconds: 124_500,
                durationMilliseconds: nil
            )
        )

        try XCTAssertJSONObjectEqual(event, [
            "event_type": "codex_review_event",
            "event_params": [
                "thread_id": "thread-1",
                "turn_id": "turn-1",
                "item_id": nil,
                "review_id": "review-1",
                "app_server_client": [
                    "product_client_id": "codex_tui",
                    "client_name": "codex-tui",
                    "client_version": "1.2.3",
                    "rpc_transport": "websocket",
                    "experimental_api_enabled": true
                ],
                "runtime": [
                    "codex_rs_version": "0.99.0",
                    "runtime_os": "macos",
                    "runtime_os_version": "15.3.1",
                    "runtime_arch": "aarch64"
                ],
                "thread_source": "user",
                "subagent_source": nil,
                "parent_thread_id": nil,
                "tool_kind": "mcp_tool_call",
                "tool_name": "mcp__example__run",
                "reviewer": "guardian",
                "trigger": "network_policy_denial",
                "status": "approved",
                "resolution": "network_policy_amendment",
                "started_at_ms": 123_000,
                "completed_at_ms": 124_500,
                "duration_ms": nil
            ]
        ])
    }

    func testReviewAnalyticsEnumsUseRustSnakeCaseValues() throws {
        try XCTAssertJSONObjectEqual(EnumSamples(), [
            "tool_kinds": [
                "command_execution",
                "file_change",
                "mcp_tool_call",
                "permissions",
                "network_access"
            ],
            "reviewers": [
                "guardian",
                "user"
            ],
            "triggers": [
                "initial",
                "sandbox_denial",
                "network_policy_denial",
                "execve_intercept"
            ],
            "statuses": [
                "approved",
                "denied",
                "aborted",
                "timed_out"
            ],
            "resolutions": [
                "none",
                "session_approval",
                "exec_policy_amendment",
                "network_policy_amendment"
            ]
        ])
    }

    private struct EnumSamples: Encodable {
        let toolKinds: [ReviewSubjectKind] = [
            .commandExecution,
            .fileChange,
            .mcpToolCall,
            .permissions,
            .networkAccess
        ]
        let reviewers: [ReviewAnalyticsReviewer] = [.guardian, .user]
        let triggers: [ReviewTrigger] = [
            .initial,
            .sandboxDenial,
            .networkPolicyDenial,
            .execveIntercept
        ]
        let statuses: [ReviewStatus] = [.approved, .denied, .aborted, .timedOut]
        let resolutions: [ReviewResolution] = [
            .none,
            .sessionApproval,
            .execPolicyAmendment,
            .networkPolicyAmendment
        ]

        private enum CodingKeys: String, CodingKey {
            case toolKinds = "tool_kinds"
            case reviewers
            case triggers
            case statuses
            case resolutions
        }
    }
}
