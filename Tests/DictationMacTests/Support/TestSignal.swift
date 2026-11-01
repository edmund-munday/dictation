import Foundation

/// Synthetic microphone audio at 16 kHz for gate tests.
enum TestSignal {
    static let rate: Double = 16_000

    static func silence(seconds: Double) -> [Float] {
        [Float](repeating: 0, count: Int(seconds * rate))
    }

    /// Deterministic white noise with the given RMS level in dBFS.
    static func noise(seconds: Double, dbfs: Double, seed: UInt64 = 7) -> [Float] {
        var state = seed
        let rms = Float(pow(10, dbfs / 20))
        // Uniform in [-1, 1] has RMS 1/sqrt(3).
        let scale = rms * Float(3.0.squareRoot())
        return (0..<Int(seconds * rate)).map { _ in
            state = state &* 6364136223846793005 &+ 1442695040888963407
            let unit = Float(state >> 40) / Float(1 << 24)
            return (unit * 2 - 1) * scale
        }
    }

    /// A 200 Hz tone with the given RMS level in dBFS, standing in for voiced speech.
    static func voice(seconds: Double, dbfs: Double) -> [Float] {
        let amplitude = Float(pow(10, dbfs / 20) * 2.0.squareRoot())
        return (0..<Int(seconds * rate)).map { i in
            amplitude * Float(sin(2 * Double.pi * 200 * Double(i) / rate))
        }
    }

    /// Room noise with a phrase of voice in the middle.
    static func phrase(voiceDbfs: Double, roomDbfs: Double = -70) -> [Float] {
        let lead = noise(seconds: 0.3, dbfs: roomDbfs)
        let tail = noise(seconds: 0.3, dbfs: roomDbfs, seed: 11)
        let room = noise(seconds: 0.6, dbfs: roomDbfs, seed: 13)
        let speech = zip(voice(seconds: 0.6, dbfs: voiceDbfs), room).map(+)
        return lead + speech + tail
    }
}
