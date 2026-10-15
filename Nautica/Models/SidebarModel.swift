import AppKit
import Foundation

/// State and persistence for the sidebar: favorites, home-directory tree, and recents.
@MainActor
@Observable
final class SidebarModel {
    var favorites: [SidebarItem] = []
    var cloudStorage: [SidebarItem] = []
    var locations: [SidebarItem] = []
    var sharedServers: [SidebarItem] = []
    var treeRoot: SidebarItem?
    var recents: [SidebarItem] = []

    /// IDs of tree nodes currently enumerating their children (drives the spinner).
    private(set) var loadingIDs: Set<UUID> = []

    private let fileSystem = FileSystemService.shared

    private static let favoritesKey = "Nautica.Sidebar.Favorites"
    private static let recentsKey = "Nautica.Sidebar.Recent"
    private static let maxRecents = 20
    /// Tree nodes expand automatically on first load down to this depth (root = 1).
    /// Keep at 1: deeper auto-expansion enumerates the whole subtree at launch
    /// and stalls the UI; children load lazily when the user expands a node.
    private static let initialExpansionDepth = 1

    init() {
        favorites = Self.loadFavorites()
        cloudStorage = CloudStorageService.detectCloudStorageItems()
        locations = Self.loadLocations()
        sharedServers = Self.loadSharedServers()
        recents = Self.loadRecents()
        let home = FileManager.default.homeURL
        treeRoot = SidebarItem(url: home, name: "Home", children: [])

        NotificationCenter.default.addObserver(
            forName: NSWorkspace.didMountNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshLocations()
            }
        }
        NotificationCenter.default.addObserver(
            forName: NSWorkspace.didUnmountNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshLocations()
            }
        }
    }

    /// Re-scans active cloud storage directories (OneDrive, Google Drive, Dropbox, iCloud Drive).
    func refreshCloudStorage() {
        cloudStorage = CloudStorageService.detectCloudStorageItems()
    }

    /// Adds a user-specified custom cloud folder to the sidebar.
    func addCustomCloudFolder(url: URL) {
        CloudStorageService.addCustomCloudFolder(url)
        refreshCloudStorage()
    }

    /// Hides a cloud storage provider from the sidebar.
    func hideCloudStorageItem(item: SidebarItem) {
        CloudStorageService.hideCloudFolder(path: item.url.standardizedFileURL.path)
        CloudStorageService.hideCloudFolder(path: item.name)
        refreshCloudStorage()
    }

    /// Re-scans mounted volumes, locations, and shared network servers.
    func refreshLocations() {
        locations = Self.loadLocations()
        sharedServers = Self.loadSharedServers()
    }

    /// Ejects/unmounts the given volume.
    func ejectVolume(item: SidebarItem) throws {
        try NSWorkspace.shared.unmountAndEjectDevice(at: item.url)
        refreshLocations()
    }

    // MARK: - Favorites

    func addFavorite(url: URL) {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue,
              !favorites.contains(where: { $0.url == url })
        else { return }
        favorites.append(Self.makeItem(for: url))
        Self.saveFavorites(favorites)
    }

    func insertFavorite(url: URL, at index: Int) {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else { return }

        if let existingIndex = favorites.firstIndex(where: { $0.url == url }) {
            if existingIndex == index || existingIndex == index - 1 { return }
            let item = favorites.remove(at: existingIndex)
            let clampedIndex = max(0, min(favorites.count, index > existingIndex ? index - 1 : index))
            favorites.insert(item, at: clampedIndex)
        } else {
            let clampedIndex = max(0, min(favorites.count, index))
            favorites.insert(Self.makeItem(for: url), at: clampedIndex)
        }
        Self.saveFavorites(favorites)
    }

    func removeFavorites(at offsets: IndexSet) {
        favorites.remove(atOffsets: offsets)
        Self.saveFavorites(favorites)
    }

    func moveFavorites(from source: IndexSet, to destination: Int) {
        favorites.move(fromOffsets: source, toOffset: destination)
        Self.saveFavorites(favorites)
    }

    // MARK: - Recents

    /// Records a navigated directory, most-recent first, capped at 20.
    func recordVisit(_ url: URL) {
        recents.removeAll { $0.url == url }
        recents.insert(Self.makeItem(for: url), at: 0)
        if recents.count > Self.maxRecents {
            recents.removeLast(recents.count - Self.maxRecents)
        }
        UserDefaults.standard.set(recents.map(\.url.path), forKey: Self.recentsKey)
    }

    /// Clears the recent directory history.
    func clearRecents() {
        recents.removeAll()
        UserDefaults.standard.removeObject(forKey: Self.recentsKey)
    }

    // MARK: - Tree

    func expand(_ item: SidebarItem, depth: Int = 1) {
        guard updateNode(id: item.id, mutate: { $0.isExpanded = true }) else { return }
        if item.children?.isEmpty ?? true {
            Task { await loadChildren(of: item.id, url: item.url, depth: depth) }
        }
    }

    func collapse(_ item: SidebarItem) {
        updateNode(id: item.id, mutate: { $0.isExpanded = false })
    }

    func isLoading(_ item: SidebarItem) -> Bool {
        loadingIDs.contains(item.id)
    }

    /// Enumerates a node's subdirectories. Nodes above the initial-expansion
    /// depth are expanded and loaded in turn, so the tree opens 3 levels deep.
    private func loadChildren(of id: UUID, url: URL, depth: Int) async {
        loadingIDs.insert(id)
        defer { loadingIDs.remove(id) }

        let contents = (try? await fileSystem.contentsOfDirectory(at: url, includingHidden: false)) ?? []
        var children = contents
            .filter(\.isDirectory)
            .map { SidebarItem(url: $0.url, name: $0.name, children: []) }

        let autoExpand = depth < Self.initialExpansionDepth
        if autoExpand {
            for index in children.indices { children[index].isExpanded = true }
        }
        updateNode(id: id, mutate: { $0.children = children })

        if autoExpand {
            for child in children {
                await loadChildren(of: child.id, url: child.url, depth: depth + 1)
            }
        }
    }

    @discardableResult
    private func updateNode(id: UUID, mutate: (inout SidebarItem) -> Void) -> Bool {
        guard var root = treeRoot, updateNode(id: id, in: &root, mutate: mutate) else {
            return false
        }
        treeRoot = root
        return true
    }

    private func updateNode(id: UUID, in item: inout SidebarItem, mutate: (inout SidebarItem) -> Void) -> Bool {
        if item.id == id {
            mutate(&item)
            return true
        }
        guard var children = item.children else { return false }
        for index in children.indices where updateNode(id: id, in: &children[index], mutate: mutate) {
            item.children = children
            return true
        }
        return false
    }

    // MARK: - Persistence

    /// Writes the favorites chosen during onboarding (Prompt 15), replacing
    /// any seeded defaults. Safe because onboarding runs before the first
    /// `SidebarModel` exists.
    static func saveInitialFavorites(_ urls: [URL]) {
        saveFavorites(urls.map(makeItem(for:)))
    }

    private static func makeItem(for url: URL) -> SidebarItem {
        let home = FileManager.default.homeURL
        let cloudRoot = home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
        let name: String
        if url.standardizedFileURL == home.standardizedFileURL { name = "Home" }
        else if url.standardizedFileURL == cloudRoot.standardizedFileURL { name = "iCloud Drive" }
        else { name = FileManager.default.displayName(atPath: url.path) }
        return SidebarItem(url: url, name: name)
    }

    private static func defaultFavorites() -> [SidebarItem] {
        let fileManager = FileManager.default
        var urls: [URL] = []
        let appURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        if fileManager.fileExists(atPath: appURL.path) {
            urls.append(appURL)
        }
        urls.append(fileManager.desktopURL)
        if let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
            urls.append(docs)
        }
        urls.append(fileManager.downloadsURL)
        if let music = fileManager.urls(for: .musicDirectory, in: .userDomainMask).first,
           fileManager.fileExists(atPath: music.path) {
            urls.append(music)
        }
        if let pics = fileManager.urls(for: .picturesDirectory, in: .userDomainMask).first {
            urls.append(pics)
        }
        let dev = fileManager.homeURL.appending(path: "Development", directoryHint: .isDirectory)
        let projects = fileManager.homeURL.appending(path: "Projects", directoryHint: .isDirectory)
        if fileManager.fileExists(atPath: dev.path) {
            urls.append(dev)
        } else if fileManager.fileExists(atPath: projects.path) {
            urls.append(projects)
        }
        if let movies = fileManager.urls(for: .moviesDirectory, in: .userDomainMask).first,
           fileManager.fileExists(atPath: movies.path) {
            urls.append(movies)
        }
        return urls.map(makeItem(for:))
    }

    private static func loadLocations() -> [SidebarItem] {
        var items: [SidebarItem] = []
        let fileManager = FileManager.default
        let keys: [URLResourceKey] = [
            .volumeLocalizedNameKey,
            .volumeIsRemovableKey,
            .volumeIsEjectableKey,
            .volumeIsInternalKey,
            .volumeIsRootFileSystemKey
        ]
        let options: FileManager.VolumeEnumerationOptions = [.skipHiddenVolumes]
        let urls = fileManager.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: options) ?? []

        for url in urls {
            let values = try? url.resourceValues(forKeys: Set(keys))
            let name = values?.volumeLocalizedName ?? url.lastPathComponent
            let isInternal = values?.volumeIsInternal ?? true
            let isEjectable = (values?.volumeIsEjectable ?? false) || (values?.volumeIsRemovable ?? false)
            let isRoot = (values?.volumeIsRootFileSystem ?? false) || (url.path == "/")
            let displayName = isRoot ? "Macintosh HD" : name

            if isInternal || isRoot || !url.path.hasPrefix("/Volumes") {
                items.append(SidebarItem(
                    url: url,
                    name: displayName,
                    isEjectable: isEjectable
                ))
            }
        }

        if !items.contains(where: { $0.url.path == "/" }) {
            items.insert(SidebarItem(url: URL(fileURLWithPath: "/"), name: "Macintosh HD"), at: 0)
        }

        return items
    }

    static func loadSharedServers() -> [SidebarItem] {
        var items: [SidebarItem] = []
        let fileManager = FileManager.default
        let keys: [URLResourceKey] = [
            .volumeLocalizedNameKey,
            .volumeIsRemovableKey,
            .volumeIsEjectableKey,
            .volumeIsInternalKey,
            .volumeIsRootFileSystemKey
        ]
        let options: FileManager.VolumeEnumerationOptions = [.skipHiddenVolumes]
        let urls = fileManager.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: options) ?? []

        for url in urls {
            let values = try? url.resourceValues(forKeys: Set(keys))
            let isInternal = values?.volumeIsInternal ?? true
            let isRoot = (values?.volumeIsRootFileSystem ?? false) || (url.path == "/")
            let name = values?.volumeLocalizedName ?? url.lastPathComponent
            let isEjectable = (values?.volumeIsEjectable ?? false) || (values?.volumeIsRemovable ?? false)

            if !isInternal && !isRoot && url.path.hasPrefix("/Volumes") {
                items.append(SidebarItem(
                    url: url,
                    name: name,
                    customSystemImage: "server.rack",
                    isEjectable: isEjectable
                ))
            }
        }

        // Always include Network entry
        let networkURL = URL(fileURLWithPath: "/Volumes")
        if !items.contains(where: { $0.url == networkURL }) {
            items.insert(SidebarItem(url: networkURL, name: "Network", customSystemImage: "network"), at: 0)
        }

        return items
    }

    private static func loadFavorites() -> [SidebarItem] {
        let defaults = UserDefaults.standard
        guard let bookmarks = defaults.array(forKey: favoritesKey) as? [Data] else {
            // First launch: seed the defaults.
            let items = defaultFavorites()
            saveFavorites(items)
            return items
        }
        return bookmarks.compactMap { data in
            var isStale = false
            guard let url = try? URL(
                resolvingBookmarkData: data,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) else { return nil }
            return makeItem(for: url)
        }
    }

    private static func saveFavorites(_ items: [SidebarItem]) {
        let bookmarks = items.compactMap { item in
            try? item.url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        }
        UserDefaults.standard.set(bookmarks, forKey: favoritesKey)
    }

    private static func loadRecents() -> [SidebarItem] {
        let paths = UserDefaults.standard.stringArray(forKey: recentsKey) ?? []
        return paths.map { makeItem(for: URL(fileURLWithPath: $0, isDirectory: true)) }
    }
}
