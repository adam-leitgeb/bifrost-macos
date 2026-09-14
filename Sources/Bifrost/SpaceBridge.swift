import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

/// Thin wrapper over the private window-server calls needed to see and reach
/// windows on other desktops.
///
/// The Accessibility API only ever reports windows on the *current* Space, so
/// there is no public way to enumerate — let alone raise — a window sitting on
/// another desktop. These symbols are what window managers such as AltTab use.
///
/// Every symbol is looked up at runtime rather than linked, so a macOS release
/// that removes one degrades to current-desktop cycling instead of failing to
/// launch.
@MainActor
enum SpaceBridge {
    private typealias MainConnectionFn = @convention(c) () -> Int32
    private typealias SpacesForWindowsFn = @convention(c) (Int32, Int32, CFArray) -> Unmanaged<CFArray>?
    private typealias ManagedDisplaySpacesFn = @convention(c) (Int32) -> Unmanaged<CFArray>?
    private typealias SetCurrentSpaceFn = @convention(c) (Int32, CFString, UInt64) -> Void
    private typealias WindowIDForElementFn = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError

    /// Every Space, not just the visible one.
    private static let allSpacesMask: Int32 = 0x7

    private static func lookUp<T>(_ name: String, as type: T.Type) -> T? {
        // RTLD_DEFAULT — the symbols live in already-loaded system frameworks.
        guard let pointer = dlsym(UnsafeMutableRawPointer(bitPattern: -2), name) else { return nil }
        return unsafeBitCast(pointer, to: type)
    }

    private static let mainConnection = lookUp("CGSMainConnectionID", as: MainConnectionFn.self)
    private static let spacesForWindows = lookUp("CGSCopySpacesForWindows", as: SpacesForWindowsFn.self)
    private static let managedDisplaySpaces = lookUp("CGSCopyManagedDisplaySpaces", as: ManagedDisplaySpacesFn.self)
    private static let setCurrentSpace = lookUp("CGSManagedDisplaySetCurrentSpace", as: SetCurrentSpaceFn.self)
    private static let windowIDForElement = lookUp("_AXUIElementGetWindow", as: WindowIDForElementFn.self)

    /// False when a macOS release has moved or removed any of the symbols.
    static var isAvailable: Bool {
        mainConnection != nil && spacesForWindows != nil
            && managedDisplaySpaces != nil && setCurrentSpace != nil
            && windowIDForElement != nil
    }

    private static var connection: Int32? { mainConnection?() }

    /// The Spaces a window belongs to. Empty for the offscreen scratch buffers
    /// that apps like Xcode and Chromium keep around, which is what makes this
    /// a reliable way to tell a real window from an artefact.
    static func spaces(forWindow windowID: CGWindowID) -> [Int] {
        guard let connection, let spacesForWindows else { return [] }
        let ids = [windowID] as CFArray
        guard let result = spacesForWindows(connection, allSpacesMask, ids)?.takeRetainedValue() else { return [] }
        return (result as? [Int]) ?? []
    }

    struct Display {
        let identifier: String
        let currentSpace: Int
        let spaces: [Int]
    }

    static func displays() -> [Display] {
        guard let connection, let managedDisplaySpaces,
              let raw = managedDisplaySpaces(connection)?.takeRetainedValue() as? [[String: Any]]
        else { return [] }

        return raw.compactMap { entry in
            guard let identifier = entry["Display Identifier"] as? String else { return nil }
            let spaces = (entry["Spaces"] as? [[String: Any]])?.compactMap { $0["ManagedSpaceID"] as? Int } ?? []
            let current = (entry["Current Space"] as? [String: Any])?["ManagedSpaceID"] as? Int ?? -1
            return Display(identifier: identifier, currentSpace: current, spaces: spaces)
        }
    }

    /// The Spaces currently showing, one per display.
    static func activeSpaces() -> Set<Int> {
        Set(displays().map(\.currentSpace))
    }

    /// Whether `space` is already the one showing on its display.
    static func isVisible(space: Int) -> Bool {
        activeSpaces().contains(space)
    }

    /// Switches the display owning `space` over to it. Returns false when no
    /// display claims that Space.
    @discardableResult
    static func show(space: Int) -> Bool {
        guard let connection, let setCurrentSpace,
              let display = displays().first(where: { $0.spaces.contains(space) })
        else { return false }

        setCurrentSpace(connection, display.identifier as CFString, UInt64(space))
        return true
    }

    /// The window-server id behind an accessibility element, so the two views
    /// of a window can be matched up.
    static func windowID(of element: AXUIElement) -> CGWindowID? {
        guard let windowIDForElement else { return nil }
        var id: CGWindowID = 0
        guard windowIDForElement(element, &id) == .success, id != 0 else { return nil }
        return id
    }
}
