import Foundation
import DictationCore

/// Test double: time advances only when `advance(by:)` is called.
public final class FakeClock: Clock, @unchecked Sendable {
    public private(set) var now: Duration
    /// Invoked after each advance so a session can evaluate timers.
    public var onAdvance: (() -> Void)?

    public init(now: Duration = .zero) {
        self.now = now
    }

    public func advance(by duration: Duration) {
        now += duration
        onAdvance?()
    }

    public func observeAdvances(_ handler: @escaping @Sendable () -> Void) {
        onAdvance = handler
    }
}
