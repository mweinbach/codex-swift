import CodexCore
import XCTest

final class ContextUpdateBuilderTests: XCTestCase {
    func testBuildSettingsUpdateItemsInjectsFullEnvironmentWhenBaselineMissingLikeRust() {
        let current = contextItem(
            cwd: "/repo",
            currentDate: "2026-05-10",
            timezone: "America/New_York",
            network: TurnContextNetworkItem(
                allowedDomains: ["api.example.com"],
                deniedDomains: ["blocked.example.com"]
            )
        )

        let items = ContextUpdateBuilder.buildSettingsUpdateItems(
            previous: nil,
            current: current,
            shell: shell()
        )

        XCTAssertEqual(userTexts(in: items), ["""
        <environment_context>
          <cwd>/repo</cwd>
          <shell>bash</shell>
          <current_date>2026-05-10</current_date>
          <timezone>America/New_York</timezone>
          <network enabled="true">
            <allowed>api.example.com</allowed>
            <denied>blocked.example.com</denied>
          </network>
        </environment_context>
        """])
    }

    func testBuildSettingsUpdateItemsEmitsEnvironmentItemForNetworkChangesLikeRust() {
        let previous = contextItem(cwd: "/repo")
        let current = contextItem(
            cwd: "/repo",
            network: TurnContextNetworkItem(
                allowedDomains: ["api.example.com"],
                deniedDomains: ["blocked.example.com"]
            )
        )

        let items = ContextUpdateBuilder.buildSettingsUpdateItems(
            previous: previous,
            current: current,
            shell: shell()
        )

        XCTAssertEqual(userTexts(in: items), ["""
        <environment_context>
          <network enabled="true">
            <allowed>api.example.com</allowed>
            <denied>blocked.example.com</denied>
          </network>
        </environment_context>
        """])
    }

    func testBuildSettingsUpdateItemsEmitsEnvironmentItemForTimeChangesLikeRust() {
        let previous = contextItem(cwd: "/repo", currentDate: "2026-05-09", timezone: "America/New_York")
        let current = contextItem(cwd: "/repo", currentDate: "2026-05-10", timezone: "Europe/Berlin")

        let items = ContextUpdateBuilder.buildSettingsUpdateItems(
            previous: previous,
            current: current,
            shell: shell()
        )

        XCTAssertEqual(userTexts(in: items), ["""
        <environment_context>
          <current_date>2026-05-10</current_date>
          <timezone>Europe/Berlin</timezone>
        </environment_context>
        """])
    }

    func testBuildSettingsUpdateItemsEmitsEnvironmentItemForCwdChangesLikeRust() {
        let previous = contextItem(cwd: "/repo")
        let current = contextItem(cwd: "/repo/subdir")

        let items = ContextUpdateBuilder.buildSettingsUpdateItems(
            previous: previous,
            current: current,
            shell: shell()
        )

        XCTAssertEqual(userTexts(in: items), ["""
        <environment_context>
          <cwd>/repo/subdir</cwd>
          <shell>bash</shell>
        </environment_context>
        """])
    }

    func testBuildSettingsUpdateItemsOmitsEnvironmentWhenDisabledLikeRust() {
        let previous = contextItem(cwd: "/repo")
        let current = contextItem(cwd: "/repo/subdir")

        let items = ContextUpdateBuilder.buildSettingsUpdateItems(
            previous: previous,
            current: current,
            shell: shell(),
            includeEnvironmentContext: false
        )

        XCTAssertEqual(userTexts(in: items), [])
    }

    func testBuildSettingsUpdateItemsEmitsRealtimeStartAndEndLikeRust() {
        let inactive = contextItem(cwd: "/repo", realtimeActive: false)
        let active = contextItem(cwd: "/repo", realtimeActive: true)

        let startItems = ContextUpdateBuilder.buildSettingsUpdateItems(
            previous: inactive,
            current: active,
            shell: shell()
        )
        XCTAssertTrue(developerTexts(in: startItems).contains { $0.contains("<realtime_conversation>") })
        XCTAssertTrue(developerTexts(in: startItems).contains { $0.contains("Realtime conversation started.") })

        let endItems = ContextUpdateBuilder.buildSettingsUpdateItems(
            previous: active,
            current: inactive,
            shell: shell()
        )
        XCTAssertTrue(developerTexts(in: endItems).contains { $0.contains("Realtime conversation ended.") })
        XCTAssertTrue(developerTexts(in: endItems).contains { $0.contains("Reason: inactive") })
    }

    func testBuildSettingsUpdateItemsUsesPreviousTurnSettingsForRealtimeEndLikeRust() {
        let previous = contextItem(cwd: "/repo", realtimeActive: nil)
        let current = contextItem(cwd: "/repo", realtimeActive: false)

        let items = ContextUpdateBuilder.buildSettingsUpdateItems(
            previous: previous,
            current: current,
            shell: shell(),
            previousRealtimeActive: true
        )

        XCTAssertTrue(developerTexts(in: items).contains { $0.contains("Reason: inactive") })
    }

    func testBuildSettingsUpdateItemsUsesCustomRealtimeStartInstructionsLikeRust() {
        let items = ContextUpdateBuilder.buildSettingsUpdateItems(
            previous: contextItem(cwd: "/repo", realtimeActive: false),
            current: contextItem(cwd: "/repo", realtimeActive: true),
            shell: shell(),
            realtimeStartInstructions: "Custom realtime start"
        )

        XCTAssertEqual(developerTexts(in: items), ["""
        <realtime_conversation>
        Custom realtime start
        </realtime_conversation>
        """])
    }

    func testBuildSettingsUpdateItemsPreservesEmptyCustomRealtimeStartInstructionsLikeRust() {
        let items = ContextUpdateBuilder.buildSettingsUpdateItems(
            previous: contextItem(cwd: "/repo", realtimeActive: false),
            current: contextItem(cwd: "/repo", realtimeActive: true),
            shell: shell(),
            realtimeStartInstructions: ""
        )

        XCTAssertEqual(developerTexts(in: items), ["<realtime_conversation>\n\n</realtime_conversation>"])
    }
}

private func contextItem(
    cwd: String,
    currentDate: String? = nil,
    timezone: String? = nil,
    network: TurnContextNetworkItem? = nil,
    realtimeActive: Bool? = nil
) -> TurnContextItem {
    TurnContextItem(
        cwd: cwd,
        currentDate: currentDate,
        timezone: timezone,
        approvalPolicy: .onRequest,
        sandboxPolicy: .readOnly,
        network: network,
        model: "gpt-5.4",
        realtimeActive: realtimeActive,
        summary: .auto
    )
}

private func shell() -> Shell {
    Shell(shellType: .bash, shellPath: "/bin/bash")
}

private func userTexts(in items: [ResponseItem]) -> [String] {
    texts(in: items, role: "user")
}

private func developerTexts(in items: [ResponseItem]) -> [String] {
    texts(in: items, role: "developer")
}

private func texts(in items: [ResponseItem], role expectedRole: String) -> [String] {
    items.flatMap { item -> [String] in
        guard case let .message(_, role, content, _) = item, role == expectedRole else {
            return []
        }
        return content.compactMap { item in
            guard case let .inputText(text) = item else {
                return nil
            }
            return text
        }
    }
}
