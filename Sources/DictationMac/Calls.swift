import CoreAudio
import DictationCore
import Foundation

/// Detects calls: a known call app is running while the microphone is in use elsewhere (M13).
public enum CallDetector {
    public static func callKind(forBundleID id: String) -> CallAppKind {
        switch id {
        case "com.apple.FaceTime": return .faceTime
        case "us.zoom.xos": return .zoomMeeting
        case "com.microsoft.teams", "com.microsoft.teams2": return .teamsMeeting
        case "com.cisco.webexmeetingsapp", "Cisco-Systems.Spark", "com.webex.meetingmanager": return .webexMeeting
        default: return .none
        }
    }

    public static func activeCall(runningBundleIDs: [String], micInUseElsewhere: Bool) -> CallAppKind {
        guard micInUseElsewhere else { return .none }
        for id in runningBundleIDs {
            let kind = callKind(forBundleID: id)
            if kind != .none { return kind }
        }
        return .none
    }

    /// Whether the default input device is running for any process (CoreAudio).
    public static func defaultInputIsRunningSomewhere() -> Bool {
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
            == noErr, device != 0 else { return false }
        var running: UInt32 = 0
        size = UInt32(MemoryLayout<UInt32>.size)
        address.mSelector = kAudioDevicePropertyDeviceIsRunningSomewhere
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &running) == noErr else { return false }
        return running != 0
    }
}
