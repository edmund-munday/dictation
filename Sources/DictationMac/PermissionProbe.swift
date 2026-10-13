import AVFoundation
import ApplicationServices
import CoreGraphics
import Foundation
import Speech

/// Reads current permission status without prompting.
public enum PermissionProbe {
    public static func current(needsSpeechRecognition: Bool) -> PermissionReport {
        var granted: Set<PermissionKind> = []
        if AVCaptureDevice.authorizationStatus(for: .audio) == .authorized { granted.insert(.microphone) }
        if AXIsProcessTrusted() { granted.insert(.accessibility) }
        if CGPreflightListenEventAccess() { granted.insert(.inputMonitoring) }
        if SFSpeechRecognizer.authorizationStatus() == .authorized { granted.insert(.speechRecognition) }
        return PermissionReport(granted: granted, needsSpeechRecognition: needsSpeechRecognition)
    }
}
