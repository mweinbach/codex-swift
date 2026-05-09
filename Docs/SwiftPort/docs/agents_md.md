# AGENTS.md

`AGENTS.md` files provide scoped instructions to coding agents. The Swift port
follows the same scoping rules as Rust: an `AGENTS.md` applies to the directory
that contains it and all children unless a deeper file overrides it.

This repository's root `AGENTS.md` is rewritten for SwiftPM and 1:1 porting
work. For product-level behavior, see
https://developers.openai.com/codex/agents-md.
