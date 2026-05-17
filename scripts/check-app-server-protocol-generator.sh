#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

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
        swift build --product codex >&2
        local bin_dir
        bin_dir="$(swift build --show-bin-path)"
        resolve_executable "$bin_dir/codex"
    )
}

RUST_CODEX_BINARY="$(resolve_rust_codex || true)"
if [[ -z "$RUST_CODEX_BINARY" ]]; then
    cat >&2 <<'EOF'
error: app-server protocol generator drift check requires the Rust codex binary.

Set CODEX_RUST_BINARY to a Rust-built codex executable, or keep a sibling Rust
checkout built at ../codex/codex-rs/target/debug/codex.
EOF
    exit 1
fi

SWIFT_CODEX_BINARY="$(resolve_swift_codex)"

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/codex-app-server-protocol-generator.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

canonicalize_json_tree() {
    local source_dir="$1"
    local output_dir="$2"

    python3 - "$source_dir" "$output_dir" <<'PY'
import json
import os
import sys
from pathlib import Path


source_dir = Path(sys.argv[1])
output_dir = Path(sys.argv[2])


def schema_array_item_sort_key(item):
    if item is None:
        return "null"
    if isinstance(item, bool):
        return f"b:{item}"
    if isinstance(item, (int, float)):
        return f"n:{item}"
    if isinstance(item, str):
        return f"s:{item}"
    if isinstance(item, dict):
        reference = item.get("$ref")
        if isinstance(reference, str):
            return f"ref:{reference}"
        title = item.get("title")
        if isinstance(title, str):
            return f"title:{title}"
    return None


def canonicalize_json(value):
    if isinstance(value, list):
        items = [canonicalize_json(item) for item in value]
        sortable = []
        for item in items:
            key = schema_array_item_sort_key(item)
            if key is None:
                return items
            stable = json.dumps(item, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
            sortable.append((key, stable, item))
        return [item for _, _, item in sorted(sortable, key=lambda entry: (entry[0], entry[1]))]
    if isinstance(value, dict):
        return {key: canonicalize_json(value[key]) for key in sorted(value)}
    return value


for root, _, files in os.walk(source_dir):
    for filename in files:
        source_path = Path(root) / filename
        relative_path = source_path.relative_to(source_dir)
        output_path = output_dir / relative_path
        output_path.parent.mkdir(parents=True, exist_ok=True)
        if source_path.suffix == ".json":
            value = json.loads(source_path.read_text(encoding="utf-8"))
            output_path.write_text(
                json.dumps(canonicalize_json(value), indent=2, ensure_ascii=False) + "\n",
                encoding="utf-8",
            )
        else:
            output_path.write_bytes(source_path.read_bytes())
PY
}

run_pair() {
    local compare_mode="$1"
    shift
    local name="$1"
    shift

    local rust_out="$WORK_DIR/rust/$name"
    local swift_out="$WORK_DIR/swift/$name"
    mkdir -p "$rust_out" "$swift_out"

    echo "checking app-server $* ($name)" >&2
    env -u CODEX_RUST_BINARY "$RUST_CODEX_BINARY" app-server "$@" --out "$rust_out"
    CODEX_RUST_BINARY="$RUST_CODEX_BINARY" "$SWIFT_CODEX_BINARY" app-server "$@" --out "$swift_out"

    local left="$rust_out"
    local right="$swift_out"
    if [[ "$compare_mode" == "json" ]]; then
        left="$WORK_DIR/canonical-rust/$name"
        right="$WORK_DIR/canonical-swift/$name"
        canonicalize_json_tree "$rust_out" "$left"
        canonicalize_json_tree "$swift_out" "$right"
    fi

    if ! diff -ru "$left" "$right"; then
        echo "error: Swift app-server generator wrapper drifted for $name" >&2
        return 1
    fi
}

run_pair "raw" "typescript" generate-ts
run_pair "raw" "typescript-experimental" generate-ts --experimental
run_pair "json" "json-schema" generate-json-schema
run_pair "json" "json-schema-experimental" generate-json-schema --experimental
run_pair "json" "internal-json-schema" generate-internal-json-schema

echo "app-server protocol generator outputs match the Rust oracle" >&2
