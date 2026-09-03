import AppKit
import Foundation

/// A row in the sidebar: favorite, tree node, or recent folder.
struct SidebarItem: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let name: String
    var children: [SidebarItem]?
    var isExpanded: Bool = false

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
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 16, height: 16)
        Self.iconCache.setObject(icon, forKey: url as NSURL)
        return icon
    }
}
