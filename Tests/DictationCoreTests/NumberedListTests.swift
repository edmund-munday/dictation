@testable import DictationCore
import XCTest

/// R220-R221: dictated enumerations become numbered lists; ordinary numbers stay in sentences.
final class NumberedListTests: XCTestCase {
    private func insert(_ raw: String, role: FieldRole = .textArea) throws -> String {
        let h = try TestHarness()
        h.session.setCleanupBackend(.off)
        h.latchOn()
        h.focusEditable(role: role)
        h.pressTalkKey()
        h.speakWhileHeld(raw)
        h.releaseTalkKey()
        h.clock.advance(by: .milliseconds(250))
        XCTAssertEqual(h.session.insertRequests.count, 1)
        XCTAssertTrue(h.session.emittedKeyEvents.isEmpty)
        return try XCTUnwrap(h.session.insertRequests.first).text
    }

    func test_R221_numberWordsBecomeNumberedListWithLeadIn() throws {
        XCTAssertEqual(
            try insert("my priorities today are one fix the build two ship the app three call sam"),
            "My priorities today are:\n1. Fix the build\n2. Ship the app\n3. Call sam")
    }

    func test_R221_ordinalsBecomeNumberedListWithoutLeadIn() throws {
        XCTAssertEqual(
            try insert("first check the logs second restart the worker third ping me"),
            "1. Check the logs\n2. Restart the worker\n3. Ping me")
    }

    func test_R221_commasBetweenItemsAreDropped() throws {
        XCTAssertEqual(
            try insert("to do one buy milk comma two walk the dog comma three email mum"),
            "To do:\n1. Buy milk\n2. Walk the dog\n3. Email mum")
    }

    func test_R221_ordinaryNumbersStayInSentences() throws {
        XCTAssertEqual(try insert("let's meet at three pm"), "Let's meet at three pm.")
        XCTAssertEqual(try insert("i have two kids and one dog"), "I have two kids and one dog.")
        XCTAssertEqual(try insert("i have one dog and two cats"), "I have one dog and two cats.")
        XCTAssertFalse(try insert("first we check the logs then second guess it").contains("\n"))
    }

    func test_R221_listStaysInlineInTerminalsAndSingleLineFields() throws {
        for role in [FieldRole.terminal, .textField] {
            let t = try insert("one fix the build two ship the app three call sam", role: role)
            XCTAssertFalse(t.contains("\n"), "\(role): \(t)")
            XCTAssertTrue(t.contains("1. Fix the build"), "\(role): \(t)")
        }
    }

    func test_R220_promptDescribesNumberedListsWithExamples() {
        let p = DictationCore.CleanupPrompt.text.lowercased()
        XCTAssertTrue(p.contains("numbered list"))
        XCTAssertTrue(p.contains("\n1. "))
        XCTAssertTrue(p.contains("\n2. "))
        XCTAssertTrue(p.contains("meet at three pm"), "needs a non-list number example")
    }
}
