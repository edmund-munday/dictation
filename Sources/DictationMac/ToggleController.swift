import DictationCore
import Foundation

/// Enabled/disabled state (M5). Enabled maps onto the core latch.
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

    public var statusSymbolName: String { isEnabled ? "mic.fill" : "mic.slash" }

    public var menuTitle: String {
        isEnabled ? "Dictation On (Ctrl-Opt-Space turns off)" : "Dictation Off (Ctrl-Opt-Space turns on)"
    }
}
