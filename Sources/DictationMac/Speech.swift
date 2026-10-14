import DictationCore
import Foundation

/// Batch speech-to-text over in-memory 16 kHz-ish mono samples.
public protocol SpeechTranscriber: AnyObject {
    var name: String { get }
    /// Returns the transcript, "" for silence, or nil when recognition failed.
    func transcribe(samples: [Float], sampleRate: Double) -> String?
}

/// Live microphone samples held only in memory.
public protocol AudioSource: AnyObject {
    var sampleRate: Double { get }
    func start() throws
    func stop()
    /// Everything captured since the last `start()`.
    func snapshot() -> [Float]
}

/// Reports the focused element for the core.
public protocol FocusProvider: AnyObject {
    func currentFocus(at time: Duration) -> FocusSnapshot
}

/// 16-bit PCM mono WAV encoding.
public enum WAVEncoder {
    public static func encode(samples: [Float], sampleRate: Int) -> Data {
        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        let byteCount = samples.count * 2
        data.append(contentsOf: Array("RIFF".utf8))
        append(UInt32(36 + byteCount))
        data.append(contentsOf: Array("WAVEfmt ".utf8))
        append(UInt32(16))
        append(UInt16(1))
        append(UInt16(1))
        append(UInt32(sampleRate))
        append(UInt32(sampleRate * 2))
        append(UInt16(2))
        append(UInt16(16))
        data.append(contentsOf: Array("data".utf8))
        append(UInt32(byteCount))
        data.reserveCapacity(data.count + byteCount)
        for sample in samples {
            let clipped = max(-1, min(1, sample))
            append(Int16(clipped * Float(Int16.max)))
        }
        return data
    }

    /// Linear resampling to the target rate.
    public static func resample(_ samples: [Float], from source: Double, to target: Double) -> [Float] {
        guard source != target, source > 0, !samples.isEmpty else { return samples }
        let ratio = source / target
        let count = Int(Double(samples.count) / ratio)
        var out = [Float](repeating: 0, count: count)
        for i in 0..<count {
            let pos = Double(i) * ratio
            let j = Int(pos)
            let frac = Float(pos - Double(j))
            let a = samples[min(j, samples.count - 1)]
            let b = samples[min(j + 1, samples.count - 1)]
            out[i] = a + (b - a) * frac
        }
        return out
    }
}

/// whisper.cpp via whisper-cli. Each call writes one transient WAV chunk in
/// `scratchDirectory` and deletes it as soon as whisper exits (M7).
public final class WhisperTranscriber: SpeechTranscriber {
    public let executable: URL
    public let model: URL
    public let scratchDirectory: URL
    public var timeout: TimeInterval = 30
    public var name: String { "whisper.cpp (\(model.lastPathComponent))" }

    public init(executable: URL, model: URL, scratchDirectory: URL) {
        self.executable = executable
        self.model = model
        self.scratchDirectory = scratchDirectory
    }

    /// Model choice: `defaults write com.edmundmunday.dictation.hand whisperModel <file or path>`,
    /// else small.en (q5_1, ~+0.35 s over base on an M-series Air, more accurate), else base.en.
    public static func defaultModel() -> URL {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Dictation/models")
        if let configured = UserDefaults.standard.string(forKey: "whisperModel"), !configured.isEmpty {
            return configured.hasPrefix("/") ? URL(fileURLWithPath: configured)
                : dir.appendingPathComponent(configured)
        }
        let preferred = dir.appendingPathComponent("ggml-small.en-q5_1.bin")
        if FileManager.default.fileExists(atPath: preferred.path) { return preferred }
        return dir.appendingPathComponent("ggml-base.en.bin")
    }

    /// Vocabulary hint passed as whisper's initial prompt; override with the `whisperPrompt` default
    /// (empty string disables it).
    public var initialPrompt: String = UserDefaults.standard.string(forKey: "whisperPrompt")
        ?? "Edmund dictating notes and messages: note, notes, gateway, Grok, Grok Bot, Grok Build, Claude, Codex, MacBook, Origin, worker, dictation."

