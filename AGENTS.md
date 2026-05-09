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
  read like `foo(false)` or `bar(nil)`. Prefer enums, option structs, named
  methods, or other Swift API shapes that make the call site self-documenting.
- Avoid unlabeled parameters except for conventional first arguments where the
  call site remains clear. If an existing unlabeled API forces an opaque literal,
  use a short argument comment such as `foo(/* animated: */ false)`.
- Keep argument comments exact and useful. Match the callee's semantic parameter
  name and do not add comments for obvious string literals or values that are
  already clear from labels.
- Prefer exhaustive `switch` statements for enums. Avoid `default` unless the
  enum is intentionally open-ended or forward-compatible decoding requires it.
- Newly added protocols should include doc comments explaining the protocol's
  role, who implements it, and what invariants callers may rely on.
- Avoid boolean state pairs when a single enum models the state more accurately.
- Avoid small helper methods that are referenced only once unless they isolate a
  non-obvious parity rule or improve testability.

## Swift Concurrency

- Prefer native Swift `async` protocol requirements, for example
  `func load(...) async throws -> Value`.
- Add `Sendable` conformance to value types that cross task, actor, or callback
  boundaries.
- Mark escaping concurrent closures as `@Sendable` when they can run across
  concurrency domains.
- Avoid `@unchecked Sendable`, `nonisolated(unsafe)`, and `@preconcurrency`
  unless there is a specific interoperability reason. If one is necessary, keep
  the scope small and document the invariant in code or tests.
- Do not use detached tasks as a shortcut around ownership or lifetime problems.
  Prefer structured tasks, explicit cancellation paths, and injected clocks or
  transports in tests.

## Codable And Wire Shapes

- Keep app-server and protocol payload fields camelCase unless the Rust API or
  config TOML compatibility requires snake_case.
- Preserve Rust optional behavior exactly: distinguish omitted fields from
  explicit `null` where Rust does.
- For tagged unions, keep the Rust tag names, variant names, defaults, and
  unknown-variant behavior.
- Prefer whole-object encode/decode assertions over field-by-field checks when
  testing wire shapes.
- When adding app-server v2 request/response/notification models, keep method
  names in `<resource>/<method>` form and use singular resource names.
- Config RPC payloads may use snake_case when mirroring `config.toml` keys.

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

## Tests

- Start with the focused test filter for the changed area, then broaden to
  adjacent tests, then run the full suite.
- Prefer equality over whole objects where practical. Use targeted field checks
  only when the object contains nondeterministic data.
- Avoid mutating process-global state in tests. Prefer injecting environment,
  clocks, transports, file systems, or config roots.
- Keep fixtures small and explicit. When comparing Rust parity, mention the Rust
  source behavior in the test name or nearby assertion context.
- If SwiftPM reports sandbox/cache/manifest access errors in this local
  environment, rerun the same command with the required permission rather than
  changing code to accommodate the sandbox.

Common verification commands:

```shell
swift test --filter ConfigRequirementsTests
swift test --filter CodexAppServerTests
swift test
git diff --check
```

## Documentation

- `Docs/PORTING.md` is the checkpoint ledger for completed and pending parity.
- `Docs/SwiftPort/` contains Swift-rewritten copies of relevant upstream Codex
  docs. Keep them practical for this Swift package, not merely pasted Rust docs.
- When refreshing from `/Users/mweinbach/Projects/codex`, translate Rust-specific
  guidance into Swift equivalents. For example, translate Cargo/Clippy/Bazel
  instructions into SwiftPM/test guidance, Rust trait guidance into Swift
  protocol/concurrency guidance, and serde/ts-rs rules into Swift `Codable`
  wire-shape rules.
