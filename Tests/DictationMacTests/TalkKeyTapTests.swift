import CoreGraphics
import DictationCore
import DictationMac
import XCTest

/// M1–M4: the event tap turns raw keyboard events into core hold events and never swallows them.
final class TalkKeyTapTests: XCTestCase {
    private let cmd: UInt64 = 0x100000
    private let leftCmdDevice: UInt64 = 0x8
    private let rightCmdDevice: UInt64 = 0x10
    private let shift: UInt64 = 0x20000
    private let control: UInt64 = 0x40000
    private let option: UInt64 = 0x80000

    private func feed(_ h: MacHarness, _ t: TalkKeyTranslator, _ e: RawKeyEvent) {
        for out in t.translate(e, at: h.clock.now) {
            if case .talk(let ev) = out { h.session.ingestTalkKey(ev) }
        }
    }

    func test_M1_leftCommandAloneStartsAndEndsHold() throws {
        let h = try MacHarness()
        h.session.ingestFocus(h.field())
        let t = TalkKeyTranslator()
        feed(h, t, RawKeyEvent(kind: .flagsChanged, keyCode: 55, flags: cmd | leftCmdDevice))
        XCTAssertEqual(h.session.micState, .open)
        XCTAssertTrue(h.session.panel.isVisible)
        h.clock.advance(by: .milliseconds(400))
        feed(h, t, RawKeyEvent(kind: .flagsChanged, keyCode: 55, flags: 0))
        XCTAssertNotEqual(h.session.micState, .open)
    }

    func test_M1_rightCommandAloneDoesNothingByDefault() throws {
        let h = try MacHarness()
        h.session.ingestFocus(h.field())
        let t = TalkKeyTranslator()
        feed(h, t, RawKeyEvent(kind: .flagsChanged, keyCode: 54, flags: cmd | rightCmdDevice))
        XCTAssertNotEqual(h.session.micState, .open)
        XCTAssertFalse(h.session.panel.isVisible)
    }

    func test_M2_otherKeyWhileHeldCancelsHold() throws {
        let h = try MacHarness()
        h.session.ingestFocus(h.field())
        let t = TalkKeyTranslator()
        feed(h, t, RawKeyEvent(kind: .flagsChanged, keyCode: 55, flags: cmd | leftCmdDevice))
        feed(h, t, RawKeyEvent(kind: .keyDown, keyCode: 8, flags: cmd | leftCmdDevice)) // Cmd-C
        XCTAssertNotEqual(h.session.micState, .open)
        XCTAssertFalse(h.session.panel.isVisible)
    }

    func test_M2_otherModifierWhileHeldCancelsHold() throws {
        let h = try MacHarness()
        h.session.ingestFocus(h.field())
        let t = TalkKeyTranslator()
        feed(h, t, RawKeyEvent(kind: .flagsChanged, keyCode: 55, flags: cmd | leftCmdDevice))
        feed(h, t, RawKeyEvent(kind: .flagsChanged, keyCode: 56, flags: cmd | leftCmdDevice | shift))
        XCTAssertNotEqual(h.session.micState, .open)
    }

    func test_M3_leftCommandWithModifierAlreadyDownDoesNotStartHold() throws {
        let h = try MacHarness()
        h.session.ingestFocus(h.field())
        let t = TalkKeyTranslator()
        feed(h, t, RawKeyEvent(kind: .flagsChanged, keyCode: 58, flags: option))
        feed(h, t, RawKeyEvent(kind: .flagsChanged, keyCode: 55, flags: option | cmd | leftCmdDevice))
        XCTAssertNotEqual(h.session.micState, .open)
        XCTAssertFalse(h.session.panel.isVisible)
    }

    func test_M3_leftCommandWithLetterAlreadyDownDoesNotStartHold() throws {
        let h = try MacHarness()
        h.session.ingestFocus(h.field())
        let t = TalkKeyTranslator()
        feed(h, t, RawKeyEvent(kind: .keyDown, keyCode: 0, flags: 0)) // "a" held
        feed(h, t, RawKeyEvent(kind: .flagsChanged, keyCode: 55, flags: cmd | leftCmdDevice))
        XCTAssertNotEqual(h.session.micState, .open)
    }

    func test_M2_M4_tapReturnsEveryEventUnchanged() throws {
        var outputs: [TapOutput] = []
        let tap = KeyboardTap(clock: TestClock()) { outputs.append($0) }

        let cmdDown = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: 55, keyDown: true))
        cmdDown.type = .flagsChanged
        cmdDown.flags = CGEventFlags(rawValue: cmd | leftCmdDevice)
        XCTAssertTrue(tap.handle(type: .flagsChanged, event: cmdDown) === cmdDown)

        let letter = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: 8, keyDown: true))
        letter.flags = CGEventFlags(rawValue: cmd | leftCmdDevice)
        XCTAssertTrue(tap.handle(type: .keyDown, event: letter) === letter)
        XCTAssertEqual(letter.getIntegerValueField(.keyboardEventKeycode), 8)

        let cmdUp = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: 55, keyDown: false))
        cmdUp.type = .flagsChanged
        cmdUp.flags = CGEventFlags(rawValue: 0)
        XCTAssertTrue(tap.handle(type: .flagsChanged, event: cmdUp) === cmdUp)

        // Hold began, then was interrupted by the letter; the tap synthesised nothing extra.
        let talk = outputs.compactMap { out -> TalkKeyEvent? in
            if case .talk(let e) = out { return e }
            return nil
        }
        XCTAssertEqual(talk.first?.identity, .command(.left))
        XCTAssertEqual(talk.first?.isDown, true)
        XCTAssertEqual(talk.filter { $0.identity == .command(.left) }.count, 2)
    }
}
