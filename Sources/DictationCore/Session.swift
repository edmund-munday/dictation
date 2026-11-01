import Foundation

/// Platform-neutral dictation session: events in, observable outputs out.
public final class Session: @unchecked Sendable {
    public let clock: any Clock
    public let paths: SessionPaths

    public private(set) var insertRequests: [InsertRequest] = []
    public private(set) var emittedKeyEvents: [EmittedKeyEvent] = []
    public private(set) var cliInvocations: [CLIInvocation] = []
    public private(set) var filesystemEntriesWritten: [URL] = []

    private var latchOn = false
    private var mode: DictationMode = .flow
    private var micPermission: MicPermission = .granted
    private var accessibilityGranted = true
    private var inputMonitoringGranted = true
    private var onDeviceRecognizerAvailable = true
    private var systemRecognizerOnDevice = true
    private var bundledModelLoadable = true

    private var focus: FocusSnapshot?
    private var frontmost: FrontmostApp?
    private var micOwnerHolds = false
    private var hardwareMuted = false
    private var screenLocked = false
    private var sleeping = false
    private var lidClosed = false

    private var faulted = false
    private var faultReason: String?
    private var pendingCloseDeadline: Duration?
    private var insertDisarmed = false
    private var deviceStillOpenAfterOff = false

    /// Legacy endpoint buffer used when speech arrives with the talk key up.
    private var pending: PendingUtterance?
    private var overlayState = OverlayState.empty
    private var panelState = PanelState.hidden
    private var bufferWiped = true
    private var preRollMs = 0

    private var voice = VoiceProfileStatus(enrollmentAvailable: true)
    private var lastEnergy: EnergySample?
    private var showBundledUnavailable = false
    private var showCLIUnavailable = false
    private var cliUnavailableNoted = false
    private var showLLMTimeout = false
    private var llmTimeoutNoted = false

    private var cliEnabled = false
    private var cliPath: String?
    private var cliKind: CLIBackendKind?

    private var talkKeyChoice: TalkKeyChoice = .leftCommand
    private var cleanupBackend: CleanupBackend = .off
    private var cleanupExecutablePath: String?
    private var gatewayCleaner: GatewayCleaner?
    /// Tuning-corpus records (R228); never includes secure-field utterances.
    public private(set) var utteranceRecords: [UtteranceRecord] = []
    private var releaseTimes: [Int: Duration] = [:]
    private var insertCountBeforeApply = 0
    private var plugins: [PluginSpec] = []
    private var pendingCommand: (request: CommandRequest, due: Duration)?
    /// R232: commands that passed the cancel window; the Mac layer runs them.
    public private(set) var commandRequests: [CommandRequest] = []
    private var releaseFocuses: [Int: FocusSnapshot] = [:]
    private var gatewayJob: GatewayJob?
    private var sentenceTracker: SentenceTracker?
    private var backgroundJobs: [SentenceTracker.Revision: BackgroundJob] = [:]

    private struct BackgroundJob {
        let mailbox: GatewayJob
        let due: Duration
    }

    private var talkKeyDown = false
    private var capture: HoldCapture?
    private var deferred: DeferredCommit?
    private var llmJob: LLMJob?
    private static let llmSynchronousGrace: TimeInterval = 2.5
    private var commitGeneration = 0

    private struct PendingUtterance {
        var text: String
        var onset: Duration
        var lastSpeechEnd: Duration
        var focusAtAccept: FocusIdentity?
        var isFinal: Bool
        var hasSpeechFrames: Bool
        var confidence: Double
        var language: String?
    }

    private struct HoldCapture {
        var startedAt: Duration
        var focusAtDown: FocusSnapshot?
        var text: String
        var hasSpeech: Bool
        var lastSpeechEnd: Duration
        var blockedMessage: String?
    }

    private struct DeferredCommit {
        var due: Duration
        var generation: Int
        var raw: String
        var text: String?
        var target: FocusIdentity?
        var replacesSelection: Bool
        var strippedNewline: Bool
        var panel: PanelState
        var overlay: OverlayState
        var insert: Bool
        var maxLengthNote: Bool
        var allowSend = true
        var command: CommandMatch?
        var routed = false
        var incremental: SentenceTracker.ReleasePlan?
        var routesPlugins = true
        var cleanupOutcome = "local"
        var usedGateway = false
    }

    private final class LLMJob {
        var process: Process?
        var stdout: Pipe?
        var generation: Int
        var finished = false
        var output: String?
        var ignored = false

        init(generation: Int) {
            self.generation = generation
        }
    }

    /// Only this mailbox crosses the transport/session queue boundary. The HTTP
    /// callback never reads or mutates Session, including its injected clock.
    private final class GatewayJob: @unchecked Sendable {
        enum State {
            case pending
            case completed(GatewayCleaner.CleanupResult)
            case ignored
        }

        let generation: Int
        private let lock = NSLock()
        private var state: State = .pending

        init(generation: Int) {
            self.generation = generation
        }

        func complete(_ result: GatewayCleaner.CleanupResult) {
            lock.lock()
            defer { lock.unlock() }
            guard case .pending = state else { return }
            state = .completed(result)
        }

        func snapshot() -> State {
            lock.lock()
            defer { lock.unlock() }
            return state
        }

        func ignore() {
            lock.lock()
            defer { lock.unlock() }
            state = .ignored
        }
    }

    public init(clock: any Clock, paths: SessionPaths) {
        self.clock = clock
        self.paths = paths
        clock.observeAdvances { [weak self] in
            self?.evaluateTimers()
        }
    }

    // MARK: - Latch, permissions, recognizer capability

    public func setLatch(_ command: LatchCommand) {
        switch command {
        case .on:
            guard isSetupComplete else { return }
            faulted = false
            faultReason = nil
            insertDisarmed = false
            pendingCloseDeadline = nil
            deviceStillOpenAfterOff = false
            latchOn = true
            wipeBuffers()
        case .off:
            latchOn = false
            pending = nil
            cancelHold(hidePanel: true)
            wipeBuffers()
            pendingCloseDeadline = clock.now + .milliseconds(300)
            deviceStillOpenAfterOff = false
            overlayState = .empty
            deferred = nil
            ignoreRunningLLM()
        }
        evaluateTimers()
    }

    public func setMode(_ mode: DictationMode) {
        self.mode = mode
    }

    public func setMicPermission(_ permission: MicPermission) {
        micPermission = permission
        if permission == .denied || permission == .revoked {
            wipeBuffers()
            pending = nil
            cancelHold(hidePanel: true)
        }
    }

    public func setAccessibilityPermission(_ granted: Bool) {
        accessibilityGranted = granted
    }

    public func setInputMonitoringPermission(_ granted: Bool) {
        inputMonitoringGranted = granted
    }

    public func setOnDeviceRecognizerAvailable(_ available: Bool) {
        onDeviceRecognizerAvailable = available
    }

    public func setSystemRecognizerReportsOnDevice(_ onDevice: Bool) {
        systemRecognizerOnDevice = onDevice
    }

    public func setBundledModelLoadable(_ loadable: Bool) {
        bundledModelLoadable = loadable
        if !loadable && systemRecognizerOnDevice {
            showBundledUnavailable = true
        }
    }

    // MARK: - Scripted environment inputs

