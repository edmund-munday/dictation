import AppKit
import CoreGraphics
import Foundation

/// Presses Return. The only place the app ever sends Return (R223, chat apps only).
public protocol ReturnKeySender: AnyObject {
    func sendReturn()
}

public final class CGReturnKeySender: ReturnKeySender {
    public init() {}
    public func sendReturn() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let kVKReturn: CGKeyCode = 36
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: kVKReturn, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: kVKReturn, keyDown: false) else { return }
        down.flags = []
        up.flags = []
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}

/// Which apps get an automatic Return after a confirmed insert (Edmund 2026-10-14; replaces the
/// "never press Return" rule for chat apps only). Browsers are deliberately not included.
public struct AutoSendPolicy: Equatable {
    public static let enabledKey = "autoSendInChatApps"
    public static let extraAppsKey = "autoSendExtraChatApps"
    public static let defaultChatApps: Set<String> = [
        "com.anysphere.sand",          // Grok Bot
        "com.tinyspeck.slackmacgap",   // Slack
        "com.apple.MobileSMS",         // Messages
        "net.whatsapp.WhatsApp",       // WhatsApp
        "desktop.WhatsApp",            // WhatsApp (Catalyst)
        "com.hnc.Discord",             // Discord
        "ru.keepcoder.Telegram",       // Telegram
        "org.telegram.desktop",        // Telegram Desktop
        "org.whispersystems.signal-desktop", // Signal
        "com.microsoft.teams2",        // Teams
        "com.microsoft.teams",         // Teams (classic)
        "com.facebook.archon",         // Messenger
        "com.facebook.archon.developerID", // Messenger
    ]

    public var enabled: Bool
    public var chatApps: Set<String>

    public init(enabled: Bool = true, chatApps: Set<String> = AutoSendPolicy.defaultChatApps) {
        self.enabled = enabled
        self.chatApps = chatApps
    }

    public func isChatApp(_ bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return chatApps.contains(bundleID)
    }

    public func shouldSend(bundleID: String?, inserted: Bool, text: String, allowed: Bool) -> Bool {
        enabled && allowed && inserted && isChatApp(bundleID)
            && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public static func load(from defaults: UserDefaults = .standard) -> AutoSendPolicy {
        let enabled = defaults.object(forKey: enabledKey) as? Bool ?? true
        let extra = Set(defaults.stringArray(forKey: extraAppsKey) ?? [])
        return AutoSendPolicy(enabled: enabled, chatApps: defaultChatApps.union(extra))
    }
}
