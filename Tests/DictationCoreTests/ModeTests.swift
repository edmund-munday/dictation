import XCTest
import DictationCore

final class ModeTests: XCTestCase {
    func test_R14_talkKeyHoldStartsCaptureAndReleaseEndsIt() throws {
        let h = try TestHarness()
        h.session.setCleanupBackend(.off)

        h.pressTalkKey()
        h.speakWhileHeld("ignored while off")
        h.releaseTalkKey()
        h.clock.advance(by: .milliseconds(200))
        XCTAssertEqual(h.session.micState, .closed)
        XCTAssertFalse(h.session.panel.isVisible)
        XCTAssertTrue(h.session.insertRequests.isEmpty)

        h.latchOn()
        h.focusEditable()
        XCTAssertEqual(h.session.micState, .closed)

        h.pressTalkKey()
        XCTAssertEqual(h.session.micState, .open)
        XCTAssertEqual(h.session.panel.text, MenuText.panelListening)
        h.speakWhileHeld("hello there")
        h.releaseTalkKey()
        h.clock.advance(by: .milliseconds(200))

        XCTAssertEqual(h.session.insertRequests.count, 1)
        XCTAssertFalse(h.session.panel.isVisible)
    }
}
