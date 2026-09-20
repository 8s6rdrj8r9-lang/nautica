import Foundation

enum Constants {
    /// ~/Library/Application Support/Nautica
    static let appSupportURL = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)
        .first!
        .appendingPathComponent("Nautica")

    // MARK: - UserDefaults keys

    /// Selected terminal emulator raw value (Prompt 13).
    static let defaultTerminalKey = "defaultTerminal"
    /// Custom shell path; empty means the login shell (Prompt 14).
    static let terminalShellKey = "terminalShell"
    /// "home" | "desktop" | "lastVisited" (Prompt 14).
    static let defaultNewWindowFolderKey = "defaultNewWindowFolder"
    static let showExtensionsKey = "showExtensions"
    static let confirmTrashKey = "confirmTrash"
    static let showHiddenFilesKey = "showHiddenFiles"
    static let splitLayoutKey = "splitLayout"
    static let defaultViewModeKey = "defaultViewMode"
    static let defaultIconSizeKey = "defaultIconSize"
    static let sidebarWidthKey = "sidebarWidth"
    static let sidebarAutoWidthKey = "sidebarAutoWidth"
    static let sidebarFontSizeKey = "sidebarFontSize"
    static let sidebarSpacingKey = "sidebarSpacing"
    static let listFontSizeKey = "listFontSize"
    static let listIconSizeKey = "listIconSize"
    static let listSpacingKey = "listSpacing"
    static let iconFontSizeKey = "iconFontSize"
    static let iconSpacingKey = "iconSpacing"
    static let useSystemAccentKey = "useSystemAccent"
    static let checkForUpdatesKey = "checkForUpdates"
    // Vault Security & Auto-Lock (Phase 16)
    static let vaultAutoLockOnSleepKey = "vaultAutoLockOnSleep"
    static let vaultAutoLockOnScreenLockKey = "vaultAutoLockOnScreenLock"
    static let vaultInactivityTimeoutKey = "vaultInactivityTimeout"

    /// Initial folder for a new window, per the General preference.
    static func defaultWindowURL() -> URL {
        switch UserDefaults.standard.string(forKey: defaultNewWindowFolderKey) {
        case "desktop":
            return FileManager.default.homeURL.appendingPathComponent("Desktop")
        default:
            // "home", and "lastVisited" falls back to Home for brand-new
            // windows; launch-time tab restore covers the last session.
            return FileManager.default.homeURL
        }
    }
}
