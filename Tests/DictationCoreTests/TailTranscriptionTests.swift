import DictationCore
import Foundation
import XCTest

final class TailTranscriptionTests: XCTestCase {
    func test_R259_recordedPartialsKeepTheExpectedStableSentencePrefixes() throws {
        let fixtures = try recordings()
        XCTAssertEqual(Set(fixtures.keys), Set(["long-dictation", "long-plain", "long-scratch", "short-dictation"]))
        let expected: [String: (offset: Double, ending: String)] = [
            "long-dictation": (19.88, "before we change anything."),
            "long-plain": (17.0, "main argument first."),
            "long-scratch": (17.4, "choosing their own food."),
        ]
        for name in fixtures.keys.sorted() {
            let fixture = try XCTUnwrap(fixtures[name])
            let tracker = StableSentenceTracker()
            for partial in fixture.partials {
                let before = tracker.stablePrefix
                tracker.ingest(segments: partial.segments.map(\.transcriptSegment), audioSeconds: partial.t)
                if partial.segments.contains(where: { $0.end > partial.t + 0.5 }) {
                    XCTAssertEqual(tracker.stablePrefix, before, "Ignore the entire degenerate partial: \(name), \(partial.t)s")
                }
            }
            guard let expectation = expected[name] else {
                XCTAssertNil(tracker.stablePrefix, name)
                continue
            }
            let stable = try XCTUnwrap(tracker.stablePrefix, name)
            XCTAssertEqual(stable.offsetSeconds, expectation.offset, accuracy: 0.15, name)
            XCTAssertTrue(stable.text.hasSuffix(expectation.ending), "\(name): \(stable.text)")
            let final = fixture.final_segments.map(\.text).joined(separator: " ")
            XCTAssertTrue(normalized(final).hasPrefix(normalized(stable.text)), name)
        }
    }

    func test_R259_changedSentenceDropsTheOldPrefixUntilConfirmedAgain() throws {
        let tracker = StableSentenceTracker()
        let original = [TranscriptSegment(start: 0, end: 2, text: "Book Friday.")]
        tracker.ingest(segments: original, audioSeconds: 3)
        XCTAssertNil(tracker.stablePrefix, "One partial cannot confirm a sentence")
        tracker.ingest(segments: original, audioSeconds: 4)
        XCTAssertEqual(tracker.stablePrefix?.text, "Book Friday.")

        let revised = [TranscriptSegment(start: 0, end: 2, text: "Book Thursday.")]
        tracker.ingest(segments: revised, audioSeconds: 5)
        XCTAssertNil(tracker.stablePrefix, "A changed prefix must not retain Friday")
        tracker.ingest(segments: revised, audioSeconds: 6)
        XCTAssertEqual(tracker.stablePrefix?.text, "Book Thursday.")
        XCTAssertEqual(try XCTUnwrap(tracker.stablePrefix).offsetSeconds, 2, accuracy: 0.001)
        tracker.reset()
        XCTAssertNil(tracker.stablePrefix)
        tracker.ingest(segments: revised, audioSeconds: 7)
        XCTAssertNil(tracker.stablePrefix, "Reset also clears the previous partial")
    }

    func test_R259_degeneratePartialNeitherConfirmsNorResetsStability() throws {
        let tracker = StableSentenceTracker()
        let real = [TranscriptSegment(start: 0, end: 19.88, text: "Before we change anything.")]
        tracker.ingest(segments: real, audioSeconds: 20)
        // Include a valid sentence too: ignoring only the offending segment would
        // incorrectly confirm the prefix from this otherwise degenerate run.
        let degenerate = real + [TranscriptSegment(start: 19.88, end: 30, text: "Hallucinated words.")]
        tracker.ingest(segments: degenerate, audioSeconds: 21.6)
        XCTAssertNil(tracker.stablePrefix)
        tracker.ingest(segments: real, audioSeconds: 22)
        let stable = try XCTUnwrap(tracker.stablePrefix)
        tracker.ingest(segments: [TranscriptSegment(start: 0, end: 30, text: "An unrelated hallucination.")],
                       audioSeconds: 21.6)
        XCTAssertEqual(tracker.stablePrefix, stable)
        tracker.ingest(segments: real, audioSeconds: 23)
        XCTAssertEqual(tracker.stablePrefix, stable)
    }

    func test_R259_stabilityNormalizesTextAndRequiresMatchingBoundaryTimes() throws {
        let tracker = StableSentenceTracker()
        tracker.ingest(segments: [TranscriptSegment(start: 0, end: 2, text: "Hello, WORLD!")], audioSeconds: 3)
        tracker.ingest(segments: [TranscriptSegment(start: 0, end: 2.14, text: "hello world.")], audioSeconds: 4)
        XCTAssertEqual(normalized(try XCTUnwrap(tracker.stablePrefix).text), "hello world")
        tracker.reset()
        tracker.ingest(segments: [TranscriptSegment(start: 0, end: 2, text: "Hello world.")], audioSeconds: 3)
        tracker.ingest(segments: [TranscriptSegment(start: 0, end: 2.3, text: "Hello world.")], audioSeconds: 4)
        XCTAssertNil(tracker.stablePrefix, "Text alone cannot confirm a moved boundary")
        tracker.reset()
        for seconds in [3.0, 4.0] {
            tracker.ingest(segments: [TranscriptSegment(start: 0, end: 2, text: "Hello world")], audioSeconds: seconds)
        }
        XCTAssertNil(tracker.stablePrefix, "Only sentence-ending segments create boundaries")
    }

