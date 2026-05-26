import AppKit
import ApplicationServices

enum WindowSnapper {

    // MARK: - Public API

    @discardableResult
    static func snap(to zone: SnapZone) -> Bool {
        guard ensureAccessibility() else { return false }

        guard let (appElement, window) = focusedAppAndWindow() else {
            NSLog("BrotherPaul: no focused window to snap")
            return false
        }

        let cursor = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSPointInRect(cursor, $0.frame) }
                  ?? currentScreen(forWindow: window)
                  ?? NSScreen.main
        guard let screen = screen else { return false }

        let target = zone.frame(in: screen)
        let _ = appElement // kept around so the app reference isn't released early
        return setFrame(target, on: window)
    }

    /// AX-space frame (top-left origin) of the currently focused window.
    static func focusedWindowAXFrame() -> CGRect? {
        guard let (_, window) = focusedAppAndWindow() else { return nil }
        return axFrame(of: window)
    }

    // MARK: - Permission

    @discardableResult
    static func ensureAccessibility(prompt: Bool = false) -> Bool {
        if AXIsProcessTrusted() { return true }
        if prompt {
            let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            let opts: CFDictionary = [key: true] as CFDictionary
            return AXIsProcessTrustedWithOptions(opts)
        }
        return false
    }

    // MARK: - Internals

    private static func focusedAppAndWindow() -> (AXUIElement, AXUIElement)? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let appEl = AXUIElementCreateApplication(app.processIdentifier)

        var ref: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(appEl, kAXFocusedWindowAttribute as CFString, &ref)
        guard status == .success, let cf = ref else { return nil }

        let window = cf as! AXUIElement
        return (appEl, window)
    }

    private static func setFrame(_ frame: CGRect, on window: AXUIElement) -> Bool {
        // Convert from Cocoa screen coords (origin = bottom-left of primary screen,
        // y grows up) to AX coords (origin = top-left of primary screen, y grows down).
        guard let primary = NSScreen.screens.first else { return false }
        let primaryHeight = primary.frame.height
        var pos = CGPoint(x: frame.origin.x, y: primaryHeight - frame.origin.y - frame.size.height)
        var size = frame.size

        guard
            let posValue = AXValueCreate(.cgPoint, &pos),
            let sizeValue = AXValueCreate(.cgSize, &size)
        else { return false }

        // Set size first (some apps clamp position to fit), then position, then size again
        // to overcome cases where the app refuses to resize until repositioned.
        _ = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        _ = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, posValue)
        _ = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        return true
    }

    private static func axFrame(of window: AXUIElement) -> CGRect? {
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &posRef) == .success,
            AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef) == .success,
            let posV = posRef, let sizeV = sizeRef
        else { return nil }

        var pos = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(posV as! AXValue, .cgPoint, &pos)
        AXValueGetValue(sizeV as! AXValue, .cgSize, &size)
        return CGRect(origin: pos, size: size)
    }

    private static func currentScreen(forWindow window: AXUIElement) -> NSScreen? {
        guard let axRect = axFrame(of: window),
              let primary = NSScreen.screens.first else { return nil }
        // Convert AX top-left to Cocoa bottom-left to find the containing screen.
        let cocoaY = primary.frame.height - axRect.origin.y - axRect.size.height
        let center = CGPoint(x: axRect.midX, y: cocoaY + axRect.size.height / 2)
        return NSScreen.screens.first { NSPointInRect(center, $0.frame) }
    }
}
