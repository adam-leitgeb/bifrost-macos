import SwiftUI

struct ContentView: View {
    @Environment(AppStore.self) private var store
    @Environment(Updater.self) private var updater
    @State private var conflictMessage: String?
    @State private var listHeight: CGFloat = 0

    private static let maxListHeight: CGFloat = 340
    @State private var isTrusted = WindowCycler.isTrusted

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            entryList

            if !hasAddedApps {
                Divider()
                emptyState
            }

            Divider()
            WindowSnappingSection(onToggle: setSnapsWindows) { hotkey, position in
                assign(hotkey, to: position)
            }

            if let conflictMessage {
                Divider()
                notice(conflictMessage, systemImage: "exclamationmark.triangle.fill")
            }

            if needsAccessibility {
                Divider()
                accessibilityNotice
            }

            Divider()
            footer
        }
        .frame(width: 360)
        .onAppear { isTrusted = WindowCycler.isTrusted }
    }

    private var hasAddedApps: Bool {
        store.entries.contains(where: \.isRemovable)
    }

    private var needsAccessibility: Bool {
        !isTrusted && (store.cyclesWindows || store.snapsWindows)
    }

    private var accessibilityFeatures: String {
        switch (store.cyclesWindows, store.snapsWindows) {
        case (true, true):
            "Window cycling and snapping need"
        case (false, true):
            "Window snapping needs"
        default:
            "Window cycling needs"
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack {
            Text("Bifrost")
                .font(.headline)
            Spacer()
            Text("\(store.entries.count)")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 24))
                .foregroundStyle(.tertiary)
            Text("Add your apps")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("Click Add App…, then Record to assign a shortcut.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.vertical, 28)
    }

    private var entryList: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(store.entries.filter { !$0.isRemovable }, content: row)

                if hasAddedApps {
                    Divider()
                        .padding(.vertical, 4)
                }

                ForEach(store.entries.filter(\.isRemovable), content: row)
            }
            .padding(.vertical, 4)
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(key: ListHeightKey.self, value: proxy.size.height)
                }
            )
        }
        // A ScrollView has no ideal height of its own. The menu bar window
        // sizes itself to fit its content, so without a definite height here
        // the list collapses to zero and the rows are clipped away entirely.
        // Measure the rows and pin the scroll view to that, capped so that
        // long lists scroll instead of growing without bound.
        .frame(height: min(max(listHeight, 1), Self.maxListHeight))
        .scrollBounceBehavior(.basedOnSize)
        .onPreferenceChange(ListHeightKey.self) { height in
            Task { @MainActor in listHeight = height }
        }
    }

    private func row(for entry: AppEntry) -> some View {
        EntryRow(entry: entry) { hotkey in
            assign(hotkey, to: entry)
        } onClear: {
            assign(nil, to: entry)
        } onRemove: {
            store.remove(entry)
        }
    }

    private var accessibilityNotice: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.fill")
                .foregroundStyle(.secondary)
            Text("\(accessibilityFeatures) Accessibility access.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Button("Open Settings") {
                WindowCycler.openAccessibilitySettings()
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private func notice(_ message: String, systemImage: String) -> some View {
        Label(message, systemImage: systemImage)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footer: some View {
        VStack(spacing: 0) {
            cyclingToggle
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

            Divider()
            UpdatesSection()
            Divider()

            HStack {
                Button("Add App…") {
                    AppPicker.present { urls in store.add(urls: urls) }
                }
                Spacer()
                Button("Check for Updates…") {
                    updater.checkForUpdates()
                }
                .disabled(!updater.canCheckForUpdates)
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q")
            }
            .controlSize(.small)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    private var cyclingToggle: some View {
        SettingToggle(
            title: "Cycle windows on repeated press",
            subtitle: "Requires Accessibility permission",
            isOn: store.cyclesWindows,
            onChange: setCyclesWindows
        )
    }

    // MARK: - Actions

    private func assign(_ hotkey: Hotkey?, to entry: AppEntry) {
        guard canAssign(hotkey, to: .app(entry.id)) else {
            return
        }

        store.setHotkey(hotkey, for: entry)
    }

    private func assign(_ hotkey: Hotkey?, to position: SnapPosition) {
        guard canAssign(hotkey, to: .snap(position)) else {
            return
        }

        store.setSnapHotkey(hotkey, for: position)
    }

    private func canAssign(_ hotkey: Hotkey?, to owner: ShortcutOwner) -> Bool {
        if let hotkey, let conflict = store.conflict(for: hotkey, excluding: owner) {
            conflictMessage = "\(hotkey.displayString) is already used by \(conflict)."
            return false
        }

        conflictMessage = nil
        return true
    }

    private func setCyclesWindows(_ enabled: Bool) {
        store.setCyclesWindows(enabled)
        requestTrustIfNeeded(enabled)
    }

    private func setSnapsWindows(_ enabled: Bool) {
        store.setSnapsWindows(enabled)
        requestTrustIfNeeded(enabled)
    }

    private func requestTrustIfNeeded(_ enabled: Bool) {
        // Ask for the permission at the moment it first becomes relevant,
        // rather than on launch.
        if enabled && !WindowCycler.isTrusted {
            WindowCycler.requestTrust()
        }

        isTrusted = WindowCycler.isTrusted
    }
}

/// One row: icon, name, shortcut recorder, and a hover button that clears the
/// shortcut, or removes the app once there is no shortcut left to clear.
private struct EntryRow: View {
    let entry: AppEntry
    let onHotkeyChange: (Hotkey?) -> Void
    let onClear: () -> Void
    let onRemove: () -> Void

    @State private var isHovering = false
    @State private var isRemovalArmed = true

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: entry.icon)
                .resizable()
                .frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: 0) {
                Text(entry.name)
                    .font(.system(size: 13))
                    .lineLimit(1)
                if !entry.existsOnDisk {
                    Text("Not installed")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 4)

            HotkeyField(hotkey: entry.hotkey, onChange: onHotkeyChange)

            trailingButton
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(isHovering ? Color.primary.opacity(0.06) : .clear)
        .onHover(perform: didHover)
    }

    @ViewBuilder
    private var trailingButton: some View {
        if entry.hotkey != nil {
            Button(action: didTapClear) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .opacity(isHovering ? 1 : 0)
            .help("Clear shortcut for \(entry.name)")
        } else {
            Button(action: onRemove) {
                Image(systemName: "trash.circle.fill")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .opacity(isHovering && canRemove ? 1 : 0)
            .disabled(!canRemove)
            .help("Remove \(entry.name)")
        }
    }

    private var canRemove: Bool {
        entry.isRemovable && isRemovalArmed
    }

    // MARK: - Actions

    private func didHover(_ hovering: Bool) {
        isHovering = hovering

        if !hovering {
            isRemovalArmed = true
        }
    }

    // The trash button appears in the clear button's place, so a double-click
    // meant to clear would otherwise remove the app too.
    private func didTapClear() {
        isRemovalArmed = false
        onClear()
    }
}

/// Carries the measured height of the entry rows up to the scroll view.
private struct ListHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
