import XCTest
import DictationCore

final class HoldToTalkTests: XCTestCase {
    func test_R104_holdingTalkKeyOpensMicAndShowsListeningPanel() throws {
        let h = try TestHarness()
        h.latchOn()
        h.focusEditable()
        XCTAssertEqual(h.session.micState, .closed)

        h.pressTalkKey()

        XCTAssertEqual(h.session.micState, .open)
        XCTAssertTrue(h.session.panel.isVisible)
        XCTAssertEqual(h.session.panel.text, MenuText.panelListening)
    }

    func test_R105_panelShowsPartialTranscriptWhileHeld() throws {
        let h = try TestHarness()
        h.latchOn()
        h.focusEditable()
        h.pressTalkKey()
        h.speakWhileHeld("ship", isFinal: false)
        XCTAssertEqual(h.session.panel.text, "ship")

        h.speakWhileHeld("ship it", isFinal: false)
        XCTAssertEqual(h.session.panel.text, "ship it")
        XCTAssertTrue(h.session.insertRequests.isEmpty)
    }

    func test_R106_releaseShowsCleaningUpThenHidesAfterInsert() throws {
        let h = try TestHarness()
        h.session.setCleanupBackend(.off)
        h.latchOn()
        h.focusEditable()
        h.pressTalkKey()
        h.speakWhileHeld("hello there")
        h.releaseTalkKey()

        XCTAssertEqual(h.session.panel.text, MenuText.panelCleaning)
        XCTAssertTrue(h.session.insertRequests.isEmpty)

        h.clock.advance(by: .milliseconds(200))
        XCTAssertEqual(h.session.insertRequests.count, 1)
        XCTAssertFalse(h.session.panel.isVisible)
    }

    func test_R107_insertsIntoFieldFocusedWhenTalkKeyWentDown() throws {
        let h = try TestHarness()
        let original = FocusIdentity(pid: 42, elementID: "field-1")
        let moved = FocusIdentity(pid: 42, elementID: "field-2")
        h.session.setCleanupBackend(.off)
        h.latchOn()
        h.focusEditable(identity: original)
        h.pressTalkKey()
        h.focusEditable(identity: moved)
        h.speakWhileHeld("hello there")
        h.releaseTalkKey()
        h.clock.advance(by: .milliseconds(200))

        XCTAssertEqual(h.session.insertRequests.count, 1)
        XCTAssertEqual(h.session.insertRequests.first?.target, original)
    }

    func test_R107_missingOriginalFieldShowsCopyFallback() throws {
        let h = try TestHarness()
        h.session.setCleanupBackend(.off)
        h.latchOn()
        h.focusEditable()
        h.pressTalkKey()
        h.session.ingestFocus(
            FocusSnapshot(
                timestamp: h.clock.now,
                role: .textField,
                identity: h.fieldIdentity,
                exists: false
            )
        )
        h.speakWhileHeld("hello there")
        h.releaseTalkKey()
        h.clock.advance(by: .milliseconds(200))

        XCTAssertTrue(h.session.insertRequests.isEmpty)
        XCTAssertEqual(h.session.panel.text, MenuText.insertFailed)
        XCTAssertEqual(h.session.panel.buttons.map(\.title), ["Copy"])
    }

    func test_R108_noEditableFieldShowsCopyPanelAndInsertsNothing() throws {
        let h = try TestHarness()
        h.session.setCleanupBackend(.off)
        h.latchOn()
        h.clearFocus()
        h.pressTalkKey()
        h.speakWhileHeld("nowhere to go")
        h.releaseTalkKey()
        h.clock.advance(by: .milliseconds(200))

        XCTAssertTrue(h.session.insertRequests.isEmpty)
        XCTAssertEqual(h.session.panel.text, MenuText.panelNoField)
        XCTAssertEqual(h.session.panel.buttons.map(\.title), ["Copy"])
    }

    func test_R109_shortHoldOrSilenceInsertsNothingAndClosesPanel() throws {
        let short = try TestHarness()
        let cli = try short.installFakeCLI(result: "Nope.", name: "short-cli")
        short.session.setCleanupBackend(.cursorCLI, executablePath: cli.path)
        short.latchOn()
        short.focusEditable()
        short.pressTalkKey()
        XCTAssertEqual(short.session.panel.text, MenuText.panelListening)
        short.speakWhileHeld("too short")
        short.clock.advance(by: .milliseconds(299))
        short.releaseTalkKey()

        XCTAssertTrue(short.session.insertRequests.isEmpty)
        XCTAssertFalse(short.session.panel.isVisible)
        XCTAssertEqual(short.session.cliInvocations.count, 0)
        XCTAssertEqual(short.fakeCLILog(name: "short-cli"), "")

        let silent = try TestHarness()
        silent.session.setCleanupBackend(.cursorCLI, executablePath: cli.path)
        silent.latchOn()
        silent.focusEditable()
        silent.pressTalkKey()
        silent.clock.advance(by: .milliseconds(1000))
        silent.releaseTalkKey()
        silent.clock.advance(by: .milliseconds(200))

        XCTAssertTrue(silent.session.insertRequests.isEmpty)
        XCTAssertFalse(silent.session.panel.isVisible)
        XCTAssertEqual(silent.session.cliInvocations.count, 0)
    }

    func test_R110_escapeWhileHeldCancelsWithoutLlmOrInsert() throws {
        let h = try TestHarness()
        let cli = try h.installFakeCLI(result: "Nope.", name: "cancel-cli")
        h.session.setCleanupBackend(.cursorCLI, executablePath: cli.path)
        h.latchOn()
        h.focusEditable()
        h.pressTalkKey()
        XCTAssertEqual(h.session.panel.text, MenuText.panelListening)
        h.speakWhileHeld("forget this")
        h.pressOtherKey(.escape)

        XCTAssertTrue(h.session.insertRequests.isEmpty)
        XCTAssertFalse(h.session.panel.isVisible)
        XCTAssertEqual(h.session.cliInvocations.count, 0)
        XCTAssertEqual(h.fakeCLILog(name: "cancel-cli"), "")
    }

    func test_R115_holdOf120SecondsStopsAsReleaseAndNotesMaximum() throws {
        let h = try TestHarness()
        h.session.setCleanupBackend(.off)
        h.latchOn()
        h.focusEditable()
        h.pressTalkKey()
        h.speakWhileHeld("a very long thought")
        h.clock.advance(by: .seconds(120))

        XCTAssertTrue(h.session.panel.text?.contains(MenuText.panelMaxLength) == true)
        XCTAssertEqual(h.session.insertRequests.count, 1)
        XCTAssertEqual(h.session.micState, .closed)
    }

    func test_R119_disablingMidHoldInsertsNothingAndClosesMic() throws {
        let h = try TestHarness()
        h.session.setCleanupBackend(.off)
        h.latchOn()
        h.focusEditable()
        h.pressTalkKey()
        XCTAssertEqual(h.session.micState, .open)
        XCTAssertEqual(h.session.panel.text, MenuText.panelListening)
        h.speakWhileHeld("do not keep")
        h.latchOff()
        h.releaseTalkKey()
        h.clock.advance(by: .milliseconds(200))

        XCTAssertTrue(h.session.insertRequests.isEmpty)
        XCTAssertEqual(h.session.micState, .closed)
        XCTAssertFalse(h.session.panel.isVisible)
    }
}
