import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

/// Cycles through an app's windows on repeated hotkey presses, including
/// windows sitting on other desktops.
///
/// The accessibility API only reports windows on the desktop that is currently
/// showing, so reaching the rest means asking the window server directly — see
/// `SpaceBridge`. Accessibility is still what actually raises a window, so the
/// permission is required either way.
@MainActor
enum WindowCycler {
    /// Accessibility calls are synchronous IPC into the target app; without a
    /// timeout a beachballing app would hang our hotkey handler.
    private static let messagingTimeout: Float = 0.5

    /// Anything smaller than this is a scratch buffer, not a window.
    private static let minimumSide: Double = 100

    /// How long to let a desktop switch settle before raising. The transition
    /// is animated, and the window is not reachable until it finishes.
    private static let spaceSwitchDelay: TimeInterval = 0.45

    private struct Window {
        let id: CGWindowID
        let space: Int
    }

    /// Fallback rotation, used only when the window-server symbols are absent.
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

    /// Only the fallback keeps state. The main path works out where it is from
    /// the window actually in front, so there is nothing to prime.
    static func beginCycle(for app: NSRunningApplication, bundleIdentifier: String) {
        guard !SpaceBridge.isAvailable else { return }
        fallbackBeginCycle(for: app, bundleIdentifier: bundleIdentifier)
    }

    /// Moves to the app's next window, switching desktops if that is where it
    /// lives. Returns false when there is nothing to cycle.
    @discardableResult
    static func advance(for app: NSRunningApplication, bundleIdentifier: String) -> Bool {
        guard SpaceBridge.isAvailable else {
            return fallbackAdvance(for: app, bundleIdentifier: bundleIdentifier)
        }

        let windows = self.windows(of: app)
        guard windows.count > 1 else { return false }

        // Anchoring on the window that is genuinely in front, rather than on
        // whatever was aimed at last time, keeps the rotation honest: a raise
        // that does not land costs one press instead of desynchronising it.
        let current = frontmostVisibleWindowID(of: app)
        let index = current.flatMap { id in windows.firstIndex { $0.id == id } } ?? -1
        reveal(windows[(index + 1) % windows.count], of: app)
        return true
    }

    /// Whether the frontmost window on screen belongs to `app`.
    ///
    /// `NSRunningApplication.isActive` is unreliable in the moments after a
    /// desktop switch, which would otherwise turn a press meant to cycle into
    /// a plain re-activation.
    static func ownsFrontWindow(_ app: NSRunningApplication) -> Bool {
        guard let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else { return false }

        let visible = SpaceBridge.activeSpaces()

        for entry in list {
            guard entry["kCGWindowLayer"] as? Int == 0,
                  let id = entry["kCGWindowNumber"] as? CGWindowID,
                  let bounds = entry["kCGWindowBounds"] as? [String: Any],
                  bounds["Width"] as? Double ?? 0 >= minimumSide,
                  bounds["Height"] as? Double ?? 0 >= minimumSide,
                  let space = SpaceBridge.spaces(forWindow: id).first,
                  visible.contains(space)
            else { continue }
            // The first qualifying entry is the frontmost window on screen.
            return entry["kCGWindowOwnerPID"] as? pid_t == app.processIdentifier
        }
        return false
    }

    static func forget(bundleIdentifier: String) {
        fallbackCycles[bundleIdentifier] = nil
    }

    // MARK: - Window inspection

