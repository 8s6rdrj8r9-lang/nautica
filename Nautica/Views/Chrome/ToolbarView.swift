import AppKit
import SwiftUI

private extension NSToolbarItem.Identifier {
    static let toggleSidebar = NSToolbarItem.Identifier("Nautica.ToggleSidebar")
    static let navigationGroup = NSToolbarItem.Identifier("Nautica.NavigationGroup")
    static let back = NSToolbarItem.Identifier("Nautica.Back")
    static let forward = NSToolbarItem.Identifier("Nautica.Forward")
    static let splitLayout = NSToolbarItem.Identifier("Nautica.SplitLayout")
    static let viewMode = NSToolbarItem.Identifier("Nautica.ViewMode")
    static let sortMenu = NSToolbarItem.Identifier("Nautica.SortMenu")
    static let share = NSToolbarItem.Identifier("Nautica.Share")
    static let tags = NSToolbarItem.Identifier("Nautica.Tags")
    static let action = NSToolbarItem.Identifier("Nautica.Action")
    static let newFolder = NSToolbarItem.Identifier("Nautica.NewFolder")
    static let quickLook = NSToolbarItem.Identifier("Nautica.QuickLook")
    static let trash = NSToolbarItem.Identifier("Nautica.Trash")
    static let getInfo = NSToolbarItem.Identifier("Nautica.GetInfo")
    static let terminal = NSToolbarItem.Identifier("Nautica.Terminal")
    static let newTab = NSToolbarItem.Identifier("Nautica.NewTab")
    static let batchRename = NSToolbarItem.Identifier("Nautica.BatchRename")
    static let search = NSToolbarItem.Identifier("Nautica.Search")
    static let pathBar = NSToolbarItem.Identifier("Nautica.PathBar")
    static let iconSize = NSToolbarItem.Identifier("Nautica.IconSize")
    static let hiddenFiles = NSToolbarItem.Identifier("Nautica.HiddenFiles")
}

/// Main-window toolbar matching macOS Finder:
/// Back/Forward navigation group, flexible space, View mode, Panes, Sort/Group, Share, Tags, Actions, New Folder, and Search.
final class BrowserToolbar: NSObject {
    // MARK: - Callbacks (wired by BrowserView)

    var onBack: (() -> Void)?
    var onForward: (() -> Void)?
    var onNavigate: ((URL) -> Void)?
    var onAddFavorite: ((URL) -> Void)?
    var onSplitLayoutChanged: ((SplitLayout) -> Void)?
    var onViewModeChanged: ((ViewMode) -> Void)?
    var onIconSizeChanged: ((CGFloat) -> Void)?
    var onToggleHiddenFiles: (() -> Void)?
    var onSortChanged: ((SortKey, Bool) -> Void)?
    var onGroupByChanged: ((GroupByCriterion) -> Void)?
    var onShare: (() -> Void)?
    var onNewFolder: (() -> Void)?
    var onGetInfo: (() -> Void)?
    var onRename: (() -> Void)?
    var onBatchRename: (() -> Void)?
    var onTrash: (() -> Void)?
    var onTogglePathBar: (() -> Void)?
    var onSearch: ((String) -> Void)?
    var onQuickLook: (() -> Void)?
    var onTerminal: (() -> Void)?
    var onNewTab: (() -> Void)?
    var onApplyTag: ((String, String) -> Void)?

    // MARK: - Mirrored state (set before calling refresh())

    var canGoBack = false
    var canGoForward = false
    var hasSelection = false
    var currentURL = FileManager.default.homeURL
    var splitLayout: SplitLayout = .single
    var viewMode: ViewMode = .list
    var iconSize: CGFloat = 64
    var showsHiddenFiles = false
    var currentSortKey: SortKey = .name
    var sortAscending: Bool = true
    var currentGroupBy: GroupByCriterion = .none

    let toolbar: NSToolbar

    private weak var navigationControl: NSSegmentedControl?
    private weak var backItem: NSToolbarItem?
    private weak var forwardItem: NSToolbarItem?
    private weak var pathBarHostingView: NSHostingView<PathBarView>?
    private weak var splitLayoutControl: NSSegmentedControl?
    private weak var viewModeControl: NSSegmentedControl?
    private weak var iconSizeSlider: NSSlider?
    private weak var hiddenFilesButton: NSButton?

