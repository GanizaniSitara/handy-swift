import Foundation

/// Uses monotonic times. Silent audio callbacks are input, not a disconnected device.
struct RecordingWatchdog {
    enum Action { case none, discard, transcribe }
    let startedAt: TimeInterval
    let noInputTimeoutMs: Int
    let maxRecordingMs: Int

    func action(now: TimeInterval, lastInputAt: TimeInterval?) -> Action {
        // Match Handy.NET: the hard ceiling keeps the captured audio, even if input stalled.
        if maxRecordingMs > 0, (now - startedAt) * 1000 >= Double(maxRecordingMs) {
            return .transcribe
        }
        if noInputTimeoutMs > 0, (now - (lastInputAt ?? startedAt)) * 1000 >= Double(noInputTimeoutMs) {
            return .discard
        }
        return .none
    }
}
