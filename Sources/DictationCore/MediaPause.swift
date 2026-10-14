import Foundation

public enum MediaPlayState {
    case playing
    case notPlaying
    case unknown
}

public protocol MediaController: AnyObject {
    func playState() -> MediaPlayState
    func pause()
    func resume()
}

/// Call from one serial queue to keep capture starts, ends, and setting changes ordered.
public final class MediaPauseCoordinator {
    private let controller: any MediaController
    private var pausedMedia = false
    public var enabled: Bool

    public init(controller: any MediaController, enabled: Bool) {
        self.controller = controller
        self.enabled = enabled
    }

    public func dictationStarted() {
        guard enabled, !pausedMedia, controller.playState() == .playing else { return }
        controller.pause()
        pausedMedia = true
    }

    public func dictationEnded() {
        guard pausedMedia else { return }
        pausedMedia = false
        controller.resume()
    }

    /// Transfers the paused playback state to a plugin without resuming it.
    public func handOff() -> Bool {
        let wasPlaying = pausedMedia
        pausedMedia = false
        return wasPlaying
    }

    public static func isEnabled(in defaults: UserDefaults) -> Bool {
        defaults.object(forKey: "pauseMediaWhileDictating") as? Bool ?? true
    }
}
