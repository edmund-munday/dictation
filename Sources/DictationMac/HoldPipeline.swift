import DictationCore
import Foundation

/// Connects tap output, the microphone, and the transcriber to the core session.
/// Not thread-safe: call every method from one serial queue.
public final class HoldPipeline {
    private let session: Session
    private let clock: any Clock
    private let audio: AudioSource
    private let transcriber: SpeechTranscriber
    private let focus: FocusProvider
    /// Called before a hold begins so the caller can refresh call / mic-owner state.
    public var beforeHold: (() -> Void)?
    /// Called whenever the session may have new output.
    public var onChange: (() -> Void)?
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
        guard let text = transcriber.transcribe(samples: samples, sampleRate: audio.sampleRate),
              !text.isEmpty, isCapturing else { return }
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
        beforeHold?()
        session.ingestFocus(focus.currentFocus(at: clock.now))
        session.ingestTalkKey(event)
        guard session.micState == .open else { return }
        do {
            try audio.start()
            isCapturing = true
        } catch {
            isCapturing = false
        }
    }

    private func end(_ event: TalkKeyEvent) {
        if isCapturing {
            let samples = audio.snapshot()
            stopCapture()
            if let text = transcriber.transcribe(samples: samples, sampleRate: audio.sampleRate), !text.isEmpty {
                ingest(text, final: true)
            }
        }
        session.ingestTalkKey(TalkKeyEvent(
            timestamp: clock.now, identity: event.identity, isDown: false,
            otherKeysAlreadyDown: event.otherKeysAlreadyDown))
    }

    private func stopCapture() {
        audio.stop()
        isCapturing = false
    }

    private func ingest(_ text: String, final: Bool) {
        let now = clock.now
        session.ingestRecognizerTokens([
            RecognizerToken(text: text, start: .zero, end: now, isSpeech: true, confidence: 1, language: "en",
                            isFinal: final),
        ])
    }
}
