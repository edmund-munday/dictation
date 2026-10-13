import XCTest
import DictationCore

final class LatchMenuTests: XCTestCase {
    func test_R2_enablingArmsToolMicStaysClosedUntilTalkKey() throws {
        let h = try TestHarness()
        h.clearFocus()
        h.latchOn()

        XCTAssertTrue(h.session.isLatchOn)
        XCTAssertEqual(h.session.micState, .closed)
        XCTAssertEqual(h.session.menuText, MenuText.readyToTalk)
    }

    func test_R3_choosingOffClosesMicWipesBufferAndShowsOffMenu() throws {
        let h = try TestHarness()
        h.readyListening()
        h.speakOnly("hello")
        h.latchOff()
        h.session.reportDeviceClose(DeviceCloseResult(timestamp: h.clock.now, isClosed: true))

        XCTAssertEqual(h.session.micState, .closed)
        XCTAssertTrue(h.session.bufferStatus.isWiped)
        XCTAssertEqual(h.session.menuText, MenuText.off)
    }

    func test_R7_startsOffAndNeverReopensMicUntilLatchOn() throws {
        let h = try TestHarness()

        XCTAssertFalse(h.session.isLatchOn)
        XCTAssertEqual(h.session.micState, .closed)
        XCTAssertEqual(h.session.menuText, MenuText.off)

        h.clock.advance(by: .seconds(60))
        XCTAssertEqual(h.session.micState, .closed)
        XCTAssertFalse(h.session.isLatchOn)
    }

    func test_R8_micStillOpen300msAfterOffBecomesFault() throws {
        let h = try TestHarness()
        h.readyListening()
        h.latchOff()
        h.session.reportDeviceClose(DeviceCloseResult(timestamp: h.clock.now, isClosed: false))
        h.clock.advance(by: .milliseconds(300))

        XCTAssertTrue(h.session.menuText.hasPrefix(MenuText.off))
        XCTAssertTrue(h.session.menuText.count > MenuText.off.count, "fault reason must be appended")
        h.focusEditable()
        h.speakAndWait("should not insert")
        XCTAssertTrue(h.session.insertRequests.isEmpty)
    }

    func test_R9_talkKeyHeldOverEditableFieldShowsListeningMenu() throws {
        let h = try TestHarness()
        h.latchOn()
        h.focusEditable()
        h.pressTalkKey()

        XCTAssertEqual(h.session.menuText, MenuText.listeningHold)
    }

    func test_R10_micPermissionDeniedShowsRefusedAndInsertsNothing() throws {
        let h = try TestHarness()
        h.session.setMicPermission(.denied)
        h.latchOn()
        h.focusEditable()
        h.speakAndWait("secret")

        XCTAssertEqual(h.session.menuText, MenuText.refused)
        XCTAssertTrue(h.session.insertRequests.isEmpty)
    }

    func test_R11_noIdleAutoOffAfterEightHours() throws {
        let h = try TestHarness()
        h.readyListening()
        h.clock.advance(by: .hours(8))

        XCTAssertTrue(h.session.isLatchOn)
        XCTAssertEqual(h.session.micState, .open)
    }
}
