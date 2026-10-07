import AppKit
import Carbon.HIToolbox

struct Shortcut: Equatable {
    var keyCode: UInt32
    /// Carbon modifier flags (`cmdKey`, `shiftKey`, …).
    var modifiers: UInt32

    /// Builds a shortcut from a key press. Requires ⌘, ⌥ or ⌃ so plain typing is never hijacked.
    init?(event: NSEvent) {
        let flags = event.modifierFlags
        var modifiers: UInt32 = 0
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        guard modifiers != 0 else { return nil }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        self.init(keyCode: UInt32(event.keyCode), modifiers: modifiers)
    }

    init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    var display: String {
        let symbols = [(controlKey, "⌃"), (optionKey, "⌥"), (shiftKey, "⇧"), (cmdKey, "⌘")]
        return symbols.filter { modifiers & UInt32($0.0) != 0 }.map(\.1).joined() + Self.name(of: Int(keyCode))
    }

    private static func name(of code: Int) -> String {
        // ANSI key codes 0x00–0x2F in order.
        let ansi = Array("ASDFHGZXCV§BQWERYT123465=97-80]OU[IP↩LJ'K;\\,/NM.")
        if code < ansi.count { return String(ansi[code]) }
        let special = [
            kVK_Tab: "⇥", kVK_Space: "Space", kVK_ANSI_Grave: "`", kVK_Delete: "⌫",
            kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_DownArrow: "↓", kVK_UpArrow: "↑",
            kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
            kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        ]
        return special[code] ?? "Key \(code)"
    }
}

@MainActor
final class Settings: ObservableObject {
    static let shared = Settings()

    private let defaults = UserDefaults.standard

    @Published var keepDays: Int { didSet { defaults.set(keepDays, forKey: "clearAfterDays") } }
    @Published var maxItems: Int { didSet { defaults.set(maxItems, forKey: "clearAfterCount") } }
    @Published var cleanPinned: Bool { didSet { defaults.set(cleanPinned, forKey: "clearPinned") } }
    @Published var autoPaste: Bool { didSet { defaults.set(autoPaste, forKey: "autoPaste") } }
    @Published var skipSensitive: Bool { didSet { defaults.set(skipSensitive, forKey: "skipSensitive") } }
    @Published var captureScreenshots: Bool { didSet { defaults.set(captureScreenshots, forKey: "captureScreenshots") } }
    @Published var copyScreenshots: Bool { didSet { defaults.set(copyScreenshots, forKey: "copyScreenshots") } }
    @Published var shortcut: Shortcut {
        didSet {
            defaults.set(Int(shortcut.keyCode), forKey: "shortcutKeyCode")
            defaults.set(Int(shortcut.modifiers), forKey: "shortcutModifiers")
        }
    }

    private init() {
        let defaults = UserDefaults.standard
        defaults.register(defaults: [
            "clearAfterDays": 30,
            "clearAfterCount": 500,
            "clearPinned": false,
            "autoPaste": true,
            "skipSensitive": true,
            "captureScreenshots": true,
            "copyScreenshots": true,
            "shortcutKeyCode": kVK_ANSI_V,
            "shortcutModifiers": cmdKey | shiftKey,
        ])
        keepDays = defaults.integer(forKey: "clearAfterDays")
        maxItems = defaults.integer(forKey: "clearAfterCount")
        cleanPinned = defaults.bool(forKey: "clearPinned")
        autoPaste = defaults.bool(forKey: "autoPaste")
        skipSensitive = defaults.bool(forKey: "skipSensitive")
        captureScreenshots = defaults.bool(forKey: "captureScreenshots")
        copyScreenshots = defaults.bool(forKey: "copyScreenshots")
        shortcut = Shortcut(
            keyCode: UInt32(defaults.integer(forKey: "shortcutKeyCode")),
            modifiers: UInt32(defaults.integer(forKey: "shortcutModifiers"))
        )
    }
}
