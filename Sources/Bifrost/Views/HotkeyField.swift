import AppKit
import Carbon.HIToolbox
import SwiftUI

/// A capsule that records a key combination while it has focus.
///
/// Escape cancels, Delete clears, and anything else is captured verbatim.
struct HotkeyField: View {
    let hotkey: Hotkey?
    let onChange: (Hotkey?) -> Void

    @State private var isRecording = false
    @State private var monitor: Any?
    @State private var isHovering = false

    var body: some View {
        Button(action: toggleRecording) {
            Text(label)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(foreground)
                .frame(minWidth: 62)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(background, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(.tint.opacity(isRecording ? 0.9 : 0), lineWidth: 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(isRecording ? "Press a key combination, or Escape to cancel" : "Click to record a shortcut")
        .onDisappear(perform: stopRecording)
    }

    private var label: String {
        if isRecording {
            return "Press keys…"
        }

        return hotkey?.displayString ?? "Record"
    }

    private var foreground: Color {
        if isRecording {
            return .primary
        }

        return hotkey == nil ? .secondary : .primary
    }

    private var background: some ShapeStyle {
        if isRecording {
            return AnyShapeStyle(.tint.opacity(0.15))
        }

        return AnyShapeStyle(Color.primary.opacity(isHovering ? 0.12 : 0.07))
    }

    // MARK: - Recording

    private func toggleRecording() {
        isRecording ? stopRecording() : startRecording()
    }

    private func startRecording() {
        guard !isRecording else {
            return
        }

        isRecording = true

        // Otherwise pressing a combination that is already registered would
        // launch that app instead of being recorded.
        HotKeyManager.shared.pause()

        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            guard isRecording else {
                return event
            }

            if event.type == .keyDown {
                handle(event)
            }

            return nil  // swallow the event either way
        }
    }

    private func stopRecording() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }

        monitor = nil

        guard isRecording else {
            return
        }

        isRecording = false
        HotKeyManager.shared.resume()
    }

    private func handle(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let bare = flags.isDisjoint(with: [.command, .option, .control, .shift])

        if bare {
            switch Int(event.keyCode) {
            case kVK_Escape:
                stopRecording()
                return
            case kVK_Delete, kVK_ForwardDelete:
                onChange(nil)
                stopRecording()
                return
            default:
                break
            }
        }

        let candidate = Hotkey(keyCode: event.keyCode, cocoaModifiers: flags)
        guard candidate.isValid else {
            // Shift alone (or no modifier) would capture ordinary typing.
            NSSound.beep()
            return
        }

        onChange(candidate)
        stopRecording()
    }
}
