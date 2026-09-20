import AppKit
import Observation
import UniformTypeIdentifiers

/// Section identifier for the icon grid's diffable data source.
private enum IconViewSection {
    case main
}

/// NSCollectionView subclass that handles mouse selection, drag & drop initiation,
/// and forwards key events to the file-view coordinator.
private final class IconCollectionView: NSCollectionView {
    var onKeyDown: ((NSEvent) -> Bool)?
    var onMouseDown: ((NSEvent, IndexPath?) -> Void)?
    var onMouseUp: ((NSEvent, IndexPath?) -> Void)?
    var onDoubleClick: ((NSEvent, IndexPath) -> Void)?
    var onDragStart: ((IndexPath, NSEvent) -> Void)?
    var onMenuRequest: ((IndexPath?, NSPoint) -> NSMenu?)?

    private var initialMouseDownEvent: NSEvent?
    private var initialMouseDownPoint: NSPoint = .zero
    private var initialIndexPath: IndexPath?
    private var didDrag = false

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if onKeyDown?(event) != true {
            super.keyDown(with: event)
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        if event.modifierFlags.contains(.control) {
            super.mouseDown(with: event)
            return
        }

        initialMouseDownEvent = event
        let point = convert(event.locationInWindow, from: nil)
        initialMouseDownPoint = point
        initialIndexPath = indexPathForItem(at: point)
        didDrag = false

        if event.clickCount == 2, let indexPath = initialIndexPath {
            onDoubleClick?(event, indexPath)
            return
        }

        onMouseDown?(event, initialIndexPath)
    }

    override func mouseDragged(with event: NSEvent) {
        guard !didDrag else { return }
        let point = convert(event.locationInWindow, from: nil)
        let dx = point.x - initialMouseDownPoint.x
        let dy = point.y - initialMouseDownPoint.y
        if hypot(dx, dy) >= 3 {
            if let indexPath = initialIndexPath, let startEvent = initialMouseDownEvent {
                didDrag = true
                onDragStart?(indexPath, startEvent)
                return
            }
        }
    }

    override func mouseUp(with event: NSEvent) {
        if didDrag {
            didDrag = false
            return
        }
        onMouseUp?(event, initialIndexPath)
        initialMouseDownEvent = nil
        initialIndexPath = nil
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        let indexPath = indexPathForItem(at: point)
        return onMenuRequest?(indexPath, point)
    }
}

/// Lazily loads and resizes file icons off the main thread, cached by URL.
/// Directories with many items are prefetched in small batches.
final class IconCache {
    /// Items per prefetch batch (spec: batches of 50 for large directories).
    static let batchSize = 50

    private let cache: NSCache<NSString, NSImage> = {
        let c = NSCache<NSString, NSImage>()
        c.countLimit = 1500
        return c
    }()

    let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "nautica.icon-loading"
        queue.qualityOfService = .userInitiated
        return queue
    }()

    func clear() {
        cache.removeAllObjects()
    }

    func cachedIcon(for url: URL, size: CGFloat) -> NSImage? {
        cache.object(forKey: "\(url.absoluteString)|\(size)" as NSString)
    }

    /// Loads the icon for `url`, invoking `completion` on the main thread.
    func icon(for url: URL, size: CGFloat, completion: @escaping (NSImage) -> Void) {
        if let cached = cachedIcon(for: url, size: size) {
            completion(cached)
            return
        }
        queue.addOperation { [weak self] in
            guard let image = self?.loadIcon(for: url, size: size) else { return }
            DispatchQueue.main.async { completion(image) }
        }
    }

    /// Preloads icons in batches of `batchSize` on the loading queue.
    func prefetch(urls: [URL], size: CGFloat) {
        let missing = urls.filter { cachedIcon(for: $0, size: size) == nil }
        for start in stride(from: 0, to: missing.count, by: Self.batchSize) {
            let batch = Array(missing[start..<min(start + Self.batchSize, missing.count)])
            queue.addOperation { [weak self] in
                for url in batch {
                    self?.loadIcon(for: url, size: size)
                }
            }
        }
    }

    /// Loads and resizes the workspace icon; caches the result. Thread-safe.
    @discardableResult
    private func loadIcon(for url: URL, size: CGFloat) -> NSImage? {
        let key = "\(url.absoluteString)|\(size)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let resized = Self.resized(NSWorkspace.shared.icon(forFile: url.path), to: size)
        cache.setObject(resized, forKey: key)
        return resized
    }

    private static func resized(_ image: NSImage, to size: CGFloat) -> NSImage {
        let targetSize = NSSize(width: size, height: size)
        let result = NSImage(size: targetSize)
        result.lockFocus()
        image.draw(
            in: NSRect(origin: .zero, size: targetSize),
            from: NSRect(origin: .zero, size: image.size),
            operation: .sourceOver,
            fraction: 1
        )
        result.unlockFocus()
        return result
    }
}

