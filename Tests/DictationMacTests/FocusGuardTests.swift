import AppKit
import AVFoundation
import DictationCore
import DictationMac
import Foundation
import XCTest

/// R266–R271: replay microphone input through the app's hold/release and insertion boundaries.
/// All speech recognition is real whisper; only the OS boundaries are test doubles.
final class FocusGuardTests: XCTestCase {
    func test_R266_differentElementInSameProcessOffersCopyWithoutInsertingOrSending() throws {
        let replay = try FocusGuardReplay()
        replay.holdAndRelease()
        replay.focus.snapshot = FocusGuardReplay.field(elementID: "field-B")
        replay.pollAfterRelease()

        try assertSwitchedField(replay)
    }

    func test_R266_differentProcessWithSameElementIDOffersCopyWithoutInsertingOrSending() throws {
        let replay = try FocusGuardReplay()
        replay.holdAndRelease()
        // Keeping the element ID isolates the pid half of the identity comparison.
        replay.focus.snapshot = FocusGuardReplay.field(pid: 5252)
        replay.pollAfterRelease()

        try assertSwitchedField(replay)
    }

    func test_R267_sameProcessAndElementWithChangedRoleLabelAndFrameInsertsAndSends() throws {
        let replay = try FocusGuardReplay()
        replay.holdAndRelease()
        var resized = FocusGuardReplay.field()
        resized.identity.roleLabel = "AXTextField"
        resized.identity.frameDescription = "x=20 y=30 width=800 height=160"
        replay.focus.snapshot = resized
        replay.pollAfterRelease()

        try assertInsertedAndSent(replay)
    }

    func test_R268_noFocusAtInsertionMatchesUncheckedCoordinator() throws {
        try assertMatchesUncheckedCoordinator(FocusSnapshot(
            timestamp: .zero, role: .none, identity: .none))
    }

    func test_R268_nonEditableFocusAtInsertionMatchesUncheckedCoordinator() throws {
        try assertMatchesUncheckedCoordinator(FocusSnapshot(
            timestamp: .zero, role: .none,
            identity: FocusIdentity(pid: 5252, elementID: "button-B", roleLabel: "AXButton")))
    }

    func test_R269_focusMovesDuringHoldAndReturnsBeforeReleaseInsertsIntoOriginalField() throws {
        let replay = try FocusGuardReplay()
        replay.beginHold()
        replay.focus.snapshot = FocusGuardReplay.field(elementID: "field-B")
        replay.partial(at: 0.8)
        replay.focus.snapshot = FocusGuardReplay.field()
        replay.partial(at: 1.6)
        replay.release()
        replay.pollAfterRelease()

        try assertInsertedAndSent(replay)
    }

    func test_R269_otherFieldAtReleaseButOriginalFieldAtInsertionInsertsIntoOriginalField() throws {
        let replay = try FocusGuardReplay()
        replay.beginHold()
        replay.partial(at: 0.8)
        replay.partial(at: 1.6)
        replay.focus.snapshot = FocusGuardReplay.field(elementID: "field-B")
        replay.release()
        replay.focus.snapshot = FocusGuardReplay.field()
        replay.pollAfterRelease()

        try assertInsertedAndSent(replay)
    }

    func test_R270_nilFocusPreservesInsertionAndAutoSendAfterFocusChanges() throws {
        let replay = try FocusGuardReplay(checkFocus: false)
        replay.holdAndRelease()
        replay.focus.snapshot = FocusGuardReplay.field(pid: 5252, elementID: "field-B")
        replay.pollAfterRelease()

        try assertInsertedAndSent(replay)
    }

    func test_R271_realWhisperShortDictationSwitchedAfterReleaseKeepsSeeYouAtBehindCopy() throws {
        let replay = try FocusGuardReplay()
        replay.holdAndRelease()
        replay.focus.snapshot = FocusGuardReplay.field(pid: 5252, elementID: "field-B")
        replay.pollAfterRelease()

        try assertSwitchedField(replay)
    }

