import DictationCore
import Foundation

/// Wall clock whose timer ticks on a caller-chosen serial queue, so the session is only
/// touched from that queue.
public final class QueueClock: Clock, @unchecked Sendable {
    private let origin = ContinuousClock.now
    private let queue: DispatchQueue
    private var timer: DispatchSourceTimer?
    private var handlers: [@Sendable () -> Void] = []

    public init(queue: DispatchQueue) {
        self.queue = queue
    }

    public var now: Duration { origin.duration(to: .now) }

    /// Adds a handler; every handler runs on each tick, in registration order.
    public func observeAdvances(_ handler: @escaping @Sendable () -> Void) {
        queue.async { [self] in
            handlers.append(handler)
            guard timer == nil else { return }
            let source = DispatchSource.makeTimerSource(queue: queue)
            source.schedule(deadline: .now() + .milliseconds(50), repeating: .milliseconds(50))
            source.setEventHandler { [weak self] in
                self?.handlers.forEach { $0() }
            }
            timer = source
            source.resume()
        }
    }

    deinit { timer?.cancel() }
}
