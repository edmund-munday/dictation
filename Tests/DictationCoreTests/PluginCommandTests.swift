import DictationCore
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest

/// R229-R233, R236-R237: voice-command routing, local fast path, and cancel windows.
final class PluginCommandTests: XCTestCase {
    static let screenshotJSON = """
    {"name":"screenshot","description":"Take a screenshot of the screen and copy it to the clipboard.",
     "triggers":["take a screenshot","take a screenshot of {subject}","grab a screenshot","screenshot this"],
     "args":{"subject":{"type":"string","description":"what to capture"}},
     "action":{"type":"exec","path":"/bin/echo","argv":["{subject}"]},"timeout_s":15}
    """
    static let echoJSON = """
    {"name":"echo","description":"Test plugin that echoes text back.","triggers":["test echo {text}"],
     "args":{"text":{"type":"string","required":true}},"action":{"type":"exec","path":"/bin/echo"}}
    """

    private func plugins() throws -> [PluginSpec] {
        [try PluginSpec.parse(Data(Self.screenshotJSON.utf8)), try PluginSpec.parse(Data(Self.echoJSON.utf8))]
    }

    // R229 plugin files
    func test_R229_parsesPluginWithDefaults() throws {
        let p = try PluginSpec.parse(Data(Self.echoJSON.utf8))
        XCTAssertEqual(p.name, "echo")
        XCTAssertTrue(p.enabled)
        XCTAssertEqual(p.timeoutSeconds, 10)
        XCTAssertEqual(p.action.argv, [])
        XCTAssertEqual(p.args["text"]?.required, true)
        XCTAssertEqual(try PluginSpec.parse(Data(Self.screenshotJSON.utf8)).timeoutSeconds, 15)
    }

