import DictationCore
import Foundation

/// Connects tap output, the microphone, and the transcriber to the core session.
/// Not thread-safe: call every method from one serial queue.
public final class HoldPipeline {
    public static let tailTranscriptionDefaultKey = "tailTranscriptionOnRelease"
    public static let tailTranscriptionDefaultOn = true
    public var tailTranscriptionEnabled = HoldPipeline.tailTranscriptionDefaultOn
    private let stableSentences = StableSentenceTracker()
    private let tailPolicy = TailTranscriptionPolicy()
    private let session: Session
    private let clock: any Clock
    private let audio: AudioSource
    private let transcriber: SpeechTranscriber
    private let focus: FocusProvider
    /// Called before a hold begins so the caller can refresh call / mic-owner state.
    public var beforeHold: (() -> Void)?
    /// Called whenever the session may have new output.
    public var onChange: (() -> Void)?
    /// Called once after the microphone successfully starts capturing.
    public var onCaptureStart: (() -> Void)?
    /// Called once after capture stops and the release reaches the session, or on cancellation.
    public var onCaptureEnd: (() -> Void)?
    public private(set) var isCapturing = false

    public init(
        session: Session, clock: any Clock, audio: AudioSource,
        transcriber: SpeechTranscriber, focus: FocusProvider
    ) {
        self.session = session
        self.clock = clock
        self.audio = audio
        self.transcriber = transcriber
        self.focus = focus
    }

    public func handle(_ output: TapOutput) {
        guard case .talk(let event) = output else { return }
        if case .command(let side) = event.identity, isTalkSide(side) {
            event.isDown ? begin(event) : end(event)
        } else {
            session.ingestTalkKey(event)
            if isCapturing, session.micState != .open {
                stopCapture()
            }
        }
        onChange?()
    }

    /// Re-transcribes everything captured so far and shows it in the panel.
    public func partialTick() {
        guard isCapturing, session.micState == .open else { return }
        let samples = audio.snapshot()
        let text: String?
        if tailTranscriptionEnabled, let segmented = transcriber as? SegmentedSpeechTranscriber {
            guard let segments = segmented.transcribeSegments(samples: samples, sampleRate: audio.sampleRate,
                                                              prompt: nil), isCapturing else { return }
            stableSentences.ingest(segments: segments, audioSeconds: Double(samples.count) / audio.sampleRate)
            text = segments.map(\.text).joined(separator: " ")
        } else {
            text = transcriber.transcribe(samples: samples, sampleRate: audio.sampleRate)
        }
        guard let text, !text.isEmpty, isCapturing else { return }
        ingest(text, final: false)
        onChange?()
    }

    private func isTalkSide(_ side: CommandSide) -> Bool {
        switch session.settings.talkKey {
        case .leftCommand: return side == .left
        case .rightCommand: return side == .right
        case .eitherCommand: return true
        }
    }

    private func begin(_ event: TalkKeyEvent) {
        guard !isCapturing else { return }
        stableSentences.reset()
        beforeHold?()
        session.ingestFocus(focus.currentFocus(at: clock.now))
        session.ingestTalkKey(event)
        guard session.micState == .open else { return }
        do {
            try audio.start()
            isCapturing = true
            onCaptureStart?()
        } catch {
            isCapturing = false
        }
    }

    private func end(_ event: TalkKeyEvent) {
        let wasCapturing = isCapturing
        if isCapturing {
            let samples = audio.snapshot()
            stopCapture(notifyEnd: false)
            if let text = releaseTranscript(samples: samples), !text.isEmpty {
                ingest(text, final: true)
            }
            session.ingestFocus(focus.currentFocus(at: clock.now))
        }
        session.ingestTalkKey(TalkKeyEvent(
            timestamp: clock.now, identity: event.identity, isDown: false,
            otherKeysAlreadyDown: event.otherKeysAlreadyDown))
        if wasCapturing { onCaptureEnd?() }
    }

    private func releaseTranscript(samples: [Float]) -> String? {
        let sampleRate = audio.sampleRate
        if tailTranscriptionEnabled, sampleRate.isFinite, sampleRate > 0,
           let segmented = transcriber as? SegmentedSpeechTranscriber,
           let stable = stableSentences.stablePrefix,
           case .tail(let start) = tailPolicy.plan(audioSeconds: Double(samples.count) / sampleRate, stable: stable) {
            let startIndex = min(samples.count, max(0, Int(start * sampleRate)))
            let tailSamples = Array(samples[startIndex...])
            let prompt = [segmented.initialPrompt, stable.text].filter { !$0.isEmpty }.joined(separator: " ")
            let segments = segmented.transcribeSegments(samples: tailSamples, sampleRate: sampleRate, prompt: prompt)
            let tail = segments?.map(\.text).joined(separator: " ")
            if tailPolicy.acceptTail(tail, tailAudioSeconds: Double(tailSamples.count) / sampleRate,
                                     prefix: stable.text), let tail {
                return TailJoin.join(prefix: stable.text, tail: tail)
            }
        }
        return transcriber.transcribe(samples: samples, sampleRate: sampleRate)
    }

    private func stopCapture(notifyEnd: Bool = true) {
        guard isCapturing else { return }
        audio.stop()
        isCapturing = false
        if notifyEnd { onCaptureEnd?() }
    }

    private func ingest(_ text: String, final: Bool) {
        let now = clock.now
        session.ingestRecognizerTokens([
            RecognizerToken(text: text, start: .zero, end: now, isSpeech: true, confidence: 1, language: "en",
                            isFinal: final),
        ])
    }
}
