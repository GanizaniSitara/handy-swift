import AppKit
import AVFoundation
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let statusLine = NSMenuItem(title: "Loading model…", action: nil, keyEquivalent: "")
    private let dictation = Dictation()
    private let hotkey = HotkeyTap()
    private let overlay = Overlay()
    private var modelReady = false
    private var sigterm: DispatchSourceSignal?
    private let loginItem = NSMenuItem(title: "Open at Login", action: #selector(toggleLogin), keyEquivalent: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        DiagLog.write("session start pid=\(getpid()) path=\(Bundle.main.bundlePath)")
        SessionMarker.begin()

        // pkill/logout send SIGTERM; exit cleanly so it isn't recorded as a crash.
        signal(SIGTERM, SIG_IGN)
        sigterm = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        sigterm?.setEventHandler { NSApplication.shared.terminate(nil) }
        sigterm?.resume()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.addItem(statusLine)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Copy Last Transcript  ⌥⇧C", action: #selector(copyLast), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Retype Last Transcript  ⌥⇧V", action: #selector(retypeLast), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Open Settings File", action: #selector(openSettings), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Open Log", action: #selector(openLog), keyEquivalent: ""))
        loginItem.target = self
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(loginItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Handy Swift", action: #selector(quit), keyEquivalent: "q"))
        statusItem.menu = menu

        dictation.onStateChange = { [weak self] state in
            SessionMarker.phase("\(state)")
            self?.refresh()
            guard let self else { return }
            self.overlay.show(state, level: { [recorder = self.dictation.recorder] in recorder.level })
        }
        hotkey.onToggle = { [weak self] in self?.dictation.toggle() }
        hotkey.isActive = { [weak self] in self?.dictation.isActive ?? false }
        hotkey.onCancel = { [weak self] in self?.dictation.cancel() }
        hotkey.onCopyLast = { [weak self] in self?.copyLast() }
        hotkey.onRetypeLast = { [weak self] in self?.dictation.retypeLast() }
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
        SessionMarker.end()
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

    @objc private func retypeLast() {
        // Let the menu close and focus return to the previous window first.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.dictation.retypeLast() }
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            DiagLog.write("session login item change failed error=\"\(error.localizedDescription)\"")
            NSSound.beep()
        }
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    @objc private func openSettings() {
        _ = Settings.load()  // creates the file with defaults if missing
        NSWorkspace.shared.open(Settings.url)
    }

    @objc private func openLog() {
        let log = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/HandySwift/handy.log")
        NSWorkspace.shared.open(log)
    }

    @objc private func quit() {
        NSApplication.shared.terminate(self)
    }
}
