import XCTest
import DictationCore

final class TimingTests: XCTestCase {
    func test_R52_insertWithin100msOfLlmOr200msOfLocalRelease() throws {
        let local = try TestHarness()
        local.session.setCleanupBackend(.off)
        local.latchOn()
        local.focusEditable()
        local.pressTalkKey()
        local.speakWhileHeld("hello there")
        local.releaseTalkKey()
        local.clock.advance(by: .milliseconds(200))

        XCTAssertEqual(local.session.insertRequests.count, 1)
        XCTAssertEqual(local.session.insertRequests.first?.text, "Hello there.")

        let llm = try TestHarness()
        let cli = try llm.installFakeCLI(result: "Hello there.", delayMs: 0, name: "fast-llm")
        llm.session.setCleanupBackend(.cursorCLI, executablePath: cli.path)
        llm.latchOn()
        llm.focusEditable()
        llm.pressTalkKey()
        llm.speakWhileHeld("hello there")
        llm.releaseTalkKey()
        llm.clock.advance(by: .milliseconds(100))

        XCTAssertEqual(llm.session.insertRequests.count, 1)
        XCTAssertEqual(llm.session.insertRequests.first?.text, "Hello there.")
        XCTAssertEqual(llm.session.cliInvocations.count, 1)
    }
}
