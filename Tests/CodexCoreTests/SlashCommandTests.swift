import CodexCore
import XCTest

final class SlashCommandTests: XCTestCase {
    func testBuiltInCommandsPreserveRustPresentationOrder() {
        let commands = SlashCommand.builtInCommands(includeDebugCommands: true).map(\.0)
        var expected = [
            "model",
            "ide",
            "permissions",
            "keymap",
            "vim",
            "setup-default-sandbox"
        ]
        #if os(Windows)
        expected.append("sandbox-add-read-dir")
        #endif
        expected.append(contentsOf: [
            "experimental",
            "approve",
            "memories",
            "skills",
            "hooks",
            "review",
            "rename",
            "new",
            "resume",
            "fork",
            "init",
            "compact",
            "plan",
            "goal",
            "collab",
            "agent",
            "side",
            "copy",
            "raw",
            "diff",
            "mention",
            "status",
            "debug-config",
            "title",
            "statusline",
            "theme",
            "mcp",
            "apps",
            "plugins",
            "logout",
            "quit",
            "exit",
            "feedback",
            "rollout",
            "ps",
            "stop",
            "clear",
            "personality",
            "realtime",
            "settings",
            "test-approval",
            "subagents",
            "debug-m-drop",
            "debug-m-update"
        ])
        XCTAssertEqual(commands, expected)
    }

    func testDebugCommandsAreHiddenWhenRequested() {
        let commands = SlashCommand.builtInCommands(includeDebugCommands: false).map(\.0)
        XCTAssertFalse(commands.contains("rollout"))
        XCTAssertFalse(commands.contains("test-approval"))
        XCTAssertTrue(commands.contains("debug-m-drop"))
        XCTAssertTrue(commands.contains("debug-m-update"))
    }

    func testCommandAliasesAndCanonicalNamesMatchRust() {
        XCTAssertEqual(SlashCommand.stop.command, "stop")
        XCTAssertEqual(SlashCommand.from(commandName: "stop"), .stop)
        XCTAssertEqual(SlashCommand.from(commandName: "clean"), .stop)
        XCTAssertEqual(SlashCommand.autoReview.command, "approve")
        XCTAssertEqual(SlashCommand.from(commandName: "approve"), .autoReview)
    }

    func testAvailabilityDuringTaskMatchesRustLogic() {
        XCTAssertFalse(SlashCommand.model.availableDuringTask)
        XCTAssertFalse(SlashCommand.review.availableDuringTask)
        XCTAssertFalse(SlashCommand.theme.availableDuringTask)
        XCTAssertTrue(SlashCommand.goal.availableDuringTask)
        XCTAssertTrue(SlashCommand.ide.availableDuringTask)
        XCTAssertTrue(SlashCommand.title.availableDuringTask)
        XCTAssertTrue(SlashCommand.statusline.availableDuringTask)
        XCTAssertTrue(SlashCommand.raw.availableDuringTask)
        XCTAssertTrue(SlashCommand.diff.availableDuringTask)
        XCTAssertTrue(SlashCommand.quit.availableDuringTask)
    }

    func testInlineArgsAndSideConversationFlagsMatchRustLogic() {
        let inlineCommands = Set(SlashCommand.allCases.filter(\.supportsInlineArgs).map(\.command))
        XCTAssertEqual(
            inlineCommands,
            [
                "review",
                "rename",
                "plan",
                "goal",
                "ide",
                "keymap",
                "mcp",
                "raw",
                "side",
                "resume",
                "sandbox-add-read-dir"
            ]
        )

        let sideCommands = SlashCommand.builtInCommands(
            options: allEnabledOptions(sideConversationActive: true)
        ).map(\.1)
        XCTAssertEqual(sideCommands, [.ide, .copy, .raw, .diff, .mention, .status])
        XCTAssertTrue(SlashCommand.raw.supportsInlineArgs)
        XCTAssertTrue(SlashCommand.raw.availableInSideConversation)
    }

    func testCatalogPreservesBuiltInCommandsWhenServiceTiersAreDisabled() {
        let options = allEnabledOptions(
            serviceTierCommandsEnabled: false,
            serviceTiers: [
                ModelServiceTier(id: "priority", name: "fast", description: "Fastest inference.")
            ]
        )
        let commands = SlashCommandCatalog.commands(
            options: options
        )

        XCTAssertEqual(commands, SlashCommand.builtInCommands(options: options).map { .builtIn($0.1) })
        XCTAssertNil(
            SlashCommandCatalog.find(
                "fast",
                options: options
            )
        )
    }

    func testCatalogInsertsServiceTierCommandsAfterModel() {
        let fast = ModelServiceTier(id: "priority", name: "fast", description: "Fastest inference.")
        let slow = ModelServiceTier(id: "batch", name: "slow", description: "Lower-priority inference.")
        let commands = SlashCommandCatalog.commands(
            options: allEnabledOptions(
                serviceTiers: [fast, slow]
            )
        )
        let modelIndex = commands.firstIndex(of: .builtIn(.model))

        XCTAssertEqual(modelIndex, 0)
        XCTAssertEqual(
            Array(commands.prefix(3)),
            [
                .builtIn(.model),
                .serviceTier(ServiceTierSlashCommand(modelServiceTier: fast)),
                .serviceTier(ServiceTierSlashCommand(modelServiceTier: slow))
            ]
        )
    }

