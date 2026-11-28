import AppKit
import Carbon.HIToolbox

/// Registers a global system hotkey via Carbon `RegisterEventHotKey` (works without Accessibility permission).
@MainActor
final class GlobalHotkeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private let onTrigger: @MainActor () -> Void

    init(onTrigger: @escaping @MainActor () -> Void) {
        self.onTrigger = onTrigger
    }

    /// Registers Option+Space (`⌥Space`) by default. Returns true if registration succeeded.
    @discardableResult
    func registerOptionSpace() -> Bool {
        unregister()
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return noErr }
                let manager = Unmanaged<GlobalHotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                Task { @MainActor in
                    manager.onTrigger()
                }
                return noErr
            },
            1,
            &eventType,
            selfPointer,
            &eventHandlerRef
        )
        guard handlerStatus == noErr else { return false }

        let hotKeyID = EventHotKeyID(signature: 0x4F52_4341, id: 1) // 'ORCA'
        let regStatus = RegisterEventHotKey(
            UInt32(kVK_Space),
            UInt32(optionKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        return regStatus == noErr
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }
}
