import AppKit
import Foundation

/// A row in the sidebar: favorite, tree node, or recent folder.
struct SidebarItem: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let name: String
    var children: [SidebarItem]?
    var isExpanded: Bool = false

    /// Lazily-loaded folder icon (system icon for the item).
    /// Computed so it stays out of the synthesized `Hashable`/`Equatable`.
    var icon: NSImage? {
        NSWorkspace.shared.icon(forFile: url.path)
    }
}
