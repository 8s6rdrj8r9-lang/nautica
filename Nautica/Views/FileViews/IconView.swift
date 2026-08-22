import AppKit
import Observation
import UniformTypeIdentifiers

/// Section identifier for the icon grid's diffable data source.
private enum IconViewSection {
    case main
}

/// NSCollectionView subclass that forwards key events to the file-view
/// coordinator (arrow navigation, Cmd+A, Esc, type-ahead, Space/Quick Look).
private final class IconCollectionView: NSCollectionView {
    var onKeyDown: ((NSEvent) -> Bool)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if onKeyDown?(event) != true {
            super.keyDown(with: event)
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }
}

/// Lazily loads and resizes file icons off the main thread, cached by URL.
/// Directories with many items are prefetched in small batches.
final class IconCache {
    /// Items per prefetch batch (spec: batches of 50 for large directories).
    static let batchSize = 50

    private let cache = NSCache<NSURL, NSImage>()

    let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "nautica.icon-loading"
        queue.qualityOfService = .userInitiated
        return queue
    }()

    func clear() {
        cache.removeAllObjects()
    }

    func cachedIcon(for url: URL) -> NSImage? {
        cache.object(forKey: url as NSURL)
    }

    /// Loads the icon for `url`, invoking `completion` on the main thread.
    func icon(for url: URL, size: CGFloat, completion: @escaping (NSImage) -> Void) {
        if let cached = cachedIcon(for: url) {
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
        let missing = urls.filter { cachedIcon(for: $0) == nil }
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
        let key = url as NSURL
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

/// NSFilePromiseProvider that retains its own delegate (the provider's
/// delegate property semantics are left unspecified, so we keep it strongly).
private final class FilePromiseProvider: NSFilePromiseProvider {
    private final class Delegate: NSObject, NSFilePromiseProviderDelegate {
        let sourceURL: URL
        let queue = OperationQueue()

        init(sourceURL: URL) {
            self.sourceURL = sourceURL
        }

        func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider,
                                 fileNameForType fileType: String) -> String {
            sourceURL.lastPathComponent
        }

        func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider,
                                 writePromiseTo url: URL,
                                 completionHandler: @escaping (Error?) -> Void) {
            var coordinationError: NSError?
            var copyError: Error?
            NSFileCoordinator().coordinate(
                readingItemAt: sourceURL,
                options: [],
                writingItemAt: url,
                options: .forReplacing,
                error: &coordinationError
            ) { readingURL, writingURL in
                do {
                    try FileManager.default.copyItem(at: readingURL, to: writingURL)
                } catch {
                    copyError = error
                }
            }
            completionHandler(copyError ?? coordinationError)
        }

        func operationQueue(for filePromiseProvider: NSFilePromiseProvider) -> OperationQueue {
            queue
        }
    }

    private let promiseDelegate: Delegate

    init(sourceURL: URL) {
        promiseDelegate = Delegate(sourceURL: sourceURL)
        super.init(fileType: UTType.fileURL.identifier, delegate: promiseDelegate)
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
    var iconSize: CGFloat = 64 {
        didSet {
            let clamped = min(256, max(32, iconSize))
            guard clamped != oldValue else { return }
            iconSize = clamped
            iconCache.clear()
            updateLayout()
            applyItems(currentItems)
        }
    }

    /// Double-click on a folder.
    var onNavigate: ((URL) -> Void)?
    /// Keyboard events from the collection view (FileViewCoordinator routes these).
    var keyDownHandler: ((NSEvent) -> Bool)?
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
            iconItem.configure(with: fileItem, isSelected: self.selectionModel.isSelected(fileItem.id))
            self.iconCache.icon(for: fileItem.url, size: self.iconSize) { [weak iconItem] image in
                guard let iconItem, iconItem.fileItem?.id == fileItem.id else { return }
                iconItem.iconView.image = image
            }
            return iconItem
        }

        let click = NSClickGestureRecognizer(target: self, action: #selector(handleClick(_:)))
        let doubleClick = NSClickGestureRecognizer(target: self, action: #selector(handleDoubleClick(_:)))
        doubleClick.numberOfClicksRequired = 2
        let rightClick = NSClickGestureRecognizer(target: self, action: #selector(handleRightClick(_:)))
        rightClick.buttonMask = 0x2
        collectionView.addGestureRecognizer(click)
        collectionView.addGestureRecognizer(doubleClick)
        collectionView.addGestureRecognizer(rightClick)

        applyItems(directoryContents.items)
        startObserving()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        let insets = flowLayout.sectionInset
        let available = collectionView.bounds.width - insets.left - insets.right
        let pitch = flowLayout.itemSize.width + flowLayout.minimumInteritemSpacing
        let count = max(1, Int(available / pitch))
        if count != currentColumnCount {
            currentColumnCount = count
            onColumnCountChanged?(count)
        }
    }

    private func updateLayout() {
        let width = max(Self.minimumItemWidth, iconSize + 24)
        flowLayout.itemSize = NSSize(width: width, height: iconSize + 48)
        flowLayout.minimumInteritemSpacing = Self.gridSpacing
        flowLayout.minimumLineSpacing = Self.gridSpacing
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
        currentItems = items
        var snapshot = NSDiffableDataSourceSnapshot<IconViewSection, FileItem>()
        snapshot.appendSections([.main])
        snapshot.appendItems(items, toSection: .main)
        dataSource.apply(snapshot, animatingDifferences: false)
        applySelectionToVisibleItems()
        if items.count > 1000 {
            iconCache.prefetch(urls: items.map(\.url), size: iconSize)
        }
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

    @objc private func handleClick(_ recognizer: NSClickGestureRecognizer) {
        collectionView.window?.makeFirstResponder(collectionView)
        let point = recognizer.location(in: collectionView)
        guard let indexPath = collectionView.indexPathForItem(at: point),
              let item = dataSource.itemIdentifier(for: indexPath) else {
            // Click on empty area: deselect all.
            selectionModel.deselectAll()
            return
        }
        let flags = NSApp.currentEvent?.modifierFlags ?? []
        selectionModel.handleClick(item.id, modifierFlags: flags, in: currentItems)
    }

    @objc private func handleDoubleClick(_ recognizer: NSClickGestureRecognizer) {
        let point = recognizer.location(in: collectionView)
        guard let indexPath = collectionView.indexPathForItem(at: point),
              let item = dataSource.itemIdentifier(for: indexPath) else { return }
        open(item)
    }

    private func open(_ item: FileItem) {
        if item.isDirectory {
            onNavigate?(item.url)
        } else {
            NSWorkspace.shared.open(item.url)
        }
    }

    // MARK: - Context menu

    @objc private func handleRightClick(_ recognizer: NSClickGestureRecognizer) {
        let point = recognizer.location(in: collectionView)
        guard let event = NSApp.currentEvent,
              let indexPath = collectionView.indexPathForItem(at: point),
              let item = dataSource.itemIdentifier(for: indexPath) else { return }
        if !selectionModel.isSelected(item.id) {
            selectionModel.select(item.id, modifierFlags: [])
        }
        contextMenuItems = selectedItems()

        let menu = NSMenu()
        menu.addItem(makeMenuItem(title: "Open", action: #selector(openSelection(_:))))
        menu.addItem(makeOpenWithMenuItem(for: item))
        menu.addItem(.separator())
        menu.addItem(makeMenuItem(title: "Get Info", action: #selector(showInfo(_:))))
        menu.addItem(makeMenuItem(title: "Rename", action: #selector(renameSelection(_:))))
        menu.addItem(makeMenuItem(title: "Move to Trash", action: #selector(moveSelectionToTrash(_:))))
        let tagsItem = makeMenuItem(title: "Tags", action: nil)
        tagsItem.isEnabled = false // TagService integration arrives with F-013.
        menu.addItem(tagsItem)
        menu.addItem(.separator())
        menu.addItem(makeMenuItem(title: "Share…", action: #selector(shareSelection(_:))))

        let location = collectionView.convert(event.locationInWindow, from: nil)
        menu.popUp(positioning: nil, at: location, in: collectionView)
    }

    private func makeMenuItem(title: String, action: Selector?) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    private func makeOpenWithMenuItem(for item: FileItem) -> NSMenuItem {
        let menuItem = NSMenuItem(title: "Open With", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        let applications = NSWorkspace.shared.urlsForApplications(toOpen: item.url)
        if applications.isEmpty {
            let empty = NSMenuItem(title: "No Applications Found", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            submenu.addItem(empty)
        } else {
            for appURL in applications {
                let appItem = NSMenuItem(
                    title: FileManager.default.displayName(atPath: appURL.path),
                    action: #selector(openWithApplication(_:)),
                    keyEquivalent: ""
                )
                appItem.target = self
                appItem.representedObject = appURL
                let icon = NSWorkspace.shared.icon(forFile: appURL.path)
                icon.size = NSSize(width: 16, height: 16)
                appItem.image = icon
                submenu.addItem(appItem)
            }
        }
        menuItem.submenu = submenu
        return menuItem
    }

    @objc private func openSelection(_ sender: NSMenuItem) {
        for item in contextMenuItems where !item.isDirectory {
            NSWorkspace.shared.open(item.url)
        }
        if let folder = contextMenuItems.first(where: \.isDirectory) {
            onNavigate?(folder.url)
        }
    }

    @objc private func openWithApplication(_ sender: NSMenuItem) {
        guard let appURL = sender.representedObject as? URL else { return }
        NSWorkspace.shared.open(
            contextMenuItems.map(\.url),
            withApplicationAt: appURL,
            configuration: NSWorkspace.OpenConfiguration()
        )
    }

    @objc private func showInfo(_ sender: NSMenuItem) {
        guard let item = contextMenuItems.first else { return }
        // Interim panel; a full inspector window is a later refinement.
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

    @objc private func renameSelection(_ sender: NSMenuItem) {
        // Inline rename arrives with the file-operation service in Prompt 10.
        NSLog("Nautica: Rename requested for %@ (not yet implemented)",
              contextMenuItems.map(\.name).joined(separator: ", "))
    }

    @objc private func moveSelectionToTrash(_ sender: NSMenuItem) {
        var failedNames: [String] = []
        for item in contextMenuItems {
            do {
                try FileManager.default.trashItem(at: item.url, resultingItemURL: nil)
            } catch {
                failedNames.append(item.name)
            }
        }
        selectionModel.deselectAll()
        directoryContents.reload()
        if !failedNames.isEmpty {
            let alert = NSAlert()
            alert.messageText = "Some items could not be moved to the Trash."
            alert.informativeText = failedNames.joined(separator: "\n")
            alert.runModal()
        }
    }

    @objc private func shareSelection(_ sender: NSMenuItem) {
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
        return FilePromiseProvider(sourceURL: item.url)
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
            extras.map { FilePromiseProvider(sourceURL: $0.url) }
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
        guard hasURLs || hasPromises else { return [] }

        let destination = dropTarget(
            for: proposedDropIndexPath.pointee as IndexPath,
            dropOperation: proposedDropOperation.pointee
        )
        guard FileManager.default.isWritableFile(atPath: destination.path) else { return [] }

        // Highlight folders as drop targets; anything else targets the current directory.
        if proposedDropOperation.pointee == .on,
           let item = dataSource.itemIdentifier(for: proposedDropIndexPath.pointee as IndexPath),
           !item.isDirectory {
            proposedDropOperation.pointee = .before
        }
        // Copy by default; Command held during the drop moves instead.
        return NSApp.currentEvent?.modifierFlags.contains(.command) == true ? .move : .copy
    }

    func collectionView(_ collectionView: NSCollectionView,
                        acceptDrop draggingInfo: NSDraggingInfo,
                        indexPath: IndexPath,
                        dropOperation: NSCollectionView.DropOperation) -> Bool {
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
        DispatchQueue.global(qos: .userInitiated).async {
            for url in urls {
                let destination = target.appendingPathComponent(url.lastPathComponent)
                var coordinationError: NSError?
                NSFileCoordinator().coordinate(
                    readingItemAt: url,
                    options: [],
                    writingItemAt: destination,
                    options: .forReplacing,
                    error: &coordinationError
                ) { readingURL, writingURL in
                    do {
                        if move {
                            try FileManager.default.moveItem(at: readingURL, to: writingURL)
                        } else {
                            try FileManager.default.copyItem(at: readingURL, to: writingURL)
                        }
                    } catch {
                        NSLog("Nautica: drop import of %@ failed: %@",
                              url.path, error.localizedDescription)
                    }
                }
                if let coordinationError {
                    NSLog("Nautica: drop coordination failed for %@: %@",
                          url.path, coordinationError.localizedDescription)
                }
            }
            DispatchQueue.main.async { [weak self] in
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
