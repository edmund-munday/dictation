import AVFoundation
import DictationCore
import DictationMac
import Foundation
import XCTest

final class TailTranscriptionPipelineTests: XCTestCase {
    func test_R258_recordedFinalOutputParsesToSegmentsAndTheExistingPlainText() throws {
        for name in ["long-dictation", "long-scratch", "long-plain", "short-dictation"] {
            let fixture = try recording(name)
            let segments = WhisperTranscriber.parseSegments(fixture.final_stdout)
            XCTAssertEqual(segments.count, fixture.final_segments.count, name)
            for (actual, expected) in zip(segments, fixture.final_segments) {
                XCTAssertEqual(actual.start, expected.start, accuracy: 0.01, name)
                XCTAssertEqual(actual.end, expected.end, accuracy: 0.01, name)
                XCTAssertEqual(actual.text, expected.text, name)
            }
            XCTAssertEqual(segments.map(\.text).joined(separator: " "),
                           WhisperTranscriber.parseOutput(fixture.final_stdout), name)
        }
    }

    func test_R258_segmentParsingDropsSpeechAnnotations() {
        let output = """
        [00:00:00.000 --> 00:00:01.000]  [BLANK_AUDIO]
        [00:00:01.000 --> 00:00:02.000]  (wind)
        [00:00:02.000 --> 00:00:03.250]  (wind)Hello[Music].
        [00:00:03.250 --> 00:00:04.000]  [Music]
        """
        let segments = WhisperTranscriber.parseSegments(output)
        XCTAssertEqual(segments, [TranscriptSegment(start: 2, end: 3.25, text: "Hello.")])
        XCTAssertEqual(segments.map(\.text).joined(separator: " "), WhisperTranscriber.parseOutput(output))
    }

    func test_R260_longPlainReleaseTranscribesOnlyTheTailAndInsertsAccurateText() throws {
        try assertTailRelease("long-plain", offset: 17.0, requiredPhrases: ["later this week"])
    }

    func test_R260_longDictationReleaseKeepsTheThursdayCorrectionWithoutRepeatingTheJoin() throws {
        try assertTailRelease("long-dictation", offset: 19.88, requiredPhrases: ["Thursday", "not Friday"])
    }

    func test_R261_disabledTailSettingUsesExactlyOneFullReleaseTranscription() throws {
        try assertFullRelease("long-plain", enabled: false)
    }

    func test_R261_shortDictationWithoutAStablePrefixUsesExactlyOneFullReleaseTranscription() throws {
        try assertFullRelease("short-dictation", enabled: true)
    }

    func test_R261_emptyReleaseTailFallsBackToExactlyOneFullTranscription() throws {
        try assertFullRelease("long-dictation", enabled: true, emptyTail: true)
    }

    func test_R261_nonSegmentedTranscriberKeepsTodaysFullReleaseAndInsertedText() throws {
        let fixture = try recording("long-plain")
        let h = try MacHarness()
        h.session.setCleanupBackend(.off)
        let audio = try audio("long-plain")
        let today = WhisperTranscriber.parseOutput(fixture.final_stdout)
        let scripted = ScriptedTranscriber(today)
        let speech = FullSampleRecorder(scripted)
        let pipeline = pipeline(h, audio: audio, transcriber: speech, enabled: true)
        pipeline.handle(key(h, down: true))
        var previousTime = 0.0
        for partial in fixture.partials {
            audio.expose(seconds: partial.t)
            h.clock.advance(by: .seconds(partial.t - previousTime))
            pipeline.partialTick()
            previousTime = partial.t
        }
        audio.exposeAll()
        h.clock.advance(by: .seconds(audio.durationSeconds - previousTime))
        let before = speech.sampleCounts.count
        pipeline.handle(key(h, down: false))
        h.clock.advance(by: .milliseconds(250))
        XCTAssertEqual(Array(speech.sampleCounts.dropFirst(before)), [audio.samples.count])
        XCTAssertEqual(scripted.calls, fixture.partials.count + 1)
        XCTAssertEqual(h.session.utteranceRecords.map(\.raw), [today])
        XCTAssertEqual(h.session.insertRequests.map(\.text), try todaysInsert(today, audio: audio))
    }

