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

# Sign with a real identity, not ad-hoc. The Accessibility permission is tied
# to the code signature, so an ad-hoc signature — whose hash changes on every
# build — would make macOS re-prompt after each rebuild.
IDENTITY="${BIFROST_SIGN_IDENTITY:-Apple Development: Adam Leitgeb (443BG854Y5)}"

if security find-identity -v -p codesigning | grep -qF "$IDENTITY"; then
    codesign --force --options runtime --sign "$IDENTITY" "$APP"
    echo "Signed as: $IDENTITY"
else
    echo "warning: identity '$IDENTITY' not found; falling back to ad-hoc."
    echo "         Accessibility permission will need re-granting after each build."
    echo "         Set BIFROST_SIGN_IDENTITY to choose another identity."
    codesign --force --sign - "$APP"
fi

echo "Built $APP"
