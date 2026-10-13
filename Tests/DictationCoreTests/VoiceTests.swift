import XCTest
import DictationCore

final class VoiceTests: XCTestCase {
    func test_R83_enrollmentCompletingEnablesSpeakerFiltering() throws {
        let h = try TestHarness()
        XCTAssertTrue(h.session.voiceProfile.enrollmentAvailable)
        h.session.completeVoiceEnrollment()

        XCTAssertTrue(h.session.voiceProfile.isEnrolled)
        XCTAssertTrue(h.session.voiceProfile.speakerFilteringEnabled)

        h.readyListening()
        h.session.ingestSpeakerScore(SpeakerScore(timestamp: h.clock.now, matchScore: 0.05))
        h.speakAndWait("intruder")
        XCTAssertTrue(h.session.insertRequests.isEmpty)
    }

    func test_R84_enrollmentCanBeSkippedAndToolStillWorks() throws {
        let h = try TestHarness()
        h.session.skipVoiceEnrollment()
        XCTAssertTrue(h.session.voiceProfile.enrollmentSkipped)
        XCTAssertFalse(h.session.voiceProfile.speakerFilteringEnabled)

        h.readyListening()
        h.speakAndWait("works without enrollment")
        XCTAssertEqual(h.session.insertRequests.count, 1)
    }

    func test_R85_voiceProfileImprovesFromAcceptedNotCancelledUtterances() throws {
        let h = try TestHarness()
        h.session.completeVoiceEnrollment()
        h.readyListening()
        let versionBefore = h.session.voiceProfile.version
        let acceptedBefore = h.session.voiceProfile.acceptedUtteranceCount

        h.speakAndWait("accepted phrase")
        h.session.reportInsertionSucceeded(for: 0)
        XCTAssertEqual(h.session.voiceProfile.acceptedUtteranceCount, acceptedBefore + 1)
        XCTAssertEqual(h.session.voiceProfile.version, versionBefore + 1)

        h.speakOnly("cancelled phrase")
        h.session.ingestKey(KeyPress(timestamp: h.clock.now, kind: .escape, isDown: true))
        h.advanceSilenceAndHold()
        XCTAssertEqual(h.session.voiceProfile.acceptedUtteranceCount, acceptedBefore + 1)
    }

    func test_R86_voiceDataNeverSentToCLIOnlyPhraseText() throws {
        let h = try TestHarness()
        let cli = try h.installFakeCLI(result: "Hello.", delayMs: 0)
        h.session.completeVoiceEnrollment()
        h.session.configureCLI(path: cli.path, kind: .cursorCLI, enabled: true)
        h.session.confirmCLIConsent()
        h.readyListening()
        h.speakAndWait("hello")

        XCTAssertFalse(h.session.cliInvocations.isEmpty)
        for invocation in h.session.cliInvocations {
            XCTAssertFalse(invocation.containedAudioPayload)
            XCTAssertFalse(invocation.stdinText.isEmpty)
            XCTAssertFalse(invocation.stdinText.contains("voiceprint"))
            XCTAssertFalse(invocation.stdinText.contains("embedding"))
        }
    }

    func test_R87_resetVoiceProfileDeletesAndDisablesFiltering() throws {
        let h = try TestHarness()
        h.session.completeVoiceEnrollment()
        XCTAssertTrue(h.session.voiceProfile.speakerFilteringEnabled)
        h.session.resetVoiceProfile()

        XCTAssertFalse(h.session.voiceProfile.isEnrolled)
        XCTAssertFalse(h.session.voiceProfile.speakerFilteringEnabled)
        XCTAssertEqual(h.session.voiceProfile.version, 0)
    }
}
