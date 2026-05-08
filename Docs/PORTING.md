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
- `codex-rs/protocol/src/conversation_id.rs`
  - string-backed Codable conversation IDs with UUIDv7 generation
- `codex-rs/protocol/src/config_types.rs`
  - reasoning summary, verbosity, forced login method, trust level, and sandbox mode wire values
- `codex-rs/protocol/src/protocol.rs`
  - ask-for-approval wire values and sandbox policy tagged Codable shape/access helpers
- `codex-rs/common/src/approval_presets.rs`
  - built-in approval preset ordering and policy pairs
- `codex-rs/protocol/src/approvals.rs`
  - transparent execpolicy amendment array encoding
- `codex-rs/protocol/src/user_input.rs`
  - tagged user input variants for text, images, local images, and skills
- `codex-rs/protocol/src/plan_tool.rs`
  - update-plan argument wire shapes
- `codex-rs/protocol/src/custom_prompts.rs`
  - custom prompt metadata and `prompts` command prefix
- `codex-rs/protocol/src/models.rs`
  - sandbox permission values, response input items, content items, function-call output payloads, shell tool call params, web-search actions, and compaction alias decoding
- `codex-rs/protocol/src/parse_command.rs`
  - tagged parsed-command model
- `codex-rs/core/src/parse_command.rs`
  - first command parser parity slice for shell extraction, simple shell tokenization, small pipeline formatter dropping, `cd` context, `rg`, `grep`, `ls`, `cat`, `head`, `tail`, `nl`, and `sed -n`
- `codex-rs/common/src/fuzzy_match.rs`
  - Unicode-aware case-insensitive subsequence matching, original-character highlight indices, scoring, and empty-needle behavior
- `codex-rs/apply-patch`
  - initial native `CodexApplyPatch` target and `apply_patch` executable
  - parser support for add/delete/update/move hunks, lenient heredoc patch arguments, missing context errors, multiple chunks, parent directory creation, and summary output

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
- local image loading/resizing into data URLs
- MCP `CallToolResult` conversion into function-call output payloads
- full Rust command parser parity for complex Bash/Powershell AST cases
- apply-patch invocation detection from arbitrary shell commands/heredocs
- apply-patch unified diff preview helpers

Every future slice should add parity tests that point back to the Rust file or behavior being ported.
