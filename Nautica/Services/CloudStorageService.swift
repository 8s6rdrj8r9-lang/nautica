import Foundation

/// Supported cloud storage provider classifications.
enum CloudStorageProvider: String, Sendable, CaseIterable {
    case iCloud
    case oneDrive
    case googleDrive
    case dropbox
    case box
    case generic
}

/// Service that automatically detects local sync directories for cloud storage providers
/// (OneDrive, Google Drive, Dropbox, iCloud Drive, etc.) via macOS FileProvider and standard mount points.
struct CloudStorageService: Sendable {

    private static let customFoldersKey = "Nautica.Sidebar.CustomCloudFolders"
    private static let hiddenFoldersKey = "Nautica.Sidebar.HiddenCloudFolders"

    /// Custom cloud storage folder paths added by the user.
    static func customCloudFolders() -> [URL] {
        let paths = UserDefaults.standard.stringArray(forKey: customFoldersKey) ?? []
        return paths.compactMap { URL(fileURLWithPath: $0) }
    }

    /// Adds and persists a custom cloud storage folder.
    static func addCustomCloudFolder(_ url: URL) {
        var paths = UserDefaults.standard.stringArray(forKey: customFoldersKey) ?? []
        let path = url.standardizedFileURL.path
        if !paths.contains(path) {
            paths.append(path)
            UserDefaults.standard.set(paths, forKey: customFoldersKey)
        }
    }

    /// Removes a custom cloud storage folder.
    static func removeCustomCloudFolder(_ url: URL) {
        var paths = UserDefaults.standard.stringArray(forKey: customFoldersKey) ?? []
        let path = url.standardizedFileURL.path
        paths.removeAll { $0 == path }
        UserDefaults.standard.set(paths, forKey: customFoldersKey)
    }

    /// Set of hidden cloud storage provider standardized paths or display names.
    static func hiddenCloudFolders() -> Set<String> {
        let paths = UserDefaults.standard.stringArray(forKey: hiddenFoldersKey) ?? []
        return Set(paths)
    }

    /// Hides a cloud storage provider from the sidebar.
    static func hideCloudFolder(path: String) {
        var paths = Set(UserDefaults.standard.stringArray(forKey: hiddenFoldersKey) ?? [])
        paths.insert(path)
        UserDefaults.standard.set(Array(paths), forKey: hiddenFoldersKey)
    }

    /// Unhides a cloud storage provider in the sidebar.
    static func unhideCloudFolder(path: String) {
        var paths = Set(UserDefaults.standard.stringArray(forKey: hiddenFoldersKey) ?? [])
        paths.remove(path)
        UserDefaults.standard.set(Array(paths), forKey: hiddenFoldersKey)
    }

    /// Detects all active cloud storage provider folders on the system.
    /// Deduplicates by standardized URL path and respects user-hidden providers.
    static func detectCloudStorageItems(fileManager: FileManager = .default) -> [SidebarItem] {
        var items: [SidebarItem] = []
        var seenPaths: Set<String> = []
        let hidden = hiddenCloudFolders()

        func addItem(_ item: SidebarItem) {
            let standardizedPath = item.url.standardizedFileURL.path
            guard !seenPaths.contains(standardizedPath) else { return }
            guard !hidden.contains(standardizedPath) && !hidden.contains(item.name) else { return }
            var isDir: ObjCBool = false
            if fileManager.fileExists(atPath: standardizedPath, isDirectory: &isDir), isDir.boolValue {
                seenPaths.insert(standardizedPath)
                items.append(item)
            }
        }

        // 1. Apple iCloud Drive
        let icloudURL = fileManager.homeURL.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
        addItem(SidebarItem(
            url: icloudURL,
            name: "iCloud Drive",
            customSystemImage: systemImage(for: .iCloud)
        ))

        // 2. Modern macOS FileProvider directory (~/Library/CloudStorage)
        let cloudStorageDir = fileManager.homeURL.appendingPathComponent("Library/CloudStorage")
        if let contents = try? fileManager.contentsOfDirectory(
            at: cloudStorageDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            for folderURL in contents {
                var isDir: ObjCBool = false
                if fileManager.fileExists(atPath: folderURL.path, isDirectory: &isDir), isDir.boolValue {
                    let item = parseCloudFolder(name: folderURL.lastPathComponent, url: folderURL)
                    addItem(item)
                }
            }
        }

        // 3. Legacy and fallback mount points (if not already found in CloudStorage)
        let legacyCandidates: [(URL, CloudStorageProvider, String)] = [
            (fileManager.homeURL.appendingPathComponent("Dropbox"), .dropbox, "Dropbox"),
            (fileManager.homeURL.appendingPathComponent("OneDrive"), .oneDrive, "OneDrive"),
            (URL(fileURLWithPath: "/Volumes/GoogleDrive", isDirectory: true), .googleDrive, "Google Drive"),
            (fileManager.homeURL.appendingPathComponent("Google Drive"), .googleDrive, "Google Drive")
        ]

        for (url, provider, fallbackName) in legacyCandidates {
            addItem(SidebarItem(
                url: url,
                name: fallbackName,
                customSystemImage: systemImage(for: provider)
            ))
        }

        // 4. Custom pinned cloud folders
        for customURL in customCloudFolders() {
            let providerType = provider(for: customURL) ?? .generic
            addItem(SidebarItem(
                url: customURL,
                name: customURL.lastPathComponent,
                customSystemImage: systemImage(for: providerType)
            ))
        }

        return items
    }

