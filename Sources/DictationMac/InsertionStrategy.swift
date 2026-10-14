import AppKit
import CoreGraphics
import Foundation

/// How text reaches the focused element (R219).
public enum InsertionStrategy {
    public enum Method: Equatable { case accessibility, paste }

    /// Chromium/Electron contenteditable reports AXSelectedText writes as successful but ignores them.
    public static func method(isChromiumElement: Bool) -> Method {
        isChromiumElement ? .paste : .accessibility
    }

    /// Whether an AX write visibly landed: the value changed and now contains the text.
    public static func didInsert(before: String?, after: String?, text: String) -> Bool {
        guard let after, after != before else { return false }
        return after.contains(text)
    }

    /// kVK_ANSI_V. Only Cmd-V is ever posted; Return/Enter is never sent.
    public static let pasteKeyCode: CGKeyCode = 9

    /// Puts `text` on the clipboard, posts Cmd-V, and restores the previous clipboard after ~300 ms.
    public static func paste(_ text: String, pasteboard: NSPasteboard = .general) -> Bool {
        let saved: [[NSPasteboard.PasteboardType: Data]] = (pasteboard.pasteboardItems ?? []).map { item in
            var d: [NSPasteboard.PasteboardType: Data] = [:]
            for t in item.types { if let data = item.data(forType: t) { d[t] = data } }
            return d
        }
        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else { return false }
        let changeCount = pasteboard.changeCount
        let source = CGEventSource(stateID: .combinedSessionState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: pasteKeyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: pasteKeyCode, keyDown: false)
        else { return false }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            // Leave the clipboard alone if something else changed it meanwhile.
            guard pasteboard.changeCount == changeCount else { return }
            pasteboard.clearContents()
            let items: [NSPasteboardItem] = saved.map { d in
                let item = NSPasteboardItem()
                for (t, data) in d { item.setData(data, forType: t) }
                return item
            }
            if !items.isEmpty { pasteboard.writeObjects(items) }
        }
        return true
    }
}
