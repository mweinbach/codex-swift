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

    func testBuildSettingsUpdateItemsPrependsModelSwitchInstructionsLikeRust() {
        let previous = contextItem(cwd: "/repo", model: "previous-regular-model")
        let current = contextItem(cwd: "/repo", model: "gpt-5.4", personality: .friendly)
        let modelInfo = modelInfo(
            slug: "gpt-5.4",
            baseInstructions: "base instructions",
            modelMessages: ModelMessages(
                instructionsTemplate: "Base\n{{ personality }}",
                instructionsVariables: ModelInstructionsVariables(
                    personalityDefault: "default style",
                    personalityFriendly: "friendly style",
                    personalityPragmatic: "pragmatic style"
                )
            )
        )

        let items = ContextUpdateBuilder.buildSettingsUpdateItems(
            previous: previous,
            current: current,
            shell: shell(),
            previousModel: previous.model,
            currentModelInfo: modelInfo
        )

        XCTAssertEqual(developerTexts(in: items), ["""
        <model_switch>

        The user was previously using a different model. Please continue the conversation according to the following instructions:

        Base
        friendly style

        </model_switch>
        """])
    }

    func testBuildSettingsUpdateItemsOmitsModelSwitchWhenInstructionsEmptyLikeRust() {
        let previous = contextItem(cwd: "/repo", model: "old-model")
        let current = contextItem(cwd: "/repo", model: "new-model")

        let items = ContextUpdateBuilder.buildSettingsUpdateItems(
            previous: previous,
            current: current,
            shell: shell(),
            previousModel: previous.model,
            currentModelInfo: modelInfo(slug: "new-model", baseInstructions: "")
        )

        XCTAssertEqual(developerTexts(in: items), [])
    }

    func testBuildSettingsUpdateItemsEmitsPermissionsBeforeCollaborationLikeRust() throws {
        let previous = contextItem(
            cwd: "/repo",
            approvalPolicy: .never,
            permissionProfile: .readOnly(),
            collaborationMode: CollaborationMode(
                mode: .defaultMode,
                settings: CollaborationModeSettings(model: "gpt-5.4")
            )
        )
        let current = contextItem(
            cwd: "/repo",
            approvalPolicy: .onRequest,
            permissionProfile: .workspaceWrite(),
            collaborationMode: CollaborationMode(
                mode: .plan,
                settings: CollaborationModeSettings(
                    model: "gpt-5.4",
                    developerInstructions: "Plan before editing."
                )
            )
        )

        let items = ContextUpdateBuilder.buildSettingsUpdateItems(
            previous: previous,
            current: current,
            shell: shell(),
            execPermissionApprovalsEnabled: true
        )
        let texts = developerTexts(in: items)

        XCTAssertEqual(texts.count, 2)
        XCTAssertTrue(texts[0].contains("<permissions instructions>"))
        XCTAssertTrue(texts[0].contains("`sandbox_mode` is `workspace-write`"))
        XCTAssertTrue(texts[0].contains("with_additional_permissions"))
        XCTAssertEqual(texts[1], """
        <collaboration_mode>
        Plan before editing.
        </collaboration_mode>
        """)
    }

    func testBuildSettingsUpdateItemsOmitsPermissionsWhenUnchangedOrDisabledLikeRust() {
        let previous = contextItem(cwd: "/repo", approvalPolicy: .onRequest, permissionProfile: .readOnly())
        let current = contextItem(cwd: "/repo", approvalPolicy: .onRequest, permissionProfile: .readOnly())

        XCTAssertEqual(
            developerTexts(in: ContextUpdateBuilder.buildSettingsUpdateItems(
                previous: previous,
                current: current,
                shell: shell()
            )),
            []
        )
        XCTAssertEqual(
            developerTexts(in: ContextUpdateBuilder.buildSettingsUpdateItems(
                previous: previous,
                current: contextItem(cwd: "/repo", approvalPolicy: .never, permissionProfile: .readOnly()),
                shell: shell(),
                includePermissionsInstructions: false
            )),
            []
        )
    }

    func testBuildSettingsUpdateItemsEmitsCollaborationModeInstructionsLikeRust() {
        let previous = contextItem(
            cwd: "/repo",
            collaborationMode: CollaborationMode(
                mode: .defaultMode,
                settings: CollaborationModeSettings(model: "gpt-5.4")
            )
        )
        let current = contextItem(
            cwd: "/repo",
            collaborationMode: CollaborationMode(
                mode: .plan,
                settings: CollaborationModeSettings(
                    model: "gpt-5.4",
                    developerInstructions: "Plan before editing."
                )
            )
        )

        let items = ContextUpdateBuilder.buildSettingsUpdateItems(
            previous: previous,
            current: current,
            shell: shell()
        )

        XCTAssertEqual(developerTexts(in: items), ["""
        <collaboration_mode>
        Plan before editing.
        </collaboration_mode>
        """])
    }

    func testBuildSettingsUpdateItemsOmitsEmptyCollaborationModeInstructionsLikeRust() {
        let previous = contextItem(
            cwd: "/repo",
            collaborationMode: CollaborationMode(
                mode: .plan,
                settings: CollaborationModeSettings(
                    model: "gpt-5.4",
                    developerInstructions: "Plan first."
                )
            )
        )
        let current = contextItem(
            cwd: "/repo",
            collaborationMode: CollaborationMode(
                mode: .defaultMode,
                settings: CollaborationModeSettings(model: "gpt-5.4", developerInstructions: "")
            )
        )

        let items = ContextUpdateBuilder.buildSettingsUpdateItems(
            previous: previous,
            current: current,
            shell: shell()
        )

        XCTAssertEqual(developerTexts(in: items), [])
    }

    func testBuildSettingsUpdateItemsOmitsCollaborationModeInstructionsWhenDisabledLikeRust() {
        let previous = contextItem(
            cwd: "/repo",
            collaborationMode: CollaborationMode(
                mode: .defaultMode,
                settings: CollaborationModeSettings(model: "gpt-5.4")
            )
        )
        let current = contextItem(
            cwd: "/repo",
            collaborationMode: CollaborationMode(
                mode: .plan,
                settings: CollaborationModeSettings(
                    model: "gpt-5.4",
                    developerInstructions: "Plan before editing."
                )
            )
        )

        let items = ContextUpdateBuilder.buildSettingsUpdateItems(
            previous: previous,
            current: current,
            shell: shell(),
            includeCollaborationModeInstructions: false
        )

        XCTAssertEqual(developerTexts(in: items), [])
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

    func testBuildSettingsUpdateItemsEmitsPersonalitySpecWhenFeatureEnabledLikeRust() {
        let previous = contextItem(cwd: "/repo", personality: .friendly)
        let current = contextItem(cwd: "/repo", personality: .pragmatic)

        let items = ContextUpdateBuilder.buildSettingsUpdateItems(
            previous: previous,
            current: current,
            shell: shell(),
            currentModelInfo: modelInfo(
                slug: current.model,
                modelMessages: ModelMessages(
                    instructionsTemplate: "Base\n{{ personality }}",
                    instructionsVariables: ModelInstructionsVariables(
                        personalityDefault: "default style",
                        personalityFriendly: "friendly style",
                        personalityPragmatic: "pragmatic style"
                    )
                )
            )
        )

        XCTAssertEqual(developerTexts(in: items), [
            "<personality_spec>\n"
                + " The user has requested a new communication style. Future messages should adhere to the following personality: \n"
                + "pragmatic style \n"
                + "</personality_spec>"
        ])
    }

    func testBuildSettingsUpdateItemsOmitsPersonalitySpecWhenModelChangedLikeRust() {
        let previous = contextItem(cwd: "/repo", model: "old-model", personality: .friendly)
        let current = contextItem(cwd: "/repo", model: "new-model", personality: .pragmatic)
        let modelInfo = modelInfo(
            slug: "new-model",
            baseInstructions: "new instructions",
            modelMessages: ModelMessages(
                instructionsTemplate: "Base\n{{ personality }}",
                instructionsVariables: ModelInstructionsVariables(
                    personalityDefault: "default style",
                    personalityFriendly: "friendly style",
                    personalityPragmatic: "pragmatic style"
                )
            )
        )

        let changedModelItems = ContextUpdateBuilder.buildSettingsUpdateItems(
            previous: previous,
            current: current,
            shell: shell(),
            currentModelInfo: modelInfo
        )

        XCTAssertEqual(developerTexts(in: changedModelItems), [])
    }
}

