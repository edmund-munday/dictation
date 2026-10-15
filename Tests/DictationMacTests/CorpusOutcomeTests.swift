import DictationCore
import DictationMac
import Foundation
import XCTest

final class CorpusOutcomeTests: XCTestCase {
    func test_R281_corpusJSONLinesIncludeGatewayAndLocalCleanupOutcomes() throws {
        let h = try MacHarness()
        let network = CorpusOutcomeTransport()
        h.session.setGatewayCleaner(GatewayCleaner(
            config: GatewayConfig(url: try XCTUnwrap(URL(string: "https://gateway.invalid")), key: "test-only-key"),
            transport: network))
        h.session.setCleanupBackend(.gateway)
        // Use the real coordinator; corpus metadata is available before OS insertion is reported.
        let coordinator = InsertionCoordinator(session: h.session, inserter: AccessibilityBridge())
        let directory = h.directory.appendingPathComponent("corpus", isDirectory: true)
        let logger = CorpusLogger(directory: directory, enabled: true)

        release(h)
        try network.reply(text: "Hello there.") // Identical to local cleanup, but actually used the gateway.
        h.clock.advance(by: .zero)
        logger.poll(session: h.session, coordinator: coordinator)

        h.session.setCleanupBackend(.off)
        release(h)
        h.clock.advance(by: .milliseconds(250))
        logger.poll(session: h.session, coordinator: coordinator)
        logger.poll(session: h.session, coordinator: coordinator)

        XCTAssertEqual(h.session.insertRequests.map(\.text), ["Hello there.", "Hello there."])
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "jsonl" }
        XCTAssertEqual(files.count, 1)
        let file = try XCTUnwrap(files.first)
        let contents = try String(contentsOf: file, encoding: .utf8)
        XCTAssertTrue(contents.hasSuffix("\n"))
        let rows = try contents.split(separator: "\n").map {
            try XCTUnwrap(JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any])
        }
        XCTAssertEqual(rows.count, 2, "Each utterance gets one JSONL line")
        XCTAssertEqual(rows.compactMap { $0["raw"] as? String }, ["um hello there", "um hello there"])
        XCTAssertEqual(rows.compactMap { $0["cleaned"] as? String }, ["Hello there.", "Hello there."])
        XCTAssertEqual(rows.compactMap { $0["backend"] as? String }, ["gateway", "local"])
        XCTAssertEqual(rows.compactMap { $0["cleanupOutcome"] as? String }, ["gateway", "local"])
    }

    private func release(_ h: MacHarness) {
        h.session.ingestFocus(h.field(.textArea))
        h.session.ingestTalkKey(TalkKeyEvent(timestamp: h.clock.now, identity: .command(.left), isDown: true))
        let start = h.clock.now
        h.clock.advance(by: .milliseconds(500))
        h.session.ingestRecognizerTokens([
            RecognizerToken(text: "um hello there", start: start, end: h.clock.now, isFinal: true),
        ])
        h.session.ingestTalkKey(TalkKeyEvent(timestamp: h.clock.now, identity: .command(.left), isDown: false))
    }
}

private final class CorpusOutcomeTransport: GatewayHTTPTransport {
    private var completion: ((Result<(Data, Int), Error>) -> Void)?

    func send(_ request: URLRequest, completion: @escaping (Result<(Data, Int), Error>) -> Void) {
        XCTAssertNil(self.completion, "Only the release request should reach the network")
        self.completion = completion
    }

    func reply(text: String) throws {
        let callback = try XCTUnwrap(completion, "Expected a gateway request at release")
        completion = nil
        callback(.success((try JSONSerialization.data(withJSONObject: ["text": text]), 200)))
    }
}
