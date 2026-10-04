import Foundation

/// Appends dated lines to ~/Library/Logs/HandySwift/handy.log — one line per dictation plus lifecycle events.
enum DiagLog {
    private static let queue = DispatchQueue(label: "HandySwift.DiagLog")
    private static let url: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/HandySwift")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("handy.log")
    }()
    private static let stamp = ISO8601DateFormatter()

    static func write(_ line: String) {
        let text = "\(stamp.string(from: Date())) \(line)\n"
        queue.async {
            guard let data = text.data(using: .utf8) else { return }
            if let h = try? FileHandle(forWritingTo: url) {
                h.seekToEndOfFile()
                h.write(data)
                try? h.close()
            } else {
                try? data.write(to: url)
            }
        }
    }
}
