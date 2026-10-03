import Cocoa
import CoreGraphics

class HotkeyManager {
    static let shared = HotkeyManager()
    
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    
    var onDictationTrigger: ((Bool) -> Void)?
    
    func start() {
        let eventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        
        let observer = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { (proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? in
                
                guard let refcon = refcon else { return Unmanaged.passRetained(event) }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
                
                let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                let flags = event.flags
                
                // Debug log
                NSLog("HandySwiftKey: keyCode=\(keyCode) flags=\(flags.rawValue) type=\(type.rawValue)")
                
                // Space bar (keycode 49) + Control modifier
                if keyCode == 49 && flags.contains(.maskControl) {
                    if type == .keyDown {
                        // Prevent auto-repeat triggers
                        let autorepeat = event.getIntegerValueField(.keyboardEventAutorepeat)
                        if autorepeat == 0 {
                            DispatchQueue.main.async {
                                manager.onDictationTrigger?(true)
                            }
                        }
                    } else if type == .keyUp {
                        DispatchQueue.main.async {
                            manager.onDictationTrigger?(false)
                        }
                    }
                    // Swallow the hotkey event
                    return nil
                }
                
                return Unmanaged.passRetained(event)
            },
            userInfo: observer
        ) else {
            NSLog("Failed to create event tap. Make sure Accessibility permissions are granted.")
            return
        }
        
        self.eventTap = tap
        self.runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        NSLog("HotkeyManager started.")
    }
    
    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
    }
}
