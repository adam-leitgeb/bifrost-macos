import AppKit
import ApplicationServices

/// Moves the frontmost window to half of its screen, like the built-in
/// fn-⌃-arrow shortcuts that third-party keyboards have no fn key for.
@MainActor
enum WindowSnapper {
    private static let messagingTimeout: Float = 0.5

    static func snap(frontmostWindowTo position: SnapPosition) {
        guard WindowCycler.isTrusted,
              let app = NSWorkspace.shared.frontmostApplication,
              let window = focusedWindow(of: app),
              let current = frame(of: window),
              let screen = screen(containing: current)
        else {
            NSSound.beep()
            return
        }

        let target = position.frame(in: accessibilityFrame(of: screen.visibleFrame))

        // Resizing first keeps a window moving to a smaller screen from being
        // clamped at its old size, and resizing again afterwards catches apps
        // that constrain size by position.
        setSize(target.size, of: window)
        setPosition(target.origin, of: window)
        setSize(target.size, of: window)
    }

    // MARK: - Screens

    /// AppKit measures screens from the bottom-left corner of the primary
    /// screen; the accessibility API measures windows from its top-left.
    private static func accessibilityFrame(of rect: CGRect) -> CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    private static func screen(containing window: CGRect) -> NSScreen? {
        let overlaps = NSScreen.screens.map { screen in
            let intersection = accessibilityFrame(of: screen.frame).intersection(window)
            return (screen: screen, area: intersection.isNull ? 0 : intersection.width * intersection.height)
        }

        guard let best = overlaps.max(by: { $0.area < $1.area }), best.area > 0 else {
            return NSScreen.main
        }

        return best.screen
    }

    // MARK: - Accessibility helpers

    private static func focusedWindow(of app: NSRunningApplication) -> AXUIElement? {
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(element, messagingTimeout)

        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXFocusedWindowAttribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXUIElementGetTypeID()
        else {
            return nil
        }

        return (value as! AXUIElement)
    }

    private static func frame(of window: AXUIElement) -> CGRect? {
        guard let positionValue = axValue(of: window, kAXPositionAttribute),
              let sizeValue = axValue(of: window, kAXSizeAttribute)
        else {
            return nil
        }

        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue, .cgPoint, &position),
              AXValueGetValue(sizeValue, .cgSize, &size)
        else {
            return nil
        }

        return CGRect(origin: position, size: size)
    }

    private static func axValue(of element: AXUIElement, _ name: String) -> AXValue? {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &raw) == .success,
              let raw,
              CFGetTypeID(raw) == AXValueGetTypeID()
        else {
            return nil
        }

        return (raw as! AXValue)
    }

    private static func setPosition(_ position: CGPoint, of window: AXUIElement) {
        var position = position
        guard let value = AXValueCreate(.cgPoint, &position) else {
            return
        }

        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value)
    }

    private static func setSize(_ size: CGSize, of window: AXUIElement) {
        var size = size
        guard let value = AXValueCreate(.cgSize, &size) else {
            return
        }

        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, value)
    }
}
