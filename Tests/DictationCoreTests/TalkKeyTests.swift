import XCTest
import DictationCore

final class TalkKeyTests: XCTestCase {
    func test_R120_talkKeyDefaultsToLeftCommandAndCanChange() throws {
        let h = try TestHarness()
        h.session.setCleanupBackend(.off)
        XCTAssertEqual(h.session.settings.talkKey, .leftCommand)

        h.latchOn()
        h.focusEditable()
        h.pressTalkKey(side: .right)
        XCTAssertFalse(h.session.panel.isVisible)
        h.releaseTalkKey(side: .right)

        h.session.setTalkKey(.rightCommand)
        XCTAssertEqual(h.session.settings.talkKey, .rightCommand)
        h.pressTalkKey(side: .left)
        XCTAssertFalse(h.session.panel.isVisible)
        h.releaseTalkKey(side: .left)

        h.pressTalkKey(side: .right)
        XCTAssertEqual(h.session.panel.text, MenuText.panelListening)
        h.speakWhileHeld("left command")
        h.releaseTalkKey(side: .right)
        h.clock.advance(by: .milliseconds(200))
        XCTAssertEqual(h.session.insertRequests.count, 1)

        h.session.setTalkKey(.eitherCommand)
        XCTAssertEqual(h.session.settings.talkKey, .eitherCommand)
        h.pressTalkKey(side: .right)
        XCTAssertEqual(h.session.panel.text, MenuText.panelListening)
        h.releaseTalkKey(side: .right)
        h.pressTalkKey(side: .left)
        XCTAssertEqual(h.session.panel.text, MenuText.panelListening)
    }

    func test_R121_commandWithAnotherKeyAlreadyDownDoesNotStartCapture() throws {
        let h = try TestHarness()
        let cli = try h.installFakeCLI(result: "Nope.", name: "chord-cli")
        h.session.setCleanupBackend(.cursorCLI, executablePath: cli.path)
        h.latchOn()
        h.focusEditable()
        XCTAssertEqual(h.session.micState, .closed)

        h.pressTalkKey(otherKeysAlreadyDown: [.modifier("shift")])
        h.speakWhileHeld("chorded")
        h.releaseTalkKey()
        h.clock.advance(by: .milliseconds(200))

        XCTAssertFalse(h.session.panel.isVisible)
        XCTAssertEqual(h.session.micState, .closed)
        XCTAssertTrue(h.session.insertRequests.isEmpty)
        XCTAssertEqual(h.session.cliInvocations.count, 0)
        XCTAssertEqual(h.fakeCLILog(name: "chord-cli"), "")
    }

    func test_R122_otherKeyDuringHoldCancelsAndReachesTheApp() throws {
        let h = try TestHarness()
        let cli = try h.installFakeCLI(result: "Nope.", name: "shortcut-cli")
        h.session.setCleanupBackend(.cursorCLI, executablePath: cli.path)
        h.latchOn()
        h.focusEditable()
        h.pressTalkKey()
        XCTAssertEqual(h.session.panel.text, MenuText.panelListening)
        h.speakWhileHeld("cancel me")
        h.pressOtherKey(.character("k"))

        XCTAssertEqual(h.session.emittedKeyEvents, [EmittedKeyEvent(kind: .character("k"))])
        XCTAssertFalse(h.session.panel.isVisible)
        XCTAssertTrue(h.session.insertRequests.isEmpty)
        XCTAssertEqual(h.session.cliInvocations.count, 0)
        XCTAssertEqual(h.fakeCLILog(name: "shortcut-cli"), "")
        XCTAssertEqual(h.session.micState, .closed)
    }
}
