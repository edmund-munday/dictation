import Foundation

// MARK: - Latch & mode

public enum LatchCommand: Sendable, Equatable {
    case on
    case off
}

public enum DictationMode: Sendable, Equatable {
    case flow
    case guarded
}

// MARK: - Recognizer / audio inputs

public struct RecognizerToken: Sendable, Equatable {
    public var text: String
    public var start: Duration
    public var end: Duration
    /// VAD / speech-activity flag for the token's time range.
    public var isSpeech: Bool
    public var confidence: Double
    /// BCP-47 language tag when known; `nil` if unspecified.
    public var language: String?
    public var isFinal: Bool

    public init(
        text: String,
        start: Duration,
        end: Duration,
        isSpeech: Bool = true,
        confidence: Double = 1.0,
        language: String? = "en",
        isFinal: Bool = true
    ) {
        self.text = text
        self.start = start
        self.end = end
        self.isSpeech = isSpeech
        self.confidence = confidence
        self.language = language
        self.isFinal = isFinal
    }
}

public struct EnergySample: Sendable, Equatable {
    public var timestamp: Duration
    public var energyDb: Double
    public var noiseFloorDb: Double
    public var isBuiltInMic: Bool

    public init(timestamp: Duration, energyDb: Double, noiseFloorDb: Double, isBuiltInMic: Bool) {
        self.timestamp = timestamp
        self.energyDb = energyDb
        self.noiseFloorDb = noiseFloorDb
        self.isBuiltInMic = isBuiltInMic
    }
}

public struct SpeakerScore: Sendable, Equatable {
    public var timestamp: Duration
    /// Higher means closer match to the enrolled voiceprint.
    public var matchScore: Double

    public init(timestamp: Duration, matchScore: Double) {
        self.timestamp = timestamp
        self.matchScore = matchScore
    }
}

// MARK: - Focus

public enum FieldRole: Sendable, Equatable {
    case none
    case textField
    case textArea
    case secureTextField
    case comboBox
    case terminal
    case editableWebArea
}

public struct FocusIdentity: Sendable, Hashable {
    public var pid: Int
    public var elementID: String?
    public var roleLabel: String?
    public var frameDescription: String?

    public init(
        pid: Int,
        elementID: String? = nil,
        roleLabel: String? = nil,
        frameDescription: String? = nil
    ) {
        self.pid = pid
        self.elementID = elementID
        self.roleLabel = roleLabel
        self.frameDescription = frameDescription
    }

    public static let none = FocusIdentity(pid: 0)
}

public struct FocusSnapshot: Sendable, Equatable {
    public var timestamp: Duration
    public var role: FieldRole
    public var isSecureInput: Bool
    public var selectionLength: Int
    public var selectionContainsLineBreak: Bool
    public var precedingCharacter: Character?
    public var identity: FocusIdentity
    /// False when the focused element has gone away (R107). Ignored until hold-to-talk is implemented.
    public var exists: Bool

    public init(
        timestamp: Duration,
        role: FieldRole,
        isSecureInput: Bool = false,
        selectionLength: Int = 0,
        selectionContainsLineBreak: Bool = false,
        precedingCharacter: Character? = nil,
        identity: FocusIdentity,
        exists: Bool = true
    ) {
        self.timestamp = timestamp
        self.role = role
        self.isSecureInput = isSecureInput
        self.selectionLength = selectionLength
        self.selectionContainsLineBreak = selectionContainsLineBreak
        self.precedingCharacter = precedingCharacter
        self.identity = identity
        self.exists = exists
    }
}

// MARK: - Apps / mic / system

public enum CallAppKind: Sendable, Equatable {
    case none
    case faceTime
    case zoomMeeting
    case teamsMeeting
    case webexMeeting
}

public struct FrontmostApp: Sendable, Equatable {
    public var timestamp: Duration
    public var bundleID: String
    public var callKind: CallAppKind

    public init(timestamp: Duration, bundleID: String, callKind: CallAppKind = .none) {
        self.timestamp = timestamp
        self.bundleID = bundleID
        self.callKind = callKind
    }
}

public struct MicOwnerStatus: Sendable, Equatable {
    public var timestamp: Duration
    public var anotherAppHoldsInput: Bool

    public init(timestamp: Duration, anotherAppHoldsInput: Bool) {
        self.timestamp = timestamp
        self.anotherAppHoldsInput = anotherAppHoldsInput
    }
}

public enum MicPermission: Sendable, Equatable {
    case granted
    case denied
    case revoked
}

public struct HardwareMute: Sendable, Equatable {
    public var timestamp: Duration
    public var isMuted: Bool

    public init(timestamp: Duration, isMuted: Bool) {
        self.timestamp = timestamp
        self.isMuted = isMuted
    }
}

/// Result of a device-close attempt reported by the platform shell.
public struct DeviceCloseResult: Sendable, Equatable {
    public var timestamp: Duration
    public var isClosed: Bool

    public init(timestamp: Duration, isClosed: Bool) {
        self.timestamp = timestamp
        self.isClosed = isClosed
    }
}

