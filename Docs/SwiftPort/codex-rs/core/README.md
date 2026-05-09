# CodexCore

`CodexCore` is the Swift port of the Rust `codex-core` behavior surface. It is
shared by the Swift CLI, app-server, MCP server, ChatGPT auth, and helper
executables.

## Responsibilities

- Protocol models and JSON wire-shape compatibility
- Config parsing, profile merging, feature toggles, and requirements
- Rollout read/write models and persistence classification
- Non-interactive exec and Responses API request building
- Sandbox policies, permission profiles, filesystem permissions, and command
  safety helpers
- Hook discovery, hook event parsing, and non-interactive hook execution helpers
- MCP config, OAuth metadata, and tool/resource payload models
- Apply-patch integration helpers and user shell command formatting

## Platform Notes

- macOS sandbox parity uses Seatbelt-oriented policy modeling where implemented.
- Linux and Windows sandbox helper behavior is still incomplete in the Swift
  runtime; keep Rust docs as the source contract and track gaps in
  `Docs/PORTING.md`.
- `apply_patch` behavior is exposed through the Swift `apply_patch` executable
  and the non-interactive shell interception path.

## Verification

Use focused `CodexCoreTests` filters for the behavior being ported, then run the
full package suite:

```shell
swift test --filter ConfigRequirementsTests
swift test --filter ResponseModelsTests
swift test
```
