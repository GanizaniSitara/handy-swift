import Foundation

/// A marker file present only while Handy runs. Finding one at launch means the previous
/// session died without a clean exit; it records the dictation phase it was in.
enum SessionMarker {
    private static let url = Settings.directory.appendingPathComponent("session.marker")

    /// Logs a crash if the previous session left its marker behind, then claims the marker.
    static func begin() {
        if let previous = try? String(contentsOf: url, encoding: .utf8) {
            DiagLog.write("session previous_crashed \(previous.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        phase("idle")
    }

    static func phase(_ name: String) {
        try? FileManager.default.createDirectory(at: Settings.directory, withIntermediateDirectories: true)
        try? "pid=\(getpid()) phase=\(name) at=\(ISO8601DateFormatter().string(from: Date()))\n"
            .write(to: url, atomically: true, encoding: .utf8)
    }

    static func end() {
        try? FileManager.default.removeItem(at: url)
    }
}
