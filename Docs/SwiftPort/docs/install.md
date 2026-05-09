# Installing And Building

## System Requirements

| Requirement | Details |
| --- | --- |
| Operating system | macOS 14+ for the current SwiftPM package |
| Swift toolchain | Swift 6.2 or newer |
| Xcode | Xcode or Xcode beta with the matching macOS SDK |
| Git | Recommended for tests and Codex git features |

## Build From Source

```shell
git clone https://github.com/mweinbach/codex-swift.git
cd codex-swift
swift build
```

Run the CLI from SwiftPM:

```shell
swift run codex --help
```

Run the app-server:

```shell
swift run codex app-server --listen stdio://
```

Run the Responses API proxy:

```shell
swift run codex-responses-api-proxy --help
```

## Testing

Run focused tests for the area you changed, then run the full suite:

```shell
swift test --filter CodexAppServerTests
swift test
git diff --check
```

The Swift port intentionally keeps many Rust-facing command names, config keys,
wire fields, and error strings. When a behavior is unclear, compare against
`/Users/mweinbach/Projects/codex` and record the result in `Docs/PORTING.md`.
