@testable import DictationCore
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest

/// R214-R217: spoken punctuation becomes marks (Edmund, 2026-10-14 13:31).
final class SpokenPunctuationTests: XCTestCase {
    private func insertLocal(_ raw: String, role: FieldRole = .textArea) throws -> TestHarness {
        let h = try TestHarness()
        h.session.setCleanupBackend(.off)
        dictate(h, raw, role: role)
        return h
    }

    private func dictate(_ h: TestHarness, _ raw: String, role: FieldRole) {
        h.latchOn()
        h.focusEditable(role: role)
        h.pressTalkKey()
        h.speakWhileHeld(raw)
        h.releaseTalkKey()
        h.clock.advance(by: .milliseconds(250))
    }

    private func text(_ h: TestHarness) throws -> String {
        XCTAssertEqual(h.session.insertRequests.count, 1)
        return try XCTUnwrap(h.session.insertRequests.first).text
    }

    func test_R214_localRulesConvertSpokenPunctuationToMarks() throws {
        let cases: [(String, String)] = [
            ("send the deck comma thanks full stop", "Send the deck, thanks."),
            ("is it ready question mark", "Is it ready?"),
            ("that is great exclamation mark", "That is great!"),
            ("send the deck period", "Send the deck."),
            ("send the deck COMMA thanks", "Send the deck, thanks."),
            ("done full stop next one please", "Done. Next one please."),
        ]
        for (raw, expected) in cases {
            let h = try insertLocal(raw)
            XCTAssertEqual(try text(h), expected, raw)
        }
    }

    func test_R214_localRulesTurnNewLineAndNewParagraphIntoLineBreaksInTextAreas() throws {
        let line = try text(try insertLocal("line one new line line two"))
        XCTAssertTrue(line.contains("\n"), line)
        XCTAssertFalse(line.lowercased().contains("new line"), line)
        XCTAssertTrue(line.hasPrefix("Line one"), line)
        XCTAssertTrue(line.contains("\nLine two"), line)

        let para = try text(try insertLocal("dear team new paragraph thanks for the work"))
        XCTAssertTrue(para.contains("\n\nThanks for the work"), para)
        XCTAssertFalse(para.lowercased().contains("new paragraph"), para)
    }

    func test_R214_neverEndsWithALineBreak() throws {
        let h = try insertLocal("thanks new line")
        let t = try text(h)
        XCTAssertFalse(t.hasSuffix("\n"), t)
        XCTAssertFalse(t.lowercased().contains("new line"), t)
        XCTAssertTrue(h.session.emittedKeyEvents.isEmpty)
    }

    func test_R215_promptAsksForMarksAndOwnPunctuation() {
        let prompt = DictationCore.CleanupPrompt.text.lowercased()
        for phrase in ["comma", "full stop", "period", "question mark", "exclamation mark",
                       "new line", "new paragraph", "line break", "blank line", "minimal",
                       "send the deck, thanks."] {
            XCTAssertTrue(prompt.contains(phrase), "Missing prompt content: \(phrase)")
        }
        XCTAssertFalse(prompt.contains("never convert"))
        XCTAssertFalse(prompt.contains("kept exactly as words"))
    }

    private func gateway(_ h: TestHarness, reply: String) {
        let transport = SPStubTransport(text: reply)
        h.session.setGatewayCleaner(GatewayCleaner(
            config: GatewayConfig(url: URL(string: "https://gateway.invalid")!, key: "test-only-key"),
            transport: transport))
        h.session.setCleanupBackend(.gateway)
    }

    func test_R216_gatewayResultWithMarksIsInserted() throws {
        let cases: [(String, String)] = [
            ("send the deck comma thanks", "Send the deck, thanks."),
            ("can you send the deck question mark", "Can you send the deck?"),
            ("send the deck exclamation mark", "Send the deck!"),
            ("send the deck full stop thanks", "Send the deck. Thanks."),
        ]
        for (raw, reply) in cases {
            let h = try TestHarness()
            gateway(h, reply: reply)
            dictate(h, raw, role: .textArea)
            XCTAssertEqual(h.session.insertRequests.map(\.text), [reply], raw)
        }
    }

    func test_R217_gatewayLineBreaksAreTextInTextAreasAndSpacesInTerminals() throws {
        let reply = "Dear team,\n\nThanks for the work."
        let area = try TestHarness()
        gateway(area, reply: reply)
        dictate(area, "dear team comma new paragraph thanks for the work", role: .textArea)
        XCTAssertEqual(area.session.insertRequests.map(\.text), [reply])
        XCTAssertTrue(area.session.emittedKeyEvents.isEmpty)

        for role in [FieldRole.terminal, .textField, .comboBox] {
            let h = try TestHarness()
            gateway(h, reply: reply)
            dictate(h, "dear team comma new paragraph thanks for the work", role: role)
            let t = try text(h)
            XCTAssertFalse(t.contains("\n"), "\(role): \(t)")
            XCTAssertFalse(t.contains("\r"), "\(role): \(t)")
            XCTAssertTrue(h.session.emittedKeyEvents.isEmpty, "\(role)")
        }
    }
}

private final class SPStubTransport: GatewayHTTPTransport {
    let text: String
    init(text: String) { self.text = text }
    func send(_ request: URLRequest, completion: @escaping (Result<(Data, Int), Error>) -> Void) {
        let data = try! JSONSerialization.data(withJSONObject: ["text": text])
        completion(.success((data, 200)))
    }
}
