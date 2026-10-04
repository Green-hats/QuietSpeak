#!/bin/bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")" && pwd)"
source "$PROJECT_ROOT/Scripts/environment.sh"
python3 "$PROJECT_ROOT/Scripts/check-version.py"
cargo fmt --manifest-path "$PROJECT_ROOT/Core/Cargo.toml" -- --check
cargo clippy --manifest-path "$PROJECT_ROOT/Core/Cargo.toml" --release --locked --all-targets --no-deps -- -D warnings
xcrun swift-format lint --strict --configuration "$PROJECT_ROOT/.swift-format" \
  --recursive "$PROJECT_ROOT/Native" "$PROJECT_ROOT/Tests" "$PROJECT_ROOT/Scripts/make-icon.swift"
for SCRIPT in "$PROJECT_ROOT"/*.sh "$PROJECT_ROOT"/Scripts/*.sh; do
  bash -n "$SCRIPT"
done
