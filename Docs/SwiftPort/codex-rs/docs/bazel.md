# Bazel

The Swift port does not use Bazel. Build and test with SwiftPM:

```shell
swift build
swift test
```

Bazel notes from the Rust project remain relevant only when inspecting
`/Users/mweinbach/Projects/codex` or comparing Rust CI behavior. Do not add
Bazel metadata to `codex-swift` unless the project intentionally adopts it.
