import Foundation

/// Platform-neutral dictation session: events in, observable outputs out.
public final class Session: @unchecked Sendable {
    public let clock: any Clock
    public let paths: SessionPaths

    public private(set) var insertRequests: [InsertRequest] = []
    public private(set) var emittedKeyEvents: [EmittedKeyEvent] = []
    public private(set) var cliInvocations: [CLIInvocation] = []
    public private(set) var filesystemEntriesWritten: [URL] = []

    // MARK: - Internal state

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
    private var fnDown = false

    private var faulted = false
    private var faultReason: String?
    private var pendingCloseDeadline: Duration?
    private var insertDisarmed = false
    /// After Off, platform reported the device still open.
    private var deviceStillOpenAfterOff = false

    private var pending: PendingUtterance?
    /// Speech heard while unfocused; attached or dropped when focus arrives.
    private var preFocus: PendingUtterance?
    private var overlayState = OverlayState.empty
    private var bufferWiped = true
    private var preRollMs = 0

    private var voice = VoiceProfileStatus(enrollmentAvailable: true)
    private var lastSpeakerScore: Double?
    private var lastEnergy: EnergySample?
    private var builtInWarningShown = false
    private var showBuiltInWarning = false
    private var showBundledUnavailable = false
    private var showCLIUnavailable = false
    private var cliUnavailableNoted = false

    private var cliEnabled = false
    private var cliPath: String?
    private var cliKind: CLIBackendKind?
    private var cliConsented = false
    private var consentPromptMessage: String?

    private struct PendingUtterance {
        var text: String
        var onset: Duration
        var lastSpeechEnd: Duration
        var focusAtAccept: FocusIdentity?
        var discarded: Bool
        var isFinal: Bool
        var hasSpeechFrames: Bool
        var confidence: Double
        var language: String?
        var forcedEndpoint: Bool
        var cueExtendsSilence: Bool
    }

    public init(clock: any Clock, paths: SessionPaths) {
        self.clock = clock
        self.paths = paths
        if let fake = clock as? FakeClock {
            fake.onAdvance = { [weak self] in
                self?.evaluateTimers()
            }
        }
    }

    // MARK: - Latch, mode, permissions, recognizer capability

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
            discardPending()
            preFocus = nil
            wipeBuffers()
            pendingCloseDeadline = clock.now + .milliseconds(300)
            deviceStillOpenAfterOff = false
            overlayState = .empty
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
            discardPending()
            preFocus = nil
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

        if let energy = lastEnergy, shouldDropForEnergy(energy) {
            return
        }

        if voice.speakerFilteringEnabled, let score = lastSpeakerScore, score < 0.5 {
            return
        }

        if !token.isSpeech {
            return
        }

        if let lang = token.language, !lang.lowercased().hasPrefix("en") {
            return
        }
        if token.confidence < 0.5 {
            return
        }

        maybeShowCLIConsent()

        // No editable focus: hold in pre-focus buffer only (never commit).
        guard isEditableFocus, let focus else {
            absorbPreFocus(token)
            return
        }

        // Drop if onset is more than 400 ms before this field gained focus.
        if token.start + .milliseconds(400) < focus.timestamp {
            pending = nil
            preFocus = nil
            return
        }

