# Contributing To The Swift Port

This repository is focused on a 1:1 Swift port of the Rust Codex project. The
best contribution is a small, verified parity slice that moves one Rust behavior
into Swift without changing unrelated surfaces.

## Development Workflow

1. Identify the Rust source file, route, or test that defines the behavior.
2. Add or update Swift tests that make the expected behavior explicit.
3. Implement the smallest Swift change that matches Rust.
4. Run the focused test filter, then the adjacent tests if a boundary changed.
5. Run `swift test` and `git diff --check` before committing.
6. Update `Docs/PORTING.md` with the completed behavior and any remaining gap.

## Porting Guidelines

- Preserve Rust wire shapes, field names, default values, ordering, and error
  strings.
- Keep public Swift APIs close to the existing target ownership boundaries.
- Avoid ambiguous literal call sites such as `foo(false)`, `bar(nil)`, or
  `load(0)`. Prefer argument labels, enums, option structs, labeled overloads,
  and named methods.
- Use exact Swift argument comments only when an existing positional API cannot
  be changed. The comment should match the callee's external label, or the local
  parameter name for intentionally unlabeled parameters:
  `setExpanded(/* animated: */ false)`.
- Prefer Swift interpolation over `String(format:)` unless the exact formatting
  behavior is part of the Rust-compatible output.
- Prefer exhaustive `switch` statements over `default` for closed enums. Do not
  use `@unknown default` for first-party enums just to avoid updating callers.
- Document newly added protocols with their role, expected implementers, and
  concurrency expectations.
- Use native Swift `async` protocol requirements plus `Sendable` and `@Sendable`
  where values or closures cross concurrency boundaries.
- Avoid broad `@unchecked Sendable`, `nonisolated(unsafe)`, and `@preconcurrency`
  annotations. If one is required for interoperability, keep it scoped and
  document the invariant.
- Prefer whole-object assertions in protocol/config tests, especially when JSON
  omitted-versus-null behavior matters.
- Model Rust omitted/null/value distinctions explicitly. A plain Swift optional
  is only correct when Rust also treats absence and `None` the same way on that
  wire surface.
- Keep implementation details `internal` or `private` unless another SwiftPM
  target needs them.
- Avoid broad refactors while porting a behavior slice.
- Do not mark a slice complete until the Swift tests cover the Rust behavior
  being claimed.

## Useful Commands

```shell
swift test --filter ResponseModelsTests
swift test --filter ConfigRequirementsTests
swift test --filter CodexAppServerTests
swift test
git diff --check
```

## Source References

- Swift port: `/Users/mweinbach/Projects/codex-swift`
- Rust source of truth: `/Users/mweinbach/Projects/codex`
- Porting ledger: `Docs/PORTING.md`
