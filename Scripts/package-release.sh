#!/bin/bash
# Notarizes build/Bifrost.app and packages it as a distributable disk image.
#
#   ./Scripts/package-release.sh
#
# Authenticates to Apple with an App Store Connect API key, taken from either
# APP_STORE_CONNECT_KEY_CONTENT (base64 of the .p8) or APP_STORE_CONNECT_KEY_PATH,
# alongside APP_STORE_CONNECT_KEY_ID and APP_STORE_CONNECT_ISSUER_ID.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/build/Bifrost.app"
DMG="$ROOT/build/Bifrost.dmg"

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

spctl --assess --type execute --verbose=2 "$APP"

echo "Packaged $DMG"
