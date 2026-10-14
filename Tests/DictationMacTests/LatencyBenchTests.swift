import AVFoundation
import DictationCore
import DictationMac
import Foundation
import XCTest

/// Opt-in measurements using the current app pipeline, real whisper and the real gateway.
/// No microphone, focused application, AX insertion or virtual audio device is needed.
final class LatencyBenchTests: XCTestCase {
    func test_R257_recordedAudioMeasuresReleaseToInsertThroughTheAppInputHandler() throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["DICTATION_LATENCY_BENCH"] == "1" else {
            throw XCTSkip("Set DICTATION_LATENCY_BENCH=1 to run the real whisper/gateway latency bench")
        }
        // An explicitly enabled bench fails if its real dependencies are missing.
        let whisper = try XCTUnwrap(WhisperTranscriber.locate(
            executables: WhisperTranscriber.defaultExecutables, model: WhisperTranscriber.defaultModel()),
            "Install whisper-cli and the default Whisper model before running the bench")
        let config = try XCTUnwrap(GatewayConfig.load(from: GatewayConfig.defaultPath),
                                  "Configure the real gateway at \(GatewayConfig.defaultPath.path)")
        let root = URL(fileURLWithPath: #filePath).resolvingSymlinksInPath()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        var measurements: [String: Double] = [:]
        for wav in ["long-plain.wav", "long-dictation.wav"] {
            let audio = try ReplayedWAVAudio(url: root.appendingPathComponent("Tests/Fixtures/audio/" + wav))
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("dictation-latency-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let done = expectation(description: "\(wav) inserted after release")
            let run = LatencyReplay(
                audio: audio, directory: directory,
                transcriber: WhisperTranscriber(executable: whisper.executable, model: whisper.model,
                                                scratchDirectory: directory.appendingPathComponent("whisper")),
                cleaner: GatewayCleaner(config: config), done: done)
            run.start()
            wait(for: [done], timeout: audio.durationSeconds + 120)
            let result = run.finish()
            let milliseconds = try XCTUnwrap(result.milliseconds, "No insert request for \(wav)")
            XCTAssertEqual(result.inserts.count, 1, wav)
            let insert = try XCTUnwrap(result.inserts.first)
            XCTAssertFalse(insert.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, wav)
            XCTAssertEqual(insert.target.elementID, "latency-bench-field")
            measurements[wav] = milliseconds
            print("Latency bench \(wav): \(milliseconds) ms from release to insert")
        }

        let label = environment["DICTATION_LATENCY_LABEL"] ?? "run"
        let output = root.appendingPathComponent("build/latency.json")
        try FileManager.default.createDirectory(at: output.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        var document: [String: Any] = [:]
        if FileManager.default.fileExists(atPath: output.path) {
            document = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: output)) as? [String: Any])
        }
        // {"before": {"long-plain.wav": ms, ...}, "after": {...}}. Preserve other
        // labels and any other WAV keys already recorded under the same label.
        var labelled = document[label] as? [String: Any] ?? [:]
        for (wav, milliseconds) in measurements { labelled[wav] = milliseconds }
        document[label] = labelled
        try JSONSerialization.data(withJSONObject: document, options: [.prettyPrinted, .sortedKeys])
            .write(to: output, options: .atomic)
        print("Latency measurements saved to \(output.path) under \(label)")
    }
}

/// Audio-input boundary: expose only the WAV prefix that would have arrived by now.
/// Playback advances with wall time even while synchronous whisper occupies the work queue.
private final class ReplayedWAVAudio: AudioSource {
    let sampleRate: Double
    let durationSeconds: TimeInterval
    private let samples: [Float]
    private var startedAt: ContinuousClock.Instant?
    private var stoppedCount: Int?

    init(url: URL) throws {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        XCTAssertEqual(format.sampleRate, 16_000, url.lastPathComponent)
        XCTAssertEqual(format.channelCount, 1, url.lastPathComponent)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format,
                                                   frameCapacity: AVAudioFrameCount(file.length)))
        try file.read(into: buffer)
        let channel = try XCTUnwrap(buffer.floatChannelData?[0], "WAV must decode to float PCM")
        let samples = Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
        XCTAssertFalse(samples.isEmpty, url.lastPathComponent)
        self.samples = samples
        sampleRate = format.sampleRate
        durationSeconds = Double(samples.count) / format.sampleRate
    }

    func start() throws {
        stoppedCount = nil
        startedAt = ContinuousClock.now
    }

    func stop() { stoppedCount = capturedCount }

    func snapshot() -> [Float] { Array(samples.prefix(capturedCount)) }

    private var capturedCount: Int {
        if let stoppedCount { return stoppedCount }
        guard let startedAt else { return 0 }
        let elapsed = startedAt.duration(to: .now).components
        let seconds = Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
        return min(samples.count, max(0, Int(seconds * sampleRate)))
    }
}

