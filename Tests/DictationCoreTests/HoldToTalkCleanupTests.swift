import XCTest
import DictationCore

final class HoldToTalkCleanupTests: XCTestCase {
    func test_R111_oneLlmCallPerUtteranceWithRawTranscriptOnStdin() throws {
        let h = try TestHarness()
        let cli = try h.installFakeCLI(result: "First.", name: "once")
        h.session.setCleanupBackend(.cursorCLI, executablePath: cli.path)
        h.latchOn()
        h.focusEditable()

        h.pressTalkKey()
        h.speakWhileHeld("first utterance")
        h.releaseTalkKey()
        h.clock.advance(by: .milliseconds(100))

        h.pressTalkKey()
        h.speakWhileHeld("second utterance")
        h.releaseTalkKey()
        h.clock.advance(by: .milliseconds(100))

        XCTAssertEqual(h.session.cliInvocations.count, 2)
        XCTAssertEqual(h.session.cliInvocations[0].stdinText, "first utterance")
        XCTAssertEqual(h.session.cliInvocations[1].stdinText, "second utterance")
        XCTAssertFalse(h.session.cliInvocations[1].stdinText.contains("first utterance"))
        XCTAssertFalse(h.session.cliInvocations[0].containedAudioPayload)
        let log = h.fakeCLILog(name: "once")
        XCTAssertTrue(log.contains("first utterance"))
        XCTAssertTrue(log.contains("second utterance"))
    }

    func test_R112_llmResultTrimmedOrRejectedForEmptyLengthOrPreamble() throws {
        try assertLLMInsert(result: "  \"Hello there.\"  ", spoken: "hello there", expect: "Hello there.")
        try assertLLMInsert(result: "", spoken: "hello there", expect: "Hello there.")
        try assertLLMInsert(result: "Sure, Hello there.", spoken: "hello there", expect: "Hello there.")
        try assertLLMInsert(result: "Here is the text.", spoken: "hello there", expect: "Hello there.")
        let huge = String(repeating: "word ", count: 80)
        try assertLLMInsert(result: huge, spoken: "hello there", expect: "Hello there.")
    }

    func test_R113_llmTimeoutAfterFourSecondsUsesLocalAndIgnoresLateAnswer() throws {
        let h = try TestHarness()
        let cli = try h.installFakeCLI(result: "FROM LLM", delayMs: 5_000, name: "slow")
        h.session.setCleanupBackend(.cursorCLI, executablePath: cli.path)
        h.latchOn()
        h.focusEditable()
        h.pressTalkKey()
        h.speakWhileHeld("hello there")
        h.releaseTalkKey()
        h.clock.advance(by: .seconds(4))

        XCTAssertEqual(h.session.insertRequests.count, 1)
        XCTAssertEqual(h.session.insertRequests.first?.text, "Hello there.")
        XCTAssertTrue(h.session.menuText.contains(MenuText.llmTimedOut))

        h.clock.advance(by: .seconds(5))
        XCTAssertEqual(h.session.insertRequests.count, 1)
        XCTAssertFalse(h.session.insertRequests.contains { $0.text.contains("FROM LLM") })

        let notes = h.session.menuText.components(separatedBy: MenuText.llmTimedOut).count - 1
        XCTAssertEqual(notes, 1)
    }

    func test_R114_cleanupBackendSettingSelectsProcessOrLocalRules() throws {
        let off = try TestHarness()
        let offCLI = try off.installFakeCLI(result: "SHOULD NOT RUN", name: "off-cli")
        off.session.setCleanupBackend(.off, executablePath: offCLI.path)
        XCTAssertEqual(off.session.settings.cleanupBackend, .off)
        try releaseHello(off)
        XCTAssertEqual(off.session.cliInvocations.count, 0)
        XCTAssertEqual(off.fakeCLILog(name: "off-cli"), "")
        XCTAssertEqual(off.session.insertRequests.first?.text, "Hello.")

        for backend in [CleanupBackend.cursorCLI, .claudeCLI, .grokCLI] {
            let h = try TestHarness()
            let cli = try h.installFakeCLI(result: "From \(backend).", name: "cli-\(backend)")
            h.session.setCleanupBackend(backend, executablePath: cli.path)
            XCTAssertEqual(h.session.settings.cleanupBackend, backend)
            try releaseHello(h, spoken: "hello")
            XCTAssertEqual(h.session.cliInvocations.count, 1)
            XCTAssertEqual(h.session.cliInvocations.first?.executablePath, cli.path)
            XCTAssertEqual(h.session.insertRequests.first?.text, "From \(backend).")
        }

        let local = try TestHarness()
        local.session.setCleanupBackend(.localModel)
        XCTAssertEqual(local.session.settings.cleanupBackend, .localModel)
        try releaseHello(local)
        XCTAssertEqual(local.session.cliInvocations.count, 0)
        XCTAssertEqual(local.session.insertRequests.count, 1)
    }

