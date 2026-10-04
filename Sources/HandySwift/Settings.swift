import Foundation

/// ~/Library/Application Support/HandySwift/settings.json. Field names match Handy.NET's
/// settings.json (camelCase) so a domainCorrections list can be copied between the two.
/// Re-read on every dictation, so edits take effect without a restart.
struct Settings: Codable {
    var charDelayMs: Double = 3
    var appLanguage: String = "en"
    /// nil = language defaults; [] = filler removal off.
    var customFillerWords: [String]? = nil
    var domainCorrections: [DomainCorrection] = []

    static let directory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/HandySwift")
    static let url = directory.appendingPathComponent("settings.json")

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Settings()
        charDelayMs = try c.decodeIfPresent(Double.self, forKey: .charDelayMs) ?? d.charDelayMs
        appLanguage = try c.decodeIfPresent(String.self, forKey: .appLanguage) ?? d.appLanguage
        customFillerWords = try c.decodeIfPresent([String].self, forKey: .customFillerWords)
        domainCorrections = try c.decodeIfPresent([DomainCorrection].self, forKey: .domainCorrections) ?? []
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

    func save() {
        try? FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? enc.encode(self).write(to: Self.url, options: .atomic)
    }
}
