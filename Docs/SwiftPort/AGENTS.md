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
- Do not present unported behavior as complete. Point readers to
  `Docs/PORTING.md` for current Swift status.

## Call-Site Clarity

- Avoid ambiguous `Bool`, numeric, and optional parameters that force call sites
  such as `foo(false)` or `bar(nil)`. Prefer Swift argument labels, enums,
  option structs, named methods, or small value types that make the call site
  self-documenting.
- Do not add unlabeled parameters unless they are conventional and clear at the
  call site. When an existing positional API cannot be changed and an opaque
  literal is unavoidable, use an exact argument comment such as
  `setExpanded(/* animated: */ false)` or `load(/* retryLimit: */ 0)`.
- The argument comment should match the callee's semantic parameter name. Do not
  add comments for obvious string literals or already-labeled arguments.
- There is no Rust `argument-comment-lint` equivalent in this Swift port today.
  Prefer improving the API shape, then rely on review and focused tests for the
  remaining unavoidable positional literals.

## Swift Control Flow

- Make `switch` statements over local enums exhaustive. Avoid `default` unless
  the enum intentionally accepts future cases or the decoding logic is explicitly
  preserving Rust's unknown-variant behavior.
- Model state with a single enum when paired booleans or several optionals would
  allow impossible states.
- Keep helpers small and named for the Rust parity rule they protect when the
  behavior is subtle; otherwise prefer direct readable Swift.

## Protocols And Concurrency

- Newly added protocols should include doc comments explaining the protocol's
  role, who implements it, and what invariants callers can rely on.
- Prefer native Swift protocol requirements such as
  `func load(...) async throws -> Value` for asynchronous contracts.
- Types and closures that cross task, actor, or callback boundaries should be
  `Sendable` and `@Sendable` where appropriate.
- Avoid broad `@unchecked Sendable`, `nonisolated(unsafe)`, and `@preconcurrency`
  annotations. If interoperability requires one, keep it narrowly scoped and
  document the invariant in code or a test.
- Prefer structured tasks, explicit cancellation, and injected clocks or
  transports over `Task.detached` shortcuts.

## Codable And Protocol Shapes

- Translate serde/ts-rs guidance into Swift `Codable` and app-server wire-shape
  guidance. Preserve Rust field names, tag names, enum values, defaults, and
  unknown-field behavior.
- Swift optionals are not automatically equivalent to Rust `Option`. Use
  `encodeIfPresent` only when Rust omits the field when absent; explicitly
  encode `null` when Rust serializes `None` as `null`.
- For tagged unions, prefer explicit `init(from:)` and `encode(to:)` paths when
  synthesis cannot preserve Rust's exact shape.
- Prefer whole-object JSON fixture assertions for wire shapes. Field-by-field
  checks are fine only when nondeterministic fields make full equality noisy.
