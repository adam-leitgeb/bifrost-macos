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

VERSION="${BIFROST_VERSION:-$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || true)}"
VERSION="${VERSION:-0.0.0}"

# CFBundleVersion must increase monotonically for Sparkle and macOS to regard a
# build as newer. Commit count does that without a counter to maintain by hand.
BUILD_NUMBER="${BIFROST_BUILD_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Bifrost"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP/Contents/Info.plist"

# Sign with a real identity, not ad-hoc. The Accessibility permission is tied
# to the code signature, so an ad-hoc signature — whose hash changes on every
# build — would make macOS re-prompt after each rebuild.
#
# Developer ID is preferred over Apple Development so local builds carry the
# same designated requirement as released ones, and the permission granted to
# one carries over to the other.
select_identity() {
    if [ -n "${BIFROST_SIGN_IDENTITY:-}" ]; then
        printf '%s' "$BIFROST_SIGN_IDENTITY"
        return
    fi

    local available
    available="$(security find-identity -v -p codesigning)"

    local kind
    for kind in "Developer ID Application" "Apple Development"; do
        local found
        found="$(printf '%s\n' "$available" | sed -n "s/.*\"\(${kind}[^\"]*\)\".*/\1/p" | head -1)"

        if [ -n "$found" ]; then
            printf '%s' "$found"
            return
        fi
    done
}

IDENTITY="$(select_identity)"

if [ -z "$IDENTITY" ]; then
    echo "warning: no signing identity found; falling back to ad-hoc."
    echo "         Accessibility permission will need re-granting after each build."
    echo "         Set BIFROST_SIGN_IDENTITY to choose an identity."
    codesign --force --sign - "$APP"
else
    # Notarization requires a secure timestamp, so Developer ID builds must
    # reach Apple's timestamp server. Development builds skip it to stay
    # usable offline.
    TIMESTAMP=(--timestamp=none)

    case "$IDENTITY" in
        "Developer ID Application"*) TIMESTAMP=(--timestamp) ;;
    esac

    codesign --force --options runtime "${TIMESTAMP[@]}" --sign "$IDENTITY" "$APP"
    echo "Signed as: $IDENTITY"
fi

echo "Built $APP ($VERSION build $BUILD_NUMBER)"
