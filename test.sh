#!/bin/bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")" && pwd)"
source "$PROJECT_ROOT/Scripts/environment.sh"
python3 "$PROJECT_ROOT/Scripts/check-version.py"
cargo test --manifest-path "$PROJECT_ROOT/Core/Cargo.toml" --release --locked
xcrun swiftc -swift-version 5 -module-cache-path "$BUILD_ROOT/swift-cache" \
  "$PROJECT_ROOT/Native/Storage.swift" "$PROJECT_ROOT/Tests/ModelTests.swift" \
  -framework Security -o "$BUILD_ROOT/model-tests"
"$BUILD_ROOT/model-tests"
