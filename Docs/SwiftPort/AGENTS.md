# Swift Port Documentation

The files in this directory are copied from upstream Codex docs only when they
help the Swift port. They must be rewritten into Swift-port guidance before
commit.

## Swift Translation Rules

- Translate Rust workflow commands into SwiftPM commands such as `swift build`,
  `swift test --filter ...`, `swift test`, and `git diff --check`.
- Keep Rust paths, Cargo commands, Clippy checks, or Bazel invocations only when
  the doc is explicitly describing the source behavior contract in
  `/Users/mweinbach/Projects/codex`.
- Translate Rust lint rules into the Swift rule they were protecting. For
  example, Clippy's collapsible-control-flow and format-argument rules become
  readable Swift control flow and interpolation-first string construction, not
  references to Clippy.
- Translate the upstream API-design intent, not just the nouns. A Rust note
  about avoiding ambiguous `bool` or `Option` arguments should become concrete
  Swift guidance about labels, domain enums, option structs, overloads, and
  omitted/null modeling.
- Do not present unported behavior as complete. Point readers to
  `Docs/PORTING.md` for current Swift status.
- Do not add general product or user-facing Codex documentation here. The
  official docs live elsewhere; keep this directory limited to Swift-port
  guidance, copied upstream docs that have been rewritten for the Swift package,
  and app-server API/examples documentation when that API surface changes.

## Call-Site Clarity

- Avoid ambiguous `Bool`, numeric, and optional parameters that force call sites
  such as `foo(false)`, `bar(nil)`, or `load(0)`. Prefer Swift argument labels,
  enums, option structs, named methods, labeled overloads, or small value types
  that make the call site self-documenting.
- Prefer labels and value types that describe intent instead of storage. For
  example, prefer `readRollout(limit: .all)` or
  `setExpanded(false, animated: false)` over positional sentinels.
- Do not add unlabeled parameters unless they are conventional and clear at the
  call site, such as `XCTAssertEqual`, collection transforms, or an API whose
  first argument reads naturally with the base name.
- When an existing positional API cannot be changed and an opaque literal is
  unavoidable, use an exact Swift argument comment immediately before the
  literal: `setExpanded(/* animated: */ false)`,
  `load(/* retryLimit: */ 0)`, or
  `parse(/* allowUnknownVariants: */ true)`.
- The argument comment must match the callee's external argument label. If the
  argument is intentionally unlabeled, match the local parameter name from the
  function declaration. Do not substitute a friendlier alias, because exactness
  lets review catch signature drift.
- Do not add comments for string literals, enum cases, static members, or
  already-labeled arguments unless the comment adds real clarity.
- There is no Rust `argument-comment-lint` equivalent in this Swift port today.
  Treat exact argument comments as a review convention for unavoidable
  positional literals; prefer improving the API shape first.
- Prefer a small enum or options struct over multiple optional parameters when
  nil combinations would be hard to read or would admit impossible states.
- When the value is protocol data rather than an API choice, do not hide
  omitted/null/value semantics behind unlabeled optionals. Decode or inspect the
  raw JSON when needed so `nil` does not erase a distinction Rust preserves.

## Swift Control Flow

- Make `switch` statements over local enums exhaustive. Avoid `default` unless
  the enum intentionally accepts future cases, the enum comes from a framework
  that may add cases, or the decoding logic is explicitly preserving Rust's
  unknown-variant behavior.
- Avoid using `@unknown default` as a blanket escape hatch for first-party enums.
  Add the new case and let the compiler show every affected decision point.
- Model state with a single enum when paired booleans or several optionals would
  allow impossible states.
- Keep helpers small and named for the Rust parity rule they protect when the
  behavior is subtle; otherwise prefer direct readable Swift.
- Prefer Swift string interpolation over `String(format:)` unless fixed locale,
  numeric precision, padding, or protocol-compatible formatting is required.
- Keep APIs `internal` or `private` by default. Export `public` symbols only for
  target boundaries that need them.

## Protocols And Concurrency

- Newly added protocols should include doc comments explaining the protocol's
  role, who implements it, and what invariants callers can rely on.
- Prefer native Swift protocol requirements such as
  `func load(...) async throws -> Value` for asynchronous contracts.
- Treat upstream `async_trait`, `async_fn_in_trait`, and RPITIT guidance as the
  Swift requirement to make async ownership explicit in the protocol shape:
  actor isolation where needed, `async`/`throws` on the requirement,
  `Sendable` return values for cross-domain results, and `@Sendable` closures
  for callbacks that may run concurrently.
- Types and closures that cross task, actor, or callback boundaries should be
  `Sendable` and `@Sendable` where appropriate.
- Avoid broad `@unchecked Sendable`, `nonisolated(unsafe)`, and `@preconcurrency`
  annotations. If interoperability requires one, keep it narrowly scoped and
  document the invariant in code or a test.
- Do not use concurrency escape annotations as the Swift equivalent of Rust's
  discouraged async-trait shortcuts. Put the actor isolation, `async`/`throws`,
  and `Sendable` requirements on the protocol or adapter that owns the
  contract.
- Prefer structured tasks, explicit cancellation, and injected clocks or
  transports over `Task.detached` shortcuts.
- Store long-lived tasks explicitly and make cancellation observable in tests
  when the Rust behavior being ported depends on shutdown or interruption.

## Codable And Protocol Shapes

- Translate serde/ts-rs guidance into Swift `Codable` and app-server wire-shape
  guidance. Preserve Rust field names, tag names, enum values, defaults, and
  unknown-field behavior.
- Swift optionals are not automatically equivalent to Rust `Option`. Use
  `encodeIfPresent` only when Rust omits the field when absent; explicitly
  encode `null` when Rust serializes `None` as `null`.
- When Rust distinguishes omitted, `null`, and value, model that explicitly in
  Swift instead of collapsing it to a plain optional. Use a small tri-state enum
  or raw JSON inspection when request validation needs to know whether the
  client set a field.
- For tagged unions, prefer explicit `init(from:)` and `encode(to:)` paths when
  synthesis cannot preserve Rust's exact shape.
- Prefer whole-object JSON fixture assertions for wire shapes. Field-by-field
  checks are fine only when nondeterministic fields make full equality noisy.
- Preserve Rust's omitted-versus-null distinction in tests. A passing Swift
  decode is not enough when the encoded JSON shape is part of the app-server or
  config contract.

## Test And Build Guidance

- Run the focused SwiftPM test first, then adjacent tests for the touched
  target, then `swift test` before calling the slice complete.
- For wire-shape or call-site guidance changes, useful focused lanes include
  `swift test --filter ResponseModelsTests`,
  `swift test --filter RolloutModelsTests`, and the app-server route test that
  owns the changed protocol shape.
- If a SwiftPM command fails because the local sandbox blocks manifest or cache
  access, rerun the same command with the required permission. Do not change the
  implementation to fit that local sandbox failure.
- Use `git diff --check` before committing documentation or code changes.
- When a test needs a first-party executable, use package test helpers or an
  injected path instead of hard-coding `.build` paths.
