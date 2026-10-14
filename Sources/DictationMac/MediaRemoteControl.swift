import Darwin
import DictationCore
import Dispatch
import Foundation

/// Uses Apple-signed Perl to access MediaRemote on macOS 15.4 and later.
public final class PerlMediaRemoteController: MediaController {
    private let dylibURL: URL?

    public init() {
        dylibURL = Bundle.main.url(forResource: "mediactl", withExtension: "dylib")
    }

    public func playState() -> MediaPlayState {
        switch run("status", timeout: .milliseconds(300)) {
        case "playing": return .playing
        case "stopped": return .notPlaying
        default: return .unknown
        }
    }

    public func pause() {
        _ = run("pause", timeout: .seconds(1))
    }

    public func resume() {
        _ = run("play", timeout: .seconds(1))
    }

    private func run(_ command: String, timeout: DispatchTimeInterval) -> String? {
        guard let dylibURL, FileManager.default.fileExists(atPath: dylibURL.path) else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [
            "-e", "require DynaLoader; DynaLoader::dl_load_file($ARGV[0],0) or exit 3",
            dylibURL.path,
        ]
        var environment = ProcessInfo.processInfo.environment
        environment["DICTATION_MEDIA_CMD"] = command
        process.environment = environment
        let output = Pipe()
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        let done = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in done.signal() }
        let deadline = DispatchTime.now() + timeout
        do {
            try process.run()
        } catch {
            return nil
        }
        try? output.fileHandleForWriting.close()
        if done.wait(timeout: deadline) == .timedOut {
            // SIGKILL provides a hard limit even if the helper ignores termination.
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            process.waitUntilExit()
            return nil
        }
        guard process.terminationReason == .exit, process.terminationStatus == 0 else { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
