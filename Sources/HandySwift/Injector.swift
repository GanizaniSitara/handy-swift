import Cocoa

/// Types text as Unicode key events — no Cmd+V, no synthetic modifiers. Every event carries
/// empty flags so a physically held modifier cannot turn a character into a shortcut.
enum Injector {
    enum Result { case typed, focusChanged(typed: Int) }

    /// Blocking; call off the main thread. Re-checks the target before every character.
    /// `charDelayMs` paces input — terminals drop characters that arrive too fast.
    static func type(_ text: String, into target: FocusTarget, charDelayMs: Double) -> Result {
        let source = CGEventSource(stateID: .privateState)
        let delay = charDelayMs / 1000
        var typed = 0
        for ch in text {
            guard FocusGuard.matches(target) else { return .focusChanged(typed: typed) }
            let units = Array(String(ch).utf16)
            for down in [true, false] {
                guard let e = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down) else { continue }
                e.flags = []
                e.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
                e.post(tap: .cghidEventTap)
            }
            typed += 1
            Thread.sleep(forTimeInterval: delay)
        }
        return .typed
    }

    static func copyToClipboard(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }
}
