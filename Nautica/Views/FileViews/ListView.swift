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

    var headerTitle: String { title }

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

/// Representation of a single displayed row in the hierarchical list view.
struct HierarchicalRow: Equatable {
    let item: FileItem
    let depth: Int
    let isExpanded: Bool
    let parentURL: URL?
    let isGroupHeader: Bool
    let groupTitle: String
    let groupCount: Int

    init(
        item: FileItem,
        depth: Int = 0,
        isExpanded: Bool = false,
        parentURL: URL? = nil,
        isGroupHeader: Bool = false,
        groupTitle: String = "",
        groupCount: Int = 0
    ) {
        self.item = item
        self.depth = depth
        self.isExpanded = isExpanded
        self.parentURL = parentURL
        self.isGroupHeader = isGroupHeader
        self.groupTitle = groupTitle
        self.groupCount = groupCount
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
/// selection is owned by the shared `SelectionModel`, with hierarchical inline folder
/// tree expansion (disclosure chevrons, arrow key navigation) and spring-loaded folders.
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
    var onCompressWithPassword: (([URL]) -> Void)?
    var onAddToDropShelf: (([URL]) -> Void)?
    var onSecureDelete: (([FileItem]) -> Void)?
    var onCreateEncryptedArchive: (([FileItem]) -> Void)?
    var onExtractEncryptedArchive: ((URL) -> Void)?
    var onFindDuplicates: ((URL) -> Void)?
    var onGitDiff: ((URL) -> Void)?
    var onGitCommit: (() -> Void)?
    var onUnlockVault: ((URL) -> Void)?
    var onLockVault: ((URL) -> Void)?
    var onCreateVault: (() -> Void)?
    var onCheckVaultHealth: ((URL) -> Void)?
    /// Comma-separated tag names for an item. Stub seam for TagService.
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

    // MARK: - Hierarchical State
    private(set) var currentRows: [HierarchicalRow] = []
    private(set) var currentItems: [FileItem] = []
    private var expandedURLs: Set<URL> = []
    private var subfolderItemsCache: [URL: [FileItem]] = [:]

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

        tableView.setDraggingSourceOperationMask([.copy, .move], forLocal: false)
        tableView.setDraggingSourceOperationMask([.copy, .move], forLocal: true)
        tableView.registerForDraggedTypes(
            [.fileURL] + NSFilePromiseReceiver.readableDraggedTypes
                .map { NSPasteboard.PasteboardType(rawValue: $0) }
        )

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

    // MARK: - Hierarchical Expansion & Items

    /// Rebuilds flattened rows array from directoryContents items plus any expanded child folders.
    func applyItems(_ items: [FileItem]) {
        guard isViewLoaded, tableView != nil else { return }
        rebuildHierarchicalRows()
    }

    func toggleExpansion(for item: FileItem) {
        guard item.isDirectory else { return }
        if expandedURLs.contains(item.url) {
            expandedURLs.remove(item.url)
            rebuildHierarchicalRows()
        } else {
            expandedURLs.insert(item.url)
            if subfolderItemsCache[item.url] == nil {
                Task {
                    do {
                        let children = try await FileSystemService.shared.contentsOfDirectory(
                            at: item.url,
                            includingHidden: directoryContents.showHiddenFiles
                        )
                        await MainActor.run {
                            self.subfolderItemsCache[item.url] = children
                            self.rebuildHierarchicalRows()
                        }
                    } catch {
                        await MainActor.run {
                            self.subfolderItemsCache[item.url] = []
                            self.rebuildHierarchicalRows()
                        }
                    }
                }
            } else {
                rebuildHierarchicalRows()
            }
        }
    }

    func expandFolder(_ item: FileItem) {
        guard item.isDirectory, !expandedURLs.contains(item.url) else { return }
        toggleExpansion(for: item)
    }

    private func rebuildHierarchicalRows() {
        var rows: [HierarchicalRow] = []

        func appendItems(_ items: [FileItem], depth: Int, parentURL: URL?) {
            for item in items {
                let isExp = expandedURLs.contains(item.url)
                rows.append(HierarchicalRow(item: item, depth: depth, isExpanded: isExp, parentURL: parentURL))
                if item.isDirectory && isExp {
                    if let children = subfolderItemsCache[item.url] {
                        let sorted = DirectoryContents.sort(
                            children,
                            by: directoryContents.sortKey,
                            ascending: directoryContents.sortAscending
                        )
                        appendItems(sorted, depth: depth + 1, parentURL: item.url)
                    }
                }
            }
        }

        if directoryContents.groupBy != .none {
            let groups = directoryContents.groupedSections()
            for group in groups {
                let dummyItem = FileItem(url: URL(fileURLWithPath: "/group/\(group.title)"), name: group.title, isDirectory: false, size: nil, modificationDate: nil, creationDate: nil, isHidden: false, kind: "")
                rows.append(HierarchicalRow(
                    item: dummyItem,
                    depth: 0,
                    isExpanded: true,
                    parentURL: nil,
                    isGroupHeader: true,
                    groupTitle: group.title,
                    groupCount: group.items.count
                ))
                appendItems(group.items, depth: 0, parentURL: nil)
            }
        } else {
            appendItems(directoryContents.items, depth: 0, parentURL: nil)
        }

        currentRows = rows
        currentItems = rows.filter { !$0.isGroupHeader }.map(\.item)
        tableView?.reloadData()
        applySelection()
    }

    /// Handles Finder-style right arrow expansion / child navigation.
    func handleRightArrow() -> Bool {
        guard let selectedID = selectionModel.lastClickedID,
              let index = currentRows.firstIndex(where: { $0.item.id == selectedID }) else {
            return false
        }
        let row = currentRows[index]
        if row.item.isDirectory {
            if !row.isExpanded {
                toggleExpansion(for: row.item)
                return true
            } else if index + 1 < currentRows.count {
                selectionModel.select(currentRows[index + 1].item.id, modifierFlags: [])
                applySelection()
                return true
            }
        }
        return false
    }

    /// Handles Finder-style left arrow collapse / parent navigation.
    func handleLeftArrow() -> Bool {
        guard let selectedID = selectionModel.lastClickedID,
              let index = currentRows.firstIndex(where: { $0.item.id == selectedID }) else {
            return false
        }
        let row = currentRows[index]
        if row.item.isDirectory && row.isExpanded {
            toggleExpansion(for: row.item)
            return true
        } else if let parentURL = row.parentURL,
                  let parentIndex = currentRows.firstIndex(where: { $0.item.url == parentURL }) {
            selectionModel.select(currentRows[parentIndex].item.id, modifierFlags: [])
            applySelection()
            return true
        }
        return false
    }

    // MARK: - Selection

    /// Re-establishes one-shot observation of the models after every change.
    private func startObserving() {
        withObservationTracking {
            _ = directoryContents.items
            _ = directoryContents.groupBy
            _ = selectionModel.selectedIDs
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.rebuildHierarchicalRows()
                self.startObserving()
            }
        }
    }

