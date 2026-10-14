@testable import DictationCore
import XCTest

/// R224: emphasis words and swearing are kept; only real fillers and self-correction cues go.
final class EmphasisWordsTests: XCTestCase {
    private func local(_ raw: String) throws -> String {
        let h = try TestHarness()
        h.session.setCleanupBackend(.off)
        h.latchOn()
        h.focusEditable(role: .textArea)
        h.pressTalkKey()
        h.speakWhileHeld(raw)
        h.releaseTalkKey()
        h.clock.advance(by: .milliseconds(250))
        return try XCTUnwrap(h.session.insertRequests.first).text
    }

    func test_R224_localRulesKeepEmphasisWordsAndSwearing() throws {
        XCTAssertEqual(try local("this is actually really fucking cool"), "This is actually really fucking cool.")
        XCTAssertEqual(try local("it basically just works"), "It basically just works.")
        XCTAssertEqual(try local("i literally honestly love it"), "I literally honestly love it.")
    }

    func test_R224_selfCorrectionCuesAndFillersStillGo() throws {
        XCTAssertEqual(try local("push it to thursday actually i mean friday"), "Push it to Friday.")
        XCTAssertEqual(try local("um this is uh cool"), "This is cool.")
    }

    func test_R224_promptKeepsEmphasisWithExamples() {
        let p = DictationCore.CleanupPrompt.text
        XCTAssertTrue(p.contains("This is actually really fucking cool."))
        XCTAssertTrue(p.lowercased().contains("basically"))
        XCTAssertTrue(p.lowercased().contains("swear"))
        XCTAssertFalse(p.contains("\"like\", \"you know\") and stutters"), "like/you know are not blanket fillers")
    }
}
