# Codex Swift

This repository is a native SwiftPM port of the Rust Codex project at
`/Users/mweinbach/Projects/codex`. The goal is a 1:1 implementation: Rust
behavior, protocol shapes, config semantics, persistence formats, and error
messages are the contract unless `Docs/PORTING.md` records an explicit gap.

## Build

```shell
swift build
```

Run the main executable:

```shell
swift run codex --help
```

Run the patch helper:

```shell
swift run apply_patch --help
```

## Test

Start focused, then broaden:

```shell
swift test --filter CodexCLITests
swift test
git diff --check
```

## Docs

- `Docs/PORTING.md` tracks completed parity slices and known gaps.
- `Docs/SwiftPort/` contains Swift-rewritten Codex docs copied from the Rust
  project for porting reference.
- `/Users/mweinbach/Projects/codex` remains the source-of-truth Rust
  implementation for behavior comparisons.
