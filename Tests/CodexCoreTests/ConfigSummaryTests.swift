import XCTest
@testable import CodexCore

final class ConfigSummaryTests: XCTestCase {
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
