import AppKit
import Observation

/// Owns the app list, persists it to disk, and keeps the registered hotkeys
/// in sync with it.
@MainActor
@Observable
final class AppStore {
    static let shared = AppStore()

    private(set) var entries: [AppEntry] = []

    private(set) var cyclesWindows = UserDefaults.standard.bool(forKey: cyclesWindowsKey)

    private static let cyclesWindowsKey = "cyclesWindows"

    private let fileURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Bifrost/entries.json")
    }()

    private init() {
        load()
    }

    // MARK: - Mutations

    func add(urls: [URL]) {
        var added = false
        for url in urls {
            guard let entry = AppEntry(url: url) else {
                continue
            }

            guard !entries.contains(where: { $0.bundleIdentifier == entry.bundleIdentifier }) else {
                continue
            }

            entries.append(entry)
            added = true
        }

        guard added else {
            return
        }

        sortEntries()
        persist()
    }

    func remove(_ entry: AppEntry) {
        guard entry.isRemovable else {
            return
        }

        entries.removeAll { $0.id == entry.id }
        WindowCycler.forget(bundleIdentifier: entry.bundleIdentifier)
        persist()
    }

    func setHotkey(_ hotkey: Hotkey?, for entry: AppEntry) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else {
            return
        }

        entries[index].hotkey = hotkey
        persist()
    }

    func setCyclesWindows(_ enabled: Bool) {
        cyclesWindows = enabled
        UserDefaults.standard.set(enabled, forKey: Self.cyclesWindowsKey)

        if !enabled {
            WindowCycler.forgetAll()
        }
    }

    /// The entry, if any, already using `hotkey` — other than `entry` itself.
    func conflict(for hotkey: Hotkey, excluding entry: AppEntry) -> AppEntry? {
        entries.first { $0.id != entry.id && $0.hotkey == hotkey }
    }

    // MARK: - Hotkeys

    func syncHotkeys() {
        HotKeyManager.shared.setHotkeys(
            entries.compactMap { entry in
                guard let hotkey = entry.hotkey else {
                    return nil
                }

                return (hotkey: hotkey, action: { Launcher.activate(entry, cyclesWindows: self.cyclesWindows) })
            }
        )
    }

    // MARK: - Ordering

    private func sortEntries() {
        entries.sort { lhs, rhs in
            if lhs.isRemovable != rhs.isRemovable {
                return !lhs.isRemovable
            }

            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    private func insertFinderIfMissing() {
        guard !entries.contains(where: { !$0.isRemovable }), let finder = AppEntry.finder else {
            return
        }

        entries.append(finder)
    }

    // MARK: - Persistence

    private func persist() {
        syncHotkeys()
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(entries).write(to: fileURL, options: .atomic)
        } catch {
            NSLog("Bifrost: could not save entries — \(error.localizedDescription)")
        }
    }

    private func load() {
        defer {
            insertFinderIfMissing()
            sortEntries()
        }

        guard let data = try? Data(contentsOf: fileURL) else {
            return
        }

        do {
            entries = try JSONDecoder().decode([AppEntry].self, from: data)
        } catch {
            NSLog("Bifrost: could not read entries — \(error.localizedDescription)")
        }
    }
}
