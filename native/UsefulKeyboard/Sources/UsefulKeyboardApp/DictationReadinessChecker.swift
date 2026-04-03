import ApplicationServices
import AVFoundation
import Foundation

enum DictationIssue: Equatable, Identifiable {
    case accessibilityNotGranted
    case inputMonitoringNotGranted
    case microphoneNotGranted
    case modelNotDownloaded
    case onboardingNotCompleted

    var id: String {
        switch self {
        case .accessibilityNotGranted: return "accessibility"
        case .inputMonitoringNotGranted: return "input_monitoring"
        case .microphoneNotGranted: return "microphone"
        case .modelNotDownloaded: return "model"
        case .onboardingNotCompleted: return "onboarding"
        }
    }

    var icon: String {
        switch self {
        case .accessibilityNotGranted: return "hand.raised.fill"
        case .inputMonitoringNotGranted: return "keyboard.fill"
        case .microphoneNotGranted: return "mic.slash.fill"
        case .modelNotDownloaded: return "square.and.arrow.down"
        case .onboardingNotCompleted: return "checkmark.circle"
        }
    }

    var title: String {
        switch self {
        case .accessibilityNotGranted: return "Accessibility"
        case .inputMonitoringNotGranted: return "Input Monitoring"
        case .microphoneNotGranted: return "Microphone"
        case .modelNotDownloaded: return "Speech Model"
        case .onboardingNotCompleted: return "Setup"
        }
    }

    var message: String {
        switch self {
        case .accessibilityNotGranted:
            return "Required to paste transcribed text into apps"
        case .inputMonitoringNotGranted:
            return "Required to detect your dictation hotkey"
        case .microphoneNotGranted:
            return "Required to record audio for transcription"
        case .modelNotDownloaded:
            return "Download a speech model to transcribe audio"
        case .onboardingNotCompleted:
            return "Complete initial setup to start dictating"
        }
    }

    var settingsPane: String? {
        switch self {
        case .accessibilityNotGranted: return "Privacy_Accessibility"
        case .inputMonitoringNotGranted: return "Privacy_ListenEvent"
        case .microphoneNotGranted: return nil
        case .modelNotDownloaded: return nil
        case .onboardingNotCompleted: return nil
        }
    }
}

struct DictationReadiness: Equatable {
    let issues: [DictationIssue]

    var isReady: Bool { issues.isEmpty }

    static func check(config: AppConfig, backend: BackendOption) -> DictationReadiness {
        var issues: [DictationIssue] = []

        if !config.hasCompletedOnboarding {
            issues.append(.onboardingNotCompleted)
        }

        if !backend.isDownloaded {
            issues.append(.modelNotDownloaded)
        }

        if AVCaptureDevice.authorizationStatus(for: .audio) != .authorized {
            issues.append(.microphoneNotGranted)
        }

        if !AXIsProcessTrusted() {
            issues.append(.accessibilityNotGranted)
        }

        if !CGPreflightListenEventAccess() {
            issues.append(.inputMonitoringNotGranted)
        }

        return DictationReadiness(issues: issues)
    }
}
