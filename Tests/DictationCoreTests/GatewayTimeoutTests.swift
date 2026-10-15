import DictationCore
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest

/// R280–R282: real Session input and cleanup; only the HTTP boundary is scripted.
final class GatewayTimeoutTests: XCTestCase {
    func test_R280_initializerDefaultsToFiveSeconds() throws {
        XCTAssertEqual(try defaultConfig().timeoutSeconds, 5)
    }

    func test_R280_decodingWithoutTimeoutDefaultsToFiveSeconds() throws {
        let config = try JSONDecoder().decode(GatewayConfig.self, from: Data(
            #"{"url":"https://gateway.invalid","key":"test-only-key"}"#.utf8))

        XCTAssertEqual(config.timeoutSeconds, 5)
    }

    func test_R280_explicitThreeSecondConfigControlsRequestAndReleaseDeadline() throws {
        let config = try JSONDecoder().decode(GatewayConfig.self, from: Data(
            #"{"url":"https://gateway.invalid","key":"test-only-key","timeoutSeconds":3}"#.utf8))
        XCTAssertEqual(config.timeoutSeconds, 3)
        let (h, network) = try gateway(config: config)
        release(h)
        try assertRequestTimeout(network, seconds: 3)

        h.clock.advance(by: .milliseconds(2_999))
        XCTAssertTrue(h.session.insertRequests.isEmpty)
        h.clock.advance(by: .milliseconds(1))

        try assertCompleted(h, text: "Hello there.", backend: "local", outcome: "timeout")
    }

    func test_R280_defaultConfigUsesReplyArrivingFourSecondsAfterRelease() throws {
        let (h, network) = try gateway()
        release(h)
        try assertRequestTimeout(network, seconds: 5)

        h.clock.advance(by: .seconds(3))
        XCTAssertTrue(h.session.insertRequests.isEmpty, "The old 3 s deadline must not insert local text")
        XCTAssertTrue(h.session.utteranceRecords.isEmpty)
        h.clock.advance(by: .seconds(1))
        try network.reply(text: "Hello there!", to: 0)
        h.clock.advance(by: .zero)

        try assertCompleted(h, text: "Hello there!", backend: "gateway", outcome: "gateway")
    }

    func test_R280_defaultConfigInsertsLocalTextAtFiveSecondsAndIgnoresFivePointFiveSecondReply() throws {
        let (h, network) = try gateway()
        release(h)

        h.clock.advance(by: .milliseconds(4_999))
        XCTAssertTrue(h.session.insertRequests.isEmpty)
        XCTAssertTrue(h.session.utteranceRecords.isEmpty)
        h.clock.advance(by: .milliseconds(1))
        try assertCompleted(h, text: "Hello there.", backend: "local", outcome: "timeout")
        XCTAssertEqual(h.session.utteranceRecords.first?.latencyMs, 5_000)
        let recordsAtDeadline = h.session.utteranceRecords

        h.clock.advance(by: .milliseconds(500))
        try network.reply(text: "Late gateway wording.", to: 0)
        h.clock.advance(by: .zero)
        h.clock.advance(by: .seconds(5))

        XCTAssertEqual(h.session.insertRequests.map(\.text), ["Hello there."])
        XCTAssertEqual(h.session.utteranceRecords, recordsAtDeadline, "Late replies cannot rewrite the outcome")
    }

    func test_R281_identicalTextReplyRecordsGatewayBackendAndOutcome() throws {
        let (h, network) = try gateway()
        release(h)
        h.clock.advance(by: .milliseconds(600))
        // This is also exactly what local rules produce for "um hello there".
        try network.reply(text: "Hello there.", to: 0)
        h.clock.advance(by: .zero)

        try assertCompleted(h, text: "Hello there.", backend: "gateway", outcome: "gateway")
    }

    func test_R281_noReplyRecordsTimeoutAndInsertsLocalText() throws {
        let (h, _) = try gateway()
        release(h)
        h.clock.advance(by: .seconds(5))

        try assertCompleted(h, text: "Hello there.", backend: "local", outcome: "timeout")
    }

    func test_R281_transportFailureRecordsErrorAndInsertsLocalText() throws {
        let (h, network) = try gateway()
        release(h)
        h.clock.advance(by: .milliseconds(200))
        try network.respond(to: 0, with: .failure(URLError(.notConnectedToInternet)))
        h.clock.advance(by: .zero)

        try assertCompleted(h, text: "Hello there.", backend: "local", outcome: "error")
    }

    func test_R281_HTTP503RecordsErrorAndInsertsLocalText() throws {
        let (h, network) = try gateway()
        release(h)
        h.clock.advance(by: .milliseconds(200))
        try network.respond(to: 0, with: .success((Data(#"{"error":"Service is too busy"}"#.utf8), 503)))
        h.clock.advance(by: .zero)

        try assertCompleted(h, text: "Hello there.", backend: "local", outcome: "error")
    }

    func test_R281_emptyReplyRecordsErrorAndInsertsLocalText() throws {
        for reply in ["", " \t\r\n "] {
            let (h, network) = try gateway()
            release(h)
            h.clock.advance(by: .milliseconds(200))
            try network.reply(text: reply, to: 0)
            h.clock.advance(by: .zero)

            try assertCompleted(h, text: "Hello there.", backend: "local", outcome: "error")
        }
    }

    func test_R281_preambleReplyRecordsRejectedAndInsertsLocalText() throws {
        let (h, network) = try gateway()
        release(h)
        h.clock.advance(by: .milliseconds(200))
        try network.reply(text: "Here is the cleaned text: Hello there!", to: 0)
        h.clock.advance(by: .zero)

        try assertCompleted(h, text: "Hello there.", backend: "local", outcome: "rejected")
    }

    func test_R281_gatewayBackendOffOrLocalRecordsLocalOutcome() throws {
        for backend in [CleanupBackend.off, .localModel] {
            let (h, network) = try gateway()
            h.session.setCleanupBackend(backend)
            release(h)
            h.clock.advance(by: .milliseconds(250))

            XCTAssertTrue(network.requests.isEmpty)
            try assertCompleted(h, text: "Hello there.", backend: "local", outcome: "local")
        }
    }

    func test_R282_backgroundSentenceReplyAtFourSecondsIsPreservedInReleasedText() throws {
        let (h, network) = try gateway()
        h.readyListening()
        h.pressTalkKey()
        let partial = "Send the draft today. Invite the team tomorrow. Review the budget"
        // Two stable sentences followed by speech activate the existing long-hold path.
        h.speakWhileHeld(partial, speechDuration: .milliseconds(1_600), isFinal: false)
        h.speakWhileHeld(partial, speechDuration: .milliseconds(1_600), isFinal: false)
        XCTAssertEqual(network.requests.count, 2)
        try assertRequestTimeout(network, at: 0, seconds: 5)
        try assertRequestTimeout(network, at: 1, seconds: 5)
        try network.reply(text: "Invite the team tomorrow!", to: 1)
        h.clock.advance(by: .zero)

        h.clock.advance(by: .seconds(4))
        try network.reply(text: "Send the draft today!", to: 0)
        h.clock.advance(by: .zero)
        XCTAssertEqual(h.session.panel.text,
                       "Send the draft today! Invite the team tomorrow! Review the budget")
        XCTAssertTrue(h.session.insertRequests.isEmpty)

        h.speakWhileHeld(partial + ".", speechDuration: .zero)
        h.releaseTalkKey()
        XCTAssertEqual(network.requests.count, 3)
        try network.reply(text: "Review the budget!", to: 2)
        h.clock.advance(by: .zero)

        try assertCompleted(h,
                            text: "Send the draft today! Invite the team tomorrow! Review the budget!",
                            backend: "gateway", outcome: "gateway")
    }

    private func defaultConfig() throws -> GatewayConfig {
        GatewayConfig(url: try XCTUnwrap(URL(string: "https://gateway.invalid")), key: "test-only-key")
    }

    private func gateway(config: GatewayConfig? = nil) throws -> (TestHarness, TimeoutGatewayTransport) {
        let h = try TestHarness()
        let network = TimeoutGatewayTransport()
        h.session.setGatewayCleaner(GatewayCleaner(config: try config ?? defaultConfig(), transport: network))
        h.session.setCleanupBackend(.gateway)
        return (h, network)
    }

    private func release(_ h: TestHarness) {
        h.readyListening()
        h.pressTalkKey()
        h.speakWhileHeld("um hello there")
        h.releaseTalkKey()
    }

    private func assertCompleted(
        _ h: TestHarness, text: String, backend: String, outcome: String,
        file: StaticString = #filePath, line: UInt = #line
    ) throws {
        XCTAssertEqual(h.session.insertRequests.map(\.text), [text], file: file, line: line)
        XCTAssertEqual(h.session.insertRequests.first?.target, h.fieldIdentity, file: file, line: line)
        XCTAssertEqual(h.session.utteranceRecords.count, 1, file: file, line: line)
        let record = try XCTUnwrap(h.session.utteranceRecords.first, file: file, line: line)
        XCTAssertEqual(record.cleaned, text, file: file, line: line)
        XCTAssertEqual(record.backend, backend, file: file, line: line)
        XCTAssertEqual(record.cleanupOutcome, outcome, file: file, line: line)
        XCTAssertEqual(record.insertIndex, 0, file: file, line: line)
    }

    private func assertRequestTimeout(
        _ network: TimeoutGatewayTransport, at index: Int = 0, seconds: Double,
        file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let request = try XCTUnwrap(network.requests.indices.contains(index) ? network.requests[index] : nil,
                                    file: file, line: line)
        XCTAssertEqual(request.timeoutInterval, seconds, file: file, line: line)
        let data = try XCTUnwrap(request.httpBody, file: file, line: line)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any], file: file, line: line)
        XCTAssertEqual(body["timeout_ms"] as? Int, Int(seconds * 1_000), file: file, line: line)
    }
}

/// Matches the existing held-callback transport pattern. Tests advance FakeClock
/// before delivering a reply, so no sockets, sleeps, or production-module stubs are needed.
private final class TimeoutGatewayTransport: GatewayHTTPTransport {
    private(set) var requests: [URLRequest] = []
    private var completions: [Int: (Result<(Data, Int), Error>) -> Void] = [:]

    func send(_ request: URLRequest, completion: @escaping (Result<(Data, Int), Error>) -> Void) {
        completions[requests.count] = completion
        requests.append(request)
    }

    func reply(text: String, to index: Int) throws {
        let data = try JSONSerialization.data(withJSONObject: ["text": text])
        try respond(to: index, with: .success((data, 200)))
    }

    func respond(to index: Int, with result: Result<(Data, Int), Error>) throws {
        let completion = try XCTUnwrap(completions.removeValue(forKey: index), "No pending HTTP request \(index)")
        completion(result)
    }
}
