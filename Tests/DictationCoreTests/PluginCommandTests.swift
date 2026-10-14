import DictationCore
import Foundation
import XCTest

/// R229-R233: voice-command plugins v1 (no wake word; single gateway call routes; local phrase fallback).
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
        release(h, "take a screenshot of the error dialog")
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
        release(h, "take a screenshot of the error dialog")
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
        h.speakWhileHeld("take a screenshot of the error dialog")
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

    // MARK: helpers
    private func json(_ o: [String: Any]) throws -> String {
        String(data: try JSONSerialization.data(withJSONObject: o), encoding: .utf8)!
    }
    private func commandReply() -> String {
        try! json(["mode": "command", "plugin": "screenshot", "args": ["subject": "the error dialog"],
                   "confidence": 0.93, "text": "Take a screenshot of the error dialog."])
    }
    private func config() -> GatewayConfig { GatewayConfig(url: URL(string: "https://gateway.invalid")!, key: "test-only-key") }
    private func harness(gatewayReply: String?) throws -> TestHarness {
        let h = try TestHarness()
        h.session.setGatewayCleaner(GatewayCleaner(config: config(), transport: Stub(text: gatewayReply)))
        h.session.setCleanupBackend(.gateway)
        h.session.setPlugins(try plugins())
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