    func test_R116_callOrSecureHoldInsertsNothingAndShowsPauseMessage() throws {
        let call = try TestHarness()
        let callCLI = try call.installFakeCLI(result: "leak", name: "call-cli")
        call.session.setCleanupBackend(.cursorCLI, executablePath: callCLI.path)
        call.latchOn()
        call.focusEditable()
        call.session.ingestFrontmostApp(
            FrontmostApp(timestamp: call.clock.now, bundleID: "us.zoom.xos", callKind: .zoomMeeting)
        )
        call.pressTalkKey()
        call.speakWhileHeld("during the call")
        call.releaseTalkKey()
        call.clock.advance(by: .milliseconds(200))

        XCTAssertEqual(call.session.panel.text, MenuText.callPaused)
        XCTAssertTrue(call.session.insertRequests.isEmpty)
        XCTAssertEqual(call.session.cliInvocations.count, 0)
        XCTAssertEqual(call.fakeCLILog(name: "call-cli"), "")

        let secure = try TestHarness()
        let secureCLI = try secure.installFakeCLI(result: "leak", name: "secure-cli")
        secure.session.setCleanupBackend(.cursorCLI, executablePath: secureCLI.path)
        secure.latchOn()
        secure.focusEditable(role: .secureTextField, secure: true)
        secure.pressTalkKey()
        secure.speakWhileHeld("password")
        secure.releaseTalkKey()
        secure.clock.advance(by: .milliseconds(200))

        XCTAssertEqual(secure.session.panel.text, MenuText.secure)
        XCTAssertTrue(secure.session.insertRequests.isEmpty)
        XCTAssertEqual(secure.session.cliInvocations.count, 0)
    }

    func test_R118_transcriptAndLlmResultAreNotWrittenByTheTool() throws {
        let h = try TestHarness()
        let raw = "unique transcript phrase"
        let cleaned = "Unique cleaned phrase."
        let cli = try h.installFakeCLI(result: cleaned, name: "disk-cli")
        h.session.setCleanupBackend(.cursorCLI, executablePath: cli.path)
        h.latchOn()
        h.focusEditable()
        h.pressTalkKey()
        h.speakWhileHeld(raw)
        h.releaseTalkKey()
        h.clock.advance(by: .milliseconds(100))

        XCTAssertEqual(h.session.insertRequests.first?.text, cleaned)
        let files = try h.filesUnderWorkingDirectory()
        for url in files where url.lastPathComponent != "disk-cli" && url.lastPathComponent != "disk-cli.log" {
            let body = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            XCTAssertFalse(body.contains(raw), url.lastPathComponent)
            XCTAssertFalse(body.contains(cleaned), url.lastPathComponent)
        }
        let toolWrites = h.session.filesystemEntriesWritten.map(\.lastPathComponent)
        XCTAssertFalse(toolWrites.contains { $0.contains("transcript") })
    }

    private func releaseHello(_ h: TestHarness, spoken: String = "um hello") throws {
        h.latchOn()
        h.focusEditable()
        h.pressTalkKey()
        h.speakWhileHeld(spoken)
        h.releaseTalkKey()
        h.clock.advance(by: .milliseconds(200))
    }

    private func assertLLMInsert(result: String, spoken: String, expect: String) throws {
        let h = try TestHarness()
        let cli = try h.installFakeCLI(result: result, name: "reject-\(UUID().uuidString)")
        h.session.setCleanupBackend(.grokCLI, executablePath: cli.path)
        h.latchOn()
        h.focusEditable()
        h.pressTalkKey()
        h.speakWhileHeld(spoken)
        h.releaseTalkKey()
        h.clock.advance(by: .milliseconds(100))
        XCTAssertEqual(h.session.insertRequests.first?.text, expect)
    }
}
