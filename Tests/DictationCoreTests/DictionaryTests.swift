import DictationCore
import Foundation
import XCTest

final class DictionaryTests: XCTestCase {
    private var directory: URL!
    private var dictionaryURL: URL { directory.appendingPathComponent("dictionary.txt") }

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("dictionary-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    func test_R272_requiredSpellingExamples() {
        let examples = [
            ("K-A-Z-E-Y", "Kazey"),
            ("K, A, Z, E, Y", "Kazey"),
            ("K. A. Z. E. Y.", "Kazey"),
            ("K A Z E Y", "Kazey"),
            ("capital T-E-S-S-A", "Tessa"),
            ("M O double S", "Moss"),
            ("capital G-R-O-K space capital B-O-T", "Grok Bot"),
            ("capital GROK space capital BOT", "Grok Bot"),  // real whisper variant without vocabulary prompt
            ("all caps A P I", "API"),
            ("lowercase S C R I P T", "script"),
            ("kay ay zed ee why", "Kazey"),
            ("kazey", "Kazey"),
        ]
        for (spelled, expected) in examples {
            XCTAssertEqual(SpelledTerm.parse(spelled), expected, spelled)
        }
    }

    func test_R272_allLetterNamesAndAliases() {
        let names = [
            ("ay", "A"), ("bee", "B"), ("see", "C"), ("sea", "C"), ("dee", "D"),
            ("ee", "E"), ("ef", "F"), ("gee", "G"), ("aitch", "H"), ("eye", "I"),
            ("jay", "J"), ("kay", "K"), ("el", "L"), ("em", "M"), ("en", "N"),
            ("oh", "O"), ("pee", "P"), ("cue", "Q"), ("queue", "Q"), ("ar", "R"),
            ("es", "S"), ("ess", "S"), ("tee", "T"), ("tea", "T"), ("you", "U"),
            ("vee", "V"), ("double-u", "W"), ("ex", "X"), ("why", "Y"),
            ("zed", "Z"), ("zee", "Z"),
        ]
        for (name, letter) in names {
            XCTAssertEqual(SpelledTerm.parse(name), letter, name)
        }
        XCTAssertEqual(SpelledTerm.parse("bee ee ee"), "Bee")
        XCTAssertEqual(SpelledTerm.parse("double-u ay why"), "Way")
        XCTAssertEqual(SpelledTerm.parse("em oh double ess"), "Moss")
    }

    func test_R272_caseMarkersApplyToTheirLetterOrNextWord() {
        XCTAssertEqual(SpelledTerm.parse("K A Z E Y"), "Kazey")
        XCTAssertEqual(SpelledTerm.parse("g capital R o k"), "gRok", "Only marked letters are uppercase")
        XCTAssertEqual(SpelledTerm.parse("all caps A P I space B O T"), "API Bot")
        XCTAssertEqual(SpelledTerm.parse("lowercase S C R I P T space S N I P"), "script Snip")
        XCTAssertEqual(SpelledTerm.parse("  K,\tA-Z.\nE Y.  "), "Kazey")
    }

    func test_R272_unparseableSpellingReturnsNil() {
        for spelled in ["", "   ", "K A banana", "K A 7", "K A @"] {
            XCTAssertNil(SpelledTerm.parse(spelled), spelled)
        }
    }

    func test_R275_R276_missingDictionaryIsEmptyAndTermsAreReadInFileOrder() throws {
        let dictionary = UserDictionary(fileURL: dictionaryURL)
        XCTAssertEqual(dictionary.terms, [])
        XCTAssertNil(UserDictionary.gatewayLine(terms: dictionary.terms))
        try write("Kazey\nscript\nSnip\n")
        XCTAssertEqual(dictionary.terms, ["Kazey", "script", "Snip"])
        try write("Kazey\nscript\nSnip\nQuinn\n")
        XCTAssertEqual(dictionary.terms, ["Kazey", "script", "Snip", "Quinn"], "Read changes made since construction")
    }

    func test_R275_whisperPromptHasExactLeadInOrderAndPunctuation() {
        XCTAssertEqual(UserDictionary.whisperPrompt(terms: ["Kazey", "script", "Snip", "Quinn"]),
                       "Edmund dictating notes and messages: Kazey, script, Snip, Quinn.")
    }

    func test_R275_whisperBudgetDropsOldestWholeTermsAndCountsLeadIn() {
        let leadIn = "Edmund dictating notes and messages: "
        let budget = (leadIn + "Middle, Newest.").count
        let terms = ["Oldest", "Middle", "Newest"]
        XCTAssertEqual(UserDictionary.whisperPrompt(terms: terms, budget: budget), leadIn + "Middle, Newest.")
        XCTAssertEqual(UserDictionary.whisperPrompt(terms: terms, budget: budget - 1), leadIn + "Newest.")
    }

