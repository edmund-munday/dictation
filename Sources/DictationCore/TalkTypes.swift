import Foundation

// MARK: - Talk key

public enum CommandSide: Sendable, Equatable {
    case left
    case right
}

/// Which Command key starts a hold. Right Command is the product default.
public enum TalkKeyChoice: Sendable, Equatable {
    case rightCommand
    case leftCommand
    case eitherCommand
}

/// Identity of a key in a hold-to-talk event. Distinct from `KeyKind`, which the
/// always-on path still uses.
public enum KeyIdentity: Sendable, Equatable {
    case command(CommandSide)
    case escape
    case character(Character)
    case shortcut(String)
    case modifier(String)
}

/// Key down/up delivered to the session, including keys already down.
public struct TalkKeyEvent: Sendable, Equatable {
    public var timestamp: Duration
    public var identity: KeyIdentity
    public var isDown: Bool
    public var otherKeysAlreadyDown: [KeyIdentity]

    public init(
        timestamp: Duration,
        identity: KeyIdentity,
        isDown: Bool,
        otherKeysAlreadyDown: [KeyIdentity] = []
    ) {
        self.timestamp = timestamp
        self.identity = identity
        self.isDown = isDown
        self.otherKeysAlreadyDown = otherKeysAlreadyDown
    }
}

// MARK: - Cleanup backend

public enum CleanupBackend: Sendable, Equatable {
    case cursorCLI
    case claudeCLI
    case grokCLI
    case localModel
    case off
}

// MARK: - Floating panel

public struct PanelState: Sendable, Equatable {
    public var isVisible: Bool
    public var text: String?
    public var buttons: [OverlayButton]

    public init(isVisible: Bool = false, text: String? = nil, buttons: [OverlayButton] = []) {
        self.isVisible = isVisible
        self.text = text
        self.buttons = buttons
    }

    public static let hidden = PanelState()
}
