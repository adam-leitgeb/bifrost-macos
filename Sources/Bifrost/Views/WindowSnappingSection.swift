import SwiftUI

struct WindowSnappingSection: View {
    @Environment(AppStore.self) private var store

    let onToggle: (Bool) -> Void
    let onHotkeyChange: (Hotkey?, SnapPosition) -> Void

    var body: some View {
        VStack(spacing: 0) {
            SettingToggle(
                title: "Snap windows to screen halves",
                subtitle: "Requires Accessibility permission",
                isOn: store.snapsWindows,
                onChange: onToggle
            )
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            if store.snapsWindows {
                ForEach(SnapPosition.allCases) { position in
                    SnapRow(position: position, hotkey: store.snapHotkeys[position]) { hotkey in
                        onHotkeyChange(hotkey, position)
                    }
                }
                .padding(.bottom, 4)
            }
        }
    }
}

private struct SnapRow: View {
    let position: SnapPosition
    let hotkey: Hotkey?
    let onHotkeyChange: (Hotkey?) -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: position.systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 18, height: 18)

            Text(position.title)
                .font(.system(size: 13))
                .lineLimit(1)

            Spacer(minLength: 4)

            HotkeyField(hotkey: hotkey, onChange: onHotkeyChange)

            Button {
                onHotkeyChange(nil)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .opacity(isHovering && hotkey != nil ? 1 : 0)
            .disabled(hotkey == nil)
            .help("Clear shortcut for \(position.title)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(isHovering ? Color.primary.opacity(0.06) : .clear)
        .onHover { isHovering = $0 }
    }
}
