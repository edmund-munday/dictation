import AVFoundation
import DictationCore
import DictationMac
import Foundation
import XCTest

final class ToggleTests: XCTestCase {
    func test_M5_ctrlOptSpaceIsRecognisedAsToggle() {
        let t = TalkKeyTranslator()
        let out = t.translate(RawKeyEvent(kind: .keyDown, keyCode: 49, flags: 0x40000 | 0x80000), at: .zero)
        XCTAssertEqual(out, [.toggle])
        let plain = t.translate(RawKeyEvent(kind: .keyDown, keyCode: 49, flags: 0x40000), at: .zero)
        XCTAssertFalse(plain.contains(.toggle))
        let withCmd = t.translate(
            RawKeyEvent(kind: .keyDown, keyCode: 49, flags: 0x40000 | 0x80000 | 0x100000), at: .zero)
        XCTAssertFalse(withCmd.contains(.toggle))
    }

    func test_R289_menuItemOffersPauseThenResumeThenPause() throws {
        let h = try MacHarness()
        let toggle = ToggleController(session: h.session)
        XCTAssertTrue(toggle.isEnabled)
        XCTAssertEqual(toggle.menuTitle, "Pause dictation (Ctrl-Opt-Space)")

        // The first menu item's action calls ToggleController.toggle().
        toggle.toggle()
        XCTAssertFalse(h.session.isLatchOn)
        XCTAssertEqual(toggle.menuTitle, "Resume dictation (Ctrl-Opt-Space)")

        toggle.toggle()
        XCTAssertTrue(h.session.isLatchOn)
        XCTAssertEqual(toggle.menuTitle, "Pause dictation (Ctrl-Opt-Space)")
    }

    func test_R289_ctrlOptSpaceUpdatesTheSameMenuItemInBothDirections() throws {
        let h = try MacHarness()
        let toggle = ToggleController(session: h.session)
        XCTAssertEqual(toggle.menuTitle, "Pause dictation (Ctrl-Opt-Space)")

        try pressShortcut(toggle, h)
        XCTAssertFalse(toggle.isEnabled)
        XCTAssertFalse(h.session.isLatchOn)
        XCTAssertEqual(toggle.menuTitle, "Resume dictation (Ctrl-Opt-Space)")

        try pressShortcut(toggle, h)
        XCTAssertTrue(toggle.isEnabled)
        XCTAssertTrue(h.session.isLatchOn)
        XCTAssertEqual(toggle.menuTitle, "Pause dictation (Ctrl-Opt-Space)")
    }

    func test_R290_menuAndShortcutShareThePausedIconAndRestoreTheActiveIcon() throws {
        let h = try MacHarness()
        let toggle = ToggleController(session: h.session)
        XCTAssertEqual(toggle.statusSymbolName, "mic.fill")
        toggle.toggle()
        XCTAssertEqual(toggle.statusSymbolName, "pause.circle")
        try pressShortcut(toggle, h)
        XCTAssertEqual(toggle.statusSymbolName, "mic.fill")
        try pressShortcut(toggle, h)
        XCTAssertEqual(toggle.statusSymbolName, "pause.circle")
        toggle.toggle()
        XCTAssertEqual(toggle.statusSymbolName, "mic.fill")
    }

