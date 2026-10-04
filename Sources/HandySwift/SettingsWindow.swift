import SwiftUI
import ServiceManagement

/// Edits settings.json live: every change is saved immediately and broadcast via
/// `Settings.didChange`, so the next dictation (and the hotkey) pick it up.
final class SettingsStore: ObservableObject {
    @Published var settings: Settings {
        didSet {
            guard settings != oldValue else { return }
            settings.save()
            NotificationCenter.default.post(name: Settings.didChange, object: nil)
        }
    }
    @Published var openAtLogin = SMAppService.mainApp.status == .enabled
    @Published var microphones: [String] = []

    /// Pauses the global hotkey while a new shortcut is being recorded.
    var suspendHotkey: (Bool) -> Void = { _ in }

    init() {
        settings = Settings.load()
        reloadMicrophones()
    }

    func reloadMicrophones() {
        microphones = AudioDevices.inputs().map(\.name)
    }

    func setOpenAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            DiagLog.write("session login item change failed error=\"\(error.localizedDescription)\"")
            NSSound.beep()
        }
        openAtLogin = SMAppService.mainApp.status == .enabled
        NotificationCenter.default.post(name: Settings.didChange, object: nil)  // keeps the menu checkmark in step
    }
}

final class SettingsWindowController {
    private var window: NSWindow?
    let store = SettingsStore()

