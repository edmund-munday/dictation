import AppKit
import ApplicationServices
import DictationCore
import DictationMac
import Foundation
import XCTest

final class AccessibilityRetryTests: XCTestCase {
    func test_R299_temporaryEnableResultsAreNotCached() {
        for error in [AXError.cannotComplete, .notEnoughPrecision, .failure, .apiDisabled,
                      .invalidUIElement, .noValue] {
            let f = AccessibilityRetryFixture()
            f.fake.enableResult = error

            f.activate()
            f.activate()

            XCTAssertEqual(f.fake.setPIDs, [f.pid, f.pid], "Temporary error: \(error.rawValue)")
            XCTAssertTrue(f.fake.pauses.isEmpty)
        }
    }

    func test_R299_R300_unsupportedEnableIsCachedAndNeverPauses() {
        for error in [AXError.attributeUnsupported, .notImplemented, .actionUnsupported] {
            let f = AccessibilityRetryFixture()
            f.fake.enableResult = error

            f.activate()
            f.activate()
            XCTAssertNil(f.bridge.focusedElementForTesting())
            XCTAssertNil(f.bridge.focusedElementForTesting())

            XCTAssertEqual(f.fake.setPIDs, [f.pid])
            XCTAssertEqual(f.fake.lookupPIDs, [f.pid, f.pid])
            XCTAssertTrue(f.fake.pauses.isEmpty)
        }
    }

    func test_R300_freshPidReenablesPausesOnceAndRetriesOnceReturningElement() throws {
        let f = AccessibilityRetryFixture()
        let element = AXUIElementCreateApplication(1)
        f.fake.focusResults = [nil, element]

        let found = try XCTUnwrap(f.bridge.focusedElementForTesting())

        XCTAssertTrue(CFEqual(found, element))
        XCTAssertEqual(f.fake.setPIDs, [f.pid])
        XCTAssertEqual(f.fake.lookupPIDs, [f.pid, f.pid])
        XCTAssertEqual(f.fake.pauses, [0.15])
        XCTAssertEqual(f.fake.events, ["lookup", "set", "pause", "lookup"])
    }

    func test_R300_reenableIgnoresSuccessfulCacheUntilPidProducesFocus() throws {
        let f = AccessibilityRetryFixture()
        let element = AXUIElementCreateApplication(1)
        f.activate()
        f.activate()
        XCTAssertEqual(f.fake.setPIDs, [f.pid], "A successful activation enable is cached")
        f.fake.focusResults = [nil, element]

        let found = try XCTUnwrap(f.bridge.focusedElementForTesting())

        XCTAssertTrue(CFEqual(found, element))
        XCTAssertEqual(f.fake.setPIDs, [f.pid, f.pid], "The recovery enable bypasses that cache")
        XCTAssertEqual(f.fake.lookupPIDs, [f.pid, f.pid])
        XCTAssertEqual(f.fake.pauses, [0.15])
    }

    func test_R300_R302_retryStillNilReturnsOriginalNoneSnapshotWithOnlyOnePause() {
        let f = AccessibilityRetryFixture()
        // A temporary enable failure must still get exactly one retry, never a loop.
        f.fake.enableResult = .cannotComplete

        let snapshot = f.bridge.currentFocus(at: .seconds(7))

        XCTAssertEqual(snapshot, FocusSnapshot(timestamp: .seconds(7), role: .none, identity: .none))
        XCTAssertEqual(f.fake.setPIDs, [f.pid])
        XCTAssertEqual(f.fake.lookupPIDs, [f.pid, f.pid])
        XCTAssertEqual(f.fake.pauses, [0.15])
        XCTAssertEqual(f.fake.events, ["lookup", "set", "pause", "lookup"])
    }

