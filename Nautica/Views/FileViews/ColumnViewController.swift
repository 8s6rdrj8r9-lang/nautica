import AppKit
import Observation
import SwiftUI

/// View controller presenting files in a Miller Columns layout (Finder ⌘3 style).
/// Columns display subdirectories left-to-right with keyboard traversal (←/→/↑/↓)
/// and a rich file preview column when a leaf file is selected.
final class ColumnViewController: NSViewController {
    let directoryContents: DirectoryContents
    let selectionModel: SelectionModel

    var onNavigate: ((URL) -> Void)?
    var keyDownHandler: ((NSEvent) -> Bool)?
    var onRenameRequest: (() -> Void)?
    var onCopySelection: (() -> Void)?
    var onTrashSelection: (() -> Void)?
    var onQuickLook: (() -> Void)?
    var onCompressWithPassword: (([URL]) -> Void)?
    var onFindDuplicates: ((URL) -> Void)?
    var onGitDiff: ((URL) -> Void)?
    var onGitCommit: (() -> Void)?
    var onUnlockVault: ((URL) -> Void)?
    var onLockVault: ((URL) -> Void)?
    var onCreateVault: (() -> Void)?

    private let scrollView = NSScrollView()
    private let columnsStack = NSStackView()

    /// The list of URLs currently representing the expanded column hierarchy.
    /// columnURLs[0] is directoryContents.url; each subsequent URL is a subfolder selected in the previous column.
    private var columnURLs: [URL] = []
    private var columnTableViews: [NSTableView] = []
    private var columnData: [[FileItem]] = []
    private var activeColumnIndex: Int = 0
    private var selectedPreviewItem: FileItem?
    private var previewColumnView: NSView?

