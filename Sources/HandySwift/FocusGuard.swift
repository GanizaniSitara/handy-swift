import Cocoa
import ApplicationServices

@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ id: inout CGWindowID) -> AXError

struct FocusTarget: Equatable, CustomStringConvertible {
    let pid: pid_t
    let windowId: CGWindowID?
    let appName: String

    var description: String { "\(appName)(pid=\(pid) win=\(windowId.map(String.init) ?? "?"))" }
}

/// Identifies the window keystrokes would land in. Uses the AX system-wide element rather than
/// NSWorkspace so it is live and safe to call off the main thread during injection.
enum FocusGuard {
    static func current() -> FocusTarget? {
        let system = AXUIElementCreateSystemWide()
        var appRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedApplicationAttribute as CFString, &appRef) == .success,
              let appRef, CFGetTypeID(appRef) == AXUIElementGetTypeID() else { return nil }
        let app = appRef as! AXUIElement

        var pid: pid_t = 0
        guard AXUIElementGetPid(app, &pid) == .success else { return nil }

        var windowId: CGWindowID?
        var winRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &winRef) == .success,
           let winRef, CFGetTypeID(winRef) == AXUIElementGetTypeID() {
            var id: CGWindowID = 0
            if _AXUIElementGetWindow(winRef as! AXUIElement, &id) == .success { windowId = id }
        }

        let name = NSRunningApplication(processIdentifier: pid)?.localizedName ?? "pid \(pid)"
        return FocusTarget(pid: pid, windowId: windowId, appName: name)
    }

    /// Same app, and the same window when both sides know their window id.
    static func matches(_ target: FocusTarget) -> Bool {
        guard let now = current(), now.pid == target.pid else { return false }
        if let a = target.windowId, let b = now.windowId { return a == b }
        return true
    }
}
