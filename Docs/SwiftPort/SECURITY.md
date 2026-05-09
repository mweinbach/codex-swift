# Security

The Swift port should preserve Rust Codex security behavior for auth handling,
sandboxing, approval gates, config loading, app-server transports, and persisted
session data.

Report security issues through the upstream OpenAI security process:
https://openai.com/security/disclosure/

When porting security-sensitive code, compare against `/Users/mweinbach/Projects/codex`,
add focused tests, and record completed or incomplete parity in `Docs/PORTING.md`.
