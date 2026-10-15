import AppKit
import DictationCore
import Foundation

/// R228: appends one JSON line per completed utterance to `<dir>/YYYY-MM.jsonl`.
/// Directory 0700, files 0600. Text only; secure fields never reach the session's records.
public final class CorpusLogger {
    public let directory: URL
    public var enabled: Bool
    public var bundleForPID: (Int) -> String? = { NSRunningApplication(processIdentifier: pid_t($0))?.bundleIdentifier }
    private var logged = 0

    public static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Dictation/corpus", isDirectory: true)
    }

    public init(directory: URL = CorpusLogger.defaultDirectory, enabled: Bool) {
        self.directory = directory
        self.enabled = enabled
    }

    public func poll(session: Session, coordinator: InsertionCoordinator) {
        let records = session.utteranceRecords
        defer { logged = records.count }
        guard enabled, logged < records.count else { return }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var out = ""
        for r in records[logged...] {
            let outcome = r.insertIndex.flatMap { coordinator.outcomes[$0] }
            let obj: [String: Any] = [
                "timestamp": iso.string(from: r.timestamp),
                "raw": r.raw, "tokenized": r.tokenized, "cleaned": r.cleaned,
                "backend": r.backend, "cleanupOutcome": r.cleanupOutcome, "latencyMs": r.latencyMs,
                "app": r.target.flatMap { bundleForPID($0.pid) } ?? NSNull(),
                "field": "\(r.fieldRole)",
                "inserted": outcome?.inserted ?? false,
                "autoSent": outcome?.autoSent ?? false,
                "noSend": !r.cancelled && !r.autoSendAllowed,
                "cancelled": r.cancelled,
                "mode": r.mode,
                "plugin": r.plugin ?? NSNull(),
            ]
            guard let data = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys, .withoutEscapingSlashes]),
                  let line = String(data: data, encoding: .utf8) else { continue }
            out += line + "\n"
        }
        append(out, month: records.last?.timestamp ?? Date())
    }

    private func append(_ text: String, month: Date) {
        let fm = FileManager.default
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM"
        let url = directory.appendingPathComponent(f.string(from: month) + ".jsonl")
        if !fm.fileExists(atPath: url.path) {
            fm.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600])
        }
        try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        guard let h = try? FileHandle(forWritingTo: url) else { return }
        defer { try? h.close() }
        _ = try? h.seekToEnd()
        try? h.write(contentsOf: Data(text.utf8))
    }
}