    override init() {
        toolbar = NSToolbar(identifier: "NauticaMainToolbar.v7")
        super.init()
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = true
    }

    /// Re-applies the mirrored state to the toolbar items. Cheap; call freely.
    func refresh() {
        navigationControl?.setEnabled(canGoBack, forSegment: 0)
        navigationControl?.setEnabled(canGoForward, forSegment: 1)
        backItem?.isEnabled = canGoBack
        forwardItem?.isEnabled = canGoForward
        pathBarHostingView?.rootView = makePathBarView()
        switch splitLayout {
        case .single:
            splitLayoutControl?.selectedSegment = 0
        case .horizontal2, .vertical2:
            splitLayoutControl?.selectedSegment = 1
        case .quad4, .horizontal4, .vertical4:
            splitLayoutControl?.selectedSegment = 2
        }
        viewModeControl?.selectedSegment = viewMode == .icon ? 0 : (viewMode == .list ? 1 : (viewMode == .column ? 2 : 3))
        iconSizeSlider?.doubleValue = Double(iconSize)
        iconSizeSlider?.isEnabled = viewMode == .icon
        hiddenFilesButton?.state = showsHiddenFiles ? .on : .off
    }

    private func makePathBarView() -> PathBarView {
        PathBarView(currentURL: currentURL) { [weak self] url in
            self?.onNavigate?(url)
        } onAddFavorite: { [weak self] url in
            self?.onAddFavorite?(url)
        }
    }

    // MARK: - Actions

    @objc private func backAction() { onBack?() }
    @objc private func forwardAction() { onForward?() }

    @objc private func splitLayoutAction(_ sender: NSSegmentedControl) {
        let layout: SplitLayout
        switch sender.selectedSegment {
        case 0: layout = .single
        case 1: layout = .horizontal2
        case 2: layout = .quad4
        default: layout = .single
        }
        onSplitLayoutChanged?(layout)
    }

    @objc private func viewModeAction(_ sender: NSSegmentedControl) {
        let mode: ViewMode
        switch sender.selectedSegment {
        case 0: mode = .icon
        case 1: mode = .list
        case 2: mode = .column
        case 3: mode = .gallery
        default: mode = .list
        }
        onViewModeChanged?(mode)
    }

    @objc private func iconSizeAction(_ sender: NSSlider) {
        onIconSizeChanged?(CGFloat(sender.doubleValue))
    }

    @objc private func hiddenFilesAction() { onToggleHiddenFiles?() }

    @objc private func sortKeyAction(_ sender: NSMenuItem) {
        if let key = sender.representedObject as? SortKey {
            currentSortKey = key
            onSortChanged?(key, sortAscending)
        }
    }

    @objc private func toggleSortAscending(_ sender: NSMenuItem) {
        sortAscending.toggle()
        onSortChanged?(currentSortKey, sortAscending)
    }

    @objc private func groupByAction(_ sender: NSMenuItem) {
        if let criterion = sender.representedObject as? GroupByCriterion {
            currentGroupBy = criterion
            onGroupByChanged?(criterion)
        }
    }

    @objc private func shareAction() { onShare?() }
    @objc private func newFolderAction() { onNewFolder?() }
    @objc private func getInfoAction() { onGetInfo?() }
    @objc private func quickLookAction() { onQuickLook?() }
    @objc private func terminalAction() { onTerminal?() }
    @objc private func newTabAction() { onNewTab?() }
    @objc private func renameAction() { onRename?() }
    @objc private func batchRenameAction() { onBatchRename?() }
    @objc private func navigationAction(_ sender: NSSegmentedControl) {
        if sender.selectedSegment == 0 {
            backAction()
        } else if sender.selectedSegment == 1 {
            forwardAction()
        }
    }

    @objc private func trashAction() { onTrash?() }
    @objc private func togglePathBarAction() { onTogglePathBar?() }
    @objc private func searchAction(_ sender: NSSearchField) { onSearch?(sender.stringValue) }

    @objc private func tagColorAction(_ sender: NSMenuItem) {
        if let tuple = sender.representedObject as? [String], tuple.count == 2 {
            onApplyTag?(tuple[0], tuple[1])
        }
    }
}

// MARK: - NSToolbarDelegate

