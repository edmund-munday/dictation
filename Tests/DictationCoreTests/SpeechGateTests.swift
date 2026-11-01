@testable import DictationCore
import XCTest

/// R307: the audio-level speech gate and its text counterpart.
final class SpeechGateTests: XCTestCase {
    private let rate: Double = 16_000

    private func noise(_ seconds: Double, dbfs: Double) -> [Float] {
        var state: UInt64 = 3
        let scale = Float(pow(10, dbfs / 20) * 3.0.squareRoot())
        return (0..<Int(seconds * rate)).map { _ in
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return (Float(state >> 40) / Float(1 << 24) * 2 - 1) * scale
        }
    }

    private func tone(_ seconds: Double, dbfs: Double) -> [Float] {
        let a = Float(pow(10, dbfs / 20) * 2.0.squareRoot())
        return (0..<Int(seconds * rate)).map { a * Float(sin(2 * Double.pi * 180 * Double($0) / rate)) }
    }

    func test_R307_silenceAndRoomNoiseHaveNoSpeech() {
        XCTAssertFalse(SpeechGate.hasSpeech(samples: [], sampleRate: rate))
        XCTAssertFalse(SpeechGate.hasSpeech(samples: [Float](repeating: 0, count: 16_000), sampleRate: rate))
        XCTAssertFalse(SpeechGate.hasSpeech(samples: noise(1, dbfs: -62), sampleRate: rate))
        XCTAssertFalse(SpeechGate.hasSpeech(samples: noise(1, dbfs: -40), sampleRate: rate))
    }

    func test_R307_briefBurstIsNotSpeech() {
        let s = noise(0.5, dbfs: -66) + tone(0.06, dbfs: -20) + noise(0.5, dbfs: -66)
        XCTAssertFalse(SpeechGate.hasSpeech(samples: s, sampleRate: rate))
    }

    func test_R307_quietAndNormalSpeechPass() {
        for level in [-50.0, -35, -15] {
            let s = noise(0.3, dbfs: -70) + tone(0.4, dbfs: level) + noise(0.3, dbfs: -70)
            XCTAssertTrue(SpeechGate.hasSpeech(samples: s, sampleRate: rate), "\(level) dBFS")
        }
    }

    func test_R307_speechFillingTheWholeHoldPasses() {
        XCTAssertTrue(SpeechGate.hasSpeech(samples: tone(0.5, dbfs: -30), sampleRate: rate))
        XCTAssertTrue(SpeechGate.hasSpeech(samples: tone(0.5, dbfs: -30), sampleRate: 48_000))
    }

    func test_R307_meaningfulText() {
        for text in ["", " \n", "um", "you", "Subs by www.zeoranger.co.uk"] {
            XCTAssertFalse(SpeechGate.isMeaningfulText(text), text)
        }
        XCTAssertTrue(SpeechGate.isMeaningfulText("Ship it on Friday."))
    }
}
