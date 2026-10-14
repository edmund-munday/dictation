import DictationCore
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest

/// User scenarios through the real Session and GatewayCleaner. Only HTTP is scripted.
final class IncrementalCleanupTests: XCTestCase {
    private let plainSentences = [
        "Hey Kazey, thanks for sending the draft through yesterday.",
        "I read it on the train this morning, and I really like the overall structure.",
        "The introduction is strong, but the middle section about the budget could be a bit tighter.",
        "I would also move the timeline to the end, so the reader gets the main argument first.",
        "Let me know if you want to go through it together on a call later this week.",
    ]

    func test_R249_stableSentencesAreCleanedInThePanelWhileTheUserKeepsTalking() throws {
        let fixture = try recording("long-plain")
        let network = ScriptedCleanupTransport()
        let h = try holding(network)
        // The first sentence is complete at 3.2 s, but has no following speech yet.
        for partial in fixture.partials.prefix(2) { replay(partial, into: h) }
        XCTAssertTrue(network.requests.isEmpty, "A trailing or newly completed sentence is not finalised")
        XCTAssertEqual(h.session.panel.text, fixture.partials[1].text)

        // By 9.6 s two sentences are stable, so this is unambiguously a long hold.
        for partial in fixture.partials[2...5] { replay(partial, into: h) }
        h.clock.advance(by: .zero) // Collect an immediately completed network reply.
        XCTAssertEqual(network.requests.map(\.user), Array(plainSentences.prefix(2)))
        let rawPrefix = plainSentences.prefix(2).joined(separator: " ")
        XCTAssertEqual(h.session.panel.text,
                       plainSentences.prefix(2).map(ScriptedCleanupTransport.cleaned).joined(separator: " ") + " " +
                       String(fixture.partials[5].text.dropFirst(rawPrefix.count + 1)))
        XCTAssertTrue(h.session.insertRequests.isEmpty)

        for partial in fixture.partials.dropFirst(6) { replay(partial, into: h) }
        h.clock.advance(by: .zero)
        XCTAssertEqual(network.requests.map(\.user), Array(plainSentences.prefix(4)))
        XCTAssertEqual(h.session.panel.text,
                       plainSentences.prefix(4).map(ScriptedCleanupTransport.cleaned).joined(separator: " ") +
                       " Let me know if you want to go through it together on a call.")
        for request in network.requests {
            XCTAssertFalse(request.system.contains("take a screenshot"), "Background cleanup excludes plugins")
        }
        finish(fixture.final, in: h)
        XCTAssertEqual(h.session.insertRequests.map(\.text), [cleanedPlain()])
    }

    func test_R250_releaseWaitsOnlyForTheTailAndPreservesDontSendAndSpokenMarkup() throws {
        let fixture = try recording("long-plain")
        // Same recorded hold; the second ending also exercises spoken input at release.
        let endings: [(raw: String, wire: String, cleaned: String, send: Bool)] = [
            (plainSentences[4], plainSentences[4], ScriptedCleanupTransport.cleaned(plainSentences[4]), true),
            ("Let me know comma quote later this week end quote full stop don't send",
             "Let me know comma ⟦QUOTE⟧ later this week ⟦/QUOTE⟧ full stop don't send",
             "✓ Let me know, \"later this week\".[[NOSEND]]", false),
        ]
        for ending in endings {
            let network = ScriptedCleanupTransport()
            let h = try holding(network)
            replay(fixture, into: h)
            XCTAssertEqual(network.requests.map(\.user), Array(plainSentences.prefix(4)))
            let beforeRelease = network.requests.count
            network.defaultAction = .deferred
            let raw = (Array(plainSentences.prefix(4)) + [ending.raw]).joined(separator: " ")
            finish(raw, in: h, settle: false)
            let released = h.clock.now
            XCTAssertEqual(network.requests.count, beforeRelease + 1)
            let request = try XCTUnwrap(network.requests.last)
            XCTAssertEqual(request.user, ending.wire, "Release must not re-clean the already cleaned prefix")
            XCTAssertFalse(request.system.contains("take a screenshot"))
            XCTAssertTrue(h.session.insertRequests.isEmpty, "Wait for the tail reply")
            h.clock.advance(by: .milliseconds(200))
            try network.succeed(beforeRelease, text: ending.cleaned)
            h.clock.advance(by: .zero)
            let expected = plainSentences.prefix(4).map(ScriptedCleanupTransport.cleaned).joined(separator: " ") +
                " " + ending.cleaned.replacingOccurrences(of: "[[NOSEND]]", with: "")
            XCTAssertEqual(h.session.insertRequests.map(\.text), [expected])
            XCTAssertEqual(h.session.insertRequests.first?.autoSendAllowed, ending.send)
            XCTAssertEqual(h.session.insertRequests.first?.target, h.fieldIdentity)
            XCTAssertLessThanOrEqual(h.clock.now - released, .milliseconds(200), "No extra full-text wait")
            XCTAssertEqual(network.requests.count, beforeRelease + 1)
            for token in ["[[NOSEND]]", "⟦QUOTE⟧", "⟦/QUOTE⟧", "full stop", "end quote"] {
                XCTAssertFalse(h.session.insertRequests.first?.text.contains(token) ?? false)
            }
        }
    }

