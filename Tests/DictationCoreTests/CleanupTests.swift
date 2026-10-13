import XCTest
import DictationCore

final class CleanupTests: XCTestCase {
    func test_R61_localFallbackShipItFridayActuallyIMeanMonday() throws {
        let h = try TestHarness()
        h.session.setCleanupBackend(.off)
        h.latchOn()
        h.focusEditable()
        h.pressTalkKey()
        h.speakWhileHeld("ship it friday, actually I mean monday")
        h.releaseTalkKey()
        h.clock.advance(by: .milliseconds(200))

        XCTAssertEqual(h.session.insertRequests.count, 1)
        XCTAssertEqual(h.session.insertRequests.first?.text, "Ship it Monday.")
        XCTAssertEqual(h.session.cliInvocations.count, 0)
    }

    func test_R62_thatsActuallyFineKeepsActually() throws {
        let h = try TestHarness()
        h.readyListening()
        h.speakAndWait("that's actually fine")

        XCTAssertEqual(h.session.insertRequests.count, 1)
        guard let insert = h.firstInsert() else { return }
        XCTAssertTrue(insert.text.lowercased().contains("actually"))
    }

    func test_R63_iActuallyThinkTuesdayKeepsActually() throws {
        let h = try TestHarness()
        h.readyListening()
        h.speakAndWait("I actually think tuesday")

        XCTAssertEqual(h.session.insertRequests.count, 1)
        guard let insert = h.firstInsert() else { return }
        XCTAssertTrue(insert.text.lowercased().contains("actually"))
    }

    func test_R64_goodIMeanReallyGoodKeepsBoth() throws {
        let h = try TestHarness()
        h.readyListening()
        h.speakAndWait("good, I mean really good")

        XCTAssertEqual(h.session.insertRequests.count, 1)
        guard let insert = h.firstInsert() else { return }
        let text = insert.text.lowercased()
        XCTAssertTrue(text.contains("good"))
        XCTAssertTrue(text.contains("really good"))
    }

    func test_R65_dontSendKeepsNegation() throws {
        let h = try TestHarness()
        h.readyListening()
        h.speakAndWait("don't send")

        XCTAssertEqual(h.session.insertRequests.count, 1)
        guard let insert = h.firstInsert() else { return }
        let text = insert.text.lowercased()
        XCTAssertTrue(text.contains("don't") || text.contains("dont"))
        XCTAssertTrue(text.contains("send"))
    }

    func test_R66_dontSendIMeanDoSend() throws {
        let h = try TestHarness()
        h.readyListening()
        h.speakAndWait("don't send, I mean do send")

        XCTAssertEqual(h.session.insertRequests.count, 1)
        guard let insert = h.firstInsert() else { return }
        XCTAssertEqual(insert.text, "Do send.")
    }

    func test_R67_cue_scratch_that_replacesLastMatchingItem() throws {
        try assertCueReplacement(cue: "scratch that", spoken: "meet friday scratch that monday", mustContain: "monday", mustNotContainWhole: "meet friday scratch that monday")
    }

    func test_R67_cue_no_wait_replacesLastMatchingItem() throws {
        try assertCueReplacement(cue: "no wait", spoken: "meet friday no wait monday", mustContain: "monday", mustNotContainWhole: "meet friday no wait monday")
    }

    func test_R67_cue_wait_replacesLastMatchingItem() throws {
        try assertCueReplacement(cue: "wait", spoken: "meet friday wait monday", mustContain: "monday", mustNotContainWhole: "meet friday wait monday")
    }

    func test_R67_cue_sorry_replacesLastMatchingItem() throws {
        try assertCueReplacement(cue: "sorry", spoken: "meet friday sorry monday", mustContain: "monday", mustNotContainWhole: "meet friday sorry monday")
    }

    func test_R67_cue_i_mean_replacesLastMatchingItem() throws {
        try assertCueReplacement(cue: "I mean", spoken: "meet friday I mean monday", mustContain: "monday", mustNotContainWhole: "meet friday i mean monday")
    }

    func test_R67_cue_actually_i_mean_replacesLastMatchingItem() throws {
        try assertCueReplacement(cue: "actually I mean", spoken: "meet friday actually I mean monday", mustContain: "monday", mustNotContainWhole: "meet friday actually i mean monday")
    }

    func test_R67_cue_no_i_mean_replacesLastMatchingItem() throws {
        try assertCueReplacement(cue: "no I mean", spoken: "meet friday no I mean monday", mustContain: "monday", mustNotContainWhole: "meet friday no i mean monday")
    }

