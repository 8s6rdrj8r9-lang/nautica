import AppKit
import Observation

/// Columns shown in the list view. Raw values double as table-column
/// identifiers and keys for UserDefaults persistence.
enum ListColumn: String, CaseIterable {
    case name
    case size
    case kind
    case modificationDate
    case creationDate
    case tags

    static let defaultColumns: [ListColumn] = [.name, .size, .kind, .modificationDate]

    var title: String {
        switch self {
        case .name: return "Name"
        case .size: return "Size"
        case .modificationDate: return "Date Modified"
        case .creationDate: return "Date Created"
        case .kind: return "Kind"
        case .tags: return "Tags"
        }
    }

    var defaultWidth: CGFloat {
        switch self {
        case .name: return 260
        case .size: return 90
        case .modificationDate, .creationDate: return 160
        case .kind: return 120
        case .tags: return 120
        }
    }

    var minWidth: CGFloat {
        self == .name ? 120 : 50
    }

    /// Sort attribute backing the column; the Tags stub is not sortable.
    var sortKey: SortKey? {
        switch self {
        case .name: return .name
        case .size: return .size
        case .modificationDate: return .modificationDate
        case .creationDate: return .creationDate
        case .kind: return .kind
        case .tags: return nil
        }
    }
}

/// NSTableView subclass that forwards key events to the file-view
/// coordinator (arrow navigation, Cmd+A, Esc, type-ahead, Space/Quick Look),
/// mirroring IconCollectionView.
private final class FileListTableView: NSTableView {
    var onKeyDown: ((NSEvent) -> Bool)?
    /// Builds the right-click menu for the row under the cursor.
    var onMenuRequest: ((Int) -> NSMenu?)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if onKeyDown?(event) != true {
            super.keyDown(with: event)
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        let row = row(at: point)
        guard row >= 0 else { return nil }
        return onMenuRequest?(row)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }
}

/// Persists list-view column widths and order in UserDefaults.
/// Per-folder SwiftData state (F-014) replaces this in Prompt 12.
private enum ListColumnLayoutStore {
    private static let orderKey = "Nautica.ListView.ColumnOrder"
    private static let widthsKey = "Nautica.ListView.ColumnWidths"

    static func loadOrder() -> [String]? {
        UserDefaults.standard.stringArray(forKey: orderKey)
    }

    static func loadWidth(for column: ListColumn) -> CGFloat? {
        let widths = UserDefaults.standard.dictionary(forKey: widthsKey) as? [String: Double]
        guard let width = widths?[column.rawValue], width > 0 else { return nil }
        return CGFloat(width)
    }

    static func save(tableView: NSTableView) {
        var widths: [String: Double] = [:]
        for column in tableView.tableColumns {
            widths[column.identifier.rawValue] = Double(column.width)
        }
        let defaults = UserDefaults.standard
        defaults.set(tableView.tableColumns.map(\.identifier.rawValue), forKey: orderKey)
        defaults.set(widths, forKey: widthsKey)
    }
}

/// View controller hosting the list view: a view-based NSTableView whose
/// selection is owned by the shared `SelectionModel`, mirroring
/// IconViewController. Sorting runs through `DirectoryContents` so both
/// file views share the same order.
final class ListViewController: NSViewController {
    let directoryContents: DirectoryContents
    let selectionModel: SelectionModel

    /// Double-click on a folder.
    var onNavigate: ((URL) -> Void)?
    /// Keyboard events from the table view (FileViewCoordinator routes these).
    var keyDownHandler: ((NSEvent) -> Bool)?
    /// Context-menu actions routed to BrowserView (rename sheet, copy, trash).
    var onRenameRequest: (() -> Void)?
    var onCopySelection: (() -> Void)?
    var onTrashSelection: (() -> Void)?
    /// Comma-separated tag names for an item. Stub seam for the TagService
    /// integration arriving in Prompt 11 (F-013).
    var tagsProvider: (FileItem) -> String = { _ in "" }

    private var fontSize: CGFloat = 13
    private var iconSize: CGFloat = 16
    private var rowSpacing: CGFloat = 2

    func applyAppearance(fontSize: CGFloat, iconSize: CGFloat, spacing: CGFloat) {
        guard self.fontSize != fontSize || self.iconSize != iconSize || rowSpacing != spacing else { return }
        self.fontSize = fontSize
        self.iconSize = iconSize
        rowSpacing = spacing
        iconCache.clear()
        guard isViewLoaded else { return }
        tableView.rowHeight = max(ceil(fontSize * 1.3), iconSize) + 2 * spacing
        tableView.intercellSpacing = NSSize(width: 3, height: 0)
        tableView.reloadData()
        applySelection()
    }

    private let iconCache = IconCache()
    private var tableView: FileListTableView!
    private var currentItems: [FileItem] = []

