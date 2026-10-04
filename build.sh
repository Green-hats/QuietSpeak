#!/bin/bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")" && pwd)"
source "$PROJECT_ROOT/Scripts/environment.sh"
APP_PATH="${QUIETSPEAK_APP_PATH:-$PROJECT_ROOT/dist/QuietSpeak.app}"
python3 "$PROJECT_ROOT/Scripts/check-version.py"
mkdir -p "$BUILD_ROOT" "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
cargo build --manifest-path "$PROJECT_ROOT/Core/Cargo.toml" --release --locked
python3 "$PROJECT_ROOT/Scripts/generate-notices.py"
xcrun swiftc -parse-as-library -swift-version 5 -O -module-cache-path "$BUILD_ROOT/swift-cache" \
  -target "$MAC_ARCH-apple-macosx14.0" "$PROJECT_ROOT"/Native/*.swift \
  "$CARGO_TARGET_DIR/release/libquietspeak_core.a" \
  -framework SwiftUI -framework AppKit -framework AVFoundation -framework Security \
  -framework CoreAudio -framework AudioToolbox -framework CoreFoundation -framework SystemConfiguration \
  -lresolv -o "$APP_PATH/Contents/MacOS/QuietSpeak"
cp "$PROJECT_ROOT/Resources/Info.plist" "$APP_PATH/Contents/Info.plist"
xcrun swift -module-cache-path "$BUILD_ROOT/swift-cache" "$PROJECT_ROOT/Scripts/make-icon.swift" "$BUILD_ROOT/icon.png"
mkdir -p "$BUILD_ROOT/AppIcon.iconset"
for SIZE in 16 32 128 256 512; do
  sips -z "$SIZE" "$SIZE" "$BUILD_ROOT/icon.png" --out "$BUILD_ROOT/AppIcon.iconset/icon_${SIZE}x${SIZE}.png" >/dev/null
  DOUBLE=$((SIZE*2))
  sips -z "$DOUBLE" "$DOUBLE" "$BUILD_ROOT/icon.png" --out "$BUILD_ROOT/AppIcon.iconset/icon_${SIZE}x${SIZE}@2x.png" >/dev/null
done
python3 "$PROJECT_ROOT/Scripts/package-icon.py" "$BUILD_ROOT/AppIcon.iconset" "$APP_PATH/Contents/Resources/AppIcon.icns"
cp "$PROJECT_ROOT/THIRD_PARTY_NOTICES.txt" "$APP_PATH/Contents/Resources/THIRD_PARTY_NOTICES.txt"
cp "$PROJECT_ROOT/LICENSE" "$APP_PATH/Contents/Resources/LICENSE"
codesign --force --sign - --identifier app.quietspeak.personal --entitlements "$PROJECT_ROOT/Resources/entitlements.plist" "$APP_PATH"
python3 "$PROJECT_ROOT/Scripts/verify-app.py" "$APP_PATH" --arch "$MAC_ARCH"
echo "Built: $APP_PATH"