public enum SystemEvent: Sendable, Equatable {
    case screenLock
    case screenUnlock
    case sleep
    case wake
    case lidClose
    case lidOpen
    case audioRouteChange
}

public enum KeyKind: Sendable, Equatable {
    case escape
    case character(Character)
    case fn
    case returnKey
    case tab
    case shortcut(String)
}

public struct KeyPress: Sendable, Equatable {
    public var timestamp: Duration
    public var kind: KeyKind
    public var isDown: Bool

    public init(timestamp: Duration, kind: KeyKind, isDown: Bool = true) {
        self.timestamp = timestamp
        self.kind = kind
        self.isDown = isDown
    }
}

// MARK: - Outputs

public struct InsertRequest: Sendable, Equatable {
    public var text: String
    public var target: FocusIdentity
    public var replacesSelection: Bool

    public init(text: String, target: FocusIdentity, replacesSelection: Bool = false) {
        self.text = text
        self.target = target
        self.replacesSelection = replacesSelection
    }
}

public struct EmittedKeyEvent: Sendable, Equatable {
    public var kind: KeyKind

    public init(kind: KeyKind) {
        self.kind = kind
    }
}

public enum MicState: Sendable, Equatable {
    case open
    case closed
    case released
}

public struct OverlayButton: Sendable, Equatable {
    public var title: String

    public init(title: String) {
        self.title = title
    }
}

public struct OverlayState: Sendable, Equatable {
    public var text: String?
    public var buttons: [OverlayButton]

    public init(text: String? = nil, buttons: [OverlayButton] = []) {
        self.text = text
        self.buttons = buttons
    }

    public static let empty = OverlayState()
}

public struct BufferStatus: Sendable, Equatable {
    /// Current pre-roll contents duration in milliseconds (cap 1500).
    public var preRollMilliseconds: Int
    public var heldInMemoryOnly: Bool
    public var isWiped: Bool

    public init(preRollMilliseconds: Int = 0, heldInMemoryOnly: Bool = true, isWiped: Bool = true) {
        self.preRollMilliseconds = preRollMilliseconds
        self.heldInMemoryOnly = heldInMemoryOnly
        self.isWiped = isWiped
    }
}

public struct VoiceProfileStatus: Sendable, Equatable {
    public var isEnrolled: Bool
    public var version: Int
    public var acceptedUtteranceCount: Int
    public var speakerFilteringEnabled: Bool
    public var enrollmentAvailable: Bool
    public var enrollmentSkipped: Bool

    public init(
        isEnrolled: Bool = false,
        version: Int = 0,
        acceptedUtteranceCount: Int = 0,
        speakerFilteringEnabled: Bool = false,
        enrollmentAvailable: Bool = false,
        enrollmentSkipped: Bool = false
    ) {
        self.isEnrolled = isEnrolled
        self.version = version
        self.acceptedUtteranceCount = acceptedUtteranceCount
        self.speakerFilteringEnabled = speakerFilteringEnabled
        self.enrollmentAvailable = enrollmentAvailable
        self.enrollmentSkipped = enrollmentSkipped
    }
}

public enum CLIBackendKind: Sendable, Equatable {
    case cursorCLI
    case claudeCLI
}

public struct Settings: Sendable, Equatable {
    public var mode: DictationMode
    public var cliBackendEnabled: Bool
    public var cliBackendPath: String?
    public var cliBackendKind: CLIBackendKind?
    public var cleanupBackend: CleanupBackend
    public var talkKey: TalkKeyChoice

    public init(
        mode: DictationMode = .flow,
        cliBackendEnabled: Bool = false,
        cliBackendPath: String? = nil,
        cliBackendKind: CLIBackendKind? = nil,
        cleanupBackend: CleanupBackend = .off,
        talkKey: TalkKeyChoice = .leftCommand
    ) {
        self.mode = mode
        self.cliBackendEnabled = cliBackendEnabled
        self.cliBackendPath = cliBackendPath
        self.cliBackendKind = cliBackendKind
        self.cleanupBackend = cleanupBackend
        self.talkKey = talkKey
    }
}

public struct ConsentPrompt: Sendable, Equatable {
    public var message: String

    public init(message: String) {
        self.message = message
    }
}

public struct CLIInvocation: Sendable, Equatable {
    public var executablePath: String
    public var arguments: [String]
    public var stdinText: String
    public var containedAudioPayload: Bool

    public init(
        executablePath: String,
        arguments: [String] = [],
        stdinText: String,
        containedAudioPayload: Bool = false
    ) {
        self.executablePath = executablePath
        self.arguments = arguments
        self.stdinText = stdinText
        self.containedAudioPayload = containedAudioPayload
    }
}

public struct SessionPaths: Sendable, Equatable {
    /// Directory the core may use for any on-disk artefacts (tests watch it).
    public var workingDirectory: URL

    public init(workingDirectory: URL) {
        self.workingDirectory = workingDirectory
    }
}
