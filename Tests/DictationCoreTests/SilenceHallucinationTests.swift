import XCTest
@testable import DictationCore

final class SilenceHallucinationTests: XCTestCase {
    private func hold(_ h: TestHarness, saying text: String) {
        h.pressTalkKey()
        h.speakWhileHeld(text)
        h.releaseTalkKey()
        h.clock.advance(by: .milliseconds(200))
    }

    func test_R306_inventedCreditsInsertNothing() throws {
        for phrase in ["Subs by www.zeoranger.co.uk", "Thanks for watching!", "Thank you for watching.",
                       "Subtitles by the Amara.org community", "you"] {
            let h = try TestHarness()
            h.session.setCleanupBackend(.off)
            h.latchOn()
            h.focusEditable()
            hold(h, saying: phrase)
            XCTAssertTrue(h.session.insertRequests.isEmpty, phrase)
            XCTAssertFalse(h.session.panel.isVisible, phrase)
        }
    }

    func test_R306_inventedCreditWithNoFieldOffersNoCopy() throws {
        let h = try TestHarness()
        h.session.setCleanupBackend(.off)
        h.latchOn()
        h.clearFocus()
        hold(h, saying: "Subs by www.zeoranger.co.uk")
        XCTAssertTrue(h.session.insertRequests.isEmpty)
        XCTAssertNil(h.session.panel.copyText)
    }

    func test_R306_realSentencesMentioningThePhrasesAreInserted() throws {
        for sentence in ["thanks for watching the kids tonight", "add subtitles by friday"] {
            let h = try TestHarness()
            h.session.setCleanupBackend(.off)
            h.latchOn()
            h.focusEditable()
            hold(h, saying: sentence)
            XCTAssertEqual(h.session.insertRequests.count, 1, sentence)
        }
    }
}
