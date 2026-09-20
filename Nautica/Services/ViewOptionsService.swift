import AppKit
import SwiftUI

/// Service coordinating the "Show View Options" HUD panel (⌘J).
@MainActor
final class ViewOptionsService: ObservableObject {
    static let shared = ViewOptionsService()

    private var panelController: ViewOptionsPanelController?

    // Observable states representing current folder & view parameters
    @Published var folderURL: URL = FileManager.default.homeURL
    @Published var viewMode: ViewMode = .list
    @Published var iconSize: CGFloat = 64
    @Published var fontSize: CGFloat = 13
    @Published var groupBy: GroupByCriterion = .none
    @Published var labelOnBottom: Bool = true
    @Published var showItemInfo: Bool = false

    // Column visibility toggles
    @Published var showDateModified: Bool = true
    @Published var showDateCreated: Bool = false
    @Published var showSize: Bool = true
    @Published var showKind: Bool = true
    @Published var showTags: Bool = true

    // Callbacks to synchronize changes back to the active browser tab
    var onStateChanged: (() -> Void)?
    var onUseAsDefaults: (() -> Void)?

    private init() {}

    var isVisible: Bool {
        panelController?.window?.isVisible == true
    }

    /// Toggles the View Options HUD panel (⌘J).
    func toggle(
        folderURL: URL,
        viewMode: ViewMode,
        iconSize: CGFloat,
        fontSize: CGFloat,
        groupBy: GroupByCriterion,
        onStateChanged: @escaping () -> Void,
        onUseAsDefaults: @escaping () -> Void
    ) {
        if isVisible {
            close()
        } else {
            show(
                folderURL: folderURL,
                viewMode: viewMode,
                iconSize: iconSize,
                fontSize: fontSize,
                groupBy: groupBy,
                onStateChanged: onStateChanged,
                onUseAsDefaults: onUseAsDefaults
            )
        }
    }

    func show(
        folderURL: URL,
        viewMode: ViewMode,
        iconSize: CGFloat,
        fontSize: CGFloat,
        groupBy: GroupByCriterion,
        onStateChanged: @escaping () -> Void,
        onUseAsDefaults: @escaping () -> Void
    ) {
        self.folderURL = folderURL
        self.viewMode = viewMode
        self.iconSize = iconSize
        self.fontSize = fontSize
        self.groupBy = groupBy
        self.onStateChanged = onStateChanged
        self.onUseAsDefaults = onUseAsDefaults

        if panelController == nil {
            let hostView = ViewOptionsHostView(service: self)
            panelController = ViewOptionsPanelController(rootView: AnyView(hostView))
        } else {
            let hostView = ViewOptionsHostView(service: self)
            panelController?.updateRootView(AnyView(hostView))
        }

        if let window = panelController?.window {
            if let keyWin = NSApp.keyWindow {
                let keyFrame = keyWin.frame
                let panelX = keyFrame.maxX - 300
                let panelY = keyFrame.maxY - 440
                window.setFrameOrigin(NSPoint(x: max(20, panelX), y: max(40, panelY)))
            } else {
                window.center()
            }
            window.orderFront(nil)
        }
    }

    func sync(folderURL: URL, viewMode: ViewMode, iconSize: CGFloat, groupBy: GroupByCriterion) {
        guard isVisible else { return }
        self.folderURL = folderURL
        self.viewMode = viewMode
        self.iconSize = iconSize
        self.groupBy = groupBy
    }

    func close() {
        panelController?.close()
        panelController = nil
    }

    func panelDidClose() {
        panelController = nil
    }
}

/// SwiftUI wrapper binding ViewOptionsService properties to ViewOptionsView.
private struct ViewOptionsHostView: View {
    @ObservedObject var service: ViewOptionsService

    var body: some View {
        ViewOptionsView(
            folderURL: service.folderURL,
            viewMode: Binding(
                get: { service.viewMode },
                set: {
                    service.viewMode = $0
                    service.onStateChanged?()
                }
            ),
            iconSize: Binding(
                get: { service.iconSize },
                set: {
                    service.iconSize = $0
                    service.onStateChanged?()
                }
            ),
            fontSize: Binding(
                get: { service.fontSize },
                set: {
                    service.fontSize = $0
                    service.onStateChanged?()
                }
            ),
            groupBy: Binding(
                get: { service.groupBy },
                set: {
                    service.groupBy = $0
                    service.onStateChanged?()
                }
            ),
            labelOnBottom: Binding(
                get: { service.labelOnBottom },
                set: {
                    service.labelOnBottom = $0
                    service.onStateChanged?()
                }
            ),
            showItemInfo: Binding(
                get: { service.showItemInfo },
                set: {
                    service.showItemInfo = $0
                    service.onStateChanged?()
                }
            ),
            showDateModified: Binding(
                get: { service.showDateModified },
                set: {
                    service.showDateModified = $0
                    service.onStateChanged?()
                }
            ),
            showDateCreated: Binding(
                get: { service.showDateCreated },
                set: {
                    service.showDateCreated = $0
                    service.onStateChanged?()
                }
            ),
            showSize: Binding(
                get: { service.showSize },
                set: {
                    service.showSize = $0
                    service.onStateChanged?()
                }
            ),
            showKind: Binding(
                get: { service.showKind },
                set: {
                    service.showKind = $0
                    service.onStateChanged?()
                }
            ),
            showTags: Binding(
                get: { service.showTags },
                set: {
                    service.showTags = $0
                    service.onStateChanged?()
                }
            ),
            onUseAsDefaults: {
                service.onUseAsDefaults?()
            }
        )
    }
}