    init(directoryContents: DirectoryContents, selectionModel: SelectionModel) {
        self.directoryContents = directoryContents
        self.selectionModel = selectionModel
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func loadView() {
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false

        columnsStack.orientation = .horizontal
        columnsStack.alignment = .top
        columnsStack.spacing = 1
        columnsStack.distribution = .fillProportionally
        columnsStack.translatesAutoresizingMaskIntoConstraints = false

        let clipView = NSClipView()
        clipView.documentView = columnsStack
        clipView.drawsBackground = false
        scrollView.contentView = clipView

        view = scrollView

        NSLayoutConstraint.activate([
            columnsStack.topAnchor.constraint(equalTo: clipView.topAnchor),
            columnsStack.leadingAnchor.constraint(equalTo: clipView.leadingAnchor),
            columnsStack.bottomAnchor.constraint(equalTo: clipView.bottomAnchor),
            columnsStack.heightAnchor.constraint(equalTo: clipView.heightAnchor),
        ])
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        reloadHierarchy()
    }

    /// Re-anchors the column view at directoryContents.url
    func reloadHierarchy() {
        columnURLs = [directoryContents.url]
        selectedPreviewItem = nil
        activeColumnIndex = 0
        rebuildColumns()
    }

    private func rebuildColumns() {
        columnsStack.arrangedSubviews.forEach {
            columnsStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        columnTableViews.removeAll()
        columnData.removeAll()
        previewColumnView = nil

        for (index, url) in columnURLs.enumerated() {
            addColumn(for: url, columnIndex: index)
        }

        if let previewItem = selectedPreviewItem {
            addPreviewColumn(for: previewItem)
        }

        // Scroll to the right to keep the latest column in view
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let maxX = self.columnsStack.frame.maxX
            self.scrollView.contentView.scroll(to: NSPoint(x: max(0, maxX - self.scrollView.bounds.width), y: 0))
            self.scrollView.reflectScrolledClipView(self.scrollView.contentView)
        }
    }

    private func addColumn(for url: URL, columnIndex: Int) {
        let tableScrollView = NSScrollView()
        tableScrollView.hasVerticalScroller = true
        tableScrollView.autohidesScrollers = true
        tableScrollView.translatesAutoresizingMaskIntoConstraints = false

        let tableView = ColumnTableView()
        tableView.headerView = nil
        tableView.rowHeight = 24
        tableView.intercellSpacing = NSSize(width: 0, height: 2)
        tableView.backgroundColor = .controlBackgroundColor
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("ColumnCell"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)

        tableView.delegate = self
        tableView.dataSource = self
        tableView.target = self
        tableView.action = #selector(tableViewClicked(_:))
        tableView.doubleAction = #selector(tableViewDoubleClicked(_:))

        tableView.onKeyDown = { [weak self] event in
            self?.handleColumnKeyDown(event, from: columnIndex) ?? false
        }
        tableView.onMenu = { [weak self] event, row in
            self?.contextMenu(forColumn: columnIndex, row: row)
        }

        tableView.setDraggingSourceOperationMask([.copy, .move], forLocal: false)
        tableView.setDraggingSourceOperationMask([.copy, .move], forLocal: true)
        tableView.registerForDraggedTypes([.fileURL] + NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType(rawValue: $0) })

        tableScrollView.documentView = tableView
        columnsStack.addArrangedSubview(tableScrollView)

        NSLayoutConstraint.activate([
            tableScrollView.widthAnchor.constraint(equalToConstant: 220),
            tableScrollView.topAnchor.constraint(equalTo: columnsStack.topAnchor),
            tableScrollView.bottomAnchor.constraint(equalTo: columnsStack.bottomAnchor),
        ])

        columnTableViews.append(tableView)
        columnData.append([])

        // Load files for this column asynchronously
        Task {
            let items = (try? await FileSystemService.shared.contentsOfDirectory(
                at: url,
                includingHidden: directoryContents.showHiddenFiles
            )) ?? []
            let sorted = DirectoryContents.sort(
                items,
                by: directoryContents.sortKey,
                ascending: directoryContents.sortAscending
            )
            await MainActor.run { [weak self] in
                guard let self, columnIndex < self.columnData.count else { return }
                self.columnData[columnIndex] = sorted
                self.columnTableViews[columnIndex].reloadData()

                // If this is the active column or next column is pinned, select the row
                if columnIndex + 1 < self.columnURLs.count {
                    let nextURL = self.columnURLs[columnIndex + 1]
                    if let row = sorted.firstIndex(where: { $0.url == nextURL }) {
                        self.columnTableViews[columnIndex].selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                    }
                }
            }
        }
    }

    private func addPreviewColumn(for item: FileItem) {
        let previewContainer = NSView()
        previewContainer.translatesAutoresizingMaskIntoConstraints = false

        let host = NSHostingView(rootView: ColumnFilePreviewView(item: item, onQuickLook: { [weak self] in
            self?.onQuickLook?()
        }, onOpen: { [weak self] in
            if item.isDirectory {
                self?.onNavigate?(item.url)
            } else {
                NSWorkspace.shared.open(item.url)
            }
        }))
        host.translatesAutoresizingMaskIntoConstraints = false
        previewContainer.addSubview(host)
        NSLayoutConstraint.activate([
            host.topAnchor.constraint(equalTo: previewContainer.topAnchor),
            host.leadingAnchor.constraint(equalTo: previewContainer.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: previewContainer.trailingAnchor),
            host.bottomAnchor.constraint(equalTo: previewContainer.bottomAnchor),
        ])

        columnsStack.addArrangedSubview(previewContainer)
        NSLayoutConstraint.activate([
            previewContainer.widthAnchor.constraint(equalToConstant: 260),
            previewContainer.topAnchor.constraint(equalTo: columnsStack.topAnchor),
            previewContainer.bottomAnchor.constraint(equalTo: columnsStack.bottomAnchor),
        ])
        previewColumnView = previewContainer
    }

    // MARK: - Actions & Navigation

