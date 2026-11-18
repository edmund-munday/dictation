import CoreAudio
import DictationCore
import Foundation

/// Detects calls (M13). On macOS 14 and later a call is a call app (or one of its helper
/// processes) that is itself capturing microphone input. Before macOS 14 the system cannot
/// say which process records, so a call is a call app running while the input device is in
/// use by anything. The per-process check stops a Teams window left open all day, plus any
/// other program using the mic, from pausing dictation.
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

    /// The call kind for a process that records audio: a call app, one of its helpers
    /// (bundle ID prefixed by the app's, e.g. `com.microsoft.teams2.helper`), or the
    /// FaceTime audio daemon.
    public static func callKind(forCapturingBundleID id: String) -> CallAppKind {
        if id == "com.apple.avconferenced" { return .faceTime }
        let direct = callKind(forBundleID: id)
        if direct != .none { return direct }
        let apps = ["com.apple.FaceTime", "us.zoom.xos", "com.microsoft.teams", "com.microsoft.teams2",
                    "com.cisco.webexmeetingsapp", "Cisco-Systems.Spark", "com.webex.meetingmanager"]
        for app in apps where id.hasPrefix(app + ".") {
            return callKind(forBundleID: app)
        }
        return .none
    }

    /// A call from the bundle IDs of the processes currently capturing input.
    public static func activeCall(capturingBundleIDs: [String]) -> CallAppKind {
        for id in capturingBundleIDs {
            let kind = callKind(forCapturingBundleID: id)
            if kind != .none { return kind }
        }
        return .none
    }

    /// Fallback for macOS 13: a call app running while the input device is in use anywhere.
    public static func activeCall(runningBundleIDs: [String], micInUseElsewhere: Bool) -> CallAppKind {
        guard micInUseElsewhere else { return .none }
        for id in runningBundleIDs {
            let kind = callKind(forBundleID: id)
            if kind != .none { return kind }
        }
        return .none
    }

    /// The current call, using the per-process check where the system supports it.
    public static func currentCall(runningBundleIDs: [String]) -> CallAppKind {
        if let capturing = bundleIDsCapturingInput() {
            return activeCall(capturingBundleIDs: capturing)
        }
        return activeCall(runningBundleIDs: runningBundleIDs, micInUseElsewhere: defaultInputIsRunningSomewhere())
    }

    /// Bundle IDs of processes capturing audio input right now, or nil when the system
    /// cannot report it (before macOS 14, or the query fails).
    public static func bundleIDsCapturingInput() -> [String]? {
        guard #available(macOS 14.0, *) else { return nil }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return nil }
        var processes = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &processes) == noErr else { return nil }

        var result: [String] = []
        for process in processes {
            var running: UInt32 = 0
            var runningSize = UInt32(MemoryLayout<UInt32>.size)
            var runningAddress = AudioObjectPropertyAddress(
                mSelector: kAudioProcessPropertyIsRunningInput,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain)
            guard AudioObjectGetPropertyData(process, &runningAddress, 0, nil, &runningSize, &running) == noErr,
                  running != 0 else { continue }
            var bundle: Unmanaged<CFString>?
            var bundleSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            var bundleAddress = AudioObjectPropertyAddress(
                mSelector: kAudioProcessPropertyBundleID,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain)
            if AudioObjectGetPropertyData(process, &bundleAddress, 0, nil, &bundleSize, &bundle) == noErr,
               let id = bundle?.takeRetainedValue() as String?, !id.isEmpty {
                result.append(id)
            }
        }
        return result
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
