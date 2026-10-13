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
@MainActor
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
        var compress: (() -> Void)? = nil
        var extract: (() -> Void)? = nil
        var mountDiskImage: (() -> Void)? = nil
        var compressWithPassword: (() -> Void)? = nil
        var createSymlink: (() -> Void)? = nil
        var copyPath: (() -> Void)? = nil
        var openInTerminal: (() -> Void)? = nil
        var putBack: (() -> Void)? = nil
        var makeAlias: (() -> Void)? = nil
        var showOriginal: (() -> Void)? = nil
        var rotateLeft: (() -> Void)? = nil
        var rotateRight: (() -> Void)? = nil
        var createPDF: (() -> Void)? = nil
        var runShortcut: ((String) -> Void)? = nil
        var toggleTag: ((TagColor) -> Void)? = nil
        var clearTags: (() -> Void)? = nil
        var copyChecksum: (() -> Void)? = nil
        var findDuplicates: (() -> Void)? = nil
        var gitStage: (() -> Void)? = nil
        var gitUnstage: (() -> Void)? = nil
        var gitDiscard: (() -> Void)? = nil
        var gitDiff: (() -> Void)? = nil
        var gitCommit: (() -> Void)? = nil
        var unlockVault: (() -> Void)? = nil
        var lockVault: (() -> Void)? = nil
        var createVault: (() -> Void)? = nil
        var checkVaultHealth: (() -> Void)? = nil
        var addToDropShelf: (() -> Void)? = nil
        var secureDelete: (() -> Void)? = nil
        var createEncryptedArchive: (() -> Void)? = nil
        var extractEncryptedArchive: (() -> Void)? = nil
    }

    static func makeMenu(for items: [FileItem], actions: Actions) -> NSMenu {
        let menu = NSMenu()
        if let putBack = actions.putBack, items.contains(where: { TrashOriginStore.shared.canPutBack(url: $0.url) }) {
            menu.addItem(NSMenuItem(title: "Put Back", enabled: !items.isEmpty) { _ in putBack() })
            menu.addItem(.separator())
        }
        menu.addItem(NSMenuItem(title: "Open") { _ in actions.open() })
        menu.addItem(openWithItem(for: items, actions: actions))

        if items.count == 1, ArchiveService.shared.isArchive(url: items[0].url), let extract = actions.extract {
            menu.addItem(NSMenuItem(title: "Extract “\(items[0].name)”") { _ in extract() })
        }
        if items.count == 1, ArchiveService.shared.isEncryptedArchive(url: items[0].url), let extractEnc = actions.extractEncryptedArchive {
            let encItem = NSMenuItem(title: "Extract Encrypted Archive “\(items[0].name)”…") { _ in extractEnc() }
            if let icon = NSImage(systemSymbolName: "lock.open", accessibilityDescription: "Extract encrypted archive") {
                encItem.image = icon
            }
            menu.addItem(encItem)
        }
        if items.count == 1, ArchiveService.shared.isDiskImage(url: items[0].url), let mountDiskImage = actions.mountDiskImage {
            let mountItem = NSMenuItem(title: "Open Disk Image") { _ in mountDiskImage() }
            if let icon = NSImage(systemSymbolName: "opticaldiscdrive", accessibilityDescription: "Mount disk image") {
                mountItem.image = icon
            }
            menu.addItem(mountItem)
        }

        if items.count == 1 {
            let item = items[0]
            if VaultService.shared.isVault(at: item.url) {
                let status = VaultService.shared.isVaultMounted(at: item.url)
                if status.isMounted {
                    let lockItem = NSMenuItem(title: "Lock File Vault (Eject)") { _ in
                        actions.lockVault?()
                    }
                    if let icon = NSImage(systemSymbolName: "lock.slash", accessibilityDescription: "Lock file vault") {
                        lockItem.image = icon
                    }
                    menu.addItem(lockItem)
                } else {
                    let unlockItem = NSMenuItem(title: "Unlock File Vault…") { _ in
                        actions.unlockVault?()
                    }
                    if let icon = NSImage(systemSymbolName: "lock.open", accessibilityDescription: "Unlock file vault") {
                        unlockItem.image = icon
                    }
                    menu.addItem(unlockItem)
                }

                let healthItem = NSMenuItem(title: "Check Vault Health…") { _ in
                    actions.checkVaultHealth?()
                }
                if let icon = NSImage(systemSymbolName: "cross.case", accessibilityDescription: "Check vault health") {
                    healthItem.image = icon
                }
                menu.addItem(healthItem)
            }
        } else if items.isEmpty {
            let newVaultItem = NSMenuItem(title: "New Encrypted File Vault…") { _ in
                actions.createVault?()
            }
            if let icon = NSImage(systemSymbolName: "lock.shield", accessibilityDescription: "Create encrypted vault") {
                newVaultItem.image = icon
            }
            menu.addItem(newVaultItem)
        }

        if let openInTerminal = actions.openInTerminal {
            let emulator = TerminalService.shared.defaultTerminal()
            let terminalItem = NSMenuItem(title: "Open in \(emulator.rawValue)", enabled: !items.isEmpty) { _ in
                openInTerminal()
            }
            if let appURL = emulator.appURL {
                let icon = NSWorkspace.shared.icon(forFile: appURL.path)
                icon.size = NSSize(width: 16, height: 16)
                terminalItem.image = icon
            }
            menu.addItem(terminalItem)
        }
        if items.count == 1, items[0].isAliasOrSymlink, let showOriginal = actions.showOriginal {
            menu.addItem(NSMenuItem(title: "Show Original") { _ in showOriginal() })
        }
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Get Info") { _ in actions.getInfo() })
        menu.addItem(NSMenuItem(title: "Quick Look") { _ in actions.quickLook() })
        let renameTitle = items.count > 1 ? "Batch Rename (\(items.count) Items)…" : "Rename…"
        menu.addItem(NSMenuItem(title: renameTitle, enabled: !items.isEmpty) { _ in actions.rename() })

        // Tags submenu
        let tagsItem = NSMenuItem(title: "Tags…", action: nil, keyEquivalent: "")
        let tagsMenu = NSMenu()
        for color in TagColor.allCases {
            let item = NSMenuItem(title: color.name, enabled: !items.isEmpty) { _ in
                actions.toggleTag?(color)
            }
            if let dot = TagDotsHelper.image(for: [color], diameter: 10) {
                item.image = dot
            }
            item.keyEquivalent = "\(color.shortcutNumber)"
            item.keyEquivalentModifierMask = .control
            tagsMenu.addItem(item)
        }
        tagsMenu.addItem(.separator())
        let clearTagsItem = NSMenuItem(title: "Clear All Tags", enabled: !items.isEmpty) { _ in
            actions.clearTags?()
        }
        clearTagsItem.keyEquivalent = "0"
        clearTagsItem.keyEquivalentModifierMask = .control
        tagsMenu.addItem(clearTagsItem)
        tagsItem.submenu = tagsMenu
        menu.addItem(tagsItem)

        if let addToDropShelf = actions.addToDropShelf, !items.isEmpty {
            let shelfTitle = items.count == 1 ? "Add “\(items[0].name)” to Drop Shelf" : "Add \(items.count) Items to Drop Shelf"
            let shelfItem = NSMenuItem(title: shelfTitle) { _ in addToDropShelf() }
            if let icon = NSImage(systemSymbolName: "tray.and.arrow.down", accessibilityDescription: "Add to drop shelf") {
                shelfItem.image = icon
            }
            menu.addItem(shelfItem)
        }

        menu.addItem(.separator())

        let compressTitle = items.count == 1 ? "Compress “\(items[0].name)”" : "Compress \(items.count) Items"
        if let compress = actions.compress {
            menu.addItem(NSMenuItem(title: compressTitle, enabled: !items.isEmpty) { _ in compress() })
        }
        if let compressWithPassword = actions.compressWithPassword {
            menu.addItem(NSMenuItem(title: "Compress with Password…", enabled: !items.isEmpty) { _ in compressWithPassword() })
        }
        if let createEncryptedArchive = actions.createEncryptedArchive, !items.isEmpty {
            let title = items.count == 1 ? "Create Encrypted Archive from “\(items[0].name)”…" : "Create Encrypted Archive (\(items.count) Items)…"
            let encItem = NSMenuItem(title: title) { _ in createEncryptedArchive() }
            if let icon = NSImage(systemSymbolName: "lock.shield", accessibilityDescription: "Create encrypted archive") {
                encItem.image = icon
            }
            menu.addItem(encItem)
        }
        if let makeAlias = actions.makeAlias {
            let aliasTitle = items.count == 1 ? "Make Alias" : "Make \(items.count) Aliases"
            menu.addItem(NSMenuItem(title: aliasTitle, enabled: !items.isEmpty) { _ in makeAlias() })
        }
        if let createSymlink = actions.createSymlink {
            menu.addItem(NSMenuItem(title: "Make Symlink", enabled: items.count == 1) { _ in createSymlink() })
        }
        if let copyPath = actions.copyPath {
            menu.addItem(NSMenuItem(title: "Copy as Pathname", enabled: !items.isEmpty) { _ in copyPath() })
        }
        if let copyChecksum = actions.copyChecksum, items.count == 1, !items[0].isDirectory {
            menu.addItem(NSMenuItem(title: "Copy SHA-256 Checksum") { _ in copyChecksum() })
        }
        if let findDuplicates = actions.findDuplicates {
            if items.count == 1, items[0].isDirectory {
                menu.addItem(NSMenuItem(title: "Find Duplicates in “\(items[0].name)”…") { _ in findDuplicates() })
            } else if items.isEmpty {
                menu.addItem(NSMenuItem(title: "Find Duplicates in Folder…") { _ in findDuplicates() })
            }
        }
        if let qaItem = quickActionsItem(for: items, actions: actions) {
            menu.addItem(qaItem)
        }
        menu.addItem(.separator())

        menu.addItem(NSMenuItem(title: "Copy") { _ in actions.copy() })
        menu.addItem(NSMenuItem(title: "Move to Trash") { _ in actions.trash() })

        if let secureDelete = actions.secureDelete, !items.isEmpty {
            let secTitle = items.count == 1 ? "Secure Delete “\(items[0].name)”…" : "Secure Delete \(items.count) Items…"
            let secItem = NSMenuItem(title: secTitle) { _ in secureDelete() }
            if let icon = NSImage(systemSymbolName: "trash.slash", accessibilityDescription: "Securely delete files") {
                secItem.image = icon
            }
            secItem.keyEquivalent = "\u{08}"
            secItem.keyEquivalentModifierMask = [.option, .command]
            menu.addItem(secItem)
        }

        // Cloud file actions (Download Now / Free Up Space)
        let cloudItems = items.filter(\.isCloudItem)
        if !cloudItems.isEmpty {
            let hasOnlineOnly = cloudItems.contains { $0.canDownload }
            let hasDownloaded = cloudItems.contains { $0.canEvict }

            let providerName = cloudItems.first?.cloudProvider.map {
                CloudStorageService.formatDisplayName(for: $0.rawValue, provider: $0)
            } ?? "Cloud"

            if hasOnlineOnly {
                menu.addItem(NSMenuItem(title: "Download from \(providerName)") { _ in
                    Task {
                        for item in cloudItems where item.canDownload {
                            try? await CloudStorageService.downloadItem(at: item.url)
                        }
                    }
                })
            }
            if hasDownloaded {
                menu.addItem(NSMenuItem(title: "Remove Download (Free Up Space)") { _ in
                    Task {
                        for item in cloudItems where item.canEvict {
                            try? await CloudStorageService.evictItem(at: item.url)
                        }
                    }
                })
            }
        }

        if let gitMenuItem = gitItem(for: items, actions: actions) {
            menu.addItem(gitMenuItem)
        }

        menu.addItem(.separator())
        menu.addItem(shareItem(for: items, actions: actions))
        return menu
    }

    private static func gitItem(for items: [FileItem], actions: Actions) -> NSMenuItem? {
        guard actions.gitStage != nil || actions.gitUnstage != nil || actions.gitDiscard != nil || actions.gitDiff != nil || actions.gitCommit != nil else {
            return nil
        }
        let submenu = NSMenu(title: "Git")
        var hasAny = false

        if let gitDiff = actions.gitDiff, !items.isEmpty {
            let item = NSMenuItem(title: items.count == 1 ? "Diff “\(items[0].name)”…" : "Diff Selected…") { _ in
                gitDiff()
            }
            if let img = NSImage(systemSymbolName: "doc.text.magnifyingglass", accessibilityDescription: nil) {
                item.image = img
            }
            submenu.addItem(item)
            hasAny = true
        }

        if let gitStage = actions.gitStage, !items.isEmpty {
            let item = NSMenuItem(title: items.count == 1 ? "Stage “\(items[0].name)”" : "Stage \(items.count) Items") { _ in
                gitStage()
            }
            if let img = NSImage(systemSymbolName: "plus.circle", accessibilityDescription: nil) {
                item.image = img
            }
            submenu.addItem(item)
            hasAny = true
        }

        if let gitUnstage = actions.gitUnstage, !items.isEmpty {
            let item = NSMenuItem(title: items.count == 1 ? "Unstage “\(items[0].name)”" : "Unstage \(items.count) Items") { _ in
                gitUnstage()
            }
            if let img = NSImage(systemSymbolName: "minus.circle", accessibilityDescription: nil) {
                item.image = img
            }
            submenu.addItem(item)
            hasAny = true
        }

        if let gitDiscard = actions.gitDiscard, !items.isEmpty {
            let item = NSMenuItem(title: items.count == 1 ? "Discard Changes in “\(items[0].name)”…" : "Discard Changes in \(items.count) Items…") { _ in
                gitDiscard()
            }
            if let img = NSImage(systemSymbolName: "arrow.uturn.backward", accessibilityDescription: nil) {
                item.image = img
            }
            submenu.addItem(item)
            hasAny = true
        }

        if let gitCommit = actions.gitCommit {
            if hasAny {
                submenu.addItem(.separator())
            }
            let item = NSMenuItem(title: "Commit Changes…") { _ in
                gitCommit()
            }
            if let img = NSImage(systemSymbolName: "checkmark.circle", accessibilityDescription: nil) {
                item.image = img
            }
            submenu.addItem(item)
            hasAny = true
        }

        guard hasAny else { return nil }
        let gitMenuItem = NSMenuItem(title: "Git", action: nil, keyEquivalent: "")
        if let gitIcon = NSImage(systemSymbolName: "arrow.triangle.branch", accessibilityDescription: "Git") {
            gitMenuItem.image = gitIcon
        }
        gitMenuItem.submenu = submenu
        return gitMenuItem
    }

    private static func shareItem(for items: [FileItem], actions: Actions) -> NSMenuItem {
        let urls = items.map(\.url)
        guard !urls.isEmpty else {
            let item = NSMenuItem(title: "Share…", action: nil, keyEquivalent: "")
            item.isEnabled = false
            return item
        }
        let picker = NSSharingServicePicker(items: urls)
        let shareItem = picker.standardShareMenuItem
        if let icon = NSImage(systemSymbolName: "square.and.arrow.up", accessibilityDescription: "Share") {
            shareItem.image = icon
        }
        return shareItem
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

    private static func quickActionsItem(for items: [FileItem], actions: Actions) -> NSMenuItem? {
        let submenu = NSMenu(title: "Quick Actions")
        var hasAny = false

        let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "heic", "tiff", "tif", "bmp", "gif", "webp"]
        let hasImages = items.contains { imageExtensions.contains($0.url.pathExtension.lowercased()) }
        let hasPDFs = items.contains { $0.url.pathExtension.lowercased() == "pdf" }

        if hasImages {
            if let rotateLeft = actions.rotateLeft {
                let item = NSMenuItem(title: "Rotate Left") { _ in rotateLeft() }
                if let icon = NSImage(systemSymbolName: "rotate.left", accessibilityDescription: nil) {
                    item.image = icon
                }
                submenu.addItem(item)
                hasAny = true
            }
            if let rotateRight = actions.rotateRight {
                let item = NSMenuItem(title: "Rotate Right") { _ in rotateRight() }
                if let icon = NSImage(systemSymbolName: "rotate.right", accessibilityDescription: nil) {
                    item.image = icon
                }
                submenu.addItem(item)
                hasAny = true
            }
        }

        if (hasImages || hasPDFs) && !items.isEmpty {
            if let createPDF = actions.createPDF {
                let item = NSMenuItem(title: "Create PDF") { _ in createPDF() }
                if let icon = NSImage(systemSymbolName: "doc.richtext", accessibilityDescription: nil) {
                    item.image = icon
                }
                submenu.addItem(item)
                hasAny = true
            }
        }

        let shortcuts = QuickActionService.shared.shortcuts()
        if !shortcuts.isEmpty && !items.isEmpty {
            if hasAny {
                submenu.addItem(.separator())
            }
            for shortcut in shortcuts.prefix(10) {
                let item = NSMenuItem(title: shortcut) { _ in
                    actions.runShortcut?(shortcut)
                }
                if let icon = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: nil) {
                    item.image = icon
                }
                submenu.addItem(item)
                hasAny = true
            }
        }

        if let first = items.first {
            if hasAny {
                submenu.addItem(.separator())
            }
            let aiItem = NSMenuItem(title: first.isDirectory ? "Summarize Folder with AI…" : "Explain File with AI…") { _ in
                Task { @MainActor in
                    let result: String
                    do {
                        if first.isDirectory {
                            result = try await AIService.shared.summarizeDirectory(at: first.url)
                        } else {
                            result = try await AIService.shared.explainFile(at: first.url)
                        }
                    } catch {
                        result = "AI analysis failed: \(error.localizedDescription)"
                    }
                    let alert = NSAlert()
                    alert.messageText = "Nautica Intelligence"
                    alert.informativeText = result
                    alert.alertStyle = .informational
                    alert.addButton(withTitle: "OK")
                    alert.runModal()
                }
            }
            if let icon = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "AI") {
                aiItem.image = icon
            }
            submenu.addItem(aiItem)
            hasAny = true
        }

        if !hasAny {
            return nil
        }

        let mainItem = NSMenuItem(title: "Quick Actions", action: nil, keyEquivalent: "")
        if let icon = NSImage(systemSymbolName: "wand.and.stars", accessibilityDescription: nil) {
            mainItem.image = icon
        }
        mainItem.submenu = submenu
        return mainItem
    }

    /// Shows floating Get Info panel for a single item.
    static func showInfo(for item: FileItem) {
        GetInfoService.shared.showInfo(for: item.url)
    }
}
