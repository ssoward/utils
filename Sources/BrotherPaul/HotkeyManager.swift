import AppKit
import Carbon

/// Registers global Ctrl+Opt hotkeys that snap the focused window.
final class HotkeyManager {

    private struct Binding {
        let keyCode: UInt32
        let zone: SnapZone
    }

    // Ctrl+Option
    private let modifiers: UInt32 = UInt32(controlKey | optionKey)
    private let signature: OSType = 0x42504850 // 'BPHP'

    private var hotKeyRefs: [EventHotKeyRef] = []
    private var bindings: [UInt32: Binding] = [:]
    private var eventHandlerRef: EventHandlerRef?
    private var installed = false

    func install() {
        guard !installed else { return }
        installed = true

        let allBindings: [Binding] = [
            Binding(keyCode: UInt32(kVK_LeftArrow),  zone: .leftHalf),
            Binding(keyCode: UInt32(kVK_RightArrow), zone: .rightHalf),
            Binding(keyCode: UInt32(kVK_UpArrow),    zone: .topHalf),
            Binding(keyCode: UInt32(kVK_DownArrow),  zone: .bottomHalf),
            Binding(keyCode: UInt32(kVK_ANSI_U),     zone: .topLeftQuarter),
            Binding(keyCode: UInt32(kVK_ANSI_I),     zone: .topRightQuarter),
            Binding(keyCode: UInt32(kVK_ANSI_J),     zone: .bottomLeftQuarter),
            Binding(keyCode: UInt32(kVK_ANSI_K),     zone: .bottomRightQuarter),
            Binding(keyCode: UInt32(kVK_Return),     zone: .maximize),
            Binding(keyCode: UInt32(kVK_ANSI_C),     zone: .center),
        ]

        installEventHandler()

        for (index, binding) in allBindings.enumerated() {
            let id = UInt32(index + 1)
            bindings[id] = binding
            register(binding: binding, id: id)
        }
    }

    func uninstall() {
        for ref in hotKeyRefs {
            UnregisterEventHotKey(ref)
        }
        hotKeyRefs.removeAll()
        bindings.removeAll()
        if let handler = eventHandlerRef {
            RemoveEventHandler(handler)
            eventHandlerRef = nil
        }
        installed = false
    }

    fileprivate func handleHotkey(id: UInt32) {
        guard let binding = bindings[id] else { return }
        DispatchQueue.main.async {
            WindowSnapper.snap(to: binding.zone)
        }
    }

    // MARK: - Carbon plumbing

    private func register(binding: Binding, id: UInt32) {
        let hotKeyID = EventHotKeyID(signature: signature, id: id)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            binding.keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        if status == noErr, let r = ref {
            hotKeyRefs.append(r)
        } else {
            NSLog("BrotherPaul: RegisterEventHotKey failed (key=%u status=%d)", binding.keyCode, Int(status))
        }
    }

    private func installEventHandler() {
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            hotkeyEventHandlerCallback,
            1,
            &spec,
            selfPtr,
            &eventHandlerRef
        )
    }
}

/// C callback — extracts the hotkey ID and forwards to the HotkeyManager
/// instance passed via userData.
private let hotkeyEventHandlerCallback: EventHandlerUPP = { _, eventRef, userData in
    guard let eventRef = eventRef, let userData = userData else { return noErr }

    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        eventRef,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr else { return status }

    let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
    manager.handleHotkey(id: hotKeyID.id)
    return noErr
}