private final class LatencyBenchFocus: FocusProvider {
    func currentFocus(at time: Duration) -> FocusSnapshot {
        FocusSnapshot(timestamp: time, role: .textField,
                      identity: FocusIdentity(pid: Int(ProcessInfo.processInfo.processIdentifier),
                                              elementID: "latency-bench-field"))
    }
}

/// Like AppModel, all pipeline/Session access and partial ticks use one serial queue.
private final class LatencyReplay: @unchecked Sendable {
    private let queue: DispatchQueue
    private let clock: QueueClock
    private let session: Session
    private let pipeline: HoldPipeline
    private let audio: ReplayedWAVAudio
    private let cleaner: GatewayCleaner
    private let done: XCTestExpectation
    private var partialTimer: DispatchSourceTimer?
    private var releasedAt: ContinuousClock.Instant?
    private var milliseconds: Double?
    private var finished = false

    init(audio: ReplayedWAVAudio, directory: URL, transcriber: WhisperTranscriber,
         cleaner: GatewayCleaner, done: XCTestExpectation) {
        let queue = DispatchQueue(label: "dictation.latency-bench")
        self.queue = queue
        let clock = QueueClock(queue: queue)
        let session = Session(clock: clock, paths: SessionPaths(workingDirectory: directory))
        self.clock = clock
        self.session = session
        self.audio = audio
        self.cleaner = cleaner
        self.done = done
        pipeline = HoldPipeline(session: session, clock: clock, audio: audio,
                                transcriber: transcriber, focus: LatencyBenchFocus())
    }

    func start() {
        queue.async { [self] in
            session.setMicPermission(.granted)
            session.setAccessibilityPermission(true)
            session.setInputMonitoringPermission(true)
            session.setOnDeviceRecognizerAvailable(true)
            session.setSystemRecognizerReportsOnDevice(true)
            session.setBundledModelLoadable(true)
            session.setCleanupBackend(.gateway)
            session.setGatewayCleaner(cleaner)
            session.setLatch(.on)
            pipeline.onChange = { [weak self] in self?.observeInsertion() }
            // Session's own clock observer is registered first. Observe its user-facing
            // output after every tick, including asynchronous gateway completions.
            clock.observeAdvances { [weak self] in self?.observeInsertion() }
            pipeline.handle(.talk(TalkKeyEvent(timestamp: clock.now, identity: .command(.left), isDown: true)))
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now() + .milliseconds(800), repeating: .milliseconds(800))
            timer.setEventHandler { [weak self] in self?.pipeline.partialTick() }
            partialTimer = timer
            timer.resume()
            queue.asyncAfter(deadline: .now() + audio.durationSeconds) { [self] in
                guard !finished else { return }
                partialTimer?.cancel()
                partialTimer = nil
                // Start BEFORE handling key-up: include final whisper transcription,
                // gateway cleanup and the Session's normal insertion scheduling.
                releasedAt = ContinuousClock.now
                pipeline.handle(.talk(TalkKeyEvent(timestamp: clock.now, identity: .command(.left), isDown: false)))
                observeInsertion()
            }
        }
    }

    private func observeInsertion() {
        guard !finished, let releasedAt, !session.insertRequests.isEmpty else { return }
        let elapsed = releasedAt.duration(to: .now).components
        milliseconds = Double(elapsed.seconds) * 1_000 + Double(elapsed.attoseconds) / 1e15
        finished = true
        done.fulfill()
    }

    func finish() -> (milliseconds: Double?, inserts: [InsertRequest]) {
        queue.sync {
            partialTimer?.cancel()
            partialTimer = nil
            if !finished {
                finished = true
                pipeline.handle(.talk(TalkKeyEvent(timestamp: clock.now, identity: .escape, isDown: true)))
            }
            return (milliseconds, session.insertRequests)
        }
    }
}
