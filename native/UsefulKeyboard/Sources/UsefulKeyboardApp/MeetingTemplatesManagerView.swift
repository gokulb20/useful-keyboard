import SwiftUI
import UsefulKeyboardCore

struct MeetingTemplatesManagerView: View {
    let appState: AppState
    let controller: AppController
    let onClose: () -> Void

    @State private var isCreatingTemplate = false
    @State private var editingTemplateID: String?
    @State private var draftTemplateName = ""
    @State private var draftTemplatePrompt = ""
    @State private var draftTemplateIcon = MeetingTemplates.customIconFallback
    @State private var showNameValidationError = false
    @State private var showPromptValidationError = false
    @State private var templateToDelete: CustomMeetingTemplate?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing20) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Manage Templates")
                        .font(Theme.title2())
                        .foregroundStyle(Theme.textPrimary)
                    Text("Create reusable prompt-based note formats for meetings.")
                        .font(Theme.callout())
                        .foregroundStyle(Theme.textSecondary)
                }

                Spacer()

                HStack(spacing: Theme.spacing8) {
                    if isCreatingTemplate || editingTemplateID != nil {
                        actionButton("Cancel", systemImage: "xmark") {
                            resetTemplateEditor()
                        }
                    } else {
                        actionButton("New template", systemImage: "plus") {
                            beginCreatingTemplate()
                        }
                    }

                    actionButton("Done", systemImage: "checkmark") {
                        onClose()
                    }
                    .disabled(isEditingTemplateInProgress)
                    .opacity(isEditingTemplateInProgress ? 0.55 : 1)
                    .help(isEditingTemplateInProgress ? "Finish or cancel template editing before closing." : "Close template manager")
                }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.spacing12) {
                    if controller.customMeetingTemplates().isEmpty {
                        emptyState
                    } else {
                        VStack(spacing: Theme.spacing8) {
                            ForEach(controller.customMeetingTemplates()) { template in
                                customTemplateRow(template)
                            }
                        }
                    }

                    if isCreatingTemplate || editingTemplateID != nil {
                        customTemplateEditor
                    }
                }
                .padding(.bottom, Theme.spacing4)
            }
        }
        .padding(Theme.spacing24)
        .frame(minWidth: 760, minHeight: 520)
        .background(Theme.backgroundBase)
        .alert(
            "Delete \"\(templateToDelete?.name ?? "")\"?",
            isPresented: Binding(
                get: { templateToDelete != nil },
                set: { if !$0 { templateToDelete = nil } }
            )
        ) {
            Button("Cancel", role: .cancel) {
                templateToDelete = nil
            }
            Button("Delete", role: .destructive) {
                guard let template = templateToDelete else { return }
                controller.deleteCustomMeetingTemplate(id: template.id)
                if editingTemplateID == template.id {
                    resetTemplateEditor()
                }
                templateToDelete = nil
            }
        } message: {
            Text("This template will be permanently removed. Existing meetings will keep their saved template snapshot.")
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        HStack(spacing: Theme.spacing8) {
            Image(systemName: MeetingTemplates.customIconFallback)
                .font(.system(size: 11))
                .foregroundStyle(Theme.textTertiary)
            Text("No custom templates yet.")
                .font(Theme.callout())
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(.horizontal, Theme.spacing12)
        .padding(.vertical, 10)
        .background(Theme.backgroundRaised)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerSmall))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerSmall)
                .strokeBorder(Theme.surfaceBorder, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func customTemplateRow(_ template: CustomMeetingTemplate) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacing8) {
            HStack(alignment: .top, spacing: Theme.spacing12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: template.icon)
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.accent)
                        Text(template.name)
                            .font(Theme.captionMedium())
                            .foregroundStyle(Theme.textPrimary)
                    }
                    Text(template.prompt)
                        .font(Theme.caption())
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(2)
                }
                Spacer()
                HStack(spacing: Theme.spacing8) {
                    actionButton("Edit", systemImage: "pencil") {
                        beginEditingTemplate(template)
                    }
                    actionButton("Delete", systemImage: "trash", role: .destructive) {
                        templateToDelete = template
                    }
                }
            }
        }
        .padding(Theme.spacing12)
        .background(Theme.backgroundRaised)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerSmall))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerSmall)
                .strokeBorder(Theme.surfaceBorder, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var customTemplateEditor: some View {
        VStack(alignment: .leading, spacing: Theme.spacing12) {
            Text(isCreatingTemplate ? "New template" : "Edit template")
                .font(Theme.captionMedium())
                .foregroundStyle(Theme.textPrimary)

            VStack(alignment: .leading, spacing: 6) {
                Text("Name")
                    .font(Theme.caption())
                    .foregroundStyle(Theme.textSecondary)
                TextField("Customer follow-up", text: $draftTemplateName)
                    .textFieldStyle(.roundedBorder)
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(
                                showNameValidationError ? Theme.recording.opacity(0.75) : .clear,
                                lineWidth: 1
                            )
                    }
                    .onChange(of: draftTemplateName) { _, newValue in
                        if !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            showNameValidationError = false
                        }
                    }
                if showNameValidationError {
                    Text("Enter a template name.")
                        .font(Theme.caption())
                        .foregroundStyle(Theme.recording)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Icon")
                    .font(Theme.caption())
                    .foregroundStyle(Theme.textSecondary)
                customIconPicker
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Prompt")
                    .font(Theme.caption())
                    .foregroundStyle(Theme.textSecondary)
                TextEditor(text: $draftTemplatePrompt)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textPrimary)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 140)
                    .padding(Theme.spacing8)
                    .background(Theme.backgroundBase)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cornerSmall))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.cornerSmall)
                            .strokeBorder(
                                showPromptValidationError ? Theme.recording.opacity(0.75) : Theme.surfaceBorder,
                                lineWidth: 1
                            )
                    )
                    .onChange(of: draftTemplatePrompt) { _, newValue in
                        if !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            showPromptValidationError = false
                        }
                    }
                if showPromptValidationError {
                    Text("Enter the prompt instructions for this template.")
                        .font(Theme.caption())
                        .foregroundStyle(Theme.recording)
                }
            }

            HStack {
                Spacer()
                actionButton(
                    isCreatingTemplate ? "Create template" : "Save changes",
                    systemImage: isCreatingTemplate ? "plus.circle" : "checkmark.circle"
                ) {
                    saveTemplateEditor()
                }
            }
        }
        .padding(Theme.spacing12)
        .background(Theme.surfacePrimary.opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerMedium))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerMedium)
                .strokeBorder(Theme.surfaceBorder, lineWidth: 1)
        )
    }

    private func beginCreatingTemplate() {
        isCreatingTemplate = true
        editingTemplateID = nil
        draftTemplateName = ""
        draftTemplatePrompt = ""
        draftTemplateIcon = MeetingTemplates.customIconFallback
        clearValidationErrors()
    }

    private func beginEditingTemplate(_ template: CustomMeetingTemplate) {
        isCreatingTemplate = false
        editingTemplateID = template.id
        draftTemplateName = template.name
        draftTemplatePrompt = template.prompt
        draftTemplateIcon = MeetingTemplates.normalizedCustomIcon(named: template.icon)
        clearValidationErrors()
    }

    private func resetTemplateEditor() {
        isCreatingTemplate = false
        editingTemplateID = nil
        draftTemplateName = ""
        draftTemplatePrompt = ""
        draftTemplateIcon = MeetingTemplates.customIconFallback
        clearValidationErrors()
    }

    private func saveTemplateEditor() {
        let trimmedName = draftTemplateName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPrompt = draftTemplatePrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        showNameValidationError = trimmedName.isEmpty
        showPromptValidationError = trimmedPrompt.isEmpty
        guard !trimmedName.isEmpty, !trimmedPrompt.isEmpty else { return }

        if let editingTemplateID {
            controller.updateCustomMeetingTemplate(
                id: editingTemplateID,
                name: trimmedName,
                prompt: trimmedPrompt,
                icon: draftTemplateIcon
            )
        } else {
            controller.createCustomMeetingTemplate(
                name: trimmedName,
                prompt: trimmedPrompt,
                icon: draftTemplateIcon
            )
        }
        resetTemplateEditor()
    }

    private var isEditingTemplateInProgress: Bool {
        isCreatingTemplate || editingTemplateID != nil
    }

    private func clearValidationErrors() {
        showNameValidationError = false
        showPromptValidationError = false
    }

    @ViewBuilder
    private var customIconPicker: some View {
        let columns = [
            GridItem(.adaptive(minimum: 36, maximum: 36), spacing: 6)
        ]

        VStack(alignment: .leading, spacing: Theme.spacing8) {
            HStack(spacing: Theme.spacing8) {
                Image(systemName: draftTemplateIcon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 24, height: 24)
                    .background(Theme.accentSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cornerSmall))
                Text(selectedIconLabel)
                    .font(Theme.caption())
                    .foregroundStyle(Theme.textSecondary)
            }

            LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
                ForEach(MeetingTemplates.customIconOptions) { icon in
                    Button {
                        draftTemplateIcon = icon.symbolName
                    } label: {
                        Image(systemName: icon.symbolName)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(
                                draftTemplateIcon == icon.symbolName
                                    ? Theme.accent
                                    : Theme.textSecondary
                            )
                            .frame(maxWidth: .infinity, minHeight: 28)
                            .background(
                                RoundedRectangle(cornerRadius: Theme.cornerSmall)
                                    .fill(
                                        draftTemplateIcon == icon.symbolName
                                            ? Theme.accent.opacity(0.12)
                                            : Theme.backgroundRaised
                                    )
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: Theme.cornerSmall)
                                    .strokeBorder(
                                        draftTemplateIcon == icon.symbolName
                                            ? Theme.accent.opacity(0.35)
                                            : Theme.surfaceBorder,
                                        lineWidth: 1
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                    .help(icon.label)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var selectedIconLabel: String {
        MeetingTemplates.customIconOptions.first(where: { $0.symbolName == draftTemplateIcon })?.label ?? "Custom"
    }

    @ViewBuilder
    private func actionButton(
        _ title: String,
        systemImage: String,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        let isDestructive = role == .destructive
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .semibold))
                Text(title)
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(isDestructive ? Theme.recording : Theme.textPrimary)
            .padding(.horizontal, Theme.spacing12)
            .padding(.vertical, 7)
            .background(isDestructive ? Theme.recording.opacity(0.1) : Theme.surfacePrimary)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerSmall))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerSmall)
                    .strokeBorder(
                        isDestructive ? Theme.recording.opacity(0.2) : Theme.surfaceBorder,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
    }
}