    /// Every real window of the app, on every desktop, in a stable order.
    private static func windows(of app: NSRunningApplication) -> [Window] {
        guard let list = CGWindowListCopyWindowInfo(
            [.optionAll, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else { return [] }

        let pid = app.processIdentifier
        var found: [Window] = []

        for entry in list {
            guard entry["kCGWindowOwnerPID"] as? pid_t == pid,
                  // Layer 0 is the ordinary window level; panels and status
                  // items sit above it.
                  entry["kCGWindowLayer"] as? Int == 0,
                  entry["kCGWindowAlpha"] as? Double ?? 1 > 0,
                  let id = entry["kCGWindowNumber"] as? CGWindowID,
                  let bounds = entry["kCGWindowBounds"] as? [String: Any],
                  bounds["Width"] as? Double ?? 0 >= minimumSide,
                  bounds["Height"] as? Double ?? 0 >= minimumSide
            else { continue }

            // A real window always belongs to a desktop. The offscreen buffers
            // that Chromium and Xcode keep around belong to none, which is the
            // most reliable way to tell the two apart.
            guard let space = SpaceBridge.spaces(forWindow: id).first else { continue }
            found.append(Window(id: id, space: space))
        }

        // Window ids increase with age, so this is creation order: a rotation
        // that does not reshuffle itself as windows are raised.
        return found.sorted { $0.id < $1.id }
    }

    /// The app's frontmost window among those actually on show.
    ///
    /// The on-screen window list is ordered front to back, but it also carries
    /// windows parked on other desktops, so each candidate is checked against
    /// the Spaces currently displayed.
    private static func frontmostVisibleWindowID(of app: NSRunningApplication) -> CGWindowID? {
        guard let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else { return nil }

        let visible = SpaceBridge.activeSpaces()
        let pid = app.processIdentifier

        for entry in list where entry["kCGWindowOwnerPID"] as? pid_t == pid {
            guard entry["kCGWindowLayer"] as? Int == 0,
                  let id = entry["kCGWindowNumber"] as? CGWindowID,
                  let bounds = entry["kCGWindowBounds"] as? [String: Any],
                  bounds["Width"] as? Double ?? 0 >= minimumSide,
                  bounds["Height"] as? Double ?? 0 >= minimumSide,
                  let space = SpaceBridge.spaces(forWindow: id).first,
                  visible.contains(space)
            else { continue }
            return id
        }
        return nil
    }

    // MARK: - Raising

    private static func reveal(_ window: Window, of app: NSRunningApplication) {
        guard !SpaceBridge.isVisible(space: window.space) else {
            raise(window.id, of: app)
            return
        }

        SpaceBridge.show(space: window.space)
        DispatchQueue.main.asyncAfter(deadline: .now() + spaceSwitchDelay) {
            raise(window.id, of: app)
        }
    }

    private static func raise(_ id: CGWindowID, of app: NSRunningApplication, attemptsLeft: Int = 2) {
        NSApp.yieldActivation(to: app)
        app.activate()

        if let element = accessibilityWindow(id, of: app) {
            AXUIElementPerformAction(element, kAXRaiseAction as CFString)
            return
        }

        // Straight after a desktop switch the window may not be listed yet.
        guard attemptsLeft > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            raise(id, of: app, attemptsLeft: attemptsLeft - 1)
        }
    }

    private static func accessibilityWindow(_ id: CGWindowID, of app: NSRunningApplication) -> AXUIElement? {
        for window in accessibilityWindows(of: app) where SpaceBridge.windowID(of: window) == id {
            return window
        }
        return nil
    }

    private static func accessibilityWindows(of app: NSRunningApplication) -> [AXUIElement] {
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(element, messagingTimeout)

        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement]
        else { return [] }
        return windows
    }

    // MARK: - Fallback for when the window-server symbols are gone

    private static func fallbackBeginCycle(for app: NSRunningApplication, bundleIdentifier: String) {
        let windows = cyclableAccessibilityWindows(of: app)
        fallbackCycles[bundleIdentifier] = windows.isEmpty ? nil : (windows, 0)
    }

    private static func fallbackAdvance(for app: NSRunningApplication, bundleIdentifier: String) -> Bool {
        let live = cyclableAccessibilityWindows(of: app)
        guard live.count > 1 else {
            fallbackCycles[bundleIdentifier] = nil
            return false
        }

        var cycle: (windows: [AXUIElement], index: Int)
        if let stored = fallbackCycles[bundleIdentifier], sameWindows(stored.windows, live) {
            cycle = stored
        } else {
            // Raising a window reorders the live list, so the order is captured
            // once and only rebuilt when windows actually open or close.
            cycle = (live, 0)
        }

        cycle.index = (cycle.index + 1) % cycle.windows.count
        fallbackCycles[bundleIdentifier] = cycle

        AXUIElementPerformAction(cycle.windows[cycle.index], kAXRaiseAction as CFString)
        return true
    }

    private static func cyclableAccessibilityWindows(of app: NSRunningApplication) -> [AXUIElement] {
        accessibilityWindows(of: app).filter { window in
            if boolValue(window, kAXMinimizedAttribute) == true { return false }
            if let subrole = stringValue(window, kAXSubroleAttribute) {
                return subrole == kAXStandardWindowSubrole
            }
            return stringValue(window, kAXRoleAttribute) == kAXWindowRole
        }
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
