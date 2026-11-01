import DictationCore
import DictationMac
import XCTest

/// R307: a hold with no meaningful speech never reaches Whisper, insert, Copy or auto-send.
final class SilentHoldTests: XCTestCase {
    private final class Keys: ReturnKeySender { var returns = 0; func sendReturn() { returns += 1 } }

    private struct Run {
        let transcriber: ScriptedTranscriber
        let session: Session
        let keys: Keys
    }

    /// Holds the talk key in a chat app over `samples`, with a partial tick mid-hold.
    private func hold(_ samples: [Float], heard: String = "Subs by www.zeoranger.co.uk") throws -> Run {
        let h = try MacHarness()
        let audio = CountingAudio()
        audio.samples = samples
        let speech = ScriptedTranscriber(heard)
        let chat = h.field(.textArea, id: "chat")
        let p = HoldPipeline(session: h.session, clock: h.clock, audio: audio, transcriber: speech,
                             focus: FixedFocus { t in var s = chat; s.timestamp = t; return s })
        let keys = Keys()
        let c = InsertionCoordinator(session: h.session, inserter: RecordingInserter(succeeds: true))
        c.autoSend = AutoSendPolicy(enabled: true)
        c.keySender = keys
        c.bundleForPID = { _ in "com.tinyspeck.slackmacgap" }
        c.schedule = { _, work in work() }
        p.handle(.talk(TalkKeyEvent(timestamp: h.clock.now, identity: .command(.left), isDown: true)))
        h.clock.advance(by: .milliseconds(600))
        p.partialTick()
        h.clock.advance(by: .milliseconds(600))
        p.handle(.talk(TalkKeyEvent(timestamp: h.clock.now, identity: .command(.left), isDown: false)))
        h.clock.advance(by: .seconds(5))
        c.poll()
        return Run(transcriber: speech, session: h.session, keys: keys)
    }

    private func assertNothingHappened(_ run: Run, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(run.transcriber.calls, 0, "Whisper must not run", file: file, line: line)
        XCTAssertTrue(run.session.insertRequests.isEmpty, file: file, line: line)
        XCTAssertTrue(run.session.commandRequests.isEmpty, file: file, line: line)
        XCTAssertEqual(run.keys.returns, 0, file: file, line: line)
        XCTAssertFalse(run.session.panel.isVisible, file: file, line: line)
        XCTAssertNil(run.session.panel.copyText, file: file, line: line)
    }

    func test_R307_digitalSilenceHoldRunsNothing() throws {
        assertNothingHappened(try hold(TestSignal.silence(seconds: 1.2)))
    }

    func test_R307_quietRoomHoldRunsNothing() throws {
        assertNothingHappened(try hold(TestSignal.noise(seconds: 1.2, dbfs: -62)))
    }

    func test_R307_steadyFanNoiseHoldRunsNothing() throws {
        assertNothingHappened(try hold(TestSignal.noise(seconds: 1.2, dbfs: -45)))
    }

    func test_R307_keyClickInSilenceRunsNothing() throws {
        let click = TestSignal.voice(seconds: 0.04, dbfs: -20)
        let samples = TestSignal.noise(seconds: 0.6, dbfs: -65) + click + TestSignal.noise(seconds: 0.6, dbfs: -65)
        assertNothingHappened(try hold(samples))
    }

    func test_R307_quietRealSpeechStillInsertsAndSends() throws {
        let run = try hold(TestSignal.phrase(voiceDbfs: -48), heard: "see you at five")
        XCTAssertGreaterThan(run.transcriber.calls, 0)
        XCTAssertEqual(run.session.insertRequests.count, 1)
        XCTAssertEqual(run.keys.returns, 1)
    }

    func test_R307_normalSpeechStillInsertsAndSends() throws {
        let run = try hold(TestSignal.phrase(voiceDbfs: -25), heard: "ship it on friday")
        XCTAssertEqual(run.session.insertRequests.count, 1)
        XCTAssertEqual(run.keys.returns, 1)
    }

    func test_R307_autoSendRefusesEmptyMutterAndSilencePhrases() {
        let p = AutoSendPolicy(enabled: true)
        let slack = "com.tinyspeck.slackmacgap"
        for text in ["", "   ", "um", "uh hmm", "you", "Thanks for watching!", "Subs by www.zeoranger.co.uk"] {
            XCTAssertFalse(p.shouldSend(bundleID: slack, inserted: true, text: text, allowed: true), text)
        }
        XCTAssertTrue(p.shouldSend(bundleID: slack, inserted: true, text: "Thank you, see you soon.", allowed: true))
    }
}
