import DictationCore
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest

/// R308-R309: `"api": "openai"` in gateway.json points cleanup at a local model server
/// (Ollama, llama.cpp) using the standard chat-completions format; configs without it
/// keep the gateway format unchanged.
final class LocalCleanupTests: XCTestCase {
    func test_R308_openAIConfigPostsChatCompletionsWithoutKey() throws {
        let json = #"{"url": "http://127.0.0.1:11434", "model": "qwen2.5:3b", "api": "openai"}"#
        let config = try JSONDecoder().decode(GatewayConfig.self, from: Data(json.utf8))
        XCTAssertEqual(config.api, .openai)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("local-\(UUID().uuidString).json")
        try Data(json.utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        XCTAssertEqual(GatewayConfig.load(from: file), config, "a local config needs no key")

        let transport = Stub(body: ["choices": [["message": ["role": "assistant", "content": "Ship it Monday.\n"]]]])
        let cleaner = GatewayCleaner(config: config, transport: transport)
        var result: String?
        let done = expectation(description: "cleaner completes")
        cleaner.clean("um ship it friday actually i mean monday") { result = $0; done.fulfill() }
        wait(for: [done], timeout: 1)

        XCTAssertEqual(result, "Ship it Monday.")
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url?.absoluteString, "http://127.0.0.1:11434/v1/chat/completions")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertEqual(body["model"] as? String, "qwen2.5:3b")
        XCTAssertEqual(body["stream"] as? Bool, false)
        XCTAssertGreaterThan(try XCTUnwrap(body["max_tokens"] as? Int), 0)
        XCTAssertNil(body["tool_tag"])
        let messages = try XCTUnwrap(body["messages"] as? [[String: String]])
        XCTAssertEqual(messages.first?["role"], "system")
        XCTAssertEqual(messages.last?["content"], "um ship it friday actually i mean monday")
    }

    func test_R308_openAIReplyWithoutChoicesFallsBack() {
        let config = GatewayConfig(url: URL(string: "http://127.0.0.1:11434")!, model: "m", key: "", api: .openai)
        let cleaner = GatewayCleaner(config: config, transport: Stub(body: ["text": "gateway-shaped reply"]))
        var result: String? = "unset"
        let done = expectation(description: "cleaner completes")
        cleaner.clean("hello") { result = $0; done.fulfill() }
        wait(for: [done], timeout: 1)
        XCTAssertNil(result)
    }

    func test_R309_configWithoutApiKeepsGatewayFormatAndNeedsKey() throws {
        let gateway = try JSONDecoder().decode(
            GatewayConfig.self, from: Data(#"{"url": "https://gateway.invalid", "key": "k"}"#.utf8))
        XCTAssertEqual(gateway.api, .gateway)

        let transport = Stub(body: ["text": "Hello."])
        let done = expectation(description: "cleaner completes")
        GatewayCleaner(config: gateway, transport: transport).clean("hello") { _ in done.fulfill() }
        wait(for: [done], timeout: 1)
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://gateway.invalid/v1/chat")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer k")

        let keyless = FileManager.default.temporaryDirectory.appendingPathComponent("gw-\(UUID().uuidString).json")
        try Data(#"{"url": "https://gateway.invalid"}"#.utf8).write(to: keyless)
        defer { try? FileManager.default.removeItem(at: keyless) }
        XCTAssertNil(GatewayConfig.load(from: keyless), "the gateway still requires a key")
    }
}

private final class Stub: GatewayHTTPTransport {
    private(set) var requests: [URLRequest] = []
    private let body: [String: Any]

    init(body: [String: Any]) { self.body = body }

    func send(_ request: URLRequest, completion: @escaping (Result<(Data, Int), Error>) -> Void) {
        requests.append(request)
        completion(.success((try! JSONSerialization.data(withJSONObject: body), 200)))
    }
}
