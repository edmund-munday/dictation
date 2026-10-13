import XCTest
import DictationCore

final class ModeTests: XCTestCase {
    func test_R13_flowDefaultInsertsWithoutKeyHeld() throws {
        let h = try TestHarness()
        XCTAssertEqual(h.session.settings.mode, .flow)
        h.readyListening()
        h.speakAndWait("hello world")

        XCTAssertEqual(h.session.insertRequests.count, 1)
        guard let insert = h.firstInsert() else { return }
        XCTAssertEqual(insert.target, h.fieldIdentity)
    }

    func test_R14_guardedRequiresFnAtEndpointAndShowsMenu() throws {
        let h = try TestHarness()
        h.session.setMode(.guarded)
        h.readyListening()

        XCTAssertEqual(h.session.menuText, MenuText.guarded)

        h.speakOnly("hello")
        h.advanceSilenceAndHold()
        XCTAssertTrue(h.session.insertRequests.isEmpty)

        h.speakOnly("hello")
        h.session.ingestKey(KeyPress(timestamp: h.clock.now, kind: .fn, isDown: true))
        h.advanceSilenceAndHold()
        XCTAssertEqual(h.session.insertRequests.count, 1)
    }

    func test_R15_guardedIncludesSpeechStartingUpTo400msBeforeFn() throws {
        let h = try TestHarness()
        h.session.setMode(.guarded)
        h.readyListening()

        let speechStart = h.clock.now
        h.clock.advance(by: .milliseconds(300))
        h.session.ingestRecognizerTokens([
            RecognizerToken(text: "early words", start: speechStart, end: h.clock.now),
        ])
        h.session.ingestKey(KeyPress(timestamp: h.clock.now, kind: .fn, isDown: true))
        h.clock.advance(by: .milliseconds(200))
        h.session.ingestRecognizerTokens([
            RecognizerToken(
                text: "early words continue",
                start: speechStart,
                end: h.clock.now
            ),
        ])
        h.advanceSilenceAndHold()

        XCTAssertEqual(h.session.insertRequests.count, 1)
        guard let insert = h.firstInsert() else { return }
        XCTAssertTrue(insert.text.lowercased().contains("early"))
    }

    func test_R16_guardedReleaseFnBeforeEndpointDiscardsUtterance() throws {
        let h = try TestHarness()
        h.session.setMode(.guarded)
        h.readyListening()

        h.session.ingestKey(KeyPress(timestamp: h.clock.now, kind: .fn, isDown: true))
        h.speakOnly("discard me")
        h.session.ingestKey(KeyPress(timestamp: h.clock.now, kind: .fn, isDown: false))
        h.advanceSilenceAndHold()

        XCTAssertEqual(h.session.menuText, MenuText.guarded)
        XCTAssertTrue(h.session.insertRequests.isEmpty)
        XCTAssertEqual(h.session.overlay, .empty)
    }
}