    func test_R291_leftCommandWhilePausedNeverCapturesShowsTranscriptOrInserts() throws {
        let h = try MacHarness()
        let toggle = ToggleController(session: h.session)
        let audio = try PauseWAVInput()
        let pipeline = try makePipeline(h, audio: audio)
        toggle.toggle()

        pipeline.handle(key(h, down: true))
        XCTAssertEqual(h.session.micState, .closed)
        XCTAssertFalse(h.session.panel.isVisible)
        XCTAssertNil(h.session.panel.text)
        XCTAssertEqual(audio.starts, 0)
        XCTAssertFalse(pipeline.isCapturing)
        h.clock.advance(by: .seconds(audio.durationSeconds))
        pipeline.partialTick()
        XCTAssertFalse(h.session.panel.isVisible)
        XCTAssertNil(h.session.panel.text)
        pipeline.handle(key(h, down: false))
        h.clock.advance(by: .seconds(1))

        XCTAssertEqual(audio.starts, 0)
        XCTAssertFalse(audio.running)
        XCTAssertEqual(h.session.micState, .closed)
        XCTAssertFalse(h.session.panel.isVisible)
        XCTAssertNil(h.session.panel.text)
        XCTAssertTrue(h.session.utteranceRecords.isEmpty)
        XCTAssertTrue(h.session.insertRequests.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: h.directory.appendingPathComponent("whisper").path),
                       "No transcription should even create the Whisper scratch directory")
    }

    func test_R291_pausingInTheMiddleOfAHoldDiscardsItsVisibleTranscriptAndRelease() throws {
        let h = try MacHarness()
        let toggle = ToggleController(session: h.session)
        let audio = try PauseWAVInput()
        let pipeline = try makePipeline(h, audio: audio)
        pipeline.handle(key(h, down: true))
        XCTAssertEqual(h.session.micState, .open)
        XCTAssertTrue(h.session.panel.isVisible)
        h.clock.advance(by: .seconds(audio.durationSeconds))
        pipeline.partialTick()
        XCTAssertEqual(h.session.panel.text, "Sounds good, see you at 3.")
        XCTAssertTrue(h.session.insertRequests.isEmpty)

        try pressShortcut(toggle, h)
        XCTAssertEqual(h.session.micState, .closed)
        XCTAssertFalse(h.session.panel.isVisible)
        XCTAssertNil(h.session.panel.text)
        pipeline.partialTick()
        pipeline.handle(key(h, down: false))
        h.clock.advance(by: .seconds(1))

        XCTAssertFalse(audio.running)
        XCTAssertFalse(pipeline.isCapturing)
        XCTAssertEqual(h.session.micState, .closed)
        XCTAssertFalse(h.session.panel.isVisible)
        XCTAssertNil(h.session.panel.text)
        XCTAssertTrue(h.session.utteranceRecords.isEmpty)
        XCTAssertTrue(h.session.insertRequests.isEmpty, "Releasing a cancelled hold must not insert its earlier transcript")
    }

    func test_R291_pausingWithCleanupPendingDropsTheLateResultEvenAfterResume() throws {
        let h = try MacHarness()
        let toggle = ToggleController(session: h.session)
        let audio = try PauseWAVInput()
        let pipeline = try makePipeline(h, audio: audio)
        let network = PauseCleanupTransport()
        h.session.setGatewayCleaner(GatewayCleaner(
            config: GatewayConfig(url: try XCTUnwrap(URL(string: "https://cleanup.invalid")), key: "test-only"),
            transport: network))
        h.session.setCleanupBackend(.gateway)

        pipeline.handle(key(h, down: true))
        h.clock.advance(by: .seconds(audio.durationSeconds))
        pipeline.handle(key(h, down: false))
        XCTAssertEqual(network.requests, 1)
        XCTAssertTrue(h.session.panel.isVisible)
        XCTAssertEqual(h.session.panel.text, "Cleaning up…")
        XCTAssertTrue(h.session.insertRequests.isEmpty)

        toggle.toggle()
        XCTAssertEqual(h.session.micState, .closed)
        XCTAssertFalse(h.session.panel.isVisible)
        XCTAssertNil(h.session.panel.text)
        toggle.toggle()
        try network.reply(text: "Sounds good, see you at 3.")
        h.clock.advance(by: .seconds(1))
        XCTAssertTrue(toggle.isEnabled)
        XCTAssertFalse(h.session.panel.isVisible)
        XCTAssertNil(h.session.panel.text)
        XCTAssertTrue(h.session.utteranceRecords.isEmpty)
        XCTAssertTrue(h.session.insertRequests.isEmpty, "A result from before pause must not reappear on resume")
    }

    func test_R292_resumingAllowsTheNextLeftCommandHoldToDictateAndInsertNormally() throws {
        let h = try MacHarness()
        let toggle = ToggleController(session: h.session)
        let audio = try PauseWAVInput()
        let pipeline = try makePipeline(h, audio: audio)
        toggle.toggle()
        pipeline.handle(key(h, down: true))
        h.clock.advance(by: .milliseconds(600))
        pipeline.handle(key(h, down: false))
        XCTAssertEqual(audio.starts, 0)
        XCTAssertTrue(h.session.insertRequests.isEmpty)

        try pressShortcut(toggle, h)
        XCTAssertTrue(toggle.isEnabled)
        pipeline.handle(key(h, down: true))
        XCTAssertEqual(audio.starts, 1)
        XCTAssertTrue(audio.running)
        XCTAssertEqual(h.session.micState, .open)
        XCTAssertTrue(h.session.panel.isVisible)
        h.clock.advance(by: .seconds(audio.durationSeconds))
        pipeline.partialTick()
        XCTAssertEqual(h.session.panel.text, "Sounds good, see you at 3.")
        XCTAssertTrue(h.session.insertRequests.isEmpty, "Text stays in the panel until release")
        pipeline.handle(key(h, down: false))
        h.clock.advance(by: .milliseconds(250))

        XCTAssertFalse(audio.running)
        XCTAssertEqual(h.session.micState, .closed)
        XCTAssertFalse(h.session.panel.isVisible)
        XCTAssertEqual(h.session.utteranceRecords.map(\.raw), ["Sounds good, see you at 3."])
        XCTAssertEqual(h.session.insertRequests.map(\.text), ["Sounds good, see you at 3."])
        XCTAssertEqual(h.session.insertRequests.first?.target.elementID, "field-1")
    }

    private func pressShortcut(_ toggle: ToggleController, _ h: MacHarness) throws {
        let translator = TalkKeyTranslator()
        let outputs = translator.translate(
            RawKeyEvent(kind: .keyDown, keyCode: 49, flags: 0x40000 | 0x80000), at: h.clock.now)
        XCTAssertEqual(outputs, [.toggle])
        // AppModel.startTap routes .toggle to this controller, all other output to HoldPipeline.
        for output in outputs {
            if output == .toggle { toggle.toggle() }
        }
    }

    private func key(_ h: MacHarness, down: Bool) -> TapOutput {
        .talk(TalkKeyEvent(timestamp: h.clock.now, identity: .command(.left), isDown: down))
    }

    private func makePipeline(_ h: MacHarness, audio: PauseWAVInput) throws -> HoldPipeline {
        guard let whisper = WhisperTranscriber.locate(
            executables: WhisperTranscriber.defaultExecutables, model: WhisperTranscriber.defaultModel()) else {
            throw XCTSkip("whisper-cli or model not installed; recorded-audio pause scenarios require real Whisper")
        }
        h.session.setCleanupBackend(.off)
        let transcriber = WhisperTranscriber(executable: whisper.executable, model: whisper.model,
                                            scratchDirectory: h.directory.appendingPathComponent("whisper"))
        transcriber.initialPrompt = WhisperTranscriber.defaultPrompt
        return HoldPipeline(session: h.session, clock: h.clock, audio: audio, transcriber: transcriber,
                            focus: FixedFocus { time in
                                var snapshot = h.field()
                                snapshot.timestamp = time
                                return snapshot
                            })
    }
}