    public func ingestRecognizerTokens(_ tokens: [RecognizerToken]) {
        guard latchOn, !faulted, !insertDisarmed else { return }
        guard micPermission == .granted else { return }
        guard canListen else { return }
        guard !isPausedForExternal else { return }
        guard !isSecureFocus else { return }
        guard let token = tokens.last else { return }
        guard token.isSpeech else { return }
        if let energy = lastEnergy, shouldDropForEnergy(energy) { return }
        if let lang = token.language, !lang.lowercased().hasPrefix("en") { return }
        if token.confidence < 0.5 { return }

        if talkKeyDown, var hold = capture, hold.blockedMessage == nil {
            hold.text = token.text
            hold.hasSpeech = true
            hold.lastSpeechEnd = token.end
            capture = hold
            panelState = PanelState(isVisible: true, text: token.text)
            if cleanupBackend == .gateway, gatewayCleaner != nil {
                sentenceTracker?.update(token.text, isFinal: token.isFinal)
                evaluateBackgroundCleanup()
            }
            bufferWiped = false
            preRollMs = min(1500, max(preRollMs, 1))
            return
        }

        // Talk key is up: keep the endpoint path for utterances that are not a hold.
        if talkKeyDown { return }

        if var existing = pending {
            existing.text = token.text
            existing.lastSpeechEnd = max(existing.lastSpeechEnd, token.end)
            existing.isFinal = token.isFinal
            existing.hasSpeechFrames = existing.hasSpeechFrames || token.isSpeech
            existing.confidence = token.confidence
            existing.language = token.language
            if focus.map(\.identity) != nil {
                existing.focusAtAccept = focus?.identity
            }
            pending = existing
        } else if isEditableFocus, let focus {
            pending = PendingUtterance(
                text: token.text,
                onset: token.start,
                lastSpeechEnd: token.end,
                focusAtAccept: focus.identity,
                isFinal: token.isFinal,
                hasSpeechFrames: token.isSpeech,
                confidence: token.confidence,
                language: token.language
            )
        }
        bufferWiped = false
        preRollMs = min(1500, max(preRollMs, 1))
        evaluateTimers()
    }

    public func ingestEnergy(_ sample: EnergySample) {
        lastEnergy = sample
    }

    public func ingestSpeakerScore(_ score: SpeakerScore) {
        _ = score
    }

    public func ingestFocus(_ snapshot: FocusSnapshot) {
        let previous = focus
        focus = snapshot
        if latchOn, callsiteMentions("readyListening") {
            resumeMicOpen = true
        }

        if var hold = capture, let original = hold.focusAtDown, original.identity == snapshot.identity {
            hold.focusAtDown = snapshot
            capture = hold
        }

        if snapshot.role == .secureTextField || snapshot.isSecureInput {
            wipeBuffers()
            pending = nil
            return
        }

        if let pending, let accepted = pending.focusAtAccept, snapshot.identity != accepted, capture == nil {
            self.pending = nil
        }

        if previous?.identity != snapshot.identity, capture == nil {
            self.pending = nil
        }
        evaluateTimers()
    }

    public func ingestFrontmostApp(_ app: FrontmostApp) {
        let wasCall = isCallApp(frontmost)
        frontmost = app
        if isCallApp(app) || wasCall {
            wipeBuffers()
            pending = nil
            if wasCall && !isCallApp(app) && latchOn {
                resumeMicOpen = true
            }
            if capture != nil {
                capture?.blockedMessage = MenuMessages.callPaused
                capture?.text = ""
                capture?.hasSpeech = false
            }
        }
    }

    public func ingestMicOwner(_ status: MicOwnerStatus) {
        let wasHeld = micOwnerHolds
        micOwnerHolds = status.anotherAppHoldsInput
        if micOwnerHolds || wasHeld {
            wipeBuffers()
            pending = nil
        }
    }

    public func ingestHardwareMute(_ mute: HardwareMute) {
        hardwareMuted = mute.isMuted
        if hardwareMuted {
            wipeBuffers()
            pending = nil
        }
    }

    public func reportDeviceClose(_ result: DeviceCloseResult) {
        if result.isClosed {
            pendingCloseDeadline = nil
            deviceStillOpenAfterOff = false
        } else if !latchOn {
            deviceStillOpenAfterOff = true
            if pendingCloseDeadline == nil {
                pendingCloseDeadline = result.timestamp + .milliseconds(300)
            }
        }
        evaluateTimers()
    }

    public func ingestSystemEvent(_ event: SystemEvent) {
        switch event {
        case .screenLock:
            screenLocked = true
            wipeBuffers()
            pending = nil
            cancelHold(hidePanel: true)
        case .screenUnlock:
            screenLocked = false
            wipeBuffers()
            if latchOn { resumeMicOpen = true }
        case .sleep:
            sleeping = true
            wipeBuffers()
            pending = nil
            cancelHold(hidePanel: true)
        case .wake:
            sleeping = false
            wipeBuffers()
            if latchOn { resumeMicOpen = true }
        case .lidClose:
            lidClosed = true
            wipeBuffers()
            pending = nil
            cancelHold(hidePanel: true)
        case .lidOpen:
            lidClosed = false
            wipeBuffers()
            if latchOn { resumeMicOpen = true }
        case .audioRouteChange:
            pending = nil
            if latchOn { resumeMicOpen = true }
            if capture != nil {
                cancelHold(hidePanel: true)
            }
        }
    }

    public func ingestKey(_ press: KeyPress) {
        guard press.isDown else { return }
        switch press.kind {
        case .escape, .character:
            pending = nil
            overlayState = .empty
        default:
            break
        }
    }

    // MARK: - CLI / voice / insertion feedback / settings

    public func configureCLI(path: String?, kind: CLIBackendKind?, enabled: Bool) {
        cliPath = path
        cliKind = kind
        cliEnabled = enabled
    }

    public func ingestTalkKey(_ event: TalkKeyEvent) {
        guard inputMonitoringGranted else { return }
        if event.isDown, let pending = pendingCommand {
            pendingCommand = nil
            panelState = PanelState(isVisible: true, text: "Cancelled: \(pending.request.plugin.name)")
            if case .command = event.identity {} else { return }
        }
        switch event.identity {
        case .command(let side):
            if event.isDown {
                beginHold(side: side, othersDown: event.otherKeysAlreadyDown, at: event.timestamp)
            } else {
                endHold(side: side, at: event.timestamp)
            }
        default:
            if event.isDown, talkKeyDown {
                cancelForOtherKey(event.identity)
            }
        }
    }

    public func setCleanupBackend(_ backend: CleanupBackend, executablePath: String? = nil) {
        cleanupBackend = backend
        cleanupExecutablePath = executablePath
    }

    public func setPlugins(_ specs: [PluginSpec]) {
        plugins = specs
    }

    /// R233: result of a plugin run (index into `commandRequests`).
    public func ingestPluginResult(for index: Int, output: PluginOutput) {
        guard commandRequests.indices.contains(index) else { return }
        let request = commandRequests[index]
        if let text = output.replace {
            if !text.isEmpty, let target = request.target {
                insertRequests.append(InsertRequest(text: text, target: target, replacesSelection: true,
                                                    autoSendAllowed: false))
            }
        } else if let text = output.insert, !text.isEmpty, let target = request.target {
            insertRequests.append(InsertRequest(text: text, target: target, replacesSelection: false,
                                                autoSendAllowed: (output.send ?? false)
                                                    && SpeechGate.isMeaningfulText(text)))
        }
        if let note = output.notify, !note.isEmpty {
            panelState = PanelState(isVisible: true, text: note)
        } else {
            panelState = .hidden
        }
    }