    func test_R229_loaderSkipsBadFilesAndReportsThem() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data(Self.echoJSON.utf8).write(to: dir.appendingPathComponent("echo.json"))
        try Data("{nope".utf8).write(to: dir.appendingPathComponent("bad.json"))
        let result = PluginLoader.load(directory: dir)
        XCTAssertEqual(result.plugins.map(\.name), ["echo"])
        XCTAssertNotNil(result.errors["bad.json"])
    }

    // R230 local fallback matching
    func test_R230_localTriggerMatchesPrefixAndExtractsArg() throws {
        let p = try plugins()
        XCTAssertEqual(TriggerMatcher.match("Take a screenshot of the error dialog.", plugins: p),
                       CommandMatch(plugin: "screenshot", args: ["subject": "the error dialog"], confidence: 1))
        XCTAssertEqual(TriggerMatcher.match("take a screenshot", plugins: p)?.plugin, "screenshot")
        XCTAssertEqual(TriggerMatcher.match("Screenshot this!", plugins: p)?.plugin, "screenshot")
        XCTAssertNil(TriggerMatcher.match("I need to take a screenshot later", plugins: p))
        XCTAssertNil(TriggerMatcher.match("test echo", plugins: p), "required arg missing")
    }

    // R231 router
    func test_R231_routerRunsOnlyConfidentValidCommands() throws {
        let p = try plugins()
        func json(_ o: [String: Any]) -> String { String(data: try! JSONSerialization.data(withJSONObject: o), encoding: .utf8)! }
        let cmd = json(["mode": "command", "plugin": "screenshot", "args": ["subject": "the error dialog"], "confidence": 0.93, "text": "Take a screenshot of the error dialog."])
        XCTAssertEqual(CommandRouter.parse(cmd, plugins: p),
                       .command(CommandMatch(plugin: "screenshot", args: ["subject": "the error dialog"], confidence: 0.93)))
        let low = json(["mode": "command", "plugin": "screenshot", "args": [:], "confidence": 0.6, "text": "Screenshot it."])
        XCTAssertEqual(CommandRouter.parse(low, plugins: p), .dictation("Screenshot it."))
        let unknown = json(["mode": "command", "plugin": "nope", "args": [:], "confidence": 0.99, "text": "Nope."])
        XCTAssertEqual(CommandRouter.parse(unknown, plugins: p), .dictation("Nope."))
        let missing = json(["mode": "command", "plugin": "echo", "args": [:], "confidence": 0.99, "text": "Test echo."])
        XCTAssertEqual(CommandRouter.parse(missing, plugins: p), .dictation("Test echo."))
        let dict = json(["mode": "dictation", "confidence": 0.99, "text": "Hello there."])
        XCTAssertEqual(CommandRouter.parse(dict, plugins: p), .dictation("Hello there."))
        XCTAssertEqual(CommandRouter.parse("Plain cleaned text.", plugins: p), .dictation("Plain cleaned text."))
        var disabled = p
        disabled[0].enabled = false
        XCTAssertEqual(CommandRouter.parse(cmd, plugins: disabled), .dictation("Take a screenshot of the error dialog."))
    }

    func test_R231_gatewayPromptListsEnabledPluginsOnly() throws {
        let transport = Stub(text: "Hello.")
        let cleaner = GatewayCleaner(config: config(), transport: transport)
        var p = try plugins()
        p[1].enabled = false
        cleaner.clean("hello", plugins: p) { _ in }
        cleaner.clean("hello") { _ in }
        let withPlugins = try systemPrompt(transport.requests[0])
        XCTAssertTrue(withPlugins.contains("take a screenshot of {subject}"))
        XCTAssertTrue(withPlugins.contains("\"mode\""))
        XCTAssertFalse(withPlugins.contains("test echo"))
        XCTAssertFalse(try systemPrompt(transport.requests[1]).contains("take a screenshot of {subject}"))
    }

    // R232 session routing
    func test_R232_commandIsNotTypedAndRunsAfterCancelWindow() throws {
        let h = try harness(gatewayReply: commandReply())
        release(h, "capture the error dialog for me")
        h.clock.advance(by: .milliseconds(250))
        XCTAssertTrue(h.session.insertRequests.isEmpty)
        XCTAssertTrue(h.session.commandRequests.isEmpty)
        XCTAssertEqual(h.session.panel.text, "Running: screenshot")
        h.clock.advance(by: .milliseconds(1500))
        XCTAssertEqual(h.session.commandRequests.count, 1)
        let r = try XCTUnwrap(h.session.commandRequests.first)
        XCTAssertEqual(r.plugin.name, "screenshot")
        XCTAssertEqual(r.args, ["subject": "the error dialog"])
        XCTAssertTrue(h.session.insertRequests.isEmpty)
        XCTAssertTrue(h.session.emittedKeyEvents.isEmpty)
    }

    func test_R232_anyKeyInCancelWindowCancels() throws {
        let h = try harness(gatewayReply: commandReply())
        release(h, "capture the error dialog for me")
        h.clock.advance(by: .milliseconds(250))
        h.pressOtherKey(.character("x"))
        h.clock.advance(by: .milliseconds(2000))
        XCTAssertTrue(h.session.commandRequests.isEmpty)
        XCTAssertTrue(h.session.insertRequests.isEmpty)
        XCTAssertEqual(h.session.panel.text, "Cancelled: screenshot")
    }

    func test_R232_lowConfidenceIsTypedAsDictation() throws {
        let reply = try json(["mode": "command", "plugin": "screenshot", "args": [:], "confidence": 0.5, "text": "Screenshot time."])
        let h = try harness(gatewayReply: reply)
        release(h, "screenshot time")
        h.clock.advance(by: .milliseconds(2000))
        XCTAssertEqual(h.session.insertRequests.map(\.text), ["Screenshot time."])
        XCTAssertTrue(h.session.commandRequests.isEmpty)
    }

    func test_R232_gatewayFailureFallsBackToLocalPhraseMatch() throws {
        let h = try harness(gatewayReply: nil)
        release(h, "take a screenshot of the error dialog")
        h.clock.advance(by: .milliseconds(250))
        h.clock.advance(by: .milliseconds(1500))
        XCTAssertEqual(h.session.commandRequests.first?.args, ["subject": "the error dialog"])
        XCTAssertTrue(h.session.insertRequests.isEmpty)
    }

    func test_R232_neverRunsInSecureFields() throws {
        let h = try harness(gatewayReply: commandReply())
        h.latchOn()
        h.focusEditable(role: .secureTextField, secure: true)
        h.pressTalkKey()
        h.speakWhileHeld("take a screenshot of the error dialog")
        h.releaseTalkKey()
        h.clock.advance(by: .milliseconds(4000))
        XCTAssertTrue(h.session.commandRequests.isEmpty)
    }

    func test_R232_commandWithoutFocusedFieldStillRuns() throws {
        let h = try harness(gatewayReply: commandReply())
        h.latchOn()
        h.clearFocus()
        h.pressTalkKey()
        h.speakWhileHeld("capture the error dialog for me")
        h.releaseTalkKey()
        h.clock.advance(by: .milliseconds(2000))
        XCTAssertEqual(h.session.commandRequests.count, 1)
    }

    // R233 plugin output + corpus
    func test_R233_pluginInsertGoesThroughInsertionAndSendIsOptIn() throws {
        let h = try harness(gatewayReply: commandReply())
        release(h, "take a screenshot of the error dialog")
        h.clock.advance(by: .milliseconds(1750))
        h.session.ingestPluginResult(for: 0, output: PluginOutput(insert: "done", notify: "Copied", send: nil))
        XCTAssertEqual(h.session.insertRequests.map(\.text), ["done"])
        XCTAssertEqual(h.session.insertRequests.first?.autoSendAllowed, false)
        XCTAssertEqual(h.session.panel.text, "Copied")
        h.session.ingestPluginResult(for: 0, output: PluginOutput(insert: "again", notify: nil, send: true))
        XCTAssertEqual(h.session.insertRequests.last?.autoSendAllowed, true)
    }

    func test_R233_pluginOutputParsing() {
        XCTAssertEqual(PluginOutput.parse(stdout: #"{"insert":"hi","notify":"Done","send":false}"#),
                       PluginOutput(insert: "hi", notify: "Done", send: false))
        XCTAssertEqual(PluginOutput.parse(stdout: "plain"), PluginOutput(insert: nil, notify: nil, send: nil))
    }

    func test_R233_commandIsRecordedWithModeAndPlugin() throws {
        let h = try harness(gatewayReply: commandReply())
        release(h, "take a screenshot of the error dialog")
        h.clock.advance(by: .milliseconds(1750))
        let r = try XCTUnwrap(h.session.utteranceRecords.last)
        XCTAssertEqual(r.mode, "command")
        XCTAssertEqual(r.plugin, "screenshot")
        XCTAssertNil(r.insertIndex)
        XCTAssertFalse(r.autoSendAllowed)
    }

    // R236 local fast path. A contradictory gateway reply makes accidental routing observable.
    func test_R236_normalizedExactTriggersBypassGatewayAndNeverType() throws {
        let p = try plugin(Self.screenshotJSON, overriding: ["confirm_delay_s": 0])
        for transcript in ["TAKE A SCREENSHOT!", "Um, take a screenshot.", "Uh, take a screenshot!",
                           "So, take a screenshot.", "Okay, take a screenshot.",
                           "Um, uh, so, okay, take a screenshot."] {
            let stub = Stub(text: "This would be typed by the gateway.")
            let h = try harness(transport: stub, plugins: [p])
            release(h, transcript)
            XCTAssertTrue(stub.requests.isEmpty, transcript)
            XCTAssertEqual(h.session.commandRequests.count, 1, transcript)
            XCTAssertEqual(h.session.commandRequests.first?.plugin.name, "screenshot", transcript)
            XCTAssertEqual(h.session.commandRequests.first?.args, [:], transcript)
            h.clock.advance(by: .seconds(4))
            XCTAssertTrue(stub.requests.isEmpty, transcript)
            XCTAssertEqual(h.session.commandRequests.count, 1, "Must run exactly once: \(transcript)")
            XCTAssertTrue(h.session.insertRequests.isEmpty, transcript)
            XCTAssertTrue(h.session.emittedKeyEvents.isEmpty, transcript)
        }
    }

    func test_R236_prefixTriggerExtractsArgumentWithoutGateway() throws {
        let p = try plugin(Self.screenshotJSON, overriding: ["confirm_delay_s": 0])
        for subject in ["the error dialog", "okay so the error dialog"] {
            let stub = Stub(text: "Gateway dictation.")
            let h = try harness(transport: stub, plugins: [p])
            release(h, "Um, take a screenshot of \(subject).")
            XCTAssertTrue(stub.requests.isEmpty)
            XCTAssertEqual(h.session.commandRequests.count, 1)
            XCTAssertEqual(h.session.commandRequests.first?.plugin.name, "screenshot")
            XCTAssertEqual(h.session.commandRequests.first?.args, ["subject": subject])
            XCTAssertTrue(h.session.insertRequests.isEmpty)
            XCTAssertTrue(h.session.emittedKeyEvents.isEmpty)
        }
    }

    func test_R236_nonmatchingOrMissingRequiredArgumentUsesGatewayDictation() throws {
        let requiredEvenForExact = try plugin(Self.echoJSON, overriding: ["triggers": ["test echo", "test echo {text}"]])
        for transcript in ["I need to take a screenshot later", "take a screenshot later",
                           "take a screenshot of", "test echo", "test echo !!!"] {
            let stub = Stub(text: "Gateway dictation.")
            let h = try harness(transport: stub, plugins: [try plugins()[0], requiredEvenForExact])
            release(h, transcript)
            XCTAssertEqual(stub.requests.count, 1, transcript)
            h.clock.advance(by: .seconds(4))
            XCTAssertEqual(h.session.insertRequests.map(\.text), ["Gateway dictation."], transcript)
            XCTAssertTrue(h.session.commandRequests.isEmpty, transcript)
        }
    }

    func test_R236_equalSpecificityAcrossPluginsUsesGatewayRegardlessOfOrder() throws {
        let first = try plugin(Self.echoJSON, overriding: ["name": "first", "confirm_delay_s": 0])
        let second = try plugin(Self.echoJSON, overriding: ["name": "second", "confirm_delay_s": 0])
        let exactFirst = try plugin(Self.screenshotJSON, overriding: ["name": "first", "confirm_delay_s": 0])
        let exactSecond = try plugin(Self.screenshotJSON, overriding: ["name": "second", "confirm_delay_s": 0])
        for (transcript, candidates) in [("test echo hello", [first, second]),
                                        ("take a screenshot", [exactFirst, exactSecond])] {
            for ordered in [candidates, Array(candidates.reversed())] {
                let stub = Stub(text: "Ambiguous command becomes dictation.")
                let h = try harness(transport: stub, plugins: ordered)
                release(h, transcript)
                XCTAssertEqual(stub.requests.count, 1, transcript)
                h.clock.advance(by: .seconds(4))
                XCTAssertTrue(h.session.commandRequests.isEmpty, transcript)
                XCTAssertEqual(h.session.insertRequests.map(\.text), ["Ambiguous command becomes dictation."], transcript)
            }
        }
    }

    func test_R236_moreSpecificTemplateWinsRegardlessOfPluginOrder() throws {
        let broad = try plugin(Self.echoJSON, overriding: ["triggers": ["take {text}"], "confirm_delay_s": 0])
        let specific = try plugin(Self.screenshotJSON, overriding: ["confirm_delay_s": 0])
        for ordered in [[broad, specific], [specific, broad]] {
            let stub = Stub(text: "Gateway dictation.")
            let h = try harness(transport: stub, plugins: ordered)
            release(h, "take a screenshot of the error dialog")
            XCTAssertTrue(stub.requests.isEmpty)
            XCTAssertEqual(h.session.commandRequests.count, 1)
            XCTAssertEqual(h.session.commandRequests.first?.plugin.name, "screenshot")
            XCTAssertEqual(h.session.commandRequests.first?.args, ["subject": "the error dialog"])
            XCTAssertTrue(h.session.insertRequests.isEmpty)
        }
    }

    func test_R236_duplicateTemplatesWithinOnePluginAreNotAmbiguous() throws {
        let p = try plugin(Self.echoJSON, overriding: ["triggers": ["test echo {text}", "test echo {text}"],
                                                     "confirm_delay_s": 0])
        let stub = Stub(text: "Gateway dictation.")
        let h = try harness(transport: stub, plugins: [p])
        release(h, "test echo hello")
        XCTAssertTrue(stub.requests.isEmpty)
        XCTAssertEqual(h.session.commandRequests.count, 1)
        XCTAssertEqual(h.session.commandRequests.first?.args, ["text": "hello"])
        XCTAssertTrue(h.session.insertRequests.isEmpty)
    }

    func test_R236_disabledPluginCannotMatchOrCauseAmbiguity() throws {
        let enabled = try plugin(Self.screenshotJSON, overriding: ["confirm_delay_s": 0])
        let disabled = try plugin(Self.screenshotJSON, overriding: ["name": "disabled", "enabled": false,
                                                                  "confirm_delay_s": 0])
        let stub = Stub(text: "Gateway dictation.")
        let h = try harness(transport: stub, plugins: [disabled, enabled])
        release(h, "take a screenshot")
        XCTAssertTrue(stub.requests.isEmpty)
        XCTAssertEqual(h.session.commandRequests.count, 1)
        XCTAssertEqual(h.session.commandRequests.first?.plugin.name, "screenshot")
        XCTAssertTrue(h.session.insertRequests.isEmpty)

        // An enabled but unrelated plugin must not make a disabled trigger eligible.
        let unrelated = try plugin(Self.echoJSON, overriding: ["confirm_delay_s": 0])
        for candidates in [[disabled, unrelated], [disabled], []] {
            let fallbackStub = Stub(text: "Gateway dictation.")
            let fallback = try harness(transport: fallbackStub, plugins: candidates)
            release(fallback, "take a screenshot")
            XCTAssertEqual(fallbackStub.requests.count, 1)
            fallback.clock.advance(by: .seconds(4))
            XCTAssertTrue(fallback.session.commandRequests.isEmpty)
            XCTAssertEqual(fallback.session.insertRequests.map(\.text), ["Gateway dictation."])
        }
    }

    func test_R236_secureFieldNeverRunsOrTypesMatchingCommand() throws {
        let stub = Stub(text: commandReply())
        let p = try plugin(Self.screenshotJSON, overriding: ["confirm_delay_s": 0])
        let h = try harness(transport: stub, plugins: [p])
        h.latchOn()
        h.focusEditable(role: .secureTextField, secure: true)
        h.pressTalkKey()
        h.speakWhileHeld("Um, take a screenshot.")
        h.releaseTalkKey()
        h.clock.advance(by: .seconds(12))
        XCTAssertTrue(h.session.commandRequests.isEmpty)
        XCTAssertTrue(h.session.insertRequests.isEmpty)
        XCTAssertTrue(h.session.emittedKeyEvents.isEmpty)
    }

    func test_R236_fastCommandRunsWithoutFocusedField() throws {
        let stub = Stub(text: "Gateway dictation.")
        let p = try plugin(Self.screenshotJSON, overriding: ["confirm_delay_s": 0])
        let h = try harness(transport: stub, plugins: [p])
        h.latchOn()
        h.clearFocus()
        h.pressTalkKey()
        h.speakWhileHeld("take a screenshot")
        h.releaseTalkKey()
        XCTAssertTrue(stub.requests.isEmpty)
        XCTAssertEqual(h.session.commandRequests.count, 1)
        XCTAssertEqual(h.session.commandRequests.first?.plugin.name, "screenshot")
        XCTAssertTrue(h.session.insertRequests.isEmpty)
    }

    func test_R236_focusBecomesSecureBeforeReleasePreventsCommandAndTyping() throws {
        let stub = Stub(text: commandReply())
        let p = try plugin(Self.screenshotJSON, overriding: ["confirm_delay_s": 0])
        let h = try harness(transport: stub, plugins: [p])
        h.readyListening()
        h.pressTalkKey()
        h.speakWhileHeld("take a screenshot")
        h.focusEditable(role: .secureTextField, secure: true)
        h.releaseTalkKey()
        h.clock.advance(by: .seconds(12))
        XCTAssertTrue(h.session.commandRequests.isEmpty)
        XCTAssertTrue(h.session.insertRequests.isEmpty)
        XCTAssertTrue(h.session.emittedKeyEvents.isEmpty)
    }

    // R237 delays are checked from release, without advancing the clock for zero.
    func test_R237_omittedDelayWaitsExactlyOneAndAHalfSeconds() throws {
        let stub = Stub(text: "Gateway dictation.")
        let h = try harness(transport: stub, plugins: [try plugins()[0]])
        release(h, "take a screenshot")
        XCTAssertTrue(stub.requests.isEmpty)
        XCTAssertEqual(h.session.panel.text, "Running: screenshot")
        XCTAssertTrue(h.session.commandRequests.isEmpty)
        h.clock.advance(by: .milliseconds(1499))
        XCTAssertTrue(h.session.commandRequests.isEmpty)
        h.clock.advance(by: .milliseconds(1))
        XCTAssertEqual(h.session.commandRequests.count, 1)
        XCTAssertEqual(h.session.commandRequests.first?.plugin.name, "screenshot")
        XCTAssertTrue(h.session.insertRequests.isEmpty)
    }

    func test_R237_delayBelongsToTheMatchedPlugin() throws {
        let screenshot = try plugin(Self.screenshotJSON, overriding: ["confirm_delay_s": 0])
        let echo = try plugin(Self.echoJSON, overriding: ["confirm_delay_s": 0.5])
        for (transcript, name, delayMS) in [("take a screenshot", "screenshot", 0),
                                           ("test echo hello", "echo", 500)] {
            let stub = Stub(text: "Gateway dictation.")
            let h = try harness(transport: stub, plugins: [screenshot, echo])
            release(h, transcript)
            XCTAssertTrue(stub.requests.isEmpty)
            XCTAssertEqual(h.session.panel.text, "Running: \(name)")
            if delayMS > 0 {
                XCTAssertTrue(h.session.commandRequests.isEmpty)
                h.clock.advance(by: .milliseconds(delayMS - 1))
                XCTAssertTrue(h.session.commandRequests.isEmpty)
                h.clock.advance(by: .milliseconds(1))
            }
            XCTAssertEqual(h.session.commandRequests.count, 1)
            XCTAssertEqual(h.session.commandRequests.first?.plugin.name, name)
            h.clock.advance(by: .seconds(12))
            XCTAssertEqual(h.session.commandRequests.count, 1)
            XCTAssertTrue(h.session.insertRequests.isEmpty)
        }
    }

    func test_R237_anyKeyJustBeforeDelayExpiresCancelsPermanently() throws {
        let p = try plugin(Self.screenshotJSON, overriding: ["confirm_delay_s": 0.5])
        for key: KeyIdentity in [.character("x"), .escape, .shortcut("copy"), .modifier("shift"), .command(.right)] {
            let stub = Stub(text: "Gateway dictation.")
            let h = try harness(transport: stub, plugins: [p])
            release(h, "take a screenshot")
            XCTAssertTrue(stub.requests.isEmpty)
            XCTAssertEqual(h.session.panel.text, "Running: screenshot")
            h.clock.advance(by: .milliseconds(499))
            XCTAssertTrue(h.session.commandRequests.isEmpty)
            h.pressOtherKey(key)
            h.clock.advance(by: .seconds(12))
            XCTAssertEqual(h.session.panel.text, "Cancelled: screenshot")
            XCTAssertTrue(h.session.commandRequests.isEmpty)
            XCTAssertTrue(h.session.insertRequests.isEmpty)
        }
    }

    func test_R237_delayIsClampedToZeroThroughTenSeconds() throws {
        for (delay, expectedMS) in [(-0.5, 0), (10.0, 10000), (25.0, 10000)] {
            let p = try plugin(Self.screenshotJSON, overriding: ["confirm_delay_s": delay])
            let stub = Stub(text: "Gateway dictation.")
            let h = try harness(transport: stub, plugins: [p])
            release(h, "take a screenshot")
            XCTAssertTrue(stub.requests.isEmpty)
            if expectedMS > 0 {
                XCTAssertEqual(h.session.panel.text, "Running: screenshot")
                XCTAssertTrue(h.session.commandRequests.isEmpty)
                h.clock.advance(by: .milliseconds(expectedMS - 1))
                XCTAssertTrue(h.session.commandRequests.isEmpty)
                h.clock.advance(by: .milliseconds(1))
            }
            XCTAssertEqual(h.session.commandRequests.count, 1, "confirm_delay_s: \(delay)")
            XCTAssertEqual(h.session.commandRequests.first?.plugin.name, "screenshot")
            XCTAssertTrue(h.session.insertRequests.isEmpty)
        }
    }

    func test_R237_gatewayRoutedCommandAlsoUsesPluginDelay() throws {
        let stub = Stub(text: commandReply())
        let p = try plugin(Self.screenshotJSON, overriding: ["confirm_delay_s": 0.5])
        let h = try harness(transport: stub, plugins: [p])
        release(h, "capture the error dialog for me")
        XCTAssertEqual(stub.requests.count, 1)
        h.clock.advance(by: .milliseconds(250))
        XCTAssertEqual(h.session.panel.text, "Running: screenshot")
        XCTAssertTrue(h.session.commandRequests.isEmpty)
        h.clock.advance(by: .milliseconds(499))
        XCTAssertTrue(h.session.commandRequests.isEmpty)
        h.clock.advance(by: .milliseconds(1))
        XCTAssertEqual(h.session.commandRequests.count, 1)
        XCTAssertEqual(h.session.commandRequests.first?.args, ["subject": "the error dialog"])
        XCTAssertTrue(h.session.insertRequests.isEmpty)
    }

    // MARK: helpers
    private func plugin(_ source: String, overriding fields: [String: Any]) throws -> PluginSpec {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(source.utf8)) as? [String: Any])
        object.merge(fields) { _, new in new }
        return try PluginSpec.parse(JSONSerialization.data(withJSONObject: object))
    }
    private func json(_ o: [String: Any]) throws -> String {
        String(data: try JSONSerialization.data(withJSONObject: o), encoding: .utf8)!
    }
    private func commandReply() -> String {
        try! json(["mode": "command", "plugin": "screenshot", "args": ["subject": "the error dialog"],
                   "confidence": 0.93, "text": "Take a screenshot of the error dialog."])
    }
    private func config() -> GatewayConfig { GatewayConfig(url: URL(string: "https://gateway.invalid")!, key: "test-only-key") }
    private func harness(gatewayReply: String?) throws -> TestHarness {
        try harness(transport: Stub(text: gatewayReply), plugins: plugins())
    }
    private func harness(transport: Stub, plugins: [PluginSpec]) throws -> TestHarness {
        let h = try TestHarness()
        h.session.setGatewayCleaner(GatewayCleaner(config: config(), transport: transport))
        h.session.setCleanupBackend(.gateway)
        h.session.setPlugins(plugins)
        return h
    }
    private func release(_ h: TestHarness, _ raw: String) {
        h.readyListening()
        h.pressTalkKey()
        h.speakWhileHeld(raw)
        h.releaseTalkKey()
    }
    private func systemPrompt(_ r: URLRequest) throws -> String {
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(r.httpBody)) as? [String: Any])
        let messages = try XCTUnwrap(body["messages"] as? [[String: String]])
        return try XCTUnwrap(messages.first?["content"])
    }
    private final class Stub: GatewayHTTPTransport {
        var requests: [URLRequest] = []
        let text: String?
        init(text: String?) { self.text = text }
        func send(_ request: URLRequest, completion: @escaping (Result<(Data, Int), Error>) -> Void) {
            requests.append(request)
            if let text { completion(.success((try! JSONSerialization.data(withJSONObject: ["text": text]), 200))) }
            else { completion(.failure(URLError(.timedOut))) }
        }
    }
}
