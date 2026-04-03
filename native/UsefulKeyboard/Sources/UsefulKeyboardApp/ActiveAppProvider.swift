import AppKit
import ApplicationServices
import Foundation

/// Detects the frontmost application and extracts browser tab URL/title when applicable.
/// Uses NSWorkspace for app identity and Accessibility API for browser URL extraction.
@MainActor
final class ActiveAppProvider {

    /// Cached snapshot of the current frontmost app.
    private(set) var currentApp: ActiveAppContext?

    /// Browser bundle IDs (reuses MeetingDetector's list).
    private static let browserBundleIDs: Set<String> = [
        "com.google.Chrome",
        "com.brave.Browser",
        "company.thebrowser.Browser",
        "org.mozilla.firefox",
        "com.apple.Safari",
    ]

    // MARK: - Snapshot

    /// Capture the current frontmost app as an ActiveAppContext.
    /// Call this when dictation starts (point-in-time) or on a timer for meetings.
    func snapshot() -> ActiveAppContext? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let bundleID = app.bundleIdentifier else { return nil }

        let appName = app.localizedName ?? bundleID

        var browserURL: String?
        var browserTitle: String?
        if Self.browserBundleIDs.contains(bundleID) {
            (browserURL, browserTitle) = extractBrowserInfo(from: app)
        }

        let category = AppCategory.resolve(bundleID: bundleID, browserURL: browserURL)

        let context = ActiveAppContext(
            bundleID: bundleID,
            appName: appName,
            category: category,
            browserTabURL: browserURL,
            browserTabTitle: browserTitle
        )
        currentApp = context
        return context
    }

    /// Update from an already-known NSRunningApplication (e.g., from workspace notification).
    func update(from app: NSRunningApplication) {
        guard let bundleID = app.bundleIdentifier else { return }
        let appName = app.localizedName ?? bundleID

        var browserURL: String?
        var browserTitle: String?
        if Self.browserBundleIDs.contains(bundleID) {
            (browserURL, browserTitle) = extractBrowserInfo(from: app)
        }

        let category = AppCategory.resolve(bundleID: bundleID, browserURL: browserURL)

        currentApp = ActiveAppContext(
            bundleID: bundleID,
            appName: appName,
            category: category,
            browserTabURL: browserURL,
            browserTabTitle: browserTitle
        )
    }

    // MARK: - Browser Info Extraction

    /// Extract the current tab URL and title from a browser via Accessibility API.
    /// Returns (url, title). Both may be nil if Accessibility is unavailable.
    private func extractBrowserInfo(from app: NSRunningApplication) -> (String?, String?) {
        let axApp = AXUIElementCreateApplication(app.processIdentifier)

        // Get the focused window
        var windowValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &windowValue) == .success else {
            return (nil, nil)
        }
        let window = windowValue as! AXUIElement

        // Get window title (usually contains the tab title)
        var titleValue: CFTypeRef?
        let title: String?
        if AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleValue) == .success {
            title = titleValue as? String
        } else {
            title = nil
        }

        // Try to get URL from the address bar.
        // Most browsers expose the URL via the focused UI element or a specific toolbar element.
        let url = extractURLFromBrowser(axApp: axApp, bundleID: app.bundleIdentifier ?? "")

        return (url, title)
    }

    /// Attempt to extract the URL from a browser's address bar via Accessibility.
    /// Different browsers expose this differently.
    private func extractURLFromBrowser(axApp: AXUIElement, bundleID: String) -> String? {
        // Chrome/Brave/Arc: AXValue of the address bar text field
        // Safari: different hierarchy
        // Generic approach: find a text field with role AXTextField in the toolbar

        var windowValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &windowValue) == .success else {
            return nil
        }
        let window = windowValue as! AXUIElement

        // Try to find toolbar → text field with URL
        if let toolbar = findChild(of: window, role: "AXToolbar") {
            if let textField = findChild(of: toolbar, role: "AXTextField") {
                var value: CFTypeRef?
                if AXUIElementCopyAttributeValue(textField, kAXValueAttribute as CFString, &value) == .success {
                    return value as? String
                }
            }
            // Some browsers use AXComboBox for the address bar
            if let comboBox = findChild(of: toolbar, role: "AXComboBox") {
                var value: CFTypeRef?
                if AXUIElementCopyAttributeValue(comboBox, kAXValueAttribute as CFString, &value) == .success {
                    return value as? String
                }
            }
        }
        return nil
    }

    /// Recursively find the first child element with a matching role.
    private func findChild(of element: AXUIElement, role targetRole: String) -> AXUIElement? {
        var childrenValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenValue) == .success,
              let children = childrenValue as? [AXUIElement] else {
            return nil
        }

        for child in children {
            var roleValue: CFTypeRef?
            if AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &roleValue) == .success,
               let role = roleValue as? String, role == targetRole {
                return child
            }
        }

        // Recurse one level deep (toolbar is usually a direct child of window)
        for child in children {
            if let found = findChild(of: child, role: targetRole) {
                return found
            }
        }

        return nil
    }
}
