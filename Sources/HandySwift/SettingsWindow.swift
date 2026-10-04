import SwiftUI
import ServiceManagement

/// Handy.NET's settings model: edits are staged in `draft` and written by Apply,
/// which saves settings.json and broadcasts `Settings.didChange`.
final class SettingsStore: ObservableObject {
    @Published var draft: Settings
    @Published var draftOpenAtLogin = SMAppService.mainApp.status == .enabled
    @Published private(set) var saved: Settings
    @Published var microphones: [String] = []
    @Published var status = ""
    @Published var modelStatus = "Loading…"

    /// Pauses the global hotkey while a new shortcut is being recorded.
    var suspendHotkey: (Bool) -> Void = { _ in }

    init() {
        let s = Settings.load()
        saved = s
        draft = s
    }

    var isDirty: Bool {
        draft != saved || draftOpenAtLogin != (SMAppService.mainApp.status == .enabled)
    }

    /// Re-reads disk state, discarding unapplied edits (e.g. after hand-editing the file).
    func reload() {
        let s = Settings.load()
        saved = s
        draft = s
        draftOpenAtLogin = SMAppService.mainApp.status == .enabled
        microphones = AudioDevices.inputs().map(\.name)
        status = ""
    }

    func apply() {
        draft.historyLimit = max(1, draft.historyLimit)
        draft.save()
        saved = draft
        let loginNow = SMAppService.mainApp.status == .enabled
        if draftOpenAtLogin != loginNow {
            do {
                if draftOpenAtLogin { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                DiagLog.write("session login item change failed error=\"\(error.localizedDescription)\"")
                NSSound.beep()
            }
            draftOpenAtLogin = SMAppService.mainApp.status == .enabled
        }
        NotificationCenter.default.post(name: Settings.didChange, object: nil)
        status = "Saved"
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            if self?.status == "Saved" { self?.status = "" }
        }
    }
}

final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    let store = SettingsStore()

    func show() {
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(store: store, close: { [weak self] in
                self?.window?.performClose(nil)
            })))
            w.title = "Handy Swift — Settings"
            w.styleMask = [.titled, .closable, .miniaturizable]
            w.setContentSize(NSSize(width: 780, height: 640))
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.center()
            window = w
        }
        store.reload()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

// MARK: - Layout, mirroring Handy.NET's MainWindow.xaml

private enum Theme {
    static let accent = Palette.idle                                  // Color.BackgroundUI #5893DA
    static let success = Color(nsColor: NSColor(srgbRed: 0x2A / 255.0, green: 0x8F / 255.0, blue: 0x3A / 255.0, alpha: 1))
    static let border = Color(nsColor: .separatorColor)
    static let card = Color(nsColor: .controlBackgroundColor)
    static let background = Color(nsColor: .windowBackgroundColor)
}

private enum Page: String, CaseIterable { case general = "General", advanced = "Advanced", models = "Models", log = "Log" }

struct SettingsView: View {
    @ObservedObject var store: SettingsStore
    let close: () -> Void
    @State private var page: Page = .general

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            VStack(spacing: 0) {
                Group {
                    switch page {
                    case .general: ScrollView { GeneralPage(store: store).padding(.bottom, 14) }
                    case .advanced: ScrollView { AdvancedPage(store: store).padding(.bottom, 14) }
                    case .models: ScrollView { ModelsPage(store: store).padding(.bottom, 14) }
                    case .log: LogPage()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                footer
            }
        }
        .frame(width: 780, height: 640)
        .background(Theme.background)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                if let logo = HandLogo.image {
                    Image(nsImage: logo).resizable().interpolation(.high).frame(width: 22, height: 24)
                }
                Text("Handy Swift").font(.system(size: 20, weight: .semibold)).foregroundStyle(Color(nsColor: Theme.accent))
            }
            .padding(EdgeInsets(top: 16, leading: 16, bottom: 18, trailing: 0))
            Divider().padding(.horizontal, 10).padding(.bottom, 8)
            ForEach(Page.allCases, id: \.self) { p in
                Button { page = p } label: {
                    Text(p.rawValue)
                        .font(.system(size: 14))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 6)
                            .fill(page == p ? Color(nsColor: Theme.accent).opacity(0.18) : .clear))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 6).padding(.vertical, 2)
            }
            Spacer()
            Text("v\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev")")
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .padding(EdgeInsets(top: 0, leading: 16, bottom: 14, trailing: 16))
        }
        .frame(width: 170)
    }

    private var footer: some View {
        HStack {
            Button("Help") {
                NSWorkspace.shared.open(URL(string: "https://github.com/GanizaniSitara/handy-swift#readme")!)
            }
            Text(store.status).fontWeight(.semibold).foregroundStyle(Theme.success)
            Spacer()
            Button("Minimize", action: close)
            Button("Apply") { store.apply() }
                .keyboardShortcut(.defaultAction)
                .disabled(!store.isDirty)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }
}

