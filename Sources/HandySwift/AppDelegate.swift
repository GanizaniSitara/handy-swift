import AppKit

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "HandySwift")
        }
        
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "HandySwift Active", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))
        statusItem.menu = menu
        
        // Register Control + Space hotkey for dictation via NSEvent
        var isRecording = false
        NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 49 && event.modifierFlags.contains(.control) {
                NSLog("HandySwift: Control+Space detected via NSEvent")
                if isRecording {
                    DictationEngine.shared.stopRecording()
                    isRecording = false
                } else {
                    DictationEngine.shared.startRecording()
                    isRecording = true
                }
            }
        }
        
        NSLog("HandySwift started.")
    }
    
    @objc func quit() {
        NSApplication.shared.terminate(self)
    }
}
