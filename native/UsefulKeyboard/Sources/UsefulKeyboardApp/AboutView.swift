import SwiftUI
import UsefulKeyboardCore

struct AboutView: View {
    let controller: AppController

    private var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.2.0"
        return "v\(v)"
    }

    private var appDataPath: String {
        AppIdentity.supportDirectoryURL.path
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacing32) {
                Text("About")
                    .font(Theme.title1())
                    .foregroundStyle(Theme.textPrimary)

                // MARK: - App Info
                sectionHeader("App Info")
                aboutCard {
                    aboutRow("Version") {
                        Text(version)
                            .font(.system(size: 15, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Theme.textPrimary)
                    }

                    Divider().background(Theme.surfaceBorder)

                    aboutRow("Check for Updates") {
                        actionButton("Check Now", icon: "arrow.triangle.2.circlepath") {
                            // TODO: Wire to Sparkle SPUStandardUpdaterController
                        }
                    }
                }

                // MARK: - Data
                sectionHeader("Data")
                aboutCard {
                    VStack(alignment: .leading, spacing: Theme.spacing12) {
                        Text("App Data Directory")
                            .font(Theme.body())
                            .foregroundStyle(Theme.textPrimary)

                        HStack {
                            Text(appDataPath)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(Theme.textTertiary)
                                .lineLimit(2)
                                .truncationMode(.middle)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            actionButton("Open", icon: "folder") {
                                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: appDataPath)
                            }
                        }
                    }
                }

                // MARK: - Acknowledgements
                sectionHeader("Acknowledgements")
                aboutCard {
                    acknowledgement(
                        name: "FluidAudio by FluidInference",
                        description: "CoreML speech stack powering Parakeet, Qwen3 ASR, Silero VAD, and speaker diarization on Apple Silicon."
                    )
                    Divider().background(Theme.surfaceBorder)
                    acknowledgement(
                        name: "whisper.cpp",
                        description: "Local Whisper inference engine used for the app's Whisper Small, Medium, and Large Turbo backends."
                    )
                }

                Spacer(minLength: Theme.spacing32)
            }
            .padding(Theme.spacing32)
        }
        .background(Theme.backgroundBase)
    }

    // MARK: - Components

    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Theme.textTertiary)
            .textCase(.uppercase)
            .padding(.leading, 2)
    }

    @ViewBuilder
    private func aboutCard(@ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .padding(Theme.spacing20)
        .background(Theme.backgroundRaised)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerMedium))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerMedium)
                .strokeBorder(Theme.surfaceBorder, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func aboutRow(_ label: String, @ViewBuilder control: () -> some View) -> some View {
        HStack {
            Text(label)
                .font(Theme.body())
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            control()
        }
        .padding(.vertical, Theme.spacing8)
    }

    @ViewBuilder
    private func acknowledgement(name: String, description: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacing4) {
            Text(name)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text(description)
                .font(Theme.callout())
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Theme.spacing8)
    }

    @ViewBuilder
    private func actionButton(_ title: String, icon: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 11))
                }
                Text(title)
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, Theme.spacing16)
            .padding(.vertical, Theme.spacing8)
            .background(Theme.surfacePrimary)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerSmall))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerSmall)
                    .strokeBorder(Theme.surfaceBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
