import Foundation

/// The macOS privacy permissions the app depends on (M14).
public enum PermissionKind: String, CaseIterable, Sendable, Hashable {
    case microphone
    case accessibility
    case inputMonitoring
    case speechRecognition

    public var title: String {
        switch self {
        case .microphone: return "Microphone"
        case .accessibility: return "Accessibility"
        case .inputMonitoring: return "Input Monitoring"
        case .speechRecognition: return "Speech Recognition"
        }
    }

    public var settingsURL: URL {
        let anchor: String
        switch self {
        case .microphone: anchor = "Privacy_Microphone"
        case .accessibility: anchor = "Privacy_Accessibility"
        case .inputMonitoring: anchor = "Privacy_ListenEvent"
        case .speechRecognition: anchor = "Privacy_SpeechRecognition"
        }
        return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")!
    }
}

/// Which permissions are missing. Reporting only; the app never requests a grant itself.
public struct PermissionReport: Sendable, Equatable {
    public var granted: Set<PermissionKind>
    public var needsSpeechRecognition: Bool

    public init(granted: Set<PermissionKind>, needsSpeechRecognition: Bool) {
        self.granted = granted
        self.needsSpeechRecognition = needsSpeechRecognition
    }

    public var missing: [PermissionKind] {
        PermissionKind.allCases.filter { kind in
            if kind == .speechRecognition && !needsSpeechRecognition { return false }
            return !granted.contains(kind)
        }
    }

    public var summary: String {
        let m = missing
        if m.isEmpty { return "All permissions granted." }
        return "Missing: " + m.map(\.title).joined(separator: ", ")
    }
}
