import AppKit
import Foundation
import Network

/// Manages remote server connections (⌘K), favorite servers, recent history,
/// and Bonjour discovery for local network machines.
@MainActor
@Observable
final class ServerConnectionService {
    static let shared = ServerConnectionService()

    private static let favoritesKey = "Nautica.ServerConnection.Favorites"
    private static let recentsKey = "Nautica.ServerConnection.Recents"
    private static let maxRecents = 15

    var favoriteServers: [String] = []
    var recentServers: [String] = []
    var discoveredServers: [String] = []

    private var bonjourBrowser: NWBrowser?

    private init() {
        favoriteServers = UserDefaults.standard.stringArray(forKey: Self.favoritesKey) ?? [
            "smb://",
            "afp://",
            "nfs://"
        ]
        recentServers = UserDefaults.standard.stringArray(forKey: Self.recentsKey) ?? []
        startBonjourDiscovery()
    }

    func addFavorite(_ server: String) {
        let trimmed = server.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !favoriteServers.contains(trimmed) else { return }
        favoriteServers.append(trimmed)
        UserDefaults.standard.set(favoriteServers, forKey: Self.favoritesKey)
    }

    func removeFavorite(at index: Int) {
        guard index >= 0, index < favoriteServers.count else { return }
        favoriteServers.remove(at: index)
        UserDefaults.standard.set(favoriteServers, forKey: Self.favoritesKey)
    }

    func recordRecent(_ server: String) {
        let trimmed = server.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        recentServers.removeAll { $0 == trimmed }
        recentServers.insert(trimmed, at: 0)
        if recentServers.count > Self.maxRecents {
            recentServers.removeLast(recentServers.count - Self.maxRecents)
        }
        UserDefaults.standard.set(recentServers, forKey: Self.recentsKey)
    }

    /// Connects to a server URL (e.g. smb://..., afp://..., nfs://...).
    /// Uses NSWorkspace to trigger macOS native authentication and mounting,
    /// waiting up to timeout for the volume to appear under /Volumes.
    func connect(to address: String) async throws -> URL? {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(),
              ["smb", "afp", "nfs", "http", "https", "ftp", "vnc"].contains(scheme) else {
            throw NSError(domain: "ServerConnectionService", code: 400, userInfo: [
                NSLocalizedDescriptionKey: "Invalid server URL. Please use smb://, afp://, nfs://, http://, or vnc://."
            ])
        }

        recordRecent(trimmed)

        // Snapshot existing mounted volumes
        let preMounts = Set(FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil, options: []) ?? [])

        // Launch system connection (brings up native macOS auth/credentials dialog)
        NSWorkspace.shared.open(url)

        // Poll for up to 10 seconds for new mount
        for _ in 0..<20 {
            try? await Task.sleep(nanoseconds: 500_000_000)
            let postMounts = Set(FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil, options: []) ?? [])
            let newVolumes = postMounts.subtracting(preMounts)
            if let first = newVolumes.first {
                return first
            }
        }
        return nil
    }

    func startBonjourDiscovery() {
        let descriptor = NWBrowser.Descriptor.bonjour(type: "_smb._tcp", domain: "local.")
        let parameters = NWParameters()
        let browser = NWBrowser(for: descriptor, using: parameters)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor in
                var names = Set<String>()
                for result in results {
                    if case let .service(name, _, _, _) = result.endpoint {
                        names.insert(name)
                    }
                }
                self?.discoveredServers = names.sorted()
            }
        }
        browser.start(queue: .main)
        self.bonjourBrowser = browser
    }
}