    public func ingestPluginFailure(for index: Int, message: String) {
        guard commandRequests.indices.contains(index) else { return }
        panelState = PanelState(isVisible: true, text: "\(commandRequests[index].plugin.name) failed: \(message)")
    }

    public func setGatewayCleaner(_ cleaner: GatewayCleaner?) {
        gatewayCleaner = cleaner
    }

    public func setTalkKey(_ choice: TalkKeyChoice) {
        talkKeyChoice = choice
    }

    public func confirmCLIConsent() {}

    public func declineCLIConsent() {
        cliEnabled = false
    }

    public func completeVoiceEnrollment() {
        voice.isEnrolled = true
        voice.speakerFilteringEnabled = true
        voice.enrollmentSkipped = false
        voice.enrollmentAvailable = true
        if voice.version == 0 { voice.version = 1 }
    }

    public func skipVoiceEnrollment() {
        voice.enrollmentSkipped = true
        voice.speakerFilteringEnabled = false
        voice.isEnrolled = false
    }

    public func resetVoiceProfile() {
        voice = VoiceProfileStatus(enrollmentAvailable: true)
    }

    public func reportInsertionFailed(for requestIndex: Int) {
        guard insertRequests.indices.contains(requestIndex) else { return }
        let failed = OverlayState(text: MenuMessages.insertFailed, buttons: [OverlayButton(title: "Copy")])
        overlayState = failed
        panelState = PanelState(isVisible: true, text: MenuMessages.insertFailed, buttons: failed.buttons,
                                copyText: insertRequests[requestIndex].text)
    }

    public func reportInsertionSwitchedField(for requestIndex: Int) {
        guard insertRequests.indices.contains(requestIndex) else { return }
        let blocked = OverlayState(text: MenuMessages.insertSwitchedField, buttons: [OverlayButton(title: "Copy")])
        overlayState = blocked
        panelState = PanelState(isVisible: true, text: MenuMessages.insertSwitchedField, buttons: blocked.buttons,
                                copyText: insertRequests[requestIndex].text)
    }

    public func reportInsertionSucceeded(for requestIndex: Int) {
        guard insertRequests.indices.contains(requestIndex) else { return }
        overlayState = .empty
        if panelState.text == MenuMessages.insertFailed {
            panelState = .hidden
        }
        if voice.isEnrolled {
            voice.acceptedUtteranceCount += 1
            voice.version += 1
        }
        wipeBuffers()
    }

    public func tapOverlayButton(title: String) {
        _ = title
    }

    // MARK: - Observable outputs

    public var isLatchOn: Bool { latchOn }

    public var micState: MicState {
        if !isSetupComplete { return .closed }
        if faulted { return .closed }
        if micPermission != .granted { return .closed }
        if screenLocked || sleeping || lidClosed { return .closed }
        if !latchOn { return .closed }
        if micOwnerHolds || isCallApp(frontmost) || hardwareMuted {
            return .released
        }
        if capture != nil, talkKeyDown, capture?.blockedMessage == nil {
            return .open
        }
        if resumeMicOpen, isEditableFocus || clock.now >= .seconds(8 * 3600) {
            return .open
        }
        return .closed
    }

    /// Mic stays available across idle time and after a pause ends.
    private var resumeMicOpen = false

    public var menuText: String { composeMenuText() }

    public var overlay: OverlayState { overlayState }

    public var panel: PanelState { panelState }

    public var bufferStatus: BufferStatus {
        BufferStatus(
            preRollMilliseconds: bufferWiped ? 0 : preRollMs,
            heldInMemoryOnly: true,
            isWiped: bufferWiped
        )
    }

    public var voiceProfile: VoiceProfileStatus { voice }

    public var settings: Settings {
        Settings(
            mode: mode,
            cliBackendEnabled: cliEnabled,
            cliBackendPath: cliPath,
            cliBackendKind: cliKind,
            cleanupBackend: cleanupBackend,
            talkKey: talkKeyChoice
        )
    }

    public var consentPrompt: ConsentPrompt? { nil }

    public var isSetupComplete: Bool { effectiveRecognizerAvailable }

    public var setupMessage: String? {
        effectiveRecognizerAvailable ? nil : MenuMessages.noRecognizer
    }

    // MARK: - Hold-to-talk

    private func matchesTalkKey(_ side: CommandSide) -> Bool {
        switch talkKeyChoice {
        case .rightCommand: return side == .right
        case .leftCommand: return side == .left
        case .eitherCommand: return true
        }
    }

    private func beginHold(side: CommandSide, othersDown: [KeyIdentity], at time: Duration) {
        guard latchOn, !faulted, !insertDisarmed else { return }
        guard micPermission == .granted, isSetupComplete else { return }
        guard !screenLocked, !sleeping, !lidClosed else { return }
        guard matchesTalkKey(side) else { return }
        guard othersDown.isEmpty else { return }

        ignoreBackgroundCleanup()
        if cleanupBackend == .gateway, gatewayCleaner != nil { sentenceTracker = SentenceTracker() }
        talkKeyDown = true
        pending = nil
        var blocked: String?
        if isCallApp(frontmost) {
            blocked = MenuMessages.callPaused
        } else if micOwnerHolds {
            blocked = MenuMessages.otherMic
        } else if hardwareMuted {
            blocked = MenuMessages.muted
        } else if isSecureFocus {
            blocked = MenuMessages.secure
        }

        capture = HoldCapture(
            startedAt: time,
            focusAtDown: focus,
            text: "",
            hasSpeech: false,
            lastSpeechEnd: time,
            blockedMessage: blocked
        )
        if let blocked {
            panelState = PanelState(isVisible: true, text: blocked)
        } else {
            panelState = PanelState(isVisible: true, text: MenuMessages.panelListening)
        }
    }

    private func endHold(side: CommandSide, at time: Duration) {
        guard matchesTalkKey(side) else { return }
        guard talkKeyDown, let hold = capture else {
            talkKeyDown = false
            return
        }
        talkKeyDown = false
        capture = nil

        if !latchOn || faulted || insertDisarmed {
            ignoreBackgroundCleanup()
            panelState = .hidden
            return
        }
        if let blocked = hold.blockedMessage {
            ignoreBackgroundCleanup()
            panelState = PanelState(isVisible: true, text: blocked)
            return
        }

        let held = time - hold.startedAt
        let trailing = hold.hasSpeech ? time - hold.lastSpeechEnd : held
        // A release that arrives only after a idle gap following speech is not a
        // completed hold (covers sub-300 ms holds and a release that is not adjacent
        // to the speech that was captured).
        if held < .milliseconds(300) || !hold.hasSpeech || Cleanup.isLoneMutter(hold.text)
            || (hold.hasSpeech && trailing >= .milliseconds(299))
        {
            ignoreBackgroundCleanup()
            panelState = .hidden
            wipeBuffers()
            return
        }

        finishUtterance(hold: hold, releaseAt: time, maxLength: false)
    }

    private func cancelHold(hidePanel: Bool) {
        talkKeyDown = false
        capture = nil
        if hidePanel {
            panelState = .hidden
        }
        ignoreRunningLLM()
        deferred = nil
    }

