import CodexCore
import XCTest

final class ReviewAnalyticsTests: XCTestCase {
    func testCodexCommandExecutionEventRequestUsesRustWireShape() throws {
        let actions: [AppServerProtocol.CommandAction] = [
            .read(command: "cat README.md", name: "README.md", path: "/repo/README.md"),
            .listFiles(command: "ls Sources", path: "/repo/Sources"),
            .search(command: "rg TODO", query: "TODO", path: nil),
            .unknown(command: "swift test")
        ]
        let event = CodexCommandExecutionEventRequest(
            eventType: "codex_command_execution_event",
            eventParams: CodexCommandExecutionEventParams(
                base: CodexToolItemEventBase(
                    threadID: "thread-1",
                    turnID: "turn-1",
                    itemID: "item-1",
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
                    toolName: "shell",
                    startedAtMilliseconds: 123_000,
                    completedAtMilliseconds: 125_000,
                    durationMilliseconds: 2_000,
                    executionDurationMilliseconds: 1_900,
                    reviewCount: 0,
                    guardianReviewCount: 0,
                    userReviewCount: 0,
                    finalApprovalOutcome: .notNeeded,
                    terminalStatus: .completed,
                    failureKind: nil,
                    requestedAdditionalPermissions: false,
                    requestedNetworkAccess: false
                ),
                commandExecutionSource: .agent,
                exitCode: 0,
                commandActionCounts: CodexCommandActionCounts(actions: actions)
            )
        )

        try XCTAssertJSONObjectEqual(event, [
            "event_type": "codex_command_execution_event",
            "event_params": [
                "thread_id": "thread-1",
                "turn_id": "turn-1",
                "item_id": "item-1",
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
                "tool_name": "shell",
                "started_at_ms": 123_000,
                "completed_at_ms": 125_000,
                "duration_ms": 2_000,
                "execution_duration_ms": 1_900,
                "review_count": 0,
                "guardian_review_count": 0,
                "user_review_count": 0,
                "final_approval_outcome": "not_needed",
                "terminal_status": "completed",
                "failure_kind": nil,
                "requested_additional_permissions": false,
                "requested_network_access": false,
                "command_execution_source": "agent",
                "exit_code": 0,
                "command_total_action_count": 4,
                "command_read_action_count": 1,
                "command_list_files_action_count": 1,
                "command_search_action_count": 1,
                "command_unknown_action_count": 1
            ]
        ])
    }

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
            ],
            "tool_item_outcomes": [
                "unknown",
                "not_needed",
                "config_allowed",
                "policy_forbidden",
                "guardian_approved",
                "guardian_denied",
                "guardian_aborted",
                "user_approved",
                "user_approved_for_session",
                "user_denied",
                "user_aborted"
            ],
            "tool_item_statuses": [
                "completed",
                "failed",
                "rejected",
                "interrupted"
            ],
            "tool_item_failure_kinds": [
                "tool_error",
                "approval_denied",
                "approval_aborted",
                "sandbox_denied",
                "policy_forbidden"
            ],
            "command_execution_sources": [
                "agent",
                "user_shell",
                "unified_exec_startup",
                "unified_exec_interaction"
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
        let toolItemOutcomes: [ToolItemFinalApprovalOutcome] = [
            .unknown,
            .notNeeded,
            .configAllowed,
            .policyForbidden,
            .guardianApproved,
            .guardianDenied,
            .guardianAborted,
            .userApproved,
            .userApprovedForSession,
            .userDenied,
            .userAborted
        ]
        let toolItemStatuses: [ToolItemTerminalStatus] = [
            .completed,
            .failed,
            .rejected,
            .interrupted
        ]
        let toolItemFailureKinds: [ToolItemFailureKind] = [
            .toolError,
            .approvalDenied,
            .approvalAborted,
            .sandboxDenied,
            .policyForbidden
        ]
        let commandExecutionSources: [CommandExecutionSource] = [
            .agent,
            .userShell,
            .unifiedExecStartup,
            .unifiedExecInteraction
        ]

        private enum CodingKeys: String, CodingKey {
            case toolKinds = "tool_kinds"
            case reviewers
            case triggers
            case statuses
            case resolutions
            case toolItemOutcomes = "tool_item_outcomes"
            case toolItemStatuses = "tool_item_statuses"
            case toolItemFailureKinds = "tool_item_failure_kinds"
            case commandExecutionSources = "command_execution_sources"
        }
    }
}
