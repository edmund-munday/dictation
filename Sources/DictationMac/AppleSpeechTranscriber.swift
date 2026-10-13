import AVFoundation
import Foundation
import Speech

/// Apple's SFSpeechRecognizer forced on-device; the fallback when whisper is unavailable.
public final class AppleSpeechTranscriber: SpeechTranscriber {
    private let recognizer: SFSpeechRecognizer?
    public var name: String { "Apple on-device speech" }

    public init(locale: Locale = Locale(identifier: "en-US")) {
        recognizer = SFSpeechRecognizer(locale: locale)
    }

    /// True when the recognizer exists and supports on-device recognition.
    public var isAvailable: Bool {
        guard let recognizer else { return false }
        return recognizer.supportsOnDeviceRecognition
    }

    public func transcribe(samples: [Float], sampleRate: Double) -> String? {
        guard let recognizer, recognizer.supportsOnDeviceRecognition, !samples.isEmpty else { return nil }
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))
        else { return nil }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { src in
            buffer.floatChannelData![0].update(from: src.baseAddress!, count: samples.count)
        }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = false
        request.append(buffer)
        request.endAudio()

        let done = DispatchSemaphore(value: 0)
        var text: String?
        let lock = NSLock()
        let task = recognizer.recognitionTask(with: request) { result, error in
            lock.lock()
            defer { lock.unlock() }
            if let result, result.isFinal {
                text = result.bestTranscription.formattedString
                done.signal()
            } else if error != nil {
                done.signal()
            }
        }
        if done.wait(timeout: .now() + 15) == .timedOut {
            task.cancel()
        }
        lock.lock()
        defer { lock.unlock() }
        return text
    }
}
