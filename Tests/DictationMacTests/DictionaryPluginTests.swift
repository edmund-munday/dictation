import DictationCore
import DictationMac
import Foundation
import XCTest

final class DictionaryPluginTests: XCTestCase {
    // PluginRunner inherits its environment. Restore this process-wide override
    // immediately after each real script invocation, including assertion failures.
    private static let environmentLock = NSLock()
    private let preferredPrefix = "Preferred spellings (use exactly when these words are meant): "

    func test_R273_R279_recordedAddFixturesAppendInOrderAndNotifyWithoutGatewayOrInsertion() throws {
        let (h, network) = try harness()
        var expected: [String] = []
        for (fixture, term) in [("dict-1", "Kazey"), ("dict-2", "Tessa"), ("dict-3", "Moss"),
                                ("dict-4", "Grok Bot"), ("dict-6", "Quinn")] {
            try runVoice(try recordedText(fixture), in: h, network: network, notification: "Added: \(term)")
            expected.append(term)
            XCTAssertEqual(try dictionaryLines(h), expected, fixture)
        }
    }

    func test_R273_duplicateVoiceAddsAreCaseInsensitiveAndKeepOneLine() throws {
        let (h, network) = try harness()
        let text = try recordedText("dict-1")
        for _ in 0..<2 {
            try runVoice(text, in: h, network: network, notification: "Added: Kazey")
            XCTAssertEqual(try dictionaryLines(h), ["Kazey"])
        }
        // A pre-existing spelling with different case is still the same term.
        try writeDictionary("kAzEy\n", in: h)
        try runVoice(text, in: h, network: network, notification: "Added: Kazey")
        XCTAssertEqual(try dictionaryLines(h).map { $0.lowercased() }, ["kazey"])
    }

    func test_R272_R273_spellingVariantsReachRealScriptThroughFastPath() throws {
        for (spelled, term) in [
            ("K, A, Z, E, Y", "Kazey"), ("K. A. Z. E. Y.", "Kazey"), ("K A Z E Y", "Kazey"),
            ("capital T-E-S-S-A", "Tessa"), ("M O double S", "Moss"),
            ("capital G-R-O-K space capital B-O-T", "Grok Bot"), ("all caps A P I", "API"),
            ("lowercase S C R I P T", "script"), ("kay ay zed ee why", "Kazey"), ("kazey", "Kazey"),
        ] {
            let (h, network) = try harness()
            try runVoice("Add word " + spelled, in: h, network: network, notification: "Added: \(term)")
            XCTAssertEqual(try dictionaryLines(h), [term], spelled)
        }
    }

    func test_R274_recordedRemoveIsCaseInsensitiveAndPreservesOtherTerms() throws {
        let (h, network) = try harness()
        try writeDictionary("Tessa\nkAzEy\nSnip\n", in: h)
        try runVoice(try recordedText("dict-5"), in: h, network: network, notification: "Removed: Kazey")
        XCTAssertEqual(try dictionaryLines(h), ["Tessa", "Snip"])
    }

    func test_R274_removingAbsentTermNotifiesAndLeavesDictionaryUnchanged() throws {
        let (h, network) = try harness()
        try writeDictionary("Tessa\nSnip\n", in: h)
        let before = try Data(contentsOf: dictionaryURL(h))
        try runVoice(try recordedText("dict-5"), in: h, network: network, notification: "Not in dictionary: Kazey")
        XCTAssertEqual(try Data(contentsOf: dictionaryURL(h)), before)
    }

    func test_R274_unparseableAddAndRemoveNotifyAndLeaveDictionaryUnchanged() throws {
        let (h, network) = try harness()
        try writeDictionary("Kazey\nSnip\n", in: h)
        let before = try Data(contentsOf: dictionaryURL(h))
        for transcript in ["Add word K A banana.", "Remove word K A banana."] {
            try runVoice(transcript, in: h, network: network, notification: "Couldn't spell that word.")
            XCTAssertEqual(try Data(contentsOf: dictionaryURL(h)), before, transcript)
        }
    }

