@testable import DictationCore
import Foundation
import XCTest

/// R222: a trailing "don't send" instruction is stripped and the insert is marked not to auto-send.
final class DontSendTests: XCTestCase {
    private func run(_ raw: String, gatewayReply: String? = nil) throws -> InsertRequest {
        let h = try TestHarness()
        if let gatewayReply {
            h.session.setGatewayCleaner(GatewayCleaner(
                config: GatewayConfig(url: URL(string: "https://gateway.invalid")!, key: "test-only-key"),
                transport: DSStub(text: gatewayReply)))
            h.session.setCleanupBackend(.gateway)
        } else {
            h.session.setCleanupBackend(.off)
        }
        h.latchOn()
        h.focusEditable(role: .textArea)
        h.pressTalkKey()
        h.speakWhileHeld(raw)
        h.releaseTalkKey()
        h.clock.advance(by: .milliseconds(250))
        XCTAssertEqual(h.session.insertRequests.count, 1)
        XCTAssertTrue(h.session.emittedKeyEvents.isEmpty)
        return try XCTUnwrap(h.session.insertRequests.first)
    }

    func test_R222_trailingDontSendIsStrippedAndBlocksAutoSend() throws {
        for raw in ["see you at five oh actually don't send this", "see you at five don't send",
                    "see you at five don't send it yet", "see you at five hold off sending",
                    "see you at five no send"] {
            let r = try run(raw)
            XCTAssertFalse(r.autoSendAllowed, raw)
            XCTAssertFalse(r.text.lowercased().contains("send"), "\(raw) -> \(r.text)")
            XCTAssertTrue(r.text.lowercased().hasPrefix("see you at five"), "\(raw) -> \(r.text)")
        }
    }

    func test_R222_dontSendInTheMiddleIsContentAndAllowsAutoSend() throws {
        let r = try run("don't send the invoice until friday")
        XCTAssertTrue(r.autoSendAllowed)
        XCTAssertTrue(r.text.lowercased().contains("don't send the invoice"), r.text)
        XCTAssertTrue(try run("see you at five").autoSendAllowed)
    }

    func test_R222_gatewaySentinelBlocksAutoSendAndIsRemoved() throws {
        let r = try run("see you at five oh wait hold that one back", gatewayReply: "See you at five.[[NOSEND]]")
        XCTAssertFalse(r.autoSendAllowed)
        XCTAssertEqual(r.text, "See you at five.")
    }

    func test_R222_localBackstopStripsInstructionTheGatewayKept() throws {
        let r = try run("see you at five don't send it yet", gatewayReply: "See you at five. Don't send it yet.")
        XCTAssertFalse(r.autoSendAllowed)
        XCTAssertEqual(r.text, "See you at five.")
    }

    func test_R222_gatewayTextWithMidMessageDontSendStillAllowsAutoSend() throws {
        let r = try run("don't send the invoice until friday", gatewayReply: "Don't send the invoice until Friday.")
        XCTAssertTrue(r.autoSendAllowed)
        XCTAssertEqual(r.text, "Don't send the invoice until Friday.")
    }

    func test_R222_promptExplainsTheNoSendMarker() {
        let p = DictationCore.CleanupPrompt.text
        XCTAssertTrue(p.contains("[[NOSEND]]"))
        XCTAssertTrue(p.lowercased().contains("don't send"))
    }
}

private final class DSStub: GatewayHTTPTransport {
    let text: String
    init(text: String) { self.text = text }
    func send(_ request: URLRequest, completion: @escaping (Result<(Data, Int), Error>) -> Void) {
        completion(.success((try! JSONSerialization.data(withJSONObject: ["text": text]), 200)))
    }
}
