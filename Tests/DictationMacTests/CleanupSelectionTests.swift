import DictationCore
import DictationMac
import XCTest

/// M8, M9: pick the fastest working cleanup CLI, wrap it with the fixed prompt, fall back locally.
final class CleanupSelectionTests: XCTestCase {
    private func selector(_ h: MacHarness, timeout: TimeInterval = 3) -> CleanupCLISelector {
        CleanupCLISelector(
            searchDirectories: [h.directory.appendingPathComponent("bin")],
            wrapperDirectory: h.directory.appendingPathComponent("wrappers"),
            probeTimeout: timeout
        )
    }

    func test_M8_noWorkingCLIFallsBackToLocalRules() throws {
        let h = try MacHarness()
        try h.script(named: "grok", body: "exit 1")
        let s = selector(h).select()
        XCTAssertEqual(s.backend, .localModel)
        XCTAssertNil(s.executablePath)
        XCTAssertTrue(s.menuLabel.lowercased().contains("local"))
    }

    func test_M8_skipsFailingAndMissingAndPicksWorkingOne() throws {
        let h = try MacHarness()
        try h.script(named: "grok", body: "exit 3")
        try h.script(named: "cursor-agent", body: "printf 'Hello.'")
        let s = selector(h).select()
        XCTAssertEqual(s.backend, .cursorCLI)
        XCTAssertEqual(s.cliName, "cursor-agent")
        XCTAssertTrue(s.menuLabel.contains("cursor-agent"))
    }

    func test_M8_fastestWorkingCLIWins() throws {
        let h = try MacHarness()
        try h.script(named: "grok", body: "sleep 1.5; printf 'Hello.'")
        try h.script(named: "claude", body: "printf 'Hello.'")
        let s = selector(h).select()
        XCTAssertEqual(s.backend, .claudeCLI)
    }

    func test_M8_cliThatHangsPastTimeoutIsNotChosen() throws {
        let h = try MacHarness()
        try h.script(named: "grok", body: "sleep 30; printf 'late'")
        let start = Date()
        let s = selector(h, timeout: 1).select()
        XCTAssertEqual(s.backend, .localModel)
        XCTAssertLessThan(Date().timeIntervalSince(start), 10)
    }

    func test_M9_wrapperSendsFixedPromptAndTranscriptAndCoreInsertsOutput() throws {
        let h = try MacHarness()
        let log = h.directory.appendingPathComponent("args.log")
        try h.script(named: "claude", body: """
        for a in "$@"; do printf '%s\\n' "$a" >> "\(log.path)"; done
        printf 'Ship it Monday.'
        """)
        let s = selector(h).select()
        let path = try XCTUnwrap(s.executablePath)
        h.session.setCleanupBackend(s.backend, executablePath: path)

        h.session.ingestFocus(h.field())
        h.session.ingestTalkKey(TalkKeyEvent(timestamp: h.clock.now, identity: .command(.left), isDown: true))
        h.clock.advance(by: .milliseconds(500))
        let raw = "ship it friday actually i mean monday"
        h.session.ingestRecognizerTokens([
            RecognizerToken(text: raw, start: .zero, end: h.clock.now, isFinal: true),
        ])
        h.session.ingestTalkKey(TalkKeyEvent(timestamp: h.clock.now, identity: .command(.left), isDown: false))
        h.clock.advance(by: .milliseconds(150))

        XCTAssertEqual(h.session.insertRequests.first?.text, "Ship it Monday.")
        let args = try String(contentsOf: log, encoding: .utf8)
        XCTAssertTrue(args.contains(raw))
        XCTAssertTrue(args.contains(CleanupPrompt.text))
    }

    func test_M9_failingCLIAtRuntimeUsesLocalCleanup() throws {
        let h = try MacHarness()
        let flag = h.directory.appendingPathComponent("broken")
        // Works for the probe, fails afterwards.
        try h.script(named: "grok", body: """
        if [ -f "\(flag.path)" ]; then exit 1; fi
        printf 'ok'
        """)
        let s = selector(h).select()
        XCTAssertEqual(s.backend, .grokCLI)
        FileManager.default.createFile(atPath: flag.path, contents: Data())
        h.session.setCleanupBackend(s.backend, executablePath: s.executablePath)
        h.session.ingestFocus(h.field())
        h.session.ingestTalkKey(TalkKeyEvent(timestamp: h.clock.now, identity: .command(.left), isDown: true))
        h.clock.advance(by: .milliseconds(500))
        h.session.ingestRecognizerTokens([
            RecognizerToken(text: "um hello there", start: .zero, end: h.clock.now, isFinal: true),
        ])
        h.session.ingestTalkKey(TalkKeyEvent(timestamp: h.clock.now, identity: .command(.left), isDown: false))
        h.clock.advance(by: .milliseconds(250))
        XCTAssertEqual(h.session.insertRequests.first?.text, "Hello there.")
    }
}