    func test_R251_crossSentenceCorrectionsSendTheWholeRawTranscriptOnRelease() throws {
        var cases = [try recording("long-scratch"), try recording("long-dictation")]
        let plain = try recording("long-plain")
        for cue in ["No wait, use Thursday.", "I mean Thursday.", "Sorry, use Thursday.",
                    "Let me start again. Book Thursday.", "Start over. Book Thursday.",
                    "Number one, book Thursday. Number two, invite Sarah.",
                    "Quote book Thursday. Invite Sarah end quote."] {
            var variant = plain
            variant.final += " " + cue
            cases.append(variant)
        }
        for fixture in cases {
            let network = ScriptedCleanupTransport()
            let h = try holding(network)
            replay(fixture, into: h)
            XCTAssertGreaterThanOrEqual(network.requests.count, 2, "Exercise the long path: \(fixture.final)")
            let beforeRelease = network.requests.count
            finish(fixture.final, in: h)
            XCTAssertEqual(network.requests.count, beforeRelease + 1)
            // GatewayCleaner encodes spoken quote cues at the real HTTP boundary.
            let wire = fixture.final.replacingOccurrences(of: "Quote ", with: "⟦QUOTE⟧ ")
                .replacingOccurrences(of: "end quote", with: "⟦/QUOTE⟧")
            XCTAssertEqual(network.requests.last?.user, wire)
            XCTAssertEqual(h.session.insertRequests.map(\.text), [ScriptedCleanupTransport.cleaned(wire)])
            XCTAssertEqual(h.session.insertRequests.first?.autoSendAllowed, true)
        }
    }

    func test_R252_whisperRevisionsRemoveOldCleanupAndDiscardRepliesForTheOldSentence() throws {
        // Real small.en revision: north -> North in the last recorded partial/final.
        let dictation = try recording("long-dictation")
        let north = "Sales in the north region went up by about 12%, which is really good news for the team."
        let network = ScriptedCleanupTransport()
        let h = try holding(network)
        for partial in dictation.partials {
            replay(partial, into: h)
            if partial.t == 14.4 {
                XCTAssertTrue(h.session.panel.text?.contains(ScriptedCleanupTransport.cleaned(north)) ?? false)
            }
            if partial.text.contains("Sales in the North") {
                XCTAssertFalse(h.session.panel.text?.contains(ScriptedCleanupTransport.cleaned(north)) ?? false)
            }
        }
        XCTAssertEqual(network.requests.filter { $0.user == north }.count, 1)
        finish(dictation.final, in: h)
        XCTAssertEqual(h.session.insertRequests.map(\.text), [ScriptedCleanupTransport.cleaned(dictation.final)])
        XCTAssertFalse(h.session.insertRequests.first?.text.contains(ScriptedCleanupTransport.cleaned(north)) ?? false)

        // Script a revision before the old HTTP reply arrives (within its timeout).
        let plain = try recording("long-plain")
        let delayed = ScriptedCleanupTransport()
        delayed.actionForUser = { [first = plainSentences[0]] user in user == first ? .deferred : .immediate }
        let revisedHold = try holding(delayed)
        var nextPartial = 0
        while nextPartial < plain.partials.count, delayed.requests.isEmpty {
            replay(plain.partials[nextPartial], into: revisedHold)
            nextPartial += 1
        }
        XCTAssertEqual(delayed.requests.filter { $0.user == plainSentences[0] }.count, 1)
        let oldRequest = try XCTUnwrap(delayed.requests.firstIndex { $0.user == plainSentences[0] })
        let revised = plainSentences[0].replacingOccurrences(of: "Kazey", with: "Casey")
        var revision = try XCTUnwrap(plain.partials.indices.contains(nextPartial) ? plain.partials[nextPartial] : nil)
        revision.text = revision.text.replacingOccurrences(of: "Kazey", with: "Casey")
        replay(revision, into: revisedHold)
        try delayed.succeed(oldRequest)
        revisedHold.clock.advance(by: .zero)
        XCTAssertFalse(revisedHold.session.panel.text?.contains(ScriptedCleanupTransport.cleaned(plainSentences[0])) ?? false)
        delayed.actionForUser = nil
        for var partial in plain.partials.dropFirst(nextPartial + 1) {
            partial.text = partial.text.replacingOccurrences(of: "Kazey", with: "Casey")
            replay(partial, into: revisedHold)
            XCTAssertFalse(revisedHold.session.panel.text?.contains(ScriptedCleanupTransport.cleaned(plainSentences[0])) ?? false)
        }
        XCTAssertEqual(delayed.requests.filter { $0.user == revised }.count, 1)
        XCTAssertEqual(delayed.requests.filter { $0.user == plainSentences[0] }.count, 1)
        finish(plain.final.replacingOccurrences(of: "Kazey", with: "Casey"), in: revisedHold)
        XCTAssertEqual(revisedHold.session.insertRequests.map(\.text),
                       [([revised] + Array(plainSentences.dropFirst())).map(ScriptedCleanupTransport.cleaned)
                        .joined(separator: " ")])
    }

