import AppKit
import ApplicationServices
import Foundation

/// Cycles through an app's windows on repeated hotkey presses, including
/// windows on other desktops.
///
/// Reaching another desktop is the hard part. The accessibility API only lists
/// windows on the desktop currently showing, and switching desktops behind
/// macOS's back leaves Mission Control drawing from a stale model. So this goes
/// through the app's own Window menu instead: it lists every window wherever it
/// lives, marks the active one with a checkmark, and picking an entry makes
/// macOS switch desktops itself, properly.
///
/// Apps without a usable Window menu fall back to cycling the windows on the
/// current desktop.
@MainActor
enum WindowCycler {
    /// Accessibility calls are synchronous IPC into the target app; without a
    /// timeout a beachballing app would hang our hotkey handler.
    private static let messagingTimeout: Float = 0.5

    /// Rotation state for the fallback path only.
    private static var fallbackCycles: [String: (windows: [AXUIElement], index: Int)] = [:]

    // MARK: - Permission

    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    @discardableResult
    static func requestTrust() -> Bool {
        // The SDK imports `kAXTrustedCheckOptionPrompt` as a mutable global,
        // which Swift 6 rejects as not concurrency-safe; its value is stable
        // and documented, so use it directly.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Cycling

    /// Only the fallback keeps state; the Window menu already knows which
    /// window is current.
    static func beginCycle(for app: NSRunningApplication, bundleIdentifier: String) {
        guard windowMenuEntries(of: app).isEmpty else { return }
        let windows = cyclableWindows(of: app)
        fallbackCycles[bundleIdentifier] = windows.isEmpty ? nil : (windows, 0)
    }

    /// Moves to the app's next window. Returns false when there is nothing to
    /// cycle through.
    @discardableResult
    static func advance(for app: NSRunningApplication, bundleIdentifier: String) -> Bool {
        let entries = windowMenuEntries(of: app)
        guard !entries.isEmpty else {
            return fallbackAdvance(for: app, bundleIdentifier: bundleIdentifier)
        }

        // The checkmark marks the window in front, so there is no rotation
        // state to keep and nothing that can drift out of step.
        let current = entries.firstIndex(where: isCheckmarked) ?? 0
        let target = entries[(current + 1) % entries.count]
        AXUIElementPerformAction(target, kAXPressAction as CFString)
        return true
    }

    static func forget(bundleIdentifier: String) {
        fallbackCycles[bundleIdentifier] = nil
    }

    // MARK: - Window menu

    private static func windowMenuEntries(of app: NSRunningApplication) -> [AXUIElement] {
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(element, messagingTimeout)

        guard let menuBar = elementAttribute(element, kAXMenuBarAttribute),
              let windowMenu = windowMenu(in: menuBar)
        else { return [] }
        return windowEntries(of: windowMenu)
    }

    /// Other menus can pass for a window list — Brave's Tab menu lists tabs
    /// with the active one checkmarked, and Finder's View menu checkmarks its
    /// view mode — so the Window menu is recognised by the commands only it
    /// carries, not by shape. Its title is localised, so not by that either.
    private static func windowMenu(in menuBar: AXUIElement) -> AXUIElement? {
        for menuBarItem in children(of: menuBar).reversed() {
            guard let menu = children(of: menuBarItem).first else { continue }
            if children(of: menu).contains(where: { isWindowListAnchor($0) || isMinimize($0) }) {
                return menu
            }
        }
        return nil
    }

    /// Position alone can't find the entries: Xcode splits its windows into
    /// one separator-delimited group per project, and commands such as "Bring
    /// All to Front" can sit alone in a group just like a window. What sets
    /// windows apart is that they share one action, the one behind the
    /// checkmarked front window. Items without an identifier fall back to the
    /// front window's group.
    private static func windowEntries(of menu: AXUIElement) -> [AXUIElement] {
        let items = children(of: menu)
        let candidates = items.lastIndex(where: isWindowListAnchor).map { Array(items[($0 + 1)...]) } ?? items

        let checkmarked = candidates.filter(isCheckmarked)
        guard checkmarked.count == 1, let front = checkmarked.first else { return [] }

        let entries: [AXUIElement]
        if let action = identifier(of: front) {
            entries = candidates.filter { identifier(of: $0) == action }
        } else {
            entries = separatedGroups(of: candidates).first { $0.contains { CFEqual($0, front) } } ?? []
        }
        return entries.count > 1 ? entries : []
    }

    private static func separatedGroups(of items: [AXUIElement]) -> [[AXUIElement]] {
        var groups: [[AXUIElement]] = []
        var current: [AXUIElement] = []

        for item in items {
            if isSeparator(item) {
                if !current.isEmpty { groups.append(current) }
                current = []
            } else {
                current.append(item)
            }
        }
        if !current.isEmpty { groups.append(current) }
        return groups
    }

    /// Separators carry no title.
    private static func isSeparator(_ element: AXUIElement) -> Bool {
        title(of: element)?.isEmpty ?? true
    }

    /// AppKit appends the window list after "Bring All to Front" and its
    /// "Arrange in Front" alternate. Identifiers are selector names, so they
    /// hold in every language.
    private static func isWindowListAnchor(_ element: AXUIElement) -> Bool {
        guard let identifier = identifier(of: element) else { return false }
        return identifier == "arrangeInFront" || identifier == "alternateArrangeInFront"
    }

    private static func isMinimize(_ element: AXUIElement) -> Bool {
        let commandAlone = 0
        return attribute(element, kAXMenuItemCmdCharAttribute) as? String == "M"
            && attribute(element, kAXMenuItemCmdModifiersAttribute) as? Int == commandAlone
    }

    /// Other marks share the column: ◆ for a minimized window, • for one with
    /// unsaved changes or a running process.
    private static func isCheckmarked(_ element: AXUIElement) -> Bool {
        attribute(element, "AXMenuItemMarkChar") as? String == "✓"
    }

    // MARK: - Fallback: windows on the current desktop

    private static func fallbackAdvance(for app: NSRunningApplication, bundleIdentifier: String) -> Bool {
        let live = cyclableWindows(of: app)
        guard live.count > 1 else {
            fallbackCycles[bundleIdentifier] = nil
            return false
        }

        var cycle: (windows: [AXUIElement], index: Int)
        if let stored = fallbackCycles[bundleIdentifier], sameWindows(stored.windows, live) {
            cycle = stored
        } else {
            // Raising a window reorders the live list, so the order is captured
            // once and rebuilt only when windows actually open or close.
            cycle = (live, 0)
        }

        cycle.index = (cycle.index + 1) % cycle.windows.count
        fallbackCycles[bundleIdentifier] = cycle

        AXUIElementPerformAction(cycle.windows[cycle.index], kAXRaiseAction as CFString)
        return true
    }

    /// Skips panels, sheets and inspectors — Xcode reports a lot of those — and
    /// skips minimized windows, since un-minimizing something the user put away
    /// mid-cycle is more surprising than helpful.
    private static func cyclableWindows(of app: NSRunningApplication) -> [AXUIElement] {
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(element, messagingTimeout)

        guard let windows = attribute(element, kAXWindowsAttribute) as? [AXUIElement] else { return [] }
        return windows.filter { window in
            if attribute(window, kAXMinimizedAttribute) as? Bool == true { return false }
            if let subrole = attribute(window, kAXSubroleAttribute) as? String {
                return subrole == kAXStandardWindowSubrole
            }
            return attribute(window, kAXRoleAttribute) as? String == kAXWindowRole
        }
    }

    private static func sameWindows(_ lhs: [AXUIElement], _ rhs: [AXUIElement]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        for window in lhs where !rhs.contains(where: { CFEqual($0, window) }) {
            return false
        }
        return true
    }

    // MARK: - Accessibility helpers

    private static func attribute(_ element: AXUIElement, _ name: String) -> Any? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    /// A conditional cast to a CoreFoundation type always succeeds, so the
    /// type has to be checked explicitly.
    private static func elementAttribute(_ element: AXUIElement, _ name: String) -> AXUIElement? {
        guard let value = attribute(element, name) else { return nil }
        let raw = value as CFTypeRef
        guard CFGetTypeID(raw) == AXUIElementGetTypeID() else { return nil }
        return (raw as! AXUIElement)
    }

    private static func children(of element: AXUIElement) -> [AXUIElement] {
        attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
    }

    private static func title(of element: AXUIElement) -> String? {
        attribute(element, kAXTitleAttribute) as? String
    }

    private static func identifier(of element: AXUIElement) -> String? {
        guard let identifier = attribute(element, kAXIdentifierAttribute) as? String, !identifier.isEmpty else { return nil }
        return identifier
    }
}
