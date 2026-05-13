import CodexCore
import XCTest

final class SlashCommandTests: XCTestCase {
    func testBuiltInCommandsPreserveRustPresentationOrder() {
        let commands = SlashCommand.builtInCommands(includeDebugCommands: true).map(\.0)
        XCTAssertEqual(commands, [
            "model",
            "approvals",
            "experimental",
            "skills",
            "review",
            "new",
            "resume",
            "init",
            "compact",
            "diff",
            "mention",
            "status",
            "mcp",
            "logout",
            "quit",
            "exit",
            "feedback",
            "rollout",
            "ps",
            "test-approval"
        ])
    }

    func testDebugCommandsAreHiddenWhenRequested() {
        let commands = SlashCommand.builtInCommands(includeDebugCommands: false).map(\.0)
        XCTAssertFalse(commands.contains("rollout"))
        XCTAssertFalse(commands.contains("test-approval"))
    }

    func testAvailabilityDuringTaskMatchesRustLogic() {
        XCTAssertFalse(SlashCommand.model.availableDuringTask)
        XCTAssertFalse(SlashCommand.review.availableDuringTask)
        XCTAssertTrue(SlashCommand.diff.availableDuringTask)
        XCTAssertTrue(SlashCommand.quit.availableDuringTask)
    }

    func testCatalogPreservesBuiltInCommandsWhenServiceTiersAreDisabled() {
        let commands = SlashCommandCatalog.commands(
            options: SlashCommandOptions(
                includeDebugCommands: true,
                serviceTierCommandsEnabled: false,
                serviceTiers: [
                    ModelServiceTier(id: "priority", name: "fast", description: "Fastest inference.")
                ]
            )
        )

        XCTAssertEqual(commands, SlashCommand.builtInCommands(includeDebugCommands: true).map { .builtIn($0.1) })
        XCTAssertNil(
            SlashCommandCatalog.find(
                "fast",
                options: SlashCommandOptions(
                    includeDebugCommands: true,
                    serviceTierCommandsEnabled: false,
                    serviceTiers: [
                        ModelServiceTier(id: "priority", name: "fast", description: "Fastest inference.")
                    ]
                )
            )
        )
    }

    func testCatalogInsertsServiceTierCommandsAfterModel() {
        let fast = ModelServiceTier(id: "priority", name: "fast", description: "Fastest inference.")
        let slow = ModelServiceTier(id: "batch", name: "slow", description: "Lower-priority inference.")
        let commands = SlashCommandCatalog.commands(
            options: SlashCommandOptions(
                includeDebugCommands: true,
                serviceTierCommandsEnabled: true,
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
        let options = SlashCommandOptions(
            includeDebugCommands: true,
            serviceTierCommandsEnabled: true,
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
        let options = SlashCommandOptions(
            includeDebugCommands: true,
            serviceTierCommandsEnabled: true,
            serviceTiers: [
                ModelServiceTier(id: "shadow", name: "model", description: "Should not replace the built-in command.")
            ]
        )

        XCTAssertEqual(SlashCommandCatalog.find("model", options: options), .builtIn(.model))
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
        XCTAssertEqual(command.command, "fast")
        XCTAssertEqual(command.description, "Fastest inference.")
    }
}
