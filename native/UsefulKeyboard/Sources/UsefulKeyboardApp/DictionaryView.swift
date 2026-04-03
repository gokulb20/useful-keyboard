import SwiftUI
import UsefulKeyboardCore

struct DictionaryView: View {
    let appState: AppState
    let controller: AppController
    @State private var isAdding = false
    @State private var newWord = ""
    @State private var newReplacement = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacing24) {
                header
                wordList
            }
            .padding(Theme.spacing32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.backgroundBase)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.spacing8) {
            HStack {
                Text("Dictionary")
                    .font(Theme.title1())
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Button {
                    isAdding = true
                    newWord = ""
                    newReplacement = ""
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .bold))
                        Text("Add new")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, Theme.spacing12)
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
            Text("Add custom words to improve transcription accuracy for names, brands, and domain terms.")
                .font(Theme.body())
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private var wordList: some View {
        VStack(spacing: 0) {
            if isAdding {
                addWordRow
                Divider().background(Theme.surfaceBorder)
            }

            if appState.config.customWords.isEmpty && !isAdding {
                emptyState
            } else {
                ForEach(appState.config.customWords) { word in
                    wordRow(word)
                    Divider().background(Theme.surfaceBorder)
                }
            }
        }
        .background(Theme.backgroundRaised)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerMedium))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerMedium)
                .strokeBorder(Theme.surfaceBorder, lineWidth: 1)
        )
    }

    private var emptyState: some View {
        VStack(spacing: Theme.spacing8) {
            Image(systemName: "character.book.closed")
                .font(.system(size: 28))
                .foregroundStyle(Theme.textTertiary)
            Text("No custom words yet")
                .font(Theme.body())
                .foregroundStyle(Theme.textSecondary)
            Text("Add words that Whisper frequently gets wrong")
                .font(Theme.caption())
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(Theme.spacing32)
    }

    private func wordRow(_ word: CustomWord) -> some View {
        HStack {
            if let replacement = word.replacement, !replacement.isEmpty {
                Text(word.word)
                    .font(Theme.body())
                    .foregroundStyle(Theme.textSecondary)
                Image(systemName: "arrow.right")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textTertiary)
                Text(replacement)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
            } else {
                Text(word.word)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
            }
            Spacer()
            Button {
                controller.removeCustomWord(id: word.id)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Theme.spacing16)
        .padding(.vertical, Theme.spacing12)
    }

    private var addWordRow: some View {
        HStack(spacing: Theme.spacing8) {
            TextField("Word", text: $newWord)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 180)

            Text("→")
                .font(Theme.body())
                .foregroundStyle(Theme.textTertiary)

            TextField("Replace with (optional)", text: $newReplacement)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 200)

            Button {
                let trimmed = newWord.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                let replacement = newReplacement.trimmingCharacters(in: .whitespacesAndNewlines)
                let word = CustomWord(
                    word: trimmed,
                    replacement: replacement.isEmpty ? nil : replacement
                )
                controller.addCustomWord(word)
                newWord = ""
                newReplacement = ""
                isAdding = false
            } label: {
                Text("Add")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.accent)
            }
            .buttonStyle(.plain)
            .disabled(newWord.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Button {
                isAdding = false
                newWord = ""
                newReplacement = ""
            } label: {
                Text("Cancel")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Theme.spacing16)
        .padding(.vertical, Theme.spacing12)
    }
}
