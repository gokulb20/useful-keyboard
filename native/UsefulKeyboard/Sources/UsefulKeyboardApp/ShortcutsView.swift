import SwiftUI
import AppKit
import UsefulKeyboardCore

struct ShortcutsView: View {
    let appState: AppState
    let controller: AppController
    @State private var isRecording = false
    @State private var eventMonitor: Any?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacing24) {
                Text("Shortcuts")
                    .font(Theme.title1())
                    .foregroundStyle(Theme.textPrimary)

                Text("Choose your preferred shortcut for dictation.")
                    .font(Theme.body())
                    .foregroundStyle(Theme.textSecondary)

                shortcutSection

                doubleTapSection

                resetButton
            }
            .padding(Theme.spacing32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onDisappear {
            stopRecording()
        }
    }

    private var shortcutSection: some View {
        VStack(alignment: .leading, spacing: Theme.spacing16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: Theme.spacing4) {
                    Text("Push to Talk")
                        .font(Theme.headline())
                        .foregroundStyle(Theme.textPrimary)
                    Text("Hold to record, release to transcribe")
                        .font(Theme.caption())
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                hotkeyBadge
            }

            Divider()
                .background(Theme.surfaceBorder)

            changeButton
        }
        .padding(Theme.spacing16)
        .background(Theme.backgroundRaised)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerMedium))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerMedium)
                .strokeBorder(Theme.surfaceBorder, lineWidth: 1)
        )
    }

    private var hotkeyBadge: some View {
        Text(appState.config.dictationHotkey.label)
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, Theme.spacing12)
            .padding(.vertical, Theme.spacing4)
            .background(Theme.surfacePrimary)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerSmall))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerSmall)
                    .strokeBorder(Theme.surfaceBorder, lineWidth: 1)
            )
    }

    private var changeButton: some View {
        Button {
            if isRecording {
                stopRecording()
            } else {
                startRecording()
            }
        } label: {
            Text(isRecording ? "Press a modifier key..." : "Change Shortcut")
                .font(Theme.body())
                .foregroundStyle(isRecording ? Theme.accent : Theme.textPrimary)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, Theme.spacing12)
        .padding(.vertical, Theme.spacing8)
        .background(isRecording ? Theme.accentSubtle : Theme.surfacePrimary)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerSmall))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerSmall)
                .strokeBorder(isRecording ? Theme.accent.opacity(0.3) : Theme.surfaceBorder, lineWidth: 1)
        )
    }

    private var doubleTapSection: some View {
        VStack(alignment: .leading, spacing: Theme.spacing16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: Theme.spacing4) {
                    Text("Hands-Free Mode")
                        .font(Theme.headline())
                        .foregroundStyle(Theme.textPrimary)
                    Text("Double-tap to start, tap again to stop")
                        .font(Theme.caption())
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { appState.config.enableDoubleTapDictation },
                    set: { newValue in
                        controller.updateConfig { $0.enableDoubleTapDictation = newValue }
                    }
                ))
                .toggleStyle(.switch)
                .tint(Theme.accent)
                .labelsHidden()
            }
        }
        .padding(Theme.spacing16)
        .background(Theme.backgroundRaised)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerMedium))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerMedium)
                .strokeBorder(Theme.surfaceBorder, lineWidth: 1)
        )
    }

    private var resetButton: some View {
        Button {
            controller.updateDictationHotkey(.default)
        } label: {
            Text("Reset to Default")
                .font(Theme.body())
                .foregroundStyle(Theme.textSecondary)
        }
        .buttonStyle(.plain)
        .disabled(appState.config.dictationHotkey == .default)
    }

    private func startRecording() {
        isRecording = true
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [self] event in
            let keyCode = event.keyCode
            if let label = HotkeyConfig.label(for: keyCode) {
                let newConfig = HotkeyConfig(keyCode: keyCode, label: label)
                controller.updateDictationHotkey(newConfig)
                stopRecording()
            }
            return event
        }
    }

    private func stopRecording() {
        isRecording = false
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
}
