import AppKit
import Foundation

/// A row in the sidebar: favorite, tree node, or recent folder.
struct SidebarItem: Identifiable, Hashable {
    let id: UUID
    let url: URL
    let name: String
    var children: [SidebarItem]?
    var isExpanded: Bool
    var customSystemImage: String?
    var isEjectable: Bool

    init(
        id: UUID = UUID(),
        url: URL,
        name: String,
        children: [SidebarItem]? = nil,
        isExpanded: Bool = false,
        customSystemImage: String? = nil,
        isEjectable: Bool = false
    ) {
        self.id = id
        self.url = url
        self.name = name
        self.children = children
        self.isExpanded = isExpanded
        self.customSystemImage = customSystemImage
        self.isEjectable = isEjectable
    }

    init(
        id: UUID = UUID(),
        url: URL,
        name: String,
        children: [SidebarItem]? = nil,
        isExpanded: Bool = false,
        customSystemImage: String? = nil
    ) {
        self.init(
            id: id,
            url: url,
            name: name,
            children: children,
            isExpanded: isExpanded,
            customSystemImage: customSystemImage,
            isEjectable: false
        )
    }

    /// Session-wide icon cache: `NSWorkspace.icon(forFile:)` is a synchronous
    /// main-thread call, so without caching every SwiftUI re-render would
    /// re-fetch an icon per row.
    private static let iconCache = NSCache<NSURL, NSImage>()

    /// Lazily-loaded folder icon (system icon for the item), cached per URL.
    /// Computed so it stays out of the synthesized `Hashable`/`Equatable`.
    var icon: NSImage? {
        if let cached = Self.iconCache.object(forKey: url as NSURL) {
            return cached
        }
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 32, height: 32)
        Self.iconCache.setObject(icon, forKey: url as NSURL)
        return icon
    }

    /// The emblem SF symbol corresponding to the folder (e.g. `arrow.down.circle` for Downloads,
    /// `display` for Desktop, `doc` for Documents, `cloud.fill` for OneDrive, `folder` for generic).
    var systemImage: String {
        if let custom = customSystemImage, !custom.isEmpty {
            return custom
        }
        let nameLower = name.lowercased()
        let pathLower = url.path.lowercased()
        let homePath = FileManager.default.homeDirectoryForCurrentUser.path.lowercased()

        if pathLower == "/applications" || nameLower == "applications" {
            return "app.badge"
        }
        if pathLower == "\(homePath)/desktop" || nameLower == "desktop" {
            return "display"
        }
        if pathLower == "\(homePath)/documents" || nameLower == "documents" {
            return "doc"
        }
        if pathLower == "\(homePath)/downloads" || nameLower == "downloads" {
            return "arrow.down.circle"
        }
        if pathLower == "\(homePath)/music" || nameLower == "music" {
            return "music.note"
        }
        if pathLower == "\(homePath)/pictures" || nameLower == "pictures" || nameLower == "photos" {
            return "photo"
        }
        if pathLower == "\(homePath)/movies" || nameLower == "movies" || nameLower == "videos" {
            return "film"
        }
        if pathLower.contains("development") || pathLower.contains("developer") || pathLower.contains("projects")
            || nameLower == "development" || nameLower == "developer" || nameLower == "projects" || nameLower == "code" || nameLower == "dev" {
            return "hammer"
        }
        if pathLower == homePath || nameLower == "home" {
            return "house"
        }
        if pathLower.contains("com~apple~clouddocs") || nameLower == "icloud drive" || nameLower == "icloud" {
            return "icloud"
        }
        if nameLower.contains("onedrive") {
            return "cloud.fill"
        }
        if nameLower.contains("googledrive") || nameLower.contains("google drive") {
            return "externaldrive.badge.icloud"
        }
        if nameLower.contains("dropbox") {
            return "shippingbox.fill"
        }
        if nameLower.contains("box") && (nameLower.contains("box-box") || nameLower == "box") {
            return "shippingbox"
        }
        if pathLower == "/" || nameLower == "macintosh hd" {
            return "internaldrive"
        }
        if isEjectable {
            return "externaldrive"
        }
        if pathLower == "/volumes" || nameLower == "network" {
            return "network"
        }
        if nameLower == "public" || nameLower == "shared" {
            return "person.2"
        }
        if nameLower == "library" {
            return "books.vertical"
        }
        if nameLower == "trash" {
            return "trash"
        }
        if nameLower == "recent" || nameLower == "recents" {
            return "clock"
        }
        return "folder"
    }
}
