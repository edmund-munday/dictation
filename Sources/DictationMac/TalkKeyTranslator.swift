import DictationCore
import Foundation

/// A keyboard event reduced to what the talk-key logic needs (CGEvent type, keycode, flags).
public struct RawKeyEvent: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case keyDown
        case keyUp
        case flagsChanged
    }

    public var kind: Kind
    public var keyCode: UInt16
    public var flags: UInt64

    public init(kind: Kind, keyCode: UInt16, flags: UInt64) {
        self.kind = kind
        self.keyCode = keyCode
        self.flags = flags
    }
}

/// What the tap reports: a core talk-key event or the Ctrl-Opt-Space toggle.
public enum TapOutput: Sendable, Equatable {
    case talk(TalkKeyEvent)
    case toggle
}

/// macOS virtual key codes and CGEventFlags bits used by the tap.
public enum MacKey {
    public static let leftCommand: UInt16 = 55
    public static let rightCommand: UInt16 = 54
    public static let leftShift: UInt16 = 56
    public static let rightShift: UInt16 = 60
    public static let leftOption: UInt16 = 58
    public static let rightOption: UInt16 = 61
    public static let leftControl: UInt16 = 59
    public static let rightControl: UInt16 = 62
    public static let capsLock: UInt16 = 57
    public static let function: UInt16 = 63
    public static let space: UInt16 = 49
    public static let escape: UInt16 = 53

    public static let commandFlag: UInt64 = 0x0010_0000
    public static let shiftFlag: UInt64 = 0x0002_0000
    public static let controlFlag: UInt64 = 0x0004_0000
    public static let optionFlag: UInt64 = 0x0008_0000
    public static let functionFlag: UInt64 = 0x0080_0000
    public static let capsLockFlag: UInt64 = 0x0001_0000
    public static let leftCommandDeviceFlag: UInt64 = 0x0000_0008
    public static let rightCommandDeviceFlag: UInt64 = 0x0000_0010
}

/// Turns raw key events into core `TalkKeyEvent`s. It only observes; callers must pass
/// every event on unchanged (M4).
public final class TalkKeyTranslator {
    private var keysDown: Set<UInt16> = []
    private var leftCommandDown = false
    private var rightCommandDown = false

    public init() {}

    public func translate(_ event: RawKeyEvent, at time: Duration) -> [TapOutput] {
        switch event.kind {
        case .keyDown:
            return keyDown(event, at: time)
        case .keyUp:
            keysDown.remove(event.keyCode)
            return []
        case .flagsChanged:
            return flagsChanged(event, at: time)
        }
    }

    private func keyDown(_ event: RawKeyEvent, at time: Duration) -> [TapOutput] {
        let isRepeat = keysDown.contains(event.keyCode)
        keysDown.insert(event.keyCode)
        let mods = event.flags & (MacKey.commandFlag | MacKey.shiftFlag | MacKey.controlFlag | MacKey.optionFlag)
        if event.keyCode == MacKey.space, mods == (MacKey.controlFlag | MacKey.optionFlag) {
            return isRepeat ? [] : [.toggle]
        }
        if isRepeat { return [] }
        return [.talk(TalkKeyEvent(timestamp: time, identity: identity(forKeyCode: event.keyCode), isDown: true))]
    }

    private func flagsChanged(_ event: RawKeyEvent, at time: Duration) -> [TapOutput] {
        let flags = event.flags
        switch event.keyCode {
        case MacKey.leftCommand, MacKey.rightCommand:
            let side: CommandSide = event.keyCode == MacKey.leftCommand ? .left : .right
            let deviceBit = side == .left ? MacKey.leftCommandDeviceFlag : MacKey.rightCommandDeviceFlag
            // Some keyboards omit device bits; fall back to the generic Command flag.
            let anyDeviceBit = flags & (MacKey.leftCommandDeviceFlag | MacKey.rightCommandDeviceFlag) != 0
            let nowDown = anyDeviceBit ? (flags & deviceBit != 0) : (flags & MacKey.commandFlag != 0)
            let wasDown = side == .left ? leftCommandDown : rightCommandDown
            guard nowDown != wasDown else { return [] }
            let otherCommandDown = side == .left ? rightCommandDown : leftCommandDown
            if side == .left { leftCommandDown = nowDown } else { rightCommandDown = nowDown }
            if nowDown {
                var others = otherKeys(flags: flags)
                if otherCommandDown { others.append(.command(side == .left ? .right : .left)) }
                return [.talk(TalkKeyEvent(
                    timestamp: time, identity: .command(side), isDown: true, otherKeysAlreadyDown: others))]
            }
            return [.talk(TalkKeyEvent(timestamp: time, identity: .command(side), isDown: false))]
        default:
            guard let (name, mask) = modifier(forKeyCode: event.keyCode) else { return [] }
            let down = flags & mask != 0
            if event.keyCode == MacKey.capsLock {
                // Caps Lock toggles state; any change counts as a press.
                return [.talk(TalkKeyEvent(timestamp: time, identity: .modifier(name), isDown: true))]
            }
            if down { keysDown.insert(event.keyCode) } else { keysDown.remove(event.keyCode) }
            return [.talk(TalkKeyEvent(timestamp: time, identity: .modifier(name), isDown: down))]
        }
    }

    private func otherKeys(flags: UInt64) -> [KeyIdentity] {
        var result: [KeyIdentity] = []
        if flags & MacKey.shiftFlag != 0 { result.append(.modifier("shift")) }
        if flags & MacKey.controlFlag != 0 { result.append(.modifier("control")) }
        if flags & MacKey.optionFlag != 0 { result.append(.modifier("option")) }
        if flags & MacKey.functionFlag != 0 { result.append(.modifier("fn")) }
        for code in keysDown.sorted() where modifier(forKeyCode: code) == nil {
            result.append(identity(forKeyCode: code))
        }
        return result
    }

    private func modifier(forKeyCode code: UInt16) -> (String, UInt64)? {
        switch code {
        case MacKey.leftShift, MacKey.rightShift: return ("shift", MacKey.shiftFlag)
        case MacKey.leftOption, MacKey.rightOption: return ("option", MacKey.optionFlag)
        case MacKey.leftControl, MacKey.rightControl: return ("control", MacKey.controlFlag)
        case MacKey.function: return ("fn", MacKey.functionFlag)
        case MacKey.capsLock: return ("capslock", MacKey.capsLockFlag)
        default: return nil
        }
    }

    private func identity(forKeyCode code: UInt16) -> KeyIdentity {
        if code == MacKey.escape { return .escape }
        if let ch = Self.ansiCharacters[code] { return .character(ch) }
        return .shortcut("key-\(code)")
    }

    private static let ansiCharacters: [UInt16: Character] = [
        0: "a", 1: "s", 2: "d", 3: "f", 4: "h", 5: "g", 6: "z", 7: "x", 8: "c", 9: "v",
        11: "b", 12: "q", 13: "w", 14: "e", 15: "r", 16: "y", 17: "t", 18: "1", 19: "2",
        20: "3", 21: "4", 22: "6", 23: "5", 25: "9", 26: "7", 28: "8", 29: "0", 31: "o",
        32: "u", 34: "i", 35: "p", 37: "l", 38: "j", 40: "k", 45: "n", 46: "m", 49: " ",
    ]
}
