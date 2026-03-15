import AppKit
import CoreAudio
import Foundation

@MainActor
final class MicActivityMonitor {
    var onMeetingAppDetected: ((String) -> Void)?
    private var timer: Timer?
    private var lastDetectedBundleID: String?
    private var suppressUntil: Date?
    private var recentlyActivatedMeetingApp: (bundleID: String, name: String, at: Date)?
    private var workspaceObserver: NSObjectProtocol?

    private static let meetingApps: [String: String] = [
        "us.zoom.xos": "Zoom",
        "us.zoom.ZoomPhone": "Zoom Phone",
        "com.google.Chrome": "Chrome",
        "com.apple.FaceTime": "FaceTime",
        "com.microsoft.teams2": "Teams",
        "com.microsoft.teams": "Teams",
        "com.tinyspeck.slackmacgap": "Slack",
        "com.brave.Browser": "Brave",
        "company.thebrowser.Browser": "Arc",
        "org.mozilla.firefox": "Firefox",
        "com.apple.Safari": "Safari",
        "com.webex.meetingmanager": "Webex",
        "com.cisco.webexmeetingsapp": "Webex",
    ]

    /// Our own bundle ID — never trigger for our own mic usage
    private static let selfBundleID = Bundle.main.bundleIdentifier ?? "com.muesli.app"

    func start() {
        guard timer == nil else { return }

        // Watch for app activations to know when a meeting app comes to foreground
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let bundleID = app.bundleIdentifier,
                  let appName = Self.meetingApps[bundleID] else { return }
            self?.recentlyActivatedMeetingApp = (bundleID, appName, Date())
        }

        timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.poll()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let observer = workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            workspaceObserver = nil
        }
    }

    /// Suppress notifications for a period (after dismiss or start recording)
    func suppress(for duration: TimeInterval = 120) {
        suppressUntil = Date().addingTimeInterval(duration)
    }

    /// Call this when Muesli's own dictation starts/stops to prevent false triggers
    func noteDictationActive() {
        // Suppress for a short window after our own dictation
        suppressUntil = Date().addingTimeInterval(10)
    }

    private func poll() {
        guard isMicInUse() else {
            // Mic not in use — reset detection so we can re-trigger next time
            if lastDetectedBundleID != nil {
                lastDetectedBundleID = nil
            }
            return
        }

        // Check if suppressed (our own dictation or user dismissed)
        if let until = suppressUntil, Date() < until {
            return
        }

        // Only trigger if a meeting app was activated recently (within last 5 minutes)
        // This avoids triggering on our own mic usage
        guard let recent = recentlyActivatedMeetingApp,
              Date().timeIntervalSince(recent.at) < 300 else { return }

        // Only trigger once per app session
        if lastDetectedBundleID == recent.bundleID { return }

        // Verify the meeting app is still running
        let stillRunning = NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == recent.bundleID
        }
        guard stillRunning else { return }

        lastDetectedBundleID = recent.bundleID
        fputs("[mic-monitor] meeting app detected: \(recent.name) (\(recent.bundleID))\n", stderr)
        onMeetingAppDetected?(recent.name)
    }

    private func isMicInUse() -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)

        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address, 0, nil, &size, &deviceID
        ) == noErr else { return false }

        var isRunning: UInt32 = 0
        var runningAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        size = UInt32(MemoryLayout<UInt32>.size)

        guard AudioObjectGetPropertyData(
            deviceID, &runningAddress, 0, nil, &size, &isRunning
        ) == noErr else { return false }

        return isRunning != 0
    }
}