    /// The SelectionModel is the source of truth; the table view's native
    /// selection only mirrors it.
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
        if VaultService.shared.isVault(at: item.url) {
            let status = VaultService.shared.isVaultMounted(at: item.url)
            if status.isMounted, let mount = status.mountURL {
                onNavigate?(mount)
            } else {
                onUnlockVault?(item.url)
            }
        } else if ArchiveService.shared.isArchive(url: item.url) {
            Task {
                do {
                    _ = try await ArchiveService.shared.extract(archiveURL: item.url)
                    await MainActor.run { self.directoryContents.reload() }
                } catch {
                    await MainActor.run { NSAlert(error: error).runModal() }
                }
            }
        } else if ArchiveService.shared.isDiskImage(url: item.url) {
            Task {
                do {
                    let mountPoint = try await ArchiveService.shared.attachDiskImage(at: item.url)
                    await MainActor.run { self.onNavigate?(mountPoint) }
                } catch {
                    await MainActor.run { NSAlert(error: error).runModal() }
                }
            }
        } else if item.isDirectory {
            onNavigate?(item.url)
        } else {
            NSWorkspace.shared.open(item.url)
        }
    }

    // MARK: - Context menu

    private var contextMenuItems: [FileItem] = []
    private var sharingServicePicker: NSSharingServicePicker?

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
        let isGit = GitService.shared.isGitRepository(at: directoryContents.url)
        return FileContextMenu.Actions(
            open: { [weak self] in
                guard let self else { return }
                for item in contextMenuItems {
                    if VaultService.shared.isVault(at: item.url) {
                        let status = VaultService.shared.isVaultMounted(at: item.url)
                        if status.isMounted, let mount = status.mountURL {
                            self.onNavigate?(mount)
                        } else {
                            self.onUnlockVault?(item.url)
                        }
                    } else if item.isDirectory {
                        self.onNavigate?(item.url)
                    } else {
                        NSWorkspace.shared.open(item.url)
                    }
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
                    GetInfoService.shared.showInfo(for: item.url)
                }
            },
            rename: { [weak self] in
                self?.onRenameRequest?()
            },
            copy: { [weak self] in
                self?.onCopySelection?()
            },
            trash: { [weak self] in
                self?.onTrashSelection?()
            },
            share: { [weak self] in
                self?.shareSelection(anchoredAtRow: row)
            },
            compress: { [weak self] in
                guard let self else { return }
                let urls = self.contextMenuItems.map(\.url)
                guard let first = urls.first else { return }
                let targetDir = first.deletingLastPathComponent()
                let archiveName = urls.count == 1 ? "\(first.deletingPathExtension().lastPathComponent).zip" : "Archive.zip"
                let zipURL = targetDir.appendingPathComponent(archiveName)
                Task.detached {
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
                    if urls.count == 1 {
                        process.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", first.path, zipURL.path]
                    } else {
                        process.arguments = ["-c", "-k", "--sequesterRsrc"] + urls.map(\.path) + [zipURL.path]
                    }
                    try? process.run()
                    process.waitUntilExit()
                }
            },
            extract: { [weak self] in
                guard let self, let first = self.contextMenuItems.first else { return }
                Task {
                    do {
                        _ = try await ArchiveService.shared.extract(archiveURL: first.url)
                        await MainActor.run { self.directoryContents.reload() }
                    } catch {
                        await MainActor.run { NSAlert(error: error).runModal() }
                    }
                }
            },
            mountDiskImage: { [weak self] in
                guard let self, let first = self.contextMenuItems.first else { return }
                Task {
                    do {
                        let mount = try await ArchiveService.shared.attachDiskImage(at: first.url)
                        await MainActor.run { self.onNavigate?(mount) }
                    } catch {
                        await MainActor.run { NSAlert(error: error).runModal() }
                    }
                }
            },
            compressWithPassword: { [weak self] in
                guard let self else { return }
                self.onCompressWithPassword?(self.contextMenuItems.map(\.url))
            },
            createSymlink: { [weak self] in
                guard let self, let first = self.contextMenuItems.first else { return }
                let parentDir = first.url.deletingLastPathComponent()
                let symlinkName = "\(first.name) symlink"
                let symlinkURL = parentDir.appendingPathComponent(symlinkName)
                try? FileManager.default.createSymbolicLink(at: symlinkURL, withDestinationURL: first.url)
            },
            copyPath: { [weak self] in
                guard let self else { return }
                let text = self.contextMenuItems.map(\.url.path).joined(separator: "\n")
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            },
            openInTerminal: { [weak self] in
                guard let self, let first = self.contextMenuItems.first else { return }
                let folderURL = first.isDirectory ? first.url : first.url.deletingLastPathComponent()
                Task {
                    try? await TerminalService.shared.openTerminal(
                        at: folderURL,
                        emulator: TerminalService.shared.defaultTerminal()
                    )
                }
            },
            putBack: { [weak self] in
                guard let self else { return }
                let urls = self.contextMenuItems.map(\.url)
                Task {
                    _ = await TrashOriginStore.shared.putBack(urls: urls)
                    await MainActor.run {
                        self.directoryContents.reload()
                    }
                }
            },
            makeAlias: { [weak self] in
                guard let self else { return }
                let urls = self.contextMenuItems.map(\.url)
                guard !urls.isEmpty else { return }
                let dest = self.directoryContents.url
                Task {
                    _ = await FileOperationService.shared.makeAliases(for: urls, in: dest)
                    await MainActor.run { self.directoryContents.reload() }
                }
            },
            showOriginal: { [weak self] in
                guard let self, let first = self.contextMenuItems.first else { return }
                if let targetURL = first.resolvedTargetURL ?? FileOperationService.shared.resolveTarget(for: first.url) {
                    let parentURL = targetURL.deletingLastPathComponent().standardizedFileURL
                    let currentParent = self.directoryContents.url.standardizedFileURL
                    if currentParent.path == parentURL.path {
                        self.selectionModel.deselectAll()
                        if let item = self.currentItems.first(where: { $0.url.standardizedFileURL.path == targetURL.standardizedFileURL.path }) {
                            self.selectionModel.select(item.id, modifierFlags: [])
                            self.applySelection()
                        }
                    } else {
                        self.onNavigate?(parentURL)
                    }
                }
            },
            rotateLeft: { [weak self] in
                guard let self else { return }
                let urls = self.contextMenuItems.map(\.url)
                Task {
                    for url in urls {
                        await QuickActionService.shared.rotateImage(at: url, degrees: 270)
                    }
                    await MainActor.run { self.directoryContents.reload() }
                }
            },
            rotateRight: { [weak self] in
                guard let self else { return }
                let urls = self.contextMenuItems.map(\.url)
                Task {
                    for url in urls {
                        await QuickActionService.shared.rotateImage(at: url, degrees: 90)
                    }
                    await MainActor.run { self.directoryContents.reload() }
                }
            },
            createPDF: { [weak self] in
                guard let self else { return }
                let urls = self.contextMenuItems.map(\.url)
                let dest = self.directoryContents.url
                Task {
                    _ = try? await QuickActionService.shared.createPDF(from: urls, in: dest)
                    await MainActor.run { self.directoryContents.reload() }
                }
            },
            runShortcut: { [weak self] shortcutName in
                guard let self, let first = self.contextMenuItems.first else { return }
                Task {
                    _ = try? await QuickActionService.shared.runShortcut(name: shortcutName, inputFile: first.url)
                    await MainActor.run { self.directoryContents.reload() }
                }
            },
            toggleTag: { [weak self] color in
                guard let self else { return }
                let urls = self.contextMenuItems.map(\.url)
                Task {
                    try? await TagService.shared.toggleColorTag(color, for: urls)
                    await MainActor.run { self.directoryContents.reload() }
                }
            },
            clearTags: { [weak self] in
                guard let self else { return }
                let urls = self.contextMenuItems.map(\.url)
                Task {
                    try? await TagService.shared.clearAllTags(for: urls)
                    await MainActor.run { self.directoryContents.reload() }
                }
            },
            copyChecksum: { [weak self] in
                guard let self, let first = self.contextMenuItems.first, !first.isDirectory else { return }
                Task {
                    if let hash = try? await ChecksumService.shared.computeSHA256(url: first.url) {
                        await MainActor.run {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(hash, forType: .string)
                        }
                    }
                }
            },
            findDuplicates: { [weak self] in
                guard let self else { return }
                let folder = self.contextMenuItems.first(where: \.isDirectory)?.url ?? self.directoryContents.url
                self.onFindDuplicates?(folder)
            },
            gitStage: isGit ? { [weak self] in
                guard let self else { return }
                let urls = self.contextMenuItems.map(\.url)
                Task {
                    try? await GitService.shared.stage(urls: urls, at: self.directoryContents.url)
                    await MainActor.run { self.directoryContents.reload() }
                }
            } : nil,
            gitUnstage: isGit ? { [weak self] in
                guard let self else { return }
                let urls = self.contextMenuItems.map(\.url)
                Task {
                    try? await GitService.shared.unstage(urls: urls, at: self.directoryContents.url)
                    await MainActor.run { self.directoryContents.reload() }
                }
            } : nil,
            gitDiscard: isGit ? { [weak self] in
                guard let self else { return }
                let urls = self.contextMenuItems.map(\.url)
                Task {
                    try? await GitService.shared.discardChanges(for: urls, at: self.directoryContents.url)
                    await MainActor.run { self.directoryContents.reload() }
                }
            } : nil,
            gitDiff: isGit ? { [weak self] in
                guard let self, let first = self.contextMenuItems.first else { return }
                self.onGitDiff?(first.url)
            } : nil,
            gitCommit: isGit ? { [weak self] in
                self?.onGitCommit?()
            } : nil,
            unlockVault: { [weak self] in
                guard let self, let first = self.contextMenuItems.first else { return }
                self.onUnlockVault?(first.url)
            },
            lockVault: { [weak self] in
                guard let self, let first = self.contextMenuItems.first else { return }
                self.onLockVault?(first.url)
            },
            createVault: { [weak self] in
                self?.onCreateVault?()
            },
            checkVaultHealth: { [weak self] in
                guard let self, let first = self.contextMenuItems.first else { return }
                self.onCheckVaultHealth?(first.url)
            },
            addToDropShelf: { [weak self] in
                guard let self else { return }
                self.onAddToDropShelf?(self.contextMenuItems.map(\.url))
            },
            secureDelete: { [weak self] in
                guard let self else { return }
                self.onSecureDelete?(self.contextMenuItems)
            },
            createEncryptedArchive: { [weak self] in
                guard let self else { return }
                self.onCreateEncryptedArchive?(self.contextMenuItems)
            },
            extractEncryptedArchive: { [weak self] in
                guard let self, let first = self.contextMenuItems.first else { return }
                self.onExtractEncryptedArchive?(first.url)
            }
        )
    }

    private func shareSelection(anchoredAtRow row: Int) {
        let urls = contextMenuItems.map(\.url)
        guard !urls.isEmpty else { return }
        let picker = NSSharingServicePicker(items: urls)
        sharingServicePicker = picker
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
        currentRows.count
    }

    // MARK: - Drag source

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        guard row >= 0, row < currentRows.count, !currentRows[row].isGroupHeader else { return nil }
        let item = currentRows[row].item
        if !selectionModel.isSelected(item.id) {
            selectionModel.select(item.id, modifierFlags: [])
            applySelection()
        }
        return item.url as NSURL
    }

    func tableView(_ tableView: NSTableView,
                   draggingSession session: NSDraggingSession,
                   willBeginAt screenPoint: NSPoint,
                   forRowIndexes rowIndexes: IndexSet) {
        let writtenIDs = Set(rowIndexes.compactMap { $0 < currentRows.count ? currentRows[$0].item.id : nil })
        let extras = currentItems.filter { selectionModel.isSelected($0.id) && !writtenIDs.contains($0.id) }
        guard !extras.isEmpty else { return }
        session.draggingPasteboard.writeObjects(
            extras.map { $0.url as NSURL }
        )
    }

    func tableView(_ tableView: NSTableView,
                   draggingSession session: NSDraggingSession,
                   endedAt screenPoint: NSPoint,
                   operation: NSDragOperation) {
        SpringLoadManager.shared.cancel()
    }

    // MARK: - Drop target & Spring-Loading

    func tableView(_ tableView: NSTableView,
                   validateDrop info: NSDraggingInfo,
                   proposedRow row: Int,
                   proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
        let pasteboard = info.draggingPasteboard
        let hasURLs = pasteboard.canReadObject(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        )
        let hasPromises = pasteboard.canReadObject(
            forClasses: [NSFilePromiseReceiver.self],
            options: nil
        )
        guard hasURLs || hasPromises else {
            SpringLoadManager.shared.cancel()
            return []
        }

        let target: URL
        if dropOperation == .on, row >= 0, row < currentRows.count, currentRows[row].item.isDirectory {
            let folderItem = currentRows[row].item
            target = folderItem.url

            // Spring-load: hovering over a folder row for 0.7s expands it inline
            SpringLoadManager.shared.hover(on: folderItem.url) { [weak self] url in
                guard let self else { return }
                if !self.expandedURLs.contains(url) {
                    self.toggleExpansion(for: folderItem)
                }
            }
        } else {
            SpringLoadManager.shared.cancel()
            target = directoryContents.url
        }
        guard FileManager.default.isWritableFile(atPath: target.path) else { return [] }

        if dropOperation == .on, row >= 0, row < currentRows.count, !currentRows[row].item.isDirectory {
            tableView.setDropRow(-1, dropOperation: .on)
        }

        return NSApp.currentEvent?.modifierFlags.contains(.command) == true ? .move : .copy
    }

    func tableView(_ tableView: NSTableView,
                   acceptDrop info: NSDraggingInfo,
                   row: Int,
                   dropOperation: NSTableView.DropOperation) -> Bool {
        SpringLoadManager.shared.cancel()

        let target: URL
        if dropOperation == .on, row >= 0, row < currentRows.count, currentRows[row].item.isDirectory {
            target = currentRows[row].item.url
        } else {
            target = directoryContents.url
        }

        let pasteboard = info.draggingPasteboard
        var handled = false

        if let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL], !urls.isEmpty {
            let move = NSApp.currentEvent?.modifierFlags.contains(.command) == true
            importFiles(urls, to: target, move: move)
            handled = true
        }

        if let receivers = pasteboard.readObjects(
            forClasses: [NSFilePromiseReceiver.self],
            options: nil
        ) as? [NSFilePromiseReceiver], !receivers.isEmpty {
            receivePromises(receivers, to: target)
            handled = true
        }

        return handled
    }

    private func importFiles(_ urls: [URL], to target: URL, move: Bool) {
        Task {
            let progress = Progress()
            if move {
                _ = await FileOperationService.shared.moveItems(urls, to: target, progress: progress)
            } else {
                _ = await FileOperationService.shared.copyItems(urls, to: target, progress: progress)
            }
            await MainActor.run { [weak self] in
                self?.directoryContents.reload()
            }
        }
    }

    private func receivePromises(_ receivers: [NSFilePromiseReceiver], to target: URL) {
        let queue = OperationQueue()
        queue.qualityOfService = .userInitiated
        for receiver in receivers {
            receiver.receivePromisedFiles(
                atDestination: target,
                options: [:],
                operationQueue: queue
            ) { [weak self] _, error in
                if let error {
                    NSLog("Nautica: promised file receive failed: %@", error.localizedDescription)
                }
                DispatchQueue.main.async {
                    self?.directoryContents.reload()
                }
            }
        }
    }
}