    func test_R68_scratchThatPlusClauseReplacesUtteranceTextBeforeCue() throws {
        let h = try TestHarness()
        h.readyListening()
        h.speakAndWait("Scratch that, ship it monday")

        XCTAssertEqual(h.session.insertRequests.count, 1)
        guard let insert = h.firstInsert() else { return }
        let text = insert.text.lowercased()
        XCTAssertTrue(text.contains("ship it monday") || text.contains("ship it monday."))
        XCTAssertFalse(text.contains("scratch that"))
    }

    func test_R70_localFallbackNeverAddsWordNotSpoken() throws {
        let corpus = [
            "ship it friday, actually I mean monday",
            "that's actually fine",
            "I actually think tuesday",
            "good, I mean really good",
            "don't send",
            "don't send, I mean do send",
            "hello world",
            "um please review this",
        ]
        for phrase in corpus {
            let h = try TestHarness()
            h.session.setCleanupBackend(.off)
            h.latchOn()
            h.focusEditable()
            h.pressTalkKey()
            h.speakWhileHeld(phrase)
            h.releaseTalkKey()
            h.clock.advance(by: .milliseconds(200))
            XCTAssertEqual(h.session.insertRequests.count, 1, phrase)
            guard let insert = h.firstInsert() else { return }
            let spokenWords = Set(wordTokens(phrase))
            let outputWords = wordTokens(insert.text)
            for word in outputWords {
                XCTAssertTrue(
                    spokenWords.contains(word) || isPunctuationOnly(word),
                    "added word '\(word)' not in spoken '\(phrase)'"
                )
            }
        }
    }

    func test_R71_localFallbackNeverRemovesUnlicensedWords() throws {
        let corpus = [
            "that's actually fine",
            "I actually think tuesday",
            "good, I mean really good",
            "don't send",
            "hello beautiful world",
        ]
        for phrase in corpus {
            let h = try TestHarness()
            h.session.setCleanupBackend(.off)
            h.latchOn()
            h.focusEditable()
            h.pressTalkKey()
            h.speakWhileHeld(phrase)
            h.releaseTalkKey()
            h.clock.advance(by: .milliseconds(200))
            XCTAssertEqual(h.session.insertRequests.count, 1, phrase)
            guard let insert = h.firstInsert() else { return }
            let spoken = wordTokens(phrase)
            let output = Set(wordTokens(insert.text))
            for word in spoken where !isCueWord(word) {
                XCTAssertTrue(output.contains(word), "removed '\(word)' from '\(phrase)'")
            }
        }
    }

    func test_R72_negationNeverDroppedUnlessReplacementCarriesFlip() throws {
        let h = try TestHarness()
        h.readyListening()
        h.speakAndWait("don't send the email")
        XCTAssertEqual(h.session.insertRequests.count, 1)
        guard let insert = h.firstInsert() else { return }
        let text = insert.text.lowercased()
        XCTAssertTrue(text.contains("don't") || text.contains("not") || text.contains("never"))
    }

    func test_R73_ambiguousCorrectionParseInsertsLiteralPunctuated() throws {
        let h = try TestHarness()
        h.readyListening()
        h.speakAndWait("good, I mean really good")

        XCTAssertEqual(h.session.insertRequests.count, 1)
        guard let insert = h.firstInsert() else { return }
        let text = insert.text.lowercased()
        XCTAssertTrue(text.contains("good"))
        XCTAssertTrue(text.contains("really"))
    }

    func test_R74_autoPunctuationSentenceFinalAndCapitalisation() throws {
        let h = try TestHarness()
        h.readyListening()
        h.speakAndWait("how are you")

        XCTAssertEqual(h.session.insertRequests.count, 1)
        guard let insert = h.firstInsert() else { return }
        let text = insert.text
        XCTAssertTrue(text.first?.isUppercase == true)
        XCTAssertTrue(text.hasSuffix(".") || text.hasSuffix("?"))
    }

    func test_R75_spokenPunctuationWordsStayWords() throws {
        let h = try TestHarness()
        h.readyListening()
        h.speakAndWait("list comma period new paragraph")

        XCTAssertEqual(h.session.insertRequests.count, 1)
        guard let insert = h.firstInsert() else { return }
        let text = insert.text.lowercased()
        XCTAssertTrue(text.contains("comma"))
        XCTAssertTrue(text.contains("period"))
        XCTAssertTrue(text.contains("new paragraph"))
    }

    func test_R76_fillerMuttersInsideSentenceRemoved() throws {
        let h = try TestHarness()
        h.readyListening()
        h.speakAndWait("please um review uh this")

        XCTAssertEqual(h.session.insertRequests.count, 1)
        guard let insert = h.firstInsert() else { return }
        let text = insert.text.lowercased()
        XCTAssertFalse(text.split(separator: " ").contains("um"))
        XCTAssertFalse(text.split(separator: " ").contains("uh"))
        XCTAssertTrue(text.contains("review"))
    }

