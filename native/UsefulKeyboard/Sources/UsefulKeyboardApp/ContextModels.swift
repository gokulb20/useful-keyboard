import Foundation
import UsefulKeyboardCore

/// The resolved context snapshot at a point in time.
struct AppContext: Equatable, Sendable, Codable {
    let timestamp: Date
    let activeApp: ActiveAppContext?
    let calendarEvent: RichCalendarContext?
    let contentHints: [ContentHint]
    let resolvedProfile: ContextProfile?

    static let empty = AppContext(
        timestamp: .distantPast,
        activeApp: nil,
        calendarEvent: nil,
        contentHints: [],
        resolvedProfile: nil
    )
}

/// Active application info.
struct ActiveAppContext: Equatable, Sendable, Codable {
    let bundleID: String
    let appName: String
    let category: AppCategory
    let browserTabURL: String?
    let browserTabTitle: String?

    init(
        bundleID: String,
        appName: String,
        category: AppCategory,
        browserTabURL: String? = nil,
        browserTabTitle: String? = nil
    ) {
        self.bundleID = bundleID
        self.appName = appName
        self.category = category
        self.browserTabURL = browserTabURL
        self.browserTabTitle = browserTabTitle
    }
}

/// App categories for rule matching.
enum AppCategory: String, Codable, Sendable {
    case chat
    case email
    case ide
    case notes
    case browser
    case meeting
    case terminal
    case document
    case other

    /// Known bundle ID to category mappings.
    static let bundleIDMap: [String: AppCategory] = [
        // Chat
        "com.tinyspeck.slackmacgap": .chat,
        "com.apple.MobileSMS": .chat,
        "net.whatsapp.WhatsApp": .chat,
        "com.hnc.Discord": .chat,
        "ru.keepcoder.Telegram": .chat,
        "com.facebook.archon.developerID": .chat,  // Messenger
        // Email
        "com.apple.mail": .email,
        "com.microsoft.Outlook": .email,
        "com.readdle.smartemail-macos": .email,  // Spark
        // IDE
        "com.apple.dt.Xcode": .ide,
        "com.microsoft.VSCode": .ide,
        "com.jetbrains.intellij": .ide,
        "com.jetbrains.CLion": .ide,
        "com.jetbrains.WebStorm": .ide,
        "com.jetbrains.pycharm": .ide,
        "com.sublimetext.4": .ide,
        "com.cursor.Cursor": .ide,
        "dev.zed.Zed": .ide,
        // Notes
        "com.apple.Notes": .notes,
        "md.obsidian": .notes,
        "notion.id": .notes,
        "com.lukilabs.lukiapp": .notes,  // Bear
        "com.craft.craft": .notes,
        // Meeting
        "us.zoom.xos": .meeting,
        "us.zoom.ZoomPhone": .meeting,
        "com.apple.FaceTime": .meeting,
        "com.microsoft.teams2": .meeting,
        "com.microsoft.teams": .meeting,
        "com.webex.meetingmanager": .meeting,
        "com.cisco.webexmeetingsapp": .meeting,
        // Terminal
        "com.apple.Terminal": .terminal,
        "com.googlecode.iterm2": .terminal,
        "dev.warp.Warp-Stable": .terminal,
        // Document
        "com.apple.iWork.Pages": .document,
        "com.microsoft.Word": .document,
        "com.google.Chrome.app.Docs": .document,
        // Browser
        "com.google.Chrome": .browser,
        "com.brave.Browser": .browser,
        "company.thebrowser.Browser": .browser,
        "org.mozilla.firefox": .browser,
        "com.apple.Safari": .browser,
    ]

    /// URL patterns for browser-based app detection.
    static let browserURLCategories: [(pattern: String, category: AppCategory)] = [
        ("meet.google.com", .meeting),
        ("teams.microsoft.com", .meeting),
        ("zoom.us", .meeting),
        ("slack.com", .chat),
        ("discord.com", .chat),
        ("mail.google.com", .email),
        ("outlook.live.com", .email),
        ("outlook.office.com", .email),
        ("notion.so", .notes),
        ("docs.google.com", .document),
        ("github.com", .ide),
        ("gitlab.com", .ide),
    ]

    /// Resolve category from bundle ID, with optional browser URL override.
    static func resolve(bundleID: String, browserURL: String? = nil) -> AppCategory {
        // For browser apps, check URL first for more specific category
        if let url = browserURL, bundleIDMap[bundleID] == .browser {
            for (pattern, category) in browserURLCategories {
                if url.contains(pattern) { return category }
            }
            return .browser
        }
        return bundleIDMap[bundleID] ?? .other
    }
}

/// Rich calendar context (extends existing CalendarEventContext).
struct RichCalendarContext: Equatable, Sendable, Codable {
    let id: String
    let title: String
    let attendees: [String]
    let attendeeCount: Int
    let notes: String?
    let isRecurring: Bool
    let organizer: String?
    let location: String?

    /// Convert to the existing CalendarEventContext for backward compatibility.
    var asCalendarEventContext: CalendarEventContext {
        CalendarEventContext(id: id, title: title)
    }
}

/// Hints derived from content/speech analysis.
struct ContentHint: Equatable, Sendable, Codable {
    let category: ContentCategory
    let confidence: Double
}

enum ContentCategory: String, Codable, Sendable {
    case standup
    case codeReview
    case planning
    case oneOnOne
    case interview
    case presentation
    case casual
    case technical
    case general
}

/// A user-facing context profile that bundles behavior settings.
struct ContextProfile: Codable, Equatable, Sendable, Identifiable {
    var id: String = UUID().uuidString
    var name: String
    var tone: TextTone = .neutral
    var formatStyle: FormatStyle = .prose
    var customWordSetIDs: [UUID] = []
    var preferredBackend: String?
    var meetingTemplateID: String?

    static let defaults: [ContextProfile] = [
        ContextProfile(id: "builtin-casual", name: "Casual", tone: .casual, formatStyle: .prose),
        ContextProfile(id: "builtin-professional", name: "Professional", tone: .professional, formatStyle: .prose),
        ContextProfile(id: "builtin-technical", name: "Technical", tone: .technical, formatStyle: .prose),
        ContextProfile(id: "builtin-notes", name: "Notes", tone: .neutral, formatStyle: .bullets),
        ContextProfile(id: "builtin-code", name: "Code", tone: .technical, formatStyle: .codeComment),
    ]
}

enum TextTone: String, Codable, Sendable {
    case casual
    case neutral
    case professional
    case technical
}

enum FormatStyle: String, Codable, Sendable {
    case prose
    case bullets
    case codeComment
    case markdown
}
