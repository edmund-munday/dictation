import Foundation

/// R307: decides from the audio itself whether a hold heard any speech, so a silent
/// hold never reaches Whisper (which invents text from silence) or auto-send.
public enum SpeechGate {
    static let frameSeconds = 0.02
    /// Voiced frames needed in total; shorter bursts are key clicks and bumps.
    static let minimumVoicedSeconds = 0.12
    /// Frames quieter than this are never speech.
    static let absoluteFloorDb = -55.0
    /// Frames louder than this are always loud enough, whatever the room noise.
    static let alwaysLoudDb = -35.0
    /// How far above the hold's own noise floor a frame must be to count as voiced.
    static let aboveFloorDb = 10.0

    /// True when enough 20 ms frames are louder than both the absolute floor and the
    /// hold's noise floor (its 10th-percentile frame) plus 10 dB.
    public static func hasSpeech(samples: [Float], sampleRate: Double) -> Bool {
        guard sampleRate.isFinite, sampleRate > 0 else { return false }
        let frameLength = max(1, Int(sampleRate * frameSeconds))
        let needed = Int((minimumVoicedSeconds / frameSeconds).rounded(.up))
        let levels = frameLevels(samples, frameLength: frameLength)
        guard levels.count >= needed else { return false }
        let noiseFloor = levels.sorted()[levels.count / 10]
        let threshold = max(absoluteFloorDb, min(noiseFloor + aboveFloorDb, alwaysLoudDb))
        return levels.lazy.filter { $0 >= threshold }.count >= needed
    }

    /// False for text that must never be inserted on its own or auto-sent: empty,
    /// a lone filler, or a phrase Whisper invents from silence (R306).
    public static func isMeaningfulText(_ text: String) -> Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !Cleanup.wordTokens(text).isEmpty
            && !Cleanup.isLoneMutter(text)
    }

    private static func frameLevels(_ samples: [Float], frameLength: Int) -> [Double] {
        stride(from: 0, to: samples.count - frameLength + 1, by: frameLength).map { start in
            var sum: Double = 0
            for i in start..<(start + frameLength) {
                let s = Double(samples[i])
                sum += s * s
            }
            let rms = (sum / Double(frameLength)).squareRoot()
            return rms > 0 ? 20 * log10(rms) : -120
        }
    }
}