    /// Determines which cloud provider owns the given URL.
    static func provider(for url: URL) -> CloudStorageProvider? {
        let path = url.standardizedFileURL.path

        if path.contains("com~apple~CloudDocs") || path.contains("Library/Mobile Documents") {
            return .iCloud
        }

        if let range = path.range(of: "/Library/CloudStorage/") {
            let sub = path[range.upperBound...]
            let component = sub.split(separator: "/").first.map(String.init) ?? ""
            return provider(for: component, url: url)
        }

        let lower = path.lowercased()
        if lower.contains("/dropbox") {
            return .dropbox
        }
        if lower.contains("/onedrive") {
            return .oneDrive
        }
        if lower.contains("/googledrive") || lower.contains("/google drive") {
            return .googleDrive
        }
        if lower.contains("/box") {
            return .box
        }

        for customURL in customCloudFolders() {
            if path.hasPrefix(customURL.standardizedFileURL.path) {
                return provider(for: customURL.lastPathComponent, url: customURL)
            }
        }

        return nil
    }

    /// Evaluates the synchronization status of a file using URLResourceValues and low-level APFS dataless flags.
    static func cloudStatus(for url: URL, resourceValues: URLResourceValues? = nil, provider: CloudStorageProvider? = nil) -> CloudSyncStatus {
        let values = resourceValues ?? (try? url.resourceValues(forKeys: [
            .isUbiquitousItemKey,
            .ubiquitousItemDownloadingStatusKey,
            .ubiquitousItemIsDownloadingKey,
            .ubiquitousItemHasUnresolvedConflictsKey
        ]))

        let isUbiquitous = values?.isUbiquitousItem ?? false
        let cloudProv = provider ?? self.provider(for: url)

        guard isUbiquitous || cloudProv != nil else {
            return .notCloud
        }

        if values?.ubiquitousItemHasUnresolvedConflicts == true {
            return .conflict
        }

        if values?.ubiquitousItemIsDownloading == true {
            return .downloading
        }

        if values?.ubiquitousItemDownloadingStatus == .notDownloaded {
            return .onlineOnly
        }

        // Low-level APFS dataless check (0x40000000 = SF_DATALESS / UF_DATALESS)
        var statBuf = stat()
        if stat(url.path, &statBuf) == 0 {
            let datalessFlag: UInt32 = 0x40000000
            if (statBuf.st_flags & datalessFlag) != 0 {
                return .onlineOnly
            }
        }

        if values?.ubiquitousItemDownloadingStatus == .current || values?.ubiquitousItemDownloadingStatus == .downloaded {
            return .downloaded
        }

        return .downloaded
    }

