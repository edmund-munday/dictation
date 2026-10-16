import DictationCore
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest

/// Exercise the gate at the last Core boundary the app consumes: queued commands.
/// Inline manifests exercise Core independently of the shipped Mac assets.
final class SnipSubjectTests: XCTestCase {
    private let ignoreWords = [
        "um", "uh", "er", "like", "so", "just", "please", "this", "that", "it", "here", "there",
        "the", "a", "an", "my", "whole", "entire", "full", "screen", "everything", "now",
    ]

    func test_R283_fastPathQueuesOnlyConcreteSubjectsWithoutGateway() throws {
        let cases: [(String, String?)] = [
            ("Take a screenshot.", nil),
            ("Take a screenshot of this.", nil),
            ("Um, screenshot this.", nil),
            ("Take a screenshot of the screen.", nil),
            ("Screenshot the Slack window.", "Slack window"),
            ("Screenshot that chart.", "chart"),
            ("Screenshot that.", nil),
            ("Screenshot that, um.", nil),
            ("Take a screenshot of the error dialog.", "the error dialog"),
        ]
        for (utterance, subject) in cases {
            let network = Transport()
            let h = try harness(plugin: plugin(), network: network)
            release(utterance, in: h)
            XCTAssertEqual(h.session.commandRequests.count, 1, utterance)
            let request = try XCTUnwrap(h.session.commandRequests.first)
            XCTAssertEqual(request.plugin.name, "screenshot", utterance)
            XCTAssertEqual(request.args["subject"]?.lowercased(), subject?.lowercased(), utterance)
            if subject == nil { XCTAssertEqual(request.args, [:], utterance) }
            assertCommandOnly(h, network: network, expectedRequests: 0)
        }
    }

    func test_R283_fastPathDropsEveryConfiguredIgnoreWordAndCombinations() throws {
        for subject in ignoreWords + ["THIS, that! THE screen", "um uh er just please my entire full screen now"] {
            let network = Transport()
            let h = try harness(plugin: plugin(), network: network)
            release("Take a screenshot of \(subject).", in: h)
            XCTAssertEqual(h.session.commandRequests.count, 1, subject)
            XCTAssertEqual(h.session.commandRequests.first?.args, [:], subject)
            assertCommandOnly(h, network: network, expectedRequests: 0)
        }
    }

    func test_R283_gatewayDropsDeicticSubjectBeforeCommandIsQueued() throws {
        for subject in ["this", "  THIS!  ", "Um, uh; the WHOLE screen, please!"] {
            let network = Transport(args: ["subject": subject])
            let h = try harness(plugin: plugin(), network: network)
            release("Capture what I am pointing at.", in: h)
            XCTAssertEqual(h.session.commandRequests.count, 1, subject)
            XCTAssertEqual(h.session.commandRequests.first?.args, [:], subject)
            assertCommandOnly(h, network: network, expectedRequests: 1)
        }
    }

    func test_R283_gatewayKeepsConcreteSubjectAsSpokenAndTrimsEdges() throws {
        for subject in ["  the Slack window  ", "that chart", "the error dialog", "this <Chart> & *legend*!"] {
            let network = Transport(args: ["subject": subject])
            let h = try harness(plugin: plugin(), network: network)
            release("Capture what I am pointing at.", in: h)
            XCTAssertEqual(h.session.commandRequests.count, 1)
            XCTAssertEqual(h.session.commandRequests.first?.args,
                           ["subject": subject.trimmingCharacters(in: .whitespacesAndNewlines)])
            assertCommandOnly(h, network: network, expectedRequests: 1)
        }
    }

    func test_R283_missingOrEmptyIgnoreWordsPreservesOtherwiseIgnoredSubject() throws {
        let configurations: [[String]?] = [nil, []]
        for words in configurations {
            let network = Transport(args: ["subject": "this"])
            let h = try harness(plugin: plugin(ignoreWords: words), network: network)
            release("Capture what I am pointing at.", in: h)
            XCTAssertEqual(h.session.commandRequests.count, 1)
            XCTAssertEqual(h.session.commandRequests.first?.args, ["subject": "this"])
            assertCommandOnly(h, network: network, expectedRequests: 1)
        }
    }

