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
