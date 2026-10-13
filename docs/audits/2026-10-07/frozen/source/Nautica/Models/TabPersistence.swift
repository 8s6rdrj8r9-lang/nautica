import AppKit

/// URLs waiting to be consumed by newly created browser windows: tabs restored
/// on launch, or the current folder handed to a Cmd+T new tab. Each new
/// `BrowserView` pops one URL on appear; an empty queue means "open Home".
/// Main-thread only.
final class TabRestoreQueue {
    static let shared = TabRestoreQueue()
    private(set) var pending: [URL] = []

    func enqueue(_ url: URL) { pending.append(url) }
    func enqueue(contentsOf urls: [URL]) { pending.append(contentsOf: urls) }

    func pop() -> URL? {
        pending.isEmpty ? nil : pending.removeFirst()
    }
}

/// Maps each live browser `NSWindow` to a provider of its current directory
/// URL so the app can save open tabs on quit and restore them on launch
/// (Prompt 8). Main-thread only.
final class WindowTabRegistry {
    static let shared = WindowTabRegistry()

    static let savedTabPathsKey = "savedTabPaths"

    private var providers: [ObjectIdentifier: () -> URL] = [:]

    func register(_ window: NSWindow, provider: @escaping () -> URL) {
        providers[ObjectIdentifier(window)] = provider
    }

    /// Current directory of every live browser window, front to back.
    func currentTabURLs() -> [URL] {
        // Drop entries whose window has since closed.
        let live = Set(NSApp.windows.map { ObjectIdentifier($0) })
        providers = providers.filter { live.contains($0.key) }
        return NSApp.windows.compactMap { providers[ObjectIdentifier($0)]?() }
    }

    func save() {
        UserDefaults.standard.set(currentTabURLs().map(\.path), forKey: Self.savedTabPathsKey)
    }

    /// Saved tab URLs from the previous session, skipping folders that no
    /// longer exist.
    func restoredURLs() -> [URL] {
        (UserDefaults.standard.stringArray(forKey: Self.savedTabPathsKey) ?? [])
            .map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }
}

/// Manages window tab grouping, moving tabs to separate windows, merging windows,
/// and tab closure actions. Main actor only.
@MainActor
final class WindowTabManager {
    static let shared = WindowTabManager()

    private init() {}

    /// Moves the active tab into its own separate window.
    func moveTabToNewWindow(for window: NSWindow? = NSApp.keyWindow) {
        window?.moveTabToNewWindow(nil)
    }

    /// Merges all open browser windows into a single tabbed window.
    func mergeAllWindows(for window: NSWindow? = NSApp.keyWindow) {
        window?.mergeAllWindows(nil)
    }

    /// Closes all tabs in the active window's tab group except for the active tab.
    func closeOtherTabs(for window: NSWindow? = NSApp.keyWindow) {
        guard let window, let tabbed = window.tabbedWindows else { return }
        for tab in tabbed where tab !== window {
            tab.performClose(nil)
        }
    }

    /// Closes all tabs in the tab group to the right of the active tab.
    func closeTabsToTheRight(for window: NSWindow? = NSApp.keyWindow) {
        guard let window, let tabbed = window.tabbedWindows,
              let currentIndex = tabbed.firstIndex(where: { $0 === window }) else { return }
        let toClose = tabbed.suffix(from: currentIndex + 1)
        for tab in toClose {
            tab.performClose(nil)
        }
    }
}
