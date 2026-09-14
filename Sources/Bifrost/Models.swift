import AppKit
import Carbon.HIToolbox

/// A key combination expressed in Carbon terms, which is what
/// `RegisterEventHotKey` speaks natively.
struct Hotkey: Codable, Equatable, Hashable {
    /// Virtual key code (`kVK_*`), layout independent.
    var keyCode: UInt32
    /// Carbon modifier mask (`cmdKey`, `optionKey`, `controlKey`, `shiftKey`).
    var modifiers: UInt32

    /// `⌃⌥⇧⌘K`-style label, in the order the system menus use.
    var displayString: String {
        var result = ""
        if modifiers & UInt32(controlKey) != 0 { result += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { result += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { result += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { result += "⌘" }
        return result + KeyNames.display(for: keyCode)
    }

    /// A hotkey with no non-shift modifier would swallow ordinary typing.
    var isValid: Bool {
        modifiers & UInt32(cmdKey | optionKey | controlKey) != 0
    }

    init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    init(keyCode: UInt16, cocoaModifiers: NSEvent.ModifierFlags) {
        var mask: UInt32 = 0
        if cocoaModifiers.contains(.command) { mask |= UInt32(cmdKey) }
        if cocoaModifiers.contains(.option) { mask |= UInt32(optionKey) }
        if cocoaModifiers.contains(.control) { mask |= UInt32(controlKey) }
        if cocoaModifiers.contains(.shift) { mask |= UInt32(shiftKey) }
        self.keyCode = UInt32(keyCode)
        self.modifiers = mask
    }
}

/// One application the user has added to the menu, plus its optional hotkey.
struct AppEntry: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var bundleIdentifier: String
    var path: String
    var hotkey: Hotkey?
    /// Opt-in: pressing the hotkey again while this app is frontmost moves to
    /// its next window. Requires the Accessibility permission.
    var cyclesWindows: Bool

    init(
        id: UUID = UUID(),
        name: String,
        bundleIdentifier: String,
        path: String,
        hotkey: Hotkey? = nil,
        cyclesWindows: Bool = false
    ) {
        self.id = id
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.path = path
        self.hotkey = hotkey
        self.cyclesWindows = cyclesWindows
    }

    /// Hand-rolled so entries saved before window cycling existed still load.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        bundleIdentifier = try container.decode(String.self, forKey: .bundleIdentifier)
        path = try container.decode(String.self, forKey: .path)
        hotkey = try container.decodeIfPresent(Hotkey.self, forKey: .hotkey)
        cyclesWindows = try container.decodeIfPresent(Bool.self, forKey: .cyclesWindows) ?? false
    }

    var url: URL { URL(fileURLWithPath: path) }

    /// The app may have been moved, renamed or uninstalled since it was added.
    var existsOnDisk: Bool { FileManager.default.fileExists(atPath: path) }

    var icon: NSImage {
        guard existsOnDisk else {
            return NSImage(systemSymbolName: "questionmark.app", accessibilityDescription: nil) ?? NSImage()
        }
        return NSWorkspace.shared.icon(forFile: path)
    }

    init?(url: URL) {
        guard let bundle = Bundle(url: url), let identifier = bundle.bundleIdentifier else { return nil }
        let name = FileManager.default.displayName(atPath: url.path)
        self.init(
            name: name.hasSuffix(".app") ? String(name.dropLast(4)) : name,
            bundleIdentifier: identifier,
            path: url.path
        )
    }
}
