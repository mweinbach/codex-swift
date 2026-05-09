# Configuration

The Swift port reads and writes Codex `config.toml` with Rust-compatible keys
and wire behavior. The implementation should match the upstream docs for user
semantics while using Swift code paths internally.

For the canonical product behavior, see:

- Basic configuration: https://developers.openai.com/codex/config-basic
- Advanced configuration: https://developers.openai.com/codex/config-advanced
- Full reference: https://developers.openai.com/codex/config-reference

Swift parity status is tracked in `Docs/PORTING.md`, especially the config,
requirements, MCP, hooks, permissions, and app-server sections.
