# Non-Interactive Mode

The Swift executable keeps the Rust `codex exec` command surface and persists
rollout files that later resume/list APIs can inspect.

Run it through SwiftPM while developing:

```shell
swift run codex exec "summarize this repository"
```

For product-level behavior, see https://developers.openai.com/codex/noninteractive.
Current Swift parity and known runtime gaps are tracked in `Docs/PORTING.md`.
