# Configuration

Swift configuration docs live in `Docs/SwiftPort/docs/config.md`. The Swift
implementation should preserve the Rust `config.toml` model, including MCP
server configuration, profiles, sandbox settings, feature toggles, hooks,
plugins, skills, and requirements where ported.

Use `Docs/PORTING.md` to verify current completion before relying on a config
field in the Swift runtime.
