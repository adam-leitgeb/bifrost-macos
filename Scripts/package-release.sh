#!/bin/bash
# Notarizes build/Bifrost.app and packages it as a distributable disk image,
# plus the zip and appcast.xml that Sparkle updates installed copies from.
#
#   ./Scripts/package-release.sh
#
# Authenticates to Apple with an App Store Connect API key, taken from either
# APP_STORE_CONNECT_KEY_CONTENT (base64 of the .p8) or APP_STORE_CONNECT_KEY_PATH,
# alongside APP_STORE_CONNECT_KEY_ID and APP_STORE_CONNECT_ISSUER_ID.
#
# Signs the update with SPARKLE_ED_PRIVATE_KEY, as exported by
# `generate_keys -x`.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/build/Bifrost.app"
DMG="$ROOT/build/Bifrost.dmg"
ZIP="$ROOT/build/Bifrost.zip"
APPCAST="$ROOT/build/appcast.xml"
SPARKLE_BIN="$ROOT/.build/artifacts/sparkle/Sparkle/bin"

if [ ! -d "$APP" ]; then
    echo "error: $APP not found. Run Scripts/build-app.sh first." >&2
    exit 1
fi

if ! codesign --verify --strict "$APP" 2>/dev/null; then
    echo "error: $APP is not validly signed." >&2
    exit 1
fi

IDENTITY="$(codesign -dv --verbose=4 "$APP" 2>&1 | sed -n 's/^Authority=//p' | head -1)"

case "$IDENTITY" in
    "Developer ID Application"*) ;;
    *)
        echo "error: signed as '${IDENTITY:-ad-hoc}', which Apple will not notarize." >&2
        echo "       A Developer ID Application identity is required." >&2
        exit 1
        ;;
esac

PLIST="$APP/Contents/Info.plist"
VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$PLIST")"

# Without the public key every update is refused, and an install shipped
# without it can never be updated to one that has it.
if ! /usr/libexec/PlistBuddy -c "Print :SUPublicEDKey" "$PLIST" > /dev/null 2>&1; then
    echo "error: SUPublicEDKey is missing from Info.plist." >&2
    echo "       Run $SPARKLE_BIN/generate_keys and add the key it prints." >&2
    exit 1
fi

if [ -z "${SPARKLE_ED_PRIVATE_KEY:-}" ]; then
    echo "error: set SPARKLE_ED_PRIVATE_KEY to the key from 'generate_keys -x'." >&2
    exit 1
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

KEY="$WORK/AuthKey.p8"

if [ -n "${APP_STORE_CONNECT_KEY_CONTENT:-}" ]; then
    printf '%s' "$APP_STORE_CONNECT_KEY_CONTENT" | base64 --decode > "$KEY"
elif [ -n "${APP_STORE_CONNECT_KEY_PATH:-}" ]; then
    cp "$APP_STORE_CONNECT_KEY_PATH" "$KEY"
else
    echo "error: set APP_STORE_CONNECT_KEY_CONTENT or APP_STORE_CONNECT_KEY_PATH." >&2
    exit 1
fi

notarize() {
    xcrun notarytool submit "$1" \
        --key "$KEY" \
        --key-id "${APP_STORE_CONNECT_KEY_ID:?set APP_STORE_CONNECT_KEY_ID}" \
        --issuer "${APP_STORE_CONNECT_ISSUER_ID:?set APP_STORE_CONNECT_ISSUER_ID}" \
        --wait
}

# The app is notarized and stapled before going into the image, so a copy
# dragged out of it validates offline too. Stapling the image alone would
# leave the installed app relying on a network lookup at first launch.
#
# ditto, not zip: the bundle carries symlinks that a plain zip flattens, which
# makes notarization reject the submission.
ditto -c -k --keepParent "$APP" "$WORK/app.zip"
notarize "$WORK/app.zip"
xcrun stapler staple "$APP"

STAGE="$WORK/dmg"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

rm -f "$DMG"
hdiutil create -volname "Bifrost" -srcfolder "$STAGE" -ov -format UDZO -quiet "$DMG"

codesign --force --timestamp --sign "$IDENTITY" "$DMG"
notarize "$DMG"
xcrun stapler staple "$DMG"

# Sparkle installs from a zip of the stapled app, not the disk image: it only
# has to unpack it, and the app inside is the one already notarized above.
UPDATES="$WORK/updates"
mkdir -p "$UPDATES"
ditto -c -k --keepParent "$APP" "$UPDATES/Bifrost.zip"

ED_KEY="$WORK/sparkle_ed_key"
printf '%s' "$SPARKLE_ED_PRIVATE_KEY" > "$ED_KEY"

TAG="v$VERSION"
RELEASES="https://github.com/adam-leitgeb/bifrost-macos/releases"

"$SPARKLE_BIN/generate_appcast" \
    --ed-key-file "$ED_KEY" \
    --download-url-prefix "$RELEASES/download/$TAG/" \
    --full-release-notes-url "$RELEASES/tag/$TAG" \
    --maximum-deltas 0 \
    -o "$APPCAST" \
    "$UPDATES"

cp "$UPDATES/Bifrost.zip" "$ZIP"

spctl --assess --type execute --verbose=2 "$APP"

echo "Packaged $DMG"