    func test_R283_gateIsPerArgumentAndLeavesUnconfiguredArgsInRequest() throws {
        let network = Transport(args: ["subject": "this", "caption": "this"])
        let h = try harness(plugin: plugin(ignoreWords: ignoreWords, includeCaption: true), network: network)
        release("Capture what I am pointing at.", in: h)
        XCTAssertEqual(h.session.commandRequests.count, 1)
        XCTAssertEqual(h.session.commandRequests.first?.args, ["caption": "this"])
        assertCommandOnly(h, network: network, expectedRequests: 1)
    }

    func test_R294_ignoreWordsDecodesAndDefaultsToEmpty() throws {
        let absent = try plugin(ignoreWords: nil)
        XCTAssertEqual(absent.args["subject"]?.ignoreWords, [])
        let configured = try plugin()
        XCTAssertEqual(configured.args["subject"]?.ignoreWords, ignoreWords)
        let encoded = try JSONEncoder().encode(configured)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let args = try XCTUnwrap(object["args"] as? [String: [String: Any]])
        XCTAssertEqual(args["subject"]?["ignore_words"] as? [String], ignoreWords)
        XCTAssertNil(args["subject"]?["ignoreWords"])
        let prompt = try XCTUnwrap(CommandRouter.promptSection(for: [configured]))
        XCTAssertFalse(prompt.contains("ignore_words"))
    }

    func test_R294_normalisesListEntriesAndDropsZeroWordValues() throws {
        let p = try plugin(ignoreWords: ["Whole-Screen", "PLEASE!"])
        for subject in ["whole screen", " WHOLE-SCREEN, please! ", "...!", "  "] {
            XCTAssertEqual(p.validated(["subject": subject]), [:], subject)
        }
        XCTAssertEqual(p.validated(["subject": "  Whole-Screen chart!  "]),
                       ["subject": "Whole-Screen chart!"])
        XCTAssertEqual(try plugin(ignoreWords: nil).validated(["subject": "?!"]), [:])
    }

    func test_R294_droppedRequiredArgFallsBackToDictationInBothRoutes() throws {
        var p = try plugin()
        p.args["subject"]?.required = true
        XCTAssertNil(p.validated(["subject": "this"]))
        XCTAssertNil(TriggerMatcher.match("take a screenshot of this", plugins: [p]))
        let reply = #"{"mode":"command","plugin":"screenshot","args":{"subject":"this"},"confidence":1,"text":"Take a screenshot of this."}"#
        XCTAssertEqual(CommandRouter.parse(reply, plugins: [p]), .dictation("Take a screenshot of this."))
    }

    func test_R294_droppedArgUsesExistingDefaultLogic() throws {
        var p = try plugin()
        // Programmatic configuration exercises validation order; manifests cannot combine these options.
        p.args["subject"]?.default = "desktop"
        XCTAssertEqual(p.validated(["subject": "this"]), ["subject": "desktop"])
        XCTAssertEqual(p.validated(["subject": "?!"]), ["subject": "desktop"])
    }

    func test_R294_parseRejectsDefaultCombinedWithIgnoreWordsEvenEmpty() throws {
        for words in [[], ["this"]] as [[String]] {
            let manifest: [String: Any] = [
                "name": "bad", "action": ["path": "/bin/echo"],
                "args": ["subject": ["default": "desktop", "ignore_words": words]],
            ]
            XCTAssertThrowsError(try PluginSpec.parse(JSONSerialization.data(withJSONObject: manifest)))
        }
    }

    func test_R295_timeoutUsesOnlyPresentOptionalArgKeysAndFallsBackWhenUnset() throws {
        var p = try plugin()
        XCTAssertEqual(p.timeoutWithArgsSeconds, 40)
        XCTAssertEqual(p.timeout(for: [:]), 15)
        XCTAssertEqual(p.timeout(for: ["subject": "chart"]), 40)
        XCTAssertEqual(p.timeout(for: ["unknown": "chart"]), 15)
        XCTAssertEqual(p.timeout(for: try XCTUnwrap(p.validated(["subject": "this"]))), 15)
        p.args["subject"]?.required = true
        XCTAssertEqual(p.timeout(for: ["subject": "chart"]), 15)
        p.args["subject"]?.required = false
        p.timeoutWithArgsSeconds = nil
        XCTAssertEqual(p.timeout(for: ["subject": "chart"]), 15)
    }