    private func assertSwitchedField(
        _ replay: FocusGuardReplay, file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let message = "Not inserted: you switched to a different field. Copy it instead."
        XCTAssertEqual(MenuMessages.insertSwitchedField, message, file: file, line: line)
        XCTAssertTrue(replay.inserter.calls.isEmpty, file: file, line: line)
        XCTAssertEqual(replay.keys.returns, 0, file: file, line: line)
        XCTAssertTrue(replay.keys.delays.isEmpty, "Do not schedule Return", file: file, line: line)
        XCTAssertTrue(replay.h.session.panel.isVisible, file: file, line: line)
        XCTAssertEqual(replay.h.session.panel.text, message, file: file, line: line)
        XCTAssertEqual(replay.h.session.panel.buttons.map(\.title), ["Copy"], file: file, line: line)
        XCTAssertEqual(replay.h.session.overlay.text, message, file: file, line: line)
        XCTAssertEqual(replay.h.session.overlay.buttons.map(\.title), ["Copy"], file: file, line: line)
        let text = try XCTUnwrap(replay.h.session.panel.copyText, file: file, line: line)
        XCTAssertTrue(text.lowercased().contains("see you at"), text, file: file, line: line)
        XCTAssertEqual(text, replay.h.session.insertRequests.first?.text, file: file, line: line)
        XCTAssertEqual(replay.coordinator.outcomes.count, 1, file: file, line: line)
        let outcome = try XCTUnwrap(replay.coordinator.outcomes[0], file: file, line: line)
        XCTAssertFalse(outcome.inserted, file: file, line: line)
        XCTAssertFalse(outcome.autoSent, file: file, line: line)
        XCTAssertEqual(replay.board.string(forType: .string), FocusGuardReplay.clipboardBefore,
                       file: file, line: line)

        // A later app poll must not retry a blocked request, even after returning to A.
        let panel = replay.h.session.panel
        replay.focus.snapshot = FocusGuardReplay.field()
        replay.h.clock.advance(by: .seconds(1))
        replay.coordinator.poll()
        XCTAssertEqual(replay.h.session.panel, panel, file: file, line: line)
        XCTAssertTrue(replay.inserter.calls.isEmpty, file: file, line: line)
        XCTAssertEqual(replay.keys.returns, 0, file: file, line: line)
        XCTAssertEqual(replay.coordinator.outcomes.count, 1, file: file, line: line)
        replay.coordinator.tap(button: "Copy")
        XCTAssertEqual(replay.board.string(forType: .string), text, file: file, line: line)
    }