// MARK: - NSTableViewDelegate

extension ListViewController: NSTableViewDelegate {
    func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool {
        row < currentRows.count && currentRows[row].isGroupHeader
    }

    func tableView(_ tableView: NSTableView,
                   viewFor tableColumn: NSTableColumn?,
                   row: Int) -> NSView? {
        guard row < currentRows.count else { return nil }
        let rowData = currentRows[row]

        if rowData.isGroupHeader {
            let identifier = NSUserInterfaceItemIdentifier("GroupHeaderCell")
            let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView
                ?? {
                    let c = NSTableCellView()
                    c.identifier = identifier
                    let tf = NSTextField(labelWithString: "")
                    tf.font = NSFont.boldSystemFont(ofSize: 11)
                    tf.textColor = .secondaryLabelColor
                    tf.translatesAutoresizingMaskIntoConstraints = false
                    c.addSubview(tf)
                    c.textField = tf
                    NSLayoutConstraint.activate([
                        tf.leadingAnchor.constraint(equalTo: c.leadingAnchor, constant: 4),
                        tf.centerYAnchor.constraint(equalTo: c.centerYAnchor),
                        tf.trailingAnchor.constraint(lessThanOrEqualTo: c.trailingAnchor, constant: -4)
                    ])
                    return c
                }()
            cell.textField?.stringValue = "\(rowData.groupTitle) (\(rowData.groupCount))"
            return cell
        }

        guard let tableColumn,
              let column = ListColumn(rawValue: tableColumn.identifier.rawValue) else { return nil }
        let item = rowData.item
        let identifier = tableColumn.identifier
        let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? ListViewCell
            ?? ListViewCell(identifier: identifier)

        cell.configure(
            with: item,
            forColumn: column,
            depth: rowData.depth,
            isExpanded: rowData.isExpanded,
            tags: tagsProvider(item),
            fontSize: fontSize,
            iconSize: iconSize,
            onToggleExpand: { [weak self] in
                self?.toggleExpansion(for: item)
            }
        )

        if column == .name {
            iconCache.icon(for: item.url, size: iconSize) { [weak cell] image in
                guard let cell, cell.fileItem?.id == item.id else { return }
                cell.imageView?.image = image
            }
        }
        return cell
    }

    func tableView(_ tableView: NSTableView,
                   selectionIndexesForProposedSelection proposedSelectionIndexes: IndexSet)
        -> IndexSet {
        guard let event = NSApp.currentEvent,
              event.type == .leftMouseDown || event.type == .leftMouseUp else {
            return proposedSelectionIndexes
        }
        let row = tableView.clickedRow
        if row >= 0, row < currentRows.count, currentRows[row].isGroupHeader {
            return tableView.selectedRowIndexes
        }
        guard row >= 0, row < currentItems.count else {
            selectionModel.deselectAll()
            return IndexSet()
        }
        selectionModel.handleClick(currentItems[row].id, modifierFlags: event.modifierFlags, in: currentItems)
        return selectedRowIndexes()
    }

    func tableView(_ tableView: NSTableView,
                   sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        guard let descriptor = tableView.sortDescriptors.first,
              let key = descriptor.key,
              let sortKey = SortKey(rawValue: key) else { return }
        directoryContents.sort(by: sortKey, ascending: descriptor.ascending)
    }
}
