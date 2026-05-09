import CodexCore
import XCTest

final class HookDispatcherTests: XCTestCase {
    func testSelectHandlersKeepsDuplicateStopHandlers() throws {
        let handlers = try [
            makeHandler(eventName: .stop, matcher: nil, command: "echo same", displayOrder: 0),
            makeHandler(eventName: .stop, matcher: nil, command: "echo same", displayOrder: 1)
        ]

        let selected = HookDispatcher.selectHandlers(handlers, eventName: .stop, matcherInput: nil)

        XCTAssertEqual(selected.map(\.displayOrder), [0, 1])
    }

    func testSelectHandlersKeepsOverlappingSessionStartMatchers() throws {
        let handlers = try [
            makeHandler(eventName: .sessionStart, matcher: "start.*", command: "echo same", displayOrder: 0),
            makeHandler(eventName: .sessionStart, matcher: "^startup$", command: "echo same", displayOrder: 1)
        ]

        let selected = HookDispatcher.selectHandlers(handlers, eventName: .sessionStart, matcherInput: "startup")

        XCTAssertEqual(selected.map(\.displayOrder), [0, 1])
    }

    func testCompactHooksMatchTrigger() throws {
        let handlers = try [
            makeHandler(eventName: .preCompact, matcher: "manual", command: "echo manual", displayOrder: 0),
            makeHandler(eventName: .preCompact, matcher: "auto", command: "echo auto", displayOrder: 1)
        ]

        let selected = HookDispatcher.selectHandlers(handlers, eventName: .preCompact, matcherInput: "manual")

        XCTAssertEqual(selected.map(\.displayOrder), [0])
    }

    func testToolUseHooksMatchToolNameAndStarMatcher() throws {
        let handlers = try [
            makeHandler(eventName: .preToolUse, matcher: "*", command: "echo all", displayOrder: 0),
            makeHandler(eventName: .preToolUse, matcher: "^Edit$", command: "echo edit", displayOrder: 1),
            makeHandler(eventName: .postToolUse, matcher: "^Bash$", command: "echo post", displayOrder: 2)
        ]

        let preSelected = HookDispatcher.selectHandlers(handlers, eventName: .preToolUse, matcherInput: "Bash")
        let postSelected = HookDispatcher.selectHandlers(handlers, eventName: .postToolUse, matcherInput: "Bash")

        XCTAssertEqual(preSelected.map(\.displayOrder), [0])
        XCTAssertEqual(postSelected.map(\.displayOrder), [2])
    }

    func testExactMatcherSupportsPipeAlternativesAndRegexOnlyForRegexPatterns() {
        XCTAssertTrue(HookDispatcher.matchesMatcher("Edit|Write", input: "Edit"))
        XCTAssertTrue(HookDispatcher.matchesMatcher("Edit|Write", input: "Write"))
        XCTAssertFalse(HookDispatcher.matchesMatcher("Edit|Write", input: "Bash"))
        XCTAssertTrue(HookDispatcher.matchesMatcher("^Bash", input: "BashOutput"))
        XCTAssertFalse(HookDispatcher.matchesMatcher("[", input: "Bash"))
        XCTAssertTrue(HookDispatcher.validateMatcherPattern("mcp__memory"))
    }

    func testMatcherAliasesMatchOncePerHandler() throws {
        let handlers = try [
            makeHandler(eventName: .preToolUse, matcher: "^apply_patch$", command: "echo apply_patch", displayOrder: 0),
            makeHandler(eventName: .preToolUse, matcher: "^Write$", command: "echo write", displayOrder: 1),
            makeHandler(eventName: .preToolUse, matcher: "^Edit$", command: "echo edit", displayOrder: 2),
            makeHandler(eventName: .preToolUse, matcher: "apply_patch|Write|Edit", command: "echo combined", displayOrder: 3)
        ]

        let selected = HookDispatcher.selectHandlers(
            handlers,
            eventName: .preToolUse,
            matcherInputs: HookDispatcher.matcherInputs(toolName: "apply_patch", matcherAliases: ["Write", "Edit"])
        )

        XCTAssertEqual(selected.map(\.displayOrder), [0, 1, 2, 3])
    }

    func testUserPromptSubmitIgnoresMatchers() throws {
        let handlers = try [
            makeHandler(eventName: .userPromptSubmit, matcher: "^hello", command: "echo first", displayOrder: 0),
            makeHandler(eventName: .userPromptSubmit, matcher: "[", command: "echo second", displayOrder: 1)
        ]

        let selected = HookDispatcher.selectHandlers(handlers, eventName: .userPromptSubmit, matcherInput: nil)

        XCTAssertEqual(selected.map(\.displayOrder), [0, 1])
    }

    func testRunningAndCompletedSummariesMatchRustDispatcherShape() throws {
        let handler = try makeHandler(
            eventName: .sessionStart,
            matcher: "startup",
            command: "echo boot",
            statusMessage: "warming up",
            source: .plugin,
            displayOrder: 7
        )

        let running = HookDispatcher.runningSummary(handler: handler, startedAt: 11)
        let completed = HookDispatcher.completedSummary(
            handler: handler,
            runResult: HookCommandRunResult(startedAt: 11, completedAt: 13, durationMs: 2_000),
            status: .completed,
            entries: [HookOutputEntry(kind: .context, text: "ready")]
        )

        XCTAssertEqual(running.id, "session-start:7:/tmp/hooks.json")
        XCTAssertEqual(running.handlerType, .command)
        XCTAssertEqual(running.executionMode, .sync)
        XCTAssertEqual(running.scope, .thread)
        XCTAssertEqual(running.source, .plugin)
        XCTAssertEqual(running.status, .running)
        XCTAssertEqual(running.statusMessage, "warming up")
        XCTAssertNil(running.completedAt)
        XCTAssertNil(running.durationMs)
        XCTAssertEqual(running.entries, [])
        XCTAssertEqual(completed.completedAt, 13)
        XCTAssertEqual(completed.durationMs, 2_000)
        XCTAssertEqual(completed.entries, [HookOutputEntry(kind: .context, text: "ready")])
    }

