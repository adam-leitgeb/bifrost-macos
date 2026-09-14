import AppKit

/// Brings an app to the front, launching it first if it is not running.
///
/// With window cycling on, pressing the hotkey while the app is *already*
/// frontmost moves to its next window instead of doing nothing.
enum Launcher {
    @MainActor
    static func activate(_ entry: AppEntry, cyclesWindows: Bool) {
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
        if cyclesWindows, running.isActive, WindowCycler.isTrusted,
           WindowCycler.advance(for: running, bundleIdentifier: entry.bundleIdentifier) {
            return
        }

        // Under cooperative activation the frontmost app has to hand over its
        // claim, otherwise our request is deferred until the user clicks.
        NSApp.yieldActivation(to: running)
        running.activate()

        // Activating a process never asks it to show a window, so apps that
        // keep running with every window closed — Signal and LM Studio among
        // them — would come forward with nothing on screen. Reopen, as a Dock
        // click does. It goes out unconditionally: Bifrost can only see
        // windows on the current desktop, but AppKit tells the app about its
        // windows on every desktop, and an app that has some ignores it.
        open(running.bundleURL ?? entry.url)

        if cyclesWindows, WindowCycler.isTrusted {
            // Pin the rotation to the window that is now in front, so the next
            // press steps off it predictably.
            WindowCycler.beginCycle(for: running, bundleIdentifier: entry.bundleIdentifier)
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
