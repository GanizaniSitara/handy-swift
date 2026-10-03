import Cocoa
import Carbon

@MainActor
class GlobalHotkey {
    static let shared = GlobalHotkey()
    var onAction: ((Bool) -> Void)?
    
    func register(keyCode: UInt32 = UInt32(kVK_Space), modifiers: UInt32 = UInt32(controlKey)) {
        var hotKeyRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(1212826457), id: 1) // "HNDY" in dec
        
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        if status != noErr {
            NSLog("HandySwift: Failed to register Carbon Hotkey")
        }
        
        var eventTypes = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        ]
        
        let ptr = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        
        InstallEventHandler(GetApplicationEventTarget(), { (handler, event, userData) -> OSStatus in
            guard let event = event, let userData = userData else { return noErr }
            let mySelf = Unmanaged<GlobalHotkey>.fromOpaque(userData).takeUnretainedValue()
            
            let eventKind = GetEventKind(event)
            let isDown = (eventKind == kEventHotKeyPressed)
            
            Task { @MainActor in
                mySelf.onAction?(isDown)
            }
            return noErr
        }, 2, &eventTypes, ptr, nil)
    }
}