    @objc private func tableViewClicked(_ sender: NSTableView) {
        guard let columnIndex = columnTableViews.firstIndex(of: sender) else { return }
        activeColumnIndex = columnIndex
        let row = sender.selectedRow
        guard row >= 0, row < columnData[columnIndex].count else { return }
        let selectedItem = columnData[columnIndex][row]

        // Update shared selectionModel
        selectionModel.select(selectedItem.id, modifierFlags: [])

        if selectedItem.isDirectory {
            selectedPreviewItem = nil
            // Drill in: keep columns up to columnIndex, then append this folder
            columnURLs = Array(columnURLs.prefix(columnIndex + 1)) + [selectedItem.url]
            rebuildColumns()
        } else {
            // Leaf file selected: show preview column
            columnURLs = Array(columnURLs.prefix(columnIndex + 1))
            selectedPreviewItem = selectedItem
            rebuildColumns()
        }
    }

    @objc private func tableViewDoubleClicked(_ sender: NSTableView) {
        guard let columnIndex = columnTableViews.firstIndex(of: sender) else { return }
        let row = sender.selectedRow
        guard row >= 0, row < columnData[columnIndex].count else { return }
        let item = columnData[columnIndex][row]

        if item.isDirectory {
            onNavigate?(item.url)
        } else {
            NSWorkspace.shared.open(item.url)
        }
    }

    private func handleColumnKeyDown(_ event: NSEvent, from columnIndex: Int) -> Bool {
        let hasCommand = event.modifierFlags.contains(.command)

        if hasCommand {
            if let char = event.charactersIgnoringModifiers?.lowercased() {
                switch char {
                case "o":
                    openSelection(in: columnIndex)
                    return true
                default:
                    break
                }
            }
        }

        guard let scalars = event.charactersIgnoringModifiers?.unicodeScalars,
              scalars.count == 1, let scalar = scalars.first else {
            return keyDownHandler?(event) ?? false
        }

        switch scalar.value {
        case UInt32(NSRightArrowFunctionKey):
            // Drill into the next column if available
            if columnIndex + 1 < columnTableViews.count {
                let nextTable = columnTableViews[columnIndex + 1]
                view.window?.makeFirstResponder(nextTable)
                if nextTable.selectedRow < 0 && !columnData[columnIndex + 1].isEmpty {
                    nextTable.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
                }
                activeColumnIndex = columnIndex + 1
                return true
            }
        case UInt32(NSLeftArrowFunctionKey):
            // Move back to parent column
            if columnIndex > 0 {
                let prevTable = columnTableViews[columnIndex - 1]
                view.window?.makeFirstResponder(prevTable)
                activeColumnIndex = columnIndex - 1
                return true
            }
        case UInt32(NSDownArrowFunctionKey):
            if hasCommand {
                openSelection(in: columnIndex)
                return true
            }
        case 0x20: // Space: Quick Look
            onQuickLook?()
            return true
        case 0x0D, 0x03: // Return: Rename
            onRenameRequest?()
            return true
        default:
            break
        }

        return keyDownHandler?(event) ?? false
    }

    private func openSelection(in columnIndex: Int) {
        let tableView = columnTableViews[columnIndex]
        let row = tableView.selectedRow
        guard row >= 0, row < columnData[columnIndex].count else { return }
        let item = columnData[columnIndex][row]
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
                    await MainActor.run { self.rebuildColumns() }
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
}

// MARK: - NSTableViewDataSource & Delegate

extension ColumnViewController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        guard let index = columnTableViews.firstIndex(of: tableView), index < columnData.count else { return 0 }
        return columnData[index].count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let index = columnTableViews.firstIndex(of: tableView),
              index < columnData.count,
              row < columnData[index].count else { return nil }

        let item = columnData[index][row]
        let identifier = NSUserInterfaceItemIdentifier("ColumnRowCell")
        var cellView = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView

