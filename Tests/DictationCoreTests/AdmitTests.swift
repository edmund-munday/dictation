import XCTest
import DictationCore

final class AdmitTests: XCTestCase {
    func test_R18_speechWhileTalkKeyNotHeldInsertsNothing() throws {
        let h = try TestHarness()
        h.latchOn()
        h.focusEditable()
        h.speakWhileHeld("room talk")
        h.clock.advance(by: .seconds(2))

        XCTAssertTrue(h.session.insertRequests.isEmpty)
        XCTAssertEqual(h.session.micState, .closed)
        XCTAssertFalse(h.session.panel.isVisible)
        XCTAssertEqual(h.fakeCLILog(), "")
    }

    func test_R21_secureFieldsNeverReceiveTextAndShowMenu() throws {
        let h = try TestHarness()
        h.latchOn()
        h.focusEditable(role: .secureTextField, secure: true)
        h.speakAndWait("password123")

        XCTAssertEqual(h.session.menuText, MenuText.secure)
        XCTAssertTrue(h.session.insertRequests.isEmpty)
    }

    func test_R23_callAppFrontmostPausesAndInsertsNothing() throws {
        let h = try TestHarness()
        h.readyListening()
        h.session.ingestFrontmostApp(
            FrontmostApp(timestamp: h.clock.now, bundleID: "us.zoom.xos", callKind: .zoomMeeting)
        )
        h.speakAndWait("meeting chat")

        XCTAssertEqual(h.session.menuText, MenuText.callPaused)
        XCTAssertTrue(h.session.insertRequests.isEmpty)
    }

    func test_R24_otherAppHoldingMicReleasesAndShowsMenu() throws {
        let h = try TestHarness()
        h.readyListening()
        h.session.ingestMicOwner(
            MicOwnerStatus(timestamp: h.clock.now, anotherAppHoldsInput: true)
        )

        XCTAssertEqual(h.session.micState, .released)
        XCTAssertEqual(h.session.menuText, MenuText.otherMic)
    }

    func test_R25_resumeAfterCallOrMicReleaseWithoutInsertingGapSpeech() throws {
        let h = try TestHarness()
        h.readyListening()
        h.session.ingestFrontmostApp(
            FrontmostApp(timestamp: h.clock.now, bundleID: "com.apple.FaceTime", callKind: .faceTime)
        )
        h.speakAndWait("during call")
        h.frontmostNotes()
        h.focusEditable()

        XCTAssertEqual(h.session.micState, .open)
        XCTAssertTrue(h.session.isLatchOn)
        XCTAssertTrue(h.session.insertRequests.isEmpty)

        h.speakAndWait("after call")
        XCTAssertEqual(h.session.insertRequests.count, 1)
    }

    func test_R26_hardwareMutePausesAndInsertsNothing() throws {
        let h = try TestHarness()
        h.readyListening()
        h.session.ingestHardwareMute(HardwareMute(timestamp: h.clock.now, isMuted: true))
        h.speakAndWait("muted")

        XCTAssertEqual(h.session.menuText, MenuText.muted)
        XCTAssertTrue(h.session.insertRequests.isEmpty)
    }

    func test_R27_sixtySecondsNonSpeechIncludingHallucinationInsertsNothing() throws {
        let h = try TestHarness()
        h.readyListening()
        let start = h.clock.now
        h.clock.advance(by: .seconds(60))
        h.session.ingestRecognizerTokens([
            RecognizerToken(
                text: "Thanks for watching",
                start: start,
                end: h.clock.now,
                isSpeech: false
            ),
        ])
        h.advanceSilenceAndHold()

        XCTAssertTrue(h.session.insertRequests.isEmpty)
        XCTAssertTrue(h.session.isLatchOn)
    }

    func test_R28_utteranceOfOnlyMutterWordsInsertsNothing() throws {
        let h = try TestHarness()
        h.readyListening()
        XCTAssertEqual(h.session.menuText, MenuText.ready)
        for mutter in ["uh", "um", "hmm", "ugh", "oh", "ah"] {
            h.speakAndWait(mutter)
        }
        XCTAssertTrue(h.session.insertRequests.isEmpty)
        XCTAssertEqual(h.session.menuText, MenuText.ready)
    }

    func test_R29_sentenceStartingWithMutterIsInserted() throws {
        let h = try TestHarness()
        h.readyListening()
        h.speakAndWait("um ship it monday")

        XCTAssertEqual(h.session.insertRequests.count, 1)
        guard let insert = h.firstInsert() else { return }
        XCTAssertFalse(insert.text.isEmpty)
    }

    func test_R30_ambientEnergyOnBuiltInAndHeadsetFloorIsDropped() throws {
        let h = try TestHarness()
        h.readyListening()

        h.session.ingestEnergy(
            EnergySample(
                timestamp: h.clock.now,
                energyDb: -40,
                noiseFloorDb: -40,
                isBuiltInMic: true
            )
        )
        h.speakAndWait("ambient", isSpeech: true)
        XCTAssertTrue(h.session.insertRequests.isEmpty)

        h.session.ingestEnergy(
            EnergySample(
                timestamp: h.clock.now,
                energyDb: -35,
                noiseFloorDb: -40,
                isBuiltInMic: false
            )
        )
        h.speakAndWait("quiet headset", isSpeech: true)
        XCTAssertTrue(h.session.insertRequests.isEmpty)
        XCTAssertEqual(h.session.menuText, MenuText.ready)
    }

    func test_R33_lockSleepLidCloseClosesMicWipesAndDropsSpeech() throws {
        let h = try TestHarness()
        h.readyListening()
        XCTAssertEqual(h.session.micState, .open)
        XCTAssertTrue(h.session.isLatchOn)

        h.session.ingestSystemEvent(.screenLock)
        h.speakAndWait("while locked")

        XCTAssertEqual(h.session.micState, .closed)
        XCTAssertTrue(h.session.bufferStatus.isWiped)
        XCTAssertTrue(h.session.insertRequests.isEmpty)

        h.session.ingestSystemEvent(.sleep)
        XCTAssertEqual(h.session.micState, .closed)
        h.session.ingestSystemEvent(.lidClose)
        XCTAssertEqual(h.session.micState, .closed)
    }

    func test_R34_unlockWithLatchOnResumesListeningWithEmptyBuffer() throws {
        let h = try TestHarness()
        h.readyListening()
        h.session.ingestSystemEvent(.screenLock)
        h.session.ingestSystemEvent(.screenUnlock)

        XCTAssertTrue(h.session.isLatchOn)
        XCTAssertEqual(h.session.micState, .open)
        XCTAssertTrue(h.session.bufferStatus.isWiped)
        XCTAssertTrue(
            h.session.menuText == MenuText.listening || h.session.menuText == MenuText.ready
        )
    }

    func test_R35_audioRouteChangeMidUtteranceInsertsNothing() throws {
        let h = try TestHarness()
        h.readyListening()
        h.speakOnly("halfway")
        h.session.ingestSystemEvent(.audioRouteChange)
        h.advanceSilenceAndHold()

        XCTAssertTrue(h.session.insertRequests.isEmpty)
        XCTAssertEqual(h.session.micState, .open)
    }
}
