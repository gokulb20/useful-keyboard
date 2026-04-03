import Foundation

/// Pure logic engine for context detection. No system dependencies, fully testable.
/// Merges signals from multiple providers and resolves a context profile via user rules.
final class ContextEngine: @unchecked Sendable {

    // MARK: - Current signal state

    private(set) var activeApp: ActiveAppContext?
    private(set) var calendarEvent: RichCalendarContext?
    private(set) var contentHints: [ContentHint] = []

    // MARK: - Configuration

    private(set) var rules: [ContextRule] = ContextRule.defaults
    private(set) var profiles: [ContextProfile] = ContextProfile.defaults

    // MARK: - Signal updates

    func updateActiveApp(_ app: ActiveAppContext?) {
        activeApp = app
    }

    func updateCalendarEvent(_ event: RichCalendarContext?) {
        calendarEvent = event
    }

    func updateContentHints(_ hints: [ContentHint]) {
        contentHints = hints
    }

    // MARK: - Configuration updates

    func setRules(_ rules: [ContextRule]) {
        self.rules = rules
    }

    func setProfiles(_ profiles: [ContextProfile]) {
        self.profiles = profiles
    }

    // MARK: - Resolution

    /// Resolve current signals + rules into a full AppContext.
    func resolve(now: Date = Date()) -> AppContext {
        let profile = resolveProfile()
        return AppContext(
            timestamp: now,
            activeApp: activeApp,
            calendarEvent: calendarEvent,
            contentHints: contentHints,
            resolvedProfile: profile
        )
    }

    /// Capture a point-in-time snapshot (for dictation).
    func snapshot(now: Date = Date()) -> AppContext {
        resolve(now: now)
    }

    /// Find the highest-priority matching profile based on current signals and rules.
    func resolveProfile() -> ContextProfile? {
        let matchingRules = rules
            .filter(\.enabled)
            .filter { $0.condition.matches(activeApp: activeApp, calendarEvent: calendarEvent) }
            .sorted { $0.priority > $1.priority }

        guard let bestRule = matchingRules.first else { return nil }
        return profiles.first { $0.id == bestRule.profileID }
    }

    /// Reset all signal state (useful after idle periods).
    func reset() {
        activeApp = nil
        calendarEvent = nil
        contentHints = []
    }
}
