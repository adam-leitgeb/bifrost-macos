#!/bin/bash
# Builds Bifrost.app from the Swift package.
#
#   ./Scripts/build-app.sh            # release build into ./build
#   ./Scripts/build-app.sh debug      # debug build

set -euo pipefail

CONFIG="${1:-release}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/build/Bifrost.app"

cd "$ROOT"

# Build with Xcode's toolchain, not whatever `swift` happens to be on PATH.
# A swiftly/standalone toolchain older than the installed SDK compiles the
# system SwiftUI module pathologically slowly (minutes instead of seconds).
export TOOLCHAINS="${TOOLCHAINS:-com.apple.dt.toolchain.XcodeDefault}"
SWIFT=(xcrun --toolchain "$TOOLCHAINS" swift)

"${SWIFT[@]}" build -c "$CONFIG"
BIN="$("${SWIFT[@]}" build -c "$CONFIG" --show-bin-path)/Bifrost"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Bifrost"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Ad-hoc signature: gives the bundle a stable identity for the system's
# per-app preferences without needing a developer certificate.
codesign --force --sign - "$APP" >/dev/null 2>&1 || \
    echo "warning: ad-hoc code signing failed; the app will still run"

echo "Built $APP"
