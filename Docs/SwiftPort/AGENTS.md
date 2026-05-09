# Swift Port Documentation

The files in this directory are copied from upstream Codex docs only when they
help the Swift port. They must be rewritten into Swift-port guidance before
commit.

- Translate Rust workflow commands into SwiftPM commands such as `swift build`,
  `swift test --filter ...`, and `swift test`.
- Translate Rust API advice into Swift equivalents. For example, Clippy
  call-site clarity rules become Swift argument-label, enum, option-struct, and
  exact argument-comment rules.
- Translate Rust trait guidance into Swift protocol guidance, including
  `async` requirements, `Sendable`, `@Sendable`, and avoiding broad
  `@unchecked Sendable`.
- Translate serde/ts-rs guidance into Swift `Codable` and app-server wire-shape
  guidance.
- Keep Rust paths or Cargo/Bazel commands only when the doc is explicitly
  describing the source behavior contract in `/Users/mweinbach/Projects/codex`.
- Do not present unported behavior as complete. Point readers to
  `Docs/PORTING.md` for current Swift status.
