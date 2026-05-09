# Protocol Models

Swift protocol types live primarily in `Sources/CodexCore`. They mirror Rust
internal protocol, app-server protocol, Responses API items, rollout events, and
MCP payload models.

When changing a protocol type, compare the Swift encoder/decoder behavior
against the Rust implementation and add tests for exact field names, optional
null handling, tagged-union shapes, defaults, and compatibility aliases.
