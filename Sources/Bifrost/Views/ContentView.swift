import SwiftUI

struct ContentView: View {
    @Environment(AppStore.self) private var store
    @State private var conflictMessage: String?
    @State private var listHeight: CGFloat = 0

    private static let maxListHeight: CGFloat = 340
    @State private var isTrusted = WindowCycler.isTrusted

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if store.entries.isEmpty {
                emptyState
            } else {
                entryList
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

    /// Cycling is switched on somewhere, but the permission it needs is not
    /// granted — without this the feature would just silently do nothing.
    private var needsAccessibility: Bool {
        !isTrusted && store.entries.contains(where: \.cyclesWindows)
    }

    // MARK: - Sections

    private var header: some View {
        HStack {
            Text("Bifrost")
                .font(.headline)
            Spacer()
            Text(store.entries.isEmpty ? "" : "\(store.entries.count)")
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
            Text("No apps yet")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("Add an app, then click Record to assign a shortcut.")
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
                ForEach(store.entries) { entry in
                    EntryRow(entry: entry) { hotkey in
                        assign(hotkey, to: entry)
                    } onToggleCycling: {
                        toggleCycling(for: entry)
                    } onRemove: {
                        store.remove(entry)
                    }
                }
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

    private var accessibilityNotice: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.fill")
                .foregroundStyle(.secondary)
            Text("Window cycling needs Accessibility access.")
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
        HStack {
            Button("Add App…") {
                AppPicker.present { urls in store.add(urls: urls) }
            }
            Spacer()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .controlSize(.small)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Actions

    private func assign(_ hotkey: Hotkey?, to entry: AppEntry) {
        if let hotkey, let owner = store.conflict(for: hotkey, excluding: entry) {
            conflictMessage = "\(hotkey.displayString) is already used by \(owner.name)."
            return
        }
        conflictMessage = nil
        store.setHotkey(hotkey, for: entry)
    }

    private func toggleCycling(for entry: AppEntry) {
        let enabling = !entry.cyclesWindows
        store.setCyclesWindows(enabling, for: entry)

        // Ask for the permission at the moment it first becomes relevant,
        // rather than on launch.
        if enabling && !WindowCycler.isTrusted {
            WindowCycler.requestTrust()
        }
        isTrusted = WindowCycler.isTrusted
    }
}

/// One row: icon, name, window-cycling toggle, shortcut recorder, and a remove
/// button that appears on hover.
private struct EntryRow: View {
    let entry: AppEntry
    let onHotkeyChange: (Hotkey?) -> Void
    let onToggleCycling: () -> Void
    let onRemove: () -> Void

    @State private var isHovering = false

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

            Button(action: onToggleCycling) {
                Image(systemName: "macwindow.on.rectangle")
                    .font(.system(size: 12))
                    .foregroundStyle(entry.cyclesWindows ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                    .frame(width: 20, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(entry.cyclesWindows
                  ? "Repeat the shortcut to cycle \(entry.name) windows"
                  : "Cycle windows on repeat press (needs Accessibility)")

            HotkeyField(hotkey: entry.hotkey, onChange: onHotkeyChange)

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .opacity(isHovering ? 1 : 0)
            .help("Remove \(entry.name)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(isHovering ? Color.primary.opacity(0.06) : .clear)
        .onHover { isHovering = $0 }
    }
}

/// Carries the measured height of the entry rows up to the scroll view.
private struct ListHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
