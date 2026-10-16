import DictationCore
import DictationMac
import Foundation
import XCTest

final class SnipPipelineTests: XCTestCase {
    // PluginRunner inherits the process environment. Keep the override scoped to
    // the real invocation and restore it even when an assertion or unwrap fails.
    private static let environmentLock = NSLock()

    func test_R288_recordedSnipFixturesDescribeOnlyNamedSubjectsThroughRealPipeline() throws {
        let cases: [(String, String?)] = [
            ("snip-1", "the Slack window"),
            ("snip-2", nil),
            ("snip-3", nil),
            ("snip-4", "chart"),
        ]
        for (fixture, subject) in cases {
            let (h, network) = try harness()
            let calls = h.directory.appendingPathComponent("snip-calls.jsonl")
            let snip = try h.script(named: "snip", body: """
            exec python3 - '\(calls.path)' "$@" <<'PY'
            import json
            import sys
            argv = sys.argv[2:]
            with open(sys.argv[1], "a", encoding="utf-8") as calls:
                calls.write(json.dumps(argv) + "\\n")
            print(json.dumps({"ok": True, "path": "/tmp/x.png",
                              "cropped": "--describe" in argv, "reason": None,
                              "fullPath": "/tmp/x.png"}))
            PY
            """)

            try runVoice(try recordedText(fixture), in: h, network: network,
                         snip: snip, subject: subject)

            let lines = try String(contentsOf: calls, encoding: .utf8).split(whereSeparator: \.isNewline)
            XCTAssertEqual(lines.count, 1, "\(fixture): execute fake snip exactly once")
            let argv = try JSONDecoder().decode([String].self, from: Data(try XCTUnwrap(lines.first).utf8))
            let base = ["capture", "--out", "clipboard", "--json"]
            if let subject {
                XCTAssertEqual(argv.map { $0.lowercased() }, base + ["--describe", subject.lowercased()], fixture)
            } else {
                XCTAssertFalse(argv.contains("--describe"), fixture)
                XCTAssertEqual(argv, base, fixture)
            }
        }
    }

    // Mirror the app: Session queues the command on release, PluginRunner runs
    // the installed wrapper with the original transcript, then Session shows notify.
    private func runVoice(_ transcript: String, in h: MacHarness, network: SnipTransport,
                          snip: URL, subject: String?, file: StaticString = #filePath, line: UInt = #line) throws {
        let index = h.session.commandRequests.count
        h.session.ingestFocus(h.field())
        h.session.ingestTalkKey(TalkKeyEvent(timestamp: h.clock.now, identity: .command(.left), isDown: true))
        let start = h.clock.now
        h.clock.advance(by: .milliseconds(600))
        h.session.ingestRecognizerTokens([RecognizerToken(text: transcript, start: start, end: h.clock.now,
            isSpeech: true, confidence: 1, language: "en", isFinal: true)])
        endHold(h)
        XCTAssertEqual(h.session.commandRequests.count, index + 1, "Must run immediately on release", file: file, line: line)
        XCTAssertTrue(network.requests.isEmpty, file: file, line: line)
        XCTAssertTrue(h.session.insertRequests.isEmpty, file: file, line: line)
        let request = try XCTUnwrap(h.session.commandRequests.dropFirst(index).first, file: file, line: line)
        XCTAssertEqual(request.plugin.name, "screenshot", file: file, line: line)
        XCTAssertEqual(request.args["subject"]?.lowercased(), subject?.lowercased(), file: file, line: line)
        let context = ["transcript": request.transcript, "timestamp": ISO8601DateFormatter().string(from: Date())]
        let result = withSnip(snip) {
            PluginRunner.run(request.plugin, args: request.args, context: context)
        }
        XCTAssertFalse(result.timedOut, file: file, line: line)
        XCTAssertEqual(result.exitCode, 0, result.stderr, file: file, line: line)
        let output = try XCTUnwrap(result.output, file: file, line: line)
        h.session.ingestPluginResult(for: index, output: output)
        // The fast path may lowercase the subject; the panel must preserve the
        // actual subject passed to the wrapper, including the notification wording.
        let notification: String
        if subject != nil {
            notification = "Screenshot of \(try XCTUnwrap(request.args["subject"])) copied to clipboard"
        } else {
            notification = "Screenshot copied to clipboard"
        }
        XCTAssertTrue(h.session.panel.isVisible, file: file, line: line)
        XCTAssertEqual(h.session.panel.text, notification, file: file, line: line)
        h.clock.advance(by: .seconds(12))
        XCTAssertTrue(network.requests.isEmpty, "No delayed cleanup request", file: file, line: line)
        XCTAssertTrue(h.session.insertRequests.isEmpty, file: file, line: line)
        XCTAssertTrue(h.session.emittedKeyEvents.isEmpty, file: file, line: line)
        XCTAssertEqual(h.session.commandRequests.count, index + 1, "Execute once", file: file, line: line)
    }

