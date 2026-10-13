import AppKit
import DictationCore
import DictationMac
import Foundation

/// Transcriber double returning scripted text and recording what it was given.
final class ScriptedTranscriber: SpeechTranscriber {
    var name: String { "scripted" }
    var nextText: String?
    private(set) var calls = 0

    init(_ text: String?) { nextText = text }

    func transcribe(samples: [Float], sampleRate: Double) -> String? {
        calls += 1
        return nextText
    }
}

/// Audio double: counts starts/stops, returns one second of silence.
final class CountingAudio: AudioSource {
    private(set) var starts = 0
    private(set) var stops = 0
    private(set) var running = false
    let sampleRate: Double = 16_000

    func start() throws {
        starts += 1
        running = true
    }

    func stop() {
        stops += 1
        running = false
    }

    func snapshot() -> [Float] { [Float](repeating: 0, count: 16_000) }
}

/// Focus double returning a fixed snapshot (timestamped by the caller's clock).
final class FixedFocus: FocusProvider {
    var snapshot: (Duration) -> FocusSnapshot
    init(_ snapshot: @escaping (Duration) -> FocusSnapshot) { self.snapshot = snapshot }
    func currentFocus(at time: Duration) -> FocusSnapshot { snapshot(time) }
}

/// Inserter double: records insert calls and returns a scripted result.
final class RecordingInserter: TextInserter {
    var succeeds: Bool
    private(set) var inserted: [(text: String, target: FocusIdentity)] = []
    init(succeeds: Bool) { self.succeeds = succeeds }

    func insert(_ text: String, into target: FocusIdentity, replacingSelection: Bool) -> Bool {
        inserted.append((text, target))
        return succeeds
    }
}
