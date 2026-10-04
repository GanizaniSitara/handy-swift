import AVFoundation

/// Captures the default input device as 16 kHz mono Float32, the format Parakeet expects.
final class Recorder {
    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var samples: [Float] = []
    private var _level: Float = 0

    /// RMS of the most recent buffer, 0…1. Read by the overlay meter.
    var level: Float { lock.withLock { _level } }
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
            let rms = chunk.isEmpty ? 0 : (chunk.reduce(0) { $0 + $1 * $1 } / Float(chunk.count)).squareRoot()
            self.lock.withLock {
                self.samples.append(contentsOf: chunk)
                self._level = rms
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
        return lock.withLock { _level = 0; return samples }
    }
}