extension BrowserToolbar: NSToolbarDelegate {
    func toolbar(_ toolbar: NSToolbar,
                 itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        switch itemIdentifier {
        case .toggleSidebar:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Sidebar"
            item.paletteLabel = "Sidebar"
            item.toolTip = "Hide or show the sidebar"
            item.image = NSImage(systemSymbolName: "sidebar.leading", accessibilityDescription: "Toggle Sidebar")
            item.action = #selector(NSSplitViewController.toggleSidebar(_:))
            item.visibilityPriority = .high
            return item

        case .navigationGroup:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Navigate"
            item.paletteLabel = "Navigate"
            let control = NSSegmentedControl(
                images: [
                    NSImage(systemSymbolName: "chevron.backward", accessibilityDescription: "Back")!,
                    NSImage(systemSymbolName: "chevron.forward", accessibilityDescription: "Forward")!,
                ],
                trackingMode: .momentary,
                target: self,
                action: #selector(navigationAction(_:))
            )
            control.segmentStyle = .separated
            control.setEnabled(canGoBack, forSegment: 0)
            control.setEnabled(canGoForward, forSegment: 1)
            control.sizeToFit()
            item.view = control
            item.minSize = control.fittingSize
            item.maxSize = control.fittingSize
            item.visibilityPriority = .high
            navigationControl = control
            return item

        case .back:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Back"
            item.paletteLabel = "Back"
            item.image = NSImage(systemSymbolName: "chevron.backward", accessibilityDescription: "Back")
            item.target = self
            item.action = #selector(backAction)
            item.isEnabled = canGoBack
            backItem = item
            return item

        case .forward:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Forward"
            item.paletteLabel = "Forward"
            item.image = NSImage(systemSymbolName: "chevron.forward", accessibilityDescription: "Forward")
            item.target = self
            item.action = #selector(forwardAction)
            item.isEnabled = canGoForward
            forwardItem = item
            return item

        case .splitLayout:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Panes"
            item.paletteLabel = "Panes"
            let control = NSSegmentedControl(
                images: [
                    NSImage(systemSymbolName: "rectangle", accessibilityDescription: "Single Pane")!,
                    NSImage(systemSymbolName: "rectangle.split.2x1", accessibilityDescription: "2 Panes")!,
                    NSImage(systemSymbolName: "rectangle.split.2x2", accessibilityDescription: "4 Panes")!,
                ],
                trackingMode: .selectOne,
                target: self,
                action: #selector(splitLayoutAction(_:))
            )
            control.segmentStyle = .separated
            switch splitLayout {
            case .single: control.selectedSegment = 0
            case .horizontal2, .vertical2: control.selectedSegment = 1
            case .quad4, .horizontal4, .vertical4: control.selectedSegment = 2
            }
            control.sizeToFit()
            item.view = control
            item.minSize = control.fittingSize
            item.maxSize = control.fittingSize
            item.visibilityPriority = .high
            splitLayoutControl = control
            return item

        case .viewMode:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "View"
            item.paletteLabel = "View"
            let control = NSSegmentedControl(
                images: [
                    NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: "Icon View")!,
                    NSImage(systemSymbolName: "list.bullet", accessibilityDescription: "List View")!,
                    NSImage(systemSymbolName: "rectangle.split.3x1", accessibilityDescription: "Column View")!,
                    NSImage(systemSymbolName: "photo.on.rectangle", accessibilityDescription: "Gallery View")!,
                ],
                trackingMode: .selectOne,
                target: self,
                action: #selector(viewModeAction(_:))
            )
            control.segmentStyle = .separated
            control.selectedSegment = viewMode == .icon ? 0 : (viewMode == .list ? 1 : (viewMode == .column ? 2 : 3))
            control.sizeToFit()
            item.view = control
            item.minSize = control.fittingSize
            item.maxSize = control.fittingSize
            item.visibilityPriority = .high
            viewModeControl = control
            return item

        case .sortMenu:
            let item = NSMenuToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Group"
            item.paletteLabel = "Group"
            item.image = NSImage(systemSymbolName: "square.grid.3x1.below.line.grid.1x2", accessibilityDescription: "Group and Sort")
                ?? NSImage(systemSymbolName: "arrow.up.arrow.down", accessibilityDescription: "Group and Sort")
            let menu = NSMenu(title: "Group and Sort")

            let arrangeMenu = NSMenu(title: "Arrange By")
            for criterion in GroupByCriterion.allCases {
                let menuItem = NSMenuItem(title: criterion.title, action: #selector(groupByAction(_:)), keyEquivalent: "")
                menuItem.target = self
                menuItem.representedObject = criterion
                arrangeMenu.addItem(menuItem)
            }
            let arrangeSubmenuItem = NSMenuItem(title: "Arrange By", action: nil, keyEquivalent: "")
            arrangeSubmenuItem.submenu = arrangeMenu
            menu.addItem(arrangeSubmenuItem)
            menu.addItem(NSMenuItem.separator())

            for key in SortKey.allCases {
                let menuItem = NSMenuItem(title: "Sort by \(key.title)", action: #selector(sortKeyAction(_:)), keyEquivalent: "")
                menuItem.target = self
                menuItem.representedObject = key
                menu.addItem(menuItem)
            }
            menu.addItem(NSMenuItem.separator())
            let ascItem = NSMenuItem(title: "Ascending", action: #selector(toggleSortAscending(_:)), keyEquivalent: "")
            ascItem.target = self
            menu.addItem(ascItem)
            item.menu = menu
            item.visibilityPriority = .standard
            return item

        case .share:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Share"
            item.paletteLabel = "Share"
            item.toolTip = "Share selected items"
            item.image = NSImage(systemSymbolName: "square.and.arrow.up", accessibilityDescription: "Share")
            item.target = self
            item.action = #selector(shareAction)
            item.visibilityPriority = .standard
            return item

        case .tags:
            let item = NSMenuToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Tags"
            item.paletteLabel = "Edit Tags"
            item.toolTip = "Apply tags to selected items"
            item.image = NSImage(systemSymbolName: "tag", accessibilityDescription: "Tags")
            let menu = NSMenu(title: "Tags")
            let tagColors: [(String, String)] = [
                ("Red", "#FF3B30"),
                ("Orange", "#FF9500"),
                ("Yellow", "#FFCC00"),
                ("Green", "#34C759"),
                ("Blue", "#007AFF"),
                ("Purple", "#AF52DE"),
                ("Gray", "#8E8E93"),
            ]
            for (name, hex) in tagColors {
                let menuItem = NSMenuItem(title: name, action: #selector(tagColorAction(_:)), keyEquivalent: "")
                menuItem.target = self
                menuItem.representedObject = [name, hex]
                let dot = NSImage(size: NSSize(width: 12, height: 12), flipped: false) { rect in
                    if let color = NSColor(hex: hex) {
                        color.setFill()
                        NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
                        return true
                    }
                    return false
                }
                menuItem.image = dot
                menu.addItem(menuItem)
            }
            item.menu = menu
            item.visibilityPriority = .standard
            return item

        case .action:
            let item = NSMenuToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Action"
            item.paletteLabel = "Action"
            item.image = NSImage(systemSymbolName: "ellipsis.circle", accessibilityDescription: "Action")
            let menu = NSMenu(title: "Action")
            menu.addItem(withTitle: "New Folder", action: #selector(newFolderAction), keyEquivalent: "")
            menu.addItem(withTitle: "Get Info", action: #selector(getInfoAction), keyEquivalent: "")
            menu.addItem(withTitle: "Quick Look", action: #selector(quickLookAction), keyEquivalent: "")
            menu.addItem(NSMenuItem.separator())
            menu.addItem(withTitle: "Rename…", action: #selector(renameAction), keyEquivalent: "")
            menu.addItem(withTitle: "Batch Rename…", action: #selector(batchRenameAction), keyEquivalent: "")
            menu.addItem(withTitle: "Move to Trash", action: #selector(trashAction), keyEquivalent: "")
            menu.addItem(NSMenuItem.separator())
            menu.addItem(withTitle: "Open in Terminal", action: #selector(terminalAction), keyEquivalent: "")
            menu.addItem(withTitle: "Toggle Hidden Files", action: #selector(hiddenFilesAction), keyEquivalent: "")
            menu.addItem(withTitle: "Toggle Path Bar", action: #selector(togglePathBarAction), keyEquivalent: "")
            for m in menu.items { m.target = self }
            item.menu = menu
            item.visibilityPriority = .standard
            return item

        case .newFolder:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "New Folder"
            item.paletteLabel = "New Folder"
            item.toolTip = "Create a new folder"
            item.image = NSImage(systemSymbolName: "folder.badge.plus", accessibilityDescription: "New Folder")
            item.target = self
            item.action = #selector(newFolderAction)
            item.visibilityPriority = .standard
            return item

        case .quickLook:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Quick Look"
            item.paletteLabel = "Quick Look"
            item.toolTip = "Preview selected item"
            item.image = NSImage(systemSymbolName: "eye", accessibilityDescription: "Quick Look")
            item.target = self
            item.action = #selector(quickLookAction)
            return item

        case .trash:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Delete"
            item.paletteLabel = "Move to Trash"
            item.toolTip = "Move selected items to the Trash"
            item.image = NSImage(systemSymbolName: "trash", accessibilityDescription: "Move to Trash")
            item.target = self
            item.action = #selector(trashAction)
            return item

        case .getInfo:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Get Info"
            item.paletteLabel = "Get Info"
            item.toolTip = "Show information for selected item"
            item.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: "Get Info")
            item.target = self
            item.action = #selector(getInfoAction)
            return item

        case .terminal:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Terminal"
            item.paletteLabel = "Open in Terminal"
            item.toolTip = "Open current directory in Terminal"
            item.image = NSImage(systemSymbolName: "terminal", accessibilityDescription: "Open in Terminal")
            item.target = self
            item.action = #selector(terminalAction)
            return item

        case .newTab:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "New Tab"
            item.paletteLabel = "New Tab"
            item.toolTip = "Open a new tab at current location"
            item.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "New Tab")
            item.target = self
            item.action = #selector(newTabAction)
            return item

        case .batchRename:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Rename"
            item.paletteLabel = "Batch Rename"
            item.toolTip = "Rename selected items"
            item.image = NSImage(systemSymbolName: "pencil", accessibilityDescription: "Batch Rename")
            item.target = self
            item.action = #selector(batchRenameAction)
            return item

        case .search:
            let item = NSSearchToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Search"
            item.paletteLabel = "Search"
            item.preferredWidthForSearchField = 150
            item.searchField.target = self
            item.searchField.action = #selector(searchAction(_:))
            item.visibilityPriority = .standard
            return item

        case .pathBar:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Path"
            item.paletteLabel = "Path Bar"
            let hostingView = NSHostingView(rootView: makePathBarView())
            item.view = hostingView
            pathBarHostingView = hostingView
            return item

        case .iconSize:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Icon Size"
            item.paletteLabel = "Icon Size"
            let slider = NSSlider(value: Double(iconSize), minValue: 32, maxValue: 256,
                                  target: self, action: #selector(iconSizeAction(_:)))
            slider.isContinuous = true
            slider.controlSize = .small
            slider.isEnabled = viewMode == .icon
            item.view = slider
            iconSizeSlider = slider
            return item

        case .hiddenFiles:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Hidden Files"
            item.paletteLabel = "Hidden Files"
            let button = NSButton(checkboxWithTitle: "Hidden",
                                  target: self, action: #selector(hiddenFilesAction))
            button.controlSize = .small
            button.state = showsHiddenFiles ? .on : .off
            item.view = button
            hiddenFilesButton = button
            return item

        default:
            return nil
        }
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.toggleSidebar, .navigationGroup, .flexibleSpace, .viewMode, .splitLayout, .sortMenu, .share, .tags, .action, .newFolder, .search]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.toggleSidebar, .navigationGroup, .back, .forward, .flexibleSpace, .space, .viewMode, .splitLayout, .sortMenu, .share, .tags, .action, .newFolder, .quickLook, .trash, .getInfo, .terminal, .newTab, .batchRename, .search, .pathBar, .iconSize, .hiddenFiles]
    }
}

// MARK: - NSToolbarItemValidation

extension BrowserToolbar: NSToolbarItemValidation {
    /// Keeps back/forward and selection-dependent items in sync.
    func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
        switch item.itemIdentifier {
        case .navigationGroup, .back: return canGoBack
        case .forward: return canGoForward
        case .share, .quickLook, .getInfo, .trash, .batchRename, .tags:
            return hasSelection
        default:
            return true
        }
    }
}
