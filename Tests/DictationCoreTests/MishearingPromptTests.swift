import DictationCore
import XCTest

/// R226: the prompt fixes obvious speech-recognition mishearings only when context makes them clear.
final class MishearingPromptTests: XCTestCase {
    func test_R226_promptFixesClearMishearingsWithExamples() {
        let p = DictationCore.CleanupPrompt.text
        XCTAssertTrue(p.lowercased().contains("mishearing"))
        XCTAssertTrue(p.contains("One of the coolest things I've ever built, by a long way."))
        XCTAssertTrue(p.contains("Meet me at the bar"), "needs an example where 'bar' is correct")
    }
}

final class GrokNamesPromptTests: XCTestCase {
    func test_R226_promptKnowsGrokBotAndGrokBuild() {
        let p = DictationCore.CleanupPrompt.text
        XCTAssertTrue(p.contains("Grok Bot"))
        XCTAssertTrue(p.contains("Grok Build"))
        XCTAssertTrue(p.contains("my Grok button"), "example of the misheard name")
    }
}
