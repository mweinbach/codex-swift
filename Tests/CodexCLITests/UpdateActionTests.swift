import CodexCLI
import XCTest

final class UpdateActionTests: XCTestCase {
    func testCommandArgsMatchRustActions() {
        XCTAssertEqual(UpdateAction.npmGlobalLatest.commandArgs().command, "npm")
        XCTAssertEqual(UpdateAction.npmGlobalLatest.commandArgs().arguments, ["install", "-g", "@openai/codex"])
        XCTAssertEqual(UpdateAction.bunGlobalLatest.commandArgs().command, "bun")
        XCTAssertEqual(UpdateAction.bunGlobalLatest.commandArgs().arguments, ["install", "-g", "@openai/codex"])
        XCTAssertEqual(UpdateAction.brewUpgrade.commandArgs().command, "brew")
        XCTAssertEqual(UpdateAction.brewUpgrade.commandArgs().arguments, ["upgrade", "codex"])
    }

    func testCommandStringMatchesRustShellRendering() {
        XCTAssertEqual(UpdateAction.npmGlobalLatest.commandString(), "npm install -g @openai/codex")
        XCTAssertEqual(UpdateAction.bunGlobalLatest.commandString(), "bun install -g @openai/codex")
        XCTAssertEqual(UpdateAction.brewUpgrade.commandString(), "brew upgrade codex")
    }

    func testDetectUpdateActionWithoutEnvironmentMutation() {
        XCTAssertNil(UpdateAction.detect(
            isMacOS: false,
            currentExecutablePath: "/any/path",
            managedByNPM: false,
            managedByBUN: false
        ))
        XCTAssertEqual(UpdateAction.detect(
            isMacOS: false,
            currentExecutablePath: "/any/path",
            managedByNPM: true,
            managedByBUN: false
        ), .npmGlobalLatest)
        XCTAssertEqual(UpdateAction.detect(
            isMacOS: false,
            currentExecutablePath: "/any/path",
            managedByNPM: false,
            managedByBUN: true
        ), .bunGlobalLatest)
        XCTAssertEqual(UpdateAction.detect(
            isMacOS: true,
            currentExecutablePath: "/opt/homebrew/bin/codex",
            managedByNPM: false,
            managedByBUN: false
        ), .brewUpgrade)
        XCTAssertEqual(UpdateAction.detect(
            isMacOS: true,
            currentExecutablePath: "/usr/local/bin/codex",
            managedByNPM: false,
            managedByBUN: false
        ), .brewUpgrade)
    }

    func testManagedEnvironmentWinsBeforeHomebrewPath() {
        XCTAssertEqual(UpdateAction.detect(
            isMacOS: true,
            currentExecutablePath: "/opt/homebrew/bin/codex",
            managedByNPM: true,
            managedByBUN: true
        ), .npmGlobalLatest)
        XCTAssertEqual(UpdateAction.detect(
            isMacOS: true,
            currentExecutablePath: "/opt/homebrew/bin/codex",
            managedByNPM: false,
            managedByBUN: true
        ), .bunGlobalLatest)
    }

    func testHomebrewDetectionUsesPathComponentPrefix() {
        XCTAssertNil(UpdateAction.detect(
            isMacOS: true,
            currentExecutablePath: "/opt/homebrewish/bin/codex",
            managedByNPM: false,
            managedByBUN: false
        ))
    }

    func testDetectCurrentReadsEnvironmentFlags() {
        XCTAssertEqual(UpdateAction.detectCurrent(
            environment: ["CODEX_MANAGED_BY_NPM": "1"],
            currentExecutablePath: "/any/path",
            isMacOS: false
        ), .npmGlobalLatest)
        XCTAssertEqual(UpdateAction.detectCurrent(
            environment: ["CODEX_MANAGED_BY_BUN": "1"],
            currentExecutablePath: "/any/path",
            isMacOS: false
        ), .bunGlobalLatest)
    }

    func testNormalizedCommandArgsForWSLUsesPathHelper() {
        let normalized = UpdateAction.brewUpgrade.normalizedCommandArgsForWSL(isWSL: true)

        XCTAssertEqual(normalized.command, "brew")
        XCTAssertEqual(normalized.arguments, ["upgrade", "codex"])
    }
}
