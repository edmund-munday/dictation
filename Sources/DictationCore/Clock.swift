import Foundation

/// Injectable clock. `now` is the current time. `observeAdvances` registers
/// work that runs when time moves. `SystemClock` calls it from its own timer.
public protocol Clock: Sendable {
    var now: Duration { get }
    func observeAdvances(_ handler: @escaping @Sendable () -> Void)
    /// When true, `now` moves with wall time, so a later timer tick can
    /// observe a cleanup process. A manual clock only moves inside
    /// `observeAdvances`, and that callback has to see the process exit.
    var observesWallTime: Bool { get }
}

extension Clock {
    public var observesWallTime: Bool { false }
}

/// Wall-clock time. Deadlines are rechecked on a short repeating timer.
public final class SystemClock: Clock, @unchecked Sendable {
    private let origin = ContinuousClock.now
    private let lock = NSLock()
    private var handler: (@Sendable () -> Void)?
    private var timer: DispatchSourceTimer?

    public init() {}

    public var now: Duration {
        origin.duration(to: .now)
    }

    public var observesWallTime: Bool { true }

    public func observeAdvances(_ handler: @escaping @Sendable () -> Void) {
        lock.lock()
        self.handler = handler
        if timer == nil {
            let source = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
            source.schedule(deadline: .now() + .milliseconds(50), repeating: .milliseconds(50))
            source.setEventHandler { [weak self] in
                self?.fire()
            }
            timer = source
            source.resume()
        }
        lock.unlock()
    }

    private func fire() {
        lock.lock()
        let handler = self.handler
        lock.unlock()
        handler?()
    }

    deinit {
        timer?.cancel()
    }
}