    func test_R262_joinRemovesOneThroughEightOverlappingWords() {
        let words = ["we", "should", "review", "the", "whole", "draft", "before", "Thursday"]
        for count in 1...8 {
            let overlap = words.suffix(count).joined(separator: " ")
            let prefix = "Keep This: " + overlap + "."
            let tail = overlap.uppercased() + "! Can you put it together?"
            XCTAssertEqual(TailJoin.join(prefix: prefix, tail: tail),
                           prefix + " Can you put it together?", "\(count)-word overlap")
        }
        XCTAssertEqual(TailJoin.join(prefix: "Before we change anything.", tail: "anything. Can you put"),
                       "Before we change anything. Can you put")
        // Two overlaps are possible; the longest must win.
        XCTAssertEqual(TailJoin.join(prefix: "Go go go.", tail: "go go next."), "Go go go. next.")
    }

    func test_R262_joinPreservesPrefixAndSeparatesNonOverlappingText() {
        XCTAssertEqual(TailJoin.join(prefix: "Keep MY punctuation!", tail: "New sentence."),
                       "Keep MY punctuation! New sentence.")
        XCTAssertEqual(TailJoin.join(prefix: "Keep MY punctuation!", tail: ""), "Keep MY punctuation!")
        XCTAssertEqual(TailJoin.join(prefix: "", tail: "New sentence."), "New sentence.")
        XCTAssertEqual(TailJoin.join(prefix: "", tail: ""), "")
        let nine = "one two three four five six seven eight nine"
        XCTAssertEqual(TailJoin.join(prefix: nine + ".", tail: nine + " next."),
                       nine + ". " + nine + " next.", "Overlap search is bounded at eight words")
    }

    func test_R261_policyUsesFullTranscriptionOutsideHoldAndTailLimits() throws {
        let policy = TailTranscriptionPolicy()
        XCTAssertEqual(policy.minimumHoldSeconds, 6)
        XCTAssertEqual(policy.overlapSeconds, 0.5)
        XCTAssertEqual(policy.minimumTailSeconds, 1)
        XCTAssertEqual(policy.maximumTailSeconds, 20)
        let stable = try stablePrefix(offset: 10)
        XCTAssertEqual(policy.plan(audioSeconds: 15, stable: nil), .full)
        XCTAssertEqual(policy.plan(audioSeconds: 5.99, stable: try stablePrefix(offset: 2)), .full)
        XCTAssertEqual(policy.plan(audioSeconds: 10.49, stable: stable), .full, "Tail is 0.99s including overlap")
        XCTAssertEqual(policy.plan(audioSeconds: 29.51, stable: stable), .full, "Tail exceeds 20s including overlap")
        XCTAssertEqual(policy.plan(audioSeconds: 10.5, stable: stable), .tail(startSeconds: 9.5))
        XCTAssertEqual(policy.plan(audioSeconds: 29.5, stable: stable), .tail(startSeconds: 9.5))
        XCTAssertEqual(policy.plan(audioSeconds: 15, stable: stable), .tail(startSeconds: 9.5))
        XCTAssertEqual(policy.plan(audioSeconds: 6, stable: try stablePrefix(offset: 0.25)), .tail(startSeconds: 0))
    }

    func test_R261_policyRejectsMissingEmptyAndRepeatedTailText() {
        let policy = TailTranscriptionPolicy()
        let prefix = "Before we change anything."
        let rejected: [String?] = [nil, "", "   \n", "anything.", "CHANGE ANYTHING!"]
        for tail in rejected {
            XCTAssertFalse(policy.acceptTail(tail, tailAudioSeconds: 1.5, prefix: prefix), "\(String(describing: tail))")
        }
        XCTAssertFalse(policy.acceptTail(prefix, tailAudioSeconds: 1, prefix: prefix), "Repeating the entire prompt is suspicious")
        XCTAssertFalse(policy.acceptTail(prefix + " " + prefix, tailAudioSeconds: 5, prefix: prefix))
        XCTAssertTrue(policy.acceptTail("Anything. Can you put together a summary?", tailAudioSeconds: 5, prefix: prefix))
        XCTAssertTrue(policy.acceptTail("Can you put together a summary?", tailAudioSeconds: 5, prefix: prefix))
    }

    private func stablePrefix(offset: Double) throws -> StablePrefix {
        // StablePrefix's specified API has no public initializer. Obtain it through
        // the real tracker, just as a consumer of DictationCore would.
        let tracker = StableSentenceTracker()
        let segments = [TranscriptSegment(start: 0, end: offset, text: "A finished sentence.")]
        tracker.ingest(segments: segments, audioSeconds: offset + 1)
        tracker.ingest(segments: segments, audioSeconds: offset + 2)
        return try XCTUnwrap(tracker.stablePrefix)
    }

    private func normalized(_ text: String) -> String {
        text.lowercased().filter { !$0.isPunctuation }.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private struct Recording: Decodable {
        struct Segment: Decodable {
            let start: Double
            let end: Double
            let text: String
            var transcriptSegment: TranscriptSegment { TranscriptSegment(start: start, end: end, text: text) }
        }
        struct Partial: Decodable { let t: Double; let segments: [Segment] }
        let partials: [Partial]
        let final_segments: [Segment]
    }

    private func recordings() throws -> [String: Recording] {
        let directory = URL(fileURLWithPath: #filePath).resolvingSymlinksInPath()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/audio")
        return try JSONDecoder().decode([String: Recording].self,
                                       from: Data(contentsOf: directory.appendingPathComponent("whisper-segments.json")))
    }
}
