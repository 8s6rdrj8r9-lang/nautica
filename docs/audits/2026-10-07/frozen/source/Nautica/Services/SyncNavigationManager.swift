import Foundation

/// Coordinates directory navigation mirroring across dual panes.
/// When enabled, entering a subfolder in Pane A navigates into the corresponding
/// subfolder in Pane B (if present); navigating to parent in Pane A navigates to parent in Pane B.
@MainActor
@Observable
final class SyncNavigationManager {
    static let shared = SyncNavigationManager()

    var isSyncNavigationEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isSyncNavigationEnabled, forKey: "isSyncNavigationEnabled")
        }
    }

    private init() {
        self.isSyncNavigationEnabled = UserDefaults.standard.bool(forKey: "isSyncNavigationEnabled")
    }

    func toggle() {
        isSyncNavigationEnabled.toggle()
    }

    /// Computes the corresponding URL that the paired/inactive pane should navigate to
    /// given the source pane's transition from `fromURL` to `toURL`.
    ///
    /// - Parameters:
    ///   - toURL: The new URL the active pane just navigated to.
    ///   - fromURL: The previous URL of the active pane.
    ///   - pairedCurrentURL: The current URL of the inactive/paired pane.
    ///   - fileManager: FileManager instance (defaults to `.default`).
    /// - Returns: A new URL for the paired pane if a valid mirrored path exists; otherwise `nil`.
    func synchronizedURL(
        toURL: URL,
        fromURL: URL,
        pairedCurrentURL: URL,
        fileManager: FileManager = .default
    ) -> URL? {
        guard isSyncNavigationEnabled else { return nil }

        let standardTo = toURL.standardizedFileURL
        let standardFrom = fromURL.standardizedFileURL
        let standardPaired = pairedCurrentURL.standardizedFileURL

        if standardTo == standardFrom {
            return nil
        }

        // Case 1: Navigating UP to enclosing parent
        if standardTo == standardFrom.deletingLastPathComponent() {
            let candidateParent = standardPaired.deletingLastPathComponent()
            if candidateParent.path != standardPaired.path && fileManager.fileExists(atPath: candidateParent.path) {
                return candidateParent
            }
            return nil
        }

        // Case 2: Navigating DOWN into a subfolder
        if standardTo.deletingLastPathComponent() == standardFrom {
            let childName = standardTo.lastPathComponent
            let candidateChild = standardPaired.appendingPathComponent(childName)
            var isDir: ObjCBool = false
            if fileManager.fileExists(atPath: candidateChild.path, isDirectory: &isDir), isDir.boolValue {
                return candidateChild
            }
            return nil
        }

        // Case 3: Arbitrary relative navigation (e.g. relative path jumping)
        let fromPath = standardFrom.path.hasSuffix("/") ? standardFrom.path : standardFrom.path + "/"
        if standardTo.path.hasPrefix(fromPath) {
            let relative = String(standardTo.path.dropFirst(fromPath.count))
            let candidate = standardPaired.appendingPathComponent(relative)
            var isDir: ObjCBool = false
            if fileManager.fileExists(atPath: candidate.path, isDirectory: &isDir), isDir.boolValue {
                return candidate
            }
        }

        return nil
    }
}
