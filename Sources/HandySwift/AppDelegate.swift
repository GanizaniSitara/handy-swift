import AppKit
import AVFoundation
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let statusLine = NSMenuItem(title: "Loading model…", action: nil, keyEquivalent: "")
    private let dictation = Dictation()
    private let hotkey = HotkeyTap()
    private let overlay = Overlay()
    private let settingsWindow = SettingsWindowController()
    private lazy var historyWindow = HistoryWindowController(history: dictation.history)
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
        menu.addItem(NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "History…", action: #selector(showHistory), keyEquivalent: ""))
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
            self.overlay.show(state, levels: { [recorder = self.dictation.recorder] in recorder.levels })
        }
        hotkey.onToggle = { [weak self] in self?.dictation.toggle() }
        hotkey.isActive = { [weak self] in self?.dictation.isActive ?? false }
        hotkey.onCancel = { [weak self] in self?.dictation.cancel() }
        hotkey.onCopyLast = { [weak self] in self?.copyLast() }
        hotkey.onRetypeLast = { [weak self] in self?.dictation.retypeLast() }
        settingsWindow.store.suspendHotkey = { [weak self] on in self?.hotkey.suspended = on }
        NotificationCenter.default.addObserver(forName: Settings.didChange, object: nil, queue: .main) { [weak self] _ in
            self?.applySettings()
        }
        hotkey.dictation = Settings.load().dictationShortcut
        refresh()

        AVCaptureDevice.requestAccess(for: .audio) { granted in
            if !granted { DiagLog.write("session microphone access denied") }
        }
        startHotkey(prompt: true)

        Task {
            do {
                _ = try await dictation.transcriber.load()
                DiagLog.write("session model loaded")
                await MainActor.run {
                    self.modelReady = true
                    self.settingsWindow.store.modelStatus = "Loaded"
                    self.refresh()
                }
            } catch {
                DiagLog.write("session model load failed error=\"\(error.localizedDescription)\"")
                await MainActor.run {
                    self.statusLine.title = "Model failed to load — see log"
                    self.settingsWindow.store.modelStatus = "Failed — see Log"
                }
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
        let text: String
        switch dictation.state {
        case .idle: text = modelReady ? "Ready — \(hotkey.dictation.symbols) to dictate" : "Loading model…"
        case .recording: text = "Recording — \(hotkey.dictation.symbols) to finish, Esc to cancel"
        case .transcribing: text = "Transcribing — Esc to cancel"
        }
        statusItem.button?.image = Palette.trayIcon(dictation.state)
        statusItem.button?.toolTip = "Handy Swift"
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

    @objc private func showSettings() {
        settingsWindow.show()
    }

    @objc private func showHistory() {
        historyWindow.show()
    }

    /// Applies settings that live outside the per-dictation reload: the hotkey and menu text.
    private func applySettings() {
        let settings = Settings.load()
        hotkey.dictation = settings.dictationShortcut
        dictation.history.setLimit(settings.historyLimit)
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        refresh()
    }

    @objc private func openLog() {
        let log = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/HandySwift/handy.log")
        NSWorkspace.shared.open(log)
    }

    @objc private func quit() {
        NSApplication.shared.terminate(self)
    }
}