/// View controller hosting the icon grid: an NSCollectionView driven by a
/// diffable data source, with selection owned by the shared `SelectionModel`.
final class IconViewController: NSViewController {
    /// Minimum cell width; the flow layout fits as many columns as possible.
    static let minimumItemWidth: CGFloat = 100
    static let gridSpacing: CGFloat = 10

    let directoryContents: DirectoryContents
    let selectionModel: SelectionModel

    /// Icon size in points (32–256, default 64). Driven by the toolbar slider (Prompt 7).
    private(set) var iconSize: CGFloat = 64
    private var fontSize: CGFloat = 11
    private var itemSpacing: CGFloat = 10

    func applyAppearance(fontSize: CGFloat, iconSize: CGFloat, spacing: CGFloat) {
        guard self.fontSize != fontSize || self.iconSize != iconSize || itemSpacing != spacing else { return }
        self.fontSize = fontSize
        self.iconSize = iconSize
        itemSpacing = spacing
        iconCache.clear()
        updateLayout()
        guard let dataSource else { return }
        var snapshot = dataSource.snapshot()
        snapshot.reloadItems(snapshot.itemIdentifiers)
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    /// Double-click on a folder.
    var onNavigate: ((URL) -> Void)?
    /// Keyboard events from the collection view (FileViewCoordinator routes these).
    var keyDownHandler: ((NSEvent) -> Bool)?
    /// Context-menu actions routed to BrowserView (rename sheet, copy, trash).
    var onRenameRequest: (() -> Void)?
    var onCopySelection: (() -> Void)?
    var onTrashSelection: (() -> Void)?
    var onCompressWithPassword: (([URL]) -> Void)?
    var onFindDuplicates: ((URL) -> Void)?
    var onGitDiff: ((URL) -> Void)?
    var onGitCommit: (() -> Void)?
    var onUnlockVault: ((URL) -> Void)?
    var onLockVault: ((URL) -> Void)?
    var onCreateVault: (() -> Void)?
    var onCheckVaultHealth: ((URL) -> Void)?
    /// Reports the current column count for grid-aware arrow navigation.
    var onColumnCountChanged: ((Int) -> Void)?

    private let iconCache = IconCache()
    private let flowLayout = NSCollectionViewFlowLayout()
    private var collectionView: IconCollectionView!
    private var dataSource: NSCollectionViewDiffableDataSource<IconViewSection, FileItem>!

    private var currentItems: [FileItem] = []
    private var contextMenuItems: [FileItem] = []
    private var sharingServicePicker: NSSharingServicePicker?
    private(set) var currentColumnCount = 1
    private var selectionChangedOnMouseDown = false

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

        let collectionView = IconCollectionView()
        collectionView.collectionViewLayout = flowLayout
        collectionView.isSelectable = false
        collectionView.backgroundColors = [.clear]
        collectionView.delegate = self
        collectionView.onKeyDown = { [weak self] event in
            self?.keyDownHandler?(event) ?? false
        }
        collectionView.register(IconViewItem.self, forItemWithIdentifier: IconViewItem.identifier)
        collectionView.setDraggingSourceOperationMask([.copy, .move], forLocal: false)
        collectionView.setDraggingSourceOperationMask([.copy, .move], forLocal: true)
        collectionView.registerForDraggedTypes(
            [.fileURL] + NSFilePromiseReceiver.readableDraggedTypes
                .map { NSPasteboard.PasteboardType(rawValue: $0) }
        )

        scrollView.documentView = collectionView
        self.collectionView = collectionView
        view = scrollView

        updateLayout()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        dataSource = NSCollectionViewDiffableDataSource<IconViewSection, FileItem>(
            collectionView: collectionView
        ) { [weak self] collectionView, indexPath, fileItem in
            let item = collectionView.makeItem(
                withIdentifier: IconViewItem.identifier,
                for: indexPath
            )
            guard let self, let iconItem = item as? IconViewItem else { return item }
            iconItem.configure(with: fileItem, isSelected: self.selectionModel.isSelected(fileItem.id),
                               fontSize: self.fontSize, iconSize: self.iconSize)
            self.iconCache.icon(for: fileItem.url, size: self.iconSize) { [weak iconItem] image in
                guard let iconItem, iconItem.fileItem?.id == fileItem.id else { return }
                iconItem.iconView.image = image
            }
            return iconItem
        }

        collectionView.onMouseDown = { [weak self] event, indexPath in
            self?.handleMouseDown(at: indexPath, event: event)
        }
        collectionView.onMouseUp = { [weak self] event, indexPath in
            self?.handleMouseUp(at: indexPath, event: event)
        }
        collectionView.onDoubleClick = { [weak self] event, indexPath in
            guard let self, let item = self.dataSource.itemIdentifier(for: indexPath) else { return }
            self.open(item)
        }
        collectionView.onDragStart = { [weak self] indexPath, startEvent in
            self?.handleDragStart(from: indexPath, startEvent: startEvent)
        }
        collectionView.onMenuRequest = { [weak self] indexPath, point in
            guard let self else { return nil }
            if let indexPath, let item = self.dataSource.itemIdentifier(for: indexPath) {
                if !self.selectionModel.isSelected(item.id) {
                    self.selectionModel.select(item.id, modifierFlags: [])
                    self.applySelectionToVisibleItems()
                }
                self.contextMenuItems = self.selectedItems()
                return FileContextMenu.makeMenu(for: self.contextMenuItems, actions: self.contextMenuActions())
            } else {
                self.contextMenuItems = []
                return FileContextMenu.makeMenu(for: [], actions: self.contextMenuActions())
            }
        }

        applyItems(directoryContents.items)
        startObserving()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        let insets = flowLayout.sectionInset
        let available = collectionView.bounds.width - insets.left - insets.right
        let pitch = flowLayout.itemSize.width + flowLayout.minimumInteritemSpacing
        let count = max(1, Int((available + flowLayout.minimumInteritemSpacing) / pitch))
        if count != currentColumnCount {
            currentColumnCount = count
            onColumnCountChanged?(count)
        }
    }

