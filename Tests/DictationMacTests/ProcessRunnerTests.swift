import Foundation
import XCTest
@testable import DictationMac

/// M8/M9: the clean-up CLI probe trusts ProcessRunner's stdout. Output written
/// just before the process exits must never be lost, or a working CLI is
/// passed over for local clean-up.
final class ProcessRunnerTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func script(_ body: String) throws -> URL {
        let url = dir.appendingPathComponent(UUID().uuidString + ".sh")
        try Data(("#!/bin/sh\n" + body).utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        return url
    }

    func test_M9_outputWrittenJustBeforeExitIsAlwaysReturned() throws {
        let exe = try script("cat >/dev/null\nprintf 'ok'\n")
        let runs = 200
        let lock = NSLock()
        var lost = 0
        DispatchQueue.concurrentPerform(iterations: runs) { _ in
            let r = ProcessRunner.run(executable: exe, arguments: [], stdin: "um hello there", timeout: 10)
            if r?.status != 0 || r?.stdout != "ok" {
                lock.lock(); lost += 1; lock.unlock()
            }
        }
        XCTAssertEqual(lost, 0, "\(lost) of \(runs) runs lost the CLI's output")
    }

    func test_M9_largeOutputDoesNotDeadlockThePipe() throws {
        let exe = try script("head -c 200000 /dev/zero | tr '\\0' 'a'\n")
        let r = ProcessRunner.run(executable: exe, arguments: [], stdin: nil, timeout: 10)
        XCTAssertEqual(r?.status, 0)
        XCTAssertEqual(r?.stdout.count, 200_000)
    }
}
