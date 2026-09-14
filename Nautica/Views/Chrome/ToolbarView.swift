import AppKit
import SwiftUI

private extension NSToolbarItem.Identifier {
    static let navigationGroup = NSToolbarItem.Identifier("Nautica.NavigationGroup")
    static let back = NSToolbarItem.Identifier("Nautica.Back")
    static let forward = NSToolbarItem.Identifier("Nautica.Forward")
    static let splitLayout = NSToolbarItem.Identifier("Nautica.SplitLayout")
    static let viewMode = NSToolbarItem.Identifier("Nautica.ViewMode")
    static let sortMenu = NSToolbarItem.Identifier("Nautica.SortMenu")
    static let share = NSToolbarItem.Identifier("Nautica.Share")
    static let action = NSToolbarItem.Identifier("Nautica.Action")
    static let search = NSToolbarItem.Identifier("Nautica.Search")
    static let pathBar = NSToolbarItem.Identifier("Nautica.PathBar")
    static let iconSize = NSToolbarItem.Identifier("Nautica.IconSize")
    static let hiddenFiles = NSToolbarItem.Identifier("Nautica.HiddenFiles")
}

/// Main-window toolbar matching macOS Finder:
/// Back/Forward navigation group, flexible space, View mode, Panes, Sort/Group, Share, Actions, and Search.
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
    var onShare: (() -> Void)?
    var onNewFolder: (() -> Void)?
    var onGetInfo: (() -> Void)?
    var onRename: (() -> Void)?
    var onBatchRename: (() -> Void)?
    var onTrash: (() -> Void)?
    var onTogglePathBar: (() -> Void)?
    var onSearch: ((String) -> Void)?

    // MARK: - Mirrored state (set before calling refresh())

    var canGoBack = false
    var canGoForward = false
    var currentURL = FileManager.default.homeURL
    var splitLayout: SplitLayout = .single
    var viewMode: ViewMode = .list
    var iconSize: CGFloat = 64
    var showsHiddenFiles = false
    var currentSortKey: SortKey = .name
    var sortAscending: Bool = true

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
        toolbar = NSToolbar(identifier: "NauticaMainToolbar.v5")
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
        viewModeControl?.selectedSegment = viewMode == .icon ? 0 : 1
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
        onViewModeChanged?(sender.selectedSegment == 0 ? .icon : .list)
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

    @objc private func shareAction() { onShare?() }
    @objc private func newFolderAction() { onNewFolder?() }
    @objc private func getInfoAction() { onGetInfo?() }
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
            item.image = NSImage(systemSymbolName: "chevron.backward", accessibilityDescription: "Back")
            item.target = self
            item.action = #selector(backAction)
            item.isEnabled = canGoBack
            backItem = item
            return item

        case .forward:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Forward"
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
                ],
                trackingMode: .selectOne,
                target: self,
                action: #selector(viewModeAction(_:))
            )
            control.segmentStyle = .separated
            control.selectedSegment = viewMode == .icon ? 0 : 1
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
            item.image = NSImage(systemSymbolName: "square.grid.3x1.below.line.grid.1x2", accessibilityDescription: "Sort")
                ?? NSImage(systemSymbolName: "arrow.up.arrow.down", accessibilityDescription: "Sort")
            let menu = NSMenu(title: "Sort")
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
            item.image = NSImage(systemSymbolName: "square.and.arrow.up", accessibilityDescription: "Share")
            item.target = self
            item.action = #selector(shareAction)
            return item

        case .action:
            let item = NSMenuToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Action"
            item.paletteLabel = "Action"
            item.image = NSImage(systemSymbolName: "ellipsis.circle", accessibilityDescription: "Action")
            let menu = NSMenu(title: "Action")
            menu.addItem(withTitle: "New Folder", action: #selector(newFolderAction), keyEquivalent: "")
            menu.addItem(withTitle: "Get Info", action: #selector(getInfoAction), keyEquivalent: "")
            menu.addItem(NSMenuItem.separator())
            menu.addItem(withTitle: "Rename…", action: #selector(renameAction), keyEquivalent: "")
            menu.addItem(withTitle: "Batch Rename…", action: #selector(batchRenameAction), keyEquivalent: "")
            menu.addItem(withTitle: "Move to Trash", action: #selector(trashAction), keyEquivalent: "")
            menu.addItem(NSMenuItem.separator())
            menu.addItem(withTitle: "Toggle Hidden Files", action: #selector(hiddenFilesAction), keyEquivalent: "")
            menu.addItem(withTitle: "Toggle Path Bar", action: #selector(togglePathBarAction), keyEquivalent: "")
            for m in menu.items { m.target = self }
            item.menu = menu
            item.visibilityPriority = .standard
            return item

        case .search:
            let item = NSSearchToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Search"
            item.paletteLabel = "Search"
            item.preferredWidthForSearchField = 160
            item.searchField.target = self
            item.searchField.action = #selector(searchAction(_:))
            item.visibilityPriority = .standard
            return item

        case .pathBar:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Path"
            let hostingView = NSHostingView(rootView: makePathBarView())
            item.view = hostingView
            item.minSize = NSSize(width: 160, height: 32)
            item.maxSize = NSSize(width: 4000, height: 32)
            pathBarHostingView = hostingView
            return item

        case .iconSize:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Icon Size"
            let slider = NSSlider(value: Double(iconSize), minValue: 32, maxValue: 256,
                                  target: self, action: #selector(iconSizeAction(_:)))
            slider.isContinuous = true
            slider.controlSize = .small
            slider.isEnabled = viewMode == .icon
            item.view = slider
            item.minSize = NSSize(width: 100, height: 24)
            item.maxSize = NSSize(width: 140, height: 24)
            iconSizeSlider = slider
            return item

        case .hiddenFiles:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Hidden Files"
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
        [.toggleSidebar, .navigationGroup, .flexibleSpace, .viewMode, .splitLayout, .sortMenu, .action, .search]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.toggleSidebar, .navigationGroup, .back, .forward, .flexibleSpace, .viewMode, .splitLayout, .sortMenu, .share, .action, .search, .pathBar, .iconSize, .hiddenFiles]
    }
}

// MARK: - NSToolbarItemValidation

extension BrowserToolbar: NSToolbarItemValidation {
    /// Keeps back/forward in sync when AppKit revalidates the toolbar on its own.
    func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
        switch item.itemIdentifier {
        case .navigationGroup, .back: return canGoBack
        case .forward: return canGoForward
        default: return true
        }
    }
}