    init(directoryContents: DirectoryContents, selectionModel: SelectionModel) {
        self.directoryContents = directoryContents
        self.selectionModel = selectionModel
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - View setup

    override func loadView() {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        let tableView = FileListTableView()
        tableView.headerView = NSTableHeaderView()
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 22
        tableView.intercellSpacing = NSSize(width: 6, height: 2)
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.style = .plain
        tableView.allowsMultipleSelection = true
        tableView.allowsColumnReordering = true
        tableView.allowsColumnResizing = true
        tableView.columnAutoresizingStyle = .noColumnAutoresizing
        tableView.onKeyDown = { [weak self] event in
            self?.keyDownHandler?(event) ?? false
        }
        tableView.onMenuRequest = { [weak self] row in
            self?.menu(forRow: row)
        }
        tableView.target = self
        tableView.doubleAction = #selector(handleDoubleClick(_:))

        for column in ListColumn.defaultColumns {
            let identifier = NSUserInterfaceItemIdentifier(column.rawValue)
            let tableColumn = NSTableColumn(identifier: identifier)
            tableColumn.title = column.title
            tableColumn.minWidth = column.minWidth
            tableColumn.width = ListColumnLayoutStore.loadWidth(for: column) ?? column.defaultWidth
            if column == .size {
                tableColumn.headerCell.alignment = .right
            }
            if let sortKey = column.sortKey {
                tableColumn.sortDescriptorPrototype = NSSortDescriptor(
                    key: sortKey.rawValue, ascending: true
                )
            }
            tableView.addTableColumn(tableColumn)
        }
        restoreColumnOrder(in: tableView)

        // Reflect the active sort in the header indicator.
        tableView.sortDescriptors = [
            NSSortDescriptor(
                key: directoryContents.sortKey.rawValue,
                ascending: directoryContents.sortAscending
            ),
        ]

        scrollView.documentView = tableView
        self.tableView = tableView
        view = scrollView
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(columnLayoutDidChange(_:)),
            name: NSTableView.columnDidMoveNotification,
            object: tableView
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(columnLayoutDidChange(_:)),
            name: NSTableView.columnDidResizeNotification,
            object: tableView
        )

        applyItems(directoryContents.items)
        startObserving()
    }

    /// Re-applies the persisted drag-reorder of the column headers.
    private func restoreColumnOrder(in tableView: NSTableView) {
        guard let order = ListColumnLayoutStore.loadOrder() else { return }
        for (targetIndex, rawValue) in order.enumerated() {
            let identifier = NSUserInterfaceItemIdentifier(rawValue)
            let currentIndex = tableView.column(withIdentifier: identifier)
            guard currentIndex >= 0, currentIndex != targetIndex else { continue }
            tableView.moveColumn(currentIndex, toColumn: targetIndex)
        }
    }

    @objc private func columnLayoutDidChange(_ notification: Notification) {
        ListColumnLayoutStore.save(tableView: tableView)
    }

    // MARK: - Items & selection

    /// Reloads the table for a new item list.
    func applyItems(_ items: [FileItem]) {
        guard isViewLoaded, tableView != nil else { return }
        currentItems = items
        tableView.reloadData()
        applySelection()
    }

