import AppKit
import SwiftUI

/// Hosts the icon or list view, forwards selection events from AppKit to the
/// `SelectionModel`, and handles keyboard navigation.
///
/// Prompt 3 hosts the NSCollectionView icon grid; Prompt 4 hosts the
/// NSTableView list. Only one is visible at a time, per `viewMode`.
struct FileViewCoordinator: NSViewRepresentable {
    @AppStorage(Constants.listFontSizeKey) private var listFontSize: Double = 13
    @AppStorage(Constants.listIconSizeKey) private var listIconSize: Double = 16
    @AppStorage(Constants.listSpacingKey) private var listSpacing: Double = 2
    @AppStorage(Constants.iconFontSizeKey) private var iconFontSize: Double = 11
    @AppStorage(Constants.iconSpacingKey) private var iconSpacing: Double = 10

    var directoryContents: DirectoryContents
    var selectionModel: SelectionModel
    var viewMode: ViewMode
    /// Columns per row in icon view; used for grid-aware arrow navigation.
    /// Overridden at runtime by the icon view's measured column count.
    var iconColumnCount: Int = 1
    /// Space-bar handler (Quick Look, Prompt 9).
    var onQuickLook: (() -> Void)?
    /// Icon size in points (32–256); driven by the toolbar slider (Prompt 7).
    var iconSize: CGFloat = 64
    /// Double-click on a folder in either file view.
    var onNavigate: ((URL) -> Void)?
    var onNavigateToParent: (() -> Void)?
    var onOpenSelection: (() -> Void)?
    var onCopyPath: (() -> Void)?
    var onToggleHiddenFiles: (() -> Void)?
    var onGoToFolder: (() -> Void)?
    /// Return/Enter pressed with a single selection (rename, Prompt 10).
    var onRenameRequest: (() -> Void)?
    /// Context-menu actions routed to BrowserView.
    var onCopySelection: (() -> Void)?
    var onTrashSelection: (() -> Void)?
    var onDuplicate: (() -> Void)?
    var onMakeAlias: (() -> Void)?
    var onShowOriginal: (() -> Void)?
    var onPaste: (() -> Void)?
    var onMoveHere: (() -> Void)?
    var onNewFolderWithSelection: (() -> Void)?
    var onUndo: (() -> Void)?
    var onRedo: (() -> Void)?
    var onGetInfo: (() -> Void)?
    var onPutBack: (() -> Void)?
    var onConnectToServer: (() -> Void)?
    var onCompressWithPassword: (([URL]) -> Void)?
    var onFindDuplicates: ((URL) -> Void)?
    var onGitDiff: ((URL) -> Void)?
    var onGitCommit: (() -> Void)?
    var onQuickCopyToOtherPane: (() -> Void)?
    var onQuickMoveToOtherPane: (() -> Void)?
    var onCyclePane: (() -> Void)?
    var onToggleTag: ((TagColor) -> Void)?
    var onClearTags: (() -> Void)?
    var setViewMode: ((ViewMode) -> Void)?
    var isFocused: Bool = false
    var onMouseEnter: (() -> Void)?

