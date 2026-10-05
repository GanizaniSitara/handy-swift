import Foundation

/// ~/Library/Application Support/HandySwift/settings.json. Field names match Handy.NET's
/// settings.json (camelCase) so a domainCorrections list can be copied between the two.
/// Re-read on every dictation, so edits take effect without a restart.
struct Settings: Codable, Equatable {
    /// Dictation chord in Handy.NET's notation, e.g. "Ctrl+Space".
    var hotkey = "Ctrl+Space"
    /// Alternate cancel chord for remote sessions; Alt is Option on Mac.
    var cancelChordHotkey = "Alt+Shift+X"
    var cancelChordEnabled = true
    /// Input device name; empty = system default.
    var microphoneDeviceName = ""
    var charDelayMs: Double = 3
    /// RestoreAndPaste (default) | RefuseAndCopy | PasteAnyway — as Handy.NET.
    var pasteFocusPolicy = "RestoreAndPaste"
    var appLanguage: String = "en"
    /// nil = language defaults; [] = filler removal off.
    var customFillerWords: [String]? = nil
    var domainCorrections: [DomainCorrection] = []
    /// Latest transcript count retained on disk, matching Handy.NET (minimum one).
    var historyLimit = 50
    /// No audio callbacks for this long discards capture; zero disables.
    var noInputTimeoutMs = 15_000
    /// Stop and transcribe at this duration; zero disables.
    var maxRecordingMs = 300_000

    static let directory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/HandySwift")
    static let url = directory.appendingPathComponent("settings.json")

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Settings()
        hotkey = try c.decodeIfPresent(String.self, forKey: .hotkey) ?? d.hotkey
        cancelChordHotkey = try c.decodeIfPresent(String.self, forKey: .cancelChordHotkey) ?? d.cancelChordHotkey
        cancelChordEnabled = try c.decodeIfPresent(Bool.self, forKey: .cancelChordEnabled) ?? d.cancelChordEnabled
        if cancelChordHotkey.caseInsensitiveCompare("Ctrl+Shift+X") == .orderedSame {
            cancelChordHotkey = d.cancelChordHotkey
        }
        microphoneDeviceName = try c.decodeIfPresent(String.self, forKey: .microphoneDeviceName) ?? d.microphoneDeviceName
        charDelayMs = try c.decodeIfPresent(Double.self, forKey: .charDelayMs) ?? d.charDelayMs
        pasteFocusPolicy = try c.decodeIfPresent(String.self, forKey: .pasteFocusPolicy) ?? d.pasteFocusPolicy
        appLanguage = try c.decodeIfPresent(String.self, forKey: .appLanguage) ?? d.appLanguage
        customFillerWords = try c.decodeIfPresent([String].self, forKey: .customFillerWords)
        domainCorrections = try c.decodeIfPresent([DomainCorrection].self, forKey: .domainCorrections) ?? []
        historyLimit = max(1, try c.decodeIfPresent(Int.self, forKey: .historyLimit) ?? d.historyLimit)
        noInputTimeoutMs = max(0, try c.decodeIfPresent(Int.self, forKey: .noInputTimeoutMs) ?? d.noInputTimeoutMs)
        maxRecordingMs = max(0, try c.decodeIfPresent(Int.self, forKey: .maxRecordingMs) ?? d.maxRecordingMs)
    }

    /// Writes a default file on first run; a malformed file is logged and defaults are used.
    static func load(from url: URL = Self.url) -> Settings {
        guard let data = try? Data(contentsOf: url) else {
            let s = Settings()
            s.save(to: url)
            return s
        }
        do {
            let settings = try JSONDecoder().decode(Settings.self, from: data)
            // Persist new defaults/this migration, retaining unknown fields from newer settings.
            if var fields = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let old = fields["cancelChordHotkey"] as? String
                if old == nil || old?.caseInsensitiveCompare("Ctrl+Shift+X") == .orderedSame
                    || fields["cancelChordEnabled"] == nil {
                    fields["cancelChordHotkey"] = settings.cancelChordHotkey
                    fields["cancelChordEnabled"] = settings.cancelChordEnabled
                    do {
                        let migrated = try JSONSerialization.data(withJSONObject: fields, options: [.prettyPrinted, .sortedKeys])
                        try migrated.write(to: url, options: .atomic)
                        DiagLog.write("settings cancel shortcut defaults updated")
                    } catch {
                        DiagLog.write("settings cancel chord migration could not be saved error=\"\(error)\"")
                    }
                }
            }
            return settings
        } catch {
            DiagLog.write("settings unreadable, using defaults error=\"\(error)\"")
            return Settings()
        }
    }

    var dictationShortcut: Shortcut { Shortcut(hotkey) ?? .dictationDefault }
    var cancelChordShortcut: Shortcut? {
        cancelChordEnabled ? (Shortcut(cancelChordHotkey) ?? .cancelDefault) : nil
    }

    static let didChange = Notification.Name("HandySwiftSettingsDidChange")

    func save(to url: URL = Self.url) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? enc.encode(self).write(to: url, options: .atomic)
    }
}
