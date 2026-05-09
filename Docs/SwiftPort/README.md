# Codex Swift Port Docs

These docs are rewritten copies of the upstream Codex documentation for the
Swift port in `/Users/mweinbach/Projects/codex-swift`.

The Rust project at `/Users/mweinbach/Projects/codex` remains the behavioral
source of truth. When these docs describe a command or protocol surface, the
Swift implementation should match the Rust behavior unless `Docs/PORTING.md`
records a known gap.

## Quickstart

Build the Swift package:

```shell
swift build
```

Run the Swift CLI:

```shell
swift run codex --help
```

Run the test suite:

```shell
swift test
```

## Porting References

- `docs/` contains user-facing topic docs rewritten for the Swift package.
- `codex-rs/` contains Swift-framed copies of Rust crate docs that are useful
  when matching app-server, protocol, config, and core behavior.
- `../PORTING.md` is the active parity ledger for completed slices and remaining
  gaps.
