import DictationCore
import Foundation
import XCTest

final class MediaPauseTests: XCTestCase {
    func test_R239_playingMediaPausesOnStartAndResumesOnEnd() {
        let controller = RecordingMediaController(state: .playing)
        let coordinator = MediaPauseCoordinator(controller: controller, enabled: true)

        coordinator.dictationStarted()
        XCTAssertEqual(controller.commands, [.pause])

        coordinator.dictationEnded()
        XCTAssertEqual(controller.commands, [.pause, .resume])
    }

    func test_R240_notPlayingMediaIsNeitherPausedNorResumed() {
        assertMediaIsLeftAlone(state: .notPlaying)
    }

    func test_R240_unknownMediaIsNeitherPausedNorResumed() {
        assertMediaIsLeftAlone(state: .unknown)
    }

    func test_R241_endWithoutStartDoesNotResumeMedia() {
        let controller = RecordingMediaController(state: .playing)
        let coordinator = MediaPauseCoordinator(controller: controller, enabled: true)

        coordinator.dictationEnded()
        coordinator.dictationEnded()

        XCTAssertTrue(controller.calls.isEmpty)
    }

    func test_R241_secondEndDoesNotResumeAgain() {
        let controller = RecordingMediaController(state: .playing)
        let coordinator = MediaPauseCoordinator(controller: controller, enabled: true)
        coordinator.dictationStarted()
        coordinator.dictationEnded()
        controller.calls.removeAll()

        coordinator.dictationEnded()

        XCTAssertTrue(controller.calls.isEmpty)
    }

    func test_R241_repeatedStartDoesNotPauseAgainOrLoseResume() {
        let controller = RecordingMediaController(state: .playing)
        let coordinator = MediaPauseCoordinator(controller: controller, enabled: true)
        coordinator.dictationStarted()
        // The OS now reports the media we paused as not playing.
        controller.state = .notPlaying
        coordinator.dictationStarted()
        XCTAssertEqual(controller.calls.filter { $0 == .pause }.count, 1)
        XCTAssertEqual(controller.calls.filter { $0 == .resume }.count, 0)

        coordinator.dictationEnded()
        XCTAssertEqual(controller.calls.filter { $0 == .pause }.count, 1)
        XCTAssertEqual(controller.calls.filter { $0 == .resume }.count, 1)
    }

    func test_R241_laterDictationStartsFreshAfterResume() {
        let controller = RecordingMediaController(state: .playing)
        let coordinator = MediaPauseCoordinator(controller: controller, enabled: true)
        coordinator.dictationStarted()
        coordinator.dictationEnded()
        controller.calls.removeAll()

        coordinator.dictationStarted()
        XCTAssertEqual(controller.commands, [.pause])
        coordinator.dictationEnded()
        XCTAssertEqual(controller.commands, [.pause, .resume])
    }

    func test_R241_laterDictationRechecksWhetherMediaIsPlaying() {
        let controller = RecordingMediaController(state: .playing)
        let coordinator = MediaPauseCoordinator(controller: controller, enabled: true)
        coordinator.dictationStarted()
        coordinator.dictationEnded()
        controller.state = .notPlaying
        controller.calls.removeAll()

        coordinator.dictationStarted()
        coordinator.dictationEnded()

        XCTAssertTrue(controller.calls.contains(.playState))
        XCTAssertTrue(controller.commands.isEmpty)
    }

    func test_R242_disabledSettingDoesNotQueryPauseOrResume() {
        let controller = RecordingMediaController(state: .playing)
        let coordinator = MediaPauseCoordinator(controller: controller, enabled: false)

        coordinator.dictationStarted()
        coordinator.dictationEnded()

        XCTAssertTrue(controller.calls.isEmpty)
    }

    func test_R242_disablingAfterPauseStillResumesOnceOnEnd() {
        let controller = RecordingMediaController(state: .playing)
        let coordinator = MediaPauseCoordinator(controller: controller, enabled: true)
        coordinator.dictationStarted()
        coordinator.enabled = false
        XCTAssertEqual(controller.commands, [.pause])

        coordinator.dictationEnded()
        XCTAssertEqual(controller.commands, [.pause, .resume])

        controller.calls.removeAll()
        coordinator.dictationEnded()
        coordinator.dictationStarted()
        coordinator.dictationEnded()
        XCTAssertTrue(controller.calls.isEmpty)
    }

    func test_R242_enablingSettingAllowsNextDictationToPauseAndResume() {
        let controller = RecordingMediaController(state: .playing)
        let coordinator = MediaPauseCoordinator(controller: controller, enabled: false)
        coordinator.dictationStarted()
        coordinator.dictationEnded()
        XCTAssertTrue(controller.calls.isEmpty)

        coordinator.enabled = true
        coordinator.dictationStarted()
        coordinator.dictationEnded()

        XCTAssertEqual(controller.commands, [.pause, .resume])
    }

    func test_R242_settingDefaultsToOnAndHonorsStoredFalseAndTrue() throws {
        let suiteName = "MediaPauseTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertTrue(MediaPauseCoordinator.isEnabled(in: defaults))

        defaults.set(false, forKey: "pauseMediaWhileDictating")
        XCTAssertFalse(MediaPauseCoordinator.isEnabled(in: defaults))

        defaults.set(true, forKey: "pauseMediaWhileDictating")
        XCTAssertTrue(MediaPauseCoordinator.isEnabled(in: defaults))

        defaults.removeObject(forKey: "pauseMediaWhileDictating")
        XCTAssertTrue(MediaPauseCoordinator.isEnabled(in: defaults))
    }

    private func assertMediaIsLeftAlone(
        state: MediaPlayState, file: StaticString = #filePath, line: UInt = #line
    ) {
        let controller = RecordingMediaController(state: state)
        let coordinator = MediaPauseCoordinator(controller: controller, enabled: true)

        coordinator.dictationStarted()
        XCTAssertTrue(controller.commands.isEmpty, file: file, line: line)
        // Media starting later must not make end send a resume we did not earn.
        controller.state = .playing
        coordinator.dictationEnded()
        XCTAssertTrue(controller.commands.isEmpty, file: file, line: line)
    }
}

/// Records commands at the public OS media boundary.
private final class RecordingMediaController: MediaController {
    enum Call: Equatable { case playState, pause, resume }

    var state: MediaPlayState
    var calls: [Call] = []
    var commands: [Call] { calls.filter { $0 != .playState } }

    init(state: MediaPlayState) { self.state = state }

    func playState() -> MediaPlayState {
        calls.append(.playState)
        return state
    }

    func pause() { calls.append(.pause) }
    func resume() { calls.append(.resume) }
}