    private func updateLayout() {
        let width = max(Self.minimumItemWidth * fontSize / 11, iconSize + 24)
        flowLayout.itemSize = NSSize(width: width, height: iconSize + ceil(fontSize * 2.6) + 18)
        flowLayout.minimumInteritemSpacing = itemSpacing
        flowLayout.minimumLineSpacing = itemSpacing
        flowLayout.sectionInset = NSEdgeInsets(
            top: Self.gridSpacing, left: Self.gridSpacing,
            bottom: Self.gridSpacing, right: Self.gridSpacing
        )
        flowLayout.invalidateLayout()
    }

    // MARK: - Items & selection

    /// Re-applies the diffable snapshot. Large directories prefetch icons in batches.
    func applyItems(_ items: [FileItem]) {
        guard isViewLoaded, dataSource != nil else { return }
        let displayedItems: [FileItem]
        if directoryContents.groupBy != .none {
            displayedItems = directoryContents.groupedSections().flatMap(\.items)
        } else {
            displayedItems = items
        }
        currentItems = displayedItems
        var snapshot = NSDiffableDataSourceSnapshot<IconViewSection, FileItem>()
        snapshot.appendSections([.main])
        snapshot.appendItems(displayedItems, toSection: .main)
        dataSource.apply(snapshot, animatingDifferences: false)
        applySelectionToVisibleItems()
        if displayedItems.count > 1000 {
            iconCache.prefetch(urls: displayedItems.map(\.url), size: iconSize)
        }
    }

