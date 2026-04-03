import Testing
import Foundation
@testable import UsefulKeyboardApp

@Suite("ContextEngine")
struct ContextEngineTests {

    private func makeEngine() -> ContextEngine {
        let engine = ContextEngine()
        engine.setProfiles(ContextProfile.defaults)
        engine.setRules(ContextRule.defaults)
        return engine
    }

    private func slackApp() -> ActiveAppContext {
        ActiveAppContext(bundleID: "com.tinyspeck.slackmacgap", appName: "Slack", category: .chat)
    }

    private func xcodeApp() -> ActiveAppContext {
        ActiveAppContext(bundleID: "com.apple.dt.Xcode", appName: "Xcode", category: .ide)
    }

    private func mailApp() -> ActiveAppContext {
        ActiveAppContext(bundleID: "com.apple.mail", appName: "Mail", category: .email)
    }

    private func notesApp() -> ActiveAppContext {
        ActiveAppContext(bundleID: "com.apple.Notes", appName: "Notes", category: .notes)
    }

    private func chromeApp(url: String? = nil, title: String? = nil) -> ActiveAppContext {
        ActiveAppContext(
            bundleID: "com.google.Chrome",
            appName: "Chrome",
            category: url.flatMap { AppCategory.resolve(bundleID: "com.google.Chrome", browserURL: $0) } ?? .browser,
            browserTabURL: url,
            browserTabTitle: title
        )
    }

    // MARK: - Basic Profile Resolution

    @Test("chat app resolves to casual profile")
    func chatAppResolvesCasual() {
        let engine = makeEngine()
        engine.updateActiveApp(slackApp())
        let ctx = engine.resolve()
        #expect(ctx.resolvedProfile?.id == "builtin-casual")
        #expect(ctx.resolvedProfile?.tone == .casual)
    }

    @Test("IDE app resolves to technical profile")
    func ideAppResolvesTechnical() {
        let engine = makeEngine()
        engine.updateActiveApp(xcodeApp())
        let ctx = engine.resolve()
        #expect(ctx.resolvedProfile?.id == "builtin-technical")
        #expect(ctx.resolvedProfile?.tone == .technical)
    }

    @Test("email app resolves to professional profile")
    func emailAppResolvesProfessional() {
        let engine = makeEngine()
        engine.updateActiveApp(mailApp())
        let ctx = engine.resolve()
        #expect(ctx.resolvedProfile?.id == "builtin-professional")
        #expect(ctx.resolvedProfile?.tone == .professional)
    }

    @Test("notes app resolves to notes profile with bullets format")
    func notesAppResolvesBullets() {
        let engine = makeEngine()
        engine.updateActiveApp(notesApp())
        let ctx = engine.resolve()
        #expect(ctx.resolvedProfile?.id == "builtin-notes")
        #expect(ctx.resolvedProfile?.formatStyle == .bullets)
    }

    @Test("unknown app resolves to nil profile")
    func unknownAppNilProfile() {
        let engine = makeEngine()
        engine.updateActiveApp(ActiveAppContext(
            bundleID: "com.unknown.app", appName: "Unknown", category: .other
        ))
        let ctx = engine.resolve()
        #expect(ctx.resolvedProfile == nil)
    }

    @Test("no active app resolves to nil profile")
    func noActiveApp() {
        let engine = makeEngine()
        let ctx = engine.resolve()
        #expect(ctx.resolvedProfile == nil)
        #expect(ctx.activeApp == nil)
    }

    // MARK: - Rule Priority

    @Test("higher priority rule wins over lower priority")
    func higherPriorityWins() {
        let engine = ContextEngine()
        engine.setProfiles(ContextProfile.defaults)
        engine.setRules([
            ContextRule(
                id: "low",
                name: "All chat",
                condition: .appCategory(.chat),
                profileID: "builtin-casual",
                priority: 0
            ),
            ContextRule(
                id: "high",
                name: "Slack override",
                condition: .appBundleID("com.tinyspeck.slackmacgap"),
                profileID: "builtin-professional",
                priority: 10
            ),
        ])
        engine.updateActiveApp(slackApp())
        let ctx = engine.resolve()
        #expect(ctx.resolvedProfile?.id == "builtin-professional")
    }

    @Test("disabled rules are skipped")
    func disabledRulesSkipped() {
        let engine = ContextEngine()
        engine.setProfiles(ContextProfile.defaults)
        engine.setRules([
            ContextRule(
                id: "disabled",
                name: "Chat disabled",
                condition: .appCategory(.chat),
                profileID: "builtin-casual",
                priority: 10,
                enabled: false
            ),
            ContextRule(
                id: "fallback",
                name: "Chat fallback",
                condition: .appCategory(.chat),
                profileID: "builtin-professional",
                priority: 0
            ),
        ])
        engine.updateActiveApp(slackApp())
        let ctx = engine.resolve()
        #expect(ctx.resolvedProfile?.id == "builtin-professional")
    }

