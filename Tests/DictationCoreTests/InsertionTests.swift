import XCTest
import DictationCore

final class InsertionTests: XCTestCase {
    func test_R36_qualifyingUtteranceInsertedAtFocusedFieldCaret() throws {
        let h = try TestHarness()
        h.readyListening()
        h.speakAndWait("hello there")

        XCTAssertEqual(h.session.insertRequests.count, 1)
        guard let insert = h.firstInsert() else { return }
        XCTAssertEqual(insert.target, h.fieldIdentity)
        XCTAssertFalse(insert.replacesSelection)
    }

    func test_R39_shortSelectionWithoutLineBreakIsReplaced() throws {
        let h = try TestHarness()
        h.latchOn()
        h.focusEditable(selectionLength: 40, selectionContainsLineBreak: false)
        h.speakAndWait("replacement")

        XCTAssertEqual(h.session.insertRequests.count, 1)
        guard let insert = h.firstInsert() else { return }
        XCTAssertTrue(insert.replacesSelection)
    }

    func test_R40_longOrMultilineSelectionKeptWithOverlayMessage() throws {
        let h = try TestHarness()
        h.latchOn()
        h.focusEditable(selectionLength: 120, selectionContainsLineBreak: false)
        h.speakAndWait("nope")

        XCTAssertTrue(h.session.insertRequests.isEmpty)
        XCTAssertEqual(h.session.overlay.text, MenuText.selectionKept)

        h.focusEditable(selectionLength: 10, selectionContainsLineBreak: true)
        h.speakAndWait("also nope")
        XCTAssertTrue(h.session.insertRequests.isEmpty)
        XCTAssertEqual(h.session.overlay.text, MenuText.selectionKept)
    }

    func test_R42_neverEmitsReturnTabEscapeOrShortcutKeys() throws {
        let h = try TestHarness()
        h.readyListening()
        h.speakAndWait("rm -rf /")

        XCTAssertEqual(h.session.insertRequests.count, 1)
        XCTAssertTrue(h.session.emittedKeyEvents.isEmpty)
    }

    func test_R43_newlinesStrippedInSingleLineTerminalAndComboBox() throws {
        let h = try TestHarness()
        h.latchOn()
        for role in [FieldRole.textField, .terminal, .comboBox] {
            h.focusEditable(role: role)
            h.speakAndWait("line one\nline two")
            XCTAssertEqual(h.session.insertRequests.last?.text.contains("\n"), false)
        }
        XCTAssertEqual(h.session.insertRequests.count, 3)
    }

    func test_R45_focusChangeBeforeCommitInsertsNothingAnywhere() throws {
        let h = try TestHarness()
        h.readyListening()
        h.speakOnly("abandoned")
        let other = FocusIdentity(pid: 99, elementID: "other")
        h.focusEditable(identity: other)
        h.advanceSilenceAndHold()

        XCTAssertTrue(h.session.insertRequests.isEmpty)
        XCTAssertEqual(h.session.menuText, MenuText.ready)
    }

    func test_R46_insertionFailureShowsOverlayWithCopyButton() throws {
        let h = try TestHarness()
        h.readyListening()
        h.speakAndWait("could not type")
        XCTAssertEqual(h.session.insertRequests.count, 1)
        h.session.reportInsertionFailed(for: 0)

        XCTAssertEqual(h.session.overlay.text, MenuText.insertFailed)
        XCTAssertTrue(h.session.overlay.buttons.contains(where: { $0.title == "Copy" }))
    }

    func test_R48_partialUncommittedWordsNeverAppearInField() throws {
        let h = try TestHarness()
        h.readyListening()
        let start = h.clock.now
        h.clock.advance(by: .milliseconds(200))
        h.session.ingestRecognizerTokens([
            RecognizerToken(
                text: "parti",
                start: start,
                end: h.clock.now,
                isFinal: false
            ),
        ])

        XCTAssertTrue(h.session.insertRequests.isEmpty)

        h.session.ingestRecognizerTokens([
            RecognizerToken(text: "partial words", start: start, end: h.clock.now, isFinal: true),
        ])
        h.advanceSilenceAndHold()
        XCTAssertEqual(h.session.insertRequests.count, 1)
    }

    func test_R49_overlayOnlyWhenNeededNotOnEveryPhrase() throws {
        let h = try TestHarness()
        h.readyListening()
        h.speakAndWait("ordinary phrase")
        h.session.reportInsertionSucceeded(for: 0)

        XCTAssertEqual(h.session.insertRequests.count, 1)
        XCTAssertEqual(h.session.overlay, .empty)
    }

    func test_R50_newlineStrippedShowsOverlayMessage() throws {
        let h = try TestHarness()
        h.latchOn()
        h.focusEditable(role: .terminal)
        h.speakAndWait("one\ntwo")

        XCTAssertEqual(h.session.insertRequests.count, 1)
        XCTAssertEqual(h.session.overlay.text, MenuText.newlineStripped)
    }
}