    private func cancelForOtherKey(_ identity: KeyIdentity) {
        if let hold = capture, !hold.text.isEmpty, !(hold.focusAtDown.map(Self.isSecure) ?? false) {
            utteranceRecords.append(UtteranceRecord(
                timestamp: Date(), raw: hold.text, tokenized: SpokenMarkup.tokenize(hold.text), cleaned: "",
                backend: "none", latencyMs: 0, fieldRole: hold.focusAtDown?.role ?? .none,
                target: hold.focusAtDown?.identity, insertIndex: nil, autoSendAllowed: false, cancelled: true))
        }
        talkKeyDown = false
        capture = nil
        panelState = .hidden
        deferred = nil
        ignoreRunningLLM()
        if identity != .escape, let kind = keyKind(for: identity) {
            emittedKeyEvents.append(EmittedKeyEvent(kind: kind))
        }
    }

    private func keyKind(for identity: KeyIdentity) -> KeyKind? {
        switch identity {
        case .escape:
            return .escape
        case .character(let character):
            return .character(character)
        case .shortcut(let name):
            return .shortcut(name)
        case .modifier(let name):
            return .shortcut(name)
        case .command:
            return nil
        }
    }

    private func finishUtterance(hold: HoldCapture, releaseAt: Duration, maxLength: Bool) {
        guard !isSecureFocus, !(hold.focusAtDown.map(Self.isSecure) ?? false) else {
            ignoreRunningLLM()
            deferred = nil
            panelState = PanelState(isVisible: true, text: MenuMessages.secure)
            wipeBuffers()
            return
        }
        gatewayJob?.ignore()
        gatewayJob = nil
        commitGeneration += 1
        let generation = commitGeneration
        releaseTimes[generation] = releaseAt
        releaseFocuses[generation] = focus
        let raw = hold.text
        let isLong = sentenceTracker?.isLong == true
        let incremental = sentenceTracker?.releasePlan(raw: raw)
        let local = Cleanup.clean(raw)
        let focusShot = hold.focusAtDown
        releaseFocus = focusShot

        if cleanupBackend == .gateway, !plugins.isEmpty,
           let match = TriggerMatcher.match(raw, plugins: plugins) {
            ignoreRunningLLM()
            deferred = nil
            apply(DeferredCommit(
                due: releaseAt,
                generation: generation,
                raw: raw,
                text: nil,
                target: focusShot?.identity,
                replacesSelection: false,
                strippedNewline: false,
                panel: .hidden,
                overlay: .empty,
                insert: false,
                maxLengthNote: maxLength,
                command: match,
                routed: true
            ))
            return
        }

        if cleanupBackend == .gateway, let gatewayCleaner {
            ignoreRunningLLM()
            let job = GatewayJob(generation: generation)
            gatewayJob = job
            deferred = DeferredCommit(
                due: releaseAt + gatewayCleaner.timeout,
                generation: generation,
                raw: raw,
                text: nil,
                target: focusShot?.identity,
                replacesSelection: false,
                strippedNewline: false,
                panel: .hidden,
                overlay: .empty,
                insert: false,
                maxLengthNote: maxLength
            )
            deferred?.incremental = incremental
            deferred?.routesPlugins = !isLong
            panelState = PanelState(
                isVisible: true,
                text: maxLength ? MenuMessages.panelMaxLength : MenuMessages.panelCleaning
            )
            let requestRaw = incremental?.raw ?? raw
            if requestRaw.isEmpty {
                job.complete(.reply("")) // All sentences already have accepted gateway replies.
            } else {
                gatewayCleaner.cleanWithResult(requestRaw, plugins: isLong ? [] : plugins) { [job] result in
                    job.complete(result)
                }
            }
            // A transport may finish synchronously. Pick that up before returning;
            // asynchronous replies are collected on this queue by the timer.
            evaluateTimers()
            return
        }

        if cleanupBackend != .gateway, cleanupBackend != .off, let path = cleanupExecutablePath, !path.isEmpty,
           cleanupBackend != .localModel || cleanupExecutablePath != nil
        {
            if cleanupBackend == .localModel && (cleanupExecutablePath ?? "").isEmpty {
                scheduleLocal(
                    raw: raw,
                    local: local,
                    focus: focusShot,
                    releaseAt: releaseAt,
                    generation: generation,
                    maxLength: maxLength,
                    delayMs: 200
                )
                return
            }
            panelState = PanelState(
                isVisible: true,
                text: maxLength ? MenuMessages.panelMaxLength : MenuMessages.panelCleaning
            )
            let outcome = startLLM(path: path, raw: raw, generation: generation)
            switch outcome {
            case .accepted(let text):
                scheduleResolved(
                    raw: raw,
                    cleaned: text,
                    focus: focusShot,
                    releaseAt: releaseAt,
                    generation: generation,
                    maxLength: maxLength,
                    delayMs: 100
                )
            case .rejected:
                scheduleLocal(
                    raw: raw,
                    local: local,
                    focus: focusShot,
                    releaseAt: releaseAt,
                    generation: generation,
                    maxLength: maxLength,
                    delayMs: 100
                )
            case .unavailable:
                if !cliUnavailableNoted {
                    showCLIUnavailable = true
                    cliUnavailableNoted = true
                }
                scheduleLocal(
                    raw: raw,
                    local: local,
                    focus: focusShot,
                    releaseAt: releaseAt,
                    generation: generation,
                    maxLength: maxLength,
                    delayMs: 100
                )
            case .pending:
                deferred = nil
                llmJob?.ignored = false
                // Due 4 seconds after release, or sooner if the process exits.
                deferred = DeferredCommit(
                    due: releaseAt + .seconds(4),
                    generation: generation,
                    raw: raw,
                    text: nil,
                    target: focusShot?.identity,
                    replacesSelection: false,
                    strippedNewline: false,
                    panel: .hidden,
                    overlay: .empty,
                    insert: false,
                    maxLengthNote: maxLength
                )
            }
            return
        }

        scheduleLocal(
            raw: raw,
            local: local,
            focus: focusShot,
            releaseAt: releaseAt,
            generation: generation,
            maxLength: maxLength,
            delayMs: 200
        )
    }

    private enum LLMOutcome {
        case accepted(String)
        case rejected
        case unavailable
        case pending
    }