    private func assertInsertedAndSent(
        _ replay: FocusGuardReplay, file: StaticString = #filePath, line: UInt = #line
    ) throws {
        XCTAssertEqual(replay.inserter.calls.count, 1, file: file, line: line)
        let call = try XCTUnwrap(replay.inserter.calls.first, file: file, line: line)
        XCTAssertEqual(call.target, FocusGuardReplay.field().identity, file: file, line: line)
        XCTAssertTrue(call.text.lowercased().contains("see you at"), call.text, file: file, line: line)
        XCTAssertFalse(call.replacingSelection, file: file, line: line)
        XCTAssertEqual(replay.keys.returns, 1, file: file, line: line)
        XCTAssertEqual(replay.keys.delays.count, 1, file: file, line: line)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(replay.keys.delays.first), 0.1, file: file, line: line)
        XCTAssertEqual(replay.h.session.panel, .hidden, file: file, line: line)
        XCTAssertEqual(replay.h.session.overlay, .empty, file: file, line: line)
        XCTAssertEqual(replay.coordinator.outcomes.count, 1, file: file, line: line)
        let outcome = try XCTUnwrap(replay.coordinator.outcomes[0], file: file, line: line)
        XCTAssertTrue(outcome.inserted, file: file, line: line)
        XCTAssertTrue(outcome.autoSent, file: file, line: line)
        XCTAssertEqual(replay.board.string(forType: .string), FocusGuardReplay.clipboardBefore,
                       file: file, line: line)
        replay.h.clock.advance(by: .seconds(1))
        replay.coordinator.poll()
        XCTAssertEqual(replay.inserter.calls.count, 1, file: file, line: line)
        XCTAssertEqual(replay.keys.returns, 1, file: file, line: line)
    }

    private func assertMatchesUncheckedCoordinator(
        _ insertFocus: FocusSnapshot, file: StaticString = #filePath, line: UInt = #line
    ) throws {
        // Compare both OS insertion results so the existing failure/Copy path is preserved too.
        for succeeds in [true, false] {
            let today = try FocusGuardReplay(checkFocus: false, insertionSucceeds: succeeds)
            let guarded = try FocusGuardReplay(insertionSucceeds: succeeds)
            for replay in [today, guarded] {
                replay.holdAndRelease()
                replay.focus.snapshot = insertFocus
                replay.pollAfterRelease()
            }
            XCTAssertEqual(today.inserter.calls.count, 1, file: file, line: line)
            XCTAssertEqual(guarded.inserter.calls, today.inserter.calls, file: file, line: line)
            XCTAssertEqual(guarded.keys.returns, today.keys.returns, file: file, line: line)
            XCTAssertEqual(today.keys.returns, succeeds ? 1 : 0, file: file, line: line)
            XCTAssertEqual(guarded.keys.delays, today.keys.delays, file: file, line: line)
            XCTAssertEqual(guarded.h.session.panel, today.h.session.panel, file: file, line: line)
            XCTAssertEqual(guarded.h.session.overlay, today.h.session.overlay, file: file, line: line)
            XCTAssertEqual(guarded.coordinator.outcomes.count, today.coordinator.outcomes.count,
                           file: file, line: line)
            let expected = try XCTUnwrap(today.coordinator.outcomes[0], file: file, line: line)
            let actual = try XCTUnwrap(guarded.coordinator.outcomes[0], file: file, line: line)
            XCTAssertEqual(expected.inserted, succeeds, file: file, line: line)
            XCTAssertEqual(expected.autoSent, succeeds, file: file, line: line)
            XCTAssertEqual(actual.inserted, expected.inserted, file: file, line: line)
            XCTAssertEqual(actual.autoSent, expected.autoSent, file: file, line: line)
            for replay in [today, guarded] {
                if !succeeds {
                    XCTAssertEqual(replay.h.session.panel.buttons.map(\.title), ["Copy"], file: file, line: line)
                    let text = try XCTUnwrap(replay.h.session.panel.copyText, file: file, line: line)
                    XCTAssertTrue(text.lowercased().contains("see you at"), text, file: file, line: line)
                    replay.coordinator.tap(button: "Copy")
                    XCTAssertEqual(replay.board.string(forType: .string), text, file: file, line: line)
                }
            }
            XCTAssertEqual(guarded.board.string(forType: .string), today.board.string(forType: .string),
                           file: file, line: line)
        }
    }
}

private final class FocusGuardReplay {
    static let clipboardBefore = "Previous clipboard contents"
    let h: MacHarness
    let audio: FocusGuardWAVAudio
    let focus: FocusGuardFocus
    let inserter: FocusGuardInserter
    let keys: FocusGuardKeys
    let board: NSPasteboard
    let coordinator: InsertionCoordinator
    let pipeline: HoldPipeline
    private var audioTime = 0.0

