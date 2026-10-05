import Cocoa
import AVFoundation

/// Hotkey → record → transcribe → type into the window that was focused when recording began.
final class Dictation {
    enum State { case idle, recording, transcribing }

    private(set) var state: State = .idle { didSet { onStateChange?(state) } }
    var onStateChange: ((State) -> Void)?
    let history = HistoryService(limit: Settings.load().historyLimit)
    var lastTranscript: String? { history.entries.last?.text }

    let transcriber = Transcriber()
    let recorder = Recorder()
    private let injectQueue = DispatchQueue(label: "HandySwift.inject")

    private var target: FocusTarget?
    private var startedAt = Date()
    private var generation = 0
    private var counter = 0
    private var micUsed = "default"
    private var watchdog: DispatchSourceTimer?

    // All entry points run on the main queue.

    func toggle() {
        switch state {
        case .idle: start()
        case .recording: finish()
        case .transcribing: NSSound.beep()
        }
    }

    var isActive: Bool { state != .idle }

    /// Filler/stutter filter, then domain corrections — the order Handy.NET uses.
    static func postProcess(_ raw: String, _ settings: Settings) -> (text: String, applied: [DomainCorrector.Applied]) {
        let filtered = TranscriptFilter.filter(raw, lang: settings.appLanguage, customFillerWords: settings.customFillerWords)
        return DomainCorrector.apply(filtered, settings.domainCorrections)
    }

    func cancel() {
        stopWatchdog()
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
        let settings = Settings.load()
        do {
            micUsed = try recorder.start(deviceName: settings.microphoneDeviceName)
        } catch {
            DiagLog.write("dictation id=\(counter) outcome=error stage=record error=\"\(error.localizedDescription)\"")
            NSSound.beep()
            return
        }
        startedAt = Date()
        state = .recording
        startWatchdog(settings)
    }

    private func finish() {
        stopWatchdog()
        let samples = recorder.stop()
        let recMs = Int(Date().timeIntervalSince(startedAt) * 1000)
        let peak = samples.reduce(Float(0)) { max($0, abs($1)) }
        let mic: String
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: mic = "granted"
        case .denied: mic = "denied"
        case .restricted: mic = "restricted"
        default: mic = "undetermined"
        }
        let id = counter, gen = generation, target = target

        // Parakeet rejects clips under 300 ms; an accidental double-tap shouldn't beep as an error.
        if samples.count < 16_000 * 3 / 10 {
            DiagLog.write("dictation id=\(id) rec_ms=\(recMs) samples=\(samples.count) outcome=too_short")
            state = .idle
            return
        }
        state = .transcribing

        Task {
            let t0 = Date()
            let result = await Result(catching: { try await self.transcriber.transcribe(samples) })
            let asrMs = Int(Date().timeIntervalSince(t0) * 1000)
            await MainActor.run {
                guard gen == self.generation else { return }  // cancelled while decoding
                let head = "dictation id=\(id) rec_ms=\(recMs) samples=\(samples.count) peak=\(String(format: "%.4f", peak)) mic=\(mic) device=\"\(self.micUsed)\" asr_ms=\(asrMs) target=\(target.map(String.init(describing:)) ?? "none")"
                switch result {
                case .failure(let error):
                    DiagLog.write("\(head) outcome=error stage=asr error=\"\(error.localizedDescription)\"")
                    NSSound.beep()
                    self.state = .idle
                case .success(let raw):
                    let settings = Settings.load()
                    let (text, rules) = Dictation.postProcess(raw, settings)
                    let fixes = rules.isEmpty ? "" : " corrections=\"\(rules.map { "\($0.from)->\($0.to)x\($0.count)" }.joined(separator: ";"))\""
                    if text.isEmpty {
                        DiagLog.write("\(head) raw_chars=\(raw.count) outcome=empty")
                        self.state = .idle
                        return
                    }
                    self.history.setLimit(settings.historyLimit)
                    self.history.add(text)
                    self.deliver(text, to: target, settings: settings,
                                 logHead: "\(head) raw_chars=\(raw.count) chars=\(text.count)\(fixes)")
                }
            }
        }
    }

    private func startWatchdog(_ settings: Settings) {
        guard settings.noInputTimeoutMs > 0 || settings.maxRecordingMs > 0 else { return }
        let policy = RecordingWatchdog(startedAt: ProcessInfo.processInfo.systemUptime,
                                       noInputTimeoutMs: settings.noInputTimeoutMs,
                                       maxRecordingMs: settings.maxRecordingMs)
        let id = counter
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler { [weak self] in
            guard let self, self.state == .recording, self.counter == id else { return }
            switch policy.action(now: ProcessInfo.processInfo.systemUptime, lastInputAt: self.recorder.lastInputAt) {
            case .none: break
            case .transcribe:
                DiagLog.write("dictation id=\(self.counter) watchdog=max_recording limit_ms=\(settings.maxRecordingMs)")
                self.finish()
            case .discard:
                self.stopWatchdog()
                _ = self.recorder.stop()
                self.generation += 1
                DiagLog.write("dictation id=\(self.counter) outcome=no_input discarded=true limit_ms=\(settings.noInputTimeoutMs)")
                NSSound.beep()
                self.state = .idle
            }
        }
        watchdog = timer
        timer.resume()
    }

    private func stopWatchdog() {
        watchdog?.cancel()
        watchdog = nil
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
