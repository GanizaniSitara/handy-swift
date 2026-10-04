import Foundation
import Combine

/// Keep Handy.NET's history.json shape so transcripts can be moved between apps.
struct HistoryEntry: Codable, Identifiable, Equatable {
    let id = UUID()
    let text: String
    let timestampUtc: Date

    enum CodingKeys: String, CodingKey {
        case text = "Text"
        case timestampUtc = "TimestampUtc"
    }
}

/// Used on the main thread, like Dictation and the history window.
final class HistoryService: ObservableObject {
    @Published private(set) var entries: [HistoryEntry] = []
    @Published private(set) var error: String?
    private let url: URL
    private var limit: Int

    init(url: URL = Settings.directory.appendingPathComponent("history.json"), limit: Int) {
        self.url = url
        self.limit = max(1, limit)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .custom { decoder in
                let container = try decoder.singleValueContainer()
                let text = try container.decode(String.self)
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                if let date = formatter.date(from: text) { return date }
                formatter.formatOptions = [.withInternetDateTime]
                guard let date = formatter.date(from: text) else {
                    throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid history timestamp")
                }
                return date
            }
            entries = try decoder.decode([HistoryEntry].self, from: Data(contentsOf: url))
            if entries.count > self.limit {
                entries = Array(entries.suffix(self.limit))
                save()
            }
        } catch {
            report(error)
        }
    }

    func setLimit(_ limit: Int) {
        self.limit = max(1, limit)
        guard entries.count > self.limit else { return }
        entries = Array(entries.suffix(self.limit))
        save()
    }

    func add(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        entries.append(HistoryEntry(text: text, timestampUtc: Date()))
        entries = Array(entries.suffix(limit))
        save()
    }

    func remove(_ id: UUID) {
        entries.removeAll { $0.id == id }
        save()
    }

    func clear() {
        entries = []
        save()
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(entries).write(to: url, options: .atomic)
            error = nil
        } catch {
            report(error)
        }
    }

    private func report(_ failure: Error) {
        error = "History could not be loaded or saved: \(failure.localizedDescription)"
        DiagLog.write("history error=\"\(failure.localizedDescription)\"")
    }
}
