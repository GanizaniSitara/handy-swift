import Cocoa

/// A key chord stored as Handy.NET's hotkey string ("Ctrl+Space", "Ctrl+Shift+D").
/// "Alt" is the Option key; "Cmd" is Command.
struct Shortcut: Equatable, CustomStringConvertible {
    var keyCode: Int64
    var modifiers: CGEventFlags

    static let modifierMask: CGEventFlags = [.maskControl, .maskAlternate, .maskShift, .maskCommand]
    static let dictationDefault = Shortcut(keyCode: 49, modifiers: [.maskControl])

    private static let modifierNames: [(CGEventFlags, String)] = [
        (.maskControl, "Ctrl"), (.maskAlternate, "Alt"), (.maskShift, "Shift"), (.maskCommand, "Cmd"),
    ]

    // US-layout virtual key codes for the keys a hotkey can sensibly use.
    private static let keyNames: [Int64: String] = {
        var m: [Int64: String] = [
            49: "Space", 36: "Enter", 48: "Tab", 51: "Backspace", 53: "Escape", 117: "Delete",
            123: "Left", 124: "Right", 125: "Down", 126: "Up", 115: "Home", 119: "End",
            116: "PageUp", 121: "PageDown", 50: "`", 27: "-", 24: "=", 33: "[", 30: "]",
            42: "\\", 41: ";", 39: "'", 43: ",", 47: ".", 44: "/",
        ]
        let letters: [(String, Int64)] = [
            ("A", 0), ("S", 1), ("D", 2), ("F", 3), ("H", 4), ("G", 5), ("Z", 6), ("X", 7), ("C", 8), ("V", 9),
            ("B", 11), ("Q", 12), ("W", 13), ("E", 14), ("R", 15), ("Y", 16), ("T", 17), ("O", 31), ("U", 32),
            ("I", 34), ("P", 35), ("L", 37), ("J", 38), ("K", 40), ("N", 45), ("M", 46),
        ]
        for (n, c) in letters { m[c] = n }
        let digits: [Int64] = [29, 18, 19, 20, 21, 23, 22, 26, 28, 25]  // 0…9
        for (i, c) in digits.enumerated() { m[c] = String(i) }
        let fkeys: [Int64] = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111]  // F1…F12
        for (i, c) in fkeys.enumerated() { m[c] = "F\(i + 1)" }
        return m
    }()

    var description: String {
        let mods = Self.modifierNames.filter { modifiers.contains($0.0) }.map(\.1)
        return (mods + [Self.keyNames[keyCode] ?? "Key\(keyCode)"]).joined(separator: "+")
    }

    /// Display form with Mac symbols, e.g. "⌃Space".
    var symbols: String {
        let sym: [(CGEventFlags, String)] = [(.maskControl, "⌃"), (.maskAlternate, "⌥"), (.maskShift, "⇧"), (.maskCommand, "⌘")]
        return sym.filter { modifiers.contains($0.0) }.map(\.1).joined() + (Self.keyNames[keyCode] ?? "Key\(keyCode)")
    }

    init(keyCode: Int64, modifiers: CGEventFlags) {
        self.keyCode = keyCode
        self.modifiers = modifiers.intersection(Self.modifierMask)
    }

    /// Parses "Ctrl+Shift+Space"; case-insensitive, accepts Control/Option/Alt/Command/Cmd.
    init?(_ text: String) {
        var mods: CGEventFlags = []
        var key: Int64?
        for part in text.split(separator: "+").map({ $0.trimmingCharacters(in: .whitespaces).lowercased() }) {
            switch part {
            case "ctrl", "control": mods.insert(.maskControl)
            case "alt", "option", "opt": mods.insert(.maskAlternate)
            case "shift": mods.insert(.maskShift)
            case "cmd", "command": mods.insert(.maskCommand)
            default:
                guard key == nil, let code = Self.keyNames.first(where: { $0.value.lowercased() == part })?.key else { return nil }
                key = code
            }
        }
        guard let key, !mods.isEmpty else { return nil }  // a bare key would fire on ordinary typing
        self.init(keyCode: key, modifiers: mods)
    }

    init?(event: NSEvent) {
        var mods: CGEventFlags = []
        if event.modifierFlags.contains(.control) { mods.insert(.maskControl) }
        if event.modifierFlags.contains(.option) { mods.insert(.maskAlternate) }
        if event.modifierFlags.contains(.shift) { mods.insert(.maskShift) }
        if event.modifierFlags.contains(.command) { mods.insert(.maskCommand) }
        let code = Int64(event.keyCode)
        guard !mods.isEmpty, Self.keyNames[code] != nil else { return nil }
        self.init(keyCode: code, modifiers: mods)
    }
}
