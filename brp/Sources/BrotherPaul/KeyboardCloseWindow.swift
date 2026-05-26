import AppKit

/// NSWindow that closes itself on ⌘W. Brother Paul is an accessory app with
/// no main menu, so the system has nothing to bind ⌘W to by default. Apply
/// this subclass to any window we want keyboard-dismissable.
final class KeyboardCloseWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           event.charactersIgnoringModifiers == "w" {
            performClose(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}
