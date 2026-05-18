#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
WORK_DIR="${CODEX_RUNTIME_ORACLE_WORK_DIR:-}"
if [[ -z "$WORK_DIR" ]]; then
    WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/codex-runtime-oracle.XXXXXX")"
    trap 'rm -rf "$WORK_DIR"' EXIT
else
    mkdir -p "$WORK_DIR"
fi
SWIFTPM_SCRATCH_PATH="${CODEX_RUNTIME_ORACLE_SWIFTPM_SCRATCH:-$WORK_DIR/swiftpm}"

resolve_executable() {
    local candidate="$1"
    if [[ "$candidate" == */* ]]; then
        if [[ ! -x "$candidate" ]]; then
            return 1
        fi
        local candidate_dir
        candidate_dir="$(cd "$(dirname "$candidate")" && pwd -P)"
        printf '%s/%s\n' "$candidate_dir" "$(basename "$candidate")"
        return 0
    fi
    command -v "$candidate"
}

resolve_rust_codex() {
    if [[ -n "${CODEX_RUST_BINARY:-}" ]]; then
        resolve_executable "$CODEX_RUST_BINARY"
        return
    fi

    local candidate
    for candidate in \
        "$ROOT_DIR/../codex-rs/target/debug/codex" \
        "$ROOT_DIR/../codex/codex-rs/target/debug/codex"
    do
        if [[ -x "$candidate" ]]; then
            resolve_executable "$candidate"
            return
        fi
    done

    if command -v codex-rs >/dev/null 2>&1; then
        command -v codex-rs
        return
    fi

    return 1
}

resolve_swift_codex() {
    if [[ -n "${SWIFT_CODEX_BINARY:-}" ]]; then
        resolve_executable "$SWIFT_CODEX_BINARY"
        return
    fi

    (
        cd "$ROOT_DIR"
        swift build --scratch-path "$SWIFTPM_SCRATCH_PATH" --product codex >&2
        local bin_dir
        bin_dir="$(swift build --scratch-path "$SWIFTPM_SCRATCH_PATH" --show-bin-path)"
        resolve_executable "$bin_dir/codex"
    )
}

RUST_CODEX_BINARY="$(resolve_rust_codex || true)"
if [[ -z "$RUST_CODEX_BINARY" ]]; then
    cat >&2 <<'EOF'
error: runtime oracle parity tests require the Rust codex binary.

Set CODEX_RUST_BINARY to a Rust-built codex executable, or keep a sibling Rust
checkout built at ../codex/codex-rs/target/debug/codex.
EOF
    exit 1
fi

SWIFT_CODEX_BINARY="$(resolve_swift_codex)"

cd "$ROOT_DIR"

CODEX_RUN_RUST_ORACLE_TESTS=1 \
CODEX_RUST_BINARY="$RUST_CODEX_BINARY" \
SWIFT_CODEX_BINARY="$SWIFT_CODEX_BINARY" \
swift test --scratch-path "$SWIFTPM_SCRATCH_PATH" --filter RuntimeOracleParityTests
