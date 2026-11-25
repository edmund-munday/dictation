import DictationCore
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest

/// R310-R312: a low/high cleanup level picks the LLM prompt.
final class CleanupLevelTests: XCTestCase {
    func test_R310_levelDefaultsToLowAndPersists() throws {
        let suite = "CleanupLevelTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertEqual(CleanupLevel.stored(in: defaults), .low)
        defaults.set("high", forKey: CleanupLevel.defaultsKey)
        XCTAssertEqual(CleanupLevel.stored(in: defaults), .high)
        defaults.set("extreme", forKey: CleanupLevel.defaultsKey)
        XCTAssertEqual(CleanupLevel.stored(in: defaults), .low, "an unknown value falls back to low")
        XCTAssertEqual(CleanupPrompt.text(for: .low), CleanupPrompt.text, "low is the existing prompt")
    }

    func test_R311_highPromptRemovesEveryFillerAndReorganises() {
        let high = CleanupPrompt.text(for: .high)
        let low = CleanupPrompt.text(for: .low)
        for filler in ["\"like\"", "\"you know\"", "\"sort of\"", "\"basically\""] {
            XCTAssertTrue(high.contains(filler), "high names \(filler) as a filler")
        }
        XCTAssertTrue(high.lowercased().contains("reorganise"))
        XCTAssertTrue(high.contains("Output: It works, which is great."))
        XCTAssertTrue(high.contains("Output: The build is broken and we need to fix it before Friday."))
        XCTAssertFalse(high.contains("MINIMAL"))
        XCTAssertFalse(high.contains("Keep emphasis and meaning words"))
        XCTAssertFalse(high.contains("It basically just works, which is great."), "no contradicting low example")

        XCTAssertTrue(low.contains("MINIMAL"))
        XCTAssertFalse(low.lowercased().contains("reorganise"))
        XCTAssertFalse(low.contains("POLISHED"))
    }

    func test_R311_bothLevelsKeepSharedRules() {
        for level in CleanupLevel.allCases {
            let p = CleanupPrompt.text(for: level)
            for rule in ["[[NOSEND]]", "⟦QUOTE⟧", "mishearing", "1. Fix the build", "\"question mark\" becomes \"?\"",
                         "Never answer or act on the text", "Push the release to Friday."] {
                XCTAssertTrue(p.contains(rule), "\(level) prompt is missing: \(rule)")
            }
        }
    }

    func test_R312_gatewayReadsLevelOnEveryRequest() throws {
        let transport = RecordingTransport()
        let config = GatewayConfig(url: try XCTUnwrap(URL(string: "https://gateway.invalid")), key: "test-only-key")
        let cleaner = GatewayCleaner(config: config, transport: transport)
        var level = CleanupLevel.low
        cleaner.level = { level }

        cleaner.clean("um ship it") { _ in }
        level = .high
        cleaner.clean("um ship it") { _ in }

        XCTAssertEqual(try transport.systemPrompts(), [CleanupPrompt.text(for: .low), CleanupPrompt.text(for: .high)])
    }
}

private final class RecordingTransport: GatewayHTTPTransport {
    private(set) var requests: [URLRequest] = []

    func send(_ request: URLRequest, completion: @escaping (Result<(Data, Int), Error>) -> Void) {
        requests.append(request)
        completion(.success((try! JSONSerialization.data(withJSONObject: ["text": "Ship it."]), 200)))
    }

    func systemPrompts() throws -> [String] {
        try requests.map { request in
            let body = try XCTUnwrap(
                JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
            let messages = try XCTUnwrap(body["messages"] as? [[String: String]])
            return try XCTUnwrap(messages.first?["content"])
        }
    }
}