    func test_R253_cancelledHoldsIgnoreLateRepliesAndNeverInsertOrSendAReleaseRequest() throws {
        let fixture = try recording("long-plain")
        for cancellation in ["escape", "another key", "latch off"] {
            let network = ScriptedCleanupTransport()
            network.defaultAction = .deferred
            let h = try holding(network)
            for partial in fixture.partials.prefix(6) { replay(partial, into: h) }
            XCTAssertGreaterThanOrEqual(network.requests.count, 2, "Cancel with background work: \(cancellation)")
            let beforeCancel = network.requests.count
            switch cancellation {
            case "escape": h.pressOtherKey(.escape)
            case "another key": h.pressOtherKey(.character("x"))
            default: h.latchOff()
            }
            h.releaseTalkKey()
            let cancelledPanel = h.session.panel
            for index in network.pendingIndices { try network.succeed(index) }
            h.clock.advance(by: .seconds(5))
            XCTAssertEqual(network.requests.count, beforeCancel, "Cancellation has no release call")
            XCTAssertEqual(h.session.panel, cancelledPanel, "Late replies must not revive the panel")
            XCTAssertTrue(h.session.insertRequests.isEmpty)
        }
    }

    func test_R254_shortRecordedDictationKeepsOneReleaseCallAndPluginCommandsStillRoute() throws {
        let fixture = try recording("short-dictation")
        let network = ScriptedCleanupTransport()
        let h = try holding(network)
        replay(fixture, into: h)
        XCTAssertTrue(network.requests.isEmpty)
        XCTAssertEqual(h.session.panel.text, fixture.partials.last?.text)
        finish(fixture.final, in: h)
        XCTAssertEqual(network.requests.count, 1)
        XCTAssertEqual(network.requests.first?.user, fixture.final)
        XCTAssertTrue(network.requests.first?.system.contains("take a screenshot") ?? false)
        XCTAssertEqual(h.session.insertRequests.map(\.text), [ScriptedCleanupTransport.cleaned(fixture.final)])
        XCTAssertEqual(h.session.insertRequests.first?.autoSendAllowed, true)

        // Short command needing remote routing, followed by the existing trigger fast path.
        h.pressTalkKey()
        h.speakWhileHeld("capture the current window", isFinal: false)
        XCTAssertEqual(network.requests.count, 1)
        network.defaultAction = .reply(#"{"mode":"command","plugin":"screenshot","args":{},"confidence":1,"text":"Capture the current window."}"#)
        finish("capture the current window", in: h)
        XCTAssertEqual(network.requests.count, 2)
        XCTAssertTrue(network.requests.last?.system.contains("take a screenshot") ?? false)
        XCTAssertEqual(h.session.commandRequests.map { $0.plugin.name }, ["screenshot"])
        h.pressTalkKey()
        h.speakWhileHeld("take a screenshot", isFinal: false)
        finish("take a screenshot", in: h)
        XCTAssertEqual(network.requests.count, 2, "Existing fast-path commands bypass the gateway")
        XCTAssertEqual(h.session.commandRequests.map { $0.plugin.name }, ["screenshot", "screenshot"])
        XCTAssertEqual(h.session.insertRequests.count, 1, "Commands must not become dictated text")
    }

    func test_R255_failedBackgroundAndReleaseCallsKeepCleanedSentencesAndUseLocalRulesForTheRest() throws {
        let fixture = try recording("long-plain")
        for timeout in [false, true] {
            let network = ScriptedCleanupTransport()
            network.actionForUser = { [first = plainSentences[0]] user in
                user == first ? (timeout ? .deferred : .failure) : .immediate
            }
            let h = try holding(network)
            replay(fixture, into: h)
            XCTAssertEqual(network.requests.map(\.user), Array(plainSentences.prefix(4)))
            let beforeRelease = network.requests.count
            network.actionForUser = nil
            network.defaultAction = timeout ? .deferred : .failure
            finish(fixture.final, in: h, settle: false)
            let uncleaned = plainSentences[0] + " " + plainSentences[4]
            XCTAssertEqual(network.requests.count, beforeRelease + 1)
            XCTAssertEqual(network.requests.last?.user, uncleaned)
            if timeout {
                h.clock.advance(by: .milliseconds(2_900))
                XCTAssertTrue(h.session.insertRequests.isEmpty)
            }
            h.clock.advance(by: timeout ? .milliseconds(200) : .milliseconds(250))
            // Obtain fallback wording through another real Session, not a stub of local cleanup.
            let expected = [try localOutput(plainSentences[0])] +
                plainSentences[1...3].map(ScriptedCleanupTransport.cleaned) +
                [try localOutput(plainSentences[4])]
            XCTAssertEqual(h.session.insertRequests.map(\.text), [expected.joined(separator: " ")])
            XCTAssertEqual(h.session.insertRequests.first?.autoSendAllowed, true)
            let panelAfterFallback = h.session.panel
            for index in network.pendingIndices { try network.succeed(index) }
            h.clock.advance(by: .seconds(5))
            XCTAssertEqual(h.session.insertRequests.map(\.text), [expected.joined(separator: " ")])
            XCTAssertEqual(h.session.panel, panelAfterFallback)
            XCTAssertEqual(network.requests.count, beforeRelease + 1, "No retries or duplicated sentences")
        }
    }

    func test_R256_longHoldsBoundCallCostAndAllowAtMostTwoBackgroundRequestsInFlight() throws {
        let fixture = try recording("long-plain")
        let network = ScriptedCleanupTransport()
        let h = try holding(network)
        replay(fixture, into: h)
        XCTAssertEqual(network.requests.map(\.user), Array(plainSentences.prefix(4)))
        finish(fixture.final, in: h)
        XCTAssertEqual(network.requests.map(\.user), plainSentences)
        XCTAssertLessThanOrEqual(network.requests.count, plainSentences.count)
        XCTAssertEqual(h.session.insertRequests.map(\.text), [cleanedPlain()])

        // A recognizer catches up with several sentences at once. Repeat a real recorded
        // partial twice, then keep repeating it while replies are delayed/out of order.
        let burst = ScriptedCleanupTransport()
        burst.defaultAction = .deferred
        let catchup = try holding(burst)
        let recorded = fixture.partials[10].text // Four complete sentences plus raw speech.
        catchup.speakWhileHeld(recorded, speechDuration: .milliseconds(1_600), isFinal: false)
        catchup.speakWhileHeld(recorded, speechDuration: .milliseconds(1_600), isFinal: false)
        catchup.clock.advance(by: .zero)
        XCTAssertEqual(burst.requests.count, 2, "Start two calls and queue the remaining sentences")
        XCTAssertEqual(burst.pendingIndices.count, 2)
        XCTAssertTrue(catchup.session.insertRequests.isEmpty)
        try burst.succeed(1) // Finish the second call first.
        catchup.clock.advance(by: .zero)
        XCTAssertLessThanOrEqual(burst.pendingIndices.count, 2)
        try burst.succeed(0)
        catchup.clock.advance(by: .zero)
        // Drain queued work without advancing to a timeout or allowing duplicate calls.
        for _ in 0..<4 {
            for index in burst.pendingIndices { try burst.succeed(index) }
            catchup.clock.advance(by: .zero)
        }
        catchup.speakWhileHeld(recorded, speechDuration: .milliseconds(1_600), isFinal: false)
        XCTAssertEqual(burst.requests.map(\.user).sorted(), Array(plainSentences.prefix(4)).sorted())
        XCTAssertLessThanOrEqual(burst.maximumInFlight, 2)
        burst.defaultAction = .immediate
        finish(fixture.final, in: catchup)
        XCTAssertEqual(burst.requests.count, plainSentences.count)
        XCTAssertEqual(catchup.session.insertRequests.map(\.text), [cleanedPlain()])
    }

    private struct Recording: Decodable {
        struct Partial: Decodable { var t: Double; var text: String }
        var partials: [Partial]
        var final: String
    }

    private func recording(_ name: String) throws -> Recording {
        // Resolve the source-file symlink too: the Core scratch package symlinks Tests.
        let directory = URL(fileURLWithPath: #filePath).resolvingSymlinksInPath()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/audio")
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent(name + ".wav").path))
        let data = try Data(contentsOf: directory.appendingPathComponent("whisper-partials.json"))
        return try XCTUnwrap(JSONDecoder().decode([String: Recording].self, from: data)[name])
    }

