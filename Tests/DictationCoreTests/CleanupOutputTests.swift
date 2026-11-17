import XCTest
import DictationCore

final class CleanupOutputTests: XCTestCase {
    func test_R112_validatorPassesGoodOutputUnchanged() {
        XCTAssertEqual(CleanupOutput.validate(raw: "hello there", stdout: "Hello there.", exitStatus: 0),
                       .success("Hello there."))
        XCTAssertEqual(CleanupOutput.validate(raw: "hello there", stdout: "  \"Hello there.\"\n", exitStatus: 0),
                       .success("Hello there."))
    }

    func test_R112_validatorRefusesNonZeroExitNamingStatus() {
        let result = CleanupOutput.validate(raw: "hi", stdout: "Hi.", exitStatus: 3)
        XCTAssertEqual(result, .failure(.nonZeroExit(3)))
        XCTAssertTrue(CleanupRefusal.nonZeroExit(3).description.contains("exit status 3"))
    }

    func test_R112_validatorRefusesEmptyOutput() {
        XCTAssertEqual(CleanupOutput.validate(raw: "hi", stdout: " \n\"\" ", exitStatus: 0), .failure(.empty))
    }

    func test_R112_validatorRefusesOverlongOutputNamingCap() {
        let huge = String(repeating: "word ", count: 80)
        guard case .failure(.tooLong(let limit, let actual)) =
            CleanupOutput.validate(raw: "hello", stdout: huge, exitStatus: 0) else {
            return XCTFail("expected tooLong")
        }
        XCTAssertEqual(limit, 5 * 2 + 40)
        XCTAssertGreaterThan(actual, limit)
    }

    func test_R112_validatorRefusesPreamblesNamingPrefix() {
        XCTAssertEqual(CleanupOutput.validate(raw: "hello there", stdout: "Here is the text.", exitStatus: 0),
                       .failure(.preamble("here is")))
        XCTAssertEqual(CleanupOutput.validate(raw: "hello there", stdout: "Sure, Hello there.", exitStatus: 0),
                       .failure(.preamble("sure")))
    }

    func test_R112_refusalDescriptionsNeverContainOutputText() {
        let text = "Here is SECRET words"
        guard case .failure(let refusal) = CleanupOutput.validate(raw: "x", stdout: text, exitStatus: 0) else {
            return XCTFail("expected refusal")
        }
        XCTAssertFalse(refusal.description.contains("SECRET"))
    }

    func test_R112_syncPathRefusesPreambleAndFallsBackToLocalCleanup() throws {
        let h = try TestHarness()
        let cli = try h.installFakeCLI(result: "Here is the cleaned text.", name: "sync-preamble")
        h.session.configureCLI(path: cli.path, kind: .claudeCLI, enabled: true)
        h.session.confirmCLIConsent()
        h.readyListening()
        h.speakAndWait("hello there")

        XCTAssertEqual(h.session.insertRequests.count, 1)
        XCTAssertEqual(h.session.insertRequests.first?.text, "Hello there.")
        XCTAssertEqual(h.session.cleanupRefusals, [.preamble("here is")])
    }

    func test_R112_syncPathAcceptsGoodOutput() throws {
        let h = try TestHarness()
        let cli = try h.installFakeCLI(result: "Hello there!", name: "sync-good")
        h.session.configureCLI(path: cli.path, kind: .claudeCLI, enabled: true)
        h.session.confirmCLIConsent()
        h.readyListening()
        h.speakAndWait("hello there")

        XCTAssertEqual(h.session.insertRequests.first?.text, "Hello there!")
        XCTAssertTrue(h.session.cleanupRefusals.isEmpty)
    }

    func test_R112_asyncPathLogsRefusalReason() throws {
        let h = try TestHarness()
        let cli = try h.installFakeCLI(result: "Sure, Hello there.", name: "async-preamble")
        h.session.setCleanupBackend(.grokCLI, executablePath: cli.path)
        h.latchOn()
        h.focusEditable()
        h.pressTalkKey()
        h.speakWhileHeld("hello there")
        h.releaseTalkKey()
        h.clock.advance(by: .milliseconds(100))

        XCTAssertEqual(h.session.insertRequests.first?.text, "Hello there.")
        XCTAssertEqual(h.session.cleanupRefusals, [.preamble("sure")])
    }

    func test_R111_backendRefusesMissingPathNamingPathAndKeepsPrevious() throws {
        let h = try TestHarness()
        let good = try h.installFakeCLI(result: "Hello there.", name: "good-backend")
        XCTAssertNil(h.session.setCleanupBackend(.grokCLI, executablePath: good.path))

        let missing = h.workingDirectory.appendingPathComponent("nope").path
        let refusal = h.session.setCleanupBackend(.claudeCLI, executablePath: missing)
        XCTAssertEqual(refusal, .missing(path: missing))
        XCTAssertTrue(refusal?.description.contains(missing) == true)
        XCTAssertEqual(h.session.cleanupBackendRefusals, [.missing(path: missing)])

        // Previous backend (good CLI) is still in force.
        h.latchOn()
        h.focusEditable()
        h.pressTalkKey()
        h.speakWhileHeld("hello there")
        h.releaseTalkKey()
        h.clock.advance(by: .milliseconds(100))
        XCTAssertEqual(h.session.cliInvocations.first?.executablePath, good.path)
    }

    func test_R111_backendRefusesNonExecutableFileAndDirectory() throws {
        let h = try TestHarness()
        let plain = h.workingDirectory.appendingPathComponent("plain.txt")
        try "x".write(to: plain, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: plain.path)
        XCTAssertEqual(h.session.setCleanupBackend(.cursorCLI, executablePath: plain.path),
                       .notExecutable(path: plain.path))
        XCTAssertEqual(h.session.setCleanupBackend(.cursorCLI, executablePath: h.workingDirectory.path),
                       .notAFile(path: h.workingDirectory.path))
    }
}