        if cellView == nil {
            let cell = NSTableCellView()
            cell.identifier = identifier

            let iconView = NSImageView()
            iconView.translatesAutoresizingMaskIntoConstraints = false
            iconView.imageScaling = .scaleProportionallyUpOrDown
            cell.addSubview(iconView)
            cell.imageView = iconView

            let textField = NSTextField(labelWithString: "")
            textField.translatesAutoresizingMaskIntoConstraints = false
            textField.lineBreakMode = .byTruncatingTail
            textField.font = NSFont.systemFont(ofSize: 12)
            cell.addSubview(textField)
            cell.textField = textField

            let dotsView = NSImageView()
            dotsView.translatesAutoresizingMaskIntoConstraints = false
            dotsView.imageScaling = .scaleProportionallyUpOrDown
            dotsView.tag = 998
            cell.addSubview(dotsView)

            let cloudView = NSImageView()
            cloudView.translatesAutoresizingMaskIntoConstraints = false
            cloudView.imageScaling = .scaleProportionallyUpOrDown
            cloudView.tag = 997
            cell.addSubview(cloudView)

            let gitBadge = NSTextField(labelWithString: "")
            gitBadge.translatesAutoresizingMaskIntoConstraints = false
            gitBadge.font = NSFont.systemFont(ofSize: 10, weight: .bold)
            gitBadge.alignment = .center
            gitBadge.tag = 996
            cell.addSubview(gitBadge)

            let chevron = NSImageView()
            chevron.translatesAutoresizingMaskIntoConstraints = false
            chevron.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)
            chevron.contentTintColor = .tertiaryLabelColor
            chevron.tag = 999 // marker tag
            cell.addSubview(chevron)

            NSLayoutConstraint.activate([
                iconView.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                iconView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                iconView.widthAnchor.constraint(equalToConstant: 16),
                iconView.heightAnchor.constraint(equalToConstant: 16),

                chevron.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
                chevron.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                chevron.widthAnchor.constraint(equalToConstant: 8),
                chevron.heightAnchor.constraint(equalToConstant: 10),

                dotsView.trailingAnchor.constraint(equalTo: chevron.leadingAnchor, constant: -4),
                dotsView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                dotsView.heightAnchor.constraint(equalToConstant: 8),

                cloudView.trailingAnchor.constraint(equalTo: dotsView.leadingAnchor, constant: -3),
                cloudView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                cloudView.widthAnchor.constraint(equalToConstant: 12),
                cloudView.heightAnchor.constraint(equalToConstant: 12),

                gitBadge.trailingAnchor.constraint(equalTo: cloudView.leadingAnchor, constant: -3),
                gitBadge.centerYAnchor.constraint(equalTo: cell.centerYAnchor),

                textField.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 6),
                textField.trailingAnchor.constraint(equalTo: gitBadge.leadingAnchor, constant: -3),
                textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
            cellView = cell
        }

        cellView?.textField?.stringValue = item.name
        cellView?.imageView?.image = NSWorkspace.shared.icon(forFile: item.url.path)
        let chevronView = cellView?.viewWithTag(999)
        chevronView?.isHidden = !item.isDirectory

        let dotsView = cellView?.viewWithTag(998) as? NSImageView
        if !item.tagColors.isEmpty {
            dotsView?.image = TagDotsHelper.image(for: item.tagColors, diameter: 8)
            dotsView?.isHidden = false
        } else {
            dotsView?.image = nil
            dotsView?.isHidden = true
        }

