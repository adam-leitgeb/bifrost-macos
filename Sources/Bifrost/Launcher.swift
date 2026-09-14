import AppKit

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
            launch(entry)
            return
        }

        // Bifrost is an accessory app and never steals focus, so `isActive`
        // still reflects whichever app the user was actually working in.
        if entry.cyclesWindows, running.isActive, WindowCycler.isTrusted {
            WindowCycler.advance(for: running, bundleIdentifier: entry.bundleIdentifier)
            return
        }

        // Under cooperative activation the frontmost app has to hand over its
        // claim, otherwise our request is deferred until the user clicks.
        NSApp.yieldActivation(to: running)
        running.activate()

        if entry.cyclesWindows, WindowCycler.isTrusted {
            // Pin the rotation to the window that is now in front, so the next
            // press steps off it predictably.
            WindowCycler.beginCycle(for: running, bundleIdentifier: entry.bundleIdentifier)
        }
    }

    @MainActor
    private static func launch(_ entry: AppEntry) {
        guard entry.existsOnDisk else {
            NSSound.beep()
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: entry.url, configuration: configuration) { _, error in
            if error != nil { NSSound.beep() }
        }
    }
}
