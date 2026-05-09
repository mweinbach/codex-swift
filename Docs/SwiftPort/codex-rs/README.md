# Codex Swift Package

This directory contains Swift-port notes rewritten from the Rust `codex-rs`
workspace docs. The Rust workspace remains the behavior source of truth; the
Swift package is expected to match it one slice at a time.

## Build And Run

```shell
swift build
swift run codex --help
swift run codex exec "explain this codebase"
```

## Important Runtime Surfaces

- `CodexCore` owns shared protocol models, config parsing, rollout persistence,
  sandbox/permission helpers, hook helpers, and non-interactive execution logic.
- `CodexCLI` owns command-surface parsing and command dispatch.
- `CodexAppServer` owns the newline-delimited JSON-RPC app-server runtime.
- `CodexMCPServer` owns the MCP server entrypoint.
- `CodexApplyPatch` owns the Swift patch parser and applier.
- `CodexGit` owns Swift git helpers used by cloud apply paths.

## Rust Behavior Contract

The Swift port preserves Rust CLI and app-server behavior where implemented:

- `config.toml` keys and config-layer behavior
- `codex exec` non-interactive rollout persistence
- MCP client/server config and tool shapes
- sandbox policy, permission profile, and filesystem permission semantics
- app-server v2 JSON-RPC method names, request/response shapes, notifications,
  pagination, and experimental API gating
- protocol models for Responses API items, events, turns, and rollout records

See `../PORTING.md` for exact completion status before assuming a command or
runtime path is fully ported.
