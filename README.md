# Bifrost

A menu-bar-only macOS app that gives any application a global hotkey. Press the
shortcut and the app comes to the front — launching first if it isn't running.

Built with SwiftUI's `MenuBarExtra` and Carbon's `RegisterEventHotKey`, using
nothing but system frameworks. No dependencies, no Accessibility permission, no
Dock icon.

## Build

```sh
./Scripts/build-app.sh
open build/Bifrost.app
```

To work on it in Xcode, open `Package.swift` — though running from Xcode builds
a bare executable rather than the `.app` bundle, so the menu bar item behaves
best when launched from `build/Bifrost.app`.

## Use

1. Click the rainbow icon in the menu bar.
2. **Add App…** opens `/Applications`; pick one or several.
3. Click **Record** next to an app and press the combination you want.
   - Escape cancels, Delete clears the shortcut.
   - At least one of ⌘ ⌥ ⌃ is required, so ordinary typing is never captured.

Shortcuts take effect immediately and are restored on the next launch.

### Window cycling (optional, per app)

The window button in each row turns on cycling for that app: press its shortcut
again while it is already frontmost and Bifrost moves to its next window. Useful
for two Brave windows, or several Xcode projects.

This is the only feature that needs the **Accessibility** permission — there is
no way to enumerate or raise another app's individual windows without it. It is
off by default and per app, so everything else stays permission-free. macOS
prompts the first time you switch it on; you may need to reopen the menu
afterwards for Bifrost to notice the grant.

Minimized windows are skipped, as are panels and inspectors — only standard
windows take part.

## How it works

| Concern | Approach |
| --- | --- |
| Menu bar only | `LSUIElement` in `Info.plist` plus `NSApp.setActivationPolicy(.accessory)` |
| Global hotkeys | Carbon `RegisterEventHotKey` — handled by the window server, so no Accessibility permission is needed |
| Recording | A local `NSEvent` monitor, with registered hotkeys paused so an existing shortcut can't fire mid-recording |
| Key labels | `UCKeyTranslate` against the active layout, so non-QWERTY keyboards show the right glyph |
| Activation | `NSRunningApplication.activate()`, preceded by `NSApp.yieldActivation(to:)` for macOS cooperative activation; falls back to `NSWorkspace.openApplication` |
| Window cycling | Accessibility API: `kAXWindowsAttribute` to enumerate, `kAXRaiseAction` to raise |
| Storage | JSON at `~/Library/Application Support/Bifrost/entries.json` |

Carbon's hotkey API is old but is not deprecated, and remains the only way to
claim a system-wide shortcut without the Accessibility permission an event tap
would require.

## Layout

```
Sources/Bifrost/
  BifrostApp.swift      @main scene, app delegate
  Models.swift          Hotkey and AppEntry
  AppStore.swift        list, persistence, hotkey sync
  HotKeyManager.swift   Carbon registration and dispatch
  Launcher.swift        activate, launch, or cycle
  WindowCycler.swift    Accessibility window enumeration and raising
  AppPicker.swift       NSOpenPanel over /Applications
  KeyNames.swift        key code to glyph
  Views/
    ContentView.swift   menu content
    HotkeyField.swift   shortcut recorder
```

## Signing

The app is signed with a real identity rather than ad-hoc, because the
Accessibility permission is bound to the code signature. An ad-hoc signature
changes hash on every build, so macOS would re-prompt each time. The designated
requirement resolves to bundle ID plus certificate, which stays stable across
rebuilds.

Override the identity if you need to:

```sh
BIFROST_SIGN_IDENTITY="Apple Development: Your Name (XXXXXXXXXX)" ./Scripts/build-app.sh
```

## Troubleshooting

**The build takes minutes instead of seconds.** `swift` on your `PATH` may be an
older standalone toolchain (swiftly, or one in `~/Library/Developer/Toolchains`).
An old compiler parsing a much newer system SwiftUI module is pathologically
slow. `Scripts/build-app.sh` pins Xcode's toolchain to avoid this; to do it by
hand:

```sh
xcrun --toolchain com.apple.dt.toolchain.XcodeDefault swift build -c release
```

Compare `swift --version` against `xcrun swift --version` to spot the mismatch.
