#!/bin/bash
# Shared by build, test and quality checks. Source this file after PROJECT_ROOT.
if [ "$(uname -s)" != Darwin ]; then
  echo "QuietSpeak must be built on macOS." >&2
  exit 1
fi
for TOOL in cargo xcrun cmake python3; do
  if ! command -v "$TOOL" >/dev/null 2>&1; then
    echo "Missing build tool: $TOOL. See README.md." >&2
    exit 1
  fi
done
BUILD_ROOT="${QUIETSPEAK_BUILD_DIR:-$PROJECT_ROOT/work/build}"
MAC_ARCH="$(uname -m)"
case "$MAC_ARCH" in
  arm64|x86_64) ;;
  *) echo "Unsupported architecture: $MAC_ARCH" >&2; exit 1 ;;
esac
export MACOSX_DEPLOYMENT_TARGET=14.0
export OPUS_STATIC=1
export OPUS_NO_PKG=1
export CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-$BUILD_ROOT/rust}"
mkdir -p "$BUILD_ROOT"
