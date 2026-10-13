import Foundation
import XCTest
import DictationCore

enum MenuText {
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
    static let readyToTalk = "Dictation is ready. Hold right Command in a text field to talk."
    static let listeningHold = "Dictation is listening."
    static let needsInputMonitoring = "Dictation needs Input Monitoring to detect the talk key."
    static let panelListening = "Listening…"
    static let panelCleaning = "Cleaning up…"
    static let panelNoField = "No text field was focused."
    static let panelMaxLength = "Maximum length reached."
    static let llmTimedOut = "LLM cleanup timed out; used local cleanup."
}

final class TestHarness {
    let clock: FakeClock
    let workingDirectory: URL
    let session: Session
    let fieldIdentity: FocusIdentity

    init(
        fieldIdentity: FocusIdentity = FocusIdentity(pid: 42, elementID: "field-1")
    ) throws {
        clock = FakeClock()
        workingDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("dictation-core-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
        session = Session(
            clock: clock,
            paths: SessionPaths(workingDirectory: workingDirectory)
        )
        self.fieldIdentity = fieldIdentity

        session.setMicPermission(.granted)
        session.setAccessibilityPermission(true)
        session.setInputMonitoringPermission(true)
        session.setOnDeviceRecognizerAvailable(true)
        session.setSystemRecognizerReportsOnDevice(true)
        session.setBundledModelLoadable(true)
    }

    deinit {
        try? FileManager.default.removeItem(at: workingDirectory)
    }

    func focusEditable(
        role: FieldRole = .textField,
        selectionLength: Int = 0,
        selectionContainsLineBreak: Bool = false,
        precedingCharacter: Character? = nil,
        secure: Bool = false,
        identity: FocusIdentity? = nil
    ) {
        session.ingestFocus(
            FocusSnapshot(
                timestamp: clock.now,
                role: role,
                isSecureInput: secure,
                selectionLength: selectionLength,
                selectionContainsLineBreak: selectionContainsLineBreak,
                precedingCharacter: precedingCharacter,
                identity: identity ?? fieldIdentity
            )
        )
    }

    func clearFocus() {
        session.ingestFocus(
            FocusSnapshot(
                timestamp: clock.now,
                role: .none,
                identity: .none
            )
        )
    }

    func latchOn() {
        session.setLatch(.on)
    }

    func latchOff() {
        session.setLatch(.off)
    }

    func readyListening() {
        latchOn()
        focusEditable()
    }

    /// Speak `text` as speech-flagged tokens, then advance past endpoint silence + repair hold.
    func speakAndWait(
        _ text: String,
        speechDuration: Duration = .milliseconds(500),
        isSpeech: Bool = true,
        confidence: Double = 1.0,
        language: String? = "en"
    ) {
        let start = clock.now
        clock.advance(by: speechDuration)
        let end = clock.now
        session.ingestRecognizerTokens([
            RecognizerToken(
                text: text,
                start: start,
                end: end,
                isSpeech: isSpeech,
                confidence: confidence,
                language: language,
                isFinal: true
            ),
        ])
        clock.advance(by: .milliseconds(400 + 500))
    }

    /// Speak without advancing through the full commit wait.
    func speakOnly(
        _ text: String,
        speechDuration: Duration = .milliseconds(500),
        isSpeech: Bool = true
    ) {
        let start = clock.now
        clock.advance(by: speechDuration)
        let end = clock.now
        session.ingestRecognizerTokens([
            RecognizerToken(
                text: text,
                start: start,
                end: end,
                isSpeech: isSpeech,
                isFinal: true
            ),
        ])
    }

    func advanceSilenceAndHold() {
        clock.advance(by: .milliseconds(400 + 500))
    }

    func pressTalkKey(
        side: CommandSide = .right,
        otherKeysAlreadyDown: [KeyIdentity] = []
    ) {
        session.ingestTalkKey(
            TalkKeyEvent(
                timestamp: clock.now,
                identity: .command(side),
                isDown: true,
                otherKeysAlreadyDown: otherKeysAlreadyDown
            )
        )
    }

    func releaseTalkKey(side: CommandSide = .right) {
        session.ingestTalkKey(
            TalkKeyEvent(
                timestamp: clock.now,
                identity: .command(side),
                isDown: false
            )
        )
    }

    func pressOtherKey(_ identity: KeyIdentity) {
        session.ingestTalkKey(
            TalkKeyEvent(
                timestamp: clock.now,
                identity: identity,
                isDown: true
            )
        )
    }

    /// Tokens delivered while a hold is expected to be active. Does not advance the endpoint timer.
    func speakWhileHeld(
        _ text: String,
        speechDuration: Duration = .milliseconds(500),
        isFinal: Bool = true,
        isSpeech: Bool = true
    ) {
        let start = clock.now
        clock.advance(by: speechDuration)
        session.ingestRecognizerTokens([
            RecognizerToken(
                text: text,
                start: start,
                end: clock.now,
                isSpeech: isSpeech,
                isFinal: isFinal
            ),
        ])
    }

    func frontmostNotes() {
        session.ingestFrontmostApp(
            FrontmostApp(timestamp: clock.now, bundleID: "com.apple.Notes", callKind: .none)
        )
    }

    /// Installs a fake CLI executable that records stdin and echoes `result` after `delayMs`.
    @discardableResult
    func installFakeCLI(
        result: String,
        delayMs: Int = 0,
        name: String = "fake-cli",
        exitCode: Int = 0
    ) throws -> URL {
        let scriptURL = workingDirectory.appendingPathComponent(name)
        let logURL = workingDirectory.appendingPathComponent("\(name).log")
        let script = """
        #!/bin/sh
        log="\(logURL.path)"
        echo "ARGS:$*" >> "$log"
        cat >> "$log"
        echo "" >> "$log"
        if [ "\(delayMs)" -gt 0 ]; then
          # FakeClock drives Session; sleep is real wall time for process handoff only.
          sleep $(awk "BEGIN { print \(delayMs)/1000 }")
        fi
        printf '%s' '\(result.replacingOccurrences(of: "'", with: "'\\''"))'
        exit \(exitCode)
        """
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: scriptURL.path
        )
        return scriptURL
    }

    func fakeCLILog(name: String = "fake-cli") -> String {
        let logURL = workingDirectory.appendingPathComponent("\(name).log")
        return (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
    }

    func filesUnderWorkingDirectory() throws -> [URL] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: workingDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        var files: [URL] = []
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey])
            if values.isRegularFile == true {
                files.append(url)
            }
        }
        return files
    }

    /// Safe access after a count assertion — XCTest on Linux continues past failures.
    func firstInsert(
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> InsertRequest? {
        guard let insert = session.insertRequests.first else {
            XCTFail("expected at least one insert request", file: file, line: line)
            return nil
        }
        return insert
    }

    func insert(
        at index: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> InsertRequest? {
        guard session.insertRequests.indices.contains(index) else {
            XCTFail(
                "expected insert at index \(index), have \(session.insertRequests.count)",
                file: file,
                line: line
            )
            return nil
        }
        return session.insertRequests[index]
    }
}

extension Duration {
    static func hours(_ value: Int) -> Duration {
        .seconds(value * 3600)
    }
}
