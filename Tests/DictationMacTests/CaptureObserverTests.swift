import DictationCore
import DictationMac
import Foundation
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

    func test_R248_captureEndSeesFastCommandAlreadyQueuedOnRelease() throws {
        let h = try MacHarness()
        let plugin = try PluginSpec.parse(Data(#"{"name":"capture","description":"test","triggers":["take a screenshot"],"action":{"type":"exec","path":"/bin/echo"},"confirm_delay_s":0}"#.utf8))
        h.session.setPlugins([plugin])
        h.session.setCleanupBackend(.gateway) // the local fast path (R236) applies to the gateway backend
        let audio = CountingAudio()
        let pipeline = makePipeline(h, audio: audio, transcript: "take a screenshot")
        var ends = 0
        pipeline.onCaptureEnd = {
            ends += 1
            XCTAssertFalse(audio.running)
            XCTAssertFalse(pipeline.isCapturing)
            XCTAssertEqual(h.session.commandRequests.count, 1)
            XCTAssertEqual(h.session.commandRequests.first?.plugin.name, "capture")
            XCTAssertEqual(h.session.commandRequests.first?.transcript, "take a screenshot")
            XCTAssertTrue(h.session.insertRequests.isEmpty)
        }
        pipeline.handle(talkKey(h, isDown: true))
        XCTAssertTrue(audio.running)
        XCTAssertTrue(h.session.commandRequests.isEmpty)
        h.clock.advance(by: .milliseconds(600))
        pipeline.handle(talkKey(h, isDown: false))
        XCTAssertEqual(ends, 1)
        pipeline.handle(talkKey(h, isDown: false))
        pipeline.partialTick()
        XCTAssertEqual(ends, 1)
        XCTAssertEqual(h.session.commandRequests.count, 1)
        pipeline.onCaptureEnd = nil
    }

    func test_R248_cancelByAnotherKeyNotifiesEndOnceWithoutRunningCommand() throws {
        let h = try MacHarness()
        let plugin = try PluginSpec.parse(Data(#"{"name":"capture","description":"test","triggers":["take a screenshot"],"action":{"type":"exec","path":"/bin/echo"},"confirm_delay_s":0}"#.utf8))
        h.session.setPlugins([plugin])
        h.session.setCleanupBackend(.gateway) // the local fast path (R236) applies to the gateway backend
        let audio = CountingAudio()
        let pipeline = makePipeline(h, audio: audio, transcript: "take a screenshot")
        var ends = 0
        pipeline.onCaptureEnd = {
            ends += 1
            XCTAssertFalse(audio.running)
            XCTAssertFalse(pipeline.isCapturing)
            XCTAssertTrue(h.session.commandRequests.isEmpty)
            XCTAssertTrue(h.session.insertRequests.isEmpty)
        }
        pipeline.handle(talkKey(h, isDown: true))
        h.clock.advance(by: .milliseconds(600))
        pipeline.partialTick()
        pipeline.handle(.talk(TalkKeyEvent(
            timestamp: h.clock.now, identity: .character("c"), isDown: true)))
        XCTAssertEqual(ends, 1)
        pipeline.handle(.talk(TalkKeyEvent(
            timestamp: h.clock.now, identity: .character("c"), isDown: false)))
        pipeline.handle(talkKey(h, isDown: false))
        pipeline.partialTick()
        XCTAssertEqual(ends, 1)
        XCTAssertTrue(h.session.commandRequests.isEmpty)
        XCTAssertTrue(h.session.insertRequests.isEmpty)
        pipeline.onCaptureEnd = nil
    }

    private func makePipeline(_ h: MacHarness, audio: AudioSource, transcript: String? = nil) -> HoldPipeline {
        HoldPipeline(
            session: h.session, clock: h.clock, audio: audio,
            transcriber: ScriptedTranscriber(transcript),
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
