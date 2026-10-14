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
    /// Text waiting behind the panel's Copy button after a failed insert.
    public private(set) var pendingCopyText: String?

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
            } else {
                pendingCopyText = request.text
                session.reportInsertionFailed(for: index)
            }
        }
    }

    public func tap(button title: String) {
        session.tapOverlayButton(title: title)
        guard title == "Copy", let text = pendingCopyText else { return }
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
