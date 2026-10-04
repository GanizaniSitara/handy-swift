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

    var isActive: Bool { state != .idle }

    func cancel() {
        switch state {
        case .idle:
            return
        case .recording:
            _ = recorder.stop()
            DiagLog.write("dictation id=\(counter) outcome=cancelled stage=recording")
        case .transcribing:
            DiagLog.write("dictation id=\(counter) outcome=cancelled stage=transcribing")
        }
        generation += 1
        state = .idle
    }

    /// Types the last transcript into whatever is focused now — recovery when a paste was refused.
    func retypeLast() {
        guard state == .idle, let text = lastTranscript, let target = FocusGuard.current() else { NSSound.beep(); return }
        let delay = Settings.load().charDelayMs
        injectQueue.async {
            let result = Injector.type(text, into: target, charDelayMs: delay)
            DiagLog.write("retype-last chars=\(text.count) target=\(target) outcome=\(result)")
        }
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
                case .success(let raw):
                    let settings = Settings.load()
                    let filtered = TranscriptFilter.filter(raw, lang: settings.appLanguage, customFillerWords: settings.customFillerWords)
                    let (text, rules) = DomainCorrector.apply(filtered, settings.domainCorrections)
                    let fixes = rules.isEmpty ? "" : " corrections=\"\(rules.map { "\($0.from)->\($0.to)x\($0.count)" }.joined(separator: ";"))\""
                    if text.isEmpty {
                        DiagLog.write("\(head) raw_chars=\(raw.count) outcome=empty")
                        self.state = .idle
                        return
                    }
                    self.lastTranscript = text
                    self.deliver(text, to: target, settings: settings,
                                 logHead: "\(head) raw_chars=\(raw.count) chars=\(text.count)\(fixes)")
                }
            }
        }
    }

    private func deliver(_ text: String, to target: FocusTarget?, settings: Settings, logHead: String) {
        guard let target else {
            Injector.copyToClipboard(text)
            DiagLog.write("\(logHead) outcome=clipboard reason=no_target")
            NSSound.beep()
            state = .idle
            return
        }
        let policy = Injector.FocusPolicy.parse(settings.pasteFocusPolicy)
        injectQueue.async {
            let result = Injector.type(text, into: target, charDelayMs: settings.charDelayMs, policy: policy)
            DispatchQueue.main.async {
                switch result {
                case .typed(let restores):
                    DiagLog.write("\(logHead) policy=\(policy.rawValue) focus_restores=\(restores) outcome=typed")
                case .focusChanged(let typed):
                    let rest = String(text.dropFirst(typed))
                    Injector.copyToClipboard(rest)
                    let now = FocusGuard.current().map(String.init(describing:)) ?? "none"
                    DiagLog.write("\(logHead) policy=\(policy.rawValue) outcome=\(typed == 0 ? "clipboard" : "partial") typed=\(typed) remainder_on_clipboard=\(rest.count) focused_now=\(now)")
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
