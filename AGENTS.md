# Codex Swift Port

This repository is a SwiftPM port of the Rust Codex project in
`/Users/mweinbach/Projects/codex`. Treat the Rust implementation as the
behavioral contract. Preserve Rust wire shapes, error strings, ordering,
defaults, persistence formats, and config semantics unless `Docs/PORTING.md`
explicitly records an intentional Swift limitation.

## Swift Porting Rules

- Search by concrete Rust route, type, file, or behavior before editing. Useful
  examples include `thread/read`, `thread/unsubscribe`, `turn/start`,
  `configRequirements/read`, `mcpServer/resource/read`, `plugin/read`, and
  `sessions-import`.
- Keep each slice narrow and test-backed. Update `Docs/PORTING.md` whenever a
  Rust behavior is ported, verified, or still known to be incomplete.
- Prefer existing Swift targets and helper APIs over inventing new abstractions.
- Do not overwrite unrelated local changes. Work with any user edits already in
  the tree.
- Do not add product claims to docs unless the Swift implementation actually
  supports the behavior or the doc clearly marks it as pending.

## Swift API Style

- Avoid ambiguous `Bool`, numeric, or optional parameters that make call sites
  read like `foo(false)`, `bar(nil)`, or `load(0)`. Prefer enums, option
  structs, named methods, labeled overloads, or small value types that make the
  call site self-documenting.
- Prefer external argument labels that describe the decision being made, not the
  storage detail. For example, prefer
  `loadHistory(limit: .unbounded)` or `setExpanded(false, animated: false)`
  over unlabeled sentinels or positional `nil` values.
- Avoid unlabeled parameters except for conventional first arguments where the
  call site remains clear, such as collection transforms, `XCTAssertEqual`, or
  domain APIs that read naturally as a sentence.
- When an existing unlabeled or weakly labeled API cannot be changed and an
  opaque literal is unavoidable, add an exact Swift argument comment before the
  literal: `setExpanded(/* animated: */ false)`,
  `loadHistory(/* limit: */ 0)`, or
  `decode(/* allowUnknownVariants: */ true)`.
- The comment text should match the callee's external argument label. If the
  argument is intentionally unlabeled, match the local parameter name from the
  function declaration. Do not invent a friendlier alias; the point is to make
  review catch drift between the call site and the signature.
- Do not add argument comments for string literals, enum cases, static members,
  or values that are already clear from labels unless the comment adds real
  clarity. Prefer improving the API shape over adding comments when the API is
  local to the Swift port.
- Prefer Swift string interpolation over `String(format:)` when no fixed
  locale, numeric precision, or C-format compatibility is required.
- Prefer exhaustive `switch` statements for Swift enums. Avoid `default` and
  `@unknown default` unless the enum is intentionally open-ended, imported from
  an Apple framework, or forward-compatible decoding explicitly needs an
  unknown bucket to match Rust behavior.
- Newly added protocols should include doc comments explaining the protocol's
  role, who implements it, and what invariants callers may rely on.
- Avoid boolean state pairs when a single enum models the state more accurately.
- Avoid small helper methods that are referenced only once unless they isolate a
  non-obvious parity rule or improve testability.
- Keep implementation details `internal` or `private` by default. Make APIs
  `public` only when another package target or executable actually needs them.
- Prefer adding focused files over expanding large orchestration files. Move
  tests and parity notes close to the implementation that owns the behavior.

## Swift Concurrency

- Prefer native Swift `async` protocol requirements for asynchronous contracts,
  for example `func load(...) async throws -> Value`.
- Add `Sendable` conformance to value types that cross task, actor, or callback
  boundaries.
- Mark escaping concurrent closures as `@Sendable` when they can run across
  concurrency domains.
- Avoid `@unchecked Sendable`, `nonisolated(unsafe)`, and `@preconcurrency`
  unless there is a specific interoperability reason. If one is necessary, keep
  the scope small and document the invariant in code or tests.
- Do not use broad annotations to silence concurrency checking around protocol
  requirements. Spell actor isolation, `Sendable` constraints, and async
  ownership in the protocol or wrapper type that defines the contract.
