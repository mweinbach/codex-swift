# Codex Swift

This repository is a native SwiftPM port of the Rust Codex project at
`/Users/mweinbach/Projects/codex`. The goal is a 1:1 implementation: Rust
behavior, protocol shapes, config semantics, persistence formats, and error
messages are the contract unless `Docs/PORTING.md` records an explicit gap.

## Platform Support

The Swift port is macOS-only for now. The supported product target is macOS 14
or newer, matching `Package.swift` and the current dependencies on Apple
frameworks such as CryptoKit and Security plus Darwin-specific runtime code.

Some leaf targets may build on other platforms, but that is not a product
guarantee. Linux and Windows support requires deliberate platform abstractions
for process/PTY handling, credential storage, sandboxing, filesystem
permissions, and digest/security primitives before it should be treated as Rust
platform parity.

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

## App-Server Protocol Generator

The Swift executable deliberately treats the Rust `codex` binary as the
app-server protocol generator oracle for now. Keep a built Rust checkout at
`../codex/codex-rs/target/debug/codex`, or set `CODEX_RUST_BINARY` to a
Rust-built `codex` executable before running generator commands.

Run the oracle check locally as:

```shell
scripts/check-app-server-protocol-generator.sh
```

That script regenerates the stable and experimental TypeScript/JSON schema
surfaces through both the Swift wrapper and the Rust binary, then fails if the
output trees diverge. A Swift-native generator can replace this bridge later,
but freezing generated protocol artifacts without this check is intentionally
avoided.

## Docs

- `Docs/PORTING.md` tracks completed parity slices and known gaps.
- `Docs/SwiftPort/` contains Swift-rewritten Codex docs copied from the Rust
  project for porting reference.
- `/Users/mweinbach/Projects/codex` remains the source-of-truth Rust
  implementation for behavior comparisons.
