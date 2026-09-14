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

## Reaching other desktops

The accessibility API only lists windows on the desktop currently showing, so
it cannot see — let alone raise — a window parked on another one.

Bifrost goes through the app's own **Window menu** instead. It lists every
window wherever it lives, marks the one in front with a checkmark, and choosing
an entry makes macOS switch desktops itself. Nothing has to track where the
rotation is, because the checkmark already says.

The alternative was switching desktops directly through the private
`CGSManagedDisplaySetCurrentSpace`. It works, but it changes the current Space
behind Dock's back, and Dock owns Mission Control's state — so Exposé is left
drawing from a stale model and renders incorrectly. Driving the menu keeps
every part of the system in agreement, and needs no private calls at all.

Finding the list is the fiddly part:

- Other menus share its shape. Brave's **Tab** menu is also a trailing list with
  the active entry checkmarked, and cycling tabs instead of windows would be
  quietly wrong. So the Window menu is recognised by the commands only it
  carries — "Bring All to Front", or Minimize on ⌘M — through their
  language-independent identifiers and key equivalents, and no other menu is
  ever considered.
- **Xcode groups windows by project**, one per separator-delimited group, so the
  last group is not always the whole list — and a command like "Bring All to
  Front" can sit alone in a group just like a window. Position can't tell them
  apart, but the menu items' actions can: every window entry shares the action
  behind the checkmarked front window, which no command does. So the entries
  are the items after "Bring All to Front" that share that action.
- Only the **checkmark** marks the front window. The same column shows ◆ for a
  minimized window and • for one with unsaved changes or a running process.

Apps without a usable Window menu fall back to cycling the windows on the
current desktop, where **only standard windows take part** — panels, sheets and
inspectors are filtered out by subrole, and minimized windows are skipped rather
than restored.

## Layout

```
Sources/Bifrost/
  BifrostApp.swift      @main scene, app delegate
  Models.swift          Hotkey and AppEntry
  AppStore.swift        list, persistence, hotkey sync
  HotKeyManager.swift   Carbon registration and dispatch
  Launcher.swift        activate, launch, or cycle
  WindowCycler.swift    window menu cycling, with an accessibility fallback
  AppPicker.swift       NSOpenPanel over /Applications
  KeyNames.swift        key code to glyph
  Views/
    ContentView.swift   menu content
    HotkeyField.swift   shortcut recorder
```