    /// Re-establishes one-shot observation of the models after every change.
    private func startObserving() {
        withObservationTracking {
            _ = directoryContents.items
            _ = directoryContents.groupBy
            _ = selectionModel.selectedIDs
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.applyItems(self.directoryContents.items)
                self.applySelectionToVisibleItems()
                self.startObserving()
            }
        }
    }

    /// The SelectionModel is the source of truth; mirror it onto visible cells.
    private func applySelectionToVisibleItems() {
        for case let item as IconViewItem in collectionView.visibleItems() {
            guard let fileItem = item.fileItem else { continue }
            item.isSelected = selectionModel.isSelected(fileItem.id)
        }
    }

    private func selectedItems() -> [FileItem] {
        currentItems.filter { selectionModel.isSelected($0.id) }
    }

    // MARK: - Mouse handling

    private func handleMouseDown(at indexPath: IndexPath?, event: NSEvent) {
        selectionChangedOnMouseDown = false
        guard let indexPath, let item = dataSource.itemIdentifier(for: indexPath) else {
            // Clicked background: deselect all
            selectionModel.deselectAll()
            applySelectionToVisibleItems()
            return
        }

        let flags = event.modifierFlags
        if flags.contains(.shift) {
            selectionModel.handleClick(item.id, modifierFlags: flags, in: currentItems)
            applySelectionToVisibleItems()
            selectionChangedOnMouseDown = true
        } else if flags.contains(.command) {
            if !selectionModel.isSelected(item.id) {
                selectionModel.handleClick(item.id, modifierFlags: flags, in: currentItems)
                applySelectionToVisibleItems()
                selectionChangedOnMouseDown = true
            }
        } else {
            if !selectionModel.isSelected(item.id) {
                selectionModel.select(item.id, modifierFlags: [])
                applySelectionToVisibleItems()
                selectionChangedOnMouseDown = true
            }
        }
    }

    private func handleMouseUp(at indexPath: IndexPath?, event: NSEvent) {
        guard let indexPath, let item = dataSource.itemIdentifier(for: indexPath) else { return }
        guard !selectionChangedOnMouseDown else { return }

        let flags = event.modifierFlags
        if flags.contains(.command) {
            selectionModel.handleClick(item.id, modifierFlags: flags, in: currentItems)
            applySelectionToVisibleItems()
        } else if !flags.contains(.shift) {
            if selectionModel.selectedIDs.count > 1 {
                selectionModel.select(item.id, modifierFlags: [])
                applySelectionToVisibleItems()
            }
        }
    }

    private func handleDragStart(from indexPath: IndexPath, startEvent: NSEvent) {
        guard let draggedItem = dataSource.itemIdentifier(for: indexPath) else { return }

        // Ensure dragged item is selected
        if !selectionModel.isSelected(draggedItem.id) {
            selectionModel.select(draggedItem.id, modifierFlags: [])
            applySelectionToVisibleItems()
        }

        var itemsToDrag = selectedItems()
        if !itemsToDrag.contains(where: { $0.id == draggedItem.id }) {
            itemsToDrag.append(draggedItem)
        }

        guard !itemsToDrag.isEmpty else { return }

        var draggingItems: [NSDraggingItem] = []
        for item in itemsToDrag {
            let draggingItem = NSDraggingItem(pasteboardWriter: item.url as NSURL)
            if let idx = dataSource.indexPath(for: item),
               let cell = collectionView.item(at: idx) as? IconViewItem,
               let iconImage = cell.iconView.image {
                let frameInCollection = cell.view.convert(cell.iconView.frame, to: collectionView)
                draggingItem.setDraggingFrame(frameInCollection, contents: iconImage)
            } else {
                let icon = iconCache.cachedIcon(for: item.url, size: iconSize)
                    ?? NSWorkspace.shared.icon(forFile: item.url.path)
                icon.size = NSSize(width: iconSize, height: iconSize)
                let startPoint = collectionView.convert(startEvent.locationInWindow, from: nil)
                draggingItem.setDraggingFrame(
                    NSRect(x: startPoint.x - iconSize / 2, y: startPoint.y - iconSize / 2, width: iconSize, height: iconSize),
                    contents: icon
                )
            }
            draggingItems.append(draggingItem)
        }

        collectionView.beginDraggingSession(with: draggingItems, event: startEvent, source: self)
    }

    private func open(_ item: FileItem) {
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

    /// Menu actions for the current right-click selection, shared with the
    /// list view via `FileContextMenu`.
    private func contextMenuActions() -> FileContextMenu.Actions {
        let isGit = GitService.shared.isGitRepository(at: directoryContents.url)
        return FileContextMenu.Actions(
            open: { [weak self] in self?.openSelection() },
            openWith: { [weak self] appURL in self?.openSelection(with: appURL) },
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
            share: { [weak self] in self?.shareSelection() },
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
                            self.applySelectionToVisibleItems()
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
            }
        )
    }

    private func openSelection() {
        for item in contextMenuItems {
            if VaultService.shared.isVault(at: item.url) {
                let status = VaultService.shared.isVaultMounted(at: item.url)
                if status.isMounted, let mount = status.mountURL {
                    onNavigate?(mount)
                } else {
                    onUnlockVault?(item.url)
                }
            } else if item.isDirectory {
                onNavigate?(item.url)
            } else {
                NSWorkspace.shared.open(item.url)
            }
        }
    }

    private func openSelection(with appURL: URL) {
        NSWorkspace.shared.open(
            contextMenuItems.map(\.url),
            withApplicationAt: appURL,
            configuration: NSWorkspace.OpenConfiguration()
        )
    }

    private func shareSelection() {
        let urls = contextMenuItems.map(\.url)
        guard !urls.isEmpty else { return }
        let picker = NSSharingServicePicker(items: urls)
        sharingServicePicker = picker // retained until the picker is dismissed
        if let fileItem = contextMenuItems.first,
           let indexPath = dataSource.indexPath(for: fileItem),
           let itemView = collectionView.item(at: indexPath)?.view {
            picker.show(relativeTo: itemView.bounds, of: itemView, preferredEdge: .minY)
        } else {
            picker.show(relativeTo: collectionView.bounds, of: collectionView, preferredEdge: .minY)
        }
    }
}

