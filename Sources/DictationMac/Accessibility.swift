import AppKit
import ApplicationServices
import Carbon
import DictationCore
import Foundation

/// Reads the system-wide focused element and inserts text into a remembered element.
public final class AccessibilityBridge: FocusProvider, TextInserter {
    private var elements: [String: AXUIElement] = [:]
    private var order: [String] = []
    private var counter = 0

    public init() {}

    public func currentFocus(at time: Duration) -> FocusSnapshot {
        let system = AXUIElementCreateSystemWide()
        guard let element: AXUIElement = copy(system, kAXFocusedUIElementAttribute) else {
            return FocusSnapshot(timestamp: time, role: .none, identity: .none)
        }
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        let bundle = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
        let roleName: String? = copy(element, kAXRoleAttribute)
        let subrole: String? = copy(element, kAXSubroleAttribute)
        var role = FocusClassifier.role(axRole: roleName, subrole: subrole, bundleID: bundle)
        if role == .editableWebArea, !isSettable(element, kAXValueAttribute), !isSettable(element, kAXSelectedTextAttribute) {
            role = .none
        }
        let secure = role == .secureTextField || IsSecureEventInputEnabled()

        var selectionLength = 0
        var lineBreak = false
        var preceding: Character?
        if !secure, let rangeValue: AXValue = copy(element, kAXSelectedTextRangeAttribute) {
            var range = CFRange()
            if AXValueGetValue(rangeValue, .cfRange, &range) {
                selectionLength = range.length
                if let value: String = copy(element, kAXValueAttribute) {
                    let ns = value as NSString
                    if range.location > 0, range.location <= ns.length {
                        preceding = (ns.substring(with: NSRange(location: range.location - 1, length: 1))).first
                    }
                    if range.length > 0, range.location + range.length <= ns.length {
                        lineBreak = ns.substring(with: NSRange(location: range.location, length: range.length))
                            .contains("\n")
                    }
                }
            }
        }
        let id = remember(element)
        return FocusSnapshot(
            timestamp: time, role: role, isSecureInput: secure, selectionLength: selectionLength,
            selectionContainsLineBreak: lineBreak, precedingCharacter: preceding,
            identity: FocusIdentity(pid: Int(pid), elementID: id, roleLabel: roleName),
            exists: true)
    }

    /// Sets the selected text (inserting at the caret). Never sends key events, so Return is never pressed.
    public func insert(_ text: String, into target: FocusIdentity, replacingSelection: Bool) -> Bool {
        guard let id = target.elementID, let element = elements[id] else { return false }
        // The element must still exist and still be editable.
        guard let _: String = copy(element, kAXRoleAttribute) else { return false }
        let subrole: String? = copy(element, kAXSubroleAttribute)
        if subrole == "AXSecureTextField" { return false }
        if AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFString) == .success {
            return true
        }
        // Fall back to rewriting the value around the selection.
        guard let value: String = copy(element, kAXValueAttribute),
              let rangeValue: AXValue = copy(element, kAXSelectedTextRangeAttribute) else { return false }
        var range = CFRange()
        guard AXValueGetValue(rangeValue, .cfRange, &range) else { return false }
        let ns = value as NSString
        guard range.location >= 0, range.location + range.length <= ns.length else { return false }
        let updated = ns.replacingCharacters(in: NSRange(location: range.location, length: range.length), with: text)
        guard AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, updated as CFString) == .success
        else { return false }
        var caret = CFRange(location: range.location + (text as NSString).length, length: 0)
        if let newRange = AXValueCreate(.cfRange, &caret) {
            AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, newRange)
        }
        return true
    }

    private func remember(_ element: AXUIElement) -> String {
        if let existing = elements.first(where: { CFEqual($0.value, element) })?.key { return existing }
        counter += 1
        let id = "ax-\(counter)"
        elements[id] = element
        order.append(id)
        if order.count > 32 {
            elements.removeValue(forKey: order.removeFirst())
        }
        return id
    }

    private func isSettable(_ element: AXUIElement, _ attribute: String) -> Bool {
        var settable = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(element, attribute as CFString, &settable) == .success
            && settable.boolValue
    }

    private func copy<T>(_ element: AXUIElement, _ attribute: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value else { return nil }
        return value as? T
    }
}
