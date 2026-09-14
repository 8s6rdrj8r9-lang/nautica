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
    /// Return/Enter pressed with a single selection (rename, Prompt 10).
    var onRenameRequest: (() -> Void)?
    /// Context-menu actions routed to BrowserView.
    var onCopySelection: (() -> Void)?
    var onTrashSelection: (() -> Void)?

    func makeNSView(context: Context) -> KeyHandlingView {
        let container = KeyHandlingView()
        container.onKeyDown = { [weak coordinator = context.coordinator] event in
            coordinator?.handleKeyDown(event) ?? false
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
        context.coordinator.listViewController = listController

        let listView = listController.view
        listView.translatesAutoresizingMaskIntoConstraints = false
        listView.isHidden = viewMode != .list

        container.addSubview(iconView)
        container.addSubview(listView)
        NSLayoutConstraint.activate([
            iconView.topAnchor.constraint(equalTo: container.topAnchor),
            iconView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            iconView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            iconView.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            listView.topAnchor.constraint(equalTo: container.topAnchor),
            listView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            listView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            listView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        return container
    }

    func updateNSView(_ nsView: KeyHandlingView, context: Context) {
        context.coordinator.parent = self
        guard let iconController = context.coordinator.iconViewController,
              let listController = context.coordinator.listViewController else { return }
        iconController.onNavigate = onNavigate
        listController.onNavigate = onNavigate
        let isIconMode = viewMode == .icon
        iconController.view.isHidden = !isIconMode
        listController.view.isHidden = isIconMode
        if isIconMode {
            iconController.applyAppearance(fontSize: iconFontSize, iconSize: iconSize, spacing: iconSpacing)
            iconController.applyItems(directoryContents.items)
        } else {
            listController.applyAppearance(fontSize: listFontSize, iconSize: listIconSize, spacing: listSpacing)
            listController.applyItems(directoryContents.items)
            listController.applySelection()
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

            // Cmd+A: select all. Cmd+Shift+A: deselect all.
            if event.modifierFlags.contains(.command),
               event.charactersIgnoringModifiers?.lowercased() == "a" {
                if extending {
                    selection.deselectAll()
                } else {
                    selection.selectAll(in: items)
                }
                return true
            }

            guard let scalars = event.charactersIgnoringModifiers?.unicodeScalars,
                  scalars.count == 1, let scalar = scalars.first else { return false }

            switch scalar.value {
            case UInt32(NSUpArrowFunctionKey):
                selection.moveSelection(by: -columnCount, in: items, extending: extending)
            case UInt32(NSDownArrowFunctionKey):
                selection.moveSelection(by: columnCount, in: items, extending: extending)
            case UInt32(NSLeftArrowFunctionKey):
                selection.moveSelection(by: -1, in: items, extending: extending)
            case UInt32(NSRightArrowFunctionKey):
                selection.moveSelection(by: 1, in: items, extending: extending)
            case UInt32(NSHomeFunctionKey):
                selection.selectBoundary(first: true, in: items, extending: extending)
            case UInt32(NSEndFunctionKey):
                selection.selectBoundary(first: false, in: items, extending: extending)
            case UInt32(NSPageUpFunctionKey):
                selection.moveSelection(by: -pageDelta, in: items, extending: extending)
            case UInt32(NSPageDownFunctionKey):
                selection.moveSelection(by: pageDelta, in: items, extending: extending)
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

/// NSView subclass that forwards key events to a SwiftUI-friendly closure.
final class KeyHandlingView: NSView {
    var onKeyDown: ((NSEvent) -> Bool)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if onKeyDown?(event) != true {
            super.keyDown(with: event)
        }
    }
}