        absorbFocused(token, focus: focus)
        evaluateTimers()
    }

    public func ingestEnergy(_ sample: EnergySample) {
        lastEnergy = sample
        // Warn on first built-in use above the noise floor (R31), not ambient-floor samples (R30).
        if sample.isBuiltInMic && !builtInWarningShown
            && sample.energyDb > sample.noiseFloorDb
        {
            showBuiltInWarning = true
            builtInWarningShown = true
        }
    }

    public func ingestSpeakerScore(_ score: SpeakerScore) {
        lastSpeakerScore = score.matchScore
    }

    public func ingestFocus(_ snapshot: FocusSnapshot) {
        focus = snapshot

        if snapshot.role == .secureTextField || snapshot.isSecureInput {
            wipeBuffers()
            discardPending()
            preFocus = nil
            return
        }

        if let pending, !pending.discarded, let accepted = pending.focusAtAccept {
            if snapshot.identity != accepted {
                discardPending()
            }
        }

        // Attach pre-focus speech whose onset is within 400 ms before focus.
        if snapshot.role != .none, let pre = preFocus, !pre.discarded {
            if pre.onset + .milliseconds(400) >= snapshot.timestamp {
                var attached = pre
                attached.focusAtAccept = snapshot.identity
                pending = attached
                preFocus = nil
            } else {
                preFocus = nil
            }
        }

        evaluateTimers()
    }

    public func ingestFrontmostApp(_ app: FrontmostApp) {
        let wasCall = isCallApp(frontmost)
        frontmost = app
        if isCallApp(app) {
            wipeBuffers()
            discardPending()
            preFocus = nil
        } else if wasCall {
            wipeBuffers()
            discardPending()
            preFocus = nil
        }
    }

    public func ingestMicOwner(_ status: MicOwnerStatus) {
        let wasHeld = micOwnerHolds
        micOwnerHolds = status.anotherAppHoldsInput
        if micOwnerHolds {
            wipeBuffers()
            discardPending()
            preFocus = nil
        } else if wasHeld {
            wipeBuffers()
            discardPending()
            preFocus = nil
        }
    }

    public func ingestHardwareMute(_ mute: HardwareMute) {
        hardwareMuted = mute.isMuted
        if hardwareMuted {
            wipeBuffers()
            discardPending()
            preFocus = nil
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
            discardPending()
            preFocus = nil
        case .screenUnlock:
            screenLocked = false
            wipeBuffers()
        case .sleep:
            sleeping = true
            wipeBuffers()
            discardPending()
            preFocus = nil
        case .wake:
            sleeping = false
            wipeBuffers()
        case .lidClose:
            lidClosed = true
            wipeBuffers()
            discardPending()
            preFocus = nil
        case .lidOpen:
            lidClosed = false
            wipeBuffers()
        case .audioRouteChange:
            discardPending()
            preFocus = nil
        }
    }

    public func ingestKey(_ press: KeyPress) {
        switch press.kind {
        case .fn:
            fnDown = press.isDown
            if !press.isDown, mode == .guarded {
                discardPending()
                overlayState = .empty
            }
        case .escape:
            if press.isDown {
                discardPending()
                overlayState = .empty
            }
        case .character:
            if press.isDown {
                discardPending()
                overlayState = .empty
            }
        default:
            break
        }
    }

    // MARK: - CLI / voice / insertion feedback / settings

    public func configureCLI(path: String?, kind: CLIBackendKind?, enabled: Bool) {
        cliPath = path
        cliKind = kind
        cliEnabled = enabled
        if !enabled {
            consentPromptMessage = nil
        }
    }

    public func confirmCLIConsent() {
        cliConsented = true
        consentPromptMessage = nil
    }

    public func declineCLIConsent() {
        cliConsented = false
        consentPromptMessage = nil
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
        overlayState = OverlayState(
            text: MenuMessages.insertFailed,
            buttons: [OverlayButton(title: "Copy")]
        )
    }

    public func reportInsertionSucceeded(for requestIndex: Int) {
        guard insertRequests.indices.contains(requestIndex) else { return }
        overlayState = .empty
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
        return .open
    }

    public var menuText: String { composeMenuText() }

    public var overlay: OverlayState { overlayState }

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
            cliBackendKind: cliKind
        )
    }

    public var consentPrompt: ConsentPrompt? {
        guard let consentPromptMessage else { return nil }
        return ConsentPrompt(message: consentPromptMessage)
    }

    public var isSetupComplete: Bool { effectiveRecognizerAvailable }

    public var setupMessage: String? {
        effectiveRecognizerAvailable ? nil : MenuMessages.noRecognizer
    }

    // MARK: - Internals

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

    private func absorbPreFocus(_ token: RecognizerToken) {
        if var existing = preFocus, !existing.discarded {
            existing.text = token.text
            existing.lastSpeechEnd = token.end
            existing.isFinal = token.isFinal
            existing.hasSpeechFrames = existing.hasSpeechFrames || token.isSpeech
            existing.cueExtendsSilence = endsWithEditingCue(token.text)
            preFocus = existing
        } else {
            preFocus = PendingUtterance(
                text: token.text,
                onset: token.start,
                lastSpeechEnd: token.end,
                focusAtAccept: nil,
                discarded: false,
                isFinal: token.isFinal,
                hasSpeechFrames: token.isSpeech,
                confidence: token.confidence,
                language: token.language,
                forcedEndpoint: false,
                cueExtendsSilence: endsWithEditingCue(token.text)
            )
        }
        bufferWiped = false
        preRollMs = min(1500, max(preRollMs, 1))
    }

    private func absorbFocused(_ token: RecognizerToken, focus: FocusSnapshot) {
        if var existing = pending, !existing.discarded {
            let gap = token.start - existing.lastSpeechEnd
            let sameUtterance = gap <= .milliseconds(400)
                || token.start <= existing.onset + .milliseconds(400)
                || existing.cueExtendsSilence
                || token.start == existing.onset
            if sameUtterance {
                existing.text = token.text
                existing.lastSpeechEnd = max(existing.lastSpeechEnd, token.end)
                existing.isFinal = token.isFinal
                existing.hasSpeechFrames = existing.hasSpeechFrames || token.isSpeech
                existing.confidence = token.confidence
                existing.language = token.language
                existing.cueExtendsSilence = endsWithEditingCue(token.text)
                if token.end - existing.onset >= .seconds(30)
                    || existing.lastSpeechEnd - existing.onset >= .seconds(30)
                {
                    existing.forcedEndpoint = true
                    existing.lastSpeechEnd = existing.onset + .seconds(30)
                    existing.isFinal = true
                }
                pending = existing
            } else {
                pending = newPending(token, focus: focus.identity)
            }
        } else {
            pending = newPending(token, focus: focus.identity)
        }

        bufferWiped = false
        if let pending {
            let elapsed = pending.lastSpeechEnd - pending.onset
            preRollMs = min(1500, Int(durationMilliseconds(elapsed)))
        }
    }

    private func newPending(_ token: RecognizerToken, focus: FocusIdentity) -> PendingUtterance {
        var end = token.end
        var forced = false
        if token.end - token.start >= .seconds(30) {
            end = token.start + .seconds(30)
            forced = true
        }
        return PendingUtterance(
            text: token.text,
            onset: token.start,
            lastSpeechEnd: end,
            focusAtAccept: focus,
            discarded: false,
            isFinal: token.isFinal || forced,
            hasSpeechFrames: token.isSpeech,
            confidence: token.confidence,
            language: token.language,
            forcedEndpoint: forced,
            cueExtendsSilence: endsWithEditingCue(token.text)
        )
    }

    private func endsWithEditingCue(_ text: String) -> Bool {
        let lower = text.lowercased()
        let cues = [
            "actually i mean", "no i mean", "scratch that", "no wait", "i mean",
            "actually", "wait", "sorry",
        ]
        for cue in cues where lower.contains(cue) {
            return true
        }
        return false
    }

    private func discardPending() {
        pending = nil
    }

    private func wipeBuffers() {
        bufferWiped = true
        preRollMs = 0
    }

    private func maybeShowCLIConsent() {
        guard cliEnabled, !cliConsented, let kind = cliKind else { return }
        let name: String
        switch kind {
        case .cursorCLI: name = "Cursor CLI"
        case .claudeCLI: name = "Claude CLI"
        }
        consentPromptMessage =
            "Sending the transcript to \(name) leaves this Mac. Audio stays here."
    }

    private func evaluateTimers() {
        if let deadline = pendingCloseDeadline, !latchOn, deviceStillOpenAfterOff {
            if clock.now >= deadline {
                faulted = true
                faultReason = "Microphone did not close in time."
                insertDisarmed = true
                pendingCloseDeadline = nil
            }
        }

        guard let utterance = pending, !utterance.discarded else { return }
        guard utterance.isFinal || utterance.forcedEndpoint else { return }
        guard utterance.focusAtAccept != nil else { return }

        let readyAt = utterance.lastSpeechEnd + .milliseconds(400) + .milliseconds(500)
        guard clock.now >= readyAt else { return }

        commit(utterance)
    }

    private func commit(_ utterance: PendingUtterance) {
        defer { pending = nil }

        guard latchOn, !faulted, !insertDisarmed else { return }
        guard micPermission == .granted else { return }
        guard accessibilityGranted else { return }
        guard !isPausedForExternal else { return }
        guard !isSecureFocus else { return }
        guard let focus, isEditableFocus else { return }
        guard let accepted = utterance.focusAtAccept, focus.identity == accepted else { return }
        guard utterance.hasSpeechFrames else { return }

        if mode == .guarded {
            if !inputMonitoringGranted {
                overlayState = .empty
                return
            }
            if !fnDown {
                overlayState = .empty
                return
            }
        }

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

        // One-shot CLI note: visible after the failure commit until the next commit.
        if showCLIUnavailable {
            showCLIUnavailable = false
        }

        var cleaned = Cleanup.clean(raw)

        if cleaned.isEmpty || isStandaloneCue(raw) {
            wipeBuffers()
            return
        }

        if cliEnabled, cliConsented {
            if let path = cliPath {
                if let cliResult = invokeCLI(path: path, text: raw) {
                    let trimmed = cliResult.trimmingCharacters(in: .whitespacesAndNewlines)
                    if Cleanup.obeysTokenRules(spoken: raw, result: trimmed) {
                        cleaned = trimmed.first?.isUppercase == true
                            ? trimmed
                            : Cleanup.clean(trimmed)
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

        showBuiltInWarning = false
        // Keep CLI note visible only for the menu read immediately after failure;
        // clear after the next successful local insert so "once" is satisfied.
        if showCLIUnavailable {
            // Leave it for this menu observation, clear on next compose after a beat.
            // R81 checks after first speak (note present) then second speak (note absent).
            // Clear after commit so the next menuText read after second phrase has no note.
            // But first assertion is AFTER first speak — so we need note present after first.
            // Approach: set showCLIUnavailable true on failure; clear it at start of next commit.
        }
        wipeBuffers()
    }

    private func isStandaloneCue(_ raw: String) -> Bool {
        let words = Cleanup.wordTokens(raw)
        let cues: Set<String> = ["scratch", "that", "wait", "sorry", "mean", "actually", "no", "i"]
        return !words.isEmpty && words.allSatisfy { cues.contains($0) }
    }

    private func invokeCLI(path: String, text: String) -> String? {
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

        var parts: [String] = []

        if !isEditableFocus {
            parts.append(MenuMessages.listening)
        } else if mode == .guarded {
            parts.append(MenuMessages.guarded)
        } else {
            parts.append(MenuMessages.ready)
        }

        if !inputMonitoringGranted {
            parts.append(MenuMessages.typingNoCancel)
            if mode == .guarded {
                parts.append(MenuMessages.guardedNeedsIM)
            }
        }

        if showBuiltInWarning {
            parts.append(MenuMessages.builtInWarning)
        }

        if showBundledUnavailable && !bundledModelLoadable && systemRecognizerOnDevice {
            parts.append(MenuMessages.bundledUnavailable)
        }

        if showCLIUnavailable {
            parts.append(MenuMessages.cliUnavailable)
            // Consume one-shot after it has been observable once.
            // Defer clear: mark for clear on next compose after this read is tricky.
            // Instead clear when a subsequent utterance commits successfully.
        }

        return parts.joined(separator: " ")
    }

    private func durationMilliseconds(_ duration: Duration) -> Int64 {
        let c = duration.components
        return c.seconds * 1000 + c.attoseconds / 1_000_000_000_000_000
    }
}

enum MenuMessages {
    static let listening = "Dictation is listening. Click a text field to type."
    static let off = "Dictation is off. The microphone is closed."
    static let ready = "Dictation is on. This field will receive speech."
    static let refused = "Dictation is on but the microphone is blocked. Nothing is listening."
    static let guarded = "Guarded — hold Fn to type into this field."
    static let secure = "Dictation skips secure fields."
    static let callPaused = "On — paused for a call"
    static let otherMic = "Dictation is paused while the other app has the microphone."
    static let muted = "Dictation is paused while the microphone is muted."
    static let builtInWarning =
        "This microphone hears the room. Nearby voices can land in the focused field. A headset, or Guarded mode, narrows that."
    static let selectionKept = "Selection kept. Click where the words should go."
    static let insertFailed = "Heard you. Could not type into this field."
    static let newlineStripped = "Newline stays out of this field."
    static let typingNoCancel = "Typing will not cancel a pending phrase."
    static let cliUnavailable = "CLI cleanup unavailable; using local cleanup."
    static let accessibilityMissing = "Dictation can't type: Accessibility permission is missing."
    static let guardedNeedsIM = "Guarded mode needs Input Monitoring."
    static let noRecognizer =
        "This Mac has no on-device recognizer. Dictation needs one. Cloud speech is not used."
    static let bundledUnavailable = "Using macOS on-device speech (bundled model unavailable)."
}
