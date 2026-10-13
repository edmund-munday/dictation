import XCTest
import DictationCore

final class SetupPermissionTests: XCTestCase {
    func test_R96_missingAccessibilityShowsMenuAndInsertsNothing() throws {
        let h = try TestHarness()
        h.session.setAccessibilityPermission(false)
        h.readyListening()
        h.speakAndWait("cannot type")

        XCTAssertEqual(h.session.menuText, MenuText.accessibilityMissing)
        XCTAssertTrue(h.session.insertRequests.isEmpty)
    }

    func test_R97_missingInputMonitoringCannotDetectTalkKey() throws {
        let h = try TestHarness()
        h.session.setInputMonitoringPermission(false)
        h.latchOn()
        h.focusEditable()

        XCTAssertEqual(h.session.menuText, MenuText.needsInputMonitoring)

        h.pressTalkKey()
        h.speakWhileHeld("should not capture")
        h.releaseTalkKey()
        h.clock.advance(by: .milliseconds(200))

        XCTAssertTrue(h.session.insertRequests.isEmpty)
        XCTAssertFalse(h.session.panel.isVisible)
        XCTAssertEqual(h.session.micState, .closed)
    }

    func test_R98_noOnDeviceRecognizerStopsSetupAndStaysOff() throws {
        let h = try TestHarness()
        h.session.setOnDeviceRecognizerAvailable(false)

        XCTAssertEqual(h.session.setupMessage, MenuText.noRecognizer)
        XCTAssertFalse(h.session.isSetupComplete)
        XCTAssertFalse(h.session.isLatchOn)
        XCTAssertEqual(h.session.micState, .closed)

        h.latchOn()
        XCTAssertFalse(h.session.isLatchOn)
        XCTAssertEqual(h.session.micState, .closed)
    }

    func test_R99_systemRecognizerUsedOnlyWhenOnDeviceReported() throws {
        let h = try TestHarness()
        h.session.setBundledModelLoadable(false)
        h.session.setSystemRecognizerReportsOnDevice(false)

        XCTAssertEqual(h.session.setupMessage, MenuText.noRecognizer)
        XCTAssertFalse(h.session.isSetupComplete)
        h.latchOn()
        h.focusEditable()
        h.speakAndWait("should not use server speech")
        XCTAssertTrue(h.session.insertRequests.isEmpty)
        XCTAssertEqual(h.session.micState, .closed)
        XCTAssertNotEqual(h.session.menuText, MenuText.bundledUnavailable)
    }

    func test_R100_bundledModelUnavailableFallsBackToOnDeviceSystemSpeech() throws {
        let h = try TestHarness()
        h.session.setBundledModelLoadable(false)
        h.session.setSystemRecognizerReportsOnDevice(true)
        h.readyListening()

        XCTAssertTrue(h.session.menuText.contains(MenuText.bundledUnavailable))
        h.speakAndWait("fallback works")
        XCTAssertEqual(h.session.insertRequests.count, 1)
    }

    func test_R101_permissionRevokedClosesMicToRefusedOrFaultAndNeverSilentReopen() throws {
        let h = try TestHarness()
        h.readyListening()
        h.session.setMicPermission(.revoked)

        XCTAssertEqual(h.session.micState, .closed)
        XCTAssertTrue(
            h.session.menuText == MenuText.refused
                || h.session.menuText.hasPrefix(MenuText.off)
        )
        h.clock.advance(by: .seconds(10))
        XCTAssertEqual(h.session.micState, .closed)
        h.speakAndWait("no silent reopen")
        XCTAssertTrue(h.session.insertRequests.isEmpty)
    }
}
