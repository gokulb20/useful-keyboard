import SwiftUI
import UsefulKeyboardCore

struct MeetingNotesView: View {
    let markdown: String

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Theme.spacing4) {
                let lines = markdown.components(separatedBy: .newlines)
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    markdownLine(line.trimmingCharacters(in: .whitespaces))
                }
            }
            .frame(maxWidth: 860, alignment: .leading)
            .padding(Theme.spacing24)
            .frame(maxWidth: .infinity, alignment: .center)
            .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private func markdownLine(_ line: String) -> some View {
        if line.isEmpty {
            Spacer()
                .frame(height: Theme.spacing8)
        } else if line.hasPrefix("# ") {
            Text(String(line.dropFirst(2)))
                .font(Theme.title1())
                .foregroundStyle(Theme.textPrimary)
                .padding(.top, Theme.spacing12)
        } else if line.hasPrefix("## ") {
            Text(String(line.dropFirst(3)))
                .font(Theme.title3())
                .foregroundStyle(Theme.textPrimary)
                .padding(.top, Theme.spacing8)
        } else if line.hasPrefix("### ") {
            Text(String(line.dropFirst(4)))
                .font(Theme.headline())
                .foregroundStyle(Theme.textPrimary)
                .padding(.top, Theme.spacing4)
        } else if line.hasPrefix("- [ ] ") {
            HStack(alignment: .firstTextBaseline, spacing: Theme.spacing8) {
                Image(systemName: "square")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textTertiary)
                Text(String(line.dropFirst(6)))
                    .font(Theme.body())
                    .foregroundStyle(Theme.textSecondary)
            }
        } else if line.hasPrefix("- [x] ") || line.hasPrefix("- [X] ") {
            HStack(alignment: .firstTextBaseline, spacing: Theme.spacing8) {
                Image(systemName: "checkmark.square")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.success)
                Text(String(line.dropFirst(6)))
                    .font(Theme.body())
                    .foregroundStyle(Theme.textSecondary)
            }
        } else if line.hasPrefix("- ") {
            HStack(alignment: .firstTextBaseline, spacing: Theme.spacing8) {
                Circle()
                    .fill(Theme.textTertiary)
                    .frame(width: 4, height: 4)
                    .offset(y: -2)
                Text(String(line.dropFirst(2)))
                    .font(Theme.body())
                    .foregroundStyle(Theme.textSecondary)
            }
        } else if line.hasPrefix("**") && line.hasSuffix("**") {
            Text(String(line.dropFirst(2).dropLast(2)))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
        } else {
            Text(line)
                .font(Theme.body())
                .foregroundStyle(Theme.textPrimary)
        }
    }
}