/// "SHORTCUTS"-style group title: 11pt semibold grey, as Text.SectionGroupTitle.
private struct GroupTitle: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(EdgeInsets(top: 18, leading: 14, bottom: 8, trailing: 0))
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// White rounded card with hairline rows, as the SettingsCard / SettingsRow styles.
private struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing: 0) { content }
            .background(RoundedRectangle(cornerRadius: 8).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1))
            .padding(.horizontal, 14).padding(.bottom, 4)
    }
}

private struct Row<Control: View>: View {
    let label: String
    var hint: String? = nil
    var first = false
    @ViewBuilder var control: Control
    var body: some View {
        VStack(spacing: 0) {
            if !first { Divider().padding(.leading, 14) }
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label).fontWeight(.medium)
                    if let hint { Text(hint).font(.system(size: 12)).foregroundStyle(.secondary) }
                }
                Spacer(minLength: 16)
                control
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
        }
    }
}

private struct Hint: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.system(size: 12)).foregroundStyle(.secondary)
            .padding(.horizontal, 18).padding(.top, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct GeneralPage: View {
    @ObservedObject var store: SettingsStore

    private static let languages: [(String, String)] = [
        ("en", "English"), ("de", "German"), ("es", "Spanish"), ("fr", "French"), ("it", "Italian"),
        ("pt", "Portuguese"), ("pl", "Polish"), ("cs", "Czech"), ("ru", "Russian"), ("uk", "Ukrainian"),
        ("tr", "Turkish"), ("ar", "Arabic"), ("ja", "Japanese"), ("ko", "Korean"), ("vi", "Vietnamese"), ("zh", "Chinese"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            GroupTitle("Shortcuts")
            Card {
                Row(label: "Transcribe shortcut", first: true) {
                    ShortcutRecorder(hotkey: $store.draft.hotkey, suspend: store.suspendHotkey)
                }
                Row(label: "Cancel shortcut") { Text("Esc").foregroundStyle(.secondary) }
                Row(label: "Copy last transcription") { Text("⌥⇧C").foregroundStyle(.secondary) }
                Row(label: "Retype last transcription") { Text("⌥⇧V").foregroundStyle(.secondary) }
            }
            Hint("Click the shortcut, then press the new key combination. Esc cancels.")

            GroupTitle("Sound")
            Card {
                Row(label: "Microphone", first: true) {
                    Picker("", selection: $store.draft.microphoneDeviceName) {
                        Text("System default").tag("")
                        ForEach(store.microphones, id: \.self) { Text($0).tag($0) }
                        if !store.draft.microphoneDeviceName.isEmpty,
                           !store.microphones.contains(store.draft.microphoneDeviceName) {
                            Text("\(store.draft.microphoneDeviceName) (not connected)").tag(store.draft.microphoneDeviceName)
                        }
                    }
                    .labelsHidden().frame(width: 240, alignment: .trailing)
                }
            }

            GroupTitle("Transcription")
            Card {
                Row(label: "Language", hint: "Chooses the filler-word list.", first: true) {
                    Picker("", selection: $store.draft.appLanguage) {
                        ForEach(Self.languages, id: \.0) { Text($0.1).tag($0.0) }
                    }
                    .labelsHidden().frame(width: 240, alignment: .trailing)
                }
                Row(label: "Filler words", hint: "Removes “um”, “uh” and stutters before typing.") {
                    Picker("", selection: fillerMode) {
                        Text("Language defaults").tag(FillerMode.defaults)
                        Text("Off").tag(FillerMode.off)
                        Text("Custom list").tag(FillerMode.custom)
                    }
                    .labelsHidden().frame(width: 240, alignment: .trailing)
                }
                if fillerMode.wrappedValue == .custom {
                    Row(label: "Words to remove") {
                        CommaField(placeholder: "comma-separated", list: $store.draft.customFillerWords.or([]))
                            .frame(width: 240)
                    }
                }
            }
        }
    }

    private enum FillerMode { case defaults, off, custom }

    private var fillerMode: Binding<FillerMode> {
        Binding(
            get: {
                guard let words = store.draft.customFillerWords else { return .defaults }
                return words.isEmpty ? .off : .custom
            },
            set: { mode in
                switch mode {
                case .defaults: store.draft.customFillerWords = nil
                case .off: store.draft.customFillerWords = []
                case .custom: store.draft.customFillerWords = TranscriptFilter.fillers(for: store.draft.appLanguage)
                }
            })
    }
}

private struct AdvancedPage: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        VStack(spacing: 0) {
            GroupTitle("Output")
            Card {
                Row(label: "If the target window lost focus", hint: "Handy remembers the window you started dictating in.", first: true) {
                    Picker("", selection: $store.draft.pasteFocusPolicy) {
                        Text("Restore it, then type").tag("RestoreAndPaste")
                        Text("Don't type — copy to clipboard").tag("RefuseAndCopy")
                        Text("Type into whatever is focused").tag("PasteAnyway")
                    }
                    .labelsHidden().frame(width: 240, alignment: .trailing)
                }
            }

            GroupTitle("Paste timing")
            Card {
                Row(label: "Delay between characters", hint: "Raise it if a terminal or remote session drops characters.", first: true) {
                    Stepper(value: $store.draft.charDelayMs, in: 0...50, step: 1) {
                        Text("\(Int(store.draft.charDelayMs)) ms").monospacedDigit().frame(width: 50, alignment: .trailing)
                    }
                }
            }

            GroupTitle("Domain terms")
            Card {
                DomainTermsEditor(rules: $store.draft.domainCorrections)
            }
            Hint("Rewrite misheard phrases to the right term. Lists are comma-separated. “Require any” limits a rule to text near one of those words; “Block” skips it near any of them.")

            GroupTitle("History")
            Card {
                Row(label: "Saved transcripts", hint: "Keep the latest entries. Lowering this deletes older ones when applied.", first: true) {
                    TextField("", value: $store.draft.historyLimit, format: .number)
                        .labelsHidden().textFieldStyle(.roundedBorder).frame(width: 80)
                }
            }
            Hint("At least one transcript is retained. The default is 50.")

            GroupTitle("UI")
            Card {
                Row(label: "Open at login", first: true) {
                    Toggle("", isOn: $store.draftOpenAtLogin).labelsHidden().toggleStyle(.switch)
                }
                Row(label: "Settings file", hint: "~/Library/Application Support/HandySwift/settings.json") {
                    Button("Open") { NSWorkspace.shared.open(Settings.url) }
                }
            }
        }
    }
}

