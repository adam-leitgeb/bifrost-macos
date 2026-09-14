import ApplicationServices
import AppKit

/// Cycles through an app's windows on repeated hotkey presses.
///
/// This is the one feature that needs the Accessibility permission: there is
/// no way to enumerate or raise another app's individual windows without it.
/// It is opt-in per app so the rest of Bifrost stays permission-free.
@MainActor
enum WindowCycler {
    /// Where we are in one app's window rotation.
    private struct Cycle {
        /// Captured when the rotation starts. Deliberately *not* refreshed on
        /// every press: raising a window reorders the live list, so stepping
        /// through that would ping-pong between the front two windows forever.
        var windows: [AXUIElement]
        var index: Int
    }

    private static var cycles: [String: Cycle] = [:]

    /// Accessibility calls are synchronous IPC into the target app; without a
    /// timeout a beachballing app would hang our hotkey handler.
    private static let messagingTimeout: Float = 0.5

    // MARK: - Permission

    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Shows the system's "grant Accessibility" prompt if not yet trusted.
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

    /// Starts a fresh rotation, pinned to the app's current front window.
    static func beginCycle(for app: NSRunningApplication, bundleIdentifier: String) {
        let windows = standardWindows(of: app)
        guard !windows.isEmpty else {
            cycles[bundleIdentifier] = nil
            return
        }
        cycles[bundleIdentifier] = Cycle(windows: windows, index: 0)
    }

    /// Raises the next window in the rotation. Returns false when there is
    /// nothing to cycle (one window, or Accessibility not granted).
    @discardableResult
    static func advance(for app: NSRunningApplication, bundleIdentifier: String) -> Bool {
        let live = standardWindows(of: app)
        guard live.count > 1 else {
            cycles[bundleIdentifier] = nil
            return false
        }

        var cycle: Cycle
        if let stored = cycles[bundleIdentifier], sameWindows(stored.windows, live) {
            cycle = stored
        } else {
            // Windows opened or closed since the rotation started, so the
            // remembered order is stale.
            cycle = Cycle(windows: live, index: 0)
        }

        cycle.index = (cycle.index + 1) % cycle.windows.count
        let target = cycle.windows[cycle.index]
        cycles[bundleIdentifier] = cycle

        AXUIElementPerformAction(target, kAXRaiseAction as CFString)
        return true
    }

    static func forget(bundleIdentifier: String) {
        cycles[bundleIdentifier] = nil
    }

    // MARK: - Window inspection

    private static func standardWindows(of app: NSRunningApplication) -> [AXUIElement] {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(appElement, messagingTimeout)

        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement]
        else { return [] }

        return windows.filter(isCyclable)
    }

    /// Skips panels, sheets and inspectors — Xcode in particular reports a lot
    /// of those — and skips minimized windows, since un-minimizing something
    /// the user explicitly put away mid-cycle is more surprising than helpful.
    private static func isCyclable(_ window: AXUIElement) -> Bool {
        if boolValue(window, kAXMinimizedAttribute) == true { return false }
        if let subrole = stringValue(window, kAXSubroleAttribute) {
            return subrole == kAXStandardWindowSubrole
        }
        return stringValue(window, kAXRoleAttribute) == kAXWindowRole
    }

    private static func sameWindows(_ lhs: [AXUIElement], _ rhs: [AXUIElement]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        for window in lhs where !rhs.contains(where: { CFEqual($0, window) }) {
            return false
        }
        return true
    }

    private static func stringValue(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private static func boolValue(_ element: AXUIElement, _ attribute: String) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? Bool
    }
}
