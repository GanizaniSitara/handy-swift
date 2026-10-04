import Cocoa

/// Hotkey → record → transcribe → type into the window that was focused when recording began.
final class Dictation {
    enum State { case idle, recording, transcribing }

    private(set) var state: State = .idle { didSet { onStateChange?(state) } }
    var onStateChange: ((State) -> Void)?
    private(set) var lastTranscript: String?

    let transcriber = Transcriber()
    private let recorder = Recorder()
    private let injectQueue = DispatchQueue(label: "HandySwift.inject")

    private var target: FocusTarget?
    private var startedAt = Date()
    private var generation = 0
    private var counter = 0

    // All entry points run on the main queue.

    func toggle() {
        switch state {
        case .idle: start()
        case .recording: finish()
        case .transcribing: NSSound.beep()
        }
    }

    /// Returns true if there was something to cancel (so Escape is consumed).
    func cancel() -> Bool {
        switch state {
        case .idle:
            return false
        case .recording:
            _ = recorder.stop()
            DiagLog.write("dictation id=\(counter) outcome=cancelled stage=recording")
        case .transcribing:
            DiagLog.write("dictation id=\(counter) outcome=cancelled stage=transcribing")
        }
        generation += 1
        state = .idle
        return true
    }

    private func start() {
        counter += 1
        target = FocusGuard.current()
        do {
            try recorder.start()
        } catch {
            DiagLog.write("dictation id=\(counter) outcome=error stage=record error=\"\(error.localizedDescription)\"")
            NSSound.beep()
            return
        }
        startedAt = Date()
        state = .recording
    }

    private func finish() {
        let samples = recorder.stop()
        let recMs = Int(Date().timeIntervalSince(startedAt) * 1000)
        let id = counter, gen = generation, target = target
        state = .transcribing

        Task {
            let t0 = Date()
            let result = await Result(catching: { try await self.transcriber.transcribe(samples) })
            let asrMs = Int(Date().timeIntervalSince(t0) * 1000)
            await MainActor.run {
                guard gen == self.generation else { return }  // cancelled while decoding
                let head = "dictation id=\(id) rec_ms=\(recMs) samples=\(samples.count) asr_ms=\(asrMs) target=\(target.map(String.init(describing:)) ?? "none")"
                switch result {
                case .failure(let error):
                    DiagLog.write("\(head) outcome=error stage=asr error=\"\(error.localizedDescription)\"")
                    NSSound.beep()
                    self.state = .idle
                case .success(let text) where text.isEmpty:
                    DiagLog.write("\(head) outcome=empty")
                    self.state = .idle
                case .success(let text):
                    self.lastTranscript = text
                    self.deliver(text, to: target, logHead: "\(head) chars=\(text.count)")
                }
            }
        }
    }

    private func deliver(_ text: String, to target: FocusTarget?, logHead: String) {
        guard let target, FocusGuard.matches(target) else {
            Injector.copyToClipboard(text)
            DiagLog.write("\(logHead) outcome=clipboard reason=focus_changed_before_paste")
            NSSound.beep()
            state = .idle
            return
        }
        injectQueue.async {
            let result = Injector.type(text, into: target)
            DispatchQueue.main.async {
                switch result {
                case .typed:
                    DiagLog.write("\(logHead) outcome=typed")
                case .focusChanged(let typed):
                    let rest = String(text.dropFirst(typed))
                    Injector.copyToClipboard(rest)
                    DiagLog.write("\(logHead) outcome=partial typed=\(typed) remainder_on_clipboard=\(rest.count)")
                    NSSound.beep()
                }
                self.state = .idle
            }
        }
    }
}

private extension Result where Failure == Error {
    init(catching body: () async throws -> Success) async {
        do { self = .success(try await body()) } catch { self = .failure(error) }
    }
}