private struct ModelsPage: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        VStack(spacing: 0) {
            GroupTitle("Active")
            Card {
                Row(label: "Parakeet TDT 0.6B v3", hint: "NVIDIA, 25 languages. Runs on the Neural Engine via FluidAudio.", first: true) {
                    Text(store.modelStatus).foregroundStyle(.secondary)
                }
                Row(label: "Location", hint: "~/Library/Application Support/FluidAudio/Models") {
                    Button("Show in Finder") {
                        let dir = FileManager.default.homeDirectoryForCurrentUser
                            .appendingPathComponent("Library/Application Support/FluidAudio/Models")
                        NSWorkspace.shared.activateFileViewerSelecting([dir])
                    }
                }
            }
            Hint("The model downloads automatically on first launch (about 470 MB) and then works offline.")
        }
    }
}

/// The tail of handy.log, like Handy.NET's Log page.
private struct LogPage: View {
    @State private var text = ""
    private let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/HandySwift/handy.log")

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button("Refresh", action: load)
                Button("Open Log File") { NSWorkspace.shared.open(url) }
                Spacer()
            }
            ScrollViewReader { proxy in
                ScrollView {
                    Text(text.isEmpty ? "No log yet." : text)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                    Color.clear.frame(height: 1).id("end")
                }
                .background(RoundedRectangle(cornerRadius: 8).fill(Theme.card))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1))
                .onChange(of: text) { _, _ in proxy.scrollTo("end", anchor: .bottom) }
            }
        }
        .padding(14)
        .onAppear(perform: load)
    }

    private func load() {
        let all = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        text = all.split(separator: "\n", omittingEmptySubsequences: false).suffix(400).joined(separator: "\n")
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
        VStack(alignment: .leading, spacing: 10) {
        if rules.isEmpty {
            Text("No domain terms yet.").foregroundStyle(.secondary)
        }
        ForEach(rules.indices, id: \.self) { i in
            if i > 0 { Divider() }
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
        }
        Button("Add Term") { rules.append(DomainCorrection()) }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
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