/// Recorded microphone input, with capture observability; never opens an audio device.
private final class PauseWAVInput: AudioSource {
    let sampleRate: Double
    let samples: [Float]
    var durationSeconds: Double { Double(samples.count) / sampleRate }
    private(set) var starts = 0
    private(set) var running = false

    init() throws {
        let url = URL(fileURLWithPath: #filePath).resolvingSymlinksInPath()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/audio/short-dictation.wav")
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        XCTAssertEqual(format.sampleRate, 16_000)
        XCTAssertEqual(format.channelCount, 1)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length)))
        try file.read(into: buffer)
        let channel = try XCTUnwrap(buffer.floatChannelData?[0])
        samples = Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
        sampleRate = format.sampleRate
        XCTAssertFalse(samples.isEmpty)
    }

    func start() throws { starts += 1; running = true }
    func stop() { running = false }
    func snapshot() -> [Float] { samples }
}

/// Only the remote cleanup boundary is deferred, so pause can race with a real pending result.
private final class PauseCleanupTransport: GatewayHTTPTransport {
    private(set) var requests = 0
    private var pending: ((Result<(Data, Int), Error>) -> Void)?

    func send(_ request: URLRequest, completion: @escaping (Result<(Data, Int), Error>) -> Void) {
        requests += 1
        XCTAssertNil(pending, "Only the release cleanup should be pending")
        pending = completion
    }

    func reply(text: String) throws {
        let completion = try XCTUnwrap(pending, "Release must have reached the remote cleanup API")
        pending = nil
        completion(.success((try JSONSerialization.data(withJSONObject: ["text": text]), 200)))
    }
}
