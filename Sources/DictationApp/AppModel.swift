import AVFoundation
import AppKit
import ApplicationServices
import CoreGraphics
import DictationCore
import DictationMac
import Foundation

/// Owns the core session and every Mac adapter. All session access happens on `work`.
final class AppModel: ObservableObject {
    @Published var enabled = false
    @Published var autoSendEnabled = true
    @Published var saveDictations = UserDefaults.standard.object(forKey: "saveDictationsForTuning") as? Bool ?? true
    private lazy var corpus = CorpusLogger(enabled: saveDictations)
    @Published var statusSymbol = "mic.slash"
    @Published var menuTitle = "Dictation Off"
    @Published var coreMenuText = ""
    @Published var cleanupLabel = "Cleanup: local rules"
    @Published var speechLabel = ""
    @Published var permissions = PermissionReport(granted: [], needsSpeechRecognition: false)
    @Published var tapRunning = false
    @Published var panel = PanelState.hidden
    @Published var pluginList: [PluginSpec] = []
    @Published var pluginErrors: [String: String] = [:]
    private var commandsHandled = 0
    private let pluginQueue = DispatchQueue(label: "dictation.plugins", qos: .userInitiated)

    private let work = DispatchQueue(label: "dictation.session")
    private let clock: QueueClock
    private let session: Session
    private let toggle: ToggleController
    private let pipeline: HoldPipeline
    private let insertion: InsertionCoordinator
    private let mic = MicrophoneCapture()
    private let ax = AccessibilityBridge()
    private let usesAppleSpeech: Bool
    private var tap: KeyboardTap?
    private var partialTimer: DispatchSourceTimer?
    private var lastPartial = Date.distantPast
    private let panelController = FloatingPanelController()

