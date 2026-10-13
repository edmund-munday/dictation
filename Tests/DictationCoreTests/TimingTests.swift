import XCTest
import DictationCore

final class TimingTests: XCTestCase {
    func test_R51_insertNotBefore400msSilencePlus500msHold() throws {
        let h = try TestHarness()
        h.readyListening()
        h.speakOnly("timing")
        h.clock.advance(by: .milliseconds(399 + 500))
        XCTAssertTrue(h.session.insertRequests.isEmpty)

        h.clock.advance(by: .milliseconds(1))
        XCTAssertEqual(h.session.insertRequests.count, 1)
    }

    func test_R52_insertWithin1000msOfEndOfSpeech() throws {
        let h = try TestHarness()
        h.readyListening()
        h.speakOnly("fast")
        let endOfSpeech = h.clock.now
        h.clock.advance(by: .milliseconds(1000))

        XCTAssertEqual(h.session.insertRequests.count, 1)
        // Observability: insert must have been requested by now (fake clock).
        _ = endOfSpeech
    }

    func test_R53_pauseUnder400msDoesNotSplitUtterance() throws {
        let h = try TestHarness()
        h.readyListening()
        let start = h.clock.now
        h.clock.advance(by: .milliseconds(200))
        h.session.ingestRecognizerTokens([
            RecognizerToken(text: "hello", start: start, end: h.clock.now),
        ])
        h.clock.advance(by: .milliseconds(300))
        h.session.ingestRecognizerTokens([
            RecognizerToken(text: "hello world", start: start, end: h.clock.now),
        ])
        h.advanceSilenceAndHold()

        XCTAssertEqual(h.session.insertRequests.count, 1)
    }

    func test_R54_selfCorrectionCueAtEndExtendsSilenceSoOneInsert() throws {
        let h = try TestHarness()
        h.readyListening()
        let start = h.clock.now
        h.clock.advance(by: .milliseconds(400))
        h.session.ingestRecognizerTokens([
            RecognizerToken(text: "friday", start: start, end: h.clock.now),
        ])
        h.clock.advance(by: .milliseconds(350))
        h.session.ingestRecognizerTokens([
            RecognizerToken(text: "friday actually monday", start: start, end: h.clock.now),
        ])
        h.advanceSilenceAndHold()

        XCTAssertEqual(h.session.insertRequests.count, 1)
    }

    func test_R55_lateCleanupResultIgnoredLocalInsertsOnTime() throws {
        let h = try TestHarness()
        let cli = try h.installFakeCLI(result: "Late rewrite please", delayMs: 0)
        h.session.configureCLI(path: cli.path, kind: .cursorCLI, enabled: true)
        h.session.confirmCLIConsent()
        h.readyListening()
        h.speakOnly("local phrase")
        h.clock.advance(by: .milliseconds(900))
        XCTAssertEqual(h.session.insertRequests.count, 1)
        guard let onTime = h.firstInsert()?.text else { return }
        h.clock.advance(by: .milliseconds(500))
        XCTAssertEqual(h.session.insertRequests.count, 1)
        guard let still = h.firstInsert()?.text else { return }
        XCTAssertEqual(still, onTime)
        XCTAssertFalse(onTime.lowercased().contains("please"))
    }

    func test_R56_escapeDuringWaitDiscardsPendingPhrase() throws {
        let h = try TestHarness()
        h.readyListening()
        XCTAssertEqual(h.session.menuText, MenuText.ready)
        h.speakOnly("cancel me")
        h.clock.advance(by: .milliseconds(400))
        h.session.ingestKey(KeyPress(timestamp: h.clock.now, kind: .escape, isDown: true))
        h.clock.advance(by: .milliseconds(500))

        XCTAssertTrue(h.session.insertRequests.isEmpty)
        XCTAssertEqual(h.session.overlay, .empty)
        XCTAssertEqual(h.session.menuText, MenuText.ready)
    }

    func test_R57_characterDuringWaitDiscardsPendingAndCharacterReachesField() throws {
        let h = try TestHarness()
        h.readyListening()
        h.speakOnly("pending")
        h.clock.advance(by: .milliseconds(400))
        h.session.ingestKey(
            KeyPress(timestamp: h.clock.now, kind: .character("x"), isDown: true)
        )
        h.clock.advance(by: .milliseconds(500))

        XCTAssertTrue(h.session.insertRequests.isEmpty)
        // Typed character is delivered by the platform; core must not swallow it via emitted keys.
        XCTAssertFalse(
            h.session.emittedKeyEvents.contains(where: {
                if case .character("x") = $0.kind { return true }
                return false
            })
        )
        XCTAssertEqual(h.session.menuText, MenuText.ready)
    }

    func test_R58_withoutInputMonitoringMenuAddsTypingNotice() throws {
        let h = try TestHarness()
        h.session.setInputMonitoringPermission(false)
        h.readyListening()

        XCTAssertTrue(h.session.menuText.contains(MenuText.typingNoCancel))
    }

    func test_R59_utteranceCutAt30sSpeechThenNewUtterance() throws {
        let h = try TestHarness()
        h.readyListening()
        let start = h.clock.now
        h.clock.advance(by: .seconds(30))
        h.session.ingestRecognizerTokens([
            RecognizerToken(text: String(repeating: "word ", count: 100), start: start, end: h.clock.now),
        ])
        h.advanceSilenceAndHold()
        XCTAssertEqual(h.session.insertRequests.count, 1)

        let start2 = h.clock.now
        h.clock.advance(by: .milliseconds(500))
        h.session.ingestRecognizerTokens([
            RecognizerToken(text: "continuation", start: start2, end: h.clock.now),
        ])
        h.advanceSilenceAndHold()
        XCTAssertEqual(h.session.insertRequests.count, 2)
    }
}
