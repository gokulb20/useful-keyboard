import Foundation

/// A user-defined rule that maps a condition to a context profile.
struct ContextRule: Codable, Equatable, Identifiable, Sendable {
    var id: String = UUID().uuidString
    var name: String
    var condition: RuleCondition
    var profileID: String
    var priority: Int = 0
    var enabled: Bool = true

    static let defaults: [ContextRule] = [
        ContextRule(
            id: "default-chat",
            name: "Chat apps",
            condition: .appCategory(.chat),
            profileID: "builtin-casual",
            priority: 0
        ),
        ContextRule(
            id: "default-email",
            name: "Email",
            condition: .appCategory(.email),
            profileID: "builtin-professional",
            priority: 0
        ),
        ContextRule(
            id: "default-ide",
            name: "IDE",
            condition: .appCategory(.ide),
            profileID: "builtin-technical",
            priority: 0
        ),
        ContextRule(
            id: "default-terminal",
            name: "Terminal",
            condition: .appCategory(.terminal),
            profileID: "builtin-technical",
            priority: 0
        ),
        ContextRule(
            id: "default-notes",
            name: "Notes apps",
            condition: .appCategory(.notes),
            profileID: "builtin-notes",
            priority: 0
        ),
    ]
}

/// Condition that determines when a rule activates.
enum RuleCondition: Codable, Equatable, Sendable {
    case appBundleID(String)
    case appCategory(AppCategory)
    case meetingTitleContains(String)
    case browserURLContains(String)
    case compound([RuleCondition], logic: Logic)

    enum Logic: String, Codable, Sendable {
        case all
        case any
    }

    /// Evaluate this condition against the current context signals.
    func matches(
        activeApp: ActiveAppContext?,
        calendarEvent: RichCalendarContext?
    ) -> Bool {
        switch self {
        case .appBundleID(let bundleID):
            return activeApp?.bundleID == bundleID

        case .appCategory(let category):
            return activeApp?.category == category

        case .meetingTitleContains(let substring):
            guard let title = calendarEvent?.title else { return false }
            return title.localizedCaseInsensitiveContains(substring)

        case .browserURLContains(let substring):
            guard let url = activeApp?.browserTabURL else { return false }
            return url.localizedCaseInsensitiveContains(substring)

        case .compound(let conditions, let logic):
            switch logic {
            case .all:
                return conditions.allSatisfy { $0.matches(activeApp: activeApp, calendarEvent: calendarEvent) }
            case .any:
                return conditions.contains { $0.matches(activeApp: activeApp, calendarEvent: calendarEvent) }
            }
        }
    }
}
