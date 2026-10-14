import AppKit
import DictationCore
import DictationMac
import XCTest

/// R223: after a confirmed insert into a chat app, press Return once (toggle, default on).
final class AutoSendTests: XCTestCase {
    private final class Keys: ReturnKeySender { var returns = 0; func sendReturn() { returns += 1 } }

    private func dictate(_ h: MacHarness, _ text: String) {
        h.session.ingestFocus(h.field(.textArea, id: "chat"))
        h.session.ingestTalkKey(TalkKeyEvent(timestamp: h.clock.now, identity: .command(.left), isDown: true))
        h.clock.advance(by: .milliseconds(500))
        h.session.ingestRecognizerTokens([RecognizerToken(text: text, start: .zero, end: h.clock.now, isFinal: true)])
        h.session.ingestTalkKey(TalkKeyEvent(timestamp: h.clock.now, identity: .command(.left), isDown: false))
        h.clock.advance(by: .milliseconds(250))
    }

    private func run(bundle: String?, succeeds: Bool = true, enabled: Bool = true, text: String = "hello there")
        throws -> (Keys, [TimeInterval]) {
        let h = try MacHarness()
        let keys = Keys()
        var delays: [TimeInterval] = []
        let c = InsertionCoordinator(session: h.session, inserter: RecordingInserter(succeeds: succeeds))
        c.autoSend = AutoSendPolicy(enabled: enabled)
        c.keySender = keys
        c.bundleForPID = { _ in bundle }
        c.schedule = { delay, work in delays.append(delay); work() }
        dictate(h, text)
        c.poll()
        return (keys, delays)
    }

    func test_R223_chatAppGetsOneReturnAfterConfirmedInsert() throws {
        let (keys, delays) = try run(bundle: "com.anysphere.sand")
        XCTAssertEqual(keys.returns, 1)
        XCTAssertEqual(delays.count, 1)
        XCTAssertGreaterThanOrEqual(delays[0], 0.1)
    }

    func test_R223_nonChatAppNeverGetsReturn() throws {
        XCTAssertEqual(try run(bundle: "com.apple.TextEdit").0.returns, 0)
        XCTAssertEqual(try run(bundle: nil).0.returns, 0)
    }

    func test_R223_noReturnWhenInsertFailsOrDisabled() throws {
        XCTAssertEqual(try run(bundle: "com.tinyspeck.slackmacgap", succeeds: false).0.returns, 0)
        XCTAssertEqual(try run(bundle: "com.tinyspeck.slackmacgap", enabled: false).0.returns, 0)
    }

    func test_R223_noReturnWhenUtteranceSaysDontSend() throws {
        XCTAssertEqual(try run(bundle: "com.tinyspeck.slackmacgap", text: "see you at five don't send it yet").0.returns, 0)
    }

    func test_R223_defaultChatListAndDefaultOn() {
        let p = AutoSendPolicy()
        XCTAssertTrue(p.enabled)
        for b in ["com.anysphere.sand", "com.tinyspeck.slackmacgap", "com.apple.MobileSMS", "net.whatsapp.WhatsApp"] {
            XCTAssertTrue(p.isChatApp(b), b)
        }
        XCTAssertFalse(p.isChatApp("com.apple.Terminal"))
        XCTAssertFalse(p.isChatApp("com.google.Chrome"), "browsers are not chat apps by default")
    }

    func test_R223_policyLoadsToggleAndExtraAppsFromDefaults() throws {
        let suite = "dictation-test-\(UUID().uuidString)"
        let d = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { d.removePersistentDomain(forName: suite) }
        XCTAssertTrue(AutoSendPolicy.load(from: d).enabled)
        d.set(false, forKey: AutoSendPolicy.enabledKey)
        d.set(["com.example.chat"], forKey: AutoSendPolicy.extraAppsKey)
        let p = AutoSendPolicy.load(from: d)
        XCTAssertFalse(p.enabled)
        XCTAssertTrue(p.isChatApp("com.example.chat"))
    }
}
