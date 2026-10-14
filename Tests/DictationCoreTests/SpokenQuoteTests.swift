@testable import DictationCore
import Foundation
import XCTest

/// R225: spoken "quote" is markup. Cues become ⟦QUOTE⟧/⟦/QUOTE⟧ tokens for the gateway, the local
/// rules render straight double quotes, a noun "quote" stays, and tokens never reach the field.
final class SpokenQuoteTests: XCTestCase {
    private final class Capture: GatewayHTTPTransport {
        let reply: String
        var bodies: [String] = []
        init(reply: String) { self.reply = reply }
        func send(_ request: URLRequest, completion: @escaping (Result<(Data, Int), Error>) -> Void) {
            bodies.append(String(data: request.httpBody ?? Data(), encoding: .utf8) ?? "")
            completion(.success((try! JSONSerialization.data(withJSONObject: ["text": reply]), 200)))
        }
    }

    private func dictate(_ raw: String, gateway: Capture? = nil) throws -> String {
        let h = try TestHarness()
        if let gateway {
            h.session.setGatewayCleaner(GatewayCleaner(
                config: GatewayConfig(url: URL(string: "https://gateway.invalid")!, key: "test-only-key"),
                transport: gateway))
            h.session.setCleanupBackend(.gateway)
        } else {
            h.session.setCleanupBackend(.off)
        }
        h.latchOn()
        h.focusEditable(role: .textArea)
        h.pressTalkKey()
        h.speakWhileHeld(raw)
        h.releaseTalkKey()
        h.clock.advance(by: .milliseconds(250))
        return try XCTUnwrap(h.session.insertRequests.first).text
    }

    func test_R225_localExplicitQuotePairsBecomeSpeechMarks() throws {
        XCTAssertEqual(try dictate("he said quote ship it today end quote and left"), "He said \"ship it today\" and left.")
        XCTAssertEqual(try dictate("she wrote quote not yet unquote"), "She wrote \"not yet\".")
        XCTAssertEqual(try dictate("the sign says quote closed close quote"), "The sign says \"closed\".")
    }

    func test_R225_localUnclosedQuoteRunsToSentenceEnd() throws {
        XCTAssertEqual(try dictate("so it was meant to be quote this is actually really fucking cool"),
                       "So it was meant to be \"this is actually really fucking cool\".")
    }

    func test_R225_quoteAsANounIsUntouched() throws {
        XCTAssertEqual(try dictate("send me a quote for the job"), "Send me a quote for the job.")
    }

    func test_R225_gatewayReceivesQuoteTokensNotCueWords() throws {
        let g = Capture(reply: "He said \"ship it\".")
        _ = try dictate("he said quote ship it end quote", gateway: g)
        let body = try XCTUnwrap(g.bodies.first)
        XCTAssertTrue(body.contains("⟦QUOTE⟧"), body)
        XCTAssertTrue(body.contains("⟦/QUOTE⟧"), body)
        let noun = Capture(reply: "Send me a quote for the job.")
        _ = try dictate("send me a quote for the job", gateway: noun)
        XCTAssertFalse(try XCTUnwrap(noun.bodies.first).contains("⟦QUOTE⟧"))
    }

    func test_R225_leakedTokensAreStrippedFromInsertedText() throws {
        let t = try dictate("he said quote ship it end quote", gateway: Capture(reply: "He said ⟦QUOTE⟧ship it⟦/QUOTE⟧."))
        XCTAssertFalse(t.contains("⟦"), t)
        XCTAssertFalse(t.contains("QUOTE"), t)
    }

    func test_R225_promptExplainsQuoteTokensWithExamples() {
        let p = DictationCore.CleanupPrompt.text
        XCTAssertTrue(p.contains("⟦QUOTE⟧"))
        XCTAssertTrue(p.contains("So it was meant to be \"this is actually really fucking cool\"."))
        XCTAssertTrue(p.lowercased().contains("never output"))
    }
}