    func test_R263_tailReleasePreservesBackgroundCleanupAndSendsTheWholeCrossSentenceCorrection() throws {
        let fixture = try recording("long-dictation")
        let h = try MacHarness()
        let network = TailCleanupTransport()
        h.session.setGatewayCleaner(GatewayCleaner(
            config: GatewayConfig(url: URL(string: "https://cleanup.invalid")!, key: "test-only"), transport: network))
        h.session.setCleanupBackend(.gateway)
        h.session.setPlugins([try PluginSpec.parse(Data(#"{"name":"screenshot","description":"Capture the screen","triggers":["take a screenshot"],"args":{},"action":{"type":"exec","path":"/bin/echo"},"confirm_delay_s":0}"#.utf8))])
        let audio = try audio("long-dictation")
        let speech = RecordedSegmentReplay(whisper: try whisper(h))
        let pipeline = pipeline(h, audio: audio, transcriber: speech, enabled: true)
        pipeline.handle(key(h, down: true))
        let sawCleanedPanel = replay(fixture, audio: audio, speech: speech, pipeline: pipeline, harness: h)
        XCTAssertGreaterThanOrEqual(network.requests.count, 2, "R249 background sentence requests still run")
        XCTAssertTrue(sawCleanedPanel, "Completed background sentences appear in the panel while held")
        XCTAssertTrue(network.requests.contains { $0.user == "Sales in the north region went up by about 12%, which is really good news for the team." })
        XCTAssertTrue(h.session.insertRequests.isEmpty)
        let backgroundCount = network.requests.count
        network.deferReplies = true
        speech.isReleasing = true
        pipeline.handle(key(h, down: false))
        XCTAssertEqual(speech.releaseCalls.map(\.kind), [.segments], "Exercise the tail path with cleanup enabled")
        XCTAssertEqual(network.requests.count, backgroundCount + 1)
        let release = try XCTUnwrap(network.requests.last)
        XCTAssertTrue(release.user.hasPrefix(expectedPrefix("long-dictation")), "R251 sends the full raw text")
        XCTAssertTrue(release.user.contains("Actually, I mean"))
        XCTAssertTrue(release.user.contains("Thursday"))
        XCTAssertTrue(release.user.contains("not Friday"))
        XCTAssertLessThanOrEqual(WordErrorRate.measure(reference: WhisperTranscriber.parseOutput(fixture.final_stdout),
                                                      hypothesis: release.user), 0.05)
        XCTAssertEqual(h.session.panel.text, "Cleaning up…")
        XCTAssertTrue(h.session.insertRequests.isEmpty, "Wait for the release cleanup reply")
        for request in network.requests {
            XCTAssertFalse(request.system.contains("take a screenshot"), "Long holds exclude plugin routing")
        }
        h.clock.advance(by: .milliseconds(200))
        try network.finishRelease()
        h.clock.advance(by: .zero)
        XCTAssertEqual(h.session.utteranceRecords.map(\.raw), [release.user])
        XCTAssertEqual(h.session.insertRequests.map(\.text), [TailCleanupTransport.cleaned(release.user)],
                       "R251 replaces the earlier cleaned sentences; do not prepend them again")
        XCTAssertEqual(h.session.insertRequests.first?.target.elementID, "field-1")
        XCTAssertEqual(h.session.insertRequests.first?.autoSendAllowed, true)
        XCTAssertTrue(h.session.commandRequests.isEmpty)
        h.clock.advance(by: .seconds(1))
        XCTAssertEqual(network.requests.count, backgroundCount + 1)
        XCTAssertEqual(h.session.insertRequests.count, 1)
    }

    func test_R264_tailSettingUsesThePersistedFastReleaseKey() {
        XCTAssertEqual(HoldPipeline.tailTranscriptionDefaultKey, "tailTranscriptionOnRelease")
    }

    private func assertTailRelease(_ name: String, offset: Double, requiredPhrases: [String]) throws {
        let fixture = try recording(name)
        let h = try MacHarness()
        h.session.setCleanupBackend(.off)
        let audio = try audio(name)
        let speech = RecordedSegmentReplay(whisper: try whisper(h))
        let pipeline = pipeline(h, audio: audio, transcriber: speech, enabled: true)
        pipeline.handle(key(h, down: true))
        replay(fixture, audio: audio, speech: speech, pipeline: pipeline, harness: h)
        XCTAssertEqual(speech.segmentedPartialCalls, fixture.partials.count)
        XCTAssertEqual(speech.plainPartialCalls, 0)
        XCTAssertFalse(h.session.panel.text?.isEmpty ?? true)
        XCTAssertTrue(h.session.insertRequests.isEmpty)
        speech.isReleasing = true
        pipeline.handle(key(h, down: false))
        h.clock.advance(by: .milliseconds(250))

        XCTAssertEqual(speech.releaseCalls.count, 1, name)
        let call = try XCTUnwrap(speech.releaseCalls.first)
        XCTAssertEqual(call.kind, .segments)
        XCTAssertLessThan(call.samples.count, audio.samples.count)
        XCTAssertEqual(call.sampleRate, audio.sampleRate)
        let start = Double(audio.samples.count - call.samples.count) / audio.sampleRate
        XCTAssertEqual(start, offset - 0.5, accuracy: 0.15, name)
        XCTAssertEqual(call.samples, Array(audio.samples.suffix(call.samples.count)), "Transcribe the actual WAV suffix")
        let prefix = expectedPrefix(name)
        XCTAssertEqual(call.prompt, speech.initialPrompt + " " + prefix)
        XCTAssertFalse(call.text?.isEmpty ?? true)
        XCTAssertEqual(h.session.insertRequests.count, 1)
        XCTAssertEqual(h.session.insertRequests.first?.target.elementID, "field-1")
        // Session records the final recognizer text before local cleanup removes
        // fillers/correction cues, even when the cleanup backend is off.
        XCTAssertEqual(h.session.utteranceRecords.count, 1)
        let final = try XCTUnwrap(h.session.utteranceRecords.first).raw
        XCTAssertLessThanOrEqual(WordErrorRate.measure(reference: WhisperTranscriber.parseOutput(fixture.final_stdout),
                                                      hypothesis: final), 0.05, "\(name): \(final)")
        XCTAssertTrue(final.hasPrefix(prefix), "Keep the stable prefix's punctuation and capitalization")
        for phrase in requiredPhrases { XCTAssertTrue(final.contains(phrase), final) }
        let prefixWords = WordErrorRate.words(prefix)
        let tailWords = WordErrorRate.words(String(final.dropFirst(prefix.count)))
        let limit = min(8, prefixWords.count, tailWords.count)
        if limit > 0 {
            for count in 1...limit {
                XCTAssertNotEqual(Array(prefixWords.suffix(count)), Array(tailWords.prefix(count)),
                                  "No repeated \(count)-word overlap at the join: \(final)")
            }
        }
    }

    private func assertFullRelease(_ name: String, enabled: Bool, emptyTail: Bool = false) throws {
        let fixture = try recording(name)
        let h = try MacHarness()
        h.session.setCleanupBackend(.off)
        let audio = try audio(name)
        let speech = RecordedSegmentReplay(whisper: try whisper(h))
        speech.emptyReleaseTail = emptyTail
        let pipeline = pipeline(h, audio: audio, transcriber: speech, enabled: enabled)
        pipeline.handle(key(h, down: true))
        replay(fixture, audio: audio, speech: speech, pipeline: pipeline, harness: h)
        speech.isReleasing = true
        pipeline.handle(key(h, down: false))
        h.clock.advance(by: .milliseconds(250))
        XCTAssertEqual(speech.releaseCalls.map(\.kind), emptyTail ? [.segments, .full] : [.full])
        let full = try XCTUnwrap(speech.releaseCalls.last)
        XCTAssertEqual(full.samples, audio.samples)
        XCTAssertEqual(full.sampleRate, audio.sampleRate)
        XCTAssertEqual(full.prompt, speech.initialPrompt, "Full fallback uses today's default vocabulary prompt")
        let today = try XCTUnwrap(full.text)
        XCTAssertFalse(today.isEmpty)
        XCTAssertEqual(h.session.utteranceRecords.map(\.raw), [today])
        XCTAssertEqual(h.session.insertRequests.map(\.text), try todaysInsert(today, audio: audio))
        if emptyTail {
            let tail = try XCTUnwrap(speech.releaseCalls.first)
            XCTAssertEqual(tail.text, "")
            XCTAssertLessThan(tail.samples.count, audio.samples.count)
            XCTAssertEqual(tail.prompt, speech.initialPrompt + " " + expectedPrefix(name))
        }
    }

    /// Compare fallback insertion with the real Session's existing full path.
    private func todaysInsert(_ text: String, audio: SteppedWAVAudio) throws -> [String] {
        let h = try MacHarness()
        h.session.setCleanupBackend(.off)
        let pipeline = pipeline(h, audio: audio, transcriber: ScriptedTranscriber(text), enabled: false)
        pipeline.handle(key(h, down: true))
        audio.exposeAll()
        h.clock.advance(by: .seconds(audio.durationSeconds))
        pipeline.handle(key(h, down: false))
        h.clock.advance(by: .milliseconds(250))
        XCTAssertEqual(h.session.insertRequests.count, 1)
        return h.session.insertRequests.map(\.text)
    }

    @discardableResult
    private func replay(_ fixture: SegmentRecording, audio: SteppedWAVAudio, speech: RecordedSegmentReplay,
                        pipeline: HoldPipeline, harness h: MacHarness) -> Bool {
        var previousTime = 0.0
        var sawCleanedPanel = false
        for partial in fixture.partials {
            audio.expose(seconds: partial.t)
            speech.partialStdout = partial.stdout
            h.clock.advance(by: .seconds(partial.t - previousTime))
            pipeline.partialTick()
            h.clock.advance(by: .zero)
            sawCleanedPanel = sawCleanedPanel || (h.session.panel.text?.contains("✓ ") ?? false)
            previousTime = partial.t
        }
        audio.exposeAll()
        h.clock.advance(by: .seconds(audio.durationSeconds - previousTime))
        return sawCleanedPanel
    }

    private func pipeline(_ h: MacHarness, audio: AudioSource, transcriber: SpeechTranscriber,
                          enabled: Bool) -> HoldPipeline {
        let pipeline = HoldPipeline(session: h.session, clock: h.clock, audio: audio, transcriber: transcriber,
                                    focus: FixedFocus { time in
                                        var snapshot = h.field()
                                        snapshot.timestamp = time
                                        return snapshot
                                    })
        pipeline.tailTranscriptionEnabled = enabled
        return pipeline
    }

    private func key(_ h: MacHarness, down: Bool) -> TapOutput {
        .talk(TalkKeyEvent(timestamp: h.clock.now, identity: .command(.left), isDown: down))
    }

    private func whisper(_ h: MacHarness) throws -> WhisperTranscriber {
        guard let found = WhisperTranscriber.locate(executables: WhisperTranscriber.defaultExecutables,
                                                    model: WhisperTranscriber.defaultModel()) else {
            throw XCTSkip("whisper-cli or model not installed")
        }
        return WhisperTranscriber(executable: found.executable, model: found.model,
                                  scratchDirectory: h.directory.appendingPathComponent("whisper"))
    }

    private var fixtureDirectory: URL {
        URL(fileURLWithPath: #filePath).resolvingSymlinksInPath()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/audio")
    }

    private func recording(_ name: String) throws -> SegmentRecording {
        let fixtures = try JSONDecoder().decode([String: SegmentRecording].self,
            from: Data(contentsOf: fixtureDirectory.appendingPathComponent("whisper-segments.json")))
        return try XCTUnwrap(fixtures[name])
    }

    private func audio(_ name: String) throws -> SteppedWAVAudio {
        try SteppedWAVAudio(url: fixtureDirectory.appendingPathComponent(name + ".wav"))
    }

    private func expectedPrefix(_ name: String) -> String {
        // Independent R259 oracles, not computed with the tracker/join under test.
        switch name {
        case "long-dictation":
            return "So I had a look at the quarterly numbers this morning, and they are honestly better than I expected. Sales in the north region went up by about 12%, which is really good news for the team. The south region is still a bit flat, um, but the new pricing only started last month. I think we should give it until the end of November before we change anything."
        case "long-plain":
            return "Hey Kazey, thanks for sending the draft through yesterday. I read it on the train this morning, and I really like the overall structure. The introduction is strong, but the middle section about the budget could be a bit tighter. I would also move the timeline to the end, so the reader gets the main argument first."
        default:
            XCTFail("No stable-prefix oracle for \(name)")
            return ""
        }
    }
}

private struct SegmentRecording: Decodable {
    struct Segment: Decodable { let start: Double; let end: Double; let text: String }
    struct Partial: Decodable { let t: Double; let stdout: String }
    let partials: [Partial]
    let final_segments: [Segment]
    let final_stdout: String
}

/// Replay recorded microphone input at explicit audio times; no wall-time waits.
private final class SteppedWAVAudio: AudioSource {
    let sampleRate: Double
    let samples: [Float]
    var durationSeconds: Double { Double(samples.count) / sampleRate }
    private var count = 0

    init(url: URL) throws {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        XCTAssertEqual(format.sampleRate, 16_000, url.lastPathComponent)
        XCTAssertEqual(format.channelCount, 1, url.lastPathComponent)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length)))
        try file.read(into: buffer)
        let channel = try XCTUnwrap(buffer.floatChannelData?[0])
        samples = Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
        sampleRate = format.sampleRate
        XCTAssertFalse(samples.isEmpty)
    }

    func start() throws { count = 0 }
    func stop() {}
    func expose(seconds: Double) { count = min(samples.count, max(0, Int(seconds * sampleRate))) }
    func exposeAll() { count = samples.count }
    func snapshot() -> [Float] { Array(samples.prefix(count)) }
}

/// Input replay adapter, not a replacement for parsing, tracking or joining.
/// Release calls execute real whisper, except the explicit empty-tail fault case.
private final class RecordedSegmentReplay: SegmentedSpeechTranscriber {
    enum Kind: Equatable { case full, segments }
    struct Call {
        let kind: Kind
        let samples: [Float]
        let sampleRate: Double
        let prompt: String?
        let text: String?
    }
    let whisper: WhisperTranscriber
    var name: String { "recorded partials + " + whisper.name }
    var initialPrompt: String { whisper.initialPrompt }
    var partialStdout = ""
    var isReleasing = false
    var emptyReleaseTail = false
    private(set) var segmentedPartialCalls = 0
    private(set) var plainPartialCalls = 0
    private(set) var releaseCalls: [Call] = []

    init(whisper: WhisperTranscriber) { self.whisper = whisper }

    func transcribe(samples: [Float], sampleRate: Double) -> String? {
        guard isReleasing else {
            plainPartialCalls += 1
            return WhisperTranscriber.parseOutput(partialStdout)
        }
        let text = whisper.transcribe(samples: samples, sampleRate: sampleRate)
        releaseCalls.append(Call(kind: .full, samples: samples, sampleRate: sampleRate, prompt: initialPrompt, text: text))
        return text
    }

    func transcribeSegments(samples: [Float], sampleRate: Double, prompt: String?) -> [TranscriptSegment]? {
        guard isReleasing else {
            segmentedPartialCalls += 1
            return WhisperTranscriber.parseSegments(partialStdout)
        }
        let segments: [TranscriptSegment]? = emptyReleaseTail ? []
            : whisper.transcribeSegments(samples: samples, sampleRate: sampleRate, prompt: prompt)
        releaseCalls.append(Call(kind: .segments, samples: samples, sampleRate: sampleRate, prompt: prompt,
                                 text: segments?.map(\.text).joined(separator: " ")))
        return segments
    }
}

/// Instrument the requested existing non-segmented transcriber without replacing
/// any of its behavior or adding segment conformance.
private final class FullSampleRecorder: SpeechTranscriber {
    let transcriber: SpeechTranscriber
    var name: String { transcriber.name }
    private(set) var sampleCounts: [Int] = []
    init(_ transcriber: SpeechTranscriber) { self.transcriber = transcriber }
    func transcribe(samples: [Float], sampleRate: Double) -> String? {
        sampleCounts.append(samples.count)
        return transcriber.transcribe(samples: samples, sampleRate: sampleRate)
    }
}

/// Only the HTTP boundary is scripted. Distinct cleanup output reveals whether
/// release accidentally duplicates already-cleaned background sentences.
private final class TailCleanupTransport: GatewayHTTPTransport {
    struct Request { let system: String; let user: String }
    private(set) var requests: [Request] = []
    var deferReplies = false
    private var pending: ((Result<(Data, Int), Error>) -> Void)?

    static func cleaned(_ raw: String) -> String { "✓ " + raw }

    func send(_ request: URLRequest, completion: @escaping (Result<(Data, Int), Error>) -> Void) {
        do {
            struct Body: Decodable {
                struct Message: Decodable { let role: String; let content: String }
                let messages: [Message]
            }
            let body = try JSONDecoder().decode(Body.self, from: XCTUnwrap(request.httpBody))
            let user = try XCTUnwrap(body.messages.first { $0.role == "user" }?.content)
            let system = try XCTUnwrap(body.messages.first { $0.role == "system" }?.content)
            requests.append(Request(system: system, user: user))
            if deferReplies {
                XCTAssertNil(pending, "Exactly one release request may be pending")
                pending = completion
            } else {
                completion(.success((try reply(user), 200)))
            }
        } catch {
            XCTFail("Invalid cleanup request: \(error)")
            completion(.failure(error))
        }
    }

    func finishRelease() throws {
        let completion = try XCTUnwrap(pending)
        pending = nil
        completion(.success((try reply(XCTUnwrap(requests.last).user), 200)))
    }

    private func reply(_ user: String) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["text": Self.cleaned(user)])
    }
}