// MARK: - Drag & drop

extension IconViewController: NSCollectionViewDelegate {
    func collectionView(_ collectionView: NSCollectionView,
                        canDragItemsAt indexPaths: Set<IndexPath>,
                        with event: NSEvent) -> Bool {
        true
    }

    func collectionView(_ collectionView: NSCollectionView,
                        pasteboardWriterForItemAt indexPath: IndexPath) -> NSPasteboardWriting? {
        guard let item = dataSource.itemIdentifier(for: indexPath) else { return nil }
        // Dragging an unselected item selects it exclusively (Finder behavior).
        if !selectionModel.isSelected(item.id) {
            selectionModel.select(item.id, modifierFlags: [])
        }
        return item.url as NSURL
    }

    func collectionView(_ collectionView: NSCollectionView,
                        draggingSession session: NSDraggingSession,
                        willBeginAt screenPoint: NSPoint,
                        forItemsAt indexPaths: Set<IndexPath>) {
        // Add the rest of the selection so multi-file drags carry every selected item.
        let writtenIDs = Set(indexPaths.compactMap { dataSource.itemIdentifier(for: $0)?.id })
        let extras = selectedItems().filter { !writtenIDs.contains($0.id) }
        guard !extras.isEmpty else { return }
        session.draggingPasteboard.writeObjects(
            extras.map { $0.url as NSURL }
        )
    }

    func collectionView(_ collectionView: NSCollectionView,
                        validateDrop draggingInfo: NSDraggingInfo,
                        proposedIndexPath proposedDropIndexPath: AutoreleasingUnsafeMutablePointer<NSIndexPath>,
                        dropOperation proposedDropOperation: UnsafeMutablePointer<NSCollectionView.DropOperation>)
        -> NSDragOperation {
        let pasteboard = draggingInfo.draggingPasteboard
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

        let destination = dropTarget(
            for: proposedDropIndexPath.pointee as IndexPath,
            dropOperation: proposedDropOperation.pointee
        )
        guard FileManager.default.isWritableFile(atPath: destination.path) else { return [] }

        // Highlight folders as drop targets; anything else targets the current directory.
        if proposedDropOperation.pointee == .on,
           let item = dataSource.itemIdentifier(for: proposedDropIndexPath.pointee as IndexPath) {
            if item.isDirectory {
                SpringLoadManager.shared.hover(on: item.url) { [weak self] url in
                    self?.onNavigate?(url)
                }
            } else {
                SpringLoadManager.shared.cancel()
                proposedDropOperation.pointee = .before
            }
        } else {
            SpringLoadManager.shared.cancel()
        }
        // Copy by default; Command held during the drop moves instead.
        return NSApp.currentEvent?.modifierFlags.contains(.command) == true ? .move : .copy
    }

    func collectionView(_ collectionView: NSCollectionView,
                        acceptDrop draggingInfo: NSDraggingInfo,
                        indexPath: IndexPath,
                        dropOperation: NSCollectionView.DropOperation) -> Bool {
        SpringLoadManager.shared.cancel()
        let target = dropTarget(for: indexPath, dropOperation: dropOperation)
        let pasteboard = draggingInfo.draggingPasteboard
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

    /// Folder items receive drops directly; everything else lands in the current directory.
    private func dropTarget(for indexPath: IndexPath,
                            dropOperation: NSCollectionView.DropOperation) -> URL {
        if dropOperation == .on,
           let item = dataSource.itemIdentifier(for: indexPath),
           item.isDirectory {
            return item.url
        }
        return directoryContents.url
    }

    /// Copies (or moves with Command) dropped files using NSFileCoordinator.
    /// The full FileOperationService with progress/undo arrives in Prompt 10.
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

    /// Receives promised files (e.g. drags from another Nautica window).
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

// MARK: - NSDraggingSource

extension IconViewController: NSDraggingSource {
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        [.copy, .move]
    }
}