    func makeNSView(context: Context) -> KeyHandlingView {
        let container = KeyHandlingView()
        container.onKeyDown = { [weak coordinator = context.coordinator] event in
            coordinator?.handleKeyDown(event) ?? false
        }
        container.onMouseEnter = { [weak coordinator = context.coordinator] in
            coordinator?.parent.onMouseEnter?()
        }

        let iconController = IconViewController(
            directoryContents: directoryContents,
            selectionModel: selectionModel
        )
        iconController.keyDownHandler = { [weak coordinator = context.coordinator] event in
            coordinator?.handleKeyDown(event) ?? false
        }
        iconController.onNavigate = onNavigate
        iconController.onRenameRequest = { [weak coordinator = context.coordinator] in
            coordinator?.parent.onRenameRequest?()
        }
        iconController.onCopySelection = { [weak coordinator = context.coordinator] in
            coordinator?.parent.onCopySelection?()
        }
        iconController.onTrashSelection = { [weak coordinator = context.coordinator] in
            coordinator?.parent.onTrashSelection?()
        }
        iconController.onCompressWithPassword = { [weak coordinator = context.coordinator] urls in
            coordinator?.parent.onCompressWithPassword?(urls)
        }
        iconController.onFindDuplicates = { [weak coordinator = context.coordinator] url in
            coordinator?.parent.onFindDuplicates?(url)
        }
        iconController.onGitDiff = { [weak coordinator = context.coordinator] url in
            coordinator?.parent.onGitDiff?(url)
        }
        iconController.onGitCommit = { [weak coordinator = context.coordinator] in
            coordinator?.parent.onGitCommit?()
        }
        iconController.onColumnCountChanged = { [weak coordinator = context.coordinator] count in
            coordinator?.liveColumnCount = count
        }
        context.coordinator.iconViewController = iconController

        let iconView = iconController.view
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.isHidden = viewMode != .icon

        let listController = ListViewController(
            directoryContents: directoryContents,
            selectionModel: selectionModel
        )
        listController.keyDownHandler = { [weak coordinator = context.coordinator] event in
            coordinator?.handleKeyDown(event) ?? false
        }
        listController.onNavigate = onNavigate
        listController.onRenameRequest = { [weak coordinator = context.coordinator] in
            coordinator?.parent.onRenameRequest?()
        }
        listController.onCopySelection = { [weak coordinator = context.coordinator] in
            coordinator?.parent.onCopySelection?()
        }
        listController.onTrashSelection = { [weak coordinator = context.coordinator] in
            coordinator?.parent.onTrashSelection?()
        }
        listController.onCompressWithPassword = { [weak coordinator = context.coordinator] urls in
            coordinator?.parent.onCompressWithPassword?(urls)
        }
        listController.onFindDuplicates = { [weak coordinator = context.coordinator] url in
            coordinator?.parent.onFindDuplicates?(url)
        }
        listController.onGitDiff = { [weak coordinator = context.coordinator] url in
            coordinator?.parent.onGitDiff?(url)
        }
        listController.onGitCommit = { [weak coordinator = context.coordinator] in
            coordinator?.parent.onGitCommit?()
        }
        context.coordinator.listViewController = listController

        let listView = listController.view
        listView.translatesAutoresizingMaskIntoConstraints = false
        listView.isHidden = viewMode != .list

        let columnController = ColumnViewController(
            directoryContents: directoryContents,
            selectionModel: selectionModel
        )
        columnController.keyDownHandler = { [weak coordinator = context.coordinator] event in
            coordinator?.handleKeyDown(event) ?? false
        }
        columnController.onNavigate = onNavigate
        columnController.onQuickLook = onQuickLook
        columnController.onRenameRequest = { [weak coordinator = context.coordinator] in
            coordinator?.parent.onRenameRequest?()
        }
        columnController.onCopySelection = { [weak coordinator = context.coordinator] in
            coordinator?.parent.onCopySelection?()
        }
        columnController.onTrashSelection = { [weak coordinator = context.coordinator] in
            coordinator?.parent.onTrashSelection?()
        }
        columnController.onCompressWithPassword = { [weak coordinator = context.coordinator] urls in
            coordinator?.parent.onCompressWithPassword?(urls)
        }
        columnController.onFindDuplicates = { [weak coordinator = context.coordinator] url in
            coordinator?.parent.onFindDuplicates?(url)
        }
        columnController.onGitDiff = { [weak coordinator = context.coordinator] url in
            coordinator?.parent.onGitDiff?(url)
        }
        columnController.onGitCommit = { [weak coordinator = context.coordinator] in
            coordinator?.parent.onGitCommit?()
        }
        context.coordinator.columnViewController = columnController

        let columnView = columnController.view
        columnView.translatesAutoresizingMaskIntoConstraints = false
        columnView.isHidden = viewMode != .column

        let galleryController = GalleryViewController(
            directoryContents: directoryContents,
            selectionModel: selectionModel
        )
        galleryController.keyDownHandler = { [weak coordinator = context.coordinator] event in
            coordinator?.handleKeyDown(event) ?? false
        }
        galleryController.onNavigate = onNavigate
        galleryController.onQuickLook = onQuickLook
        galleryController.onRenameRequest = { [weak coordinator = context.coordinator] in
            coordinator?.parent.onRenameRequest?()
        }
        galleryController.onCopySelection = { [weak coordinator = context.coordinator] in
            coordinator?.parent.onCopySelection?()
        }
        galleryController.onTrashSelection = { [weak coordinator = context.coordinator] in
            coordinator?.parent.onTrashSelection?()
        }
        galleryController.onGetInfo = { [weak coordinator = context.coordinator] in
            coordinator?.parent.onGetInfo?()
        }
        galleryController.onCompressWithPassword = { [weak coordinator = context.coordinator] urls in
            coordinator?.parent.onCompressWithPassword?(urls)
        }
        galleryController.onFindDuplicates = { [weak coordinator = context.coordinator] url in
            coordinator?.parent.onFindDuplicates?(url)
        }
        galleryController.onGitDiff = { [weak coordinator = context.coordinator] url in
            coordinator?.parent.onGitDiff?(url)
        }
        galleryController.onGitCommit = { [weak coordinator = context.coordinator] in
            coordinator?.parent.onGitCommit?()
        }
        context.coordinator.galleryViewController = galleryController

        let galleryView = galleryController.view
        galleryView.translatesAutoresizingMaskIntoConstraints = false
        galleryView.isHidden = viewMode != .gallery

        container.addSubview(iconView)
        container.addSubview(listView)
        container.addSubview(columnView)
        container.addSubview(galleryView)
        NSLayoutConstraint.activate([
            iconView.topAnchor.constraint(equalTo: container.topAnchor),
            iconView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            iconView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            iconView.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            listView.topAnchor.constraint(equalTo: container.topAnchor),
            listView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            listView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            listView.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            columnView.topAnchor.constraint(equalTo: container.topAnchor),
            columnView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            columnView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            columnView.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            galleryView.topAnchor.constraint(equalTo: container.topAnchor),
            galleryView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            galleryView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            galleryView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        return container
    }

    func updateNSView(_ nsView: KeyHandlingView, context: Context) {
        context.coordinator.parent = self
        guard let iconController = context.coordinator.iconViewController,
              let listController = context.coordinator.listViewController,
              let columnController = context.coordinator.columnViewController,
              let galleryController = context.coordinator.galleryViewController else { return }
        iconController.onNavigate = onNavigate
        iconController.onGitDiff = onGitDiff
        iconController.onGitCommit = onGitCommit
        listController.onNavigate = onNavigate
        listController.onGitDiff = onGitDiff
        listController.onGitCommit = onGitCommit
        columnController.onNavigate = onNavigate
        columnController.onQuickLook = onQuickLook
        columnController.onGitDiff = onGitDiff
        columnController.onGitCommit = onGitCommit
        galleryController.onNavigate = onNavigate
        galleryController.onQuickLook = onQuickLook
        galleryController.onGitDiff = onGitDiff
        galleryController.onGitCommit = onGitCommit

        let isIcon = viewMode == .icon
        let isList = viewMode == .list
        let isColumn = viewMode == .column
        let isGallery = viewMode == .gallery

        iconController.view.isHidden = !isIcon
        listController.view.isHidden = !isList
        columnController.view.isHidden = !isColumn
        galleryController.view.isHidden = !isGallery

        if isIcon {
            iconController.applyAppearance(fontSize: iconFontSize, iconSize: iconSize, spacing: iconSpacing)
            iconController.applyItems(directoryContents.items)
        } else if isList {
            listController.applyAppearance(fontSize: listFontSize, iconSize: listIconSize, spacing: listSpacing)
            listController.applyItems(directoryContents.items)
            listController.applySelection()
        } else if isColumn {
            columnController.reloadHierarchy()
        } else if isGallery {
            galleryController.reloadData()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    @MainActor
    final class Coordinator {
        var parent: FileViewCoordinator
        /// Hosted icon grid (Prompt 3); also supplies the live column count.
        var iconViewController: IconViewController?
        /// Hosted list view (Prompt 4).
        var listViewController: ListViewController?
        /// Hosted column view (Miller columns).
        var columnViewController: ColumnViewController?
        /// Hosted gallery view (Finder ⌘4 style).
        var galleryViewController: GalleryViewController?
        /// Column count measured by the icon grid's layout.
        var liveColumnCount: Int?
        private var typeAhead = TypeAheadBuffer()

        init(parent: FileViewCoordinator) {
            self.parent = parent
        }

        /// Returns true if the event was consumed.
        func handleKeyDown(_ event: NSEvent) -> Bool {
            let items = parent.directoryContents.items
            let selection = parent.selectionModel
            let extending = event.modifierFlags.contains(.shift)
            // List mode is a single column; icon mode uses the measured grid.
            let columnCount = parent.viewMode == .list
                ? 1
                : (liveColumnCount ?? parent.iconColumnCount)
            // Page Up/Down step, approximating one screenful of items.
            let pageDelta = max(10, columnCount * 3)

            let hasCommand = event.modifierFlags.contains(.command)
            let hasShift = event.modifierFlags.contains(.shift)
            let hasOption = event.modifierFlags.contains(.option)
            let hasControl = event.modifierFlags.contains(.control)

            // Command shortcuts
            if hasCommand, let char = event.charactersIgnoringModifiers?.lowercased() {
                switch char {
                case "a":
                    if hasShift {
                        selection.deselectAll()
                    } else {
                        selection.selectAll(in: items)
                    }
                    return true
                case "o":
                    parent.onOpenSelection?()
                    return true
                case "g" where hasShift:
                    parent.onGoToFolder?()
                    return true
                case "c":
                    if hasOption {
                        parent.onCopyPath?()
                    } else {
                        parent.onCopySelection?()
                    }
                    return true
                case "v":
                    if hasOption {
                        parent.onMoveHere?()
                    } else {
                        parent.onPaste?()
                    }
                    return true
                case "d":
                    parent.onDuplicate?()
                    return true
                case "l":
                    parent.onMakeAlias?()
                    return true
                case "r" where !hasOption:
                    parent.onShowOriginal?()
                    return true
                case "n" where hasControl:
                    parent.onNewFolderWithSelection?()
                    return true
                case "z":
                    if hasShift {
                        parent.onRedo?()
                    } else {
                        parent.onUndo?()
                    }
                    return true
                case "i":
                    parent.onGetInfo?()
                    return true
                case "1":
                    parent.setViewMode?(.icon)
                    return true
                case "2":
                    parent.setViewMode?(.list)
                    return true
                case "3":
                    parent.setViewMode?(.column)
                    return true
                case "4":
                    parent.setViewMode?(.gallery)
                    return true
                case "." where hasShift:
                    parent.onToggleHiddenFiles?()
                    return true
                case "k" where !hasShift:
                    parent.onConnectToServer?()
                    return true
                case "k" where hasShift:
                    parent.onNavigate?(URL(fileURLWithPath: "/Volumes"))
                    return true
                default:
                    break
                }
            }

            guard let scalars = event.charactersIgnoringModifiers?.unicodeScalars,
                  scalars.count == 1, let scalar = scalars.first else { return false }

            if hasControl && !hasCommand && !hasOption {
                if let char = event.charactersIgnoringModifiers?.first, let num = Int(String(char)) {
                    if num >= 1 && num <= 7, let color = TagColor.from(shortcutNumber: num) {
                        parent.onToggleTag?(color)
                        return true
                    } else if num == 0 {
                        parent.onClearTags?()
                        return true
                    }
                }
            }

            switch scalar.value {
            case UInt32(NSUpArrowFunctionKey):
                if hasCommand {
                    parent.onNavigateToParent?()
                } else {
                    selection.moveSelection(by: -columnCount, in: items, extending: extending)
                }
            case UInt32(NSDownArrowFunctionKey):
                if hasCommand {
                    parent.onOpenSelection?()
                } else {
                    selection.moveSelection(by: columnCount, in: items, extending: extending)
                }
            case UInt32(NSLeftArrowFunctionKey):
                if parent.viewMode == .gallery {
                    galleryViewController?.selectPrevious()
                } else if parent.viewMode == .list, let listVC = listViewController, listVC.handleLeftArrow() {
                    // Handled hierarchical collapse / jump to parent
                } else {
                    selection.moveSelection(by: -1, in: items, extending: extending)
                }
            case UInt32(NSRightArrowFunctionKey):
                if parent.viewMode == .gallery {
                    galleryViewController?.selectNext()
                } else if parent.viewMode == .list, let listVC = listViewController, listVC.handleRightArrow() {
                    // Handled hierarchical expand / jump to child
                } else {
                    selection.moveSelection(by: 1, in: items, extending: extending)
                }
            case UInt32(NSHomeFunctionKey):
                selection.selectBoundary(first: true, in: items, extending: extending)
            case UInt32(NSEndFunctionKey):
                selection.selectBoundary(first: false, in: items, extending: extending)
            case UInt32(NSPageUpFunctionKey):
                selection.moveSelection(by: -pageDelta, in: items, extending: extending)
            case UInt32(NSPageDownFunctionKey):
                selection.moveSelection(by: pageDelta, in: items, extending: extending)
            case 0x7F, 0x08, UInt32(NSDeleteFunctionKey): // Backspace / Delete
                if hasCommand {
                    let selected = items.filter { selection.isSelected($0.id) }
                    if let first = selected.first, TrashOriginStore.shared.isInsideTrash(first.url) {
                        parent.onPutBack?()
                    } else {
                        parent.onTrashSelection?()
                    }
                }
            case 0x09: // Tab
                if !hasCommand && !hasOption && !hasControl, parent.onCyclePane != nil {
                    parent.onCyclePane?()
                    return true
                }
            case UInt32(NSF5FunctionKey):
                parent.onQuickCopyToOtherPane?()
                return true
            case UInt32(NSF6FunctionKey):
                parent.onQuickMoveToOtherPane?()
                return true
            case 0x1B: // Esc: deselect all
                selection.deselectAll()
            case 0x0D, 0x03: // Return/Enter: rename (Prompt 10)
                parent.onRenameRequest?()
            case 0x20: // Space: Quick Look (Prompt 9)
                parent.onQuickLook?()
            default:
                guard let character = event.characters?.first,
                      character.isLetter || character.isNumber else { return false }
                typeAhead.append(character)
                if let match = typeAhead.match(in: items) {
                    selection.select(match.id, modifierFlags: [])
                }
            }
            return true
        }
    }
}

/// NSView subclass that forwards key events and hover/mouse-enter to SwiftUI-friendly closures.
final class KeyHandlingView: NSView {
    var onKeyDown: ((NSEvent) -> Bool)?
    var onMouseEnter: (() -> Void)?
    private var trackingArea: NSTrackingArea?

    override var acceptsFirstResponder: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        onMouseEnter?()
    }

    override func keyDown(with event: NSEvent) {
        if onKeyDown?(event) != true {
            super.keyDown(with: event)
        }
    }
}