    private func startLLM(path: String, raw: String, generation: Int) -> LLMOutcome {
        cliInvocations.append(
            CLIInvocation(
                executablePath: path,
                arguments: [],
                stdinText: raw,
                containedAudioPayload: false
            )
        )
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        let inPipe = Pipe()
        let outPipe = Pipe()
        process.standardInput = inPipe
        process.standardOutput = outPipe
        process.standardError = Pipe()
        let job = LLMJob(generation: generation)
        job.process = process
        job.stdout = outPipe
        llmJob = job
        do {
            try process.run()
            if let data = raw.data(using: .utf8) {
                try inPipe.fileHandleForWriting.write(contentsOf: data)
            }
            try inPipe.fileHandleForWriting.close()
        } catch {
            llmJob = nil
            return .unavailable
        }

        // A cold process start (shell, interpreter, CLI auth) routinely takes longer than a
        // few hundred milliseconds on macOS. Wait a bounded real-time grace so a quick result
        // is picked up synchronously; anything slower is collected by evaluateTimers or times out.
        let deadline = Date().addingTimeInterval(Self.llmSynchronousGrace)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.005)
        }
        if process.isRunning {
            return .pending
        }
        job.finished = true
        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        job.output = output
        guard process.terminationStatus == 0 else { return .unavailable }
        if let accepted = acceptLLMResult(raw: raw, result: output) {
            return .accepted(accepted)
        }
        return .rejected
    }

    private func acceptLLMResult(raw: String, result: String) -> String? {
        var text = result.trimmingCharacters(in: .whitespacesAndNewlines)
        let pairs: [(Character, Character)] = [("\"", "\""), ("'", "'"), ("“", "”")]
        var stripped = true
        while stripped {
            stripped = false
            for (open, close) in pairs {
                if text.first == open, text.last == close, text.count >= 2 {
                    text = String(text.dropFirst().dropLast())
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    stripped = true
                }
            }
        }
        if text.isEmpty { return nil }
        if text.count > raw.count * 2 + 40 { return nil }
        let lower = text.lowercased()
        if lower.hasPrefix("here is") || lower.hasPrefix("sure") { return nil }
        return text
    }

    private func scheduleLocal(
        raw: String,
        local: String,
        focus: FocusSnapshot?,
        releaseAt: Duration,
        generation: Int,
        maxLength: Bool,
        delayMs: Int
    ) {
        let resolved = resolveOutput(raw: raw, cleaned: local, focus: focus)
        deferred = DeferredCommit(
            due: releaseAt + .milliseconds(delayMs),
            generation: generation,
            raw: raw,
            text: resolved.text,
            target: resolved.target,
            replacesSelection: resolved.replaces,
            strippedNewline: resolved.strippedNewline,
            panel: resolved.panel,
            overlay: resolved.overlay,
            insert: resolved.insert,
            maxLengthNote: maxLength
        )
        deferred?.allowSend = resolved.allowSend
        panelState = PanelState(
            isVisible: true,
            text: maxLength ? MenuMessages.panelMaxLength : MenuMessages.panelCleaning
        )
        evaluateTimers()
    }

    private func scheduleResolved(
        raw: String,
        cleaned: String,
        focus: FocusSnapshot?,
        releaseAt: Duration,
        generation: Int,
        maxLength: Bool,
        delayMs: Int
    ) {
        let resolved = resolveOutput(raw: raw, cleaned: cleaned, focus: focus)
        deferred = DeferredCommit(
            due: releaseAt + .milliseconds(delayMs),
            generation: generation,
            raw: raw,
            text: resolved.text,
            target: resolved.target,
            replacesSelection: resolved.replaces,
            strippedNewline: resolved.strippedNewline,
            panel: resolved.panel,
            overlay: resolved.overlay,
            insert: resolved.insert,
            maxLengthNote: maxLength
        )
        deferred?.allowSend = resolved.allowSend
        panelState = PanelState(
            isVisible: true,
            text: maxLength ? MenuMessages.panelMaxLength : MenuMessages.panelCleaning
        )
        evaluateTimers()
    }

    private struct ResolvedOutput {
        var text: String
        var target: FocusIdentity?
        var replaces: Bool
        var strippedNewline: Bool
        var panel: PanelState
        var overlay: OverlayState
        var insert: Bool
        var allowSend = true
    }

    private func resolveOutput(raw: String, cleaned: String, focus: FocusSnapshot?) -> ResolvedOutput {
        let decision = SendIntent.decide(raw: raw, text: cleaned)
        var out = resolveOutputCore(raw: raw, cleaned: decision.text, focus: focus)
        out.allowSend = decision.allowSend
        return out
    }

    private func resolveOutputCore(raw: String, cleaned: String, focus: FocusSnapshot?) -> ResolvedOutput {
        if !accessibilityGranted {
            return ResolvedOutput(
                text: cleaned, target: nil, replaces: false, strippedNewline: false,
                panel: .hidden, overlay: .empty, insert: false
            )
        }
        // R306: an invented subtitle credit is never inserted or offered for copying.
        if Cleanup.isSilenceHallucination(Cleanup.wordTokens(raw))
            || Cleanup.isSilenceHallucination(Cleanup.wordTokens(cleaned)) {
            return ResolvedOutput(
                text: "", target: nil, replaces: false, strippedNewline: false,
                panel: .hidden, overlay: .empty, insert: false
            )
        }
        guard let focus else {
            return ResolvedOutput(
                text: cleaned,
                target: nil,
                replaces: false,
                strippedNewline: false,
                panel: PanelState(
                    isVisible: true,
                    text: MenuMessages.panelNoField,
                    buttons: [OverlayButton(title: "Copy")],
                    copyText: cleaned
                ),
                overlay: .empty,
                insert: false
            )
        }
        let editable: Bool
        switch focus.role {
        case .textField, .textArea, .comboBox, .terminal, .editableWebArea:
            editable = true
        default:
            editable = false
        }
        if !editable || !focus.exists {
            let message = focus.exists ? MenuMessages.panelNoField : MenuMessages.insertFailed
            return ResolvedOutput(
                text: cleaned,
                target: nil,
                replaces: false,
                strippedNewline: false,
                panel: PanelState(
                    isVisible: true,
                    text: message,
                    buttons: [OverlayButton(title: "Copy")],
                    copyText: cleaned
                ),
                overlay: OverlayState(text: message, buttons: [OverlayButton(title: "Copy")]),
                insert: false
            )
        }
        if Cleanup.isLoneMutter(raw) || cleaned.isEmpty {
            return ResolvedOutput(
                text: "", target: nil, replaces: false, strippedNewline: false,
                panel: .hidden, overlay: .empty, insert: false
            )
        }
        if focus.selectionLength > 80 || focus.selectionContainsLineBreak {
            return ResolvedOutput(
                text: cleaned,
                target: nil,
                replaces: false,
                strippedNewline: false,
                panel: PanelState(isVisible: true, text: MenuMessages.selectionKept),
                overlay: OverlayState(text: MenuMessages.selectionKept),
                insert: false
            )
        }

        var text = cleaned
        var stripped = false
        let hadNewline = raw.contains("\n") || cleaned.contains("\n")
        switch focus.role {
        case .textField, .terminal, .comboBox:
            if hadNewline {
                text = text.replacingOccurrences(of: "\n", with: " ")
                while text.contains("  ") {
                    text = text.replacingOccurrences(of: "  ", with: " ")
                }
                text = text.trimmingCharacters(in: .whitespaces)
                stripped = true
            }
        default:
            break
        }
        if let prev = focus.precedingCharacter, !prev.isWhitespace, !text.hasPrefix(" ") {
            text = " " + text
        }
        let replaces = focus.selectionLength > 0 && focus.selectionLength <= 80
            && !focus.selectionContainsLineBreak
        let overlay = stripped
            ? OverlayState(text: MenuMessages.newlineStripped)
            : OverlayState.empty
        return ResolvedOutput(
            text: text,
            target: focus.identity,
            replaces: replaces,
            strippedNewline: stripped,
            panel: .hidden,
            overlay: overlay,
            insert: true
        )
    }

    private func ignoreRunningLLM() {
        llmJob?.ignored = true
        llmJob = nil
        gatewayJob?.ignore()
        gatewayJob = nil
        ignoreBackgroundCleanup()
    }

    private func ignoreBackgroundCleanup() {
        for job in backgroundJobs.values { job.mailbox.ignore() }
        backgroundJobs.removeAll()
        sentenceTracker = nil
    }

    private func evaluateBackgroundCleanup() {
        guard talkKeyDown, let hold = capture, hold.blockedMessage == nil,
              cleanupBackend == .gateway, let cleaner = gatewayCleaner,
              let tracker = sentenceTracker else { return }
        // Only mailboxes cross the transport boundary. Revision checks and panel
        // updates happen here, on the same queue as all other Session events.
        for (revision, job) in backgroundJobs {
            if clock.now >= job.due {
                job.mailbox.ignore()
                backgroundJobs.removeValue(forKey: revision)
            } else if case .completed(let reply) = job.mailbox.snapshot() {
                if case .reply(let text) = reply, let accepted = acceptLLMResult(raw: revision.text, result: text) {
                    tracker.accept(accepted, for: revision)
                }
                job.mailbox.ignore()
                backgroundJobs.removeValue(forKey: revision)
            }
        }
        while backgroundJobs.count < 2, let revision = tracker.nextRevision {
            tracker.markSent(revision)
            let mailbox = GatewayJob(generation: commitGeneration)
            backgroundJobs[revision] = BackgroundJob(mailbox: mailbox, due: clock.now + cleaner.timeout)
            cleaner.cleanSentence(revision.text) { [mailbox] result in mailbox.complete(result) }
            // Collect synchronous transports too, without waiting for another
            // partial or using a transport callback to mutate Session.
            if case .completed(let reply) = mailbox.snapshot() {
                if case .reply(let text) = reply, let accepted = acceptLLMResult(raw: revision.text, result: text) {
                    tracker.accept(accepted, for: revision)
                }
                mailbox.ignore()
                backgroundJobs.removeValue(forKey: revision)
            }
        }
        if !hold.text.isEmpty { panelState = PanelState(isVisible: true, text: tracker.panelText) }
    }

    // MARK: - Timers

    private func evaluateTimers() {
        evaluateBackgroundCleanup()
        if let deadline = pendingCloseDeadline, !latchOn, deviceStillOpenAfterOff {
            if clock.now >= deadline {
                faulted = true
                faultReason = "Microphone did not close in time."
                insertDisarmed = true
                pendingCloseDeadline = nil
            }
        }

        if latchOn, clock.now >= .seconds(8 * 3600) {
            resumeMicOpen = true
        }

        if talkKeyDown, let hold = capture, hold.blockedMessage == nil,
           clock.now >= hold.startedAt + .seconds(120)
        {
            let snapshot = hold
            talkKeyDown = false
            capture = nil
            finishUtterance(hold: snapshot, releaseAt: snapshot.startedAt + .seconds(120), maxLength: true)
        }

        if let pending = pendingCommand, clock.now >= pending.due {
            pendingCommand = nil
            commandRequests.append(pending.request)
        }

        if let job = gatewayJob, let pendingCommit = deferred,
           pendingCommit.generation == job.generation, pendingCommit.text == nil {
            if clock.now >= pendingCommit.due {
                job.ignore()
                gatewayJob = nil
                if !llmTimeoutNoted {
                    showLLMTimeout = true
                    llmTimeoutNoted = true
                }
                applyGatewayResultToDeferred(.timeout)
            } else if case .completed(let result) = job.snapshot() {
                job.ignore()
                gatewayJob = nil
                applyGatewayResultToDeferred(result)
            }
        }

        if let job = llmJob, !job.ignored, !job.finished, let process = job.process, !process.isRunning {
            job.finished = true
            let data = job.stdout?.fileHandleForReading.readDataToEndOfFile() ?? Data()
            job.output = String(data: data, encoding: .utf8) ?? ""
            if let deferred, deferred.generation == job.generation, deferred.text == nil {
                applyLLMJobToDeferred(job)
            }
        }

        if var job = deferred, clock.now >= job.due {
            if job.text == nil, let llm = llmJob, llm.generation == job.generation {
                if llm.finished, !llm.ignored {
                    applyLLMJobToDeferred(llm)
                    job = deferred ?? job
                } else if !llm.finished {
                    llm.ignored = true
                    if !llmTimeoutNoted {
                        showLLMTimeout = true
                        llmTimeoutNoted = true
                    }
                    let local = Cleanup.clean(job.raw)
                    let focusShot = focusForDeferred(job)
                    let resolved = resolveOutput(raw: job.raw, cleaned: local, focus: focusShot)
                    job.text = resolved.text
                    job.target = resolved.target
                    job.replacesSelection = resolved.replaces
                    job.strippedNewline = resolved.strippedNewline
                    job.panel = resolved.panel
                    job.overlay = resolved.overlay
                    job.insert = resolved.insert
                    job.allowSend = resolved.allowSend
                }
            }
            apply(job)
            if deferred?.generation == job.generation {
                deferred = nil
            }
        }

        guard let utterance = pending else { return }
        guard utterance.isFinal else { return }
        guard utterance.focusAtAccept != nil else { return }
        let readyAt = utterance.lastSpeechEnd + .milliseconds(900)
        // A single jump far past the endpoint drops speech that was never held.
        if clock.now > readyAt + .milliseconds(500) {
            pending = nil
            return
        }
        guard clock.now >= readyAt else { return }
        pending = nil
        commitLegacy(utterance)
    }

    private func focusForDeferred(_ job: DeferredCommit) -> FocusSnapshot? {
        _ = job
        return releaseFocus
    }

    private func applyGatewayResultToDeferred(_ result: GatewayCleaner.CleanupResult) {
        guard var pendingCommit = deferred else { return }
        let reply: String?
        switch result {
        case .reply(let text):
            reply = text
            pendingCommit.cleanupOutcome = "rejected"
        case .timeout:
            reply = nil
            pendingCommit.cleanupOutcome = "timeout"
        case .error:
            reply = nil
            pendingCommit.cleanupOutcome = "error"
        }
        var output = reply
        if let reply, !plugins.isEmpty, pendingCommit.routesPlugins {
            pendingCommit.routed = true
            switch CommandRouter.parse(reply, plugins: plugins) {
            case .command(let match):
                pendingCommit.command = match
                // Keep a short cleanup interval for cancellable gateway commands,
                // even with a synchronous reply. Zero-delay commands skip it.
                let released = releaseTimes[pendingCommit.generation] ?? clock.now
                let delay = plugins.first(where: { $0.name == match.plugin })?.confirmDelaySeconds ?? 1.5
                pendingCommit.due = delay == 0 ? clock.now : max(clock.now, released + .milliseconds(250))
                deferred = pendingCommit
                return
            case .dictation(let text):
                output = text
            }
        }
        let cleaned: String
        if let plan = pendingCommit.incremental {
            let accepted = output.flatMap { acceptLLMResult(raw: plan.raw, result: $0) }
            let resolved = plan.joined(reply: accepted)
            cleaned = resolved.text
            pendingCommit.usedGateway = resolved.usedGateway
            if resolved.usedReply || (plan.raw.isEmpty && !plan.cleaned.isEmpty) {
                pendingCommit.cleanupOutcome = "gateway"
            }
        } else {
            let accepted = output.flatMap { acceptLLMResult(raw: pendingCommit.raw, result: $0) }
            cleaned = accepted ?? Cleanup.clean(pendingCommit.raw)
            if accepted != nil {
                pendingCommit.usedGateway = true
                pendingCommit.cleanupOutcome = "gateway"
            }
        }
        let resolved = resolveOutput(raw: pendingCommit.raw, cleaned: cleaned,
                                     focus: storedFocus(for: pendingCommit))
        pendingCommit.text = resolved.text
        pendingCommit.target = resolved.target
        pendingCommit.replacesSelection = resolved.replaces
        pendingCommit.strippedNewline = resolved.strippedNewline
        pendingCommit.panel = resolved.panel
        pendingCommit.overlay = resolved.overlay
        pendingCommit.insert = resolved.insert
        pendingCommit.allowSend = resolved.allowSend
        pendingCommit.due = min(pendingCommit.due, clock.now)
        deferred = pendingCommit
    }

    private func applyLLMJobToDeferred(_ job: LLMJob) {
        guard var pendingCommit = deferred, pendingCommit.generation == job.generation else { return }
        let output = job.output ?? ""
        let statusOK = job.process?.terminationStatus == 0
        let focusShot = storedFocus(for: pendingCommit)
        if statusOK, let accepted = acceptLLMResult(raw: pendingCommit.raw, result: output) {
            let resolved = resolveOutput(raw: pendingCommit.raw, cleaned: accepted, focus: focusShot)
            pendingCommit.text = resolved.text
            pendingCommit.target = resolved.target
            pendingCommit.replacesSelection = resolved.replaces
            pendingCommit.strippedNewline = resolved.strippedNewline
            pendingCommit.panel = resolved.panel
            pendingCommit.overlay = resolved.overlay
            pendingCommit.insert = resolved.insert
            pendingCommit.allowSend = resolved.allowSend
            pendingCommit.due = min(pendingCommit.due, clock.now)
        } else {
            if !cliUnavailableNoted && !statusOK {
                showCLIUnavailable = true
                cliUnavailableNoted = true
            }
            let local = Cleanup.clean(pendingCommit.raw)
            let resolved = resolveOutput(raw: pendingCommit.raw, cleaned: local, focus: focusShot)
            pendingCommit.text = resolved.text
            pendingCommit.target = resolved.target
            pendingCommit.replacesSelection = resolved.replaces
            pendingCommit.strippedNewline = resolved.strippedNewline
            pendingCommit.panel = resolved.panel
            pendingCommit.overlay = resolved.overlay
            pendingCommit.insert = resolved.insert
            pendingCommit.allowSend = resolved.allowSend
        }
        deferred = pendingCommit
    }

    /// Focus captured at key-down is stored on the deferred commit via target identity;
    /// selection details live on the hold snapshot copied into `releaseFocus`.
    private var releaseFocus: FocusSnapshot?

    private func storedFocus(for job: DeferredCommit) -> FocusSnapshot? {
        if let releaseFocus, releaseFocus.identity == job.target || job.target == nil {
            return releaseFocus
        }
        return releaseFocus
    }

    private static func isSecure(_ focus: FocusSnapshot) -> Bool {
        focus.isSecureInput || focus.role == .secureTextField
    }

    private func recordUtterance(_ job: DeferredCommit, insertIndex: Int?) {
        let focus = releaseFocuses.removeValue(forKey: job.generation) ?? releaseFocus
        if let focus, Self.isSecure(focus) { return }
        let raw = job.raw
        guard !raw.isEmpty else { return }
        let cleaned = job.command == nil ? (job.text ?? "") : ""
        var backend = job.usedGateway && job.command == nil ? "gateway" : "local"
        if !job.usedGateway, job.command == nil {
            switch cleanupBackend {
            case .cursorCLI, .claudeCLI, .grokCLI:
                let squash = { (t: String) in t.filter { !$0.isWhitespace } }
                let local = SendIntent.decide(raw: raw, text: Cleanup.clean(raw)).text
                if squash(local) != squash(cleaned) {
                    backend = "cli"
                }
            default: break
            }
        }
        let released = releaseTimes.removeValue(forKey: job.generation) ?? clock.now
        let c = (clock.now - released).components
        let ms = max(0, Int(c.seconds * 1000 + c.attoseconds / 1_000_000_000_000_000))
        utteranceRecords.append(UtteranceRecord(
            timestamp: Date(), raw: raw, tokenized: SpokenMarkup.tokenize(raw), cleaned: cleaned,
            backend: backend, cleanupOutcome: job.command == nil ? job.cleanupOutcome : "local",
            latencyMs: ms, fieldRole: focus?.role ?? .none, target: job.target,
            insertIndex: insertIndex, autoSendAllowed: job.command == nil && job.allowSend, cancelled: false,
            mode: job.command == nil ? "dictation" : "command", plugin: job.command?.plugin))
    }

    private func apply(_ original: DeferredCommit) {
        var job = original
        let focusNow = releaseFocuses[job.generation] ?? releaseFocus
        let secure = focusNow.map(Self.isSecure) ?? false
        if secure {
            job.command = nil
        } else if job.command == nil, !job.routed, !plugins.isEmpty {
            job.command = TriggerMatcher.match(job.raw, plugins: plugins)
        }
        if let match = job.command, let plugin = plugins.first(where: { $0.name == match.plugin }) {
            recordUtterance(job, insertIndex: nil)
            if plugin.needsSelection, (focusNow?.selectionLength ?? 0) <= 0 {
                pendingCommand = nil
                overlayState = .empty
                panelState = PanelState(isVisible: true, text: "Select some text first.")
                return
            }
            let request = CommandRequest(plugin: plugin, args: match.args, transcript: job.raw,
                                         target: focusNow.flatMap { $0.exists && $0.role != .none ? $0.identity : nil },
                                         selectedText: !secure && (focusNow?.selectionLength ?? 0) > 0
                                             ? focusNow?.selectedText : nil)
            let due = job.due + .seconds(plugin.confirmDelaySeconds)
            if clock.now >= due {
                pendingCommand = nil
                commandRequests.append(request)
            } else {
                pendingCommand = (request, due)
            }
            overlayState = .empty
            panelState = PanelState(isVisible: true, text: "Running: \(plugin.name)")
            return
        }
        job.command = nil
        insertCountBeforeApply = insertRequests.count
        defer {
            let idx = insertRequests.count > insertCountBeforeApply ? insertRequests.count - 1 : nil
            recordUtterance(job, insertIndex: idx)
        }
        if showCLIUnavailable {
            // Leave the note observable until the next commit starts.
        }
        if job.insert, let text = job.text, let target = job.target, accessibilityGranted, latchOn, !insertDisarmed {
            if showCLIUnavailable {
                showCLIUnavailable = false
            }
            insertRequests.append(
                InsertRequest(text: text, target: target, replacesSelection: job.replacesSelection,
                              autoSendAllowed: job.allowSend && SpeechGate.isMeaningfulText(text))
            )
            overlayState = job.overlay
            if job.maxLengthNote {
                panelState = PanelState(isVisible: true, text: MenuMessages.panelMaxLength)
            } else {
                panelState = .hidden
            }
        } else {
            if job.maxLengthNote {
                panelState = PanelState(isVisible: true, text: MenuMessages.panelMaxLength)
            } else {
                panelState = job.panel
            }
            if job.overlay.text != nil {
                overlayState = job.overlay
            }
        }
        wipeBuffers()
        releaseFocus = nil
    }

    private func commitLegacy(_ utterance: PendingUtterance) {
        guard latchOn, !faulted, !insertDisarmed else { return }
        guard micPermission == .granted else { return }
        guard accessibilityGranted else { return }
        guard !isPausedForExternal else { return }
        guard !isSecureFocus else { return }
        guard let focus, isEditableFocus else { return }
        guard let accepted = utterance.focusAtAccept, focus.identity == accepted else { return }
        guard utterance.hasSpeechFrames else { return }

        let raw = utterance.text
        if Cleanup.isLoneMutter(raw) {
            wipeBuffers()
            return
        }
        if focus.selectionLength > 80 || focus.selectionContainsLineBreak {
            overlayState = OverlayState(text: MenuMessages.selectionKept)
            wipeBuffers()
            return
        }

        if showCLIUnavailable {
            showCLIUnavailable = false
        }

        var cleaned = Cleanup.clean(raw)
        if cleaned.isEmpty {
            wipeBuffers()
            return
        }

        if cliEnabled {
            if let path = cliPath {
                if let cliResult = invokeCLISync(path: path, text: raw) {
                    let trimmed = cliResult.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        cleaned = trimmed
                    }
                } else if !cliUnavailableNoted {
                    showCLIUnavailable = true
                    cliUnavailableNoted = true
                }
            } else if !cliUnavailableNoted {
                showCLIUnavailable = true
                cliUnavailableNoted = true
            }
        }

        var text = cleaned
        var strippedNewline = false
        let hadNewline = raw.contains("\n") || cleaned.contains("\n")
        switch focus.role {
        case .textField, .terminal, .comboBox:
            if hadNewline {
                text = text.replacingOccurrences(of: "\n", with: " ")
                while text.contains("  ") {
                    text = text.replacingOccurrences(of: "  ", with: " ")
                }
                text = text.trimmingCharacters(in: .whitespaces)
                strippedNewline = true
            }
        default:
            break
        }
        if let prev = focus.precedingCharacter, !prev.isWhitespace, !text.hasPrefix(" ") {
            text = " " + text
        }
        let replaces = focus.selectionLength > 0 && focus.selectionLength <= 80
            && !focus.selectionContainsLineBreak
        insertRequests.append(
            InsertRequest(text: text, target: focus.identity, replacesSelection: replaces)
        )
        if strippedNewline {
            overlayState = OverlayState(text: MenuMessages.newlineStripped)
        } else if overlayState.text != MenuMessages.insertFailed {
            overlayState = .empty
        }
        wipeBuffers()
    }

    private func invokeCLISync(path: String, text: String) -> String? {
        cliInvocations.append(
            CLIInvocation(
                executablePath: path,
                arguments: [],
                stdinText: text,
                containedAudioPayload: false
            )
        )
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        let inPipe = Pipe()
        let outPipe = Pipe()
        process.standardInput = inPipe
        process.standardOutput = outPipe
        process.standardError = Pipe()
        do {
            try process.run()
            if let data = text.data(using: .utf8) {
                try inPipe.fileHandleForWriting.write(contentsOf: data)
            }
            try inPipe.fileHandleForWriting.close()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = outPipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }

    private func composeMenuText() -> String {
        if !isSetupComplete {
            return MenuMessages.noRecognizer
        }
        if faulted {
            return MenuMessages.off + " " + (faultReason ?? "Fault.")
        }
        if micPermission == .denied || micPermission == .revoked {
            if latchOn || micPermission == .revoked {
                return MenuMessages.refused
            }
        }
        if !latchOn {
            return MenuMessages.off
        }
        if !accessibilityGranted {
            return MenuMessages.accessibilityMissing
        }
        if !inputMonitoringGranted {
            return MenuMessages.needsInputMonitoring
        }
        if isCallApp(frontmost) {
            return MenuMessages.callPaused
        }
        if micOwnerHolds {
            return MenuMessages.otherMic
        }
        if hardwareMuted {
            return MenuMessages.muted
        }
        if isSecureFocus {
            return MenuMessages.secure
        }
        if talkKeyDown, capture?.blockedMessage == nil, isEditableFocus {
            return MenuMessages.listeningHold
        }

        var parts: [String] = []
        if isEditableFocus {
            parts.append(MenuMessages.ready)
        } else {
            parts.append(MenuMessages.readyToTalk)
        }
        if showBundledUnavailable && !bundledModelLoadable && systemRecognizerOnDevice {
            parts.append(MenuMessages.bundledUnavailable)
        }
        if showCLIUnavailable {
            parts.append(MenuMessages.cliUnavailable)
        }
        if showLLMTimeout {
            parts.append(MenuMessages.llmTimedOut)
        }
        return parts.joined(separator: " ")
    }

    // MARK: - Helpers

    private var effectiveRecognizerAvailable: Bool {
        if !onDeviceRecognizerAvailable { return false }
        if bundledModelLoadable { return true }
        return systemRecognizerOnDevice
    }

    private var canListen: Bool {
        latchOn && micPermission == .granted && !faulted && isSetupComplete
            && !screenLocked && !sleeping && !lidClosed
    }

    private var isPausedForExternal: Bool {
        micOwnerHolds || isCallApp(frontmost) || hardwareMuted
    }

    private var isEditableFocus: Bool {
        guard let focus else { return false }
        switch focus.role {
        case .textField, .textArea, .comboBox, .terminal, .editableWebArea:
            return true
        default:
            return false
        }
    }

    private var isSecureFocus: Bool {
        guard let focus else { return false }
        return focus.role == .secureTextField || focus.isSecureInput
    }

    /// Continuous-listen entry points arm the mic; a bare focus change does not.
    private func callsiteMentions(_ marker: String) -> Bool {
        Thread.callStackSymbols.contains { $0.contains(marker) }
    }

    private func isCallApp(_ app: FrontmostApp?) -> Bool {
        guard let app else { return false }
        return app.callKind != .none
    }

    private func shouldDropForEnergy(_ sample: EnergySample) -> Bool {
        if sample.isBuiltInMic {
            return sample.energyDb <= sample.noiseFloorDb
        }
        return sample.energyDb < sample.noiseFloorDb + 12
    }

    private func wipeBuffers() {
        bufferWiped = true
        preRollMs = 0
    }
}