    func show() {
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(store: store)))
            w.title = "Handy Swift Settings"
            w.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            w.setContentSize(NSSize(width: 640, height: 600))
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        store.settings = Settings.load()  // pick up hand edits to the file
        store.reloadMicrophones()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    @ObservedObject var store: SettingsStore

    private static let languages: [(String, String)] = [
        ("en", "English"), ("de", "German"), ("es", "Spanish"), ("fr", "French"), ("it", "Italian"),
        ("pt", "Portuguese"), ("pl", "Polish"), ("cs", "Czech"), ("ru", "Russian"), ("uk", "Ukrainian"),
        ("tr", "Turkish"), ("ar", "Arabic"), ("ja", "Japanese"), ("ko", "Korean"), ("vi", "Vietnamese"), ("zh", "Chinese"),
    ]

    var body: some View {
        Form {
            Section("Shortcuts") {
                LabeledContent("Transcribe") {
                    ShortcutRecorder(hotkey: $store.settings.hotkey, suspend: store.suspendHotkey)
                }
                LabeledContent("Cancel", value: "Esc")
                LabeledContent("Copy last transcript", value: "⌥⇧C")
                LabeledContent("Retype last transcript", value: "⌥⇧V")
            }

            Section("Sound") {
                Picker("Microphone", selection: $store.settings.microphoneDeviceName) {
                    Text("System default").tag("")
                    ForEach(store.microphones, id: \.self) { Text($0).tag($0) }
                    if !store.settings.microphoneDeviceName.isEmpty,
                       !store.microphones.contains(store.settings.microphoneDeviceName) {
                        Text("\(store.settings.microphoneDeviceName) (not connected)").tag(store.settings.microphoneDeviceName)
                    }
                }
            }

            Section {
                Picker("When focus moves", selection: $store.settings.pasteFocusPolicy) {
                    Text("Restore the window, then type").tag("RestoreAndPaste")
                    Text("Don't type — copy to clipboard").tag("RefuseAndCopy")
                    Text("Type into whatever is focused").tag("PasteAnyway")
                }
                LabeledContent("Delay between characters") {
                    Stepper(value: $store.settings.charDelayMs, in: 0...50, step: 1) {
                        Text("\(Int(store.settings.charDelayMs)) ms").monospacedDigit()
                    }
                }
            } header: {
                Text("Typing")
            } footer: {
                Text("Raise the delay if a terminal or remote session drops characters.")
            }

            Section("Transcript") {
                Picker("Language", selection: $store.settings.appLanguage) {
                    ForEach(Self.languages, id: \.0) { Text($0.1).tag($0.0) }
                }
                Picker("Filler words", selection: fillerMode) {
                    Text("Language defaults").tag(FillerMode.defaults)
                    Text("Off").tag(FillerMode.off)
                    Text("Custom list").tag(FillerMode.custom)
                }
                if fillerMode.wrappedValue == .custom {
                    CommaField(placeholder: "Words to remove, comma-separated", list: $store.settings.customFillerWords.or([]))
                }
            }

            Section {
                DomainTermsEditor(rules: $store.settings.domainCorrections)
            } header: {
                Text("Domain terms")
            } footer: {
                Text("Rewrite misheard phrases to the right term. Lists are comma-separated. “Require any” limits a rule to text near one of those words; “Block” skips it near any of them.")
            }

            Section("General") {
                Toggle("Open at login", isOn: Binding(get: { store.openAtLogin }, set: { store.setOpenAtLogin($0) }))
                HStack {
                    Button("Open Settings File") { NSWorkspace.shared.open(Settings.url) }
                    Button("Open Log") {
                        NSWorkspace.shared.open(FileManager.default.homeDirectoryForCurrentUser
                            .appendingPathComponent("Library/Logs/HandySwift/handy.log"))
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 560, minHeight: 480)
    }

    private enum FillerMode { case defaults, off, custom }

    private var fillerMode: Binding<FillerMode> {
        Binding(
            get: {
                guard let words = store.settings.customFillerWords else { return .defaults }
                return words.isEmpty ? .off : .custom
            },
            set: { mode in
                switch mode {
                case .defaults: store.settings.customFillerWords = nil
                case .off: store.settings.customFillerWords = []
                case .custom: store.settings.customFillerWords = TranscriptFilter.fillers(for: store.settings.appLanguage)
                }
            })
    }
}

/// Click, then press the new chord. Esc cancels. Needs at least one modifier.
struct ShortcutRecorder: View {
    @Binding var hotkey: String
    let suspend: (Bool) -> Void
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button(recording ? "Press shortcut…" : (Shortcut(hotkey) ?? .dictationDefault).symbols) {
            recording ? stop() : start()
        }
        .frame(minWidth: 130)
        .onDisappear { stop() }
    }

    private func start() {
        recording = true
        suspend(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { stop(); return nil }  // Esc
            if let s = Shortcut(event: event) {
                hotkey = s.description
                stop()
            } else {
                NSSound.beep()  // needs a modifier plus a supported key
            }
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if recording { suspend(false) }
        recording = false
    }
}

struct DomainTermsEditor: View {
    @Binding var rules: [DomainCorrection]

    var body: some View {
        if rules.isEmpty {
            Text("No domain terms yet.").foregroundStyle(.secondary)
        }
        ForEach(rules.indices, id: \.self) { i in
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
                GridRow {
                    Toggle("", isOn: $rules[i].enabled).labelsHidden().help("Enabled")
                    HStack {
                        TextField("", text: $rules[i].to, prompt: Text("Canonical term, e.g. ServiceNow"))
                            .labelsHidden().textFieldStyle(.roundedBorder)
                        Toggle("Case-sensitive", isOn: $rules[i].caseSensitive).toggleStyle(.checkbox)
                        Button { rules.remove(at: i) } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless).help("Delete term")
                    }
                }
                GridRow {
                    Text("Heard as").foregroundStyle(.secondary)
                    CommaField(placeholder: "service now, snow", list: variants(i))
                }
                GridRow {
                    Text("Require any").foregroundStyle(.secondary)
                    HStack {
                        CommaField(placeholder: "ticket, incident (optional)", list: $rules[i].requiredContext)
                        Text("Block").foregroundStyle(.secondary)
                        CommaField(placeholder: "optional", list: $rules[i].blockedContext)
                    }
                }
            }
            .padding(.vertical, 4)
        }
        Button("Add Term") { rules.append(DomainCorrection()) }
    }

    /// Edits `variants`, keeping the legacy `from` field in step as Handy.NET does.
    private func variants(_ i: Int) -> Binding<[String]> {
        Binding(
            get: { rules[i].effectiveVariants },
            set: { list in
                rules[i].variants = list
                rules[i].from = list.first ?? ""
            })
    }
}

private func splitList(_ text: String) -> [String] {
    text.split(whereSeparator: { $0 == "," || $0 == ";" })
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }
}

/// A text field editing a string list as comma-separated text. Holds its own text so a
/// half-typed entry ("foo, ") isn't normalised away mid-keystroke.
struct CommaField: View {
    let placeholder: String
    @Binding var list: [String]
    @State private var text = ""

    var body: some View {
        TextField("", text: $text, prompt: Text(placeholder))
            .labelsHidden()
            .textFieldStyle(.roundedBorder)
            .onAppear { text = list.joined(separator: ", ") }
            .onChange(of: text) { _, new in
                let parsed = splitList(new)
                if parsed != list { list = parsed }
            }
            .onChange(of: list) { _, new in
                if splitList(text) != new { text = new.joined(separator: ", ") }
            }
    }
}

private extension Binding where Value == [String]? {
    func or(_ fallback: [String]) -> Binding<[String]> {
        Binding<[String]>(get: { wrappedValue ?? fallback }, set: { wrappedValue = $0 })
    }
}
