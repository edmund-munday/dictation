import AppKit
import DictationCore
import DictationMac
import XCTest

/// R228: each completed utterance appends one JSON line to corpus/YYYY-MM.jsonl (dir 700, file 600).
/// Replaces the old "no transcript logs" rule for this tuning corpus only. Secure fields are never logged.
final class CorpusLogTests: XCTestCase {
    private func hold(_ h: MacHarness, _ text: String, focus: FocusSnapshot, cancelWith key: KeyIdentity? = nil) {
        h.session.ingestFocus(focus)
        h.session.ingestTalkKey(TalkKeyEvent(timestamp: h.clock.now, identity: .command(.left), isDown: true))
        h.clock.advance(by: .milliseconds(500))
        h.session.ingestRecognizerTokens([RecognizerToken(text: text, start: .zero, end: h.clock.now, isFinal: true)])
        if let key {
            h.session.ingestTalkKey(TalkKeyEvent(timestamp: h.clock.now, identity: key, isDown: true))
            h.session.ingestTalkKey(TalkKeyEvent(timestamp: h.clock.now, identity: .command(.left), isDown: false))
        } else {
            h.session.ingestTalkKey(TalkKeyEvent(timestamp: h.clock.now, identity: .command(.left), isDown: false))
        }
        h.clock.advance(by: .milliseconds(250))
    }

    private func setup(enabled: Bool = true) throws -> (MacHarness, InsertionCoordinator, CorpusLogger, URL) {
        let h = try MacHarness()
        let c = InsertionCoordinator(session: h.session, inserter: RecordingInserter(succeeds: true))
        c.bundleForPID = { _ in "com.anysphere.sand" }
        c.keySender = NoKeys()
        c.schedule = { _, work in work() }
        c.autoSend = AutoSendPolicy()
        let dir = h.directory.appendingPathComponent("corpus")
        let logger = CorpusLogger(directory: dir, enabled: enabled)
        logger.bundleForPID = { _ in "com.anysphere.sand" }
        return (h, c, logger, dir)
    }

    private final class NoKeys: ReturnKeySender { func sendReturn() {} }

    private func lines(_ dir: URL) throws -> [[String: Any]] {
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return try files.filter { $0.pathExtension == "jsonl" }.flatMap { url in
            try String(contentsOf: url, encoding: .utf8).split(separator: "\n").map {
                try XCTUnwrap(JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any])
            }
        }
    }

    func test_R228_completedUtteranceAppendsOneJSONLine() throws {
        let (h, c, logger, dir) = try setup()
        hold(h, "um send the deck comma thanks", focus: h.field(.textArea, id: "chat"))
        c.poll()
        logger.poll(session: h.session, coordinator: c)
        logger.poll(session: h.session, coordinator: c)
        let all = try lines(dir)
        XCTAssertEqual(all.count, 1, "logged once")
        let r = try XCTUnwrap(all.first)
        XCTAssertEqual(r["raw"] as? String, "um send the deck comma thanks")
        XCTAssertNotNil(r["tokenized"] as? String)
        XCTAssertEqual(r["cleaned"] as? String, "Send the deck, thanks.")
        XCTAssertEqual(r["backend"] as? String, "local")
        XCTAssertNotNil(r["latencyMs"] as? Int)
        XCTAssertEqual(r["app"] as? String, "com.anysphere.sand")
        XCTAssertEqual(r["field"] as? String, "textArea")
        XCTAssertEqual(r["inserted"] as? Bool, true)
        XCTAssertEqual(r["autoSent"] as? Bool, true)
        XCTAssertEqual(r["noSend"] as? Bool, false)
        XCTAssertEqual(r["cancelled"] as? Bool, false)
        XCTAssertNotNil(r["timestamp"] as? String)
    }

    func test_R228_fileAndFolderArePrivateAndNamedByMonth() throws {
        let (h, c, logger, dir) = try setup()
        hold(h, "hello there", focus: h.field(.textArea))
        c.poll()
        logger.poll(session: h.session, coordinator: c)
        let fm = FileManager.default
        let dirPerm = try XCTUnwrap(try fm.attributesOfItem(atPath: dir.path)[.posixPermissions] as? Int)
        XCTAssertEqual(dirPerm & 0o777, 0o700)
        let files = try fm.contentsOfDirectory(atPath: dir.path)
        XCTAssertEqual(files.count, 1)
        let name = try XCTUnwrap(files.first)
        XCTAssertNotNil(name.range(of: #"^\d{4}-\d{2}\.jsonl$"#, options: .regularExpression), name)
        let filePerm = try XCTUnwrap(try fm.attributesOfItem(atPath: dir.appendingPathComponent(name).path)[.posixPermissions] as? Int)
        XCTAssertEqual(filePerm & 0o777, 0o600)
    }

    func test_R228_noSendIsRecorded() throws {
        let (h, c, logger, dir) = try setup()
        hold(h, "see you at five don't send it yet", focus: h.field(.textArea))
        c.poll()
        logger.poll(session: h.session, coordinator: c)
        let r = try XCTUnwrap(try lines(dir).first)
        XCTAssertEqual(r["noSend"] as? Bool, true)
        XCTAssertEqual(r["autoSent"] as? Bool, false)
    }

    func test_R228_cancelledHoldIsRecordedAsCancelled() throws {
        let (h, c, logger, dir) = try setup()
        hold(h, "never mind this", focus: h.field(.textArea), cancelWith: .character("a"))
        c.poll()
        logger.poll(session: h.session, coordinator: c)
        let all = try lines(dir)
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?["cancelled"] as? Bool, true)
        XCTAssertEqual(all.first?["inserted"] as? Bool, false)
    }

    func test_R228_secureFieldsAreNeverLogged() throws {
        let (h, c, logger, dir) = try setup()
        hold(h, "hunter two", focus: h.field(.secureTextField, secure: true))
        c.poll()
        logger.poll(session: h.session, coordinator: c)
        XCTAssertEqual(try lines(dir).count, 0)
    }

    func test_R228_disabledWritesNothing() throws {
        let (h, c, logger, dir) = try setup(enabled: false)
        hold(h, "hello there", focus: h.field(.textArea))
        c.poll()
        logger.poll(session: h.session, coordinator: c)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.path))
    }
}