    private func holding(_ network: ScriptedCleanupTransport) throws -> TestHarness {
        let h = try TestHarness()
        h.session.setGatewayCleaner(GatewayCleaner(
            config: GatewayConfig(url: URL(string: "https://cleanup.invalid")!, key: "test-only"), transport: network))
        h.session.setCleanupBackend(.gateway)
        h.session.setPlugins([try PluginSpec.parse(Data(#"{"name":"screenshot","description":"Capture the screen","triggers":["take a screenshot"],"args":{},"action":{"type":"exec","path":"/bin/echo"},"confirm_delay_s":0}"#.utf8))])
        h.readyListening()
        h.pressTalkKey()
        return h
    }

    private func replay(_ fixture: Recording, into h: TestHarness) {
        for partial in fixture.partials { replay(partial, into: h) }
    }

    private func replay(_ partial: Recording.Partial, into h: TestHarness) {
        // Fixtures start at 1.6 s; all recorded partials are spaced 1.6 s apart.
        h.speakWhileHeld(partial.text, speechDuration: .milliseconds(1_600), isFinal: false)
        h.clock.advance(by: .zero)
    }

    private func finish(_ text: String, in h: TestHarness, settle: Bool = true) {
        h.speakWhileHeld(text, speechDuration: .zero, isFinal: true)
        h.releaseTalkKey()
        if settle { h.clock.advance(by: .milliseconds(250)) }
    }

    private func cleanedPlain() -> String {
        plainSentences.map(ScriptedCleanupTransport.cleaned).joined(separator: " ")
    }

    private func localOutput(_ raw: String) throws -> String {
        let h = try TestHarness()
        h.readyListening()
        h.pressTalkKey()
        h.speakWhileHeld(raw)
        h.releaseTalkKey()
        h.clock.advance(by: .milliseconds(250))
        return try XCTUnwrap(h.session.insertRequests.first).text
    }
}

/// Network boundary with synchronous, held, failed and never-replied-to requests.
/// A held callback can still arrive after the Session's timeout or cancellation.
private final class ScriptedCleanupTransport: GatewayHTTPTransport {
    enum Action { case immediate, deferred, failure, reply(String) }
    struct Request { let system: String; let user: String }
    var defaultAction: Action = .immediate
    var actionForUser: ((String) -> Action)?
    private(set) var requests: [Request] = []
    private(set) var maximumInFlight = 0
    private var completions: [Int: (Result<(Data, Int), Error>) -> Void] = [:]
    var pendingIndices: [Int] { completions.keys.sorted() }

    static func cleaned(_ user: String) -> String {
        "✓ " + user.replacingOccurrences(of: "⟦QUOTE⟧ ", with: "\"")
            .replacingOccurrences(of: " ⟦/QUOTE⟧", with: "\"")
    }

    func send(_ request: URLRequest, completion: @escaping (Result<(Data, Int), Error>) -> Void) {
        do {
            let body = try XCTUnwrap(request.httpBody)
            struct Body: Decodable {
                struct Message: Decodable { let role: String; let content: String }
                let messages: [Message]
            }
            let messages = try JSONDecoder().decode(Body.self, from: body).messages
            let system = try XCTUnwrap(messages.first { $0.role == "system" }?.content)
            let user = try XCTUnwrap(messages.first { $0.role == "user" }?.content)
            let index = requests.count
            requests.append(Request(system: system, user: user))
            completions[index] = completion
            maximumInFlight = max(maximumInFlight, completions.count)
            switch actionForUser?(user) ?? defaultAction {
            case .immediate: try succeed(index)
            case .deferred: break
            case .failure: completions.removeValue(forKey: index)?(.failure(URLError(.notConnectedToInternet)))
            case .reply(let text): try succeed(index, text: text)
            }
        } catch {
            XCTFail("Invalid gateway request: \(error)")
            completion(.failure(error))
        }
    }

    func succeed(_ index: Int, text: String? = nil) throws {
        let completion = try XCTUnwrap(completions.removeValue(forKey: index), "No pending request \(index)")
        let data = try JSONSerialization.data(withJSONObject: ["text": text ?? Self.cleaned(requests[index].user)])
        completion(.success((data, 200)))
    }
}
