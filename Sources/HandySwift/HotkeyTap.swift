import Cocoa

/// Listens for Handy's hotkeys via a session event tap. Never synthesises modifier keys:
/// it only observes and, for its own chords, swallows the key down and matching key up.
///
///   Ctrl+Space          toggle dictation (rebindable via settings "hotkey")
///   Esc                 cancel (consumed only while a dictation is active)
///   Option+Shift+C      copy last transcript (same chord as Handy.NET)
///   Option+Shift+V      retype last transcript into the focused window
final class HotkeyTap {
    /// Handlers run on the main queue, after the tap callback has returned.
    var onToggle: (() -> Void)?
    var onCopyLast: (() -> Void)?
    var onRetypeLast: (() -> Void)?
    /// Called synchronously in the tap: must be cheap. Returns whether Escape was consumed.
    var isActive: (() -> Bool)?
    var onCancel: (() -> Void)?

    /// The dictation chord; set from settings.
    var dictation = Shortcut.dictationDefault
    /// While the settings window records a new shortcut, let every key through.
    var suspended = false

    private var tap: CFMachPort?
    private var swallowedKeyUps = Set<Int64>()

    private enum Key { static let escape: Int64 = 53, c: Int64 = 8, v: Int64 = 9 }

    func start() -> Bool {
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, refcon in
                let me = Unmanaged<HotkeyTap>.fromOpaque(refcon!).takeUnretainedValue()
                return me.handle(type: type, event: event)
            },
            userInfo: refcon
        ) else { return false }

        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    // Runs on the main run loop. Work is deferred so a slow handler can't time the tap out.
    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            DiagLog.write("session hotkey tap re-enabled after \(type == .tapDisabledByTimeout ? "timeout" : "user input")")
            return Unmanaged.passUnretained(event)
        }

        if suspended { return Unmanaged.passUnretained(event) }

        let key = event.getIntegerValueField(.keyboardEventKeycode)

        if type == .keyUp {
            return swallowedKeyUps.remove(key) != nil ? nil : Unmanaged.passUnretained(event)
        }

        let repeating = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        let mods = event.flags.intersection([.maskControl, .maskAlternate, .maskShift, .maskCommand])

        let action: (() -> Void)?
        switch (key, mods) {
        case (dictation.keyCode, dictation.modifiers): action = onToggle
        case (Key.c, [.maskAlternate, .maskShift]): action = onCopyLast
        case (Key.v, [.maskAlternate, .maskShift]): action = onRetypeLast
        case (Key.escape, []) where isActive?() == true: action = onCancel
        default: return Unmanaged.passUnretained(event)
        }

        swallowedKeyUps.insert(key)
        if !repeating, let action { DispatchQueue.main.async(execute: action) }
        return nil
    }
}
