# Releasing

Pushing a `v*` tag builds, signs, notarizes and publishes a GitHub release:

```sh
git tag v1.0.0
git push origin v1.0.0
```

`.github/workflows/release.yml` runs `Scripts/build-app.sh` followed by
`Scripts/package-release.sh`, and attaches `Bifrost.dmg` to the release.

## What notarization does

Apple scans the signed app and issues a ticket, which `stapler` attaches to it.
Without one macOS refuses to open an app downloaded from the internet,
reporting it as damaged. `Scripts/package-release.sh` refuses to submit a build
that is not signed with a Developer ID identity, since Apple would reject it.

Notarization runs twice: once on the app, and again on the finished disk image.
Stapling the app before it goes into the image means a copy dragged out to
`/Applications` validates offline, rather than needing a network lookup on
first launch.

The app is archived with `ditto`, not `zip`, for submission. A plain `zip`
flattens the symlinks inside a bundle, and notarization rejects the result.

## The disk image

`hdiutil` builds it from a staging folder holding the app beside a symlink to
`/Applications`, which is what makes the drag-to-install gesture work. The
image is signed and notarized in its own right. There is no custom background
or icon layout; Finder's defaults put the two icons side by side.

## Required secrets

| Secret | Purpose |
| --- | --- |
| `DEVELOPER_ID_P12_BASE64` | Developer ID cert and private key, base64 of a `.p12` |
| `DEVELOPER_ID_P12_PASSWORD` | Password set when exporting that `.p12` |
| `APP_STORE_CONNECT_KEY_ID` | App Store Connect API key, for notarization |
| `APP_STORE_CONNECT_ISSUER_ID` | Issuer the key belongs to |
| `APP_STORE_CONNECT_KEY_CONTENT` | Base64 of the `.p8` key file |

The three `APP_STORE_CONNECT_*` values are the same ones used to ship iOS apps
under this team; notarization authenticates with the same API key.

## Running it locally

```sh
./Scripts/build-app.sh
APP_STORE_CONNECT_KEY_ID=... \
APP_STORE_CONNECT_ISSUER_ID=... \
APP_STORE_CONNECT_KEY_PATH=/path/to/AuthKey_XXXX.p8 \
  ./Scripts/package-release.sh
```

## Certificate renewal

The Developer ID certificate expires, and only the team's Account Holder can
issue a new one. Releases already signed and notarized keep working after it
expires — the timestamp in the signature vouches for them — but no new release
can be signed until it is renewed.
