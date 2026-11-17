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

/// Which permissions are missing. Reporting only; `PermissionRequestSequence` decides what to request.
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

/// Asks macOS for one permission at a time. When several prompts are requested together,
/// macOS shows only one, so the next request waits until the current permission is granted.
/// Order: Microphone (in-app prompt), Accessibility (live grant), Input Monitoring last
/// because macOS often asks to relaunch the app after that grant.
public struct PermissionRequestSequence: Sendable, Equatable {
    public static let order: [PermissionKind] = [.microphone, .accessibility, .inputMonitoring]
    public private(set) var requested: Set<PermissionKind> = []

    public init() {}

    /// The first permission in `order` that is not yet granted.
    public static func current(granted: Set<PermissionKind>) -> PermissionKind? {
        order.first { !granted.contains($0) }
    }

    /// The permission to request now, or nil when the current one is already requested
    /// and still waiting for a grant, or when every permission in `order` is granted.
    public mutating func next(granted: Set<PermissionKind>) -> PermissionKind? {
        guard let kind = Self.current(granted: granted), !requested.contains(kind) else { return nil }
        requested.insert(kind)
        return kind
    }
}
