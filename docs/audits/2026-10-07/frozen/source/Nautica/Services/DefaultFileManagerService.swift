import Foundation
import CoreServices

/// Service that interacts safely with macOS LaunchServices to query and set
/// the default application handler for folders and directories without disabling
/// or modifying System Integrity Protection (SIP).
final class DefaultFileManagerService: @unchecked Sendable {
    static let shared = DefaultFileManagerService()

    private init() {}

    let bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "com.arthur.nautica"
    let finderIdentifier: String = "com.apple.finder"

    private let contentTypes: [CFString] = [
        "public.folder" as CFString,
        "public.directory" as CFString
    ]

    /// Returns `true` if Nautica is currently registered as the primary handler for folders.
    func isDefaultFileManager() -> Bool {
        guard let current = currentFolderHandler() else { return false }
        return current == bundleIdentifier
    }

    /// Returns the bundle identifier of the current default folder handler (usually `com.apple.finder`).
    func currentFolderHandler() -> String? {
        if let handler = LSCopyDefaultRoleHandlerForContentType("public.folder" as CFString, .all)?.takeRetainedValue() as String? {
            return handler
        }
        return nil
    }

    /// Sets Nautica as the default system handler for folders and directories.
    @discardableResult
    func setAsDefault() -> Bool {
        var success = true
        for contentType in contentTypes {
            let status = LSSetDefaultRoleHandlerForContentType(contentType, .all, bundleIdentifier as CFString)
            if status != noErr {
                success = false
            }
        }
        return success
    }

    /// Restores Apple Finder as the default system handler for folders and directories.
    @discardableResult
    func restoreFinder() -> Bool {
        var success = true
        for contentType in contentTypes {
            let status = LSSetDefaultRoleHandlerForContentType(contentType, .all, finderIdentifier as CFString)
            if status != noErr {
                success = false
            }
        }
        return success
    }
}
