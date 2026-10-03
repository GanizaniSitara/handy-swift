import Foundation
import Speech
import AVFoundation

class DictationEngine {
    static let shared = DictationEngine()
    
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    
    private var isRecording = false
    private var focusTarget: FocusTarget?
    
    @MainActor
    func startRecording() {
        guard !isRecording else { return }
        
        // Request permissions if not already granted
        SFSpeechRecognizer.requestAuthorization { authStatus in
            if authStatus == .authorized {
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    if granted {
                        DispatchQueue.main.async {
                            self.beginAudioSession()
                        }
                    }
                }
            } else {
                NSLog("Speech recognition not authorized")
            }
        }
    }
    
    @MainActor
    private func beginAudioSession() {
        if audioEngine.isRunning {
            audioEngine.stop()
            recognitionRequest?.endAudio()
        }
        
        focusTarget = FocusGuard.shared.captureCurrentTarget()
        NSLog("🎙️ Started recording. Target: \(focusTarget?.appName ?? "Unknown")")
        isRecording = true
        
        do {
            let inputNode = audioEngine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)
            
            recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
            guard let recognitionRequest = recognitionRequest else { fatalError("Unable to create request") }
            
            // Allow on-device recognition for privacy and speed
            if #available(macOS 13.0, *) {
                recognitionRequest.requiresOnDeviceRecognition = true
            }
            
            // We want intermediate results for "speculative recognition" feel
            recognitionRequest.shouldReportPartialResults = false 
            // Actually, Handy.NET waits until key up to insert the text, so let's just get the final result.
            
            recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest, resultHandler: { result, error in
                var isFinal = false
                if let result = result {
                    isFinal = result.isFinal
                    NSLog("HandySwift: Partial transcript: \(result.bestTranscription.formattedString) (isFinal: \(isFinal))")
                    if isFinal {
                        let text = result.bestTranscription.formattedString
                        NSLog("HandySwift: 📝 Transcribed: \(text)")
                        DispatchQueue.main.async {
                            if let target = self.focusTarget {
                                Injector.shared.insertText(text, target: target)
                            } else {
                                NSLog("HandySwift: No focus target!")
                            }
                        }
                    }
                }
                
                if let error = error {
                    NSLog("HandySwift: Speech recognition error: \(error.localizedDescription)")
                }
                
                if error != nil || isFinal {
                    self.audioEngine.stop()
                    inputNode.removeTap(onBus: 0)
                    self.recognitionRequest = nil
                    self.recognitionTask = nil
                }
            })
            
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
                self.recognitionRequest?.append(buffer)
            }
            
            audioEngine.prepare()
            try audioEngine.start()
            
        } catch {
            NSLog("Audio engine failed to start: \(error.localizedDescription)")
            isRecording = false
        }
    }
    
    @MainActor
    func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        NSLog("⏹️ Stopped recording. Processing...")
        
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
    }
}
