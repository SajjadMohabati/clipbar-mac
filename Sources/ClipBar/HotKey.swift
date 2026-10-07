import AppKit
import Carbon.HIToolbox

/// A single system-wide hotkey registered through Carbon.
@MainActor
final class HotKey {
    static let shared = HotKey()

    private var handler: EventHandlerRef?
    private var ref: EventHotKeyRef?
    private var action: () -> Void = {}

    func install(_ action: @escaping () -> Void) {
        self.action = action
        guard handler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetEventDispatcherTarget(), { _, _, _ in
            MainActor.assumeIsolated { HotKey.shared.action() }
            return noErr
        }, 1, &spec, nil, &handler)
    }

    func register(_ shortcut: Shortcut) {
        unregister()
        let id = EventHotKeyID(signature: 0x434C_4942, id: 1)
        RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, id, GetEventDispatcherTarget(), 0, &ref)
    }

    func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
    }
}
