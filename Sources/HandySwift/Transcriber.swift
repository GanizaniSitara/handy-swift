import Foundation
import FluidAudio

/// Parakeet TDT v3 on CoreML via FluidAudio — the same model family Handy and Handy.NET use.
actor Transcriber {
    private var manager: AsrManager?
    private var loading: Task<AsrManager, Error>?

    /// Downloads (first run only) and loads the model. Safe to call repeatedly.
    func load() async throws -> AsrManager {
        if let manager { return manager }
        if loading == nil {
            loading = Task {
                let models = try await AsrModels.downloadAndLoad(version: .v3)
                let m = AsrManager(config: .default)
                try await m.loadModels(models)
                return m
            }
        }
        do {
            let m = try await loading!.value
            manager = m
            return m
        } catch {
            loading = nil
            throw error
        }
    }

    func transcribe(_ samples: [Float]) async throws -> String {
        let asr = try await load()
        var state = TdtDecoderState.make(decoderLayers: await asr.decoderLayerCount)
        return try await asr.transcribe(samples, decoderState: &state).text
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func transcribe(file: URL) async throws -> String {
        let asr = try await load()
        var state = TdtDecoderState.make(decoderLayers: await asr.decoderLayerCount)
        return try await asr.transcribe(file, decoderState: &state).text
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
