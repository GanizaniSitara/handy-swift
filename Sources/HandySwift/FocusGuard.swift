import Cocoa
import ApplicationServices

@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ element: AXUIElement, _ id: inout CGWindowID) -> AXError

struct FocusTarget: Equatable {
    let pid: pid_t
    let windowId: CGWindowID?
    let appName: String
}

@MainActor
class FocusGuard {
    static let shared = FocusGuard()
    
    func captureCurrentTarget() -> FocusTarget? {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return nil }
        
        let pid = frontApp.processIdentifier
        let appElem = AXUIElementCreateApplication(pid)
        var focusedWindow: CFTypeRef?
        
        var windowId: CGWindowID? = nil
        
        if AXUIElementCopyAttributeValue(appElem, kAXFocusedWindowAttribute as CFString, &focusedWindow) == .success {
            let windowElem = focusedWindow as! AXUIElement
            var cgWindowId: CGWindowID = 0
            if _AXUIElementGetWindow(windowElem, &cgWindowId) == .success {
                windowId = cgWindowId
            }
        }
        
        return FocusTarget(pid: pid, windowId: windowId, appName: frontApp.localizedName ?? "Unknown")
    }
    
    func verifyTarget(_ target: FocusTarget) -> Bool {
        guard let current = captureCurrentTarget() else { return false }
        if current.pid != target.pid { return false }
        if let originalWindowId = target.windowId, let currentWindowId = current.windowId {
            if originalWindowId != currentWindowId { return false }
        }
        return true
    }
}