    func test_R295_bothTimeoutFieldsClampAndOptionalTimeoutDefaultsNil() throws {
        let minimal = #"{"name":"t","action":{"path":"/bin/echo"}}"#
        XCTAssertNil(try PluginSpec.parse(Data(minimal.utf8)).timeoutWithArgsSeconds)
        for (value, expected) in [(-1.0, 0.1), (0.05, 0.1), (3.0, 3.0), (200.0, 120.0)] {
            let manifest: [String: Any] = ["name": "t", "action": ["path": "/bin/echo"],
                                          "timeout_s": value, "timeout_with_args_s": value]
            let p = try PluginSpec.parse(JSONSerialization.data(withJSONObject: manifest))
            XCTAssertEqual(p.timeoutSeconds, expected)
            XCTAssertEqual(p.timeoutWithArgsSeconds, expected)
        }
    }

    func test_R286_notifyReasonReachesPanelAsPlainText() throws {
        let network = Transport()
        let h = try harness(plugin: plugin(), network: network)
        release("Screenshot that chart.", in: h)
        let text = "Full screenshot copied: <b>no match</b> & *try again*"
        let stdout = String(decoding: try JSONSerialization.data(withJSONObject: ["notify": text]), as: UTF8.self)
        h.session.ingestPluginResult(for: 0, output: PluginOutput.parse(stdout: stdout))
        XCTAssertEqual(h.session.panel.text, text)
        XCTAssertTrue(h.session.insertRequests.isEmpty)
    }

    private func plugin() throws -> PluginSpec { try plugin(ignoreWords: ignoreWords) }

    private func plugin(ignoreWords: [String]?, includeCaption: Bool = false) throws -> PluginSpec {
        var subject: [String: Any] = ["type": "string", "required": false]
        if let ignoreWords { subject["ignore_words"] = ignoreWords }
        var args: [String: Any] = ["subject": subject]
        if includeCaption { args["caption"] = ["type": "string", "required": false] }
        let manifest: [String: Any] = [
            "name": "screenshot",
            "triggers": ["take a screenshot", "take a screenshot of {subject}", "grab a screenshot",
                         "grab a screenshot of {subject}", "screenshot", "screenshot this", "screenshot that",
                         "screenshot the {subject}", "screenshot that {subject}"],
            "args": args,
            "action": ["type": "exec", "path": "bin/snip-capture.py"],
            "timeout_s": 15, "timeout_with_args_s": 40, "confirm_delay_s": 0,
        ]
        return try PluginSpec.parse(JSONSerialization.data(withJSONObject: manifest))
    }

    private func harness(plugin: PluginSpec, network: Transport) throws -> TestHarness {
        let h = try TestHarness()
        h.session.setGatewayCleaner(GatewayCleaner(
            config: GatewayConfig(url: URL(string: "https://gateway.invalid")!, key: "test-only-key"),
            transport: network))
        h.session.setCleanupBackend(.gateway)
        h.session.setPlugins([plugin])
        return h
    }

    private func release(_ text: String, in h: TestHarness) {
        h.readyListening()
        h.pressTalkKey()
        h.speakWhileHeld(text)
        h.releaseTalkKey()
    }

    private func assertCommandOnly(_ h: TestHarness, network: Transport, expectedRequests: Int,
                                   file: StaticString = #filePath, line: UInt = #line) {
        h.clock.advance(by: .seconds(12))
        XCTAssertEqual(network.requests.count, expectedRequests, file: file, line: line)
        XCTAssertEqual(h.session.commandRequests.count, 1, "Execute once", file: file, line: line)
        XCTAssertTrue(h.session.insertRequests.isEmpty, file: file, line: line)
        XCTAssertTrue(h.session.emittedKeyEvents.isEmpty, file: file, line: line)
    }

    /// Only the HTTP boundary is scripted; GatewayCleaner and routing are real.
    private final class Transport: GatewayHTTPTransport {
        var requests: [URLRequest] = []
        let args: [String: String]?
        init(args: [String: String]? = nil) { self.args = args }

        func send(_ request: URLRequest, completion: @escaping (Result<(Data, Int), Error>) -> Void) {
            requests.append(request)
            do {
                let reply: String
                if let args {
                    let command: [String: Any] = ["mode": "command", "plugin": "screenshot", "args": args,
                                                  "confidence": 0.99, "text": "Capture this."]
                    reply = String(decoding: try JSONSerialization.data(withJSONObject: command), as: UTF8.self)
                } else {
                    reply = "Unexpected gateway request."
                }
                completion(.success((try JSONSerialization.data(withJSONObject: ["text": reply]), 200)))
            } catch { completion(.failure(error)) }
        }
    }
}
