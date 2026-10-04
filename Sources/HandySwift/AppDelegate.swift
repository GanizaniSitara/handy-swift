import AppKit
import AVFoundation

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let statusLine = NSMenuItem(title: "Loading model…", action: nil, keyEquivalent: "")
    private let dictation = Dictation()
    private let hotkey = HotkeyTap()
    private var modelReady = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        DiagLog.write("session start pid=\(getpid())")

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.addItem(statusLine)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Copy Last Transcript", action: #selector(copyLast), keyEquivalent: "c"))
        menu.addItem(NSMenuItem(title: "Open Log", action: #selector(openLog), keyEquivalent: "l"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Handy Swift", action: #selector(quit), keyEquivalent: "q"))
        statusItem.menu = menu

        dictation.onStateChange = { [weak self] _ in self?.refresh() }
        hotkey.onToggle = { [weak self] in self?.dictation.toggle() }
        hotkey.onCancel = { [weak self] in self?.dictation.cancel() ?? false }
        refresh()

        AVCaptureDevice.requestAccess(for: .audio) { granted in
            if !granted { DiagLog.write("session microphone access denied") }
        }
        startHotkey(prompt: true)

        Task {
            do {
                _ = try await dictation.transcriber.load()
                DiagLog.write("session model loaded")
                await MainActor.run { self.modelReady = true; self.refresh() }
            } catch {
                DiagLog.write("session model load failed error=\"\(error.localizedDescription)\"")
                await MainActor.run { self.statusLine.title = "Model failed to load — see log" }
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        DiagLog.write("session end")
    }

    /// The event tap needs Accessibility; keep retrying until the user grants it.
    private func startHotkey(prompt: Bool) {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        if AXIsProcessTrustedWithOptions(opts), hotkey.start() {
            DiagLog.write("session hotkey tap installed")
            return
        }
        statusLine.title = "Waiting for Accessibility permission…"
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.startHotkey(prompt: false) }
    }

    private func refresh() {
        let (symbol, text): (String, String)
        switch dictation.state {
        case .idle: (symbol, text) = ("mic", modelReady ? "Ready — Ctrl+Space to dictate" : "Loading model…")
        case .recording: (symbol, text) = ("mic.fill", "Recording — Ctrl+Space to finish, Esc to cancel")
        case .transcribing: (symbol, text) = ("ellipsis.circle", "Transcribing — Esc to cancel")
        }
        statusItem.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Handy Swift")
        statusItem.button?.contentTintColor = dictation.state == .recording ? .systemRed : nil
        statusLine.title = text
    }

    @objc private func copyLast() {
        guard let text = dictation.lastTranscript else { NSSound.beep(); return }
        Injector.copyToClipboard(text)
    }

    @objc private func openLog() {
        let log = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/HandySwift/handy.log")
        NSWorkspace.shared.open(log)
    }

    @objc private func quit() {
        NSApplication.shared.terminate(self)
    }
}