    func testCatalogFindResolvesServiceTierByNameAndPreservesRequestId() {
        let options = allEnabledOptions(
            serviceTiers: [
                ModelServiceTier(id: "priority", name: "fast", description: "Fastest inference.")
            ]
        )

        XCTAssertEqual(
            SlashCommandCatalog.find("fast", options: options),
            .serviceTier(
                ServiceTierSlashCommand(
                    id: "priority",
                    name: "fast",
                    description: "Fastest inference."
                )
            )
        )
    }

    func testCatalogFindPrefersBuiltInCommandsOverServiceTierNameCollisions() {
        let options = allEnabledOptions(
            serviceTiers: [
                ModelServiceTier(id: "shadow", name: "model", description: "Should not replace the built-in command.")
            ]
        )

        XCTAssertEqual(SlashCommandCatalog.find("model", options: options), .builtIn(.model))
    }

    func testFeatureGatedCommandsMatchRustFlags() {
        XCTAssertNil(SlashCommandCatalog.find("goal", options: allEnabledOptions(goalCommandEnabled: false)))
        XCTAssertNil(SlashCommandCatalog.find("realtime", options: allEnabledOptions(realtimeConversationEnabled: false)))
        XCTAssertNil(
            SlashCommandCatalog.find(
                "settings",
                options: allEnabledOptions(audioDeviceSelectionEnabled: false)
            )
        )
        XCTAssertNil(
            SlashCommandCatalog.find(
                "settings",
                options: allEnabledOptions(
                    realtimeConversationEnabled: false,
                    audioDeviceSelectionEnabled: false
                )
            )
        )
        XCTAssertNil(
            SlashCommandCatalog.find(
                "setup-default-sandbox",
                options: allEnabledOptions(allowElevateSandbox: false)
            )
        )
        XCTAssertEqual(SlashCommandCatalog.find("goal", options: allEnabledOptions()), .builtIn(.goal))
    }

    func testSideConversationExactLookupStillResolvesHiddenCommandsForDispatch() {
        let fast = ModelServiceTier(id: "priority", name: "fast", description: "Fastest inference.")
        let options = allEnabledOptions(sideConversationActive: true, serviceTiers: [fast])

        XCTAssertEqual(SlashCommandCatalog.commands(options: options).map(\.command), [
            "ide",
            "copy",
            "raw",
            "diff",
            "mention",
            "status"
        ])
        XCTAssertEqual(SlashCommandCatalog.find("review", options: options), .builtIn(.review))
        XCTAssertEqual(
            SlashCommandCatalog.find("fast", options: options),
            .serviceTier(ServiceTierSlashCommand(modelServiceTier: fast))
        )
    }

    func testServiceTierCommandsAreUnavailableDuringTasks() {
        let command = SlashCommandItem.serviceTier(
            ServiceTierSlashCommand(
                id: "priority",
                name: "fast",
                description: "Fastest inference."
            )
        )

        XCTAssertFalse(command.availableDuringTask)
        XCTAssertFalse(command.supportsInlineArgs)
        XCTAssertFalse(command.availableInSideConversation)
        XCTAssertEqual(command.command, "fast")
        XCTAssertEqual(command.description, "Fastest inference.")
    }

    private func allEnabledOptions(
        includeDebugCommands: Bool = true,
        collaborationModesEnabled: Bool = true,
        connectorsEnabled: Bool = true,
        pluginsCommandEnabled: Bool = true,
        serviceTierCommandsEnabled: Bool = true,
        goalCommandEnabled: Bool = true,
        personalityCommandEnabled: Bool = true,
        realtimeConversationEnabled: Bool = true,
        audioDeviceSelectionEnabled: Bool = true,
        allowElevateSandbox: Bool = true,
        sideConversationActive: Bool = false,
        serviceTiers: [ModelServiceTier] = []
    ) -> SlashCommandOptions {
        SlashCommandOptions(
            includeDebugCommands: includeDebugCommands,
            collaborationModesEnabled: collaborationModesEnabled,
            connectorsEnabled: connectorsEnabled,
            pluginsCommandEnabled: pluginsCommandEnabled,
            serviceTierCommandsEnabled: serviceTierCommandsEnabled,
            goalCommandEnabled: goalCommandEnabled,
            personalityCommandEnabled: personalityCommandEnabled,
            realtimeConversationEnabled: realtimeConversationEnabled,
            audioDeviceSelectionEnabled: audioDeviceSelectionEnabled,
            allowElevateSandbox: allowElevateSandbox,
            sideConversationActive: sideConversationActive,
            serviceTiers: serviceTiers
        )
    }
}
