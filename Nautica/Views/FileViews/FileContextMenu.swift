import AppKit

/// Retained target for closure-based menu items — `NSMenuItem` does not
/// retain its target, so the proxy is attached via `representedObject`.
private final class MenuActionProxy: NSObject {
    let handler: (NSMenuItem) -> Void
    init(_ handler: @escaping (NSMenuItem) -> Void) { self.handler = handler }
    @objc func perform(_ sender: NSMenuItem) { handler(sender) }
}

extension NSMenuItem {
    /// A menu item backed by a closure.
    convenience init(title: String, enabled: Bool = true, handler: @escaping (NSMenuItem) -> Void) {
        let proxy = MenuActionProxy(handler)
        self.init(title: title, action: #selector(MenuActionProxy.perform(_:)), keyEquivalent: "")
        target = proxy
        representedObject = proxy
        isEnabled = enabled
    }
}

/// The standard right-click menu shared by the icon and list views:
/// Open, Open With, Quick Look, Get Info, Rename, Copy, Move to Trash, Share.
enum FileContextMenu {
    struct Actions {
        var open: () -> Void
        /// Open all selected items with the given application URL.
        var openWith: (URL) -> Void
        var quickLook: () -> Void
        var getInfo: () -> Void
        var rename: () -> Void
        var copy: () -> Void
        var trash: () -> Void
        var share: () -> Void
    }

    static func makeMenu(for items: [FileItem], actions: Actions) -> NSMenu {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Open") { _ in actions.open() })
        menu.addItem(openWithItem(for: items, actions: actions))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quick Look") { _ in actions.quickLook() })
        menu.addItem(NSMenuItem(title: "Get Info") { _ in actions.getInfo() })
        menu.addItem(NSMenuItem(title: "Rename…", enabled: items.count == 1) { _ in actions.rename() })
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Copy") { _ in actions.copy() })
        menu.addItem(NSMenuItem(title: "Move to Trash") { _ in actions.trash() })
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Share…") { _ in actions.share() })
        return menu
    }

    private static func openWithItem(for items: [FileItem], actions: Actions) -> NSMenuItem {
        let menuItem = NSMenuItem(title: "Open With", action: nil, keyEquivalent: "")
        guard let first = items.first else {
            menuItem.isEnabled = false
            return menuItem
        }
        let submenu = NSMenu()
        let applications = NSWorkspace.shared.urlsForApplications(toOpen: first.url)
        if applications.isEmpty {
            submenu.addItem(NSMenuItem(title: "No Applications Found", enabled: false) { _ in })
        } else {
            for appURL in applications {
                let item = NSMenuItem(
                    title: FileManager.default.displayName(atPath: appURL.path)
                ) { _ in
                    actions.openWith(appURL)
                }
                let icon = NSWorkspace.shared.icon(forFile: appURL.path)
                icon.size = NSSize(width: 16, height: 16)
                item.image = icon
                submenu.addItem(item)
            }
        }
        menuItem.submenu = submenu
        return menuItem
    }

    /// Modal info panel for a single item.
    static func showInfo(for item: FileItem) {
        let alert = NSAlert()
        alert.messageText = item.name
        let icon = NSWorkspace.shared.icon(forFile: item.url.path)
        icon.size = NSSize(width: 64, height: 64)
        alert.icon = icon

        var lines = ["Path: \(item.url.path)"]
        if !item.kind.isEmpty { lines.append("Kind: \(item.kind)") }
        if let size = item.size {
            lines.append("Size: \(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))")
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        if let created = item.creationDate {
            lines.append("Created: \(formatter.string(from: created))")
        }
        if let modified = item.modificationDate {
            lines.append("Modified: \(formatter.string(from: modified))")
        }
        alert.informativeText = lines.joined(separator: "\n")
        alert.runModal()
    }
}
