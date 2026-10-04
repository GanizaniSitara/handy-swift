import AVFoundation

/// Captures the default input device as 16 kHz mono Float32, the format Parakeet expects.
final class Recorder {
    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var samples: [Float] = []
    private var _levels = [Float](repeating: 0, count: 5)

    /// Five 0…1 bar levels from the most recent buffer. Read by the overlay meter.
    var levels: [Float] { lock.withLock { _levels } }
    private let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!

    func start() throws {
        lock.withLock { samples.removeAll(keepingCapacity: true) }

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard let converter = AVAudioConverter(from: format, to: target) else {
            throw NSError(domain: "HandySwift", code: 1, userInfo: [NSLocalizedDescriptionKey: "no converter from \(format)"])
        }

        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * self.target.sampleRate / format.sampleRate) + 1
            guard let out = AVAudioPCMBuffer(pcmFormat: self.target, frameCapacity: capacity) else { return }
            var fed = false
            var error: NSError?
            converter.convert(to: out, error: &error) { _, status in
                if fed { status.pointee = .noDataNow; return nil }
                fed = true
                status.pointee = .haveData
                return buffer
            }
            guard error == nil, let data = out.floatChannelData else { return }
            let chunk = UnsafeBufferPointer(start: data[0], count: Int(out.frameLength))
            let levels = Recorder.barLevels(chunk, bars: 5)
            self.lock.withLock {
                self.samples.append(contentsOf: chunk)
                self._levels = levels
            }
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw error
        }
    }

    /// Stops capture and returns everything recorded since `start()`.
    func stop() -> [Float] {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        return lock.withLock { _levels = _levels.map { _ in 0 }; return samples }
    }

    /// RMS per equal slice, mapped -55 dBFS → 0 … -8 dBFS → 1 with Handy.NET's curve.
    static func barLevels(_ chunk: UnsafeBufferPointer<Float>, bars: Int) -> [Float] {
        let per = max(1, chunk.count / bars)
        return (0..<bars).map { b in
            let start = b * per
            let end = b == bars - 1 ? chunk.count : min(chunk.count, start + per)
            guard end > start else { return 0 }
            var sum: Float = 0
            for i in start..<end { sum += chunk[i] * chunk[i] }
            let rms = (sum / Float(end - start)).squareRoot()
            let db = rms > 1e-6 ? 20 * log10(rms) : -80
            let norm = min(max((db + 55) / 47, 0), 1)
            return min(pow(norm * 1.3, 0.7), 1)
        }
    }
}
