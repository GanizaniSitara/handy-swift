import Cocoa

/// Types text as Unicode key events — no Cmd+V, no synthetic modifiers. Every event carries
/// empty flags so a physically held modifier cannot turn a character into a shortcut.
enum Injector {
    enum Result { case typed(restores: Int), focusChanged(typed: Int) }

    /// What to do when the target window loses focus. Same names as Handy.NET's PasteFocusPolicy.
    enum FocusPolicy: String {
        case refuseAndCopy, restoreAndPaste, pasteAnyway

        static func parse(_ value: String?) -> FocusPolicy {
            switch value?.trimmingCharacters(in: .whitespaces).lowercased() {
            case "refuseandcopy", "refuse": return .refuseAndCopy
            case "pasteanyway", "anyway": return .pasteAnyway
            default: return .restoreAndPaste
            }
        }
    }

    /// True if typing may proceed into `target`, restoring focus first when the policy allows.
    static func ensureFocus(_ target: FocusTarget, policy: FocusPolicy, restores: inout Int) -> Bool {
        if policy == .pasteAnyway || FocusGuard.matches(target) { return true }
        guard policy == .restoreAndPaste, FocusGuard.restore(target) else { return false }
        restores += 1
        return true
    }

    /// Blocking; call off the main thread. Re-checks the target before every character.
    /// `charDelayMs` paces input — terminals drop characters that arrive too fast.
    static func type(_ text: String, into target: FocusTarget, charDelayMs: Double,
                     policy: FocusPolicy = .refuseAndCopy) -> Result {
        let source = CGEventSource(stateID: .privateState)
        let delay = charDelayMs / 1000
        var typed = 0
        var restores = 0
        for ch in text {
            guard ensureFocus(target, policy: policy, restores: &restores) else { return .focusChanged(typed: typed) }
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
        return .typed(restores: restores)
    }

    static func copyToClipboard(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }
}
