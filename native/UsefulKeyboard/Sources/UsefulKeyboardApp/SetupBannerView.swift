import AppKit
import AVFoundation
import SwiftUI

struct SetupBannerView: View {
    let readiness: DictationReadiness
    var onNavigateToModels: (() -> Void)?
    var onShowOnboarding: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing12) {
            HStack(spacing: Theme.spacing8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                Text("Dictation requires setup")
                    .font(Theme.headline())
                    .foregroundStyle(Theme.textPrimary)
            }

            VStack(spacing: 0) {
                ForEach(readiness.issues) { issue in
                    issueRow(issue)
                    if issue != readiness.issues.last {
                        Divider().background(Theme.surfaceBorder)
                    }
                }
            }
            .background(Theme.backgroundBase)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerSmall))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerSmall)
                    .strokeBorder(Theme.surfaceBorder, lineWidth: 1)
            )
        }
        .padding(Theme.spacing16)
        .background(Theme.backgroundRaised)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerMedium))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerMedium)
                .strokeBorder(Theme.surfaceBorder, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func issueRow(_ issue: DictationIssue) -> some View {
        HStack(spacing: Theme.spacing12) {
            Image(systemName: issue.icon)
                .font(.system(size: 14))
                .foregroundStyle(Theme.accent)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(issue.title)
                    .font(Theme.body())
                    .foregroundStyle(Theme.textPrimary)
                Text(issue.message)
                    .font(Theme.caption())
                    .foregroundStyle(Theme.textTertiary)
            }

            Spacer()

            Button(action: { handleAction(issue) }) {
                Text(actionLabel(issue))
                    .font(Theme.captionMedium())
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Theme.accentSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cornerSmall))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Theme.spacing12)
        .padding(.vertical, 10)
    }

    private func actionLabel(_ issue: DictationIssue) -> String {
        switch issue {
        case .accessibilityNotGranted, .inputMonitoringNotGranted:
            return "Open Settings"
        case .microphoneNotGranted:
            return "Grant"
        case .modelNotDownloaded:
            return "Download"
        case .onboardingNotCompleted:
            return "Setup"
        }
    }

    private func handleAction(_ issue: DictationIssue) {
        switch issue {
        case .accessibilityNotGranted:
            openSystemSettings("Privacy_Accessibility")
        case .inputMonitoringNotGranted:
            if !CGPreflightListenEventAccess() {
                CGRequestListenEventAccess()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                openSystemSettings("Privacy_ListenEvent")
            }
        case .microphoneNotGranted:
            AVCaptureDevice.requestAccess(for: .audio) { _ in }
        case .modelNotDownloaded:
            onNavigateToModels?()
        case .onboardingNotCompleted:
            onShowOnboarding?()
        }
    }

    private func openSystemSettings(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }
}