        let cloudView = cellView?.viewWithTag(997) as? NSImageView
        switch item.cloudStatus {
        case .onlineOnly:
            cloudView?.image = NSImage(systemSymbolName: "icloud.and.arrow.down", accessibilityDescription: "Stored in cloud")
            cloudView?.contentTintColor = .secondaryLabelColor
            cloudView?.isHidden = false
        case .downloading:
            cloudView?.image = NSImage(systemSymbolName: "arrow.down.circle", accessibilityDescription: "Downloading")
            cloudView?.contentTintColor = .systemBlue
            cloudView?.isHidden = false
        case .conflict:
            cloudView?.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: "Sync conflict")
            cloudView?.contentTintColor = .systemOrange
            cloudView?.isHidden = false
        case .downloaded, .notCloud:
            cloudView?.image = nil
            cloudView?.isHidden = true
        }

        let gitBadge = cellView?.viewWithTag(996) as? NSTextField
        if let gitStatus = item.gitStatus {
            gitBadge?.stringValue = gitStatus.rawValue
            gitBadge?.textColor = gitStatus.badgeColor
            gitBadge?.toolTip = "Git: \(gitStatus.displayName)"
            gitBadge?.isHidden = false
        } else {
            gitBadge?.stringValue = ""
            gitBadge?.isHidden = true
        }

        return cellView
    }

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        guard let index = columnTableViews.firstIndex(of: tableView),
              index < columnData.count,
              row < columnData[index].count else { return nil }
        return columnData[index][row].url as NSURL
    }

    func tableView(_ tableView: NSTableView,
                   validateDrop info: NSDraggingInfo,
                   proposedRow row: Int,
                   proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
        guard let colIndex = columnTableViews.firstIndex(of: tableView), colIndex < columnData.count else {
            SpringLoadManager.shared.cancel()
            return []
        }
        let pasteboard = info.draggingPasteboard
        let hasURLs = pasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
        let hasPromises = pasteboard.canReadObject(forClasses: [NSFilePromiseReceiver.self], options: nil)
        guard hasURLs || hasPromises else {
            SpringLoadManager.shared.cancel()
            return []
        }

        let items = columnData[colIndex]
        if dropOperation == .on, row >= 0, row < items.count, items[row].isDirectory {
            let folderItem = items[row]
            SpringLoadManager.shared.hover(on: folderItem.url) { [weak self] _ in
                guard let self, colIndex < self.columnTableViews.count else { return }
                self.columnTableViews[colIndex].selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                self.tableViewClicked(self.columnTableViews[colIndex])
            }
        } else {
            SpringLoadManager.shared.cancel()
        }
        return NSApp.currentEvent?.modifierFlags.contains(.command) == true ? .move : .copy
    }

    func tableView(_ tableView: NSTableView,
                   acceptDrop info: NSDraggingInfo,
                   row: Int,
                   dropOperation: NSTableView.DropOperation) -> Bool {
        SpringLoadManager.shared.cancel()
        guard let colIndex = columnTableViews.firstIndex(of: tableView), colIndex < columnURLs.count else { return false }
        let items = colIndex < columnData.count ? columnData[colIndex] : []
        let target: URL
        if dropOperation == .on, row >= 0, row < items.count, items[row].isDirectory {
            target = items[row].url
        } else {
            target = columnURLs[colIndex]
        }

        if let urls = info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            let move = NSApp.currentEvent?.modifierFlags.contains(.command) == true
            Task {
                let progress = Progress()
                if move {
                    _ = await FileOperationService.shared.moveItems(urls, to: target, progress: progress)
                } else {
                    _ = await FileOperationService.shared.copyItems(urls, to: target, progress: progress)
                }
                await MainActor.run { [weak self] in
                    self?.rebuildColumns()
                }
            }
            return true
        }
        return false
    }

    func tableView(_ tableView: NSTableView,
                   draggingSession session: NSDraggingSession,
                   endedAt screenPoint: NSPoint,
                   operation: NSDragOperation) {
        SpringLoadManager.shared.cancel()
    }

    private func contextMenu(forColumn columnIndex: Int, row: Int) -> NSMenu? {
        guard columnIndex < columnData.count, row < columnData[columnIndex].count else { return nil }
        let item = columnData[columnIndex][row]
        let items = [item]
        let targetFolder = item.isDirectory ? item.url : item.url.deletingLastPathComponent()
        let isGit = GitService.shared.isGitRepository(at: targetFolder)
        return FileContextMenu.makeMenu(
            for: items,
            actions: .init(
                open: { [weak self] in self?.openSelection(in: columnIndex) },
                openWith: { appURL in
                    NSWorkspace.shared.open([item.url], withApplicationAt: appURL, configuration: .init())
                },
                quickLook: { [weak self] in self?.onQuickLook?() },
                getInfo: { FileContextMenu.showInfo(for: item) },
                rename: { [weak self] in self?.onRenameRequest?() },
                copy: { [weak self] in self?.onCopySelection?() },
                trash: { [weak self] in self?.onTrashSelection?() },
                share: { [weak self] in
                    let picker = NSSharingServicePicker(items: [item.url])
                    if let view = self?.view {
                        picker.show(relativeTo: .zero, of: view, preferredEdge: .minY)
                    }
                },
                compress: {
                    let targetDir = item.url.deletingLastPathComponent()
                    let archiveName = "\(item.url.deletingPathExtension().lastPathComponent).zip"
                    let zipURL = targetDir.appendingPathComponent(archiveName)
                    Task.detached {
                        let process = Process()
                        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
                        process.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", item.url.path, zipURL.path]
                        try? process.run()
                        process.waitUntilExit()
                    }
                },
                extract: { [weak self] in
                    Task {
                        do {
                            _ = try await ArchiveService.shared.extract(archiveURL: item.url)
                            await MainActor.run { self?.rebuildColumns() }
                        } catch {
                            await MainActor.run { NSAlert(error: error).runModal() }
                        }
                    }
                },
                mountDiskImage: { [weak self] in
                    Task {
                        do {
                            let mount = try await ArchiveService.shared.attachDiskImage(at: item.url)
                            await MainActor.run { self?.onNavigate?(mount) }
                        } catch {
                            await MainActor.run { NSAlert(error: error).runModal() }
                        }
                    }
                },
                compressWithPassword: { [weak self] in
                    self?.onCompressWithPassword?([item.url])
                },
                createSymlink: {
                    let parentDir = item.url.deletingLastPathComponent()
                    let symlinkURL = parentDir.appendingPathComponent("\(item.name) symlink")
                    try? FileManager.default.createSymbolicLink(at: symlinkURL, withDestinationURL: item.url)
                },
                copyPath: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(item.url.path, forType: .string)
                },
                openInTerminal: {
                    let folderURL = item.isDirectory ? item.url : item.url.deletingLastPathComponent()
                    Task {
                        try? await TerminalService.shared.openTerminal(
                            at: folderURL,
                            emulator: TerminalService.shared.defaultTerminal()
                        )
                    }
                },
                putBack: { [weak self] in
                    Task {
                        _ = await TrashOriginStore.shared.putBack(urls: [item.url])
                        await MainActor.run {
                            self?.rebuildColumns()
                        }
                    }
                },
                makeAlias: { [weak self] in
                    let destination = item.url.deletingLastPathComponent()
                    Task {
                        _ = await FileOperationService.shared.makeAliases(for: [item.url], in: destination)
                        await MainActor.run {
                            self?.rebuildColumns()
                        }
                    }
                },
                showOriginal: { [weak self] in
                    if let targetURL = item.resolvedTargetURL ?? FileOperationService.shared.resolveTarget(for: item.url) {
                        let parentURL = targetURL.deletingLastPathComponent().standardizedFileURL
                        self?.onNavigate?(parentURL)
                    }
                },
                rotateLeft: { [weak self] in
                    Task {
                        await QuickActionService.shared.rotateImage(at: item.url, degrees: 270)
                        await MainActor.run {
                            self?.rebuildColumns()
                        }
                    }
                },
                rotateRight: { [weak self] in
                    Task {
                        await QuickActionService.shared.rotateImage(at: item.url, degrees: 90)
                        await MainActor.run {
                            self?.rebuildColumns()
                        }
                    }
                },
                createPDF: { [weak self] in
                    let dest = item.url.deletingLastPathComponent()
                    Task {
                        _ = try? await QuickActionService.shared.createPDF(from: [item.url], in: dest)
                        await MainActor.run {
                            self?.rebuildColumns()
                        }
                    }
                },
                runShortcut: { [weak self] shortcutName in
                    Task {
                        _ = try? await QuickActionService.shared.runShortcut(name: shortcutName, inputFile: item.url)
                        await MainActor.run {
                            self?.rebuildColumns()
                        }
                    }
                },
                toggleTag: { [weak self] color in
                    Task {
                        try? await TagService.shared.toggleColorTag(color, for: [item.url])
                        await MainActor.run {
                            self?.rebuildColumns()
                        }
                    }
                },
                clearTags: { [weak self] in
                    Task {
                        try? await TagService.shared.clearAllTags(for: [item.url])
                        await MainActor.run {
                            self?.rebuildColumns()
                        }
                    }
                },
                copyChecksum: {
                    guard !item.isDirectory else { return }
                    Task {
                        if let hash = try? await ChecksumService.shared.computeSHA256(url: item.url) {
                            await MainActor.run {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(hash, forType: .string)
                            }
                        }
                    }
                },
                findDuplicates: { [weak self] in
                    let folder = item.isDirectory ? item.url : (self?.directoryContents.url ?? item.url.deletingLastPathComponent())
                    self?.onFindDuplicates?(folder)
                },
                gitStage: isGit ? { [weak self] in
                    Task {
                        try? await GitService.shared.stage(urls: [item.url], at: targetFolder)
                        await MainActor.run { self?.rebuildColumns() }
                    }
                } : nil,
                gitUnstage: isGit ? { [weak self] in
                    Task {
                        try? await GitService.shared.unstage(urls: [item.url], at: targetFolder)
                        await MainActor.run { self?.rebuildColumns() }
                    }
                } : nil,
                gitDiscard: isGit ? { [weak self] in
                    Task {
                        try? await GitService.shared.discardChanges(for: item.url, at: targetFolder)
                        await MainActor.run { self?.rebuildColumns() }
                    }
                } : nil,
                gitDiff: isGit ? { [weak self] in
                    self?.onGitDiff?(item.url)
                } : nil,
                gitCommit: isGit ? { [weak self] in
                    self?.onGitCommit?()
                } : nil,
                unlockVault: { [weak self] in
                    self?.onUnlockVault?(item.url)
                },
                lockVault: { [weak self] in
                    self?.onLockVault?(item.url)
                },
                createVault: { [weak self] in
                    self?.onCreateVault?()
                }
            )
        )
    }
}