    /// Triggers download of the specified cloud item (and optional children).
    static func downloadItem(at url: URL, recursive: Bool = true) async throws {
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue && recursive {
            if let enumerator = FileManager.default.enumerator(
                at: url,
                includingPropertiesForKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey],
                options: [.skipsHiddenFiles]
            ) {
                for case let fileURL as URL in enumerator {
                    try? FileManager.default.startDownloadingUbiquitousItem(at: fileURL)
                }
            }
        }
        try FileManager.default.startDownloadingUbiquitousItem(at: url)
    }

    /// Evicts the locally downloaded data of the specified cloud item to free up disk space.
    static func evictItem(at url: URL, recursive: Bool = true) async throws {
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue && recursive {
            if let enumerator = FileManager.default.enumerator(
                at: url,
                includingPropertiesForKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey],
                options: [.skipsHiddenFiles]
            ) {
                for case let fileURL as URL in enumerator {
                    try? FileManager.default.evictUbiquitousItem(at: fileURL)
                }
            }
        }
        try FileManager.default.evictUbiquitousItem(at: url)
    }

    /// Parses a folder name and URL into a configured `SidebarItem`.
    static func parseCloudFolder(name: String, url: URL) -> SidebarItem {
        let providerType = provider(for: name, url: url)
        let displayName = formatDisplayName(for: name, provider: providerType)
        let icon = systemImage(for: providerType)
        return SidebarItem(url: url, name: displayName, customSystemImage: icon)
    }

    /// Identifies the cloud provider type from a folder name or URL.
    static func provider(for folderName: String, url: URL? = nil) -> CloudStorageProvider {
        if let url, url.path.contains("com~apple~CloudDocs") {
            return .iCloud
        }
        let lower = folderName.lowercased()
        if lower.hasPrefix("onedrive") {
            return .oneDrive
        } else if lower.hasPrefix("googledrive") || lower.hasPrefix("google drive") || lower.contains("googledrive") {
            return .googleDrive
        } else if lower.hasPrefix("dropbox") {
            return .dropbox
        } else if lower.hasPrefix("box") {
            return .box
        } else if lower.contains("icloud") {
            return .iCloud
        }
        return .generic
    }

    /// Converts raw directory names (e.g. `OneDrive-Personal`, `GoogleDrive-user@mail.com`)
    /// into clean, readable display titles.
    static func formatDisplayName(for folderName: String, provider: CloudStorageProvider) -> String {
        switch provider {
        case .iCloud:
            return "iCloud Drive"

        case .oneDrive:
            if folderName.lowercased() == "onedrive" {
                return "OneDrive"
            }
            if folderName.contains("-") {
                let parts = folderName.split(separator: "-", maxSplits: 1).map(String.init)
                if parts.count == 2 && !parts[1].isEmpty {
                    return "OneDrive (\(parts[1]))"
                }
            }
            return folderName

        case .googleDrive:
            if folderName.lowercased() == "googledrive" || folderName.lowercased() == "google drive" {
                return "Google Drive"
            }
            if folderName.contains("-") {
                let parts = folderName.split(separator: "-", maxSplits: 1).map(String.init)
                if parts.count == 2 && !parts[1].isEmpty {
                    return "Google Drive (\(parts[1]))"
                }
            }
            return "Google Drive"

        case .dropbox:
            if folderName.lowercased() == "dropbox" {
                return "Dropbox"
            }
            if folderName.contains("-") {
                let parts = folderName.split(separator: "-", maxSplits: 1).map(String.init)
                if parts.count == 2 && !parts[1].isEmpty {
                    return "Dropbox (\(parts[1]))"
                }
            }
            return folderName

        case .box:
            if folderName.lowercased() == "box-box" || folderName.lowercased() == "box" {
                return "Box"
            }
            return folderName

        case .generic:
            return folderName
        }
    }

    /// The SF Symbol matching the provider.
    static func systemImage(for provider: CloudStorageProvider) -> String {
        switch provider {
        case .iCloud:
            return "icloud"
        case .oneDrive:
            return "cloud.fill"
        case .googleDrive:
            return "externaldrive.badge.icloud"
        case .dropbox:
            return "shippingbox.fill"
        case .box:
            return "shippingbox"
        case .generic:
            return "cloud"
        }
    }
}
