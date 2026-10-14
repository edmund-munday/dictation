import DictationCore
import DictationMac
import XCTest

final class CaptureObserverTests: XCTestCase {
    func test_R243_holdOpensMicAndNotifiesStartThenReleaseNotifiesEndOnce() throws {
        let h = try MacHarness()
        let audio = CountingAudio()
        let pipeline = makePipeline(h, audio: audio)
        var notifications: [String] = []
        pipeline.onCaptureStart = {
            XCTAssertTrue(audio.running)
            XCTAssertTrue(pipeline.isCapturing)
            notifications.append("start")
        }
        pipeline.onCaptureEnd = {
            XCTAssertFalse(audio.running)
            XCTAssertFalse(pipeline.isCapturing)
            notifications.append("end")
        }

        pipeline.handle(talkKey(h, isDown: true))
        XCTAssertEqual(notifications, ["start"])
        h.clock.advance(by: .milliseconds(200))
        pipeline.partialTick()
        XCTAssertEqual(notifications, ["start"])

        h.clock.advance(by: .milliseconds(400))
        pipeline.handle(talkKey(h, isDown: false))
        XCTAssertEqual(notifications, ["start", "end"])

        pipeline.handle(talkKey(h, isDown: false))
        pipeline.partialTick()
        XCTAssertEqual(notifications, ["start", "end"])
        pipeline.onCaptureStart = nil
        pipeline.onCaptureEnd = nil
    }

    func test_R243_otherKeyCancelNotifiesEndOnceAndReleaseDoesNotNotifyAgain() throws {
        let h = try MacHarness()
        let audio = CountingAudio()
        let pipeline = makePipeline(h, audio: audio)
        var notifications: [String] = []
        pipeline.onCaptureStart = {
            XCTAssertTrue(audio.running)
            notifications.append("start")
        }
        pipeline.onCaptureEnd = {
            XCTAssertFalse(audio.running)
            notifications.append("end")
        }

        pipeline.handle(talkKey(h, isDown: true))
        XCTAssertEqual(notifications, ["start"])
        pipeline.handle(.talk(TalkKeyEvent(
            timestamp: h.clock.now, identity: .character("c"), isDown: true)))
        XCTAssertEqual(notifications, ["start", "end"])

        pipeline.handle(.talk(TalkKeyEvent(
            timestamp: h.clock.now, identity: .character("c"), isDown: false)))
        h.clock.advance(by: .milliseconds(600))
        pipeline.handle(talkKey(h, isDown: false))
        pipeline.partialTick()
        XCTAssertEqual(notifications, ["start", "end"])
    }

    func test_R243_blockedHoldDoesNotNotifyCaptureStartOrEnd() throws {
        let h = try MacHarness(latched: false)
        let audio = CountingAudio()
        let pipeline = makePipeline(h, audio: audio)
        var notifications: [String] = []
        pipeline.onCaptureStart = { notifications.append("start") }
        pipeline.onCaptureEnd = { notifications.append("end") }

        pipeline.handle(talkKey(h, isDown: true))
        XCTAssertFalse(audio.running)
        XCTAssertTrue(notifications.isEmpty)
        h.clock.advance(by: .milliseconds(600))
        pipeline.handle(talkKey(h, isDown: false))
        XCTAssertTrue(notifications.isEmpty)
    }

    func test_R243_microphoneOpenFailureDoesNotNotifyCaptureStartOrEnd() throws {
        let h = try MacHarness()
        let pipeline = makePipeline(h, audio: UnavailableMicrophone())
        var notifications: [String] = []
        pipeline.onCaptureStart = { notifications.append("start") }
        pipeline.onCaptureEnd = { notifications.append("end") }

        pipeline.handle(talkKey(h, isDown: true))
        XCTAssertFalse(pipeline.isCapturing)
        XCTAssertTrue(notifications.isEmpty)
        h.clock.advance(by: .milliseconds(600))
        pipeline.handle(talkKey(h, isDown: false))
        XCTAssertTrue(notifications.isEmpty)
    }

    private func makePipeline(_ h: MacHarness, audio: AudioSource) -> HoldPipeline {
        HoldPipeline(
            session: h.session, clock: h.clock, audio: audio,
            transcriber: ScriptedTranscriber(nil),
            focus: FixedFocus { time in
                var snapshot = h.field()
                snapshot.timestamp = time
                return snapshot
            })
    }

    private func talkKey(_ h: MacHarness, isDown: Bool) -> TapOutput {
        .talk(TalkKeyEvent(timestamp: h.clock.now, identity: .command(.left), isDown: isDown))
    }
}

/// An unavailable OS microphone, exercised through the public audio boundary.
private final class UnavailableMicrophone: AudioSource {
    private enum Failure: Error { case unavailable }
    let sampleRate: Double = 16_000

    func start() throws { throw Failure.unavailable }
    func stop() {}
    func snapshot() -> [Float] { [] }
}
