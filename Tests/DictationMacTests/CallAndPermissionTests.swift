import DictationCore
import DictationMac
import XCTest

/// M13: holds blocked during calls. M14: permission report and Settings panes.
final class CallAndPermissionTests: XCTestCase {
    func test_M13_knownCallAppsWithMicInUseAreACall() {
        XCTAssertEqual(CallDetector.callKind(forBundleID: "us.zoom.xos"), .zoomMeeting)
        XCTAssertEqual(CallDetector.callKind(forBundleID: "com.apple.FaceTime"), .faceTime)
        XCTAssertEqual(CallDetector.callKind(forBundleID: "com.microsoft.teams2"), .teamsMeeting)
        XCTAssertEqual(CallDetector.callKind(forBundleID: "com.apple.Notes"), CallAppKind.none)
        XCTAssertEqual(
            CallDetector.activeCall(runningBundleIDs: ["com.apple.Notes", "us.zoom.xos"], micInUseElsewhere: true),
            .zoomMeeting)
        XCTAssertEqual(
            CallDetector.activeCall(runningBundleIDs: ["us.zoom.xos"], micInUseElsewhere: false), CallAppKind.none)
        XCTAssertEqual(
            CallDetector.activeCall(runningBundleIDs: ["com.apple.Notes"], micInUseElsewhere: true), CallAppKind.none)
    }

    func test_M13_holdDuringCallIsBlockedWithPauseMessageAndNoMic() throws {
        let h = try MacHarness()
        let audio = CountingAudio()
        let p = HoldPipeline(
            session: h.session, clock: h.clock, audio: audio,
            transcriber: ScriptedTranscriber("hello"),
            focus: FixedFocus { t in
                FocusSnapshot(timestamp: t, role: .textField, identity: FocusIdentity(pid: 1, elementID: "f"))
            })
        h.session.ingestFrontmostApp(FrontmostApp(
            timestamp: h.clock.now, bundleID: "us.zoom.xos",
            callKind: CallDetector.activeCall(runningBundleIDs: ["us.zoom.xos"], micInUseElsewhere: true)))
        p.handle(.talk(TalkKeyEvent(timestamp: h.clock.now, identity: .command(.left), isDown: true)))
        XCTAssertEqual(audio.starts, 0)
        XCTAssertEqual(h.session.panel.text, "On — paused for a call")
        h.clock.advance(by: .milliseconds(600))
        p.handle(.talk(TalkKeyEvent(timestamp: h.clock.now, identity: .command(.left), isDown: false)))
        h.clock.advance(by: .milliseconds(300))
        XCTAssertTrue(h.session.insertRequests.isEmpty)
    }

    func test_M14_reportListsMissingPermissionsWithSettingsPanes() {
        let r = PermissionReport(granted: [.inputMonitoring], needsSpeechRecognition: false)
        XCTAssertEqual(r.missing, [.microphone, .accessibility])
        XCTAssertTrue(r.summary.contains("Microphone"))
        XCTAssertTrue(r.summary.contains("Accessibility"))
        XCTAssertFalse(r.summary.contains("Input Monitoring"))
        XCTAssertEqual(PermissionKind.microphone.settingsURL.absoluteString,
                       "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
        XCTAssertEqual(PermissionKind.accessibility.settingsURL.absoluteString,
                       "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        XCTAssertEqual(PermissionKind.inputMonitoring.settingsURL.absoluteString,
                       "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
        XCTAssertEqual(PermissionKind.speechRecognition.settingsURL.absoluteString,
                       "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition")
    }

    func test_M14_speechRecognitionOnlyReportedWhenAppleFallbackIsUsed() {
        let all: Set<PermissionKind> = [.microphone, .accessibility, .inputMonitoring]
        XCTAssertEqual(PermissionReport(granted: all, needsSpeechRecognition: false).missing, [])
        XCTAssertEqual(PermissionReport(granted: all, needsSpeechRecognition: true).missing, [.speechRecognition])
        XCTAssertTrue(PermissionReport(granted: all, needsSpeechRecognition: false).summary.contains("granted"))
    }
}
