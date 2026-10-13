import XCTest
import DictationCore

final class PrivacyTests: XCTestCase {
    func test_R88_noAudioFileEverWritten() throws {
        let h = try TestHarness()
        h.readyListening()
        h.speakAndWait("no files")
        XCTAssertEqual(h.session.insertRequests.count, 1)

        let audioLike = try h.filesUnderWorkingDirectory().filter {
            let ext = $0.pathExtension.lowercased()
            return ["wav", "caf", "m4a", "aac", "pcm", "raw", "flac"].contains(ext)
                || $0.lastPathComponent.lowercased().contains("audio")
        }
        XCTAssertTrue(audioLike.isEmpty)
        XCTAssertTrue(h.session.filesystemEntriesWritten.isEmpty)
        XCTAssertTrue(h.session.bufferStatus.heldInMemoryOnly)
    }

    func test_R89_noTranscriptLogWritten() throws {
        let h = try TestHarness()
        h.readyListening()
        h.speakAndWait("no transcript log")
        XCTAssertEqual(h.session.insertRequests.count, 1)

        let transcriptLike = try h.filesUnderWorkingDirectory().filter {
            let name = $0.lastPathComponent.lowercased()
            return name.contains("transcript") || name.contains("log") || $0.pathExtension == "txt"
        }
        XCTAssertTrue(transcriptLike.isEmpty)
        XCTAssertTrue(h.session.filesystemEntriesWritten.isEmpty)
    }

    func test_R90_audioNeverSentToCLIOnlyPhraseText() throws {
        let h = try TestHarness()
        let cli = try h.installFakeCLI(result: "Hello there.", delayMs: 0)
        h.session.configureCLI(path: cli.path, kind: .claudeCLI, enabled: true)
        h.session.confirmCLIConsent()
        h.readyListening()
        h.speakAndWait("hello there")

        XCTAssertEqual(h.session.insertRequests.count, 1)
        XCTAssertFalse(h.session.cliInvocations.isEmpty)
        for invocation in h.session.cliInvocations {
            XCTAssertFalse(invocation.containedAudioPayload)
            XCTAssertEqual(invocation.stdinText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, false)
        }
    }

    func test_R92_cliBackendOffStartsNoProcess() throws {
        let h = try TestHarness()
        let cli = try h.installFakeCLI(result: "Nope.", delayMs: 0)
        h.session.configureCLI(path: cli.path, kind: .cursorCLI, enabled: false)
        h.readyListening()
        h.speakAndWait("local only")

        XCTAssertEqual(h.session.insertRequests.count, 1)
        XCTAssertTrue(h.session.cliInvocations.isEmpty)
        XCTAssertEqual(h.fakeCLILog(), "")
        XCTAssertFalse(h.session.settings.cliBackendEnabled)
    }

    func test_R93_secureOrCallTextNeverSentToCLI() throws {
        let h = try TestHarness()
        let cli = try h.installFakeCLI(result: "leak", delayMs: 0)
        h.session.configureCLI(path: cli.path, kind: .cursorCLI, enabled: true)
        h.session.confirmCLIConsent()

        h.latchOn()
        h.focusEditable(role: .secureTextField, secure: true)
        h.speakAndWait("password")
        XCTAssertEqual(h.session.menuText, MenuText.secure)
        XCTAssertTrue(h.session.cliInvocations.isEmpty)

        h.focusEditable()
        h.session.ingestFrontmostApp(
            FrontmostApp(timestamp: h.clock.now, bundleID: "us.zoom.xos", callKind: .zoomMeeting)
        )
        h.speakAndWait("call words")
        XCTAssertEqual(h.session.menuText, MenuText.callPaused)
        XCTAssertTrue(h.session.cliInvocations.isEmpty)
    }

    func test_R94_prerollAtMost1_5sMemoryOnlyWipedOnOffLockSleepSecureCommit() throws {
        let h = try TestHarness()
        h.readyListening()
        h.speakOnly("buffer")
        XCTAssertLessThanOrEqual(h.session.bufferStatus.preRollMilliseconds, 1500)
        XCTAssertTrue(h.session.bufferStatus.heldInMemoryOnly)

        h.latchOff()
        XCTAssertTrue(h.session.bufferStatus.isWiped)

        h.latchOn()
        h.focusEditable()
        h.speakOnly("again")
        h.session.ingestSystemEvent(.screenLock)
        XCTAssertTrue(h.session.bufferStatus.isWiped)

        h.session.ingestSystemEvent(.screenUnlock)
        h.focusEditable()
        h.speakOnly("sleep")
        h.session.ingestSystemEvent(.sleep)
        XCTAssertTrue(h.session.bufferStatus.isWiped)

        h.session.ingestSystemEvent(.wake)
        h.focusEditable()
        h.speakOnly("secure")
        h.focusEditable(role: .secureTextField, secure: true)
        XCTAssertTrue(h.session.bufferStatus.isWiped)

        h.focusEditable()
        h.speakAndWait("commit wipe")
        XCTAssertEqual(h.session.insertRequests.count, 1)
        XCTAssertTrue(h.session.bufferStatus.isWiped)
    }
}
