# Building

```sh
./Scripts/build-app.sh          # release into ./build
./Scripts/build-app.sh debug    # debug build
```

The script compiles the package and assembles `build/Bifrost.app`.

To work on the code in Xcode, open `Package.swift`. Running from Xcode produces
a bare executable rather than an `.app` bundle, so the menu bar item behaves
best when launched from `build/Bifrost.app`.

## Versioning

`CFBundleShortVersionString` comes from the nearest git tag with its leading
`v` stripped, and `CFBundleVersion` from the commit count. Both are written
into the bundle at build time, so `Resources/Info.plist` holds placeholders
rather than real values. An untagged checkout builds as `0.0.0`.

Override either for a one-off build:

```sh
BIFROST_VERSION=1.2.3 BIFROST_BUILD_NUMBER=99 ./Scripts/build-app.sh
```

## Signing

The app is signed with a real identity rather than ad-hoc, because the
Accessibility permission used by window cycling is bound to the code signature.
An ad-hoc signature changes hash on every build, so macOS would re-prompt each
time. The designated requirement resolves to bundle ID plus certificate, which
stays stable across rebuilds.

The script picks the first identity it finds, preferring **Developer ID
Application** over **Apple Development**. Developer ID comes first so local
builds carry the same designated requirement as released ones — grant
Accessibility once and it holds across both.

Override the choice with an environment variable:

```sh
BIFROST_SIGN_IDENTITY="Apple Development: Your Name (XXXXXXXXXX)" ./Scripts/build-app.sh
```

If no identity is found the script falls back to ad-hoc signing and says so.
Everything still works, but Accessibility access needs re-granting after each
build.

Developer ID builds are timestamped, which notarization requires; other
identities skip the timestamp so builds work offline.

## Troubleshooting

**The build takes minutes instead of seconds.** The `swift` on your `PATH` may
be an older standalone toolchain — swiftly, or one in
`~/Library/Developer/Toolchains`. An old compiler parsing a much newer system
SwiftUI module is pathologically slow. `Scripts/build-app.sh` pins Xcode's
toolchain to avoid this; to do it by hand:

```sh
xcrun --toolchain com.apple.dt.toolchain.XcodeDefault swift build -c release
```

Compare `swift --version` against `xcrun swift --version` to spot the mismatch.