    // MARK: - Rule Conditions

    @Test("appBundleID condition matches exact bundle ID")
    func bundleIDCondition() {
        let condition = RuleCondition.appBundleID("com.tinyspeck.slackmacgap")
        #expect(condition.matches(activeApp: slackApp(), calendarEvent: nil))
        #expect(!condition.matches(activeApp: xcodeApp(), calendarEvent: nil))
    }

    @Test("appCategory condition matches category")
    func categoryCondition() {
        let condition = RuleCondition.appCategory(.chat)
        #expect(condition.matches(activeApp: slackApp(), calendarEvent: nil))
        #expect(!condition.matches(activeApp: xcodeApp(), calendarEvent: nil))
    }

    @Test("meetingTitleContains condition matches substring case-insensitively")
    func meetingTitleCondition() {
        let event = RichCalendarContext(
            id: "e1", title: "Sprint Planning", attendees: [], attendeeCount: 0,
            notes: nil, isRecurring: false, organizer: nil, location: nil
        )
        let condition = RuleCondition.meetingTitleContains("sprint")
        #expect(condition.matches(activeApp: nil, calendarEvent: event))
        #expect(!RuleCondition.meetingTitleContains("standup").matches(activeApp: nil, calendarEvent: event))
    }

    @Test("browserURLContains condition matches URL substring")
    func browserURLCondition() {
        let app = chromeApp(url: "https://meet.google.com/abc-def")
        let condition = RuleCondition.browserURLContains("meet.google.com")
        #expect(condition.matches(activeApp: app, calendarEvent: nil))
        #expect(!RuleCondition.browserURLContains("zoom.us").matches(activeApp: app, calendarEvent: nil))
    }

    @Test("compound ALL condition requires all sub-conditions")
    func compoundAllCondition() {
        let event = RichCalendarContext(
            id: "e1", title: "Standup", attendees: [], attendeeCount: 0,
            notes: nil, isRecurring: true, organizer: nil, location: nil
        )
        let condition = RuleCondition.compound([
            .appCategory(.chat),
            .meetingTitleContains("standup"),
        ], logic: .all)
        #expect(condition.matches(activeApp: slackApp(), calendarEvent: event))
        #expect(!condition.matches(activeApp: xcodeApp(), calendarEvent: event))
    }

    @Test("compound ANY condition requires at least one sub-condition")
    func compoundAnyCondition() {
        let condition = RuleCondition.compound([
            .appCategory(.chat),
            .appCategory(.email),
        ], logic: .any)
        #expect(condition.matches(activeApp: slackApp(), calendarEvent: nil))
        #expect(condition.matches(activeApp: mailApp(), calendarEvent: nil))
        #expect(!condition.matches(activeApp: xcodeApp(), calendarEvent: nil))
    }

    // MARK: - Calendar Context

    @Test("calendar event is included in resolved context")
    func calendarEventInContext() {
        let engine = makeEngine()
        let event = RichCalendarContext(
            id: "e1", title: "Team Standup", attendees: ["Alice", "Bob"],
            attendeeCount: 2, notes: "Daily sync", isRecurring: true,
            organizer: "Alice", location: "https://zoom.us/j/123"
        )
        engine.updateCalendarEvent(event)
        let ctx = engine.resolve()
        #expect(ctx.calendarEvent?.title == "Team Standup")
        #expect(ctx.calendarEvent?.attendeeCount == 2)
        #expect(ctx.calendarEvent?.isRecurring == true)
    }

    @Test("RichCalendarContext converts to CalendarEventContext")
    func richToBasicConversion() {
        let rich = RichCalendarContext(
            id: "e1", title: "Standup", attendees: [], attendeeCount: 0,
            notes: nil, isRecurring: false, organizer: nil, location: nil
        )
        let basic = rich.asCalendarEventContext
        #expect(basic.id == "e1")
        #expect(basic.title == "Standup")
    }

    // MARK: - Content Hints

    @Test("content hints are included in resolved context")
    func contentHintsInContext() {
        let engine = makeEngine()
        engine.updateContentHints([
            ContentHint(category: .standup, confidence: 0.9),
            ContentHint(category: .technical, confidence: 0.3),
        ])
        let ctx = engine.resolve()
        #expect(ctx.contentHints.count == 2)
        #expect(ctx.contentHints.first?.category == .standup)
    }

    // MARK: - AppCategory Resolution