    private func endHold(_ h: MacHarness) {
        h.session.ingestTalkKey(TalkKeyEvent(timestamp: h.clock.now, identity: .command(.left), isDown: false))
    }

    private func harness() throws -> (MacHarness, SnipTransport) {
        let h = try MacHarness()
        let network = SnipTransport()
        h.session.setGatewayCleaner(GatewayCleaner(
            config: GatewayConfig(url: URL(string: "https://gateway.invalid")!, key: "test-only-key"),
            transport: network))
        h.session.setCleanupBackend(.gateway)
        let plugins = h.directory.appendingPathComponent("plugins")
        try FileManager.default.createDirectory(at: plugins.appendingPathComponent("bin"), withIntermediateDirectories: true)
        for relative in ["screenshot.json", "bin/snip-capture.py"] {
            try FileManager.default.copyItem(at: examples.appendingPathComponent(relative), to: plugins.appendingPathComponent(relative))
        }
        let loaded = PluginLoader.load(directory: plugins)
        XCTAssertTrue(loaded.errors.isEmpty, "\(loaded.errors)")
        let plugin = try XCTUnwrap(loaded.plugins.first { $0.name == "screenshot" })
        // Use the shipped delay unchanged: advancing the clock to bypass a
        // confirmation would hide a regression in the immediate fast path.
        XCTAssertEqual(plugin.confirmDelaySeconds, 0)
        XCTAssertEqual(plugin.action.path, "bin/snip-capture.py")
        h.session.setPlugins([plugin])
        return (h, network)
    }

    private func withSnip<T>(_ snip: URL, _ body: () throws -> T) rethrows -> T {
        Self.environmentLock.lock()
        defer { Self.environmentLock.unlock() }
        let previous = getenv("SNIP_BIN").map { String(cString: $0) }
        setenv("SNIP_BIN", snip.path, 1)
        defer {
            if let previous { setenv("SNIP_BIN", previous, 1) }
            else { unsetenv("SNIP_BIN") }
        }
        return try body()
    }

    private var repository: URL {
        URL(fileURLWithPath: #filePath).resolvingSymlinksInPath()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }
    private var examples: URL { repository.appendingPathComponent("examples/plugins") }

    private struct Recording: Decodable { let whisper: String }
    private func recordedText(_ name: String) throws -> String {
        let audio = repository.appendingPathComponent("Tests/Fixtures/audio")
        XCTAssertGreaterThan(try Data(contentsOf: audio.appendingPathComponent(name + ".wav")).count, 44)
        let recordings = try JSONDecoder().decode([String: Recording].self,
            from: Data(contentsOf: audio.appendingPathComponent("snip-whisper.json")))
        return try XCTUnwrap(recordings[name]).whisper
    }

    // Keep GatewayCleaner real while recording any unexpected HTTP request.
    private final class SnipTransport: GatewayHTTPTransport {
        private(set) var requests: [URLRequest] = []
        func send(_ request: URLRequest, completion: @escaping (Result<(Data, Int), Error>) -> Void) {
            requests.append(request)
            completion(.success((Data(#"{"text":"Unexpected gateway request."}"#.utf8), 200)))
        }
    }
}
