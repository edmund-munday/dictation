/// Injectable clock for deterministic timing in tests and production.
public protocol Clock: Sendable {
    var now: Duration { get }
}

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
}
