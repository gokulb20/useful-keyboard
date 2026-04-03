import Foundation

public enum AppPaths {
    public static func defaultSupportDirectoryURL(appName: String = "Useful Keyboard") -> URL {
        // Check for legacy "Muesli" support directory first to preserve existing user data
        let legacyURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent("Muesli", isDirectory: true)
        if appName == "Useful Keyboard" && FileManager.default.fileExists(atPath: legacyURL.path) {
            return legacyURL
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent(appName, isDirectory: true)
    }

    public static func defaultDatabaseURL(appName: String = "Useful Keyboard") -> URL {
        let supportDir = defaultSupportDirectoryURL(appName: appName)
        // Check for legacy database name to preserve existing user data
        let legacyDB = supportDir.appendingPathComponent("muesli.db")
        if FileManager.default.fileExists(atPath: legacyDB.path) {
            return legacyDB
        }
        return supportDir.appendingPathComponent("useful-keyboard.db")
    }
}

public enum AppNotifications {
    public static let dataDidChange = Notification.Name("com.usefulkeyboard.dataChanged")

    public static func postDataDidChange() {
        DistributedNotificationCenter.default().post(name: dataDidChange, object: nil)
    }
}
