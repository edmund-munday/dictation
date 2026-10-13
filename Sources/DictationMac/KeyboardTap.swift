import CoreGraphics
import DictationCore
import Foundation

/// Listen-only CGEvent tap for keyDown/keyUp/flagsChanged. Every event is returned
/// unchanged; the tap never swallows or synthesises events (M2, M4).
public final class KeyboardTap {
    private let translator = TalkKeyTranslator()
    private let clock: any Clock
    private let sink: (TapOutput) -> Void
    private var machPort: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    public init(clock: any Clock, sink: @escaping (TapOutput) -> Void) {
        self.clock = clock
        self.sink = sink
    }

    /// Translates the event, reports outputs, and returns the very same event.
    public func handle(type: CGEventType, event: CGEvent) -> CGEvent {
        let kind: RawKeyEvent.Kind
        switch type {
        case .keyDown: kind = .keyDown
        case .keyUp: kind = .keyUp
        case .flagsChanged: kind = .flagsChanged
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let machPort { CGEvent.tapEnable(tap: machPort, enable: true) }
            return event
        default:
            return event
        }
        let raw = RawKeyEvent(
            kind: kind,
            keyCode: UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode)),
            flags: event.flags.rawValue
        )
        for output in translator.translate(raw, at: clock.now) {
            sink(output)
        }
        return event
    }

    /// Installs the tap on the current run loop. Returns false when Input Monitoring is missing.
    public func start() -> Bool {
        guard machPort == nil else { return true }
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let tap = Unmanaged<KeyboardTap>.fromOpaque(refcon).takeUnretainedValue()
                return Unmanaged.passUnretained(tap.handle(type: type, event: event))
            },
            userInfo: refcon
        ) else { return false }
        machPort = port
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        return true
    }

    public func stop() {
        if let source = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes) }
        if let port = machPort { CGEvent.tapEnable(tap: port, enable: false) }
        machPort = nil
        runLoopSource = nil
    }
}
