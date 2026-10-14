import AppKit
import DictationCore
import Foundation

/// Puts text into a previously captured focused element.
public protocol TextInserter: AnyObject {
    func insert(_ text: String, into target: FocusIdentity, replacingSelection: Bool) -> Bool
}

/// Delivers each new core insert request once and reports the result back (M10, M11).
public final class InsertionCoordinator {
    private let session: Session
    private let inserter: TextInserter
    private let pasteboard: NSPasteboard
    private var delivered = 0
    /// Per insert-request index: (inserted, autoSent). Read by CorpusLogger (R228).
    public private(set) var outcomes: [Int: (inserted: Bool, autoSent: Bool)] = [:]
    /// Text waiting behind the panel's Copy button after a failed insert.
    public private(set) var pendingCopyText: String?
    /// Auto-send (R223): nil disables it entirely.
    public var autoSend: AutoSendPolicy?
    public var keySender: ReturnKeySender = CGReturnKeySender()
    public var bundleForPID: (Int) -> String? = { NSRunningApplication(processIdentifier: pid_t($0))?.bundleIdentifier }
    /// Waits for the insert (e.g. the Cmd-V paste) to land before Return.
    public var schedule: (TimeInterval, @escaping () -> Void) -> Void = { delay, work in
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    public init(session: Session, inserter: TextInserter, pasteboard: NSPasteboard = .general) {
        self.session = session
        self.inserter = inserter
        self.pasteboard = pasteboard
    }

    public func poll() {
        let requests = session.insertRequests
        while delivered < requests.count {
            let index = delivered
            let request = requests[index]
            delivered += 1
            if inserter.insert(request.text, into: request.target, replacingSelection: request.replacesSelection) {
                pendingCopyText = nil
                session.reportInsertionSucceeded(for: index)
                if let policy = autoSend,
                   policy.shouldSend(bundleID: bundleForPID(request.target.pid), inserted: true,
                                     text: request.text, allowed: request.autoSendAllowed) {
                    let keys = keySender
                    schedule(0.15) { keys.sendReturn() }
                    outcomes[index] = (true, true)
                } else {
                    outcomes[index] = (true, false)
                }
            } else {
                pendingCopyText = request.text
                outcomes[index] = (false, false)
                session.reportInsertionFailed(for: index)
            }
        }
    }

    public func tap(button title: String) {
        let copyText = session.panel.copyText ?? pendingCopyText
        session.tapOverlayButton(title: title)
        guard title == "Copy", let text = copyText else { return }
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}

/// Maps Accessibility roles to core field roles.
public enum FocusClassifier {
    public static let terminalBundles: Set<String> = [
        "com.apple.Terminal", "com.googlecode.iterm2", "dev.warp.Warp-Stable", "com.mitchellh.ghostty",
    ]

    public static func role(axRole: String?, subrole: String?, bundleID: String?,
                            selectedTextSettable: Bool = false) -> FieldRole {
        if subrole == "AXSecureTextField" { return .secureTextField }
        let editable: FieldRole
        switch axRole {
        case "AXTextField", "AXSearchField": editable = .textField
        case "AXTextArea": editable = .textArea
        case "AXComboBox": editable = .comboBox
        case "AXWebArea": editable = .editableWebArea
        default:
            // Electron/Chrome contenteditable often reports a generic role (AXGroup etc.)
            // but exposes settable selected text: treat it as a multi-line area.
            guard selectedTextSettable else { return .none }
            editable = .textArea
        }
        if let bundleID, terminalBundles.contains(bundleID) { return .terminal }
        return editable
    }
}
