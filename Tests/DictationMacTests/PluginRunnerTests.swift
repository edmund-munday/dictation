import DictationCore
import DictationMac
import Foundation
import XCTest

/// R234: exec runner contract (argv per element, stdin JSON, env, timeout, exit codes) and bundled plugins.
final class PluginRunnerTests: XCTestCase {
    private var dir: URL!
    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    private func script(_ body: String) throws -> String {
        let url = dir.appendingPathComponent(UUID().uuidString + ".sh")
        try Data(("#!/bin/sh\n" + body).utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        return url.path
    }
    private func spec(_ path: String, argv: [String] = [], timeout: Double = 5) throws -> PluginSpec {
        let o: [String: Any] = ["name": "t", "description": "t", "triggers": ["t {subject}"],
                                "args": ["subject": ["type": "string"]],
                                "action": ["type": "exec", "path": path, "argv": argv], "timeout_s": timeout]
        return try PluginSpec.parse(JSONSerialization.data(withJSONObject: o))
    }

    func test_R234_argsStayOneLiteralArgumentNeverAShell() throws {
        let marker = dir.appendingPathComponent("pwned").path
        let s = try script(#"printf '%s|' "$#" "$@""#)
        let r = PluginRunner.run(try spec(s, argv: ["--describe", "{subject}"]),
                                 args: ["subject": "a b; touch \(marker) $(touch \(marker))"], context: [:])
        XCTAssertEqual(r.exitCode, 0)
        XCTAssertEqual(r.stdout, "2|--describe|a b; touch \(marker) $(touch \(marker))|")
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker))
    }

    func test_R234_stdinJSONAndEnvCarryArgs() throws {
        let s = try script(#"cat; printf '\n%s' "$DICTATION_ARG_SUBJECT|$DICTATION_PLUGIN|$DICTATION_VERSION""#)
        let r = PluginRunner.run(try spec(s), args: ["subject": "the error dialog"], context: ["frontmost_app": "com.x"])
        let parts = r.stdout.components(separatedBy: "\n")
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(parts[0].utf8)) as? [String: Any])
        XCTAssertEqual(obj["plugin"] as? String, "t")
        XCTAssertEqual((obj["args"] as? [String: String])?["subject"], "the error dialog")
        XCTAssertEqual((obj["context"] as? [String: String])?["frontmost_app"], "com.x")
        XCTAssertEqual(obj["version"] as? Int, 1)
        XCTAssertEqual(parts.last, "the error dialog|t|1")
    }

    func test_R234_stdoutJSONIsParsed() throws {
        let s = try script(#"echo '{"insert":"hi","notify":"Done"}'"#)
        let r = PluginRunner.run(try spec(s), args: [:], context: [:])
        XCTAssertEqual(r.output, PluginOutput(insert: "hi", notify: "Done", send: nil))
    }

    func test_R234_timeoutKillsAndReportsFailure() throws {
        let s = try script("sleep 10")
        let start = Date()
        let r = PluginRunner.run(try spec(s, timeout: 0.5), args: [:], context: [:])
        XCTAssertTrue(r.timedOut)
        XCTAssertLessThan(Date().timeIntervalSince(start), 5)
    }

    func test_R234_nonZeroExitReportsStderrFirstLine() throws {
        let s = try script("echo 'boom here' >&2; echo second >&2; exit 1")
        let r = PluginRunner.run(try spec(s), args: [:], context: [:])
        XCTAssertEqual(r.exitCode, 1)
        XCTAssertEqual(r.errorLine, "boom here")
    }

    func test_R234_bundledPluginsInstallAndMatchScreenshotPhrases() throws {
        try BundledPlugins.install(into: dir)
        let loaded = PluginLoader.load(directory: dir)
        XCTAssertEqual(Set(loaded.plugins.map(\.name)), ["echo", "screenshot"])
        for phrase in ["take a screenshot", "Take a screenshot of the error dialog.", "grab a screenshot", "screenshot this"] {
            XCTAssertEqual(TriggerMatcher.match(phrase, plugins: loaded.plugins)?.plugin, "screenshot", phrase)
        }
        XCTAssertEqual(TriggerMatcher.match("take a screenshot of the error dialog", plugins: loaded.plugins)?.args["subject"], "the error dialog")
        // echo plugin round-trips through the runner
        let echo = try XCTUnwrap(loaded.plugins.first { $0.name == "echo" })
        let r = PluginRunner.run(echo, args: ["text": #"say "hi""#], context: [:])
        XCTAssertEqual(r.exitCode, 0)
        XCTAssertEqual(r.output?.insert, #"say "hi""#)
        // install does not clobber an edited file
        try Data(PluginCommandTestsFixture.edited.utf8).write(to: dir.appendingPathComponent("echo.json"))
        try BundledPlugins.install(into: dir)
        XCTAssertEqual(try String(contentsOf: dir.appendingPathComponent("echo.json"), encoding: .utf8), PluginCommandTestsFixture.edited)
    }

    func test_R234_setEnabledRewritesOnlyThatFile() throws {
        try BundledPlugins.install(into: dir)
        try PluginLoader.setEnabled(false, plugin: "echo", directory: dir)
        let loaded = PluginLoader.load(directory: dir)
        XCTAssertEqual(loaded.plugins.first { $0.name == "echo" }?.enabled, false)
        XCTAssertEqual(loaded.plugins.first { $0.name == "screenshot" }?.enabled, true)
    }
}

enum PluginCommandTestsFixture {
    static let edited = #"{"name":"echo","description":"edited","triggers":["test echo {text}"],"action":{"type":"exec","path":"/bin/echo"}}"#
}