    func test_R275_nextWhisperPromptReadsNewVoiceTermAndRemovalWithoutRestart() throws {
        let (h, network) = try harness()
        let (whisper, seen) = try whisperCLI(h)
        whisper.dictionaryURL = dictionaryURL(h)
        try writeDictionary("Kazey\n", in: h)
        try transcribe(whisper)
        XCTAssertEqual(try prompts(seen), ["Edmund dictating notes and messages: Kazey."])

        // Reuse the same transcriber so a prompt cached at construction fails.
        try runVoice(try recordedText("dict-6"), in: h, network: network, notification: "Added: Quinn")
        try transcribe(whisper)
        XCTAssertEqual(try prompts(seen).last, "Edmund dictating notes and messages: Kazey, Quinn.")
        XCTAssertEqual(whisper.initialPrompt, "Edmund dictating notes and messages: Kazey, Quinn.",
                       "HoldPipeline uses initialPrompt as the vocabulary part of tail prompts")

        try runVoice(try recordedText("dict-5"), in: h, network: network, notification: "Removed: Kazey")
        let segments = whisper.transcribeSegments(samples: samples, sampleRate: 16_000, prompt: nil)
        XCTAssertEqual(segments?.map(\.text), ["Dictation recorded."])
        XCTAssertEqual(try prompts(seen), [
            "Edmund dictating notes and messages: Kazey.",
            "Edmund dictating notes and messages: Kazey, Quinn.",
            "Edmund dictating notes and messages: Quinn.",
        ])
    }

    func test_R275_whisperCLIReceivesNewestTermsWithinSixHundredCharacters() throws {
        let (h, _) = try harness(installPlugin: false)
        let terms = (0..<200).map { String(format: "Term%03d", $0) + String(repeating: "x", count: 33) }
        try writeDictionary(terms.joined(separator: "\n") + "\n", in: h)
        let (whisper, seen) = try whisperCLI(h)
        whisper.dictionaryURL = dictionaryURL(h)
        try transcribe(whisper)
        let prompt = try XCTUnwrap(try prompts(seen).last)
        XCTAssertLessThanOrEqual(prompt.count, 600)
        XCTAssertTrue(prompt.hasPrefix("Edmund dictating notes and messages: "))
        XCTAssertTrue(prompt.hasSuffix(try XCTUnwrap(terms.last) + "."))
        XCTAssertFalse(prompt.contains(terms[0]))
    }

    func test_R275_missingDictionaryKeepsConfiguredWhisperPrompt() throws {
        let (h, _) = try harness(installPlugin: false)
        let (whisper, seen) = try whisperCLI(h)
        whisper.initialPrompt = "My configured vocabulary."
        whisper.dictionaryURL = dictionaryURL(h)
        try transcribe(whisper)
        XCTAssertEqual(try prompts(seen), ["My configured vocabulary."])
    }

    func test_R276_fullGatewayRequestReadsPreferredSpellingsFresh() throws {
        let (h, network) = try harness()
        try runVoice(try recordedText("dict-1"), in: h, network: network, notification: "Added: Kazey")
        release("Ask Kazey about the draft.", in: h)
        XCTAssertEqual(network.requests.count, 1)
        XCTAssertEqual(try preferredLines(network), [preferredPrefix + "Kazey"])
        XCTAssertEqual(h.session.insertRequests.map(\.text), ["Ask Kazey about the draft."])

        try writeDictionary("Quinn\n", in: h)
        release("Ask Quinn tomorrow.", in: h)
        XCTAssertEqual(network.requests.count, 2)
        XCTAssertEqual(try preferredLines(network), [preferredPrefix + "Kazey", preferredPrefix + "Quinn"])
        XCTAssertEqual(h.session.insertRequests.map(\.text), ["Ask Kazey about the draft.", "Ask Quinn tomorrow."])
    }

    func test_R276_backgroundSentenceRequestsIncludePreferredSpellings() throws {
        let (h, network) = try harness(installPlugin: false)
        try writeDictionary("Kazey\nscript\nSnip\n", in: h)
        beginHold(h)
        let text = "Ask Kazey about the draft. Keep the script handy. Then call Snip."
        ingest(text, in: h, final: false)
        XCTAssertTrue(network.requests.isEmpty)
        ingest(text, in: h, final: false)
        XCTAssertEqual(network.requests.count, 2, "Two stable sentences are cleaned while the key is held")
        XCTAssertTrue(h.session.insertRequests.isEmpty)
        XCTAssertEqual(try userMessages(network), ["Ask Kazey about the draft.", "Keep the script handy."])
        XCTAssertEqual(try preferredLines(network), Array(repeating: preferredPrefix + "Kazey, script, Snip", count: 2))
        ingest(text, in: h, final: true)
        endHold(h)
        XCTAssertEqual(network.requests.count, 3)
        XCTAssertEqual(try userMessages(network).last, "Then call Snip.")
        XCTAssertEqual(try preferredLines(network).last, preferredPrefix + "Kazey, script, Snip")
        XCTAssertEqual(h.session.insertRequests.map(\.text), [text])
    }