    init(checkFocus: Bool = true, insertionSucceeds: Bool = true) throws {
        guard let whisper = WhisperTranscriber.locate(
            executables: WhisperTranscriber.defaultExecutables, model: WhisperTranscriber.defaultModel()) else {
            throw XCTSkip("whisper-cli or model not installed")
        }
        let h = try MacHarness()
        h.session.setCleanupBackend(.off)
        let fixtureDirectory = URL(fileURLWithPath: #filePath).resolvingSymlinksInPath()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/audio")
        let audio = try FocusGuardWAVAudio(url: fixtureDirectory.appendingPathComponent("short-dictation.wav"))
        let focus = FocusGuardFocus(Self.field())
        let inserter = FocusGuardInserter(succeeds: insertionSucceeds)
        let keys = FocusGuardKeys()
        let board = NSPasteboard(name: NSPasteboard.Name("dictation-focus-guard-\(UUID().uuidString)"))
        board.clearContents()
        board.setString(Self.clipboardBefore, forType: .string)
        let coordinator = InsertionCoordinator(
            session: h.session, inserter: inserter, pasteboard: board, focus: checkFocus ? focus : nil)
        coordinator.autoSend = AutoSendPolicy(enabled: true)
        coordinator.bundleForPID = { _ in "com.tinyspeck.slackmacgap" }
        coordinator.keySender = keys
        coordinator.schedule = { delay, work in keys.delays.append(delay); work() }
        self.h = h
        self.audio = audio
        self.focus = focus
        self.inserter = inserter
        self.keys = keys
        self.board = board
        self.coordinator = coordinator
        pipeline = HoldPipeline(
            session: h.session, clock: h.clock, audio: audio,
            transcriber: WhisperTranscriber(executable: whisper.executable, model: whisper.model,
                                            scratchDirectory: h.directory.appendingPathComponent("whisper")),
            focus: focus)
    }

    deinit { board.releaseGlobally() }

    static func field(pid: Int = 4242, elementID: String = "field-A") -> FocusSnapshot {
        FocusSnapshot(timestamp: .zero, role: .textArea,
                      identity: FocusIdentity(pid: pid, elementID: elementID, roleLabel: "AXTextArea",
                                              frameDescription: "x=20 y=30 width=400 height=80"))
    }

    func beginHold() {
        pipeline.handle(key(down: true))
        coordinator.poll()
        XCTAssertTrue(pipeline.isCapturing)
    }

    func partial(at seconds: Double) {
        audio.expose(seconds: seconds)
        h.clock.advance(by: .seconds(seconds - audioTime))
        audioTime = seconds
        pipeline.partialTick()
        coordinator.poll()
        XCTAssertFalse(h.session.panel.text?.isEmpty ?? true)
        XCTAssertTrue(inserter.calls.isEmpty, "Holding never inserts partial text")
        XCTAssertEqual(keys.returns, 0)
    }

    func release() {
        audio.expose(seconds: audio.durationSeconds)
        h.clock.advance(by: .seconds(audio.durationSeconds - audioTime))
        audioTime = audio.durationSeconds
        pipeline.handle(key(down: false))
        XCTAssertFalse(pipeline.isCapturing)
        XCTAssertTrue(inserter.calls.isEmpty)
    }

    func holdAndRelease() {
        beginHold()
        // The app's 800 ms partial cadence, using actual prefixes of the recorded WAV.
        partial(at: 0.8)
        partial(at: 1.6)
        release()
    }

    func pollAfterRelease() {
        h.clock.advance(by: .milliseconds(250))
        coordinator.poll()
    }

    private func key(down: Bool) -> TapOutput {
        .talk(TalkKeyEvent(timestamp: h.clock.now, identity: .command(.left), isDown: down))
    }
}

private final class FocusGuardFocus: FocusProvider {
    var snapshot: FocusSnapshot
    init(_ snapshot: FocusSnapshot) { self.snapshot = snapshot }
    func currentFocus(at time: Duration) -> FocusSnapshot {
        var current = snapshot
        current.timestamp = time
        return current
    }
}

private final class FocusGuardKeys: ReturnKeySender {
    var returns = 0
    var delays: [TimeInterval] = []
    func sendReturn() { returns += 1 }
}

private final class FocusGuardInserter: TextInserter {
    struct Call: Equatable {
        let text: String
        let target: FocusIdentity
        let replacingSelection: Bool
    }
    let succeeds: Bool
    private(set) var calls: [Call] = []
    init(succeeds: Bool) { self.succeeds = succeeds }
    func insert(_ text: String, into target: FocusIdentity, replacingSelection: Bool) -> Bool {
        calls.append(Call(text: text, target: target, replacingSelection: replacingSelection))
        return succeeds
    }
}

/// OS audio boundary: expose recorded microphone samples at explicit times without sleeping.
private final class FocusGuardWAVAudio: AudioSource {
    let sampleRate: Double
    let samples: [Float]
    var durationSeconds: Double { Double(samples.count) / sampleRate }
    private var count = 0

    init(url: URL) throws {
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

    func start() throws { count = 0 }
    func stop() {}
    func expose(seconds: Double) { count = min(samples.count, max(0, Int(seconds * sampleRate))) }
    func snapshot() -> [Float] { Array(samples.prefix(count)) }
}
