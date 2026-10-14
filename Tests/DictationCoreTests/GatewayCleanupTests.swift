import DictationCore
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest

/// G2–G7: exercise the HTTP boundary and observable Session output, without a server.
final class GatewayCleanupTests: XCTestCase {
    func test_G2_postsConfiguredModelPromptAndRawTranscript() throws {
        // Both forms must append the endpoint, preserving a configured base path.
        for base in ["https://gateway.invalid/proxy", "https://gateway.invalid/proxy/"] {
            let transport = StubGatewayHTTPTransport(response: response(text: "Ship it Monday."))
            let config = GatewayConfig(
                url: try XCTUnwrap(URL(string: base)),
                model: "test/custom-model",
                key: "test-only-key",
                timeoutSeconds: 1.25
            )
            let cleaner = GatewayCleaner(config: config, transport: transport)
            let raw = "um ship it Friday actually I mean Monday — say \"comma\"\nthen stop"
            let done = expectation(description: "cleaner completes")
            cleaner.clean(raw) { _ in done.fulfill() }
            wait(for: [done], timeout: 1)

            XCTAssertEqual(transport.requests.count, 1)
            let request = try XCTUnwrap(transport.requests.first)
            XCTAssertEqual(request.url?.absoluteString, "https://gateway.invalid/proxy/v1/chat")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-only-key")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            let body = try XCTUnwrap(
                JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any]
            )
            XCTAssertEqual(body["model"] as? String, config.model)
            XCTAssertGreaterThan(try XCTUnwrap(body["max_output_tokens"] as? Int), 0)
            XCTAssertEqual(body["timeout_ms"] as? Int, 1_250)
            XCTAssertEqual(body["tool_tag"] as? String, "dictation:cleanup")
            let messages = try XCTUnwrap(body["messages"] as? [[String: String]])
            XCTAssertEqual(messages, [
                ["role": "system", "content": DictationCore.CleanupPrompt.text],
                ["role": "user", "content": raw],
            ])
            XCTAssertFalse(DictationCore.CleanupPrompt.text.isEmpty)
        }
    }

    func test_G2_sessionSendsOneRawTranscriptPerRelease() throws {
        let h = try TestHarness()
        let transport = StubGatewayHTTPTransport(response: response(text: "Cleaned text."))
        configureGateway(h, transport: transport)
        h.readyListening()

        for raw in ["um first utterance", "uh second utterance"] {
            h.pressTalkKey()
            h.speakWhileHeld(raw)
            let countBeforeRelease = transport.requests.count
            h.releaseTalkKey()
            h.clock.advance(by: .milliseconds(250))
            XCTAssertEqual(transport.requests.count, countBeforeRelease + 1)
            let request = try XCTUnwrap(transport.requests.last)
            let body = try XCTUnwrap(
                JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any]
            )
            let messages = try XCTUnwrap(body["messages"] as? [[String: String]])
            XCTAssertEqual(messages.filter { $0["role"] == "user" }, [["role": "user", "content": raw]])
        }
        XCTAssertEqual(transport.requests.count, 2)
        XCTAssertEqual(h.session.insertRequests.count, 2)
    }

    func test_G3_cleanerTrimsSurroundingWhitespaceAndNewlines() throws {
        let transport = StubGatewayHTTPTransport(response: response(text: " \tShip it Monday.\r\n\n"))
        let cleaner = GatewayCleaner(config: config(), transport: transport)
        let done = expectation(description: "trimmed response")
        cleaner.clean("ship it friday actually i mean monday") { text in
            XCTAssertEqual(text, "Ship it Monday.")
            done.fulfill()
        }
        wait(for: [done], timeout: 1)
    }

    func test_G3_successInsertsGatewayTextWithoutReturn() throws {
        let h = try TestHarness()
        // Distinct punctuation proves this is the gateway result, rather than local fallback.
        let transport = StubGatewayHTTPTransport(response: response(text: " \tShip it Monday!\r\n\n"))
        configureGateway(h, transport: transport)
        release(h, raw: "ship it friday actually i mean monday")
        h.clock.advance(by: .milliseconds(250))

        XCTAssertEqual(h.session.insertRequests.count, 1)
        let insert = try XCTUnwrap(h.session.insertRequests.first)
        XCTAssertEqual(insert.text, "Ship it Monday!")
        XCTAssertEqual(insert.target, h.fieldIdentity)
        XCTAssertFalse(insert.replacesSelection)
        XCTAssertTrue(h.session.emittedKeyEvents.isEmpty)
    }

    func test_G3_gatewayUsesSameResultAcceptanceAsCLI() throws {
        let cases: [(result: String, inserted: String)] = [
            ("  \"Different wording.\"  ", "Different wording."),
            ("Sure, different wording.", "Hello there."),
            ("Here is the cleaned text: Different wording.", "Hello there."),
            (String(repeating: "word ", count: 80), "Hello there."),
        ]
        for item in cases {
            let h = try TestHarness()
            let transport = StubGatewayHTTPTransport(response: response(text: item.result))
            configureGateway(h, transport: transport)
            release(h, raw: "um hello there")
            h.clock.advance(by: .milliseconds(250))
            XCTAssertEqual(h.session.insertRequests.map(\.text), [item.inserted], item.result)
        }
    }

    func test_G3_insertionFailureOffersCopyForGatewayResult() throws {
        let h = try TestHarness()
        let transport = StubGatewayHTTPTransport(response: response(text: "Gateway wording."))
        configureGateway(h, transport: transport)
        release(h)
        h.clock.advance(by: .milliseconds(250))
        XCTAssertEqual(h.session.insertRequests.map(\.text), ["Gateway wording."])

        h.session.reportInsertionFailed(for: 0)

        XCTAssertEqual(h.session.panel.text, MenuText.insertFailed)
        XCTAssertEqual(h.session.panel.buttons.map(\.title), ["Copy"])
        XCTAssertEqual(h.session.overlay.buttons.map(\.title), ["Copy"])
        XCTAssertTrue(h.session.emittedKeyEvents.isEmpty)
    }

    func test_G3_gatewayKeepsTheFieldCapturedAtKeyDown() throws {
        let h = try TestHarness()
        let transport = StubGatewayHTTPTransport()
        configureGateway(h, transport: transport)
        h.readyListening()
        h.pressTalkKey()
        h.focusEditable(identity: FocusIdentity(pid: 42, elementID: "other-field"))
        h.speakWhileHeld("um hello there")
        h.releaseTalkKey()
        try transport.respond(with: response(text: "Gateway wording."))
        h.clock.advance(by: .milliseconds(250))

        XCTAssertEqual(h.session.insertRequests.count, 1)
        XCTAssertEqual(h.session.insertRequests.first?.target, h.fieldIdentity)
        XCTAssertEqual(h.session.insertRequests.first?.text, "Gateway wording.")
    }

    func test_G4_neverRespondingTransportFallsBackAfterThreeSecondsAndIgnoresLateReply() throws {
        let h = try TestHarness()
        let transport = StubGatewayHTTPTransport()
        configureGateway(h, transport: transport)
        release(h)
        XCTAssertEqual(transport.requests.count, 1)

        h.clock.advance(by: .milliseconds(2_900))
        XCTAssertTrue(h.session.insertRequests.isEmpty)
        h.clock.advance(by: .milliseconds(200))
        XCTAssertEqual(h.session.insertRequests.map(\.text), ["Hello there."])

        try transport.respond(with: response(text: "Late gateway wording."))
        h.clock.advance(by: .seconds(5))
        XCTAssertEqual(h.session.insertRequests.map(\.text), ["Hello there."])
        XCTAssertTrue(h.session.emittedKeyEvents.isEmpty)
    }

    func test_G4_deadlineStartsAtReleaseRatherThanAtKeyDown() throws {
        let h = try TestHarness()
        let transport = StubGatewayHTTPTransport()
        configureGateway(h, transport: transport)
        h.readyListening()
        h.pressTalkKey()
        h.speakWhileHeld("um hello there", speechDuration: .seconds(5))
        XCTAssertTrue(transport.requests.isEmpty)
        h.releaseTalkKey()

        h.clock.advance(by: .milliseconds(2_500))
        XCTAssertTrue(h.session.insertRequests.isEmpty)
        try transport.respond(with: response(text: "Gateway wording."))
        h.clock.advance(by: .milliseconds(250))
        XCTAssertEqual(h.session.insertRequests.map(\.text), ["Gateway wording."])
        h.clock.advance(by: .seconds(1))
        XCTAssertEqual(h.session.insertRequests.map(\.text), ["Gateway wording."])
    }

    func test_G4_lateReplyCannotCompleteTheNextUtterance() throws {
        let h = try TestHarness()
        let transport = StubGatewayHTTPTransport()
        configureGateway(h, transport: transport)
        release(h)
        h.clock.advance(by: .milliseconds(3_100))
        XCTAssertEqual(h.session.insertRequests.map(\.text), ["Hello there."])

        h.pressTalkKey()
        h.speakWhileHeld("second utterance")
        h.releaseTalkKey()
        XCTAssertEqual(transport.requests.count, 2)
        try transport.respond(to: 0, with: response(text: "Stale first result."))
        h.clock.advance(by: .milliseconds(250))
        XCTAssertEqual(h.session.insertRequests.map(\.text), ["Hello there."])
        try transport.respond(to: 1, with: response(text: "Second cleaned utterance."))
        h.clock.advance(by: .milliseconds(250))
        XCTAssertEqual(h.session.insertRequests.map(\.text), ["Hello there.", "Second cleaned utterance."])
    }

    func test_G5_nonSuccessHTTPStatusesUseLocalCleanupEvenWithTextInBody() throws {
        for status in [302, 400, 401, 429, 500] {
            try assertFailureUsesLocal(response(text: "Do not insert this.", status: status), label: "HTTP \(status)")
        }
    }

    func test_G5_transportErrorUsesLocalCleanup() throws {
        try assertFailureUsesLocal(.failure(URLError(.notConnectedToInternet)), label: "transport error")
    }

    func test_G5_missingEmptyOrUndecodableTextUsesLocalCleanup() throws {
        for body in [
            #"{"message":"no text"}"#,
            #"{"text":""}"#,
            #"{"text":" \t\r\n "}"#,
            #"{"text":null}"#,
            #"{"text":42}"#,
            #"["not an object"]"#,
            #"{"text":"truncated"#,
            "not JSON",
            "",
        ] {
            try assertFailureUsesLocal(.success((Data(body.utf8), 200)), label: body)
        }
    }

    func test_G5_gatewayBackendWithoutCleanerUsesLocalCleanup() throws {
        let h = try TestHarness()
        h.session.setCleanupBackend(.gateway)
        h.session.setGatewayCleaner(nil)
        release(h)
        h.clock.advance(by: .milliseconds(250))
        XCTAssertEqual(h.session.insertRequests.map(\.text), ["Hello there."])
    }

    func test_G5_settingCleanerDoesNotOverrideLocalBackend() throws {
        let h = try TestHarness()
        let transport = StubGatewayHTTPTransport(response: response(text: "Do not insert this."))
        h.session.setGatewayCleaner(GatewayCleaner(config: config(), transport: transport))
        h.session.setCleanupBackend(.localModel)
        release(h)
        h.clock.advance(by: .milliseconds(250))
        XCTAssertTrue(transport.requests.isEmpty)
        XCTAssertEqual(h.session.insertRequests.map(\.text), ["Hello there."])
    }

    func test_G6_loadsMinimalConfigWithDefaultModelAndTimeout() throws {
        let h = try TestHarness()
        let file = h.workingDirectory.appendingPathComponent("gateway.json")
        try Data(#"{"url":"https://gateway.invalid","key":"test-only-key"}"#.utf8).write(to: file)

        let loaded = try XCTUnwrap(GatewayConfig.load(from: file))

        XCTAssertEqual(loaded.url, URL(string: "https://gateway.invalid"))
        XCTAssertEqual(GatewayConfig.defaultModel, "deepseek/deepseek-flash")
        XCTAssertEqual(loaded.model, GatewayConfig.defaultModel)
        XCTAssertEqual(loaded.key, "test-only-key")
        XCTAssertEqual(loaded.timeoutSeconds, 3)
        XCTAssertEqual(loaded, config())
    }

    func test_G6_loadsConfiguredModelAndTimeoutOverrides() throws {
        let h = try TestHarness()
        let file = h.workingDirectory.appendingPathComponent("gateway.json")
        // Each optional field can be omitted independently.
        for item in [
            (#"{"url":"https://gateway.invalid","key":"test-only-key","model":"custom/model"}"#, "custom/model", 3.0),
            (#"{"url":"https://gateway.invalid","key":"test-only-key","timeoutSeconds":1.5}"#, GatewayConfig.defaultModel, 1.5),
            (#"{"url":"https://gateway.invalid","key":"test-only-key","model":"custom/model","timeoutSeconds":1.5}"#, "custom/model", 1.5),
        ] {
            try Data(item.0.utf8).write(to: file)
            let loaded = try XCTUnwrap(GatewayConfig.load(from: file), item.0)
            XCTAssertEqual(loaded.model, item.1)
            XCTAssertEqual(loaded.timeoutSeconds, item.2)
        }
    }

    func test_G6_missingConfigFileIsUnavailableAndSessionUsesLocalCleanup() throws {
        let h = try TestHarness()
        let file = h.workingDirectory.appendingPathComponent("missing-gateway.json")
        let loaded = GatewayConfig.load(from: file)
        XCTAssertNil(loaded)
        h.session.setCleanupBackend(.gateway)
        h.session.setGatewayCleaner(loaded.map { GatewayCleaner(config: $0, transport: StubGatewayHTTPTransport()) })
        release(h)
        h.clock.advance(by: .milliseconds(250))
        XCTAssertEqual(h.session.insertRequests.map(\.text), ["Hello there."])
    }

    func test_G6_missingEmptyKeyOrMalformedConfigIsUnavailableAndUsesLocalCleanup() throws {
        for body in [
            #"{"url":"https://gateway.invalid"}"#,
            #"{"url":"https://gateway.invalid","key":""}"#,
            #"{"url":"https://gateway.invalid","key":null}"#,
            #"{"key":"test-only-key"}"#,
            #"{"url":42,"key":"test-only-key"}"#,
            #"{"url":"https://gateway.invalid","key":"test-only-key","timeoutSeconds":"three"}"#,
            #"{"url":"https://gateway.invalid","key":"test-only-key","model":42}"#,
            "not JSON",
            "",
        ] {
            let h = try TestHarness()
            let file = h.workingDirectory.appendingPathComponent("gateway.json")
            try Data(body.utf8).write(to: file)
            let loaded = GatewayConfig.load(from: file)
            XCTAssertNil(loaded, body)
            h.session.setCleanupBackend(.gateway)
            h.session.setGatewayCleaner(loaded.map { GatewayCleaner(config: $0, transport: StubGatewayHTTPTransport()) })
            release(h)
            h.clock.advance(by: .milliseconds(250))
            XCTAssertEqual(h.session.insertRequests.map(\.text), ["Hello there."], body)
        }
    }

    func test_G7_promptDescribesCleanupAndSelfCorrectionRules() {
        let prompt = DictationCore.CleanupPrompt.text.lowercased()
        // Check required instructions, without fixing the entire prompt's wording or layout.
        for phrase in ["aggressive", "voice", "meaning", "actually i mean", "scratch that", "corrected", "filler", "punctuat", "capital", "comma", "new line", "words", "only", "cleaned text", "facts", "answer"] {
            XCTAssertTrue(prompt.contains(phrase), "Missing prompt instruction: \(phrase)")
        }
    }

    func test_G7_promptForbidsTrailingNewlineAndReturn() {
        let prompt = DictationCore.CleanupPrompt.text.lowercased()
        XCTAssertTrue(prompt.contains("trailing newline"))
        XCTAssertTrue(prompt.contains("return"))
        XCTAssertNotNil(prompt.range(
            of: #"(?:never|do not|don't|no)[^.!?]*(?:trailing newline|return)"#,
            options: .regularExpression
        ))
    }

    private func config() -> GatewayConfig {
        GatewayConfig(url: URL(string: "https://gateway.invalid")!, key: "test-only-key")
    }

    private func response(text: String, status: Int = 200) -> Result<(Data, Int), Error> {
        .success((try! JSONSerialization.data(withJSONObject: ["text": text]), status))
    }

    private func configureGateway(_ h: TestHarness, transport: StubGatewayHTTPTransport) {
        h.session.setGatewayCleaner(GatewayCleaner(config: config(), transport: transport))
        h.session.setCleanupBackend(.gateway)
    }

    private func release(_ h: TestHarness, raw: String = "um hello there") {
        h.readyListening()
        h.pressTalkKey()
        h.speakWhileHeld(raw)
        h.releaseTalkKey()
    }

    private func assertFailureUsesLocal(
        _ response: Result<(Data, Int), Error>,
        label: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        // Check the public cleaner result as well as its user-visible Session fallback.
        let transport = StubGatewayHTTPTransport(response: response)
        let cleaner = GatewayCleaner(config: config(), transport: transport)
        let done = expectation(description: "cleaner rejects \(label)")
        cleaner.clean("um hello there") { text in
            XCTAssertNil(text, label, file: file, line: line)
            done.fulfill()
        }
        wait(for: [done], timeout: 1)

        let h = try TestHarness()
        configureGateway(h, transport: StubGatewayHTTPTransport(response: response))
        release(h)
        h.clock.advance(by: .milliseconds(250))
        XCTAssertEqual(h.session.insertRequests.map(\.text), ["Hello there."], label, file: file, line: line)
    }
}

/// Only the public HTTP boundary is substituted. Nil response stays pending until
/// the test delivers a reply; it never opens a socket or uses wall-clock delays.
private final class StubGatewayHTTPTransport: GatewayHTTPTransport {
    private(set) var requests: [URLRequest] = []
    private let response: Result<(Data, Int), Error>?
    private var completions: [((Result<(Data, Int), Error>) -> Void)?] = []

    init(response: Result<(Data, Int), Error>? = nil) {
        self.response = response
    }

    func send(_ request: URLRequest, completion: @escaping (Result<(Data, Int), Error>) -> Void) {
        requests.append(request)
        completions.append(response == nil ? completion : nil)
        if let response { completion(response) }
    }

    func respond(to index: Int = 0, with result: Result<(Data, Int), Error>) throws {
        XCTAssertTrue(completions.indices.contains(index), "No HTTP request at index \(index)")
        guard completions.indices.contains(index) else { return }
        let completion = try XCTUnwrap(completions[index], "Request already answered")
        completions[index] = nil
        completion(result)
    }
}
