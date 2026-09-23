import AppKit
import SwiftUI

@main
struct BifrostApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var store = AppStore.shared
    @State private var updater = Updater.shared

    var body: some Scene {
        MenuBarExtra("Bifrost", systemImage: "rainbow") {
            ContentView()
                .environment(store)
                .environment(updater)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu bar only: no Dock tile, no menu bar title, no main window.
        NSApp.setActivationPolicy(.accessory)

        MainActor.assumeIsolated {
            AppStore.shared.syncHotkeys()
        }
    }
}