    func testScopeForEventMatchesRustDispatcher() {
        XCTAssertEqual(HookDispatcher.scope(for: .sessionStart), .thread)
        XCTAssertEqual(HookDispatcher.scope(for: .preToolUse), .turn)
        XCTAssertEqual(HookDispatcher.scope(for: .stop), .turn)
    }

    func testMatcherPatternForEventIgnoresUnsupportedEvents() {
        XCTAssertEqual(HookDispatcher.matcherPattern(for: .preToolUse, matcher: "Bash"), "Bash")
        XCTAssertNil(HookDispatcher.matcherPattern(for: .userPromptSubmit, matcher: "^hello"))
        XCTAssertNil(HookDispatcher.matcherPattern(for: .stop, matcher: "^done$"))
    }

    func testCommandRunnerBuildsDefaultAndCustomShellCommands() throws {
        let handler = try makeHandler(eventName: .preToolUse, matcher: nil, command: "echo $HOOK_VALUE", displayOrder: 0)
        var environment = ["SHELL": "/bin/zsh"]

        let defaultCommand = HookCommandRunner.buildCommand(
            shell: HookCommandShell(),
            handler: handler,
            environment: environment
        )
        XCTAssertEqual(defaultCommand.program, "/bin/zsh")
        XCTAssertEqual(defaultCommand.arguments, ["-lc", "echo $HOOK_VALUE"])

        let customCommand = HookCommandRunner.buildCommand(
            shell: HookCommandShell(program: "/bin/sh", arguments: ["-lc"]),
            handler: handler,
            environment: environment
        )
        XCTAssertEqual(customCommand.program, "/bin/sh")
        XCTAssertEqual(customCommand.arguments, ["-lc", "echo $HOOK_VALUE"])

        environment["HOOK_VALUE"] = "from-env"
        let envCommand = HookCommandRunner.buildCommand(shell: HookCommandShell(), handler: handler, environment: environment)
        XCTAssertEqual(envCommand.environment["HOOK_VALUE"], "from-env")
    }

    func testCommandRunnerCapturesStdoutStderrExitAndStdin() async throws {
        let handler = try makeHandler(
            eventName: .preToolUse,
            matcher: nil,
            command: "read line; printf \"out:%s\" \"$line\"; printf err >&2; exit 7",
            displayOrder: 0
        )

        let result = await HookCommandRunner.runCommand(
            shell: HookCommandShell(program: "/bin/sh", arguments: ["-c"]),
            handler: handler,
            inputJSON: "payload\n",
            cwd: URL(fileURLWithPath: "/tmp"),
            environment: [:]
        )

        XCTAssertEqual(result.exitCode, 7)
        XCTAssertEqual(result.stdout, "out:payload")
        XCTAssertEqual(result.stderr, "err")
        XCTAssertNil(result.error)
        XCTAssertGreaterThanOrEqual(result.completedAt, result.startedAt)
    }

    func testCommandRunnerReturnsSpawnError() async throws {
        let handler = try makeHandler(eventName: .preToolUse, matcher: nil, command: "echo nope", displayOrder: 0)

        let result = await HookCommandRunner.runCommand(
            shell: HookCommandShell(program: "/definitely/missing/codex-hook-shell", arguments: ["-lc"]),
            handler: handler,
            inputJSON: "{}",
            cwd: URL(fileURLWithPath: "/tmp"),
            environment: [:]
        )

        XCTAssertNil(result.exitCode)
        XCTAssertEqual(result.stdout, "")
        XCTAssertEqual(result.stderr, "")
        XCTAssertNotNil(result.error)
    }

    func testCommandRunnerTimesOutWithRustMessageShape() async throws {
        let handler = try makeHandler(
            eventName: .preToolUse,
            matcher: nil,
            command: "sleep 2",
            displayOrder: 0,
            timeoutSec: 1
        )

        let result = await HookCommandRunner.runCommand(
            shell: HookCommandShell(program: "/bin/sh", arguments: ["-c"]),
            handler: handler,
            inputJSON: "{}",
            cwd: URL(fileURLWithPath: "/tmp"),
            environment: [:]
        )

        XCTAssertNil(result.exitCode)
        XCTAssertEqual(result.stdout, "")
        XCTAssertEqual(result.stderr, "")
        XCTAssertEqual(result.error, "hook timed out after 1s")
    }
}

private func makeHandler(
    eventName: HookEventName,
    matcher: String?,
    command: String,
    statusMessage: String? = nil,
    source: HookSource = .user,
    displayOrder: Int64,
    timeoutSec: UInt64 = 5
) throws -> ConfiguredHookHandler {
    try ConfiguredHookHandler(
        eventName: eventName,
        matcher: matcher,
        command: command,
        timeoutSec: timeoutSec,
        statusMessage: statusMessage,
        sourcePath: AbsolutePath(absolutePath: "/tmp/hooks.json"),
        source: source,
        displayOrder: displayOrder
    )
}
