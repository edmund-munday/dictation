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

    public var setManualAccessibility: (pid_t) -> AXError = { pid in
        AXUIElementSetAttributeValue(
            AXUIElementCreateApplication(pid), "AXManualAccessibility" as CFString, kCFBooleanTrue)
    }
    /// Pid zero asks only for system-wide focus when there is no frontmost application.
    public var copyFocusedElement: (pid_t) -> AXUIElement? = { pid in
        AccessibilityBridge.defaultFocusedElement(pid: pid)
    }
    public var frontmostApp: () -> (pid: pid_t, bundleID: String?)? = {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        return (app.processIdentifier, app.bundleIdentifier)
    }
    public var pause: (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) }
    public var log: (String) -> Void = { NSLog("%@", $0) }

    private final class ManualAccessibilityState {
        var unsupported = false
        var hasProducedFocus = false
        var loggedCodes: Set<Int32> = []
    }

    // Activation arrives on main; focus resolution runs on AppModel's work queue.
    // All accesses to these collections and their state objects hold accessibilityLock.
    private let accessibilityLock = NSLock()
    private var manualAccessibilityPIDs: Set<pid_t> = []
    private var manualAccessibilityStates: [pid_t: ManualAccessibilityState] = [:]
    private var workspaceObservers: [NSObjectProtocol] = []

    public init() {
        // Electron/Chromium build their accessibility tree only when asked; ask as soon as an
        // app becomes active so the focused field is readable by the time the talk key goes down.
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: nil
        ) { [weak self] note in
            if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                self?.enableWebAccessibility(pid: app.processIdentifier, bundleID: app.bundleIdentifier)
            }
        })
        workspaceObservers.append(center.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: nil
        ) { [weak self] note in
            if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                self?.removeManualAccessibilityState(pid: app.processIdentifier)
            }
        })
        if let front = frontmostApp() { enableWebAccessibility(pid: front.pid, bundleID: front.bundleID) }
    }

    deinit {
        let center = NSWorkspace.shared.notificationCenter
        for observer in workspaceObservers { center.removeObserver(observer) }
    }

    private func enableWebAccessibility(pid: pid_t, bundleID: String?) {
        guard pid > 0 else { return }
        accessibilityLock.lock()
        let message = enableWebAccessibilityLocked(pid: pid, bundleID: bundleID, ignoringCache: false)
        accessibilityLock.unlock()
        if let message { log(message) }
    }

    /// Caller holds accessibilityLock, including during the AX set, so activation cannot race retry.
    private func enableWebAccessibilityLocked(pid: pid_t, bundleID: String?, ignoringCache: Bool) -> String? {
        guard ignoringCache || !manualAccessibilityPIDs.contains(pid) else { return nil }
        let state = manualAccessibilityStateLocked(pid: pid)
        let result = setManualAccessibility(pid)
        state.hasProducedFocus = false
        switch result {
        case .success:
            state.unsupported = false
            manualAccessibilityPIDs.insert(pid)
        case .attributeUnsupported, .notImplemented, .actionUnsupported:
            state.unsupported = true
            manualAccessibilityPIDs.insert(pid)
        default:
            state.unsupported = false
            manualAccessibilityPIDs.remove(pid)
        }
        guard state.loggedCodes.insert(result.rawValue).inserted else { return nil }
        return "Dictation AX: AXManualAccessibility pid \(pid) \(bundleID ?? "<unknown>") err \(result.rawValue)"
    }

    private func manualAccessibilityStateLocked(pid: pid_t) -> ManualAccessibilityState {
        if let state = manualAccessibilityStates[pid] { return state }
        let state = ManualAccessibilityState()
        manualAccessibilityStates[pid] = state
        return state
    }

    private func removeManualAccessibilityState(pid: pid_t) {
        accessibilityLock.lock()
        defer { accessibilityLock.unlock() }
        manualAccessibilityPIDs.remove(pid)
        manualAccessibilityStates.removeValue(forKey: pid)
    }

    private func resolveFocusedElement() -> AXUIElement? {
        guard let front = frontmostApp(), front.pid > 0 else { return copyFocusedElement(0) }
        accessibilityLock.lock()
        let state = manualAccessibilityStateLocked(pid: front.pid)
        if let element = copyFocusedElement(front.pid) {
            state.hasProducedFocus = true
            accessibilityLock.unlock()
            return element
        }
        guard !state.unsupported, !state.hasProducedFocus else {
            accessibilityLock.unlock()
            return nil
        }
        let message = enableWebAccessibilityLocked(pid: front.pid, bundleID: front.bundleID, ignoringCache: true)
        let shouldRetry = !state.unsupported
        accessibilityLock.unlock()
        if let message { log(message) }
        guard shouldRetry else { return nil }

        // Do not block activation or termination notifications while the tree becomes available.
        pause(0.15)
        accessibilityLock.lock()
        defer { accessibilityLock.unlock() }
        // Termination during the pause must not recreate stale state or affect a reused pid.
        guard manualAccessibilityStates[front.pid] === state else { return nil }
        let element = copyFocusedElement(front.pid)
        if element != nil { state.hasProducedFocus = true }
        return element
    }

    /// Exercises the same resolver as currentFocus without reading attributes of opaque test elements.
    public func focusedElementForTesting() -> AXUIElement? { resolveFocusedElement() }

    /// The system-wide lookup often fails on recent macOS, so try the app, then its focused window.
    private static func defaultFocusedElement(pid: pid_t) -> AXUIElement? {
        if pid > 0 {
            let app = AXUIElementCreateApplication(pid)
            if let element: AXUIElement = copyAttribute(app, kAXFocusedUIElementAttribute) { return element }
            if let window: AXUIElement = copyAttribute(app, kAXFocusedWindowAttribute),
               let element: AXUIElement = copyAttribute(window, kAXFocusedUIElementAttribute) { return element }
        }
        return copyAttribute(AXUIElementCreateSystemWide(), kAXFocusedUIElementAttribute)
    }

    public func currentFocus(at time: Duration) -> FocusSnapshot {
        guard let element = resolveFocusedElement() else {
            return FocusSnapshot(timestamp: time, role: .none, identity: .none)
        }
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        let bundle = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
        let roleName: String? = copy(element, kAXRoleAttribute)
        let subrole: String? = copy(element, kAXSubroleAttribute)
        var role = FocusClassifier.role(axRole: roleName, subrole: subrole, bundleID: bundle,
                                        selectedTextSettable: isSettable(element, kAXSelectedTextAttribute))
        if role == .editableWebArea, !isSettable(element, kAXValueAttribute), !isSettable(element, kAXSelectedTextAttribute) {
            role = .none
        }
        let secure = role == .secureTextField || IsSecureEventInputEnabled()

        var selectionLength = 0
        var selectedText: String?
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
        if !secure, selectionLength > 0, let text: String = copy(element, kAXSelectedTextAttribute) {
            selectedText = String(text.prefix(20_000))
        }
        let id = remember(element)
        return FocusSnapshot(
            timestamp: time, role: role, isSecureInput: secure, selectionLength: selectionLength,
            selectionContainsLineBreak: lineBreak, precedingCharacter: preceding,
            identity: FocusIdentity(pid: Int(pid), elementID: id, roleLabel: roleName),
            exists: true, selectedText: selectedText)
    }

    /// Sets the selected text (inserting at the caret). Never sends key events, so Return is never pressed.
    public func insert(_ text: String, into target: FocusIdentity, replacingSelection: Bool) -> Bool {
        guard let id = target.elementID, let element = elements[id] else { return false }
        // The element must still exist and still be editable.
        guard let _: String = copy(element, kAXRoleAttribute) else { return false }
        let subrole: String? = copy(element, kAXSubroleAttribute)
        if subrole == "AXSecureTextField" { return false }
        var names: CFArray?
        AXUIElementCopyAttributeNames(element, &names)
        let isChromium = ((names as? [String]) ?? []).contains("ChromeAXNodeId")
        if InsertionStrategy.method(isChromiumElement: isChromium) == .paste {
            return InsertionStrategy.paste(text)
        }
        let before: String? = copy(element, kAXValueAttribute)
        if AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFString) == .success {
            let after: String? = copy(element, kAXValueAttribute)
            if InsertionStrategy.didInsert(before: before, after: after, text: text) { return true }
            // The write "succeeded" but nothing visibly changed: paste instead (R219).
            return InsertionStrategy.paste(text)
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
        Self.copyAttribute(element, attribute)
    }

    private static func copyAttribute<T>(_ element: AXUIElement, _ attribute: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value else { return nil }
        return value as? T
    }
}
