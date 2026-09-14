# How it works

Bifrost is a SwiftUI `MenuBarExtra` app built on system frameworks only.

| Concern | Approach |
| --- | --- |
| Menu bar only | `LSUIElement` in `Info.plist`, plus `NSApp.setActivationPolicy(.accessory)` |
| Global hotkeys | Carbon `RegisterEventHotKey` |
| Recording | A local `NSEvent` monitor, with registered hotkeys paused so an existing shortcut can't fire mid-recording |
| Key labels | `UCKeyTranslate` against the active layout, so non-QWERTY keyboards show the right glyph |
| Activation | `NSRunningApplication.activate()`, preceded by `NSApp.yieldActivation(to:)` for cooperative activation. An app running with no windows also gets a reopen through `NSWorkspace.openApplication`, the way clicking a Dock icon does |
| Window cycling | Accessibility API — `kAXWindowsAttribute` to enumerate, `kAXRaiseAction` to raise |
| Storage | JSON at `~/Library/Application Support/Bifrost/entries.json` |

## Why Carbon for hotkeys

`RegisterEventHotKey` is old but not deprecated, and it remains the only way to
claim a system-wide shortcut without the Accessibility permission a `CGEventTap`
would require. The window server dispatches the event, so shortcuts work no
matter which app is frontmost.

## Why window cycling needs Accessibility

Nothing else can enumerate or raise another app's individual windows.
`CGWindowListCopyWindowInfo` can list windows but not act on them, and
synthesizing ⌘\` is itself gated behind the same permission. So cycling is
opt-in per app, and the rest of Bifrost stays permission-free.

Two details worth knowing:

- **Rotation order is captured once**, when cycling starts, and compared against
  the live window list as a set. Raising a window reorders that list, so
  stepping through it by index would bounce between the front two windows.
- **Only standard windows take part.** Panels, sheets and inspectors are
  filtered out by subrole, and minimized windows are skipped rather than
  restored.

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
