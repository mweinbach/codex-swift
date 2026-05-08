# Codex Swift Port

Objective: port `/Users/mweinbach/Projects/codex` from Rust to native Swift with 1:1 behavior.

Source baseline inspected for this scaffold:

- Repository: `/Users/mweinbach/Projects/codex`
- HEAD: `b00146a47f0fc7eb8353664c0bf4942763e22c91`
- Rust workspace: `codex-rs`
- Rust workspace member count: 53 Cargo manifests
- Rust source size: 789 tracked `.rs` files

## Current Swift Package Shape

- `CodexCore`: pure core/protocol utilities that can be tested without network, terminal, or model runtime.
- `CodexCLI`: top-level command metadata and CLI surface.
- `codex`: executable target.

## Ported In This Initial Slice

- `codex-rs/utils/string/src/lib.rs`
  - `take_bytes_at_char_boundary`
  - `take_last_bytes_at_char_boundary`
- `codex-rs/protocol/src/num_format.rs`
  - `format_with_separators`
  - `format_si_suffix`
- `codex-rs/utils/absolute-path/src/lib.rs`
  - absolute path normalization and relative path resolution
  - Codable base-path decode support through `JSONDecoder.userInfo`
- `codex-rs/tui/src/slash_command.rs`
  - slash command names, presentation order, descriptions, and task availability
- `codex-rs/cli/src/main.rs`
  - top-level command registry, visible aliases, hidden command marking, version
- `codex-rs/common/src/approval_mode_cli_arg.rs`
  - approval CLI argument names and protocol mapping
- `codex-rs/common/src/sandbox_mode_cli_arg.rs`
  - sandbox CLI argument names and protocol mapping
- `codex-rs/common/src/config_override.rs`
  - `-c key=value` parsing, TOML-like literal fallback, and dotted-path application
- `codex-rs/core/src/features.rs`
  - known feature keys used by `--enable` and `--disable`

## Known Gaps

The executable is not functionally equivalent yet. It currently exposes the command surface and returns a clear unimplemented status for registered commands. The remaining major areas include:

- interactive TUI runtime
- non-interactive `exec`
- model provider configuration and auth
- Responses API streaming and tool orchestration
- sandbox execution
- MCP server/client management
- app-server protocol and server runtime
- apply-patch runtime
- cloud tasks
- completion generation
- platform-specific process hardening

Every future slice should add parity tests that point back to the Rust file or behavior being ported.
