import AppKit
import DictationCore
import DictationMac
import XCTest

/// M10–M12: insertion into the hold-start field, Copy fallback, secure fields skipped.
final class MacInsertionTests: XCTestCase {
    private func dictate(_ h: MacHarness, _ text: String, focus: FocusSnapshot) {
        h.session.ingestFocus(focus)
        h.session.ingestTalkKey(TalkKeyEvent(timestamp: h.clock.now, identity: .command(.left), isDown: true))
        h.clock.advance(by: .milliseconds(500))
        h.session.ingestRecognizerTokens([
            RecognizerToken(text: text, start: .zero, end: h.clock.now, isFinal: true),
        ])
        h.session.ingestTalkKey(TalkKeyEvent(timestamp: h.clock.now, identity: .command(.left), isDown: false))
    }

    func test_M10_insertsIntoFieldFocusedAtHoldStartEvenIfFocusMoved() throws {
        let h = try MacHarness()
        let inserter = RecordingInserter(succeeds: true)
        let coordinator = InsertionCoordinator(session: h.session, inserter: inserter)
        h.session.ingestFocus(h.field(id: "original"))
        h.session.ingestTalkKey(TalkKeyEvent(timestamp: h.clock.now, identity: .command(.left), isDown: true))
        h.clock.advance(by: .milliseconds(500))
        h.session.ingestRecognizerTokens([
            RecognizerToken(text: "hello there", start: .zero, end: h.clock.now, isFinal: true),
        ])
        h.session.ingestFocus(h.field(id: "elsewhere"))
        h.session.ingestTalkKey(TalkKeyEvent(timestamp: h.clock.now, identity: .command(.left), isDown: false))
        h.clock.advance(by: .milliseconds(250))
        coordinator.poll()
        XCTAssertEqual(inserter.inserted.count, 1)
        XCTAssertEqual(inserter.inserted.first?.target.elementID, "original")
        XCTAssertEqual(inserter.inserted.first?.text, "Hello there.")
        XCTAssertFalse(inserter.inserted.first?.text.contains("\n") ?? true)
        coordinator.poll()
        XCTAssertEqual(inserter.inserted.count, 1, "each request is inserted once")
    }

    func test_M11_failedInsertShowsCopyButtonThatCopiesText() throws {
        let h = try MacHarness()
        let board = NSPasteboard(name: NSPasteboard.Name("dictation-test-\(UUID().uuidString)"))
        let coordinator = InsertionCoordinator(
            session: h.session, inserter: RecordingInserter(succeeds: false), pasteboard: board)
        dictate(h, "hello there", focus: h.field())
        h.clock.advance(by: .milliseconds(250))
        coordinator.poll()
        XCTAssertTrue(h.session.panel.isVisible)
        XCTAssertEqual(h.session.panel.buttons.map(\.title), ["Copy"])
        XCTAssertEqual(coordinator.pendingCopyText, "Hello there.")
        coordinator.tap(button: "Copy")
        XCTAssertEqual(board.string(forType: .string), "Hello there.")
        board.releaseGlobally()
    }

    func test_R238_noFocusedFieldCopyButtonCopiesText() throws {
        let h = try MacHarness()
        let board = NSPasteboard(name: NSPasteboard.Name("dictation-test-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        let coordinator = InsertionCoordinator(
            session: h.session, inserter: RecordingInserter(succeeds: false), pasteboard: board)
        dictate(h, "hello there", focus: FocusSnapshot(timestamp: h.clock.now, role: .none, identity: .none))
        h.clock.advance(by: .milliseconds(250))
        coordinator.poll()

        XCTAssertTrue(h.session.panel.isVisible)
        XCTAssertEqual(h.session.panel.text, "No text field was focused.")
        XCTAssertEqual(h.session.panel.buttons.map(\.title), ["Copy"])
        XCTAssertEqual(h.session.panel.copyText, "Hello there.")
        coordinator.tap(button: "Copy")
        XCTAssertEqual(board.string(forType: .string), "Hello there.")
    }

    func test_M12_secureFieldIsSkippedAndMicNeverOpens() throws {
        let h = try MacHarness()
        let inserter = RecordingInserter(succeeds: true)
        let coordinator = InsertionCoordinator(session: h.session, inserter: inserter)
        let audio = CountingAudio()
        let secure = h.field(.secureTextField, secure: true)
        let p = HoldPipeline(
            session: h.session, clock: h.clock, audio: audio,
            transcriber: ScriptedTranscriber("my password"),
            focus: FixedFocus { _ in secure })
        p.handle(.talk(TalkKeyEvent(timestamp: h.clock.now, identity: .command(.left), isDown: true)))
        h.clock.advance(by: .milliseconds(600))
        p.partialTick()
        p.handle(.talk(TalkKeyEvent(timestamp: h.clock.now, identity: .command(.left), isDown: false)))
        h.clock.advance(by: .milliseconds(300))
        coordinator.poll()
        XCTAssertEqual(audio.starts, 0)
        XCTAssertTrue(inserter.inserted.isEmpty)
        XCTAssertNotEqual(h.session.panel.text, "my password")
    }

    func test_M12_axSecureSubroleClassifiesAsSecure() {
        XCTAssertEqual(FocusClassifier.role(axRole: "AXTextField", subrole: "AXSecureTextField", bundleID: nil),
                       .secureTextField)
        XCTAssertEqual(FocusClassifier.role(axRole: "AXTextArea", subrole: nil, bundleID: nil), .textArea)
        XCTAssertEqual(FocusClassifier.role(axRole: "AXTextField", subrole: nil, bundleID: nil), .textField)
        XCTAssertEqual(FocusClassifier.role(axRole: "AXButton", subrole: nil, bundleID: nil), FieldRole.none)
        XCTAssertEqual(FocusClassifier.role(axRole: "AXTextArea", subrole: nil, bundleID: "com.apple.Terminal"),
                       .terminal)
    }
}