    func test_R276_missingAndEmptyDictionaryOmitPreferredSpellingsFromGateway() throws {
        let (h, network) = try harness(installPlugin: false)
        release("Please check the draft.", in: h)
        try writeDictionary("", in: h)
        release("Please check the draft.", in: h)
        XCTAssertEqual(network.requests.count, 2)
        XCTAssertEqual(try preferredLines(network), [])
        XCTAssertEqual(h.session.insertRequests.map(\.text), Array(repeating: "Please check the draft.", count: 2))
    }

    func test_R277_migrationUsesBuiltInWhisperVocabularyAndNeverOverwrites() throws {
        let (h, _) = try harness(installPlugin: false)
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: "whisperPrompt")
        defaults.removeObject(forKey: "whisperPrompt")
        defer {
            if let previous { defaults.set(previous, forKey: "whisperPrompt") }
            else { defaults.removeObject(forKey: "whisperPrompt") }
        }
        let (whisper, _) = try whisperCLI(h)
        try UserDictionary.migrateIfNeeded(fileURL: dictionaryURL(h), fromPrompt: whisper.initialPrompt)
        XCTAssertEqual(try dictionaryLines(h), ["note", "notes", "gateway", "Grok", "Grok Bot", "Grok Build",
            "Claude", "Codex", "MacBook", "Origin", "worker", "dictation", "Kazey", "script", "Snip"])
        try writeDictionary("Quinn\nMy preferred spelling\n", in: h)
        let before = try Data(contentsOf: dictionaryURL(h))
        try UserDictionary.migrateIfNeeded(fileURL: dictionaryURL(h), fromPrompt: whisper.initialPrompt)
        XCTAssertEqual(try Data(contentsOf: dictionaryURL(h)), before)
    }

    func test_R279_shippedJSONAndScriptInstallAndRunWithZeroConfirmDelay() throws {
        let (h, network) = try harness()
        let installedDirectory = h.directory.appendingPathComponent("plugins")
        let loaded = PluginLoader.load(directory: installedDirectory)
        XCTAssertTrue(loaded.errors.isEmpty, "\(loaded.errors)")
        let plugin = try XCTUnwrap(loaded.plugins.first { $0.name == "dictionary" })
        XCTAssertEqual(plugin.triggers, ["add word {letters}", "remove word {letters}"])
        XCTAssertEqual(plugin.confirmDelaySeconds, 0)
        XCTAssertEqual(plugin.action.path, "bin/dictionary.py")
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: examples.appendingPathComponent("bin/dictionary.py").path))

        // Exercise the app's actual bundled installer as well as the example files.
        let bundled = h.directory.appendingPathComponent("bundled-plugins")
        try BundledPlugins.install(into: bundled)
        let bundledLoad = PluginLoader.load(directory: bundled)
        XCTAssertTrue(bundledLoad.errors.isEmpty, "\(bundledLoad.errors)")
        let bundledPlugin = try XCTUnwrap(bundledLoad.plugins.first { $0.name == "dictionary" })
        XCTAssertEqual(bundledPlugin.triggers, plugin.triggers)
        XCTAssertEqual(bundledPlugin.confirmDelaySeconds, 0)
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: bundled.appendingPathComponent("bin/dictionary.py").path))
        h.session.setPlugins([bundledPlugin])
        try runVoice(try recordedText("dict-1"), in: h, network: network, notification: "Added: Kazey")
        XCTAssertEqual(try dictionaryLines(h), ["Kazey"])
    }

    // The app consumes Session.commandRequests, passes the original transcript in
    // stdin context, executes PluginRunner, and gives the output back to Session.
    // No invented DICTATION_TRIGGER environment variable is needed by this contract.
    private func runVoice(_ transcript: String, in h: MacHarness, network: DictionaryTransport,
                          notification: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let index = h.session.commandRequests.count
        release(transcript, in: h)
        XCTAssertEqual(h.session.commandRequests.count, index + 1, "Must run immediately on release", file: file, line: line)
        XCTAssertTrue(network.requests.isEmpty, file: file, line: line)
        XCTAssertTrue(h.session.insertRequests.isEmpty, file: file, line: line)
        let request = try XCTUnwrap(h.session.commandRequests.dropFirst(index).first, file: file, line: line)
        let context = ["transcript": request.transcript, "timestamp": ISO8601DateFormatter().string(from: Date())]
        let result = withSupportDirectory(h.directory) {
            PluginRunner.run(request.plugin, args: request.args, context: context)
        }
        XCTAssertFalse(result.timedOut, file: file, line: line)
        XCTAssertEqual(result.exitCode, 0, result.stderr, file: file, line: line)
        let output = try XCTUnwrap(result.output, file: file, line: line)
        h.session.ingestPluginResult(for: index, output: output)
        XCTAssertTrue(h.session.panel.isVisible, file: file, line: line)
        XCTAssertEqual(h.session.panel.text, notification, file: file, line: line)
        h.clock.advance(by: .seconds(12))
        XCTAssertTrue(network.requests.isEmpty, "No delayed cleanup request", file: file, line: line)
        XCTAssertTrue(h.session.insertRequests.isEmpty, file: file, line: line)
        XCTAssertTrue(h.session.emittedKeyEvents.isEmpty, file: file, line: line)
        XCTAssertEqual(h.session.commandRequests.count, index + 1, "Execute once", file: file, line: line)
    }

    private func harness(installPlugin: Bool = true) throws -> (MacHarness, DictionaryTransport) {
        let h = try MacHarness()
        let network = DictionaryTransport()
        let cleaner = GatewayCleaner(config: GatewayConfig(url: URL(string: "https://gateway.invalid")!, key: "test-only-key"),
                                     transport: network)
        let fileURL = dictionaryURL(h)
        cleaner.dictionaryTerms = { UserDictionary(fileURL: fileURL).terms }
        h.session.setGatewayCleaner(cleaner)
        h.session.setCleanupBackend(.gateway)
        if installPlugin {
            let plugins = h.directory.appendingPathComponent("plugins")
            try FileManager.default.createDirectory(at: plugins.appendingPathComponent("bin"), withIntermediateDirectories: true)
            for relative in ["dictionary.json", "bin/dictionary.py"] {
                try FileManager.default.copyItem(at: examples.appendingPathComponent(relative), to: plugins.appendingPathComponent(relative))
            }
            let loaded = PluginLoader.load(directory: plugins)
            XCTAssertTrue(loaded.errors.isEmpty, "\(loaded.errors)")
            h.session.setPlugins([try XCTUnwrap(loaded.plugins.first { $0.name == "dictionary" })])
        }
        return (h, network)
    }

    private func beginHold(_ h: MacHarness) {
        h.session.ingestFocus(h.field())
        h.session.ingestTalkKey(TalkKeyEvent(timestamp: h.clock.now, identity: .command(.left), isDown: true))
    }

    private func ingest(_ text: String, in h: MacHarness, final: Bool) {
        let start = h.clock.now
        h.clock.advance(by: .milliseconds(600))
        h.session.ingestRecognizerTokens([RecognizerToken(text: text, start: start, end: h.clock.now,
            isSpeech: true, confidence: 1, language: "en", isFinal: final)])
    }

    private func endHold(_ h: MacHarness) {
        h.session.ingestTalkKey(TalkKeyEvent(timestamp: h.clock.now, identity: .command(.left), isDown: false))
    }

    private func release(_ transcript: String, in h: MacHarness) {
        beginHold(h)
        ingest(transcript, in: h, final: true)
        endHold(h)
    }

    private func withSupportDirectory<T>(_ directory: URL, _ body: () throws -> T) rethrows -> T {
        Self.environmentLock.lock()
        defer { Self.environmentLock.unlock() }
        let previous = getenv("DICTATION_SUPPORT_DIR").map { String(cString: $0) }
        setenv("DICTATION_SUPPORT_DIR", directory.path, 1)
        defer {
            if let previous { setenv("DICTATION_SUPPORT_DIR", previous, 1) }
            else { unsetenv("DICTATION_SUPPORT_DIR") }
        }
        return try body()
    }

    private var repository: URL {
        URL(fileURLWithPath: #filePath).resolvingSymlinksInPath()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }
    private var examples: URL { repository.appendingPathComponent("examples/plugins") }
    private func dictionaryURL(_ h: MacHarness) -> URL { h.directory.appendingPathComponent("dictionary.txt") }
    private func writeDictionary(_ text: String, in h: MacHarness) throws {
        try text.write(to: dictionaryURL(h), atomically: true, encoding: .utf8)
    }
    private func dictionaryLines(_ h: MacHarness) throws -> [String] {
        try String(contentsOf: dictionaryURL(h), encoding: .utf8).split(whereSeparator: \.isNewline).map(String.init)
    }

    private struct Recording: Decodable { let whisper: String }
    private func recordedText(_ name: String) throws -> String {
        let audio = repository.appendingPathComponent("Tests/Fixtures/audio")
        XCTAssertGreaterThan(try Data(contentsOf: audio.appendingPathComponent(name + ".wav")).count, 44)
        let recordings = try JSONDecoder().decode([String: Recording].self,
            from: Data(contentsOf: audio.appendingPathComponent("dict-whisper.json")))
        return try XCTUnwrap(recordings[name]).whisper
    }

    private var samples: [Float] { [Float](repeating: 0.1, count: 8_000) }
    private func transcribe(_ whisper: WhisperTranscriber) throws {
        XCTAssertEqual(try XCTUnwrap(whisper.transcribe(samples: samples, sampleRate: 16_000)), "Dictation recorded.")
    }
    private func whisperCLI(_ h: MacHarness) throws -> (WhisperTranscriber, URL) {
        let seen = h.directory.appendingPathComponent("whisper-prompts.txt")
        let fake = try h.script(named: "whisper-cli", body: """
        while [ $# -gt 0 ]; do
          if [ "$1" = "--prompt" ]; then
            shift
            printf '%s\\n' "$1" >> '\(seen.path)'
          fi
          shift
        done
        printf '%s\\n' '[00:00:00.000 --> 00:00:00.500] Dictation recorded.'
        """)
        let model = try h.script(named: "model.bin", body: "")
        return (WhisperTranscriber(executable: fake, model: model,
            scratchDirectory: h.directory.appendingPathComponent("scratch")), seen)
    }
    private func prompts(_ url: URL) throws -> [String] {
        try String(contentsOf: url, encoding: .utf8).split(whereSeparator: \.isNewline).map(String.init)
    }

    private func preferredLines(_ network: DictionaryTransport) throws -> [String] {
        try network.requests.flatMap { request in
            try messages(request).filter { $0["role"] == "system" }.flatMap {
                ($0["content"] ?? "").split(whereSeparator: \.isNewline).map(String.init)
                    .filter { $0.hasPrefix(preferredPrefix) }
            }
        }
    }
    private func userMessages(_ network: DictionaryTransport) throws -> [String] {
        try network.requests.map { request in
            try XCTUnwrap(try messages(request).first { $0["role"] == "user" }?["content"])
        }
    }
    private func messages(_ request: URLRequest) throws -> [[String: String]] {
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(request.httpBody)) as? [String: Any])
        return try XCTUnwrap(body["messages"] as? [[String: String]])
    }

    // Only the network boundary is scripted; real GatewayCleaner request
    // construction, Session routing, and PluginRunner execution remain in use.
    private final class DictionaryTransport: GatewayHTTPTransport {
        private(set) var requests: [URLRequest] = []
        func send(_ request: URLRequest, completion: @escaping (Result<(Data, Int), Error>) -> Void) {
            requests.append(request)
            do {
                let body = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any]
                let messages = body?["messages"] as? [[String: String]]
                let raw = messages?.first { $0["role"] == "user" }?["content"] ?? "Unexpected gateway request."
                completion(.success((try JSONSerialization.data(withJSONObject: ["text": raw]), 200)))
            } catch {
                completion(.failure(error))
            }
        }
    }
}
