# Config Layer Loader

The Swift config-layer loader mirrors Rust's loader behavior for user config,
project config, managed requirements, CLI/session overrides, per-layer metadata,
and app-server `config/read` projections where ported.

## Swift Surface

- `Sources/CodexCore/ConfigLayerLoader.swift`
- `Sources/CodexCore/Config.swift`
- `Sources/CodexCore/ConfigRequirements.swift`
- `Tests/CodexCoreTests/ConfigLayerLoaderTests.swift`
- `Tests/CodexCoreTests/ConfigLoaderTests.swift`
- `Tests/CodexCoreTests/ConfigRequirementsTests.swift`

## Behavior Contract

Precedence remains top-over-bottom, matching Rust:

1. managed/system requirements and managed hooks
2. session or CLI overrides
3. project and cwd-specific config layers
4. user `config.toml`

Disabled layers should remain visible to UI/API metadata but must not contribute
to effective config values. Origins, versions, and merge behavior should stay
compatible with Rust because app-server config writes depend on those details.

## Verification

```shell
swift test --filter ConfigLayerLoaderTests
swift test --filter ConfigLoaderTests
swift test --filter ConfigRequirementsTests
```
