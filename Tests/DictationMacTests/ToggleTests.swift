import DictationCore
import DictationMac
import XCTest

/// M5: Ctrl-Opt-Space toggles; icon and menu text follow; disabled means holds do nothing.
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

    func test_M5_toggleFlipsStateIconAndMenuText() throws {
        let h = try MacHarness(latched: false)
        let toggle = ToggleController(session: h.session)
        toggle.setEnabled(true)
        XCTAssertTrue(toggle.isEnabled)
        let onIcon = toggle.statusSymbolName
        let onTitle = toggle.menuTitle
        toggle.toggle()
        XCTAssertFalse(toggle.isEnabled)
        XCTAssertFalse(h.session.isLatchOn)
        XCTAssertNotEqual(toggle.statusSymbolName, onIcon)
        XCTAssertNotEqual(toggle.menuTitle, onTitle)
        XCTAssertTrue(toggle.menuTitle.contains("Off"))
        XCTAssertTrue(onTitle.contains("On"))
    }

    func test_M5_holdingCommandWhileDisabledDoesNothing() throws {
        let h = try MacHarness(latched: false)
        let toggle = ToggleController(session: h.session)
        toggle.setEnabled(true)
        toggle.toggle()
        h.session.ingestFocus(h.field())
        h.session.ingestTalkKey(TalkKeyEvent(timestamp: h.clock.now, identity: .command(.left), isDown: true))
        XCTAssertNotEqual(h.session.micState, .open)
        XCTAssertFalse(h.session.panel.isVisible)
    }
}
