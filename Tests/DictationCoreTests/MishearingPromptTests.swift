import DictationCore
import XCTest

/// R226: the prompt fixes obvious speech-recognition mishearings only when context makes them clear.
final class MishearingPromptTests: XCTestCase {
    func test_R226_promptFixesClearMishearingsWithExamples() {
        let p = DictationCore.CleanupPrompt.text
        XCTAssertTrue(p.lowercased().contains("mishearing"))
        XCTAssertTrue(p.contains("one of the coolest things I've ever built, by a long way"))
        XCTAssertTrue(p.contains("Meet me at the bar"), "needs an example where 'bar' is correct")
    }
}