- Do not use detached tasks as a shortcut around ownership or lifetime problems.
  Prefer structured tasks, explicit cancellation paths, and injected clocks or
  transports in tests.
- For protocol requirements that cross concurrency domains, spell the async
  contract directly with `async`/`throws`, return `Sendable` values where
  relevant, and keep implementations actor-safe instead of bypassing checking
  with broad annotations.
- When async work needs to outlive a scope, keep ownership explicit with a
  stored `Task`, cancellation path, or actor boundary. Do not hide lifetime
  problems behind detached work.

## Codable And Wire Shapes

- Keep app-server and protocol payload fields camelCase unless the Rust API or
  config TOML compatibility requires snake_case.
- Preserve Rust optional behavior exactly: distinguish omitted fields from
  explicit `null` where Rust does.
- Swift `nil` is not automatically equivalent to Rust `None`. Check the Rust
  `serde` attributes before choosing between `encodeIfPresent`, explicit
  `null`, a default value, or a custom tri-state wrapper for omitted/null/value
  semantics.
- For tagged unions, keep the Rust tag names, variant names, defaults, and
  unknown-variant behavior.
- Prefer whole-object encode/decode assertions over field-by-field checks when
  testing wire shapes.
- When adding app-server v2 request/response/notification models, keep method
  names in `<resource>/<method>` form and use singular resource names.
- Config RPC payloads may use snake_case when mirroring `config.toml` keys.
- Decode unknown or future variants only where Rust accepts them. If Rust rejects
  a malformed or unknown value, preserve the rejection and error text where the
  Swift surface exposes that text.

## Module Boundaries

- `CodexCore` owns shared protocol models, config parsing, rollout persistence,
  sandbox/permission helpers, hooks, MCP models, and non-interactive runtime
  logic. Resist growing it when a narrower target already owns the behavior.
- `CodexCLI` owns CLI parsing and command dispatch.
- `CodexAppServer` owns JSON-RPC app-server request handling and notifications.
- `CodexMCPServer` owns the MCP server entrypoint.
- `CodexApplyPatch` owns patch parsing and application.
- `CodexGit` owns Swift git helpers.
- Prefer adding focused files over expanding already-large files. If a file is
  becoming a catch-all, move the new behavior and its tests toward a smaller
  module boundary.
- If you add a first-party executable or resource lookup, keep it stable under
  SwiftPM test execution and from changed working directories. Prefer injected
  paths in tests over assuming the process starts at the package root.

## Tests

- Start with the focused test filter for the changed area, then broaden to
  adjacent tests, then run the full suite.
- Prefer equality over whole objects where practical. Use targeted field checks
  only when the object contains nondeterministic data or a very large fixture
  would obscure the parity rule.
- Avoid mutating process-global state in tests. Prefer injecting environment,
  clocks, transports, file systems, or config roots.
- Keep fixtures small and explicit. When comparing Rust parity, mention the Rust
  source behavior in the test name or nearby assertion context.
- When a test spawns a Swift executable, resolve the built product through the
  package's test helpers or an injected path. Avoid fragile relative paths to
  `.build` products.
- If SwiftPM reports sandbox/cache/manifest access errors in this local
  environment, rerun the same command with the required permission rather than
  changing code to accommodate the sandbox.

Common verification commands:

```shell
swift test --filter ResponseModelsTests
swift test --filter ConfigRequirementsTests
swift test --filter CodexAppServerTests
swift test
git diff --check
```

## Documentation

- `Docs/PORTING.md` is the checkpoint ledger for completed and pending parity.
- `Docs/SwiftPort/` contains Swift-rewritten copies of relevant upstream Codex
  docs. Keep them practical for this Swift package, not merely pasted Rust docs.
- When refreshing from `/Users/mweinbach/Projects/codex`, replace Rust-specific
  guidance with the Swift equivalents above: SwiftPM/test commands, Swift
  argument-label and protocol/concurrency rules, and `Codable` wire-shape rules.
