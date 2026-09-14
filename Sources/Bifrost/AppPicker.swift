import AppKit
import UniformTypeIdentifiers

/// Standard open panel, pointed at /Applications and limited to app bundles.
enum AppPicker {
    @MainActor
    static func present(completion: @escaping ([URL]) -> Void) {
        let panel = NSOpenPanel()
        panel.title = "Add Applications"
        panel.prompt = "Add"
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.treatsFilePackagesAsDirectories = false

        // An accessory app has no windows of its own to attach a sheet to, and
        // needs to come forward for the panel to be usable.
        NSApp.activate(ignoringOtherApps: true)
        panel.begin { response in
            guard response == .OK else {
                return
            }

            completion(panel.urls)
        }
    }
}
