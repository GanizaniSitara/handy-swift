import Foundation

/// ~/Library/Application Support/HandySwift/settings.json. Field names match Handy.NET's
/// settings.json (camelCase) so a domainCorrections list can be copied between the two.
/// Re-read on every dictation, so edits take effect without a restart.
struct Settings: Codable, Equatable {
    /// Dictation chord in Handy.NET's notation, e.g. "Ctrl+Space".
    var hotkey = "Ctrl+Space"
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
    static func load() -> Settings {
        guard let data = try? Data(contentsOf: url) else {
            let s = Settings()
            s.save()
            return s
        }
        do {
            return try JSONDecoder().decode(Settings.self, from: data)
        } catch {
            DiagLog.write("settings unreadable, using defaults error=\"\(error)\"")
            return Settings()
        }
    }

    var dictationShortcut: Shortcut { Shortcut(hotkey) ?? .dictationDefault }

    static let didChange = Notification.Name("HandySwiftSettingsDidChange")

    func save() {
        try? FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? enc.encode(self).write(to: Self.url, options: .atomic)
    }
}
