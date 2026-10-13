import Foundation

/// Platform-neutral dictation session: events in, observable outputs out.
///
/// Scaffold only — bodies are intentional no-ops so behaviour tests fail on assertions.
public final class Session: @unchecked Sendable {
    public let clock: any Clock
    public let paths: SessionPaths

    public private(set) var insertRequests: [InsertRequest] = []
    public private(set) var emittedKeyEvents: [EmittedKeyEvent] = []
    public private(set) var cliInvocations: [CLIInvocation] = []
    public private(set) var filesystemEntriesWritten: [URL] = []

    public init(clock: any Clock, paths: SessionPaths) {
        self.clock = clock
        self.paths = paths
    }

    // MARK: - Latch, mode, permissions, recognizer capability

    public func setLatch(_ command: LatchCommand) {}

    public func setMode(_ mode: DictationMode) {}

    public func setMicPermission(_ permission: MicPermission) {}

    public func setAccessibilityPermission(_ granted: Bool) {}

    public func setInputMonitoringPermission(_ granted: Bool) {}

    public func setOnDeviceRecognizerAvailable(_ available: Bool) {}

    public func setSystemRecognizerReportsOnDevice(_ onDevice: Bool) {}

    public func setBundledModelLoadable(_ loadable: Bool) {}

    // MARK: - Scripted environment inputs

    public func ingestRecognizerTokens(_ tokens: [RecognizerToken]) {}

    public func ingestEnergy(_ sample: EnergySample) {}

    public func ingestSpeakerScore(_ score: SpeakerScore) {}

    public func ingestFocus(_ snapshot: FocusSnapshot) {}

    public func ingestFrontmostApp(_ app: FrontmostApp) {}

    public func ingestMicOwner(_ status: MicOwnerStatus) {}

    public func ingestHardwareMute(_ mute: HardwareMute) {}

    public func reportDeviceClose(_ result: DeviceCloseResult) {}

    public func ingestSystemEvent(_ event: SystemEvent) {}

    public func ingestKey(_ press: KeyPress) {}

    // MARK: - CLI / voice / insertion feedback / settings

    public func configureCLI(path: String?, kind: CLIBackendKind?, enabled: Bool) {}

    public func confirmCLIConsent() {}

    public func declineCLIConsent() {}

    public func completeVoiceEnrollment() {}

    public func skipVoiceEnrollment() {}

    public func resetVoiceProfile() {}

    public func reportInsertionFailed(for requestIndex: Int) {}

    public func reportInsertionSucceeded(for requestIndex: Int) {}

    public func tapOverlayButton(title: String) {}

    // MARK: - Observable outputs (defaults make behaviour assertions fail)

    public var isLatchOn: Bool { false }

    public var micState: MicState { .closed }

    public var menuText: String { "" }

    public var overlay: OverlayState { .empty }

    public var bufferStatus: BufferStatus { BufferStatus() }

    public var voiceProfile: VoiceProfileStatus { VoiceProfileStatus() }

    public var settings: Settings { Settings() }

    public var consentPrompt: ConsentPrompt? { nil }

    public var isSetupComplete: Bool { true }

    public var setupMessage: String? { nil }
}