    func test_R77_pronounIAndSentenceStartsCapitalised() throws {
        let h = try TestHarness()
        h.readyListening()
        h.speakAndWait("i think this works")

        XCTAssertEqual(h.session.insertRequests.count, 1)
        guard let insert = h.firstInsert() else { return }
        let text = insert.text
        XCTAssertTrue(text.hasPrefix("I ") || text.hasPrefix("I."))
    }

    func test_R78_consecutiveInsertsGetCorrectSpacingFromPrecedingChar() throws {
        let h = try TestHarness()
        h.latchOn()
        h.focusEditable(precedingCharacter: nil)
        h.speakAndWait("Hello")
        XCTAssertEqual(h.session.insertRequests.count, 1)
        guard let first = h.firstInsert() else { return }
        XCTAssertFalse(first.text.hasPrefix(" "))

        h.focusEditable(precedingCharacter: "o")
        h.speakAndWait("world")
        XCTAssertEqual(h.session.insertRequests.count, 2)
        guard let second = h.insert(at: 1) else { return }
        XCTAssertTrue(second.text.hasPrefix(" "))
    }

    func test_R79_cleanupAppliedAutomaticallyOnRelease() throws {
        let h = try TestHarness()
        h.session.setCleanupBackend(.off)
        h.latchOn()
        h.focusEditable()
        h.pressTalkKey()
        h.speakWhileHeld("um hello")
        h.releaseTalkKey()
        h.clock.advance(by: .milliseconds(200))

        XCTAssertEqual(h.session.insertRequests.count, 1)
        XCTAssertEqual(h.session.insertRequests.first?.text, "Hello.")
        XCTAssertFalse(h.session.panel.isVisible)
    }

    func test_R80_releaseSendsRawTranscriptOnceAndInsertsLlmResult() throws {
        let h = try TestHarness()
        let raw = "ship it friday, actually I mean monday"
        let cli = try h.installFakeCLI(result: "Ship it Monday.", delayMs: 0, name: "llm")
        h.session.setCleanupBackend(.cursorCLI, executablePath: cli.path)
        h.latchOn()
        h.focusEditable()
        h.pressTalkKey()
        h.speakWhileHeld(raw)
        h.releaseTalkKey()
        h.clock.advance(by: .milliseconds(100))

        XCTAssertEqual(h.session.cliInvocations.count, 1)
        XCTAssertEqual(h.session.cliInvocations.first?.stdinText, raw)
        XCTAssertEqual(h.fakeCLILog(name: "llm").contains(raw), true)
        XCTAssertEqual(h.session.insertRequests.first?.text, "Ship it Monday.")
    }

    func test_R81_cliMissingFailingOrSlowFallsBackWithMenuNoteOnce() throws {
        let h = try TestHarness()
        h.session.configureCLI(
            path: h.workingDirectory.appendingPathComponent("missing-cli").path,
            kind: .claudeCLI,
            enabled: true
        )
        h.session.confirmCLIConsent()
        h.readyListening()
        h.speakAndWait("hello there")

        XCTAssertEqual(h.session.insertRequests.count, 1)
        XCTAssertTrue(h.session.menuText.contains(MenuText.cliUnavailable))

        h.speakAndWait("second phrase")
        let notes = h.session.menuText.components(separatedBy: MenuText.cliUnavailable).count - 1
        XCTAssertEqual(notes, 0, "CLI unavailable note must appear only once")
    }

    func test_R82_nonEnglishOrLowConfidenceInsertsNothing() throws {
        let h = try TestHarness()
        h.readyListening()
        h.speakAndWait("bonjour le monde", confidence: 0.2, language: "fr")

        XCTAssertTrue(h.session.insertRequests.isEmpty)
        XCTAssertEqual(h.session.menuText, MenuText.ready)
    }

    private func assertCueReplacement(
        cue: String,
        spoken: String,
        mustContain: String,
        mustNotContainWhole: String
    ) throws {
        let h = try TestHarness()
        h.readyListening()
        h.speakAndWait(spoken)
        XCTAssertEqual(h.session.insertRequests.count, 1, cue)
        guard let insert = h.firstInsert() else { return }
        let text = insert.text.lowercased()
        XCTAssertTrue(text.contains(mustContain), cue)
        XCTAssertNotEqual(text, mustNotContainWhole)
        XCTAssertFalse(text.contains("friday") && text.contains("monday") && text.contains(cue.lowercased()))
    }

    private func wordTokens(_ text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    private func isPunctuationOnly(_ word: String) -> Bool {
        word.unicodeScalars.allSatisfy { CharacterSet.punctuationCharacters.contains($0) }
    }

    private func isCueWord(_ word: String) -> Bool {
        ["scratch", "that", "wait", "sorry", "mean", "actually", "no", "i"].contains(word)
    }
}