    func test_R275_twoHundredLongTermsKeepNewestWithinDefaultWhisperBudget() throws {
        let terms = longTerms()
        let prompt = UserDictionary.whisperPrompt(terms: terms)
        XCTAssertLessThanOrEqual(prompt.count, 600)
        XCTAssertTrue(prompt.hasPrefix("Edmund dictating notes and messages: "))
        XCTAssertTrue(prompt.hasSuffix(try XCTUnwrap(terms.last) + "."))
        XCTAssertFalse(prompt.contains(terms[0]))
        let kept = String(prompt.dropFirst("Edmund dictating notes and messages: ".count).dropLast())
            .components(separatedBy: ", ")
        XCTAssertGreaterThan(kept.count, 1)
        XCTAssertEqual(kept, Array(terms.suffix(kept.count)), "Keep complete newest terms in dictionary order")
    }

    func test_R276_gatewayLineIsExactAndAbsentForEmptyDictionary() {
        XCTAssertNil(UserDictionary.gatewayLine(terms: []))
        XCTAssertEqual(UserDictionary.gatewayLine(terms: ["Kazey", "script", "Snip"]),
                       "Preferred spellings (use exactly when these words are meant): Kazey, script, Snip")
    }

    func test_R276_gatewayBudgetDropsOldestWholeTermsAndCountsLeadIn() {
        let leadIn = "Preferred spellings (use exactly when these words are meant): "
        let budget = (leadIn + "Middle, Newest").count
        let terms = ["Oldest", "Middle", "Newest"]
        XCTAssertEqual(UserDictionary.gatewayLine(terms: terms, budget: budget), leadIn + "Middle, Newest")
        XCTAssertEqual(UserDictionary.gatewayLine(terms: terms, budget: budget - 1), leadIn + "Newest")
    }

    func test_R276_twoHundredLongTermsKeepNewestWithinDefaultGatewayBudget() throws {
        let terms = longTerms()
        let line = try XCTUnwrap(UserDictionary.gatewayLine(terms: terms))
        XCTAssertLessThanOrEqual(line.count, 1000)
        XCTAssertTrue(line.hasPrefix("Preferred spellings (use exactly when these words are meant): "))
        XCTAssertTrue(line.hasSuffix(try XCTUnwrap(terms.last)))
        XCTAssertFalse(line.contains(terms[0]))
        let kept = String(line.dropFirst("Preferred spellings (use exactly when these words are meant): ".count))
            .components(separatedBy: ", ")
        XCTAssertGreaterThan(kept.count, 1)
        XCTAssertEqual(kept, Array(terms.suffix(kept.count)))
    }

    func test_R277_migrationExtractsCommaSeparatedVocabularyAfterColon() throws {
        try UserDictionary.migrateIfNeeded(fileURL: dictionaryURL,
            fromPrompt: "Edmund dictating notes and messages: Kazey, script, Snip.")
        let contents = try String(contentsOf: dictionaryURL, encoding: .utf8)
        XCTAssertEqual(contents.split(whereSeparator: \.isNewline).map(String.init), ["Kazey", "script", "Snip"])
        XCTAssertEqual(UserDictionary(fileURL: dictionaryURL).terms, ["Kazey", "script", "Snip"])
    }

    func test_R277_migrationUsesCustomPromptVocabulary() throws {
        try UserDictionary.migrateIfNeeded(fileURL: dictionaryURL,
            fromPrompt: "My vocabulary: Tessa, Grok Bot, Quinn.")
        XCTAssertEqual(UserDictionary(fileURL: dictionaryURL).terms, ["Tessa", "Grok Bot", "Quinn"])
    }

    func test_R277_migrationNeverOverwritesExistingOrEmptyFile() throws {
        for existing in ["User spelling\nQuinn\n", ""] {
            try write(existing)
            let before = try Data(contentsOf: dictionaryURL)
            try UserDictionary.migrateIfNeeded(fileURL: dictionaryURL,
                fromPrompt: "Edmund dictating notes and messages: Kazey, script, Snip.")
            XCTAssertEqual(try Data(contentsOf: dictionaryURL), before)
        }
    }

    private func write(_ text: String) throws {
        try text.write(to: dictionaryURL, atomically: true, encoding: .utf8)
    }

    private func longTerms() -> [String] {
        (0..<200).map { String(format: "Term%03d", $0) + String(repeating: "x", count: 33) }
    }
}