private func contextItem(
    cwd: String,
    currentDate: String? = nil,
    timezone: String? = nil,
    network: TurnContextNetworkItem? = nil,
    approvalPolicy: AskForApproval = .onRequest,
    permissionProfile: PermissionProfile? = nil,
    model: String = "gpt-5.4",
    personality: Personality? = nil,
    collaborationMode: CollaborationMode? = nil,
    realtimeActive: Bool? = nil
) -> TurnContextItem {
    TurnContextItem(
        cwd: cwd,
        currentDate: currentDate,
        timezone: timezone,
        approvalPolicy: approvalPolicy,
        sandboxPolicy: .readOnly,
        permissionProfile: permissionProfile,
        network: network,
        model: model,
        personality: personality,
        collaborationMode: collaborationMode,
        realtimeActive: realtimeActive,
        summary: .auto
    )
}

private func shell() -> Shell {
    Shell(shellType: .bash, shellPath: "/bin/bash")
}

private func modelInfo(
    slug: String,
    baseInstructions: String = "base instructions",
    modelMessages: ModelMessages? = nil
) -> ModelInfo {
    ModelInfo(
        slug: slug,
        displayName: slug,
        supportedReasoningLevels: [],
        shellType: .default,
        visibility: .hide,
        supportedInAPI: false,
        priority: 0,
        baseInstructions: baseInstructions,
        modelMessages: modelMessages,
        supportsReasoningSummaries: false,
        supportVerbosity: false,
        truncationPolicy: .bytes(4096),
        supportsParallelToolCalls: false,
        experimentalSupportedTools: []
    )
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