// MARK: - Key Handling TableView

private final class ColumnTableView: NSTableView {
    var onKeyDown: ((NSEvent) -> Bool)?
    var onMenu: ((NSEvent, Int) -> NSMenu?)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if onKeyDown?(event) != true {
            super.keyDown(with: event)
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        let row = self.row(at: point)
        if row >= 0 {
            if !selectedRowIndexes.contains(row) {
                selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            }
            return onMenu?(event, row)
        }
        return super.menu(for: event)
    }
}

// MARK: - Preview Column View

private struct ColumnFilePreviewView: View {
    let item: FileItem
    var onQuickLook: () -> Void
    var onOpen: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if let icon = item.iconImage {
                    Image(nsImage: icon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 80, height: 80)
                        .shadow(color: .black.opacity(0.12), radius: 4, x: 0, y: 2)
                        .padding(.top, 20)
                } else {
                    Image(systemName: item.isDirectory ? "folder" : "doc")
                        .font(.system(size: 64))
                        .foregroundStyle(.secondary)
                        .padding(.top, 20)
                }

                Text(item.name)
                    .font(.system(size: 13, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
                    .padding(.horizontal, 10)

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    previewRow(label: "Kind", value: item.kind)
                    if let size = item.size, size > 0 {
                        previewRow(label: "Size", value: ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                    }
                    if let modDate = item.modificationDate {
                        previewRow(label: "Modified", value: modDate.formatted(date: .abbreviated, time: .shortened))
                    }
                }
                .font(.system(size: 11))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)

                Spacer()

                HStack(spacing: 10) {
                    Button("Quick Look", action: onQuickLook)
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                    Button("Open", action: onOpen)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
                .padding(.bottom, 16)
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
    }

    private func previewRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 55, alignment: .trailing)
            Text(value)
                .lineLimit(2)
        }
    }
}
