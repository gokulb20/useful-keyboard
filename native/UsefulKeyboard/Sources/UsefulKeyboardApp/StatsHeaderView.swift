import SwiftUI
import UsefulKeyboardCore

struct StatsHeaderView: View {
    let dictationStats: DictationStats
    let meetingStats: MeetingStats

    var body: some View {
        HStack(spacing: Theme.spacing16) {
            StatCard(
                icon: "flame.fill",
                iconColor: .orange,
                value: "\(dictationStats.currentStreakDays)",
                label: "day streak"
            )
            StatCard(
                icon: "character.cursor.ibeam",
                iconColor: Theme.accent,
                value: formatWordCount(dictationStats.totalWords),
                label: "words dictated"
            )
            StatCard(
                icon: "gauge.with.dots.needle.33percent",
                iconColor: Theme.success,
                value: String(format: "%.0f", dictationStats.averageWPM),
                label: "avg WPM"
            )
            StatCard(
                icon: "person.2.fill",
                iconColor: Theme.accent,
                value: "\(meetingStats.totalMeetings)",
                label: "meetings"
            )
        }
        .padding(.horizontal, Theme.spacing24)
        .padding(.vertical, Theme.spacing20)
    }

    private func formatWordCount(_ count: Int) -> String {
        if count >= 1000 {
            return String(format: "%.1fk", Double(count) / 1000.0)
        }
        return "\(count)"
    }
}

private struct StatCard: View {
    let icon: String
    let iconColor: Color
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: Theme.spacing8) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(iconColor)
            Text(value)
                .font(Theme.title2())
                .foregroundStyle(Theme.textPrimary)
                .contentTransition(.numericText())
            Text(label)
                .font(Theme.caption())
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(Theme.spacing16)
        .background(Theme.backgroundRaised)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerMedium))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerMedium)
                .strokeBorder(Theme.surfaceBorder, lineWidth: 1)
        )
    }
}
