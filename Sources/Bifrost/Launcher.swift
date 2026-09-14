import AppKit
import CoreGraphics

/// Brings an app to the front, launching it first if it is not running.
///
/// When the app opts into window cycling, pressing the hotkey while it is
/// *already* frontmost moves to its next window instead of doing nothing.
enum Launcher {
    @MainActor
    static func activate(_ entry: AppEntry) {
        let running = NSRunningApplication.runningApplications(
            withBundleIdentifier: entry.bundleIdentifier
        ).first

        guard let running else {
            WindowCycler.forget(bundleIdentifier: entry.bundleIdentifier)
            open(entry.url)
            return
        }

        // Bifrost is an accessory app and never steals focus, so `isActive`
        // still reflects whichever app the user was actually working in.
        if entry.cyclesWindows, running.isActive, WindowCycler.isTrusted,
           WindowCycler.advance(for: running, bundleIdentifier: entry.bundleIdentifier) {
            return
        }

        // Apps that keep running with every window closed — Signal and
        // LM Studio among them — come to the front with nothing on screen,
        // because activating a process does not ask it to show a window.
        let showsNothing = !hasOnScreenWindows(running)

        // Under cooperative activation the frontmost app has to hand over its
        // claim, otherwise our request is deferred until the user clicks.
        NSApp.yieldActivation(to: running)
        running.activate()

        // Reopening is what clicking a Dock icon does: an app with windows
        // already open ignores it, one without opens a fresh window.
        if showsNothing {
            open(running.bundleURL ?? entry.url)
        }

        if entry.cyclesWindows, WindowCycler.isTrusted {
            // Pin the rotation to the window that is now in front, so the next
            // press steps off it predictably.
            WindowCycler.beginCycle(for: running, bundleIdentifier: entry.bundleIdentifier)
        }
    }

    /// Whether the app has any ordinary window on screen right now.
    ///
    /// `CGWindowListCopyWindowInfo` reports window geometry to any caller —
    /// only window *titles* are gated behind Screen Recording — so this keeps
    /// plain launching and focusing free of permissions.
    @MainActor
    private static func hasOnScreenWindows(_ app: NSRunningApplication) -> Bool {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            // If the window list is unavailable, assume the app has windows so
            // that an app which already works is never sent a stray reopen.
            return true
        }

        let pid = app.processIdentifier
        return windows.contains { window in
            guard window["kCGWindowOwnerPID"] as? pid_t == pid else { return false }
            // Layer 0 is the normal window level; menu bar items, status
            // popovers and the like sit above it and do not count.
            return window["kCGWindowLayer"] as? Int == 0
        }
    }

    @MainActor
    private static func open(_ url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else {
            NSSound.beep()
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
            if error != nil { NSSound.beep() }
        }
    }
}
