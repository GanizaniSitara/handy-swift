import Cocoa

/// Listens for the dictation hotkey (Ctrl+Space) and Escape via a session event tap.
/// Never synthesises modifier keys: it only observes and, for its own keys, swallows.
final class HotkeyTap {
    enum Action { case toggle, cancel }

    /// Called on the main queue. Return value for `.cancel` says whether Escape was consumed.
    var onToggle: (() -> Void)?
    var onCancel: (() -> Bool)?

    private var tap: CFMachPort?
    private var swallowingSpaceUp = false

    private static let spaceKey: Int64 = 49
    private static let escapeKey: Int64 = 53

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

    // Runs on the main run loop (the tap's source is installed there).
    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        let key = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags

        if key == Self.spaceKey {
            if type == .keyDown,
               flags.contains(.maskControl),
               !flags.contains(.maskCommand), !flags.contains(.maskAlternate), !flags.contains(.maskShift) {
                swallowingSpaceUp = true
                if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 { onToggle?() }
                return nil
            }
            if type == .keyUp && swallowingSpaceUp {
                swallowingSpaceUp = false
                return nil
            }
        }

        if key == Self.escapeKey && type == .keyDown,
           event.getIntegerValueField(.keyboardEventAutorepeat) == 0,
           onCancel?() == true {
            return nil
        }

        return Unmanaged.passUnretained(event)
    }
}
