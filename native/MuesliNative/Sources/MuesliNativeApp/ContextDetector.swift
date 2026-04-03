import AppKit
import CoreGraphics

/// Detected writing context for OllamaFormatter (future).
enum WritingContext: String {
    case email
    case imessage
    case aiPrompt = "ai-prompt"
    case notes
    case code
    case general
}

/// Detects the user's writing context from the frontmost application.
///
/// Pure detection logic in `detect(bundleID:windowTitle:)` — no system dependencies, fully testable.
/// System integration via `detectCurrentContext()` static convenience.
struct ContextDetector {

    // MARK: - Bundle ID → Context (native apps)

    static let nativeAppContexts: [String: WritingContext] = [
        "com.apple.mail": .email,
        "com.apple.MobileSMS": .imessage,
        "com.apple.Notes": .notes,
        "com.openai.chat": .aiPrompt,
        "com.microsoft.VSCode": .code,
        "com.apple.dt.Xcode": .code,
        "com.apple.Terminal": .code,
        "com.googlecode.iterm2": .code,
        "dev.warp.Warp-Stable": .code,
    ]

    /// Browser bundle IDs where window title inspection is useful.
    static let browserBundleIDs: Set<String> = [
        "com.google.Chrome",
        "com.brave.Browser",
        "company.thebrowser.Browser",
        "org.mozilla.firefox",
        "com.apple.Safari",
    ]

    /// Ordered list of (substring, context) for browser window title matching.
    static let browserTitlePatterns: [(substring: String, context: WritingContext)] = [
        ("mail.google.com", .email),
        ("Gmail", .email),
        ("Inbox", .email),
        ("Outlook", .email),
        ("ChatGPT", .aiPrompt),
        ("Claude", .aiPrompt),
        ("Gemini", .aiPrompt),
        ("Perplexity", .aiPrompt),
    ]

    // MARK: - Core detection (pure, testable)

    /// Detect context from a bundle ID and optional window title.
    func detect(bundleID: String, windowTitle: String?) -> WritingContext {
        // 1. Check native app map first
        if let context = Self.nativeAppContexts[bundleID] {
            return context
        }

        // 2. If it's a browser, check window title
        if Self.browserBundleIDs.contains(bundleID), let title = windowTitle {
            for pattern in Self.browserTitlePatterns {
                if title.localizedCaseInsensitiveContains(pattern.substring) {
                    return pattern.context
                }
            }
        }

        // 3. Fallback
        return .general
    }

    // MARK: - System integration

    /// Read the window title of the frontmost window for a given PID.
    static func windowTitle(for pid: pid_t) -> String? {
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return nil
        }

        for window in windowList {
            guard
                let ownerPID = window[kCGWindowOwnerPID as String] as? pid_t,
                ownerPID == pid,
                let layer = window[kCGWindowLayer as String] as? Int,
                layer == 0
            else { continue }

            if let title = window[kCGWindowName as String] as? String, !title.isEmpty {
                return title
            }
        }
        return nil
    }

    /// Detect context from the current frontmost application.
    static func detectCurrentContext() -> WritingContext {
        guard let frontApp = NSWorkspace.shared.frontmostApplication,
              let bundleID = frontApp.bundleIdentifier else {
            return .general
        }

        let detector = ContextDetector()

        // Only fetch window title for browsers
        var title: String? = nil
        if browserBundleIDs.contains(bundleID) {
            title = windowTitle(for: frontApp.processIdentifier)
        }

        return detector.detect(bundleID: bundleID, windowTitle: title)
    }
}