    public static let defaultExecutables: [URL] = [
        URL(fileURLWithPath: "/opt/homebrew/bin/whisper-cli"),
        URL(fileURLWithPath: "/usr/local/bin/whisper-cli"),
    ]

    /// The first executable that exists, plus the model, or nil when either is missing.
    public static func locate(executables: [URL], model: URL) -> (executable: URL, model: URL)? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: model.path) else { return nil }
        guard let exe = executables.first(where: { fm.isExecutableFile(atPath: $0.path) }) else { return nil }
        return (exe, model)
    }

    public static func parseOutput(_ output: String) -> String {
        var pieces: [String] = []
        for line in output.split(whereSeparator: \.isNewline) {
            var text = String(line)
            if text.hasPrefix("["), let close = text.range(of: "]"), text.contains("-->") {
                text = String(text[close.upperBound...])
            }
            // Drop non-speech annotations like [BLANK_AUDIO], [Music], (wind).
            text = text.replacingOccurrences(of: #"\[[^\]]*\]"#, with: "", options: .regularExpression)
            text = text.replacingOccurrences(of: #"\([^)]*\)"#, with: "", options: .regularExpression)
            text = text.trimmingCharacters(in: .whitespaces)
            if !text.isEmpty { pieces.append(text) }
        }
        return pieces.joined(separator: " ")
    }

    public func transcribe(samples: [Float], sampleRate: Double) -> String? {
        let fm = FileManager.default
        try? fm.createDirectory(at: scratchDirectory, withIntermediateDirectories: true,
                                attributes: [.posixPermissions: 0o700])
        let chunk = scratchDirectory.appendingPathComponent("chunk-\(UUID().uuidString).wav")
        defer { try? fm.removeItem(at: chunk) }
        let pcm = WAVEncoder.resample(samples, from: sampleRate, to: 16_000)
        guard fm.createFile(atPath: chunk.path, contents: WAVEncoder.encode(samples: pcm, sampleRate: 16_000),
                            attributes: [.posixPermissions: 0o600]) else { return nil }
        let threads = max(2, min(8, ProcessInfo.processInfo.activeProcessorCount))
        let result = ProcessRunner.run(
            executable: executable,
            arguments: ["-m", model.path, "-f", chunk.path, "-nt", "-np", "-l", "en", "-t", String(threads)]
                + (initialPrompt.isEmpty ? [] : ["--prompt", initialPrompt]),
            stdin: nil,
            timeout: timeout
        )
        guard let result, result.status == 0 else { return nil }
        return Self.parseOutput(result.stdout)
    }
}

/// Runs a process with a timeout, collecting stdout. Nil when it cannot start or times out.
public enum ProcessRunner {
    public struct Result: Sendable {
        public var status: Int32
        public var stdout: String
        public var seconds: TimeInterval
    }

    public static func run(
        executable: URL, arguments: [String], stdin: String?, timeout: TimeInterval,
        environment: [String: String]? = nil
    ) -> Result? {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        if let environment { process.environment = environment }
        let out = Pipe()
        let input = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        process.standardInput = stdin == nil ? FileHandle.nullDevice : input
        let done = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in done.signal() }
        var collected = Data()
        let lock = NSLock()
        out.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            lock.lock()
            collected.append(chunk)
            lock.unlock()
        }
        let start = Date()
        do {
            try process.run()
        } catch {
            out.fileHandleForReading.readabilityHandler = nil
            return nil
        }
        if let stdin {
            try? input.fileHandleForWriting.write(contentsOf: Data(stdin.utf8))
            try? input.fileHandleForWriting.close()
        }
        if done.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            kill(-process.processIdentifier, SIGTERM)
            _ = done.wait(timeout: .now() + 1)
            out.fileHandleForReading.readabilityHandler = nil
            return nil
        }
        out.fileHandleForReading.readabilityHandler = nil
        let rest = out.fileHandleForReading.readDataToEndOfFile()
        lock.lock()
        collected.append(rest)
        let text = String(data: collected, encoding: .utf8) ?? ""
        lock.unlock()
        return Result(status: process.terminationStatus, stdout: text, seconds: Date().timeIntervalSince(start))
    }
}
