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
- Avoid ambiguous literal call sites. Prefer argument labels, enums, option
  structs, and named methods; use exact argument comments only when an existing
  unlabeled API forces an opaque literal.
- Prefer exhaustive `switch` statements over `default` for closed enums.
- Document newly added protocols with their role, expected implementers, and
  concurrency expectations.
- Use native Swift `async` protocol requirements plus `Sendable` and `@Sendable`
  where values or closures cross concurrency boundaries.
- Prefer whole-object assertions in protocol/config tests.
- Avoid broad refactors while porting a behavior slice.
- Do not mark a slice complete until the Swift tests cover the Rust behavior
  being claimed.

## Useful Commands

```shell
swift test --filter ConfigRequirementsTests
swift test --filter CodexAppServerTests
swift test
git diff --check
```

## Source References

- Swift port: `/Users/mweinbach/Projects/codex-swift`
- Rust source of truth: `/Users/mweinbach/Projects/codex`
- Porting ledger: `Docs/PORTING.md`
