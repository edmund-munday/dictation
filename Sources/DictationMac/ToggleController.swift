import DictationCore
import Foundation

/// Active/paused state (M5, R289-R290). Active maps onto the core latch.
public final class ToggleController {
    private let session: Session

    public init(session: Session) {
        self.session = session
    }

    public var isEnabled: Bool { session.isLatchOn }

    public func setEnabled(_ enabled: Bool) {
        session.setLatch(enabled ? .on : .off)
    }

    public func toggle() {
        setEnabled(!isEnabled)
    }

    public var statusSymbolName: String { isEnabled ? "mic.fill" : "pause.circle" }

    public var menuTitle: String {
        isEnabled ? "Pause dictation (Ctrl-Opt-Space)" : "Resume dictation (Ctrl-Opt-Space)"
    }
}