    @Test("known bundle IDs resolve to correct categories")
    func bundleIDCategoryResolution() {
        #expect(AppCategory.resolve(bundleID: "com.tinyspeck.slackmacgap") == .chat)
        #expect(AppCategory.resolve(bundleID: "com.apple.dt.Xcode") == .ide)
        #expect(AppCategory.resolve(bundleID: "com.apple.mail") == .email)
        #expect(AppCategory.resolve(bundleID: "com.apple.Notes") == .notes)
        #expect(AppCategory.resolve(bundleID: "us.zoom.xos") == .meeting)
        #expect(AppCategory.resolve(bundleID: "com.apple.Terminal") == .terminal)
        #expect(AppCategory.resolve(bundleID: "com.unknown.app") == .other)
    }

    @Test("browser URL overrides generic browser category")
    func browserURLOverride() {
        #expect(AppCategory.resolve(bundleID: "com.google.Chrome", browserURL: "https://meet.google.com/abc") == .meeting)
        #expect(AppCategory.resolve(bundleID: "com.google.Chrome", browserURL: "https://slack.com/workspace") == .chat)
        #expect(AppCategory.resolve(bundleID: "com.google.Chrome", browserURL: "https://example.com") == .browser)
    }

    @Test("browser URL does not affect non-browser apps")
    func browserURLIgnoredForNonBrowser() {
        #expect(AppCategory.resolve(bundleID: "com.tinyspeck.slackmacgap", browserURL: "https://meet.google.com") == .chat)
    }

    // MARK: - Snapshot & Reset

    @Test("snapshot returns current context")
    func snapshotCaptures() {
        let engine = makeEngine()
        let now = Date()
        engine.updateActiveApp(slackApp())
        let snap = engine.snapshot(now: now)
        #expect(snap.activeApp?.bundleID == "com.tinyspeck.slackmacgap")
        #expect(snap.timestamp == now)
    }

    @Test("reset clears all signal state")
    func resetClears() {
        let engine = makeEngine()
        engine.updateActiveApp(slackApp())
        engine.updateCalendarEvent(RichCalendarContext(
            id: "e1", title: "Test", attendees: [], attendeeCount: 0,
            notes: nil, isRecurring: false, organizer: nil, location: nil
        ))
        engine.updateContentHints([ContentHint(category: .standup, confidence: 0.9)])
        engine.reset()
        let ctx = engine.resolve()
        #expect(ctx.activeApp == nil)
        #expect(ctx.calendarEvent == nil)
        #expect(ctx.contentHints.isEmpty)
        #expect(ctx.resolvedProfile == nil)
    }

    // MARK: - Empty / Edge Cases

    @Test("empty rules produce nil profile")
    func emptyRules() {
        let engine = ContextEngine()
        engine.setRules([])
        engine.setProfiles(ContextProfile.defaults)
        engine.updateActiveApp(slackApp())
        #expect(engine.resolveProfile() == nil)
    }

    @Test("rule pointing to nonexistent profile resolves to nil")
    func missingProfile() {
        let engine = ContextEngine()
        engine.setRules([
            ContextRule(id: "r1", name: "Test", condition: .appCategory(.chat), profileID: "nonexistent"),
        ])
        engine.setProfiles([])
        engine.updateActiveApp(slackApp())
        #expect(engine.resolveProfile() == nil)
    }

    // MARK: - Codable Round-Trip

    @Test("AppContext survives JSON round-trip")
    func contextCodable() throws {
        let ctx = AppContext(
            timestamp: Date(timeIntervalSince1970: 1000),
            activeApp: ActiveAppContext(
                bundleID: "com.test.app", appName: "Test", category: .chat,
                browserTabURL: nil, browserTabTitle: nil
            ),
            calendarEvent: RichCalendarContext(
                id: "e1", title: "Meeting", attendees: ["Alice"],
                attendeeCount: 1, notes: "Notes", isRecurring: true,
                organizer: "Alice", location: "Room 1"
            ),
            contentHints: [ContentHint(category: .standup, confidence: 0.8)],
            resolvedProfile: ContextProfile.defaults[0]
        )
        let data = try JSONEncoder().encode(ctx)
        let decoded = try JSONDecoder().decode(AppContext.self, from: data)
        #expect(decoded == ctx)
    }

    @Test("ContextRule survives JSON round-trip")
    func ruleCodable() throws {
        let rule = ContextRule(
            id: "r1", name: "Test",
            condition: .compound([.appCategory(.chat), .meetingTitleContains("standup")], logic: .all),
            profileID: "p1", priority: 5
        )
        let data = try JSONEncoder().encode(rule)
        let decoded = try JSONDecoder().decode(ContextRule.self, from: data)
        #expect(decoded == rule)
    }
}
