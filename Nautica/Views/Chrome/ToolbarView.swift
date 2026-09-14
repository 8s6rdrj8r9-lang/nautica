import AppKit
import SwiftUI

private extension NSToolbarItem.Identifier {
    static let back = NSToolbarItem.Identifier("Nautica.Back")
    static let forward = NSToolbarItem.Identifier("Nautica.Forward")
    static let pathBar = NSToolbarItem.Identifier("Nautica.PathBar")
    static let splitLayout = NSToolbarItem.Identifier("Nautica.SplitLayout")
    static let viewMode = NSToolbarItem.Identifier("Nautica.ViewMode")
    static let iconSize = NSToolbarItem.Identifier("Nautica.IconSize")
    static let hiddenFiles = NSToolbarItem.Identifier("Nautica.HiddenFiles")
}

/// Main-window toolbar: back/forward, path bar, split layout, view mode, icon size, hidden files.
///
/// Owns the `NSToolbar` and acts as its delegate. Browser state is mirrored into
/// the properties below by `BrowserView`, which then calls `refresh()` to
/// re-apply it to the toolbar items.
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

    // MARK: - Mirrored state (set before calling refresh())

    var canGoBack = false
    var canGoForward = false
    var currentURL = FileManager.default.homeURL
    var splitLayout: SplitLayout = .single
    var viewMode: ViewMode = .icon
    var iconSize: CGFloat = 64
    var showsHiddenFiles = false

    let toolbar: NSToolbar

    private weak var backItem: NSToolbarItem?
    private weak var forwardItem: NSToolbarItem?
    private weak var pathBarHostingView: NSHostingView<PathBarView>?
    private weak var splitLayoutControl: NSSegmentedControl?
    private weak var viewModeControl: NSSegmentedControl?
    private weak var iconSizeSlider: NSSlider?
    private weak var hiddenFilesButton: NSButton?

    override init() {
        toolbar = NSToolbar(identifier: "NauticaBrowserToolbar")
        super.init()
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
    }

    /// Re-applies the mirrored state to the toolbar items. Cheap; call freely.
    func refresh() {
        backItem?.isEnabled = canGoBack
        forwardItem?.isEnabled = canGoForward
        pathBarHostingView?.rootView = makePathBarView()
        splitLayoutControl?.selectedSegment = splitLayout.rawValue
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
        if let layout = SplitLayout(rawValue: sender.selectedSegment) {
            onSplitLayoutChanged?(layout)
        }
    }

    @objc private func viewModeAction(_ sender: NSSegmentedControl) {
        onViewModeChanged?(sender.selectedSegment == 0 ? .icon : .list)
    }

    @objc private func iconSizeAction(_ sender: NSSlider) {
        onIconSizeChanged?(CGFloat(sender.doubleValue))
    }

    @objc private func hiddenFilesAction() { onToggleHiddenFiles?() }
}

// MARK: - NSToolbarDelegate

extension BrowserToolbar: NSToolbarDelegate {
    func toolbar(_ toolbar: NSToolbar,
                 itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        switch itemIdentifier {
        case .back, .forward:
            let isBack = itemIdentifier == .back
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = isBack ? "Back" : "Forward"
            item.image = NSImage(named: isBack ? NSImage.goBackTemplateName : NSImage.goForwardTemplateName)
            item.target = self
            item.action = isBack ? #selector(backAction) : #selector(forwardAction)
            item.isEnabled = isBack ? canGoBack : canGoForward
            if isBack { backItem = item } else { forwardItem = item }
            return item

        case .pathBar:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Path"
            let hostingView = NSHostingView(rootView: makePathBarView())
            item.view = hostingView
            // Flexible width: grows to fill the space between the arrows and
            // the trailing controls.
            item.minSize = NSSize(width: 160, height: 32)
            item.maxSize = NSSize(width: 4000, height: 32)
            pathBarHostingView = hostingView
            return item

        case .splitLayout:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Panes"
            let control = NSSegmentedControl(
                images: [
                    NSImage(systemSymbolName: "rectangle", accessibilityDescription: "Single Pane")!,
                    NSImage(systemSymbolName: "rectangle.split.2x1", accessibilityDescription: "2 Columns")!,
                    NSImage(systemSymbolName: "rectangle.split.1x2", accessibilityDescription: "2 Rows")!,
                    NSImage(systemSymbolName: "rectangle.split.2x2", accessibilityDescription: "4 Grid")!,
                    NSImage(systemSymbolName: "rectangle.split.3x1", accessibilityDescription: "4 Columns")!,
                    NSImage(systemSymbolName: "rectangle.grid.1x2", accessibilityDescription: "4 Rows")!,
                ],
                trackingMode: .selectOne,
                target: self,
                action: #selector(splitLayoutAction(_:))
            )
            control.selectedSegment = splitLayout.rawValue
            item.view = control
            splitLayoutControl = control
            return item

        case .viewMode:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "View Mode"
            let control = NSSegmentedControl(
                images: [
                    NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: "Icon View")!,
                    NSImage(systemSymbolName: "list.bullet", accessibilityDescription: "List View")!,
                ],
                trackingMode: .selectOne,
                target: self,
                action: #selector(viewModeAction(_:))
            )
            control.selectedSegment = viewMode == .icon ? 0 : 1
            item.view = control
            viewModeControl = control
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

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.back, .forward, .pathBar, .splitLayout, .viewMode, .iconSize, .hiddenFiles]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarAllowedItemIdentifiers(toolbar)
    }
}

// MARK: - NSToolbarItemValidation

extension BrowserToolbar: NSToolbarItemValidation {
    /// Keeps back/forward in sync when AppKit revalidates the toolbar on its own.
    func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
        switch item.itemIdentifier {
        case .back: return canGoBack
        case .forward: return canGoForward
        default: return true
        }
    }
}