    func test_R302_retryFailureKeepsR238CopyPanelExactlyOnce() throws {
        let f = AccessibilityRetryFixture()
        let h = try MacHarness()
        h.session.setCleanupBackend(.off)
        let board = NSPasteboard(name: NSPasteboard.Name("dictation-ax-retry-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        let inserter = RecordingInserter(succeeds: false)
        let coordinator = InsertionCoordinator(session: h.session, inserter: inserter, pasteboard: board)
        h.session.ingestFocus(f.bridge.currentFocus(at: h.clock.now))
        h.session.ingestTalkKey(TalkKeyEvent(timestamp: h.clock.now, identity: .command(.left), isDown: true))
        h.clock.advance(by: .milliseconds(500))
        h.session.ingestRecognizerTokens([
            RecognizerToken(text: "hello there", start: .zero, end: h.clock.now, isFinal: true),
        ])
        h.session.ingestTalkKey(TalkKeyEvent(timestamp: h.clock.now, identity: .command(.left), isDown: false))
        h.clock.advance(by: .milliseconds(250))
        coordinator.poll()

        XCTAssertTrue(h.session.panel.isVisible)
        XCTAssertEqual(h.session.panel.text, "No text field was focused.")
        XCTAssertEqual(h.session.panel.buttons.map(\.title), ["Copy"])
        XCTAssertEqual(h.session.panel.copyText, "Hello there.")
        let panel = h.session.panel
        coordinator.poll()
        XCTAssertEqual(h.session.panel, panel)
        XCTAssertTrue(inserter.inserted.isEmpty)
        XCTAssertTrue(h.session.insertRequests.isEmpty)
        XCTAssertEqual(f.fake.pauses, [0.15])
        coordinator.tap(button: "Copy")
        XCTAssertEqual(board.string(forType: .string), "Hello there.")
    }

    func test_R301_firstLookupFindsElementWithoutSetPauseOrSecondLookup() throws {
        let f = AccessibilityRetryFixture()
        let element = AXUIElementCreateApplication(1)
        f.fake.focusResults = [element]

        let found = try XCTUnwrap(f.bridge.focusedElementForTesting())

        XCTAssertTrue(CFEqual(found, element))
        XCTAssertTrue(f.fake.setPIDs.isEmpty)
        XCTAssertTrue(f.fake.pauses.isEmpty)
        XCTAssertEqual(f.fake.lookupPIDs, [f.pid])
        XCTAssertEqual(f.fake.events, ["lookup"])
    }

    func test_R300_pidThatAlreadyProducedFocusDoesNotRetryLaterNil() {
        let f = AccessibilityRetryFixture()
        f.fake.focusResults = [nil, AXUIElementCreateApplication(1), nil]
        XCTAssertNotNil(f.bridge.focusedElementForTesting())

        XCTAssertNil(f.bridge.focusedElementForTesting())

        XCTAssertEqual(f.fake.setPIDs, [f.pid])
        XCTAssertEqual(f.fake.lookupPIDs, [f.pid, f.pid, f.pid])
        XCTAssertEqual(f.fake.pauses, [0.15], "The later nil lookup adds no delay")
    }

    func test_R300_successOnFirstLookupAlsoSuppressesLaterNilRetry() {
        let f = AccessibilityRetryFixture()
        f.fake.focusResults = [AXUIElementCreateApplication(1), nil]
        XCTAssertNotNil(f.bridge.focusedElementForTesting())

        XCTAssertNil(f.bridge.focusedElementForTesting())

        XCTAssertTrue(f.fake.setPIDs.isEmpty)
        XCTAssertTrue(f.fake.pauses.isEmpty)
        XCTAssertEqual(f.fake.lookupPIDs, [f.pid, f.pid])
    }

    func test_R300_newEnableResetsPreviouslySeenFocus() {
        let f = AccessibilityRetryFixture()
        f.fake.enableResult = .cannotComplete
        f.activate()
        f.fake.focusResults = [AXUIElementCreateApplication(1)]
        XCTAssertNotNil(f.bridge.focusedElementForTesting())
        // The temporary failure was uncached, so activation can enable again.
        f.fake.enableResult = .success
        f.activate()

        XCTAssertNil(f.bridge.focusedElementForTesting())

        XCTAssertEqual(f.fake.setPIDs, [f.pid, f.pid, f.pid])
        XCTAssertEqual(f.fake.pauses, [0.15])
        XCTAssertEqual(f.fake.lookupPIDs, [f.pid, f.pid, f.pid])
    }

    func test_R300_finderLikeUnsupportedNilFocusNeverPausesEvenOnFreshEnable() {
        let f = AccessibilityRetryFixture()
        f.fake.app = (f.pid, "com.apple.finder")
        f.fake.enableResult = .attributeUnsupported

        let snapshot = f.bridge.currentFocus(at: .zero)
        XCTAssertEqual(f.bridge.currentFocus(at: .zero), snapshot)

        XCTAssertEqual(snapshot.role, FieldRole.none)
        XCTAssertEqual(snapshot.identity, FocusIdentity.none)
        XCTAssertEqual(f.fake.setPIDs, [f.pid])
        XCTAssertEqual(f.fake.lookupPIDs, [f.pid, f.pid])
        XCTAssertTrue(f.fake.pauses.isEmpty)
    }

    func test_R300_emptyDesktopWithoutFrontmostAppNeverEnablesOrPauses() {
        let f = AccessibilityRetryFixture()
        f.fake.app = nil

        XCTAssertEqual(f.bridge.currentFocus(at: .zero).role, FieldRole.none)

        XCTAssertTrue(f.fake.setPIDs.isEmpty)
        XCTAssertTrue(f.fake.pauses.isEmpty)
        XCTAssertEqual(f.fake.lookupPIDs, [0], "Pid zero requests only the system-wide fallback")
    }

    func test_R303_logsOncePerPidAndCodeWithoutInsertionText() {
        let f = AccessibilityRetryFixture()
        let bundle = "com.example.ax-retry"
        let otherPID = f.pid + 1
        for pid in [f.pid, otherPID] {
            f.fake.app = (pid, bundle)
            for error in [AXError.cannotComplete, .failure, .cannotComplete, .failure] {
                f.fake.enableResult = error
                _ = f.bridge.currentFocus(at: .zero)
            }
        }
        let dictatedText = "private dictated text that must never be logged"
        XCTAssertFalse(f.bridge.insert(dictatedText, into: .none, replacingSelection: false))

        let expected = [f.pid, otherPID].flatMap { pid in
            [AXError.cannotComplete, .failure].map {
                "Dictation AX: AXManualAccessibility pid \(pid) \(bundle) err \($0.rawValue)"
            }
        }
        XCTAssertEqual(f.fake.logs, expected)
        XCTAssertFalse(f.fake.logs.joined().contains(dictatedText))
    }

    func test_R304_terminationRemovesUnsupportedCacheAndLoggedCodes() {
        let f = AccessibilityRetryFixture()
        f.fake.enableResult = .attributeUnsupported
        f.activate()
        f.activate()
        XCTAssertEqual(f.fake.setPIDs, [f.pid])
        XCTAssertEqual(f.fake.logs.count, 1)

        f.terminate()
        f.activate()

        XCTAssertEqual(f.fake.setPIDs, [f.pid, f.pid])
        XCTAssertEqual(f.fake.logs.count, 2, "A reused pid has a fresh logging lifetime")
        f.fake.enableResult = .success
        f.terminate()
        XCTAssertNil(f.bridge.focusedElementForTesting())
        XCTAssertEqual(f.fake.setPIDs, [f.pid, f.pid, f.pid])
        XCTAssertEqual(f.fake.pauses, [0.15], "Unsupported state is removed too")
    }

    func test_R304_terminationRemovesSuccessfulCacheAndPreviouslySeenFocus() {
        let f = AccessibilityRetryFixture()
        f.activate()
        f.fake.focusResults = [AXUIElementCreateApplication(1)]
        XCTAssertNotNil(f.bridge.focusedElementForTesting())

        f.terminate()
        f.activate()
        XCTAssertEqual(f.fake.setPIDs, [f.pid, f.pid], "The success cache was removed")
        XCTAssertNil(f.bridge.focusedElementForTesting())

        XCTAssertEqual(f.fake.setPIDs, [f.pid, f.pid, f.pid])
        XCTAssertEqual(f.fake.pauses, [0.15], "The previously focused state was removed")
    }
}

/// Only the OS boundaries are faked; activation/termination use the real workspace notifications.
private final class AccessibilityRetryFixture {
    let bridge = AccessibilityBridge()
    let fake = AccessibilityRetryFake()
    let application = NSRunningApplication.current
    var pid: pid_t { application.processIdentifier }

    init() {
        let fake = self.fake
        fake.app = (pid, "com.example.ax-retry")
        bridge.setManualAccessibility = { pid in
            fake.setPIDs.append(pid)
            fake.events.append("set")
            return fake.enableResult
        }
        bridge.copyFocusedElement = { pid in
            fake.lookupPIDs.append(pid)
            fake.events.append("lookup")
            return fake.focusResults.isEmpty ? nil : fake.focusResults.removeFirst()
        }
        bridge.frontmostApp = { fake.app }
        bridge.pause = { fake.pauses.append($0); fake.events.append("pause") }
        bridge.log = { fake.logs.append($0) }
        // init() may have enabled the actual frontmost application before installing the seams.
        terminate()
    }

    func activate() { post(NSWorkspace.didActivateApplicationNotification) }
    func terminate() { post(NSWorkspace.didTerminateApplicationNotification) }

    private func post(_ name: Notification.Name) {
        NSWorkspace.shared.notificationCenter.post(
            name: name, object: nil, userInfo: [NSWorkspace.applicationUserInfoKey: application])
    }
}

private final class AccessibilityRetryFake {
    var app: (pid: pid_t, bundleID: String?)?
    var enableResult: AXError = .success
    var focusResults: [AXUIElement?] = []
    var setPIDs: [pid_t] = []
    var lookupPIDs: [pid_t] = []
    var pauses: [TimeInterval] = []
    var logs: [String] = []
    var events: [String] = []
}
