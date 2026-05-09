# Exec Policy

The Swift port implements Codex exec-policy parsing and checks with
Rust-compatible rule shapes, prefix matching, host executable mapping, and
diagnostics where ported.

Run the Swift command from the package:

```shell
swift run codex execpolicy check --rules path/to/rules.rules -- command args
```

For canonical user behavior, see https://developers.openai.com/codex/execpolicy.
Use `Docs/PORTING.md` to confirm which Starlark and policy features are fully
ported.
