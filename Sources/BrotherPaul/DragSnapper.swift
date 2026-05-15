import AppKit

/// Global mouse monitor that snaps the focused window when the user drops a
/// window-drag at a screen edge or corner.
///
/// Heuristic: on left-mouse-down we capture the focused window's AX frame.
/// On left-mouse-up we compare against the current frame — if the window
/// moved more than `moveThreshold` pixels, we treat the drag as a window
/// drag and snap based on cursor position.
final class DragSnapper {

    private var monitor: Any?
    private var dragStartWindowOrigin: CGPoint?
    private var dragStartCursor: CGPoint?
    private let moveThreshold: CGFloat = 8

    func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseUp]
        ) { [weak self] event in
            guard let self = self else { return }
            switch event.type {
            case .leftMouseDown: self.onMouseDown()
            case .leftMouseUp:   self.onMouseUp()
            default: break
            }
        }
    }

    func uninstall() {
        if let m = monitor {
            NSEvent.removeMonitor(m)
            monitor = nil
        }
        dragStartWindowOrigin = nil
        dragStartCursor = nil
    }

    private func onMouseDown() {
        dragStartCursor = NSEvent.mouseLocation
        dragStartWindowOrigin = WindowSnapper.focusedWindowAXFrame()?.origin
    }

    private func onMouseUp() {
        defer {
            dragStartCursor = nil
            dragStartWindowOrigin = nil
        }
        guard let startOrigin = dragStartWindowOrigin,
              let endFrame = WindowSnapper.focusedWindowAXFrame() else { return }

        let dx = abs(endFrame.origin.x - startOrigin.x)
        let dy = abs(endFrame.origin.y - startOrigin.y)
        guard dx + dy >= moveThreshold else { return }  // not a window drag

        let cursor = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSPointInRect(cursor, $0.frame) })
                       ?? NSScreen.main,
              let zone = SnapZone.zoneForCursor(cursor, on: screen) else { return }

        DispatchQueue.main.async {
            WindowSnapper.snap(to: zone)
        }
    }
}
