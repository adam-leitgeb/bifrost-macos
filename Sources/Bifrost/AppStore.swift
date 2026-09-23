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

    private(set) var snapsWindows = UserDefaults.standard.bool(forKey: snapsWindowsKey)

    private(set) var snapHotkeys: [SnapPosition: Hotkey] = [:]

    private static let cyclesWindowsKey = "cyclesWindows"
    private static let snapsWindowsKey = "snapsWindows"
    private static let snapHotkeysKey = "snapHotkeys"

    private let fileURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Bifrost/entries.json")
    }()

    private init() {
        load()
        loadSnapHotkeys()
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

    func setSnapsWindows(_ enabled: Bool) {
        snapsWindows = enabled
        UserDefaults.standard.set(enabled, forKey: Self.snapsWindowsKey)
        syncHotkeys()
    }

    func setSnapHotkey(_ hotkey: Hotkey?, for position: SnapPosition) {
        snapHotkeys[position] = hotkey
        persistSnapHotkeys()
        syncHotkeys()
    }

    /// The name of whatever already uses `hotkey`, other than `owner` itself.
    func conflict(for hotkey: Hotkey, excluding owner: ShortcutOwner) -> String? {
        if let entry = entries.first(where: { .app($0.id) != owner && $0.hotkey == hotkey }) {
            return entry.name
        }

        let position = SnapPosition.allCases.first { .snap($0) != owner && snapHotkeys[$0] == hotkey }
        return position?.title
    }

    // MARK: - Hotkeys

    func syncHotkeys() {
        let appHotkeys: [(hotkey: Hotkey, action: () -> Void)] = entries.compactMap { entry in
            guard let hotkey = entry.hotkey else {
                return nil
            }

            return (hotkey: hotkey, action: { Launcher.activate(entry, cyclesWindows: self.cyclesWindows) })
        }

        let snapHotkeys: [(hotkey: Hotkey, action: () -> Void)] = snapsWindows
            ? SnapPosition.allCases.compactMap { position in
                guard let hotkey = self.snapHotkeys[position] else {
                    return nil
                }

                return (hotkey: hotkey, action: { WindowSnapper.snap(frontmostWindowTo: position) })
            }
            : []

        HotKeyManager.shared.setHotkeys(appHotkeys + snapHotkeys)
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

    private func persistSnapHotkeys() {
        do {
            UserDefaults.standard.set(try JSONEncoder().encode(snapHotkeys), forKey: Self.snapHotkeysKey)
        } catch {
            NSLog("Bifrost: could not save snap shortcuts — \(error.localizedDescription)")
        }
    }

    private func loadSnapHotkeys() {
        guard let data = UserDefaults.standard.data(forKey: Self.snapHotkeysKey) else {
            return
        }

        do {
            snapHotkeys = try JSONDecoder().decode([SnapPosition: Hotkey].self, from: data)
        } catch {
            NSLog("Bifrost: could not read snap shortcuts — \(error.localizedDescription)")
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
