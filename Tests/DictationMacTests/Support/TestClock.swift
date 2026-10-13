import DictationCore
import Foundation

/// Manual clock for tests: time moves only when `advance(by:)` is called.
final class TestClock: Clock, @unchecked Sendable {
    private(set) var now: Duration = .zero
    private var handler: (@Sendable () -> Void)?

    func advance(by duration: Duration) {
        now += duration
        handler?()
    }

    func observeAdvances(_ handler: @escaping @Sendable () -> Void) {
        self.handler = handler
    }
}

/// A real core session in a temporary directory, latched on.
final class MacHarness {
    let clock = TestClock()
    let directory: URL
    let session: Session

    init(latched: Bool = true) throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("dictation-mac-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        session = Session(clock: clock, paths: SessionPaths(workingDirectory: directory))
        if latched { session.setLatch(.on) }
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    func field(_ role: FieldRole = .textField, secure: Bool = false, id: String = "field-1") -> FocusSnapshot {
        FocusSnapshot(
            timestamp: clock.now,
            role: role,
            isSecureInput: secure,
            identity: FocusIdentity(pid: 4242, elementID: id)
        )
    }

    /// Writes an executable shell script into the harness directory.
    @discardableResult
    func script(named name: String, in subdirectory: String = "bin", body: String) throws -> URL {
        let dir = directory.appendingPathComponent(subdirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        try ("#!/bin/sh\n" + body + "\n").write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }
}