    /// Re-establishes one-shot observation of the models after every change.
    private func startObserving() {
        withObservationTracking {
            _ = directoryContents.items
            _ = selectionModel.selectedIDs
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.applyItems(self.directoryContents.items)
                self.applySelection()
                self.startObserving()
            }
        }
    }

    /// The SelectionModel is the source of truth; the table view's native
    /// selection only mirrors it (see `selectionIndexesForProposedSelection`).
    func applySelection() {
        guard isViewLoaded, tableView != nil else { return }
        let indexes = selectedRowIndexes()
        if indexes != tableView.selectedRowIndexes {
            tableView.selectRowIndexes(indexes, byExtendingSelection: false)
        }
        // Keep keyboard-driven selections on screen.
        if let lastClickedID = selectionModel.lastClickedID,
           let row = currentItems.firstIndex(where: { $0.id == lastClickedID }),
           tableView.numberOfRows > 0 {
            let visibleRows = tableView.rows(in: tableView.visibleRect)
            if !NSLocationInRange(row, visibleRows) {
                tableView.scrollRowToVisible(row)
            }
        }
    }

    private func selectedRowIndexes() -> IndexSet {
        IndexSet(
            currentItems.indices.filter { selectionModel.isSelected(currentItems[$0].id) }
        )
    }

    // MARK: - Double-click

    @objc private func handleDoubleClick(_ sender: NSTableView) {
        let row = tableView.clickedRow
        guard row >= 0, row < currentItems.count else { return }
        let item = currentItems[row]
        if item.isDirectory {
            onNavigate?(item.url)
        } else {
            NSWorkspace.shared.open(item.url)
        }
    }

    // MARK: - Context menu

    /// Items the context menu acts on (the selection after the right-click).
    private var contextMenuItems: [FileItem] = []
    private var sharingServicePicker: NSSharingServicePicker?

    /// Right-click on a row: select it if needed, then build the shared menu.
    private func menu(forRow row: Int) -> NSMenu? {
        guard row >= 0, row < currentItems.count else { return nil }
        let item = currentItems[row]
        if !selectionModel.isSelected(item.id) {
            selectionModel.select(item.id, modifierFlags: [])
            applySelection()
        }
        contextMenuItems = currentItems.filter { selectionModel.isSelected($0.id) }
        return FileContextMenu.makeMenu(for: contextMenuItems, actions: contextMenuActions(forRow: row))
    }

    private func contextMenuActions(forRow row: Int) -> FileContextMenu.Actions {
        FileContextMenu.Actions(
            open: { [weak self] in
                guard let self else { return }
                for item in contextMenuItems where !item.isDirectory {
                    NSWorkspace.shared.open(item.url)
                }
                if let folder = contextMenuItems.first(where: \.isDirectory) {
                    onNavigate?(folder.url)
                }
            },
            openWith: { [weak self] appURL in
                guard let self else { return }
                NSWorkspace.shared.open(
                    contextMenuItems.map(\.url),
                    withApplicationAt: appURL,
                    configuration: NSWorkspace.OpenConfiguration()
                )
            },
            quickLook: { [weak self] in
                guard let self else { return }
                QuickLookService.shared.togglePreview(
                    for: contextMenuItems.map(\.url), selectedIndex: 0
                )
            },
            getInfo: { [weak self] in
                if let item = self?.contextMenuItems.first {
                    FileContextMenu.showInfo(for: item)
                }
            },
            rename: { [weak self] in self?.onRenameRequest?() },
            copy: { [weak self] in self?.onCopySelection?() },
            trash: { [weak self] in self?.onTrashSelection?() },
            share: { [weak self] in self?.shareSelection(anchoredAtRow: row) }
        )
    }

    private func shareSelection(anchoredAtRow row: Int) {
        let urls = contextMenuItems.map(\.url)
        guard !urls.isEmpty else { return }
        let picker = NSSharingServicePicker(items: urls)
        sharingServicePicker = picker // retained until the picker is dismissed
        if let rowView = tableView.rowView(atRow: row, makeIfNecessary: false) {
            picker.show(relativeTo: rowView.bounds, of: rowView, preferredEdge: .minY)
        } else {
            picker.show(relativeTo: tableView.bounds, of: tableView, preferredEdge: .minY)
        }
    }
}

// MARK: - NSTableViewDataSource

extension ListViewController: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        currentItems.count
    }
}

// MARK: - NSTableViewDelegate

extension ListViewController: NSTableViewDelegate {
    func tableView(_ tableView: NSTableView,
                   viewFor tableColumn: NSTableColumn?,
                   row: Int) -> NSView? {
        guard let tableColumn,
              let column = ListColumn(rawValue: tableColumn.identifier.rawValue),
              row < currentItems.count else { return nil }
        let item = currentItems[row]
        let identifier = tableColumn.identifier
        let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? ListViewCell
            ?? ListViewCell(identifier: identifier)
        cell.configure(with: item, forColumn: column, tags: tagsProvider(item),
                       fontSize: fontSize, iconSize: iconSize)
        if column == .name {
            iconCache.icon(for: item.url, size: iconSize) { [weak cell] image in
                guard let cell, cell.fileItem?.id == item.id else { return }
                cell.imageView?.image = image
            }
        }
        return cell
    }

    /// Routes every click through the SelectionModel (Finder semantics:
    /// plain/Cmd/Shift) and mirrors the result back to the table view.
    func tableView(_ tableView: NSTableView,
                   selectionIndexesForProposedSelection proposedSelectionIndexes: IndexSet)
        -> IndexSet {
        guard let event = NSApp.currentEvent,
              event.type == .leftMouseDown || event.type == .leftMouseUp else {
            return proposedSelectionIndexes
        }
        let row = tableView.clickedRow
        guard row >= 0, row < currentItems.count else {
            // Click on empty area: deselect all.
            selectionModel.deselectAll()
            return IndexSet()
        }
        selectionModel.handleClick(currentItems[row].id, modifierFlags: event.modifierFlags, in: currentItems)
        return selectedRowIndexes()
    }

    /// Column-header click: NSTableView toggles the sort descriptor
    /// (ascending/descending) and draws the indicator arrow; the actual
    /// sort runs in DirectoryContents so both file views share the order.
    func tableView(_ tableView: NSTableView,
                   sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        guard let descriptor = tableView.sortDescriptors.first,
              let key = descriptor.key,
              let sortKey = SortKey(rawValue: key) else { return }
        directoryContents.sort(by: sortKey, ascending: descriptor.ascending)
    }
}
