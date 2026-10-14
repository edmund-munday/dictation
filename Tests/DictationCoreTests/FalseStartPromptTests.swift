import DictationCore
import XCTest

/// R227: false starts, restarts and thinking-aloud asides are removed; message swearing stays.
final class FalseStartPromptTests: XCTestCase {
    func test_R227_promptRemovesRestartsAndAsidesWithExamples() {
        let p = DictationCore.CleanupPrompt.text
        XCTAssertTrue(p.lowercased().contains("false start"))
        XCTAssertTrue(p.contains("what am I doing"))
        XCTAssertTrue(p.contains("Output: This is me testing the new dictation tool that I built."))
        XCTAssertTrue(p.contains("This is actually really fucking cool."), "swearing in the message stays")
    }
}

final class NoRestartAsidePromptTests: XCTestCase {
    func test_R227_asidesWithoutARestartAreKept() {
        let p = DictationCore.CleanupPrompt.text
        XCTAssertTrue(p.contains("Output: Alright, so the build passed, which is great."))
        XCTAssertTrue(p.lowercased().contains("only when"), "drop only on a genuine restart")
    }
}
