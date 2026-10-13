import AVFoundation
import DictationCore
import DictationMac
import XCTest

/// M6, M7: mic audio is transcribed while holding, partials reach the panel, nothing lingers on disk.
final class SpeechPipelineTests: XCTestCase {
    private func makePipeline(
        _ h: MacHarness,
        transcriber: SpeechTranscriber,
        audio: CountingAudio,
        focus: FocusSnapshot? = nil
    ) -> HoldPipeline {
        let snap = focus ?? h.field()
        return HoldPipeline(
            session: h.session,
            clock: h.clock,
            audio: audio,
            transcriber: transcriber,
            focus: FixedFocus { t in
                var s = snap
                s.timestamp = t
                return s
            }
        )
    }

    private func down(_ h: MacHarness) -> TapOutput {
        .talk(TalkKeyEvent(timestamp: h.clock.now, identity: .command(.left), isDown: true))
    }

    private func up(_ h: MacHarness) -> TapOutput {
        .talk(TalkKeyEvent(timestamp: h.clock.now, identity: .command(.left), isDown: false))
    }

    func test_M6_partialTranscriptAppearsInPanelWhileHolding() throws {
        let h = try MacHarness()
        let audio = CountingAudio()
        let speech = ScriptedTranscriber("hello there")
        let p = makePipeline(h, transcriber: speech, audio: audio)
        p.handle(down(h))
        XCTAssertEqual(audio.starts, 1)
        h.clock.advance(by: .milliseconds(200))
        p.partialTick()
        XCTAssertEqual(h.session.panel.text, "hello there")
    }

    func test_M6_releaseTranscribesFinalTextAndInsertsIntoFieldFromHoldStart() throws {
        let h = try MacHarness()
        let audio = CountingAudio()
        let speech = ScriptedTranscriber("so um ship it on friday")
        let p = makePipeline(h, transcriber: speech, audio: audio)
        p.handle(down(h))
        h.clock.advance(by: .milliseconds(600))
        p.handle(up(h))
        XCTAssertEqual(audio.stops, 1)
        h.clock.advance(by: .milliseconds(250))
        XCTAssertEqual(h.session.insertRequests.count, 1)
        XCTAssertEqual(h.session.insertRequests.first?.target.elementID, "field-1")
        XCTAssertEqual(h.session.insertRequests.first?.text.lowercased().contains("friday"), true)
    }

    func test_M6_otherKeyCancelStopsTheMicrophone() throws {
        let h = try MacHarness()
        let audio = CountingAudio()
        let p = makePipeline(h, transcriber: ScriptedTranscriber("x"), audio: audio)
        p.handle(down(h))
        p.handle(.talk(TalkKeyEvent(timestamp: h.clock.now, identity: .character("c"), isDown: true)))
        XCTAssertFalse(audio.running)
        h.clock.advance(by: .milliseconds(600))
        p.handle(up(h))
        h.clock.advance(by: .milliseconds(300))
        XCTAssertTrue(h.session.insertRequests.isEmpty)
    }

    func test_M7_whisperChunkFilesAreDeletedAndOutputParsed() throws {
        let h = try MacHarness()
        let scratch = h.directory.appendingPathComponent("scratch")
        let seen = h.directory.appendingPathComponent("seen.txt")
        // Records the -f argument and whether it existed, then prints whisper-style output.
        let fake = try h.script(named: "whisper-cli", body: """
        while [ $# -gt 0 ]; do
          if [ "$1" = "-f" ]; then shift; f="$1"; [ -s "$f" ] && echo "exists $f" >> "\(seen.path)"; fi
          shift
        done
        echo ""
        echo "[00:00:00.000 --> 00:00:01.500]   Hello there,"
        echo "[00:00:01.500 --> 00:00:02.000]   general Kenobi."
        """)
        let model = try h.script(named: "model.bin", body: "")
        let w = WhisperTranscriber(executable: fake, model: model, scratchDirectory: scratch)
        let text = w.transcribe(samples: [Float](repeating: 0.1, count: 8_000), sampleRate: 16_000)
        XCTAssertEqual(text, "Hello there, general Kenobi.")
        let log = try String(contentsOf: seen, encoding: .utf8)
        XCTAssertTrue(log.hasPrefix("exists "))
        let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: scratch.path)) ?? []
        XCTAssertEqual(leftovers, [])
    }

    func test_M6_blankAudioMarkersBecomeEmpty() {
        XCTAssertEqual(WhisperTranscriber.parseOutput("[BLANK_AUDIO]\n"), "")
        XCTAssertEqual(WhisperTranscriber.parseOutput(" [Music]\n hi there \n"), "hi there")
    }

    func test_M6_locatorFallsBackWhenWhisperOrModelMissing() throws {
        let h = try MacHarness()
        let missing = h.directory.appendingPathComponent("nope")
        XCTAssertNil(WhisperTranscriber.locate(executables: [missing], model: missing))
        let exe = try h.script(named: "whisper-cli", body: "exit 0")
        XCTAssertNil(WhisperTranscriber.locate(executables: [exe], model: missing))
        let model = try h.script(named: "m.bin", body: "")
        XCTAssertEqual(WhisperTranscriber.locate(executables: [missing, exe], model: model)?.executable, exe)
    }

    /// Real whisper-cli end to end, when installed with the base model.
    func test_M6_realWhisperTranscribesSpokenAudio() throws {
        let exe = URL(fileURLWithPath: "/opt/homebrew/bin/whisper-cli")
        let model = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Dictation/models/ggml-base.en.bin")
        guard let found = WhisperTranscriber.locate(executables: [exe], model: model) else {
            throw XCTSkip("whisper-cli or model not installed")
        }
        let h = try MacHarness()
        let aiff = h.directory.appendingPathComponent("say.caf")
        let say = Process()
        say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        say.arguments = ["-o", aiff.path, "--data-format=LEF32@16000", "hello world this is a test"]
        try say.run()
        say.waitUntilExit()
        let file = try AVAudioFile(forReading: aiff)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(
            pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)))
        try file.read(into: buffer)
        let samples = Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
        let scratch = h.directory.appendingPathComponent("scratch")
        let w = WhisperTranscriber(executable: found.executable, model: found.model, scratchDirectory: scratch)
        let text = try XCTUnwrap(w.transcribe(samples: samples, sampleRate: file.processingFormat.sampleRate))
        XCTAssertTrue(text.lowercased().contains("hello"), text)
        XCTAssertEqual((try? FileManager.default.contentsOfDirectory(atPath: scratch.path)) ?? [], [])
    }
}
