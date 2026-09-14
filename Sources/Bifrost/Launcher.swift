import AppKit

/// Brings an app to the front, launching it first if it is not running.
enum Launcher {
    @MainActor
    static func activate(_ entry: AppEntry) {
        let running = NSRunningApplication.runningApplications(
            withBundleIdentifier: entry.bundleIdentifier
        ).first

        if let running {
            // Under cooperative activation the frontmost app has to hand over
            // its claim, otherwise our request is deferred until the user
            // clicks something.
            NSApp.yieldActivation(to: running)
            running.activate()
            return
        }

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