    init() {
        let support = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Dictation")
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("dictation-chunks", isDirectory: true)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        clock = QueueClock(queue: work)
        session = Session(clock: clock, paths: SessionPaths(workingDirectory: support))
        toggle = ToggleController(session: session)

        let transcriber: SpeechTranscriber
        if let found = WhisperTranscriber.locate(executables: WhisperTranscriber.defaultExecutables,
                                                  model: WhisperTranscriber.defaultModel()) {
            transcriber = WhisperTranscriber(executable: found.executable, model: found.model, scratchDirectory: scratch)
            usesAppleSpeech = false
        } else {
            transcriber = AppleSpeechTranscriber()
            usesAppleSpeech = true
        }
        let available = !usesAppleSpeech || (transcriber as? AppleSpeechTranscriber)?.isAvailable == true
        pipeline = HoldPipeline(session: session, clock: clock, audio: mic, transcriber: transcriber, focus: ax)
        insertion = InsertionCoordinator(session: session, inserter: ax)
        insertion.autoSend = AutoSendPolicy.load()
        autoSendEnabled = insertion.autoSend?.enabled ?? true
        speechLabel = "Speech: " + transcriber.name

        let report = PermissionProbe.current(needsSpeechRecognition: usesAppleSpeech)
        let gatewayConfig = GatewayConfig.load(from: GatewayConfig.defaultPath)
        let cleanupSelection = CleanupSelection.defaultSelection(gatewayConfig: gatewayConfig)
        cleanupLabel = cleanupSelection.menuLabel
        permissions = report
        work.sync {
            session.setOnDeviceRecognizerAvailable(available)
            session.setSystemRecognizerReportsOnDevice(true)
            session.setBundledModelLoadable(!usesAppleSpeech)
            session.setTalkKey(.leftCommand)
            if let gatewayConfig {
                session.setGatewayCleaner(GatewayCleaner(config: gatewayConfig))
                session.setCleanupBackend(.gateway)
            } else {
                session.setCleanupBackend(.localModel)
            }
            applyPermissions(report)
            toggle.setEnabled(true)
        }
        try? FileManager.default.createDirectory(at: PluginLoader.defaultDirectory, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        try? BundledPlugins.install(into: PluginLoader.defaultDirectory)
        reloadPlugins()
        pipeline.beforeHold = { [weak self] in self?.refreshCallState() }
        pipeline.onChange = { [weak self] in self?.afterSessionChange() }
        clock.observeAdvances { [weak self] in self?.afterSessionChange() }
        panelController.onButton = { [weak self] title in
            self?.work.async { self?.insertion.tap(button: title) }
        }
        startTap()
        publish()
        requestMissingPermissions()
    }

    /// Asks macOS for permissions that are still undecided so the system prompts appear
    /// (the probe never prompts, and the mic gate blocks the hold before audio starts).
    private func requestMissingPermissions() {
        if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] _ in
                DispatchQueue.main.async { self?.refreshPermissions() }
            }
        }
        if !CGPreflightListenEventAccess() { _ = CGRequestListenEventAccess() }
        if !AXIsProcessTrusted() {
            let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(opts)
        }
        // Pick up grants made in System Settings without a relaunch.
        Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] t in
            guard let self else { t.invalidate(); return }
            let before = self.permissions
            self.refreshPermissions()
            if self.permissions.missing.isEmpty && before.missing.isEmpty { t.invalidate() }
        }
    }

    // MARK: Actions

    func reloadPlugins() {
        let result = PluginLoader.load(directory: PluginLoader.defaultDirectory)
        work.async { self.session.setPlugins(result.plugins) }
        DispatchQueue.main.async {
            self.pluginList = result.plugins
            self.pluginErrors = result.errors
        }
    }

    func setPlugin(_ name: String, enabled: Bool) {
        try? PluginLoader.setEnabled(enabled, plugin: name, directory: PluginLoader.defaultDirectory)
        reloadPlugins()
    }

    func openPluginsFolder() {
        NSWorkspace.shared.activateFileViewerSelecting([PluginLoader.defaultDirectory])
    }

    /// On `work`: run commands that passed the cancel window (R232/R234), off the session queue.
    private func runPendingCommands() {
        let requests = session.commandRequests
        while commandsHandled < requests.count {
            let index = commandsHandled
            let request = requests[index]
            commandsHandled += 1
            var context: [String: String] = [
                "transcript": request.transcript,
                "timestamp": ISO8601DateFormatter().string(from: Date()),
            ]
            if let pid = request.target?.pid,
               let bundle = NSRunningApplication(processIdentifier: pid_t(pid))?.bundleIdentifier {
                context["frontmost_app"] = bundle
            } else if let bundle = NSWorkspace.shared.frontmostApplication?.bundleIdentifier {
                context["frontmost_app"] = bundle
            }
            context["display_id"] = String(CGMainDisplayID())
            pluginQueue.async { [weak self] in
                let result = PluginRunner.run(request.plugin, args: request.args, context: context)
                NSLog("Dictation plugin %@ exit %d", request.plugin.name, result.exitCode)
                guard let self else { return }
                self.work.async {
                    if result.exitCode == 0 {
                        self.session.ingestPluginResult(for: index, output: result.output ?? PluginOutput(insert: nil, notify: nil, send: nil))
                    } else if result.exitCode == 2 {
                        self.session.ingestPluginResult(for: index, output: PluginOutput(insert: request.transcript, notify: nil, send: false))
                    } else {
                        self.session.ingestPluginFailure(for: index, message: result.errorLine ?? "exit \(result.exitCode)")
                    }
                    self.afterSessionChange()
                }
            }
        }
    }

    func setSaveDictations(_ on: Bool) {
        saveDictations = on
        UserDefaults.standard.set(on, forKey: "saveDictationsForTuning")
        work.async { self.corpus.enabled = on }
    }

    func revealCorpusFolder() {
        let dir = CorpusLogger.defaultDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        NSWorkspace.shared.activateFileViewerSelecting([dir])
    }

    func setAutoSend(_ on: Bool) {
        autoSendEnabled = on
        UserDefaults.standard.set(on, forKey: AutoSendPolicy.enabledKey)
        let policy = AutoSendPolicy.load()
        work.async { [self] in insertion.autoSend = policy }
    }

    func toggleEnabled() {
        work.async { [self] in
            toggle.toggle()
            afterSessionChange()
        }
    }

    func refreshPermissions() {
        let report = PermissionProbe.current(needsSpeechRecognition: usesAppleSpeech)
        work.async { [self] in applyPermissions(report) }
        permissions = report
        if !tapRunning { startTap() }
    }

    func open(_ kind: PermissionKind) {
        NSWorkspace.shared.open(kind.settingsURL)
    }

    func rechooseCleanup() {
        cleanupLabel = "Cleanup: choosing…"
        chooseCleanup(support: FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Dictation"))
    }

    // MARK: Wiring

    private func startTap() {
        let tap = KeyboardTap(clock: clock) { [weak self] output in
            guard let self else { return }
            self.work.async {
                if output == .toggle {
                    self.toggle.toggle()
                    self.afterSessionChange()
                } else {
                    self.pipeline.handle(output)
                    self.updatePartialTimer()
                }
            }
        }
        tapRunning = tap.start()
        self.tap = tapRunning ? tap : nil
    }

    private func chooseCleanup(support: URL) {
        let selector = CleanupCLISelector(
            searchDirectories: CleanupCLISelector.defaultSearchDirectories(),
            wrapperDirectory: support.appendingPathComponent("cleanup"),
            probeTimeout: 20)
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let selection = selector.select()
            guard let self else { return }
            self.work.async {
                self.session.setCleanupBackend(selection.backend, executablePath: selection.executablePath)
            }
            DispatchQueue.main.async { self.cleanupLabel = selection.menuLabel }
        }
    }

    private func applyPermissions(_ report: PermissionReport) {
        session.setAccessibilityPermission(report.granted.contains(.accessibility))
        session.setInputMonitoringPermission(report.granted.contains(.inputMonitoring))
        session.setMicPermission(report.granted.contains(.microphone) ? .granted : .denied)
    }

    /// On `work`: refresh the call state before a hold so calls block it (M13).
    private func refreshCallState() {
        let running = NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)
        let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
        let kind = CallDetector.activeCall(runningBundleIDs: running,
                                           micInUseElsewhere: CallDetector.defaultInputIsRunningSomewhere())
        session.ingestFrontmostApp(FrontmostApp(timestamp: clock.now, bundleID: front, callKind: kind))
    }

    /// On `work`: stream partial transcripts about every 0.8 s while capturing.
    private func updatePartialTimer() {
        if pipeline.isCapturing, partialTimer == nil {
            let t = DispatchSource.makeTimerSource(queue: work)
            t.schedule(deadline: .now() + .milliseconds(800), repeating: .milliseconds(800))
            t.setEventHandler { [weak self] in
                guard let self else { return }
                if self.pipeline.isCapturing {
                    self.pipeline.partialTick()
                } else {
                    self.partialTimer?.cancel()
                    self.partialTimer = nil
                }
            }
            partialTimer = t
            t.resume()
        } else if !pipeline.isCapturing {
            partialTimer?.cancel()
            partialTimer = nil
        }
    }

    /// On `work`: deliver inserts, then publish UI state.
    private func afterSessionChange() {
        insertion.poll()
        corpus.poll(session: session, coordinator: insertion)
        runPendingCommands()
        updatePartialTimer()
        publish()
    }

    private func publish() {
        let state = (toggle.isEnabled, toggle.statusSymbolName, toggle.menuTitle, session.menuText, session.panel)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.enabled != state.0 { self.enabled = state.0 }
            if self.statusSymbol != state.1 { self.statusSymbol = state.1 }
            if self.menuTitle != state.2 { self.menuTitle = state.2 }
            if self.coreMenuText != state.3 { self.coreMenuText = state.3 }
            if self.panel != state.4 {
                self.panel = state.4
                self.panelController.show(state.4)
            }
        }
    }
}
