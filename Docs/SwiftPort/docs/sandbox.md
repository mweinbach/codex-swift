# Sandbox

The Swift port preserves the Rust sandbox policy model, permission profiles,
filesystem permissions, network policy, and app-server wire shapes as they are
ported.

Run the Swift CLI sandbox surface through SwiftPM:

```shell
swift run codex sandbox macos --help
```

For product-level sandbox behavior, see
https://developers.openai.com/codex/sandbox. Swift runtime gaps for Landlock,
Windows helpers, and full sandbox execution are tracked in `Docs/PORTING.md`.
