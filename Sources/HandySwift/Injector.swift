import Cocoa
import CoreGraphics

@MainActor
class Injector {
    static let shared = Injector()
    
    func insertText(_ text: String, target: FocusTarget) {
        for char in text {
            // Mid-injection focus guard: abort if the target window changes
            guard FocusGuard.shared.verifyTarget(target) else {
                NSLog("Focus lost or changed during injection. Aborting.")
                // In a real app, we might put the remaining text on the clipboard here
                break
            }
            
            // Convert character to UTF-16 code units for CGEvent
            let utf16 = Array(String(char).utf16)
            guard !utf16.isEmpty else { continue }
            
            // We use CGEvent(keyboardEventSource:virtualKey:keyDown:) with a dummy keycode
            // and then set the unicode string.
            let src = CGEventSource(stateID: .hidSystemState)
            
            if let keyDown = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: true),
               let keyUp = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: false) {
                
                keyDown.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
                keyUp.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
                
                keyDown.post(tap: .cghidEventTap)
                keyUp.post(tap: .cghidEventTap)
            }
            
            // Sleep very briefly to ensure events are processed in order
            Thread.sleep(forTimeInterval: 0.002)
        }
    }
}