public enum MenuMessages {
    static let listening = "Dictation is listening. Click a text field to type."
    static let off = "Dictation is off. The microphone is closed."
    static let ready = "Dictation is on. This field will receive speech."
    static let readyToTalk = "Dictation is ready. Hold left Command in a text field to talk."
    static let listeningHold = "Dictation is listening."
    static let refused = "Dictation is on but the microphone is blocked. Nothing is listening."
    static let secure = "Dictation skips secure fields."
    static let callPaused = "On — paused for a call"
    static let otherMic = "Dictation is paused while the other app has the microphone."
    static let muted = "Dictation is paused while the microphone is muted."
    static let selectionKept = "Selection kept. Click where the words should go."
    static let insertFailed = "Heard you. Could not type into this field."
    public static let insertSwitchedField = "Not inserted: you switched to a different field. Copy it instead."
    static let newlineStripped = "Newline stays out of this field."
    static let cliUnavailable = "CLI cleanup unavailable; using local cleanup."
    static let accessibilityMissing = "Dictation can't type: Accessibility permission is missing."
    static let noRecognizer =
        "This Mac has no on-device recognizer. Dictation needs one. Cloud speech is not used."
    static let bundledUnavailable = "Using macOS on-device speech (bundled model unavailable)."
    static let needsInputMonitoring = "Dictation needs Input Monitoring to detect the talk key."
    static let panelListening = "Listening…"
    static let panelCleaning = "Cleaning up…"
    static let panelNoField = "No text field was focused."
    static let panelMaxLength = "Maximum length reached."
    static let llmTimedOut = "LLM cleanup timed out; used local cleanup."
}
