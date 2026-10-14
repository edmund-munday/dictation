import DictationCore
import XCTest

/// R238: cleaned dictation stays available to Copy when focus is not editable.
final class CopyNoFieldTests: XCTestCase {
    func test_R238_noFocusedFieldShowsCleanedTextForCopy() throws {
        let h = try TestHarness()
        h.latchOn()
        h.clearFocus()
        h.pressTalkKey()
        h.speakWhileHeld("hello there")
        h.releaseTalkKey()
        h.clock.advance(by: .milliseconds(250))

        XCTAssertTrue(h.session.panel.isVisible)
        XCTAssertEqual(h.session.panel.text, MenuText.panelNoField)
        XCTAssertEqual(h.session.panel.buttons.map(\.title), ["Copy"])
        XCTAssertEqual(h.session.panel.copyText, "Hello there.")
        XCTAssertTrue(h.session.insertRequests.isEmpty)
    }

    func test_R238_nonEditableFocusShowsCleanedTextForCopy() throws {
        let h = try TestHarness()
        h.latchOn()
        h.session.ingestFocus(
            FocusSnapshot(
                timestamp: h.clock.now,
                role: .none,
                identity: FocusIdentity(pid: 42, elementID: "button-1", roleLabel: "AXButton")
            )
        )
        h.pressTalkKey()
        h.speakWhileHeld("hello there")
        h.releaseTalkKey()
        h.clock.advance(by: .milliseconds(250))

        XCTAssertTrue(h.session.panel.isVisible)
        XCTAssertEqual(h.session.panel.text, MenuText.panelNoField)
        XCTAssertEqual(h.session.panel.buttons.map(\.title), ["Copy"])
        XCTAssertEqual(h.session.panel.copyText, "Hello there.")
        XCTAssertTrue(h.session.insertRequests.isEmpty)
    }
}
