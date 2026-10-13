import AVFoundation
import Foundation

/// Microphone capture with AVAudioEngine; samples stay in memory only (M7).
public final class MicrophoneCapture: AudioSource {
    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var samples: [Float] = []
    private var running = false
    public private(set) var sampleRate: Double = 48_000

    public init() {}

    public func start() throws {
        lock.lock()
        samples.removeAll(keepingCapacity: true)
        lock.unlock()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        sampleRate = format.sampleRate
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
            guard let self, let channels = buffer.floatChannelData else { return }
            let count = Int(buffer.frameLength)
            let chans = Int(buffer.format.channelCount)
            var mono = [Float](repeating: 0, count: count)
            for c in 0..<chans {
                let p = channels[c]
                for i in 0..<count { mono[i] += p[i] / Float(chans) }
            }
            self.lock.lock()
            self.samples.append(contentsOf: mono)
            self.lock.unlock()
        }
        engine.prepare()
        try engine.start()
        running = true
    }

    public func stop() {
        guard running else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        running = false
    }

    public func snapshot() -> [Float] {
        lock.lock()
        defer { lock.unlock() }
        return samples
    }

    /// Clears captured audio from memory.
    public func wipe() {
        lock.lock()
        samples = []
        lock.unlock()
    }
}
