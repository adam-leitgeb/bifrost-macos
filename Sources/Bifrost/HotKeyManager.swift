import Carbon.HIToolbox
import Foundation

/// Registers global hotkeys through Carbon's `RegisterEventHotKey`.
///
/// Carbon hotkeys are handled by the window server, so they fire no matter
/// which app is frontmost and — unlike a `CGEventTap` — they need no
/// Accessibility permission.
@MainActor
final class HotKeyManager {
    static let shared = HotKeyManager()

    /// Four-character signature identifying hotkeys owned by this app: 'BFST'.
    private static let signature: OSType = 0x4246_5354

    private struct Registration {
        let ref: EventHotKeyRef
        let action: () -> Void
    }

    private var registrations: [UInt32: Registration] = [:]
    private var desired: [(hotkey: Hotkey, action: () -> Void)] = []
    private var nextID: UInt32 = 1
    private var eventHandler: EventHandlerRef?
    private var isPaused = false

    private init() {}

    /// Replaces every registered hotkey with `items`. Cheap enough to call on
    /// any change — there are only ever a handful of them.
    func setHotkeys(_ items: [(hotkey: Hotkey, action: () -> Void)]) {
        desired = items
        reload()
    }

    /// Suspends all hotkeys, so recording a new one cannot trigger an existing
    /// one. Balanced by `resume()`.
    func pause() {
        guard !isPaused else {
            return
        }

        isPaused = true
        unregisterAll()
    }

    func resume() {
        guard isPaused else {
            return
        }

        isPaused = false
        reload()
    }

    // MARK: - Registration

    private func reload() {
        unregisterAll()

        guard !isPaused else {
            return
        }

        installEventHandlerIfNeeded()
        for item in desired where item.hotkey.isValid {
            register(item.hotkey, action: item.action)
        }
    }

    private func register(_ hotkey: Hotkey, action: @escaping () -> Void) {
        let id = nextID
        nextID &+= 1

        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            hotkey.keyCode,
            hotkey.modifiers,
            EventHotKeyID(signature: Self.signature, id: id),
            GetEventDispatcherTarget(),
            0,
            &ref
        )

        // A non-zero status usually means another app already owns the
        // combination; skip it rather than failing the whole reload.
        guard status == noErr, let ref else {
            return
        }

        registrations[id] = Registration(ref: ref, action: action)
    }

    private func unregisterAll() {
        for registration in registrations.values {
            UnregisterEventHotKey(registration.ref)
        }
        registrations.removeAll()
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandler == nil else {
            return
        }

        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        // The callback is a C function pointer, so it cannot capture context —
        // it reaches back through the singleton instead. Carbon dispatches it
        // on the main run loop, which is what makes `assumeIsolated` sound.
        InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, event, _ -> OSStatus in
                guard let event else {
                    return OSStatus(eventNotHandledErr)
                }

                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard status == noErr, hotKeyID.signature == HotKeyManager.signature else {
                    return OSStatus(eventNotHandledErr)
                }

                MainActor.assumeIsolated {
                    HotKeyManager.shared.handle(id: hotKeyID.id)
                }
                return noErr
            },
            1,
            &spec,
            nil,
            &eventHandler
        )
    }

    private func handle(id: UInt32) {
        registrations[id]?.action()
    }
}
